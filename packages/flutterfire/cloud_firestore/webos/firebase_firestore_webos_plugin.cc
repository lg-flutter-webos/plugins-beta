#include "firebase_firestore_webos_plugin.h"
#include "firebase_firestore_webos/firebase_firestore_webos_plugin.h"
#include "firebase_core_webos/firebase_app_holder.h"

#include <firebase/app.h>
#include <firebase/firestore.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace firebase_firestore_webos {

using namespace firebase::firestore;
using firebase::Future;

// Forward declaration
MapFieldValue EncodableMapToMapFieldValue(const flutter::EncodableMap& map);

struct TransactionSession {
  TransactionSession(
      std::string app_name_in,
      std::string database_id_in,
      int64_t transaction_id_in,
      firebase::firestore::Firestore* firestore_in)
      : app_name(std::move(app_name_in)),
        database_id(std::move(database_id_in)),
        transaction_id(transaction_id_in),
        firestore(firestore_in) {}

  std::string app_name;
  std::string database_id;
  int64_t transaction_id;
  firebase::firestore::Firestore* firestore;
  firebase::firestore::Transaction* current_transaction = nullptr;
  std::mutex mutex;
  std::condition_variable condition;
  bool response_received = false;
  PigeonTransactionResult result_type = PigeonTransactionResult::failure;
  std::optional<flutter::EncodableList> updates;
};

namespace {

constexpr const char kTransactionMergeSentinel[] = "__merge__";
constexpr const char kTransactionMergeFieldsSentinel[] = "__mergeFields__";

std::string TransactionSessionKey(
    const std::string& app_name,
    const std::string& database_id,
    int64_t transaction_id) {
  return app_name + "|" + database_id + "|" + std::to_string(transaction_id);
}

bool IsStringValue(const flutter::EncodableValue& value, const std::string& expected) {
  return std::holds_alternative<std::string>(value) && std::get<std::string>(value) == expected;
}

flutter::EncodableMap StripTransactionSentinels(const flutter::EncodableMap& data) {
  flutter::EncodableMap stripped;
  for (const auto& pair : data) {
    if (IsStringValue(pair.first, kTransactionMergeSentinel) ||
        IsStringValue(pair.first, kTransactionMergeFieldsSentinel)) {
      continue;
    }
    stripped.insert(pair);
  }
  return stripped;
}

std::vector<FieldPath> MergeFieldPathsFromList(const flutter::EncodableList& fields) {
  std::vector<FieldPath> merge_fields;
  for (const auto& field_value : fields) {
    if (!std::holds_alternative<flutter::EncodableList>(field_value)) {
      continue;
    }
    std::vector<std::string> path_segments;
    for (const auto& segment_value : std::get<flutter::EncodableList>(field_value)) {
      if (std::holds_alternative<std::string>(segment_value)) {
        path_segments.push_back(std::get<std::string>(segment_value));
      }
    }
    if (!path_segments.empty()) {
      merge_fields.emplace_back(path_segments);
    }
  }
  return merge_fields;
}

SetOptions SetOptionsFromTransactionMap(const flutter::EncodableMap& data) {
  auto merge_fields_it = data.find(flutter::EncodableValue(kTransactionMergeFieldsSentinel));
  if (merge_fields_it != data.end() &&
      std::holds_alternative<flutter::EncodableList>(merge_fields_it->second)) {
    const auto merge_fields = MergeFieldPathsFromList(
        std::get<flutter::EncodableList>(merge_fields_it->second));
    if (!merge_fields.empty()) {
      return SetOptions::MergeFieldPaths(merge_fields);
    }
  }

  auto merge_it = data.find(flutter::EncodableValue(kTransactionMergeSentinel));
  if (merge_it != data.end() && std::holds_alternative<bool>(merge_it->second) &&
      std::get<bool>(merge_it->second)) {
    return SetOptions::Merge();
  }

  return SetOptions();
}

template <typename WriteTarget>
bool ApplyTransactionWrite(
    WriteTarget& write_target,
    const firebase::firestore::DocumentReference& doc_ref,
    const PigeonTransactionUpdate& update,
    std::string* error_message) {
  const std::string& op = update.type();
  if (op == "delete") {
    write_target.Delete(doc_ref);
    return true;
  }

  if (op == "set") {
    if (!update.data()) {
      if (error_message) {
        *error_message = "Transaction set operation is missing data.";
      }
      return false;
    }

    const auto stripped = StripTransactionSentinels(*update.data());
    auto map_data = EncodableMapToMapFieldValue(stripped);
    write_target.Set(doc_ref, map_data, SetOptionsFromTransactionMap(*update.data()));
    return true;
  }

  if (op == "update") {
    if (!update.data()) {
      if (error_message) {
        *error_message = "Transaction update operation is missing data.";
      }
      return false;
    }
    write_target.Update(doc_ref, EncodableMapToMapFieldValue(*update.data()));
    return true;
  }

  if (error_message) {
    *error_message = "Unsupported transaction operation: " + op;
  }
  return false;
}

}  // namespace

// Helper functions for converting between C++ and Dart types

Source StringToSource(const std::string& source_str) {
  if (source_str == "server") return Source::kServer;
  if (source_str == "cache") return Source::kCache;
  return Source::kDefault;
}

flutter::EncodableValue FieldValueToEncodable(const FieldValue& value);

flutter::EncodableMap MapFieldValueToEncodableMap(const MapFieldValue& map) {
  flutter::EncodableMap result;
  for (const auto& pair : map) {
    result[flutter::EncodableValue(pair.first)] = FieldValueToEncodable(pair.second);
  }
  return result;
}

