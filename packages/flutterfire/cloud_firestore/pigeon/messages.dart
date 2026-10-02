import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  cppHeaderOut: 'webos/messages.g.h',
  cppSourceOut: 'webos/messages.g.cc',
  cppOptions: CppOptions(namespace: 'firebase_firestore_webos'),
  dartPackageName: 'firebase_firestore_webos',
))

// ---------------------------------------------------------------------------
// Data Classes
// ---------------------------------------------------------------------------

/// Firestore settings configuration
class PigeonFirestoreSettings {
  PigeonFirestoreSettings({
    required this.host,
    required this.sslEnabled,
    required this.persistenceEnabled,
    required this.cacheSizeBytes,
  });

  String host;
  bool sslEnabled;
  bool persistenceEnabled;
  int cacheSizeBytes;
}

/// Snapshot metadata
class PigeonSnapshotMetadata {
  PigeonSnapshotMetadata({
    required this.hasPendingWrites,
    required this.isFromCache,
  });

  bool hasPendingWrites;
  bool isFromCache;
}

/// Document snapshot data
class PigeonDocumentSnapshot {
  PigeonDocumentSnapshot({
    required this.path,
    required this.data,
    required this.metadata,
    required this.exists,
  });

  String path;
  Map<String?, Object?>? data;
  PigeonSnapshotMetadata metadata;
  bool exists;
}

/// Document change type
enum PigeonDocumentChangeType {
  added,
  modified,
  removed,
}

/// Document change
class PigeonDocumentChange {
  PigeonDocumentChange({
    required this.type,
    required this.document,
    required this.oldIndex,
    required this.newIndex,
  });

  PigeonDocumentChangeType type;
  PigeonDocumentSnapshot document;
  int oldIndex;
  int newIndex;
}

/// Query snapshot
class PigeonQuerySnapshot {
  PigeonQuerySnapshot({
    required this.documents,
    required this.documentChanges,
    required this.metadata,
  });

  List<PigeonDocumentSnapshot?> documents;
  List<PigeonDocumentChange?> documentChanges;
  PigeonSnapshotMetadata metadata;
}

/// Get options
class PigeonGetOptions {
  PigeonGetOptions({
    required this.source,
  });

  String source; // 'default', 'server', 'cache'
}

/// Set options
class PigeonSetOptions {
  PigeonSetOptions({
    required this.merge,
    this.mergeFields,
  });

  bool merge;
  List<String?>? mergeFields;
}

/// Transaction update data
class PigeonTransactionUpdate {
  PigeonTransactionUpdate({
    required this.type,
    required this.path,
    this.data,
  });

  String type; // 'set', 'update', 'delete'
  String path;
  Map<String?, Object?>? data;
}

enum PigeonTransactionResult {
  success,
  failure,
}

/// Aggregate query result
class PigeonAggregateQuerySnapshot {
  PigeonAggregateQuerySnapshot({
    required this.count,
    this.sum,
    this.average,
  });

  int count;

  /// Sum aggregation results: list of {field: string, value: double}
  List<PigeonAggregateResult?>? sum;

  /// Average aggregation results: list of {field: string, value: double}
  List<PigeonAggregateResult?>? average;
}

/// A single aggregate result (field name + value)
class PigeonAggregateResult {
  PigeonAggregateResult({
    required this.field,
    required this.value,
  });

  String field;
  double value;
}

/// Query parameters for building queries
class PigeonQueryParameters {
  PigeonQueryParameters({
    this.where,
    this.orderBy,
    this.limit,
    this.limitToLast,
    this.startAt,
    this.startAfter,
    this.endAt,
    this.endBefore,
  });

  List<PigeonQueryFilter?>? where;
  List<PigeonQueryOrder?>? orderBy;
  int? limit;
  int? limitToLast;
  List<Object?>? startAt;
  List<Object?>? startAfter;
  List<Object?>? endAt;
  List<Object?>? endBefore;
}

/// Query filter
class PigeonQueryFilter {
  PigeonQueryFilter({
    required this.field,
    required this.op,
    required this.value,
  });

  String field;
  String op; // '==', '!=', '<', '<=', '>', '>=', 'array-contains', 'array-contains-any', 'in', 'not-in'
  Object? value;
}

