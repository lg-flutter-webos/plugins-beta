import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'firebase_firestore_webos_query.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosCollectionReference extends CollectionReferencePlatform {
  FirebaseFirestoreWebosCollectionReference(
    FirebaseFirestorePlatform firestore,
    String path,
  ) : super(firestore, path);

  /// Override parameters to ensure default keys (where, orderBy) are present.
  /// The CollectionReferencePlatform parent passes an empty map {} to QueryPlatform,
  /// which bypasses the _initialParameters that include default empty lists for
  /// 'where' and 'orderBy'. This causes Null errors in cloud_firestore's _JsonQuery.
  @override
  Map<String, dynamic> get parameters {
    final params = super.parameters;
    params.putIfAbsent('where', () => <List<dynamic>>[]);
    params.putIfAbsent('orderBy', () => <List<dynamic>>[]);
    return params;
  }

  @override
  DocumentReferencePlatform doc([String? documentPath]) {
    if (documentPath == null) {
      // Generate a new document ID
      documentPath = _generateDocumentId();
    }
    return firestore.doc('$path/$documentPath');
  }

  @override
  Future<DocumentReferencePlatform> add(Map<String, dynamic> data) async {
    final docRef = doc();
    await docRef.set(data);
    return docRef;
  }

  String _generateDocumentId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return random + chars[(random.hashCode % chars.length)];
  }

  @override
  QueryPlatform endAtDocument(List<dynamic> orders, List<dynamic> values) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['endAt'] = values,
    );
  }

  @override
  QueryPlatform endAt(Iterable<dynamic> fields) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['endAt'] = fields.toList(),
    );
  }

  @override
  QueryPlatform endBeforeDocument(Iterable<dynamic> orders, Iterable<dynamic> values) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['endBefore'] = values.toList(),
    );
  }

  @override
  QueryPlatform endBefore(Iterable<dynamic> fields) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['endBefore'] = fields.toList(),
    );
  }

  @override
  Future<QuerySnapshotPlatform> get([GetOptions options = const GetOptions()]) {
    return FirebaseFirestoreWebosQuery(firestore, path, false, parameters).get(options);
  }

  @override
  QueryPlatform limit(int limit) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['limit'] = limit,
    );
  }

  @override
  QueryPlatform limitToLast(int limit) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['limitToLast'] = limit,
    );
  }

  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['orderBy'] = orders.toList(),
    );
  }

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) {
    return FirebaseFirestoreWebosQuery(firestore, path, false, parameters)
        .snapshots(includeMetadataChanges: includeMetadataChanges, listenSource: listenSource);
  }

  @override
  QueryPlatform startAfterDocument(Iterable<dynamic> orders, Iterable<dynamic> values) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['startAfter'] = values.toList(),
    );
  }

  @override
  QueryPlatform startAfter(Iterable<dynamic> fields) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['startAfter'] = fields.toList(),
    );
  }

  @override
  QueryPlatform startAtDocument(Iterable<dynamic> orders, Iterable<dynamic> values) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['startAt'] = values.toList(),
    );
  }

  @override
  QueryPlatform startAt(Iterable<dynamic> fields) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['startAt'] = fields.toList(),
    );
  }

  @override
  QueryPlatform where(List<List<dynamic>> conditions) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      path,
      false,
      Map<String, dynamic>.from(parameters)..['where'] = conditions,
    );
  }

  @override
  bool get isCollectionGroupQuery => false;

  @override
  QueryPlatform whereFilter(FilterPlatformInterface filter) {
    return FirebaseFirestoreWebosQuery(firestore, path, false, parameters)
        .whereFilter(filter);
  }

  @override
  AggregateQueryPlatform count() {
    return FirebaseFirestoreWebosQuery(firestore, path, false, parameters)
        .count();
  }

  @override
  AggregateQueryPlatform aggregate(
    AggregateField aggregateField1,
    [AggregateField? aggregateField2,
    AggregateField? aggregateField3,
    AggregateField? aggregateField4,
    AggregateField? aggregateField5,
    AggregateField? aggregateField6,
    AggregateField? aggregateField7,
    AggregateField? aggregateField8,
    AggregateField? aggregateField9,
    AggregateField? aggregateField10,
    AggregateField? aggregateField11,
    AggregateField? aggregateField12,
    AggregateField? aggregateField13,
    AggregateField? aggregateField14,
    AggregateField? aggregateField15,
    AggregateField? aggregateField16,
    AggregateField? aggregateField17,
    AggregateField? aggregateField18,
    AggregateField? aggregateField19,
    AggregateField? aggregateField20,
    AggregateField? aggregateField21,
    AggregateField? aggregateField22,
    AggregateField? aggregateField23,
    AggregateField? aggregateField24,
    AggregateField? aggregateField25,
    AggregateField? aggregateField26,
    AggregateField? aggregateField27,
    AggregateField? aggregateField28,
    AggregateField? aggregateField29,
    AggregateField? aggregateField30,
  ]) {
    return FirebaseFirestoreWebosQuery(firestore, path, false, parameters)
        .aggregate(aggregateField1, aggregateField2, aggregateField3, aggregateField4, aggregateField5, aggregateField6, aggregateField7, aggregateField8, aggregateField9, aggregateField10, aggregateField11, aggregateField12, aggregateField13, aggregateField14, aggregateField15, aggregateField16, aggregateField17, aggregateField18, aggregateField19, aggregateField20, aggregateField21, aggregateField22, aggregateField23, aggregateField24, aggregateField25, aggregateField26, aggregateField27, aggregateField28, aggregateField29, aggregateField30);
  }
}
