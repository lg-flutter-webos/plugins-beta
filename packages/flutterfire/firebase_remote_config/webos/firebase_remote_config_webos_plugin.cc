#include "firebase_remote_config_webos_plugin.h"
#include <firebase_remote_config_webos/firebase_remote_config_webos_plugin.h>
#include "firebase_core_webos/firebase_app_holder.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler.h>
#include <flutter/standard_method_codec.h>

#include <thread>
#include <chrono>
#include <algorithm>

namespace firebase_remote_config_webos {

using namespace firebase::remote_config;

namespace {

class ConfigUpdateStreamHandler
  : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit ConfigUpdateStreamHandler(FirebaseRemoteConfigWebosPlugin* plugin)
      : plugin_(plugin) {}

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListen(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
          events) {
    return HandleListen(arguments, std::move(events));
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
          events) {
    return HandleListen(arguments, std::move(events));
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancel(const flutter::EncodableValue* arguments) {
    return HandleCancel(arguments);
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue* arguments) {
    return HandleCancel(arguments);
  }

 private:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  HandleListen(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
          events) {
    const std::optional<FlutterError> error =
        plugin_->StartConfigUpdateStream(arguments, std::move(events));
    if (!error.has_value()) {
      return nullptr;
    }

    return std::make_unique<flutter::StreamHandlerError<
        flutter::EncodableValue>>(
        error->code(), error->message(),
        std::make_unique<flutter::EncodableValue>(error->details()));
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  HandleCancel(const flutter::EncodableValue* arguments) {
    const std::optional<FlutterError> error =
        plugin_->StopConfigUpdateStream(arguments);
    if (!error.has_value()) {
      return nullptr;
    }

    return std::make_unique<flutter::StreamHandlerError<
        flutter::EncodableValue>>(
        error->code(), error->message(),
        std::make_unique<flutter::EncodableValue>(error->details()));
  }

  FirebaseRemoteConfigWebosPlugin* plugin_;
};

std::optional<std::string> GetAppNameFromArguments(
    const flutter::EncodableValue* arguments) {
  if (!arguments || !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
    return std::nullopt;
  }

  const auto& map = std::get<flutter::EncodableMap>(*arguments);
  const auto app_name_it = map.find(flutter::EncodableValue("appName"));
  if (app_name_it == map.end() ||
      !std::holds_alternative<std::string>(app_name_it->second)) {
    return std::nullopt;
  }

  return std::get<std::string>(app_name_it->second);
}

}  // namespace

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrar* registrar) {
  auto plugin = std::make_unique<FirebaseRemoteConfigWebosPlugin>();

  plugin->on_config_updated_event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "plugins.flutter.io/firebase_remote_config_updated",
          &flutter::StandardMethodCodec::GetInstance());
    plugin->on_config_updated_event_channel_->SetStreamHandler(
      std::make_unique<ConfigUpdateStreamHandler>(plugin.get()));

  FirebaseRemoteConfigHostApi::SetUp(registrar->messenger(), plugin.get());
  registrar->AddPlugin(std::move(plugin));
}

FirebaseRemoteConfigWebosPlugin::FirebaseRemoteConfigWebosPlugin() {
}

FirebaseRemoteConfigWebosPlugin::~FirebaseRemoteConfigWebosPlugin() {
  StopConfigUpdateStream(nullptr);
  if (on_config_updated_polling_thread_.joinable()) {
    on_config_updated_polling_thread_.join();
  }
  // RemoteConfig instances are singletons managed by the C++ SDK — do NOT delete them.
}