/// Query order
class PigeonQueryOrder {
  PigeonQueryOrder({
    required this.field,
    required this.descending,
  });

  String field;
  bool descending;
}

// ---------------------------------------------------------------------------
// Host API — Dart → C++
// ---------------------------------------------------------------------------

@HostApi()
abstract class FirestoreHostApi {
  /// Initialize Firestore instance
  @async
  void initializeFirestore(String appName, String databaseId);

  /// Set Firestore settings (must be called before any other operation)
  @async
  void setSettings(String appName, String databaseId, PigeonFirestoreSettings settings);

  /// Enable network
  @async
  void enableNetwork(String appName, String databaseId);

  /// Disable network
  @async
  void disableNetwork(String appName, String databaseId);

  /// Clear persistence
  @async
  void clearPersistence(String appName, String databaseId);

  /// Terminate Firestore instance
  @async
  void terminate(String appName, String databaseId);

  /// Wait for pending writes
  @async
  void waitForPendingWrites(String appName, String databaseId);

  /// Get a document
  @async
  PigeonDocumentSnapshot documentGet(
    String appName,
    String databaseId,
    String path,
    PigeonGetOptions options,
  );

  /// Set a document
  @async
  void documentSet(
    String appName,
    String databaseId,
    String path,
    Map<String?, Object?> data,
    PigeonSetOptions options,
  );

  /// Update a document
  @async
  void documentUpdate(
    String appName,
    String databaseId,
    String path,
    Map<String?, Object?> data,
  );

  /// Delete a document
  @async
  void documentDelete(
    String appName,
    String databaseId,
    String path,
  );

  /// Start listening to a document
  @async
  int documentAddSnapshotListener(
    String appName,
    String databaseId,
    String path,
    bool includeMetadataChanges,
  );

  /// Query get
  @async
  PigeonQuerySnapshot queryGet(
    String appName,
    String databaseId,
    String path,
    bool isCollectionGroup,
    PigeonQueryParameters parameters,
    PigeonGetOptions options,
  );

  /// Start listening to a query
  @async
  int queryAddSnapshotListener(
    String appName,
    String databaseId,
    String path,
    bool isCollectionGroup,
    PigeonQueryParameters parameters,
    bool includeMetadataChanges,
  );

  /// Count aggregate query
  @async
  PigeonAggregateQuerySnapshot queryCount(
    String appName,
    String databaseId,
    String path,
    bool isCollectionGroup,
    PigeonQueryParameters parameters,
  );

  /// Aggregate query (supports count, sum, average)
  /// The aggregateTypes parameter is a list of strings: "count", "sum:fieldName", "avg:fieldName"
  @async
  PigeonAggregateQuerySnapshot queryAggregate(
    String appName,
    String databaseId,
    String path,
    bool isCollectionGroup,
    PigeonQueryParameters parameters,
    List<String> aggregateTypes,
  );

  /// Remove a snapshot listener
  @async
  void removeSnapshotListener(
    String appName,
    String databaseId,
    int listenerId,
  );

  /// Use emulator
  @async
  void useEmulator(String appName, String databaseId, String host, int port);

  /// Set logging enabled
  @async
  void setLoggingEnabled(String appName, String databaseId, bool enabled);

  /// Commit a batch write
  @async
  void batchCommit(
    String appName,
    String databaseId,
    List<PigeonTransactionUpdate?> writes,
  );

  /// Run a transaction
  @async
  void runTransaction(
    String appName,
    String databaseId,
    int transactionId,
    int maxAttempts,
  );

  /// Get document in transaction
  @async
  PigeonDocumentSnapshot transactionGet(
    String appName,
    String databaseId,
    int transactionId,
    String path,
  );

  /// Complete transaction with updates
  @async
  void transactionComplete(
    String appName,
    String databaseId,
    int transactionId,
    PigeonTransactionResult resultType,
    List<PigeonTransactionUpdate?>? updates,
  );
}

// ---------------------------------------------------------------------------
// Flutter API — C++ → Dart
// ---------------------------------------------------------------------------

@FlutterApi()
abstract class FirestoreFlutterApi {
  /// Request transaction updates from Dart
  /// Returns JSON-encoded result data or error
  void onTransactionCallback(
    String appName,
    String databaseId,
    int transactionId,
  );
}
