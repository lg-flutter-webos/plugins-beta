import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

import 'src/firebase_firestore_webos_platform.dart';

export 'src/firebase_firestore_webos_platform.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebos extends FirebaseFirestorePlatform {
  FirebaseFirestoreWebos._({
    required FirebaseApp app,
    required String databaseId,
  }) : super(appInstance: app, databaseChoice: databaseId);

  static void registerWith() {
    FirebaseFirestorePlatform.instance = _BootstrapFirebaseFirestoreWebos();
  }

  static FirebaseFirestoreWebos instanceFor({
    required FirebaseApp app,
    required String databaseId,
  }) {
    return FirebaseFirestoreWebos._(
      app: app,
      databaseId: databaseId,
    );
  }
}

class _BootstrapFirebaseFirestoreWebos extends FirebaseFirestorePlatform {
  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) {
    return FirebaseFirestoreWebosImpl(app: app, databaseId: databaseId);
  }
}
