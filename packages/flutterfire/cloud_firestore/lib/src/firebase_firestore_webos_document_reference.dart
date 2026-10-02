import 'dart:async';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'messages.g.dart' as msgs;
import 'firebase_firestore_webos_platform.dart';
import 'firebase_firestore_webos_collection_reference.dart';
import 'firebase_firestore_webos_document_snapshot.dart';
import 'firestore_value_codec.dart';
import 'firestore_flutter_api_impl.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosDocumentReference extends DocumentReferencePlatform {
  FirebaseFirestoreWebosDocumentReference(
    FirebaseFirestorePlatform firestore,
    String path,
  ) : super(firestore, path);

  static final msgs.FirestoreHostApi _api = msgs.FirestoreHostApi();

  @override
  Future<void> delete() async {
    try {
      await _api.documentDelete(
        firestore.app.name,
        firestore.databaseId,
        path,
      );
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  Future<DocumentSnapshotPlatform> get([GetOptions options = const GetOptions()]) async {
    try {
      final pigeonOptions = msgs.PigeonGetOptions(
        source: _sourceToString(options.source),
      );

      final snapshot = await _api.documentGet(
        firestore.app.name,
        firestore.databaseId,
        path,
        pigeonOptions,
      );

      return FirebaseFirestoreWebosDocumentSnapshot(
        firestore,
        snapshot,
      );
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) {
    final controller = StreamController<DocumentSnapshotPlatform>.broadcast();
    int? listenerId;

    controller.onListen = () async {
      try {
        // Ensure the event channel is set up BEFORE starting the native
        // listener to avoid a race condition where the initial snapshot
        // fires before the Dart side is ready to receive it.
        FirestoreFlutterApiImpl.ensureDocumentListener();

        listenerId = await _api.documentAddSnapshotListener(
          firestore.app.name,
          firestore.databaseId,
          path,
          includeMetadataChanges,
        );

        // Register listener for callbacks
        FirestoreFlutterApiImpl.registerDocumentListener(
          firestore.app.name,
          firestore.databaseId,
          listenerId!,
          (snapshot, error) {
            if (error != null) {
              controller.addError(Exception(error));
            } else if (snapshot != null) {
              controller.add(FirebaseFirestoreWebosDocumentSnapshot(
                firestore,
                snapshot,
              ));
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
          FirestoreFlutterApiImpl.unregisterDocumentListener(
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
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    try {
      final pigeonOptions = msgs.PigeonSetOptions(
        merge: options?.merge ?? false,
        mergeFields: options?.mergeFields?.map((e) => e.toString()).toList(),
      );

      await _api.documentSet(
        firestore.app.name,
        firestore.databaseId,
        path,
        convertDataToPigeonMap(data),
        pigeonOptions,
      );
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  Future<void> update(Map<FieldPath, dynamic> data) async {
    try {
      final convertedData = <String, dynamic>{};
      data.forEach((key, value) {
        // Use components.join('.') instead of toString() to avoid
        // including brackets and other FieldPath formatting characters
        convertedData[key.components.join('.')] = value;
      });

      await _api.documentUpdate(
        firestore.app.name,
        firestore.databaseId,
        path,
        convertDataToPigeonMap(convertedData),
      );
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  CollectionReferencePlatform collection(String collectionPath) {
    return FirebaseFirestoreWebosCollectionReference(
      firestore,
      '$path/$collectionPath',
    );
  }

  String _sourceToString(Source source) {
    switch (source) {
      case Source.serverAndCache:
        return 'default';
      case Source.server:
        return 'server';
      case Source.cache:
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