std::optional<FlutterError>
FirebaseRemoteConfigWebosPlugin::StartConfigUpdateStream(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
  const std::optional<std::string> app_name = GetAppNameFromArguments(arguments);
  if (!app_name.has_value()) {
    return FlutterError("INVALID_ARGUMENT", "Missing required appName argument.");
  }

  auto* rc = GetRemoteConfig(*app_name);
  if (!rc) {
    return FlutterError("NO_APP", "Firebase app not initialized: " + *app_name);
  }

  StopConfigUpdateStream(nullptr);

  {
    std::lock_guard<std::mutex> lock(on_config_updated_mutex_);
    on_config_updated_events_ = std::move(events);
    stop_on_config_updated_polling_ = false;
    last_notified_updated_keys_.clear();
  }

  on_config_updated_polling_thread_ = std::thread([this, app_name_copy = *app_name]() {
    auto* initial_rc = GetRemoteConfig(app_name_copy);
    uint64_t last_fetch_time = 0;
    if (initial_rc) {
      last_fetch_time = initial_rc->GetInfo().fetch_time;
    }

    while (true) {
      {
        std::unique_lock<std::mutex> lock(on_config_updated_mutex_);
        if (on_config_updated_cv_.wait_for(
                lock, std::chrono::seconds(30),
                [this]() { return stop_on_config_updated_polling_; })) {
          break;
        }
      }

      auto* loop_rc = GetRemoteConfig(app_name_copy);
      if (!loop_rc) {
        continue;
      }

      auto fetch_future = loop_rc->Fetch(0);
      while (fetch_future.status() == firebase::kFutureStatusPending) {
        std::unique_lock<std::mutex> lock(on_config_updated_mutex_);
        if (on_config_updated_cv_.wait_for(
                lock, std::chrono::milliseconds(200),
                [this]() { return stop_on_config_updated_polling_; })) {
          return;
        }
      }

      if (fetch_future.error() != 0) {
        continue;
      }

      const ConfigInfo info = loop_rc->GetInfo();
      if (info.last_fetch_status != kLastFetchStatusSuccess ||
          info.fetch_time == last_fetch_time) {
        continue;
      }
      last_fetch_time = info.fetch_time;

      std::vector<std::string> current_updated_keys = loop_rc->GetUpdatedKeys();
      std::sort(current_updated_keys.begin(), current_updated_keys.end());

      if (!current_updated_keys.empty() && current_updated_keys != last_notified_updated_keys_) {
        last_notified_updated_keys_ = current_updated_keys;

        flutter::EncodableList updated_keys;
        for (const auto& key : current_updated_keys) {
          updated_keys.push_back(flutter::EncodableValue(key));
        }

        std::lock_guard<std::mutex> lock(on_config_updated_mutex_);
        if (on_config_updated_events_) {
          on_config_updated_events_->Success(flutter::EncodableValue(updated_keys));
        }
      } else if (current_updated_keys.empty() && !last_notified_updated_keys_.empty()) {
        last_notified_updated_keys_.clear();
      }
    }
  });

  return std::nullopt;
}

std::optional<FlutterError>
FirebaseRemoteConfigWebosPlugin::StopConfigUpdateStream(
    const flutter::EncodableValue* /*arguments*/) {
  {
    std::lock_guard<std::mutex> lock(on_config_updated_mutex_);
    stop_on_config_updated_polling_ = true;
    last_notified_updated_keys_.clear();
    on_config_updated_cv_.notify_all();
  }

  if (on_config_updated_polling_thread_.joinable()) {
    on_config_updated_polling_thread_.join();
  }

  {
    std::lock_guard<std::mutex> lock(on_config_updated_mutex_);
    on_config_updated_events_.reset();
  }

  return std::nullopt;
}

// ---------------------------------------------------------------------------
// GetRemoteConfig helper
// ---------------------------------------------------------------------------

RemoteConfig* FirebaseRemoteConfigWebosPlugin::GetRemoteConfig(
    const std::string& app_name) {
  firebase::App* app = FirebaseAppHolder::GetApp(app_name);
  if (!app) {
    return nullptr;
  }
  RemoteConfig* rc = RemoteConfig::GetInstance(app);
  return rc;
}

// ---------------------------------------------------------------------------
// ValueSource converter
// ---------------------------------------------------------------------------

