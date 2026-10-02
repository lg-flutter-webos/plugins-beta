import 'dart:async';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as cpi;

import 'messages.g.dart' as msgs;
import 'firebase_firestore_webos_aggregate_query.dart';
import 'firebase_firestore_webos_document_snapshot.dart';
import 'firebase_firestore_webos_query_snapshot.dart';
import 'firestore_flutter_api_impl.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosQuery extends cpi.QueryPlatform {
  FirebaseFirestoreWebosQuery(
    cpi.FirebaseFirestorePlatform firestore,
    this._path,
    this._isCollectionGroup,
    Map<String, dynamic>? parameters,
  ) : super(firestore, parameters);

  final String _path;
  final bool _isCollectionGroup;
  static final msgs.FirestoreHostApi _api = msgs.FirestoreHostApi();

  String get path => _path;

  msgs.PigeonQueryParameters toPigeonParameters() => _convertParameters();

  @override
  bool get isCollectionGroupQuery => _isCollectionGroup;

  @override
  cpi.QueryPlatform endAtDocument(List<dynamic> orders, List<dynamic> values) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['endAt'] = values,
    );
  }

  @override
  cpi.QueryPlatform endAt(Iterable<dynamic> fields) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['endAt'] = fields.toList(),
    );
  }

  @override
  cpi.QueryPlatform endBeforeDocument(Iterable<dynamic> orders, Iterable<dynamic> values) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['endBefore'] = values.toList(),
    );
  }

  @override
  cpi.QueryPlatform endBefore(Iterable<dynamic> fields) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['endBefore'] = fields.toList(),
    );
  }

  @override
  Future<cpi.QuerySnapshotPlatform> get([cpi.GetOptions options = const cpi.GetOptions()]) async {
    try {
      final pigeonParams = _convertParameters();
      final pigeonOptions = msgs.PigeonGetOptions(
        source: _sourceToString(options.source),
      );

      final snapshot = await _api.queryGet(
        firestore.app.name,
        firestore.databaseId,
        _path,
        _isCollectionGroup,
        pigeonParams,
        pigeonOptions,
      );

      return FirebaseFirestoreWebosQuerySnapshot(firestore, snapshot);
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  cpi.QueryPlatform limit(int limit) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['limit'] = limit,
    );
  }

  @override
  cpi.QueryPlatform limitToLast(int limit) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['limitToLast'] = limit,
    );
  }

  @override
  Stream<cpi.QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required cpi.ListenSource listenSource,
  }) {
    final controller = StreamController<cpi.QuerySnapshotPlatform>.broadcast();
    int? listenerId;

    controller.onListen = () async {
      try {
        // Ensure the event channel is set up BEFORE starting the native
        // listener to avoid a race condition where the initial snapshot
        // fires before the Dart side is ready to receive it.
        FirestoreFlutterApiImpl.ensureQueryListener();

        final pigeonParams = _convertParameters();
        listenerId = await _api.queryAddSnapshotListener(
          firestore.app.name,
          firestore.databaseId,
          _path,
          _isCollectionGroup,
          pigeonParams,
          includeMetadataChanges,
        );

        // Register listener for callbacks
        FirestoreFlutterApiImpl.registerQueryListener(
          firestore.app.name,
          firestore.databaseId,
          listenerId!,
          (snapshot, error) {
            if (error != null) {
              controller.addError(Exception(error));
            } else if (snapshot != null) {
              controller.add(FirebaseFirestoreWebosQuerySnapshot(firestore, snapshot));
            }
          },
        );
      } catch (e) {
        controller.addError(_convertError(e));
      }
    };

    controller.onCancel = () async {
      if (listenerId != null) {
        try {
          await _api.removeSnapshotListener(
            firestore.app.name,
            firestore.databaseId,
            listenerId!,
          );
          FirestoreFlutterApiImpl.unregisterQueryListener(
            firestore.app.name,
            firestore.databaseId,
            listenerId!,
          );
        } catch (e) {
          // Ignore errors on cancel
        }
      }
    };

    return controller.stream;
  }

  @override
  cpi.QueryPlatform orderBy(Iterable<List<dynamic>> orders) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['orderBy'] = orders.toList(),
    );
  }

  @override
  cpi.QueryPlatform startAfterDocument(Iterable<dynamic> orders, Iterable<dynamic> values) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['startAfter'] = values.toList(),
    );
  }

  @override
  cpi.QueryPlatform startAfter(Iterable<dynamic> fields) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['startAfter'] = fields.toList(),
    );
  }

  @override
  cpi.QueryPlatform startAtDocument(Iterable<dynamic> orders, Iterable<dynamic> values) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['startAt'] = values.toList(),
    );
  }

  @override
  cpi.QueryPlatform startAt(Iterable<dynamic> fields) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['startAt'] = fields.toList(),
    );
  }

  @override
  cpi.QueryPlatform where(List<List<dynamic>> conditions) {
    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)..['where'] = conditions,
    );
  }

  @override
  cpi.QueryPlatform whereFilter(cpi.FilterPlatformInterface filter) {
    final filterJson = filter.toJson();
    final parsedFilters = _extractFiltersFromJson(filterJson);

    return FirebaseFirestoreWebosQuery(
      firestore,
      _path,
      _isCollectionGroup,
      Map<String, dynamic>.from(parameters)
        ..['where'] = <List<dynamic>>[
          ...(parameters['where'] as List<List<dynamic>>? ?? const []),
          ...parsedFilters,
        ],
    );
  }

  @override
  cpi.AggregateQueryPlatform count() {
    return FirebaseFirestoreWebosAggregateQuery(this);
  }

  @override
  cpi.AggregateQueryPlatform aggregate(
    cpi.AggregateField aggregateField1, [
    cpi.AggregateField? aggregateField2,
    cpi.AggregateField? aggregateField3,
    cpi.AggregateField? aggregateField4,
    cpi.AggregateField? aggregateField5,
    cpi.AggregateField? aggregateField6,
    cpi.AggregateField? aggregateField7,
    cpi.AggregateField? aggregateField8,
    cpi.AggregateField? aggregateField9,
    cpi.AggregateField? aggregateField10,
    cpi.AggregateField? aggregateField11,
    cpi.AggregateField? aggregateField12,
    cpi.AggregateField? aggregateField13,
    cpi.AggregateField? aggregateField14,
    cpi.AggregateField? aggregateField15,
    cpi.AggregateField? aggregateField16,
    cpi.AggregateField? aggregateField17,
    cpi.AggregateField? aggregateField18,
    cpi.AggregateField? aggregateField19,
    cpi.AggregateField? aggregateField20,
    cpi.AggregateField? aggregateField21,
    cpi.AggregateField? aggregateField22,
    cpi.AggregateField? aggregateField23,
    cpi.AggregateField? aggregateField24,
    cpi.AggregateField? aggregateField25,
    cpi.AggregateField? aggregateField26,
    cpi.AggregateField? aggregateField27,
    cpi.AggregateField? aggregateField28,
    cpi.AggregateField? aggregateField29,
    cpi.AggregateField? aggregateField30,
  ]) {
    final agg = FirebaseFirestoreWebosAggregateQuery(this);
    final fields = <cpi.AggregateField>[
      aggregateField1,
      if (aggregateField2 != null) aggregateField2,
      if (aggregateField3 != null) aggregateField3,
      if (aggregateField4 != null) aggregateField4,
      if (aggregateField5 != null) aggregateField5,
      if (aggregateField6 != null) aggregateField6,
      if (aggregateField7 != null) aggregateField7,
      if (aggregateField8 != null) aggregateField8,
      if (aggregateField9 != null) aggregateField9,
      if (aggregateField10 != null) aggregateField10,
      if (aggregateField11 != null) aggregateField11,
      if (aggregateField12 != null) aggregateField12,
      if (aggregateField13 != null) aggregateField13,
      if (aggregateField14 != null) aggregateField14,
      if (aggregateField15 != null) aggregateField15,
      if (aggregateField16 != null) aggregateField16,
      if (aggregateField17 != null) aggregateField17,
      if (aggregateField18 != null) aggregateField18,
      if (aggregateField19 != null) aggregateField19,
      if (aggregateField20 != null) aggregateField20,
      if (aggregateField21 != null) aggregateField21,
      if (aggregateField22 != null) aggregateField22,
      if (aggregateField23 != null) aggregateField23,
      if (aggregateField24 != null) aggregateField24,
      if (aggregateField25 != null) aggregateField25,
      if (aggregateField26 != null) aggregateField26,
      if (aggregateField27 != null) aggregateField27,
      if (aggregateField28 != null) aggregateField28,
      if (aggregateField29 != null) aggregateField29,
      if (aggregateField30 != null) aggregateField30,
    ];
    for (final field in fields) {
      if (field is cpi.count) {
        agg.count();
      } else if (field is cpi.sum) {
        agg.sum(field.field);
      } else if (field is cpi.average) {
        agg.average(field.field);
      }
    }
    return agg;
  }

  msgs.PigeonQueryParameters _convertParameters() {
    final whereFilters = <msgs.PigeonQueryFilter>[];
    final orderByList = <msgs.PigeonQueryOrder>[];

    // Convert where clauses
    if (parameters['where'] != null) {
      for (final where in parameters['where'] as List) {
        whereFilters.add(msgs.PigeonQueryFilter(
          field: _normalizeFieldPath(where[0]),
          op: where[1] as String,
          value: where[2],
        ));
      }
    }

    // Convert orderBy clauses
    if (parameters['orderBy'] != null) {
      for (final order in parameters['orderBy'] as List) {
        orderByList.add(msgs.PigeonQueryOrder(
          field: _normalizeFieldPath(order[0]),
          descending: order[1] as bool,
        ));
      }
    }

    return msgs.PigeonQueryParameters(
      where: whereFilters.isEmpty ? null : whereFilters,
      orderBy: orderByList.isEmpty ? null : orderByList,
      limit: parameters['limit'] as int?,
      limitToLast: parameters['limitToLast'] as int?,
      startAt: parameters['startAt'] as List<Object?>?,
      startAfter: parameters['startAfter'] as List<Object?>?,
      endAt: parameters['endAt'] as List<Object?>?,
      endBefore: parameters['endBefore'] as List<Object?>?,
    );
  }

  String _normalizeFieldPath(dynamic value) {
    if (value is String) {
      return value;
    }
    if (value is cpi.FieldPathType && value == cpi.FieldPathType.documentId) {
      return '__name__';
    }
    if (value is cpi.FieldPath) {
      return value.components.join('.');
    }
    final raw = value.toString();
    if (raw == 'FieldPathType.documentId') {
      return '__name__';
    }
    return raw;
  }

  List<List<dynamic>> _extractFiltersFromJson(Map<String, Object?> filterJson) {
    final filters = <List<dynamic>>[];

    void collect(Map<String, Object?> node) {
      final fieldPath = node['fieldPath'];
      final op = node['op'];
      final value = node['value'];
      if (fieldPath != null && op is String) {
        filters.add([fieldPath, op, value]);
        return;
      }

      final queries = node['queries'];
      if (queries is List) {
        for (final query in queries) {
          if (query is Map) {
            collect(Map<String, Object?>.from(query));
          }
        }
      }
    }

    collect(filterJson);
    return filters;
  }

  String _sourceToString(cpi.Source source) {
    switch (source) {
      case cpi.Source.serverAndCache:
        return 'default';
      case cpi.Source.server:
        return 'server';
      case cpi.Source.cache:
        return 'cache';
      default:
        return 'default';
    }
  }

  Exception _convertError(dynamic error) {
    if (error is Exception) return error;
    return Exception(error.toString());
  }
}
