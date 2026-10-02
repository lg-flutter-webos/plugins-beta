#ifndef FIREBASE_FIRESTORE_WEBOS_PLUGIN_H_
#define FIREBASE_FIRESTORE_WEBOS_PLUGIN_H_

#include <firebase/firestore.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar.h>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "messages.g.h"

namespace firebase_firestore_webos {

class FirebaseFirestoreWebosPlugin : public flutter::Plugin,
                                     public FirestoreHostApi {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrar* registrar);

  FirebaseFirestoreWebosPlugin();
  virtual ~FirebaseFirestoreWebosPlugin();

  // Firestore Host API Implementation
  void InitializeFirestore(
      const std::string& app_name,
      const std::string& database_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void SetSettings(
      const std::string& app_name,
      const std::string& database_id,
      const PigeonFirestoreSettings& settings,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void EnableNetwork(
      const std::string& app_name,
      const std::string& database_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void DisableNetwork(
      const std::string& app_name,
      const std::string& database_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void ClearPersistence(
      const std::string& app_name,
      const std::string& database_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void Terminate(
      const std::string& app_name,
      const std::string& database_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void WaitForPendingWrites(
      const std::string& app_name,
      const std::string& database_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void DocumentGet(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      const PigeonGetOptions& options,
      std::function<void(ErrorOr<PigeonDocumentSnapshot> reply)> result) override;

  void DocumentSet(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      const flutter::EncodableMap& data,
      const PigeonSetOptions& options,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void DocumentUpdate(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      const flutter::EncodableMap& data,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void DocumentDelete(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void DocumentAddSnapshotListener(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      bool include_metadata_changes,
      std::function<void(ErrorOr<int64_t> reply)> result) override;

  void QueryGet(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      bool is_collection_group,
      const PigeonQueryParameters& parameters,
      const PigeonGetOptions& options,
      std::function<void(ErrorOr<PigeonQuerySnapshot> reply)> result) override;

  void QueryAddSnapshotListener(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      bool is_collection_group,
      const PigeonQueryParameters& parameters,
      bool include_metadata_changes,
      std::function<void(ErrorOr<int64_t> reply)> result) override;

  void QueryCount(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      bool is_collection_group,
      const PigeonQueryParameters& parameters,
      std::function<void(ErrorOr<PigeonAggregateQuerySnapshot> reply)> result) override;

  void QueryAggregate(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& path,
      bool is_collection_group,
      const PigeonQueryParameters& parameters,
      const flutter::EncodableList& aggregate_types,
      std::function<void(ErrorOr<PigeonAggregateQuerySnapshot> reply)> result) override;

  void UseEmulator(
      const std::string& app_name,
      const std::string& database_id,
      const std::string& host,
      int64_t port,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void SetLoggingEnabled(
      const std::string& app_name,
      const std::string& database_id,
      bool enabled,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void RemoveSnapshotListener(
      const std::string& app_name,
      const std::string& database_id,
      int64_t listener_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void BatchCommit(
      const std::string& app_name,
      const std::string& database_id,
      const flutter::EncodableList& writes,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void RunTransaction(
      const std::string& app_name,
      const std::string& database_id,
      int64_t transaction_id,
      int64_t max_attempts,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  void TransactionGet(
      const std::string& app_name,
      const std::string& database_id,
      int64_t transaction_id,
      const std::string& path,
      std::function<void(ErrorOr<PigeonDocumentSnapshot> reply)> result) override;

  void TransactionComplete(
      const std::string& app_name,
      const std::string& database_id,
      int64_t transaction_id,
      const PigeonTransactionResult& result_type,
      const flutter::EncodableList* updates,
      std::function<void(std::optional<FlutterError> reply)> result) override;

  // Helper methods
  firebase::firestore::Firestore* GetFirestore(
      const std::string& app_name,
      const std::string& database_id);

  static PigeonDocumentSnapshot DocumentSnapshotToPigeon(
      const firebase::firestore::DocumentSnapshot& snapshot);

 private:
  std::mutex mutex_;
  std::mutex event_mutex_;
  std::map<std::string, firebase::firestore::Firestore*> firestore_instances_;
  std::map<int64_t, firebase::firestore::ListenerRegistration> listeners_;
  std::map<std::string, std::shared_ptr<struct TransactionSession>> transaction_sessions_;
  int64_t next_listener_id_ = 0;
  flutter::BinaryMessenger* messenger_ = nullptr;

  // Event Channel for snapshot listeners (replaces Pigeon FlutterApi callbacks)
  void InitializeSnapshotEventChannels(flutter::BinaryMessenger* messenger);
  void SendDocumentSnapshotToDart(const std::string& app_name, const std::string& database_id, int64_t listener_id, const firebase::firestore::DocumentSnapshot& snapshot, const std::string* error);
  void SendQuerySnapshotToDart(const std::string& app_name, const std::string& database_id, int64_t listener_id, const firebase::firestore::QuerySnapshot& snapshot, const std::string* error);

  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> document_snapshot_event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> document_snapshot_event_sink_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> query_snapshot_event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> query_snapshot_event_sink_;

  // Buffers for events that arrive before the Dart side subscribes to the
  // event channel. Prevents the race condition where the initial snapshot
  // fires before the event sink is ready.
  std::vector<flutter::EncodableValue> document_snapshot_pending_events_;
  std::vector<flutter::EncodableValue> query_snapshot_pending_events_;
};

}  // namespace firebase_firestore_webos

#endif  // FIREBASE_FIRESTORE_WEBOS_PLUGIN_H_