PigeonValueSource FirebaseRemoteConfigWebosPlugin::CppSourceToPigeon(
    firebase::remote_config::ValueSource src) {

  switch (src) {
    case kValueSourceRemoteValue:
      return PigeonValueSource::remoteValue;

    case kValueSourceDefaultValue:
      return PigeonValueSource::defaultValue;

    case kValueSourceStaticValue:
    default:
      return PigeonValueSource::staticValue;
  }
}

// ---------------------------------------------------------------------------
// Future helpers (OnCompletion — matches auth plugin pattern for this SDK)
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::HandleVoidFuture(
    firebase::Future<void> future,
    std::function<void(std::optional<FlutterError>)> result) {
  future.OnCompletion([result](const firebase::Future<void>& f) {
    if (f.error() == 0) {
      result(std::nullopt);
    } else {
      result(FlutterError(std::to_string(f.error()), f.error_message()));
    }
  });
}

template <typename T>
void FirebaseRemoteConfigWebosPlugin::HandleFuture(
    firebase::Future<T> future,
    std::function<void(ErrorOr<T>)> result) {
  future.OnCompletion([result](const firebase::Future<T>& f) {
    if (f.error() == 0) {
      result(*f.result());
    } else {
      result(FlutterError(std::to_string(f.error()), f.error_message()));
    }
  });
}

// ---------------------------------------------------------------------------
// Initialize — get the RemoteConfig singleton; if it exists we're done.
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::Initialize(
    const std::string& app_name,
    std::function<void(std::optional<FlutterError>)> result) {
  if (!GetRemoteConfig(app_name)) {
    result(FlutterError("NO_APP", "Firebase app not initialized: " + app_name));
    return;
  }
  result(std::nullopt);
}

// ---------------------------------------------------------------------------
// EnsureInitialized — wait for the internal initialization future.
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::EnsureInitialized(
    const std::string& app_name,
    std::function<void(std::optional<FlutterError>)> result) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    result(FlutterError("NO_APP", "Firebase app not initialized: " + app_name));
    return;
  }
  rc->EnsureInitialized().OnCompletion(
    [result](const firebase::Future<firebase::remote_config::ConfigInfo>& f) {
      if (f.error() == 0) {
        result(std::nullopt);
      } else {
        result(FlutterError(std::to_string(f.error()), f.error_message()));
      }
    });
}

// ---------------------------------------------------------------------------
// Fetch — must wait for the future; result on completion.
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::Fetch(
    const std::string& app_name,
    double cache_expiration_in_seconds,
    std::function<void(std::optional<FlutterError>)> result) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    result(FlutterError("NO_APP", "Firebase app not initialized: " + app_name));
    return;
  }

  firebase::Future<void> future;
  if (cache_expiration_in_seconds <= 0) {
    future = rc->Fetch();
  } else {
    // SDK takes uint64_t milliseconds.
    future = rc->Fetch(
        static_cast<uint64_t>(cache_expiration_in_seconds * 1000.0));
  }
  HandleVoidFuture(future, result);
}

// ---------------------------------------------------------------------------
// Activate
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::Activate(
    const std::string& app_name,
    std::function<void(ErrorOr<bool>)> result) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    result(FlutterError("NO_APP", "Firebase app not initialized: " + app_name));
    return;
  }
  HandleFuture(rc->Activate(), result);
}

// ---------------------------------------------------------------------------
// FetchAndActivate
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::FetchAndActivate(
    const std::string& app_name,
    std::function<void(ErrorOr<bool>)> result) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    result(FlutterError("NO_APP", "Firebase app not initialized: " + app_name));
    return;
  }
  HandleFuture(rc->FetchAndActivate(), result);
}

// ---------------------------------------------------------------------------
// Typed getters — all synchronous in the C++ SDK after activation.
// ---------------------------------------------------------------------------

ErrorOr<std::string> FirebaseRemoteConfigWebosPlugin::GetString(
    const std::string& app_name,
    const std::string& key) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError("NO_APP", "Firebase app not initialized: " + app_name);
  }
  std::string value = rc->GetString(key.c_str());
  return value;
}