flutter::EncodableValue FieldValueToEncodable(const FieldValue& value) {
  switch (value.type()) {
    case FieldValue::Type::kNull:
      return flutter::EncodableValue();
    case FieldValue::Type::kBoolean:
      return flutter::EncodableValue(value.boolean_value());
    case FieldValue::Type::kInteger:
      return flutter::EncodableValue(value.integer_value());
    case FieldValue::Type::kDouble:
      return flutter::EncodableValue(value.double_value());
    case FieldValue::Type::kTimestamp: {
      auto ts = value.timestamp_value();
      flutter::EncodableMap timestamp;
      timestamp[flutter::EncodableValue("__datatype__")] =
          flutter::EncodableValue("timestamp");
      timestamp[flutter::EncodableValue("seconds")] =
          flutter::EncodableValue(static_cast<int64_t>(ts.seconds()));
      timestamp[flutter::EncodableValue("nanoseconds")] =
          flutter::EncodableValue(static_cast<int64_t>(ts.nanoseconds()));
      return flutter::EncodableValue(timestamp);
    }
    case FieldValue::Type::kString:
      return flutter::EncodableValue(value.string_value());
    case FieldValue::Type::kBlob: {
      const auto& blob = value.blob_value();
      return flutter::EncodableValue(std::vector<uint8_t>(blob, blob + value.blob_size()));
    }
    case FieldValue::Type::kReference:
      return flutter::EncodableValue(value.reference_value().path());
    case FieldValue::Type::kGeoPoint: {
      flutter::EncodableMap geo;
      geo[flutter::EncodableValue("latitude")] = flutter::EncodableValue(value.geo_point_value().latitude());
      geo[flutter::EncodableValue("longitude")] = flutter::EncodableValue(value.geo_point_value().longitude());
      return flutter::EncodableValue(geo);
    }
    case FieldValue::Type::kArray: {
      flutter::EncodableList list;
      for (const auto& item : value.array_value()) {
        list.push_back(FieldValueToEncodable(item));
      }
      return flutter::EncodableValue(list);
    }
    case FieldValue::Type::kMap:
      return flutter::EncodableValue(MapFieldValueToEncodableMap(value.map_value()));
    default:
      return flutter::EncodableValue();
  }
}

FieldValue EncodableToFieldValue(const flutter::EncodableValue& value);

MapFieldValue EncodableMapToMapFieldValue(const flutter::EncodableMap& map) {
  MapFieldValue result;
  for (const auto& pair : map) {
    if (std::holds_alternative<std::string>(pair.first)) {
      result[std::get<std::string>(pair.first)] = EncodableToFieldValue(pair.second);
    }
  }
  return result;
}

FieldValue EncodableToFieldValue(const flutter::EncodableValue& value) {
  if (std::holds_alternative<std::monostate>(value)) {
    return FieldValue::Null();
  } else if (std::holds_alternative<bool>(value)) {
    return FieldValue::Boolean(std::get<bool>(value));
  } else if (std::holds_alternative<int32_t>(value)) {
    return FieldValue::Integer(std::get<int32_t>(value));
  } else if (std::holds_alternative<int64_t>(value)) {
    return FieldValue::Integer(std::get<int64_t>(value));
  } else if (std::holds_alternative<double>(value)) {
    return FieldValue::Double(std::get<double>(value));
  } else if (std::holds_alternative<std::string>(value)) {
    return FieldValue::String(std::get<std::string>(value));
  } else if (std::holds_alternative<std::vector<uint8_t>>(value)) {
    const auto& blob = std::get<std::vector<uint8_t>>(value);
    return FieldValue::Blob(blob.data(), blob.size());
  } else if (std::holds_alternative<flutter::EncodableList>(value)) {
    std::vector<FieldValue> list;
    for (const auto& item : std::get<flutter::EncodableList>(value)) {
      list.push_back(EncodableToFieldValue(item));
    }
    return FieldValue::Array(list);
  } else if (std::holds_alternative<flutter::EncodableMap>(value)) {
    const auto& map = std::get<flutter::EncodableMap>(value);
    auto type_tag_it = map.find(flutter::EncodableValue("__datatype__"));
    if (type_tag_it != map.end() && std::holds_alternative<std::string>(type_tag_it->second)) {
      const std::string type_tag = std::get<std::string>(type_tag_it->second);
      if (type_tag == "timestamp") {
        auto millis_it = map.find(flutter::EncodableValue("milliseconds"));
        if (millis_it != map.end()) {
          int64_t millis = 0;
          if (std::holds_alternative<int64_t>(millis_it->second)) {
            millis = std::get<int64_t>(millis_it->second);
          } else if (std::holds_alternative<int32_t>(millis_it->second)) {
            millis = std::get<int32_t>(millis_it->second);
          } else if (std::holds_alternative<double>(millis_it->second)) {
            millis = static_cast<int64_t>(std::get<double>(millis_it->second));
          }
          const int64_t seconds = millis / 1000;
          const int32_t nanos = static_cast<int32_t>((millis % 1000) * 1000000);
          return FieldValue::Timestamp(firebase::Timestamp(seconds, nanos));
        }
      }
    }

    auto sentinel_it = map.find(flutter::EncodableValue("__fieldValueOp__"));
    if (sentinel_it != map.end() && std::holds_alternative<std::string>(sentinel_it->second)) {
      const std::string op = std::get<std::string>(sentinel_it->second);
      auto operand_it = map.find(flutter::EncodableValue("operand"));

      if (op == "delete") {
        return FieldValue::Delete();
      }
      if (op == "serverTimestamp") {
        return FieldValue::ServerTimestamp();
      }
      if (op == "incrementInteger") {
        int64_t by = 0;
        if (operand_it != map.end()) {
          if (std::holds_alternative<int64_t>(operand_it->second)) {
            by = std::get<int64_t>(operand_it->second);
          } else if (std::holds_alternative<int32_t>(operand_it->second)) {
            by = std::get<int32_t>(operand_it->second);
          }
        }
        return FieldValue::Increment(by);
      }
      if (op == "incrementDouble") {
        double by = 0.0;
        if (operand_it != map.end()) {
          if (std::holds_alternative<double>(operand_it->second)) {
            by = std::get<double>(operand_it->second);
          } else if (std::holds_alternative<int64_t>(operand_it->second)) {
            by = static_cast<double>(std::get<int64_t>(operand_it->second));
          } else if (std::holds_alternative<int32_t>(operand_it->second)) {
            by = static_cast<double>(std::get<int32_t>(operand_it->second));
          }
        }
        return FieldValue::Increment(by);
      }
      if ((op == "arrayUnion" || op == "arrayRemove") && operand_it != map.end() &&
          std::holds_alternative<flutter::EncodableList>(operand_it->second)) {
        std::vector<FieldValue> elements;
        for (const auto& element : std::get<flutter::EncodableList>(operand_it->second)) {
          elements.push_back(EncodableToFieldValue(element));
        }
        if (op == "arrayUnion") {
          return FieldValue::ArrayUnion(elements);
        }
        return FieldValue::ArrayRemove(elements);
      }
    }

    auto lat_it = map.find(flutter::EncodableValue("latitude"));
    auto lon_it = map.find(flutter::EncodableValue("longitude"));
    if (lat_it != map.end() && lon_it != map.end() && map.size() == 2) {
      double lat = 0.0;
      double lon = 0.0;
      if (std::holds_alternative<double>(lat_it->second)) {
        lat = std::get<double>(lat_it->second);
      } else if (std::holds_alternative<int32_t>(lat_it->second)) {
        lat = std::get<int32_t>(lat_it->second);
      } else if (std::holds_alternative<int64_t>(lat_it->second)) {
        lat = std::get<int64_t>(lat_it->second);
      }
      if (std::holds_alternative<double>(lon_it->second)) {
        lon = std::get<double>(lon_it->second);
      } else if (std::holds_alternative<int32_t>(lon_it->second)) {
        lon = std::get<int32_t>(lon_it->second);
      } else if (std::holds_alternative<int64_t>(lon_it->second)) {
        lon = std::get<int64_t>(lon_it->second);
      }
      return FieldValue::GeoPoint(GeoPoint(lat, lon));
    }
    return FieldValue::Map(EncodableMapToMapFieldValue(map));
  }
  return FieldValue::Null();
}

