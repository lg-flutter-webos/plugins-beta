import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'messages.g.dart' as msgs;
import 'firebase_firestore_webos_query.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosAggregateQuery extends AggregateQueryPlatform {
  FirebaseFirestoreWebosAggregateQuery(this._query) : super(_query);

  final FirebaseFirestoreWebosQuery _query;
  static final msgs.FirestoreHostApi _api = msgs.FirestoreHostApi();

  /// The list of aggregate types requested: "count", "sum:fieldName", "avg:fieldName"
  final List<String> _aggregateTypes = <String>['count'];

  @override
  Future<AggregateQuerySnapshotPlatform> get({
    required AggregateSource source,
  }) async {
    final firestore = _query.firestore;
    final result = await _api.queryAggregate(
      firestore.app.name,
      firestore.databaseId,
      _query.path,
      _query.isCollectionGroupQuery,
      _query.toPigeonParameters(),
      _aggregateTypes,
    );

    // Convert sum results
    final List<AggregateQueryResponse> sumResults = <AggregateQueryResponse>[];
    if (result.sum != null) {
      for (final r in result.sum!) {
        if (r != null) {
          sumResults.add(AggregateQueryResponse(
            type: AggregateType.sum,
            field: r.field,
            value: r.value,
          ));
        }
      }
    }

    // Convert average results
    final List<AggregateQueryResponse> averageResults = <AggregateQueryResponse>[];
    if (result.average != null) {
      for (final r in result.average!) {
        if (r != null) {
          averageResults.add(AggregateQueryResponse(
            type: AggregateType.average,
            field: r.field,
            value: r.value,
          ));
        }
      }
    }

    return AggregateQuerySnapshotPlatform(
      count: result.count,
      sum: sumResults,
      average: averageResults,
    );
  }

  @override
  AggregateQueryPlatform count() {
    if (!_aggregateTypes.contains('count')) {
      _aggregateTypes.add('count');
    }
    return this;
  }

  @override
  AggregateQueryPlatform sum(String field) {
    final spec = 'sum:$field';
    if (!_aggregateTypes.contains(spec)) {
      _aggregateTypes.add(spec);
    }
    return this;
  }

  @override
  AggregateQueryPlatform average(String field) {
    final spec = 'avg:$field';
    if (!_aggregateTypes.contains(spec)) {
      _aggregateTypes.add(spec);
    }
    return this;
  }
}