ErrorOr<bool> FirebaseRemoteConfigWebosPlugin::GetBool(
    const std::string& app_name,
    const std::string& key) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError("NO_APP", "Firebase app not initialized: " + app_name);
  }
  bool value = rc->GetBoolean(key.c_str());
  return value;
}

ErrorOr<int64_t> FirebaseRemoteConfigWebosPlugin::GetInt(
    const std::string& app_name,
    const std::string& key) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError("NO_APP", "Firebase app not initialized: " + app_name);
  }
  int64_t value = static_cast<int64_t>(rc->GetLong(key.c_str()));
  return value;
}

ErrorOr<double> FirebaseRemoteConfigWebosPlugin::GetDouble(
    const std::string& app_name,
    const std::string& key) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError("NO_APP", "Firebase app not initialized: " + app_name);
  }
  double value = rc->GetDouble(key.c_str());
  return value;
}

ErrorOr<PigeonRemoteConfigValue> FirebaseRemoteConfigWebosPlugin::GetValue(
    const std::string& app_name,
    const std::string& key) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError("NO_APP", "Firebase app not initialized: " + app_name);
  }

  firebase::remote_config::ValueInfo info;
  std::string str_value = rc->GetString(key.c_str(), &info);

  PigeonRemoteConfigValue pv(CppSourceToPigeon(info.source));
  pv.set_value(str_value);
  return pv;
}

// ---------------------------------------------------------------------------
// GetAll — iterate all known keys and return map of key → PigeonRemoteConfigValue
// ---------------------------------------------------------------------------
ErrorOr<flutter::EncodableMap> FirebaseRemoteConfigWebosPlugin::GetAll(
    const std::string& app_name) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError(
        "NO_APP",
        "Firebase app not initialized: " + app_name);
  }

  flutter::EncodableMap map;
  std::vector<std::string> keys = rc->GetKeys();

  for (const auto& key : keys) {
    firebase::remote_config::ValueInfo info;
    std::string str_value = rc->GetString(key.c_str(), &info);

    PigeonRemoteConfigValue value(
        CppSourceToPigeon(info.source));
    value.set_value(str_value);

    map[flutter::EncodableValue(key)] =
        flutter::CustomEncodableValue(value);
  }

  return map;
}

// ---------------------------------------------------------------------------
// SetDefaults — keep strings alive via shared_ptr until future completes.
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::SetDefaults(
    const std::string& app_name,
    const flutter::EncodableMap& default_parameters,
    std::function<void(std::optional<FlutterError>)> result) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    result(FlutterError("NO_APP", "Firebase app not initialized: " + app_name));
    return;
  }


  // Keep the strings alive for the duration of the async call.
  struct ReqData {
    std::vector<std::string> keys;
    std::vector<std::string> vals;
    std::vector<ConfigKeyValue> kv_pairs;
  };
  auto req = std::make_shared<ReqData>();

  for (const auto& [k, v] : default_parameters) {
    if (!std::holds_alternative<std::string>(k)) continue;
    std::string val_str;
    if (std::holds_alternative<std::string>(v))
      val_str = std::get<std::string>(v);
    else if (std::holds_alternative<int32_t>(v))
      val_str = std::to_string(std::get<int32_t>(v));
    else if (std::holds_alternative<int64_t>(v))
      val_str = std::to_string(std::get<int64_t>(v));
    else if (std::holds_alternative<double>(v))
      val_str = std::to_string(std::get<double>(v));
    else if (std::holds_alternative<bool>(v))
      val_str = std::get<bool>(v) ? "true" : "false";

    req->keys.push_back(std::get<std::string>(k));
    req->vals.push_back(std::move(val_str));
  }

  req->kv_pairs.reserve(req->keys.size());
  for (size_t i = 0; i < req->keys.size(); ++i) {
    req->kv_pairs.push_back({req->keys[i].c_str(), req->vals[i].c_str()});
  }

  auto future = rc->SetDefaults(req->kv_pairs.data(), req->kv_pairs.size());
  future.OnCompletion([req, result](const firebase::Future<void>& f) {
    if (f.error() == 0) {
      result(std::nullopt);
    } else {
      result(FlutterError(std::to_string(f.error()), f.error_message()));
    }
  });
}