bool IsDocumentIdField(const std::string& field) {
  return field == "__name__";
}

std::vector<FieldValue> EncodableListToFieldValues(const flutter::EncodableList& list) {
  std::vector<FieldValue> values;
  values.reserve(list.size());
  for (const auto& item : list) {
    values.push_back(EncodableToFieldValue(item));
  }
  return values;
}

Query ApplyWhereFilter(Query query, const PigeonQueryFilter& filter) {
  const std::string& field = filter.field();
  const bool is_doc_id = IsDocumentIdField(field);
  const std::string& op = filter.op();
  const FieldValue value = filter.value() ? EncodableToFieldValue(*filter.value()) : FieldValue::Null();

  auto apply_unary = [&](auto string_overload, auto field_path_overload) {
    if (is_doc_id) {
      return field_path_overload(FieldPath::DocumentId(), value);
    }
    return string_overload(field, value);
  };

  if (op == "==") {
    return apply_unary(
        [&](const std::string& f, const FieldValue& v) { return query.WhereEqualTo(f, v); },
        [&](const FieldPath& f, const FieldValue& v) { return query.WhereEqualTo(f, v); });
  }
  if (op == "!=") {
    return apply_unary(
        [&](const std::string& f, const FieldValue& v) { return query.WhereNotEqualTo(f, v); },
        [&](const FieldPath& f, const FieldValue& v) { return query.WhereNotEqualTo(f, v); });
  }
  if (op == "<") {
    return apply_unary(
        [&](const std::string& f, const FieldValue& v) { return query.WhereLessThan(f, v); },
        [&](const FieldPath& f, const FieldValue& v) { return query.WhereLessThan(f, v); });
  }
  if (op == "<=") {
    return apply_unary(
        [&](const std::string& f, const FieldValue& v) { return query.WhereLessThanOrEqualTo(f, v); },
        [&](const FieldPath& f, const FieldValue& v) { return query.WhereLessThanOrEqualTo(f, v); });
  }
  if (op == ">") {
    return apply_unary(
        [&](const std::string& f, const FieldValue& v) { return query.WhereGreaterThan(f, v); },
        [&](const FieldPath& f, const FieldValue& v) { return query.WhereGreaterThan(f, v); });
  }
  if (op == ">=") {
    return apply_unary(
        [&](const std::string& f, const FieldValue& v) { return query.WhereGreaterThanOrEqualTo(f, v); },
        [&](const FieldPath& f, const FieldValue& v) { return query.WhereGreaterThanOrEqualTo(f, v); });
  }
  if (op == "array-contains") {
    return apply_unary(
        [&](const std::string& f, const FieldValue& v) { return query.WhereArrayContains(f, v); },
        [&](const FieldPath& f, const FieldValue& v) { return query.WhereArrayContains(f, v); });
  }

  std::vector<FieldValue> list_values;
  if (filter.value() && std::holds_alternative<flutter::EncodableList>(*filter.value())) {
    list_values = EncodableListToFieldValues(std::get<flutter::EncodableList>(*filter.value()));
  }

  if (op == "array-contains-any") {
    if (is_doc_id) {
      return query.WhereArrayContainsAny(FieldPath::DocumentId(), list_values);
    }
    return query.WhereArrayContainsAny(field, list_values);
  }
  if (op == "in") {
    if (is_doc_id) {
      return query.WhereIn(FieldPath::DocumentId(), list_values);
    }
    return query.WhereIn(field, list_values);
  }
  if (op == "not-in") {
    if (is_doc_id) {
      return query.WhereNotIn(FieldPath::DocumentId(), list_values);
    }
    return query.WhereNotIn(field, list_values);
  }

  return query;
}

