import 'dart:async';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'messages.g.dart' as msgs;
import 'firebase_firestore_webos_document_reference.dart';
import 'firebase_firestore_webos_collection_reference.dart';
import 'firebase_firestore_webos_query.dart';
import 'firebase_firestore_webos_write_batch.dart';
import 'firebase_firestore_webos_transaction.dart';
import 'firestore_flutter_api_impl.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosImpl extends FirebaseFirestorePlatform {
  static final msgs.FirestoreHostApi _api = msgs.FirestoreHostApi();
  static final Map<String, FirebaseFirestoreWebosImpl> _instances = {};
  
  FirebaseFirestoreWebosImpl({
    required FirebaseApp app,
    required String databaseId,
  }) : super(appInstance: app, databaseChoice: databaseId) {
    final key = _getInstanceKey(app.name, databaseId);
    _instances[key] = this;

    // Setup Flutter API for callbacks
    msgs.FirestoreFlutterApi.setup(FirestoreFlutterApiImpl());
    // Initialize Firestore
    _api.initializeFirestore(app.name, databaseId);
  }

  static String _getInstanceKey(String appName, String databaseId) {
    return '${appName}_$databaseId';
  }

  static FirebaseFirestoreWebosImpl? getInstance(String appName, String databaseId) {
    return _instances[_getInstanceKey(appName, databaseId)];
  }

  Settings? _settings;

  @override
  Settings get settings {
    return _settings ??
        Settings(
          persistenceEnabled: true,
          host: 'firestore.googleapis.com',
          sslEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
  }

  @override
  set settings(Settings settings) {
    _settings = settings;
    final pigeonSettings = msgs.PigeonFirestoreSettings(
      host: settings.host ?? 'firestore.googleapis.com',
      sslEnabled: settings.sslEnabled ?? true,
      persistenceEnabled: settings.persistenceEnabled ?? true,
      cacheSizeBytes: settings.cacheSizeBytes ?? Settings.CACHE_SIZE_UNLIMITED,
    );
    _api.setSettings(app.name, databaseId, pigeonSettings);
  }

  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) {
    return FirebaseFirestoreWebosImpl(app: app, databaseId: databaseId);
  }

  @override
  WriteBatchPlatform batch() {
    return FirebaseFirestoreWebosWriteBatch(this);
  }

  @override
  Future<void> clearPersistence() async {
    try {
      await _api.clearPersistence(app.name, databaseId);
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  CollectionReferencePlatform collection(String collectionPath) {
    return FirebaseFirestoreWebosCollectionReference(this, collectionPath);
  }

  @override
  QueryPlatform collectionGroup(String collectionPath) {
    return FirebaseFirestoreWebosQuery(
      this,
      collectionPath,
      true,
      <String, dynamic>{},
    );
  }

  @override
  Future<void> disableNetwork() async {
    try {
      await _api.disableNetwork(app.name, databaseId);
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  DocumentReferencePlatform doc(String documentPath) {
    return FirebaseFirestoreWebosDocumentReference(this, documentPath);
  }

  @override
  Future<void> enableNetwork() async {
    try {
      await _api.enableNetwork(app.name, databaseId);
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  Stream<void> snapshotsInSync() {
    // TODO: Implement if C++ SDK supports it
    return Stream<void>.empty();
  }

  @override
  LoadBundleTaskPlatform loadBundle(Uint8List bundle) {
    throw UnimplementedError('loadBundle() is not supported on WebOS');
  }

  @override
  Future<QuerySnapshotPlatform> namedQueryGet(
    String name, {
    GetOptions options = const GetOptions(),
  }) {
    throw UnimplementedError('namedQueryGet() is not supported on WebOS');
  }

  int _transactionIdCounter = 0;

  @override
  Future<T?> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (timeout.inMilliseconds <= 0) {
      throw ArgumentError.value(timeout, 'timeout', 'Transaction timeout must be more than 0 milliseconds.');
    }
    if (maxAttempts < 1) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'Transaction maxAttempts must be at least 1.');
    }

    final transactionId = _transactionIdCounter++;
    final session = _TransactionSession<T>(
      appName: app.name,
      databaseId: databaseId,
      transactionId: transactionId,
    );

    FirestoreFlutterApiImpl.registerTransactionListener(
      app.name,
      databaseId,
      transactionId,
      () {
        unawaited(_handleTransactionAttempt(session, transactionHandler));
      },
    );

    session.timeoutTimer = Timer(timeout, () {
      if (session.closed) {
        return;
      }
      session.closed = true;
      session.timeoutTimer?.cancel();
      FirestoreFlutterApiImpl.unregisterTransactionListener(
        session.appName,
        session.databaseId,
        session.transactionId,
      );

      if (!session.resultCompleter.isCompleted) {
        session.resultCompleter.completeError(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'deadline-exceeded',
            message:
                'Transaction timed out after ${timeout.inMilliseconds} milliseconds.',
          ),
        );
      }

      if (!session.responseSentToNative) {
        unawaited(
          _api.transactionComplete(
            session.appName,
            session.databaseId,
            session.transactionId,
            msgs.PigeonTransactionResult.failure,
            null,
          ).catchError((_) {}),
        );
      }
    });

    unawaited(
      _api
          .runTransaction(
            session.appName,
            session.databaseId,
            session.transactionId,
            maxAttempts,
          )
          .then((_) {
        if (session.closed) {
          return;
        }
        session.closed = true;
        session.timeoutTimer?.cancel();
        FirestoreFlutterApiImpl.unregisterTransactionListener(
          session.appName,
          session.databaseId,
          session.transactionId,
        );
        if (!session.resultCompleter.isCompleted) {
          session.resultCompleter.complete(session.lastResult);
        }
      }).catchError((Object error, StackTrace stackTrace) {
        if (session.closed) {
          return;
        }
        session.closed = true;
        session.timeoutTimer?.cancel();
        FirestoreFlutterApiImpl.unregisterTransactionListener(
          session.appName,
          session.databaseId,
          session.transactionId,
        );
        if (!session.resultCompleter.isCompleted) {
          session.resultCompleter.completeError(
            _convertError(error),
            stackTrace,
          );
        }
      }),
    );

    return session.resultCompleter.future;
  }

  Future<void> _handleTransactionAttempt<T>(
    _TransactionSession<T> session,
    TransactionHandler<T> transactionHandler,
  ) async {
    if (session.closed) {
      return;
    }

    session.responseSentToNative = false;

    final transaction = FirebaseFirestoreWebosTransaction(
      this,
      session.transactionId,
    );

    try {
      final result = await transactionHandler(transaction);
      if (session.closed) {
        return;
      }

      session.lastResult = result;
      session.responseSentToNative = true;
      try {
        await _api.transactionComplete(
          session.appName,
          session.databaseId,
          session.transactionId,
          msgs.PigeonTransactionResult.success,
          transaction.getPendingWrites(),
        );
      } catch (error, stackTrace) {
        if (session.closed) {
          return;
        }

        session.closed = true;
        session.timeoutTimer?.cancel();
        FirestoreFlutterApiImpl.unregisterTransactionListener(
          session.appName,
          session.databaseId,
          session.transactionId,
        );

        if (!session.resultCompleter.isCompleted) {
          session.resultCompleter.completeError(
            _convertError(error),
            stackTrace,
          );
        }
      }
    } catch (error, stackTrace) {
      if (session.closed) {
        return;
      }

      session.closed = true;
      session.timeoutTimer?.cancel();
      FirestoreFlutterApiImpl.unregisterTransactionListener(
        session.appName,
        session.databaseId,
        session.transactionId,
      );

      try {
        session.responseSentToNative = true;
        await _api.transactionComplete(
          session.appName,
          session.databaseId,
          session.transactionId,
          msgs.PigeonTransactionResult.failure,
          null,
        );
      } catch (_) {
        // Ignore cleanup errors; the local result future will still surface
        // the original transaction failure.
      }

      if (!session.resultCompleter.isCompleted) {
        session.resultCompleter.completeError(error, stackTrace);
      }
    }
  }

  @override
  Future<void> terminate() async {
    try {
      await _api.terminate(app.name, databaseId);
      final key = _getInstanceKey(app.name, databaseId);
      _instances.remove(key);
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  Future<void> waitForPendingWrites() async {
    try {
      await _api.waitForPendingWrites(app.name, databaseId);
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  Future<void> useEmulator(String host, int port) async {
    try {
      await _api.useEmulator(app.name, databaseId, host, port);
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  Future<void> setLoggingEnabled(bool enabled) async {
    try {
      await _api.setLoggingEnabled(app.name, databaseId, enabled);
    } catch (e) {
      throw _convertError(e);
    }
  }

  Exception _convertError(dynamic error) {
    if (error is Exception) {
      return error;
    }
    return Exception(error.toString());
  }
}

class _TransactionSession<T> {
  _TransactionSession({
    required this.appName,
    required this.databaseId,
    required this.transactionId,
  });

  final String appName;
  final String databaseId;
  final int transactionId;
  final Completer<T?> resultCompleter = Completer<T?>();
  Timer? timeoutTimer;
  bool closed = false;
  bool responseSentToNative = false;
  T? lastResult;
}