// ---------------------------------------------------------------------------
// SetInitialValues — not exposed in C++ SDK; no-op.
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::SetInitialValues(
    const std::string& /*app_name*/,
    const flutter::EncodableMap& /*remote_config_values*/,
    std::function<void(std::optional<FlutterError>)> result) {
  result(std::nullopt);
}

// ---------------------------------------------------------------------------
// SetConfigSettings
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::SetConfigSettings(
    const std::string& app_name,
    const PigeonRemoteConfigSettings& settings,
    std::function<void(std::optional<FlutterError>)> result) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    result(FlutterError("NO_APP", "Firebase app not initialized: " + app_name));
    return;
  }
  ConfigSettings cs;
  cs.fetch_timeout_in_milliseconds =
      static_cast<uint64_t>(settings.fetch_timeout() * 1000.0);
  cs.minimum_fetch_interval_in_milliseconds =
      static_cast<uint64_t>(settings.minimum_fetch_interval() * 1000.0);
  HandleVoidFuture(rc->SetConfigSettings(cs), result);
}

// ---------------------------------------------------------------------------
// GetConfigSettings / GetSettings (alias)
// ---------------------------------------------------------------------------

ErrorOr<PigeonRemoteConfigSettings> FirebaseRemoteConfigWebosPlugin::GetConfigSettings(
    const std::string& app_name) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError("NO_APP", "Firebase app not initialized: " + app_name);
  }

  ConfigSettings cs = rc->GetConfigSettings();
  return PigeonRemoteConfigSettings(
      static_cast<double>(cs.fetch_timeout_in_milliseconds) / 1000.0,
      static_cast<double>(cs.minimum_fetch_interval_in_milliseconds) / 1000.0);
}

ErrorOr<PigeonRemoteConfigSettings> FirebaseRemoteConfigWebosPlugin::GetSettings(
    const std::string& app_name) {
  return GetConfigSettings(app_name);
}

// ---------------------------------------------------------------------------
// SetCustomSignals — not in C++ SDK; no-op.
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPlugin::SetCustomSignals(
    const std::string& /*app_name*/,
    const flutter::EncodableMap& /*custom_signals*/,
    std::function<void(std::optional<FlutterError>)> result) {
  result(std::nullopt);
}

// ---------------------------------------------------------------------------
// GetLastFetchStatus
// ---------------------------------------------------------------------------

ErrorOr<int64_t> FirebaseRemoteConfigWebosPlugin::GetLastFetchStatus(
    const std::string& app_name) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError(
        "NO_APP",
        "Firebase app not initialized: " + app_name);
  }

  const ConfigInfo info = rc->GetInfo();
  return static_cast<int64_t>(info.last_fetch_status);
}

// ---------------------------------------------------------------------------
// GetLastFetchTime
// ---------------------------------------------------------------------------
ErrorOr<int64_t> FirebaseRemoteConfigWebosPlugin::GetLastFetchTime(
    const std::string& app_name) {
  auto* rc = GetRemoteConfig(app_name);
  if (!rc) {
    return FlutterError(
        "NO_APP",
        "Firebase app not initialized: " + app_name);
  }

  const ConfigInfo info = rc->GetInfo();

  return static_cast<int64_t>(info.fetch_time);
}

}  // namespace firebase_remote_config_webos

// ---------------------------------------------------------------------------
// C registration entry point (called by the Flutter embedder)
// ---------------------------------------------------------------------------

void FirebaseRemoteConfigWebosPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  firebase_remote_config_webos::FirebaseRemoteConfigWebosPlugin::
      RegisterWithRegistrar(
          flutter::PluginRegistrarManager::GetInstance()
              ->GetRegistrar<flutter::PluginRegistrar>(registrar));
}