Query ApplyQueryParameters(Query query, const PigeonQueryParameters& parameters) {
  if (parameters.where()) {
    for (const auto& filter_value : *parameters.where()) {
      const auto* custom = std::get_if<flutter::CustomEncodableValue>(&filter_value);
      if (!custom || custom->type() != typeid(PigeonQueryFilter)) {
        continue;
      }
      const auto& filter = std::any_cast<const PigeonQueryFilter&>(*custom);
      query = ApplyWhereFilter(query, filter);
    }
  }

  if (parameters.order_by()) {
    for (const auto& order_value : *parameters.order_by()) {
      const auto* custom = std::get_if<flutter::CustomEncodableValue>(&order_value);
      if (!custom || custom->type() != typeid(PigeonQueryOrder)) {
        continue;
      }
      const auto& order = std::any_cast<const PigeonQueryOrder&>(*custom);
      const firebase::firestore::Query::Direction direction = order.descending() ? firebase::firestore::Query::Direction::kDescending : firebase::firestore::Query::Direction::kAscending;
      if (IsDocumentIdField(order.field())) {
        query = query.OrderBy(FieldPath::DocumentId(), direction);
      } else {
        query = query.OrderBy(order.field(), direction);
      }
    }
  }

  if (parameters.limit()) {
    query = query.Limit(static_cast<int32_t>(*parameters.limit()));
  }
  if (parameters.limit_to_last()) {
    query = query.LimitToLast(static_cast<int32_t>(*parameters.limit_to_last()));
  }

  if (parameters.start_at()) {
    query = query.StartAt(EncodableListToFieldValues(*parameters.start_at()));
  }
  if (parameters.start_after()) {
    query = query.StartAfter(EncodableListToFieldValues(*parameters.start_after()));
  }
  if (parameters.end_at()) {
    query = query.EndAt(EncodableListToFieldValues(*parameters.end_at()));
  }
  if (parameters.end_before()) {
    query = query.EndBefore(EncodableListToFieldValues(*parameters.end_before()));
  }

  return query;
}

void FirebaseFirestoreWebosPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrar* registrar) {
  auto plugin = std::make_unique<FirebaseFirestoreWebosPlugin>();
  plugin->messenger_ = registrar->messenger();
  FirestoreHostApi::SetUp(registrar->messenger(), plugin.get());
  plugin->InitializeSnapshotEventChannels(registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

FirebaseFirestoreWebosPlugin::FirebaseFirestoreWebosPlugin() {}

FirebaseFirestoreWebosPlugin::~FirebaseFirestoreWebosPlugin() {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& pair : listeners_) {
    pair.second.Remove();
  }
  listeners_.clear();
}

Firestore* FirebaseFirestoreWebosPlugin::GetFirestore(
    const std::string& app_name,
    const std::string& database_id) {
  std::lock_guard<std::mutex> lock(mutex_);
  
  const std::string key = app_name + "_" + database_id;
  
  auto it = firestore_instances_.find(key);
  if (it != firestore_instances_.end()) {
    return it->second;
  }

  firebase::App* app = FirebaseAppHolder::GetApp(app_name);
  if (!app) return nullptr;

  Firestore* firestore = nullptr;
  if (database_id == "(default)") {
    firestore = Firestore::GetInstance(app);
  } else {
    firestore = Firestore::GetInstance(app, database_id.c_str());
  }

  if (firestore) {
    firestore_instances_[key] = firestore;
  }

  return firestore;
}

PigeonDocumentSnapshot FirebaseFirestoreWebosPlugin::DocumentSnapshotToPigeon(
    const DocumentSnapshot& snapshot) {
  PigeonSnapshotMetadata metadata(
      snapshot.metadata().has_pending_writes(),
      snapshot.metadata().is_from_cache());

  PigeonDocumentSnapshot pigeon_snapshot(
      snapshot.reference().path(),
      nullptr,
      metadata,
      snapshot.exists());
  
  if (snapshot.exists()) {
    pigeon_snapshot.set_data(MapFieldValueToEncodableMap(snapshot.GetData()));
  }
  
  return pigeon_snapshot;
}

// Host API Implementations
void FirebaseFirestoreWebosPlugin::InitializeFirestore(
    const std::string& app_name,
    const std::string& database_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (firestore) {
    result(std::nullopt);
  } else {
    result(FlutterError("initialization-error", "Failed to initialize Firestore"));
  }
}

void FirebaseFirestoreWebosPlugin::SetSettings(
    const std::string& app_name,
    const std::string& database_id,
    const PigeonFirestoreSettings& settings,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  Settings cpp_settings;
  cpp_settings.set_host(settings.host());
  cpp_settings.set_ssl_enabled(settings.ssl_enabled());
  cpp_settings.set_persistence_enabled(settings.persistence_enabled());
  cpp_settings.set_cache_size_bytes(settings.cache_size_bytes());

  firestore->set_settings(cpp_settings);
  result(std::nullopt);
}

void FirebaseFirestoreWebosPlugin::EnableNetwork(
    const std::string& app_name,
    const std::string& database_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto future = firestore->EnableNetwork();
  future.OnCompletion([result](const Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("network-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::DisableNetwork(
    const std::string& app_name,
    const std::string& database_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto future = firestore->DisableNetwork();
  future.OnCompletion([result](const Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("network-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::ClearPersistence(
    const std::string& app_name,
    const std::string& database_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto future = firestore->ClearPersistence();
  future.OnCompletion([result](const Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("clear-persistence-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::Terminate(
    const std::string& app_name,
    const std::string& database_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto future = firestore->Terminate();
  future.OnCompletion([this, app_name, database_id, result](const firebase::Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      std::lock_guard<std::mutex> lock(mutex_);
      const std::string key = app_name + "_" + database_id;
      firestore_instances_.erase(key);
      result(std::nullopt);
    } else {
      result(FlutterError("terminate-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::WaitForPendingWrites(
    const std::string& app_name,
    const std::string& database_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto future = firestore->WaitForPendingWrites();
  future.OnCompletion([result](const Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("pending-writes-error", completed_future.error_message()));
    }
  });
}

// Document operations
void FirebaseFirestoreWebosPlugin::DocumentGet(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    const PigeonGetOptions& options,
    std::function<void(ErrorOr<PigeonDocumentSnapshot> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto doc_ref = firestore->Document(path);
  auto source = StringToSource(options.source());
  auto future = doc_ref.Get(source);

  future.OnCompletion([result](const Future<DocumentSnapshot>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(DocumentSnapshotToPigeon(*completed_future.result()));
    } else {
      result(FlutterError("document-get-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::DocumentSet(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    const flutter::EncodableMap& data,
    const PigeonSetOptions& options,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto doc_ref = firestore->Document(path);
  auto map_value = EncodableMapToMapFieldValue(data);

  SetOptions set_options;
  if (options.merge_fields() != nullptr) {
    const auto merge_fields = MergeFieldPathsFromList(*options.merge_fields());
    if (!merge_fields.empty()) {
      set_options = SetOptions::MergeFieldPaths(merge_fields);
    } else if (options.merge()) {
      set_options = SetOptions::Merge();
    }
  } else if (options.merge()) {
    set_options = SetOptions::Merge();
  }

  auto future = doc_ref.Set(map_value, set_options);
  future.OnCompletion([result](const Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("document-set-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::DocumentUpdate(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    const flutter::EncodableMap& data,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto doc_ref = firestore->Document(path);
  auto map_value = EncodableMapToMapFieldValue(data);

  auto future = doc_ref.Update(map_value);
  future.OnCompletion([result](const Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("document-update-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::DocumentDelete(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto doc_ref = firestore->Document(path);
  auto future = doc_ref.Delete();

  future.OnCompletion([result](const Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("document-delete-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::DocumentAddSnapshotListener(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    bool include_metadata_changes,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto doc_ref = firestore->Document(path);
  
  int64_t listener_id;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    listener_id = next_listener_id_++;
  }

  MetadataChanges metadata_changes = include_metadata_changes ? 
      MetadataChanges::kInclude : MetadataChanges::kExclude;

  auto registration = doc_ref.AddSnapshotListener(
      metadata_changes,
      [this, app_name, database_id, listener_id](const DocumentSnapshot& snapshot, Error error, const std::string& error_msg) {
        if (error == Error::kErrorOk) {
          SendDocumentSnapshotToDart(app_name, database_id, listener_id, snapshot, nullptr);
        } else {
          SendDocumentSnapshotToDart(app_name, database_id, listener_id, snapshot, &error_msg);
        }
      });

  {
    std::lock_guard<std::mutex> lock(mutex_);
    listeners_[listener_id] = registration;
  }

  result(listener_id);
}

// Query operations - simplified implementation
void FirebaseFirestoreWebosPlugin::QueryGet(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    bool is_collection_group,
    const PigeonQueryParameters& parameters,
    const PigeonGetOptions& options,
    std::function<void(ErrorOr<PigeonQuerySnapshot> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  Query query = is_collection_group ? 
      firestore->CollectionGroup(path) : 
      firestore->Collection(path);
  query = ApplyQueryParameters(query, parameters);

  auto source = StringToSource(options.source());
  auto future = query.Get(source);

  future.OnCompletion([result](const firebase::Future<QuerySnapshot>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      const auto& snapshot = *completed_future.result();
      
      PigeonSnapshotMetadata metadata(
          snapshot.metadata().has_pending_writes(),
          snapshot.metadata().is_from_cache());

      flutter::EncodableList documents;
      flutter::EncodableList document_changes;

      for (const auto& doc : snapshot.documents()) {
        auto pigeon_doc = DocumentSnapshotToPigeon(doc);
        documents.push_back(flutter::CustomEncodableValue(pigeon_doc));
      }

      for (const auto& change : snapshot.DocumentChanges()) {
        PigeonDocumentChangeType change_type;
        switch (change.type()) {
          case DocumentChange::Type::kAdded:    change_type = PigeonDocumentChangeType::added; break;
          case DocumentChange::Type::kModified: change_type = PigeonDocumentChangeType::modified; break;
          case DocumentChange::Type::kRemoved:  change_type = PigeonDocumentChangeType::removed; break;
          default:                              change_type = PigeonDocumentChangeType::modified; break;
        }
        auto pigeon_doc_change = PigeonDocumentChange(
            change_type,
            DocumentSnapshotToPigeon(change.document()),
            static_cast<int64_t>(change.old_index()),
            static_cast<int64_t>(change.new_index()));
        document_changes.push_back(flutter::CustomEncodableValue(pigeon_doc_change));
      }

      PigeonQuerySnapshot pigeon_snapshot(documents, document_changes, metadata);
      result(pigeon_snapshot);
    } else {
      result(FlutterError("query-get-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::QueryAddSnapshotListener(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    bool is_collection_group,
    const PigeonQueryParameters& parameters,
    bool include_metadata_changes,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  Query query = is_collection_group ? 
      firestore->CollectionGroup(path) : 
      firestore->Collection(path);
  query = ApplyQueryParameters(query, parameters);

  int64_t listener_id;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    listener_id = next_listener_id_++;
  }

  MetadataChanges metadata_changes = include_metadata_changes ? 
      MetadataChanges::kInclude : MetadataChanges::kExclude;

  auto registration = query.AddSnapshotListener(
      metadata_changes,
      [this, app_name, database_id, listener_id](const QuerySnapshot& snapshot, Error error, const std::string& error_msg) {
        if (error == Error::kErrorOk) {
          SendQuerySnapshotToDart(app_name, database_id, listener_id, snapshot, nullptr);
        } else {
          SendQuerySnapshotToDart(app_name, database_id, listener_id, snapshot, &error_msg);
        }
      });

  {
    std::lock_guard<std::mutex> lock(mutex_);
    listeners_[listener_id] = registration;
  }

  result(listener_id);
}

void FirebaseFirestoreWebosPlugin::QueryCount(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    bool is_collection_group,
    const PigeonQueryParameters& parameters,
    std::function<void(ErrorOr<PigeonAggregateQuerySnapshot> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  Query query = is_collection_group ?
      firestore->CollectionGroup(path) :
      firestore->Collection(path);
  query = ApplyQueryParameters(query, parameters);

  auto aggregate_query = query.Count();
  auto future = aggregate_query.Get(AggregateSource::kServer);
  future.OnCompletion([result](const Future<AggregateQuerySnapshot>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      const auto& snapshot = *completed_future.result();
      result(PigeonAggregateQuerySnapshot(snapshot.count()));
    } else {
      result(FlutterError("query-count-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::QueryAggregate(
    const std::string& app_name,
    const std::string& database_id,
    const std::string& path,
    bool is_collection_group,
    const PigeonQueryParameters& parameters,
    const flutter::EncodableList& aggregate_types,
    std::function<void(ErrorOr<PigeonAggregateQuerySnapshot> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  Query query = is_collection_group ?
      firestore->CollectionGroup(path) :
      firestore->Collection(path);
  query = ApplyQueryParameters(query, parameters);

  // The Firebase C++ SDK only supports Count() for aggregate queries.
  // Sum and average are not available in the C++ SDK.
  // We execute Count() and return the result; sum/average fields will be
  // empty lists on the Dart side, which is the correct behavior since the
  // SDK does not support them.
  auto aggregate_query = query.Count();
  auto future = aggregate_query.Get(AggregateSource::kServer);
  future.OnCompletion([result](const Future<AggregateQuerySnapshot>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      const auto& snapshot = *completed_future.result();
      // Return only count; sum and average remain null (unsupported by SDK)
      result(PigeonAggregateQuerySnapshot(snapshot.count()));
    } else {
      result(FlutterError("query-aggregate-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::UseEmulator(
    const std::string& app_name, const std::string& database_id,
    const std::string& host, int64_t port,
    std::function<void(std::optional<FlutterError> reply)> result) {
  // Firebase C++ SDK does not support UseEmulator on Firestore class.
  // It is only available on firebase::auth::Auth and firebase::storage::Storage.
  // We acknowledge the request but cannot fulfill it with the current SDK.
  result(FlutterError("unsupported", "UseEmulator is not supported in the C++ SDK version used by this platform. The emulator host/port must be configured via the FirebaseOptions at app initialization."));
}

void FirebaseFirestoreWebosPlugin::SetLoggingEnabled(
    const std::string& app_name, const std::string& database_id, bool enabled,
    std::function<void(std::optional<FlutterError> reply)> result) {
  // The Firebase C++ SDK does not support setLoggingEnabled on a per-instance basis.
  // Logging is controlled globally via firebase::LogLevel.
  // We apply the setting globally as a best-effort approximation.
  Firestore::set_log_level(enabled ? firebase::kLogLevelInfo : firebase::kLogLevelError);
  result(std::nullopt);
}

void FirebaseFirestoreWebosPlugin::RemoveSnapshotListener(
    const std::string& app_name,
    const std::string& database_id,
    int64_t listener_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  std::lock_guard<std::mutex> lock(mutex_);
  
  auto it = listeners_.find(listener_id);
  if (it != listeners_.end()) {
    it->second.Remove();
    listeners_.erase(it);
    
    // Remove any pending events for this listener from the buffers.
    // This prevents stale events from being delivered after the listener
    // has been removed.
    {
      std::lock_guard<std::mutex> event_lock(event_mutex_);
      auto remove_by_listener = [listener_id](const flutter::EncodableValue& value) {
        const auto* map = std::get_if<flutter::EncodableMap>(&value);
        if (!map) return false;
        auto it = map->find(flutter::EncodableValue("listenerId"));
        if (it == map->end()) return false;
        const auto* id = std::get_if<int64_t>(&it->second);
        return id && *id == listener_id;
      };
      document_snapshot_pending_events_.erase(
          std::remove_if(document_snapshot_pending_events_.begin(),
                         document_snapshot_pending_events_.end(),
                         remove_by_listener),
          document_snapshot_pending_events_.end());
      query_snapshot_pending_events_.erase(
          std::remove_if(query_snapshot_pending_events_.begin(),
                         query_snapshot_pending_events_.end(),
                         remove_by_listener),
          query_snapshot_pending_events_.end());
    }
    
    result(std::nullopt);
  } else {
    result(FlutterError("listener-not-found", "Listener not found"));
  }
}

// Batch operations
void FirebaseFirestoreWebosPlugin::BatchCommit(
    const std::string& app_name,
    const std::string& database_id,
    const flutter::EncodableList& writes,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  WriteBatch batch = firestore->batch();

  // Process each write operation
  for (const auto& write_value : writes) {
    const auto* custom = std::get_if<flutter::CustomEncodableValue>(&write_value);
    if (!custom || custom->type() != typeid(PigeonTransactionUpdate)) continue;
    const auto& update = std::any_cast<const PigeonTransactionUpdate&>(*custom);

    auto doc_ref = firestore->Document(update.path());
    std::string error_message;
    if (!ApplyTransactionWrite(batch, doc_ref, update, &error_message)) {
      result(FlutterError("batch-commit-error", error_message));
      return;
    }
  }

  auto future = batch.Commit();
  future.OnCompletion([result](const Future<void>& completed_future) {
    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("batch-commit-error", completed_future.error_message()));
    }
  });
}

// Transaction operations
void FirebaseFirestoreWebosPlugin::RunTransaction(
    const std::string& app_name,
    const std::string& database_id,
    int64_t transaction_id,
    int64_t max_attempts,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto* firestore = GetFirestore(app_name, database_id);
  if (!firestore) {
    result(FlutterError("not-initialized", "Firestore not initialized"));
    return;
  }

  auto session = std::make_shared<TransactionSession>(app_name, database_id, transaction_id, firestore);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    transaction_sessions_[TransactionSessionKey(app_name, database_id, transaction_id)] = session;
  }

  TransactionOptions transaction_options;
  transaction_options.set_max_attempts(static_cast<int32_t>(max_attempts));

  auto future = firestore->RunTransaction(
      transaction_options,
      [this, session, firestore](Transaction& transaction, std::string& error_message) -> Error {
        {
          std::lock_guard<std::mutex> session_lock(session->mutex);
          session->current_transaction = &transaction;
          session->response_received = false;
          session->result_type = PigeonTransactionResult::failure;
          session->updates.reset();
        }

        FirestoreFlutterApi flutter_api(messenger_);
        std::mutex dispatch_mutex;
        std::condition_variable dispatch_cv;
        bool dispatch_done = false;
        bool dispatch_success = false;
        std::string dispatch_error_message;

        flutter_api.OnTransactionCallback(
            session->app_name,
            session->database_id,
            session->transaction_id,
            [&]() {
              std::lock_guard<std::mutex> dispatch_lock(dispatch_mutex);
              dispatch_done = true;
              dispatch_success = true;
              dispatch_cv.notify_one();
            },
            [&](const FlutterError& error) {
              std::lock_guard<std::mutex> dispatch_lock(dispatch_mutex);
              dispatch_done = true;
              dispatch_success = false;
              dispatch_error_message = error.message();
              dispatch_cv.notify_one();
            });

        {
          std::unique_lock<std::mutex> dispatch_lock(dispatch_mutex);
          if (!dispatch_cv.wait_for(dispatch_lock, std::chrono::seconds(60), [&]() { return dispatch_done; })) {
            error_message = "Transaction callback timed out waiting for Dart side.";
            std::lock_guard<std::mutex> session_lock(session->mutex);
            session->current_transaction = nullptr;
            return Error::kErrorCancelled;
          }
        }

        if (!dispatch_success) {
          error_message = dispatch_error_message.empty()
              ? "Transaction callback delivery failed."
              : dispatch_error_message;
          std::lock_guard<std::mutex> session_lock(session->mutex);
          session->current_transaction = nullptr;
          return Error::kErrorCancelled;
        }

        std::optional<flutter::EncodableList> updates;
        PigeonTransactionResult result_type = PigeonTransactionResult::failure;
        {
          std::unique_lock<std::mutex> session_lock(session->mutex);
          if (!session->condition.wait_for(session_lock, std::chrono::seconds(60), [&]() { return session->response_received; })) {
            error_message = "Transaction timed out waiting for Dart side to complete.";
            return Error::kErrorCancelled;
          }
          result_type = session->result_type;
          updates = session->updates;
          session->current_transaction = nullptr;
        }

        if (result_type != PigeonTransactionResult::success) {
          error_message = "Transaction failed on Dart side.";
          return Error::kErrorCancelled;
        }

        if (updates.has_value()) {
          for (const auto& update_value : *updates) {
            const auto* custom = std::get_if<flutter::CustomEncodableValue>(&update_value);
            if (!custom || custom->type() != typeid(PigeonTransactionUpdate)) {
              error_message = "Invalid transaction update payload.";
              return Error::kErrorInvalidArgument;
            }

            const auto& update = std::any_cast<const PigeonTransactionUpdate&>(*custom);
            std::string write_error;
            auto doc_ref = firestore->Document(update.path());
            if (!ApplyTransactionWrite(transaction, doc_ref, update, &write_error)) {
              error_message = write_error;
              return Error::kErrorInvalidArgument;
            }
          }
        }

        return Error::kErrorOk;
      });

  future.OnCompletion([this, app_name, database_id, transaction_id, session, result](const Future<void>& completed_future) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      const auto key = TransactionSessionKey(app_name, database_id, transaction_id);
      auto it = transaction_sessions_.find(key);
      if (it != transaction_sessions_.end() && it->second == session) {
        transaction_sessions_.erase(it);
      }
    }

    if (completed_future.error() == Error::kErrorOk) {
      result(std::nullopt);
    } else {
      result(FlutterError("transaction-run-error", completed_future.error_message()));
    }
  });
}

void FirebaseFirestoreWebosPlugin::TransactionGet(
    const std::string& app_name,
    const std::string& database_id,
    int64_t transaction_id,
    const std::string& path,
    std::function<void(ErrorOr<PigeonDocumentSnapshot> reply)> result) {
  std::shared_ptr<TransactionSession> session;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto key = TransactionSessionKey(app_name, database_id, transaction_id);
    auto it = transaction_sessions_.find(key);
    if (it != transaction_sessions_.end()) {
      session = it->second;
    }
  }

  if (!session) {
    result(FlutterError("transaction-not-found", "Transaction session not found"));
    return;
  }

  firebase::firestore::Transaction* transaction = nullptr;
  {
    std::lock_guard<std::mutex> session_lock(session->mutex);
    transaction = session->current_transaction;
  }

  if (!transaction) {
    result(FlutterError("transaction-not-active", "Transaction is not active"));
    return;
  }

  Error error_code = Error::kErrorOk;
  std::string error_message;
  auto document_snapshot = transaction->Get(session->firestore->Document(path), &error_code, &error_message);
  if (error_code == Error::kErrorOk) {
    result(DocumentSnapshotToPigeon(document_snapshot));
  } else {
    result(FlutterError("transaction-get-error", error_message));
  }
}

void FirebaseFirestoreWebosPlugin::TransactionComplete(
    const std::string& app_name,
    const std::string& database_id,
    int64_t transaction_id,
    const PigeonTransactionResult& result_type,
    const flutter::EncodableList* updates,
    std::function<void(std::optional<FlutterError> reply)> result) {
  std::shared_ptr<TransactionSession> session;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto key = TransactionSessionKey(app_name, database_id, transaction_id);
    auto it = transaction_sessions_.find(key);
    if (it != transaction_sessions_.end()) {
      session = it->second;
    }
  }

  if (!session) {
    result(FlutterError("transaction-not-found", "Transaction session not found"));
    return;
  }

  {
    std::lock_guard<std::mutex> session_lock(session->mutex);
    if (session->response_received) {
      result(FlutterError("transaction-already-complete", "Transaction already completed"));
      return;
    }

    session->result_type = result_type;
    if (updates != nullptr) {
      session->updates = *updates;
    } else {
      session->updates.reset();
    }
    session->response_received = true;
  }

  session->condition.notify_one();
  result(std::nullopt);
}

// ---------------------------------------------------------------------------
// Event Channel Implementation (replaces Pigeon FlutterApi callbacks)
// ---------------------------------------------------------------------------

void FirebaseFirestoreWebosPlugin::InitializeSnapshotEventChannels(
    flutter::BinaryMessenger* messenger) {
  // Document snapshot event channel
  {
    const std::string channel_name = "firebase_firestore_webos/document_snapshot_events";
    auto channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        messenger, channel_name, &flutter::StandardMethodCodec::GetInstance(&FirestoreHostApiCodecSerializer::GetInstance()));
    auto handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [&](const flutter::EncodableValue* arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
          document_snapshot_event_sink_ = std::move(events);
          // Flush any pending events that were buffered before the sink was ready.
          // Use a lock to safely access the pending events buffer, since the Firebase
          // C++ SDK callbacks may be invoked from a different thread.
          std::vector<flutter::EncodableValue> pending_events;
          {
            std::lock_guard<std::mutex> lock(event_mutex_);
            pending_events.swap(document_snapshot_pending_events_);
          }
          for (const auto& event : pending_events) {
            document_snapshot_event_sink_->Success(event);
          }
          return nullptr;
        },
        [&](const flutter::EncodableValue* arguments)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
          document_snapshot_event_sink_ = nullptr;
          return nullptr;
        });
    channel->SetStreamHandler(std::move(handler));
    document_snapshot_event_channel_ = std::move(channel);
  }

  // Query snapshot event channel
  {
    const std::string channel_name = "firebase_firestore_webos/query_snapshot_events";
    auto channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        messenger, channel_name, &flutter::StandardMethodCodec::GetInstance(&FirestoreHostApiCodecSerializer::GetInstance()));
    auto handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [&](const flutter::EncodableValue* arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
          query_snapshot_event_sink_ = std::move(events);
          // Flush any pending events that were buffered before the sink was ready.
          // Use a lock to safely access the pending events buffer, since the Firebase
          // C++ SDK callbacks may be invoked from a different thread.
          std::vector<flutter::EncodableValue> pending_events;
          {
            std::lock_guard<std::mutex> lock(event_mutex_);
            pending_events.swap(query_snapshot_pending_events_);
          }
          for (const auto& event : pending_events) {
            query_snapshot_event_sink_->Success(event);
          }
          return nullptr;
        },
        [&](const flutter::EncodableValue* arguments)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
          query_snapshot_event_sink_ = nullptr;
          return nullptr;
        });
    channel->SetStreamHandler(std::move(handler));
    query_snapshot_event_channel_ = std::move(channel);
  }

}

void FirebaseFirestoreWebosPlugin::SendDocumentSnapshotToDart(
    const std::string& app_name,
    const std::string& database_id,
    int64_t listener_id,
    const firebase::firestore::DocumentSnapshot& snapshot,
    const std::string* error) {
  flutter::EncodableMap event_data;
  event_data[flutter::EncodableValue("appName")] = flutter::EncodableValue(app_name);
  event_data[flutter::EncodableValue("databaseId")] = flutter::EncodableValue(database_id);
  event_data[flutter::EncodableValue("listenerId")] = flutter::EncodableValue(listener_id);

  if (error) {
    event_data[flutter::EncodableValue("error")] = flutter::EncodableValue(*error);
    event_data[flutter::EncodableValue("snapshot")] = flutter::EncodableValue();
  } else {
    event_data[flutter::EncodableValue("error")] = flutter::EncodableValue();
    auto pigeon_snapshot = DocumentSnapshotToPigeon(snapshot);
    event_data[flutter::EncodableValue("snapshot")] = flutter::CustomEncodableValue(pigeon_snapshot);
  }

  if (!document_snapshot_event_sink_) {
    // Buffer the event until the Dart side subscribes to the event channel.
    // This prevents the race condition where the initial snapshot fires
    // before the event sink is ready.
    std::lock_guard<std::mutex> lock(event_mutex_);
    document_snapshot_pending_events_.push_back(flutter::EncodableValue(event_data));
    return;
  }

  document_snapshot_event_sink_->Success(flutter::EncodableValue(event_data));
}

void FirebaseFirestoreWebosPlugin::SendQuerySnapshotToDart(
    const std::string& app_name,
    const std::string& database_id,
    int64_t listener_id,
    const firebase::firestore::QuerySnapshot& snapshot,
    const std::string* error) {
  flutter::EncodableMap event_data;
  event_data[flutter::EncodableValue("appName")] = flutter::EncodableValue(app_name);
  event_data[flutter::EncodableValue("databaseId")] = flutter::EncodableValue(database_id);
  event_data[flutter::EncodableValue("listenerId")] = flutter::EncodableValue(listener_id);

  if (error) {
    event_data[flutter::EncodableValue("error")] = flutter::EncodableValue(*error);
    event_data[flutter::EncodableValue("snapshot")] = flutter::EncodableValue();
  } else {
    event_data[flutter::EncodableValue("error")] = flutter::EncodableValue();

    PigeonSnapshotMetadata metadata(
        snapshot.metadata().has_pending_writes(),
        snapshot.metadata().is_from_cache());

    flutter::EncodableList documents;
    flutter::EncodableList document_changes;

    for (const auto& doc : snapshot.documents()) {
      auto pigeon_doc = DocumentSnapshotToPigeon(doc);
      documents.push_back(flutter::CustomEncodableValue(pigeon_doc));
    }

    for (const auto& change : snapshot.DocumentChanges()) {
      PigeonDocumentChangeType change_type;
      switch (change.type()) {
        case DocumentChange::Type::kAdded:    change_type = PigeonDocumentChangeType::added; break;
        case DocumentChange::Type::kModified: change_type = PigeonDocumentChangeType::modified; break;
        case DocumentChange::Type::kRemoved:  change_type = PigeonDocumentChangeType::removed; break;
        default:                              change_type = PigeonDocumentChangeType::modified; break;
      }
      auto pigeon_doc_change = PigeonDocumentChange(
          change_type,
          DocumentSnapshotToPigeon(change.document()),
          static_cast<int64_t>(change.old_index()),
          static_cast<int64_t>(change.new_index()));
      document_changes.push_back(flutter::CustomEncodableValue(pigeon_doc_change));
    }

    PigeonQuerySnapshot pigeon_snapshot(documents, document_changes, metadata);
    event_data[flutter::EncodableValue("snapshot")] = flutter::CustomEncodableValue(pigeon_snapshot);
  }

  if (!query_snapshot_event_sink_) {
    // Buffer the event until the Dart side subscribes to the event channel.
    // This prevents the race condition where the initial snapshot fires
    // before the event sink is ready.
    std::lock_guard<std::mutex> lock(event_mutex_);
    query_snapshot_pending_events_.push_back(flutter::EncodableValue(event_data));
    return;
  }

  query_snapshot_event_sink_->Success(flutter::EncodableValue(event_data));
}

}  // namespace firebase_firestore_webos

// C entry point
void FirebaseFirestoreWebosPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  firebase_firestore_webos::FirebaseFirestoreWebosPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrar>(registrar));
}
