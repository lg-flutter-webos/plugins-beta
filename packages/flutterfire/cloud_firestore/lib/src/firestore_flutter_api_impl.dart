import 'dart:async';

import 'package:flutter/services.dart';

import 'messages.g.dart' as msgs;

// ignore_for_file: require_trailing_commas

typedef DocumentSnapshotCallback = void Function(
  msgs.PigeonDocumentSnapshot? snapshot,
  String? error,
);

typedef QuerySnapshotCallback = void Function(
  msgs.PigeonQuerySnapshot? snapshot,
  String? error,
);

typedef TransactionCallback = void Function();

class FirestoreFlutterApiImpl extends msgs.FirestoreFlutterApi {
  static final Map<String, Map<int, DocumentSnapshotCallback>> _documentListeners = {};
  static final Map<String, Map<int, QuerySnapshotCallback>> _queryListeners = {};
  static final Map<String, Map<int, TransactionCallback>> _transactionListeners = {};

  static StreamSubscription<dynamic>? _documentSnapshotSubscription;
  static StreamSubscription<dynamic>? _querySnapshotSubscription;

  static void _ensureDocumentSnapshotListener() {
    if (_documentSnapshotSubscription != null) return;
    final eventChannel = EventChannel(
      'firebase_firestore_webos/document_snapshot_events',
      StandardMethodCodec(msgs.FirestoreHostApi.pigeonChannelCodec as StandardMessageCodec),
    );
    _documentSnapshotSubscription = eventChannel.receiveBroadcastStream().listen((dynamic event) {
      final map = event as Map<dynamic, dynamic>;
      final appName = map['appName'] as String;
      final databaseId = map['databaseId'] as String;
      final listenerId = map['listenerId'] as int;
      final key = '${appName}_$databaseId';
      final callback = _documentListeners[key]?[listenerId];
      if (callback == null) return;

      final error = map['error'] as String?;
      if (error != null && error.isNotEmpty) {
        callback(null, error);
      } else {
        final snapshot = map['snapshot'] as msgs.PigeonDocumentSnapshot?;
        callback(snapshot, null);
      }
    });
  }

  static void _ensureQuerySnapshotListener() {
    if (_querySnapshotSubscription != null) return;
    final eventChannel = EventChannel(
      'firebase_firestore_webos/query_snapshot_events',
      StandardMethodCodec(msgs.FirestoreHostApi.pigeonChannelCodec as StandardMessageCodec),
    );
    _querySnapshotSubscription = eventChannel.receiveBroadcastStream().listen((dynamic event) {
      final map = event as Map<dynamic, dynamic>;
      final appName = map['appName'] as String;
      final databaseId = map['databaseId'] as String;
      final listenerId = map['listenerId'] as int;
      final key = '${appName}_$databaseId';
      final callback = _queryListeners[key]?[listenerId];
      if (callback == null) return;

      final error = map['error'] as String?;
      if (error != null && error.isNotEmpty) {
        callback(null, error);
      } else {
        final snapshot = map['snapshot'] as msgs.PigeonQuerySnapshot?;
        callback(snapshot, null);
      }
    });
  }

  static void ensureDocumentListener() {
    _ensureDocumentSnapshotListener();
  }

  static void registerDocumentListener(
    String appName,
    String databaseId,
    int listenerId,
    DocumentSnapshotCallback callback,
  ) {
    final key = '${appName}_$databaseId';
    _documentListeners.putIfAbsent(key, () => {});
    _documentListeners[key]![listenerId] = callback;
    _ensureDocumentSnapshotListener();
  }

  static void unregisterDocumentListener(
    String appName,
    String databaseId,
    int listenerId,
  ) {
    final key = '${appName}_$databaseId';
    _documentListeners[key]?.remove(listenerId);
  }

  static void ensureQueryListener() {
    _ensureQuerySnapshotListener();
  }

  static void registerQueryListener(
    String appName,
    String databaseId,
    int listenerId,
    QuerySnapshotCallback callback,
  ) {
    final key = '${appName}_$databaseId';
    _queryListeners.putIfAbsent(key, () => {});
    _queryListeners[key]![listenerId] = callback;
    _ensureQuerySnapshotListener();
  }

  static void unregisterQueryListener(
    String appName,
    String databaseId,
    int listenerId,
  ) {
    final key = '${appName}_$databaseId';
    _queryListeners[key]?.remove(listenerId);
  }

  static void registerTransactionListener(
    String appName,
    String databaseId,
    int transactionId,
    TransactionCallback callback,
  ) {
    final key = '${appName}_$databaseId';
    _transactionListeners.putIfAbsent(key, () => {});
    _transactionListeners[key]![transactionId] = callback;
  }

  static void unregisterTransactionListener(
    String appName,
    String databaseId,
    int transactionId,
  ) {
    final key = '${appName}_$databaseId';
    _transactionListeners[key]?.remove(transactionId);
  }

  @override
  void onTransactionCallback(
    String appName,
    String databaseId,
    int transactionId,
  ) {
    final key = '${appName}_$databaseId';
    final callback = _transactionListeners[key]?[transactionId];
    if (callback == null) {
      return;
    }
    callback();
  }
}
