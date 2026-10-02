import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'messages.g.dart' as msgs;
import 'firebase_firestore_webos_document_snapshot.dart';
import 'firebase_firestore_webos_document_change.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosQuerySnapshot extends QuerySnapshotPlatform {
  FirebaseFirestoreWebosQuerySnapshot(
    FirebaseFirestorePlatform firestore,
    this._pigeonSnapshot,
  ) : super(
          _convertDocuments(firestore, _pigeonSnapshot.documents),
          _convertDocumentChanges(firestore, _pigeonSnapshot.documentChanges),
          SnapshotMetadataPlatform(
            _pigeonSnapshot.metadata.hasPendingWrites,
            _pigeonSnapshot.metadata.isFromCache,
          ),
        );

  final msgs.PigeonQuerySnapshot _pigeonSnapshot;

  @override
  SnapshotMetadataPlatform get metadata {
    return SnapshotMetadataPlatform(
      _pigeonSnapshot.metadata.hasPendingWrites,
      _pigeonSnapshot.metadata.isFromCache,
    );
  }

  static List<DocumentSnapshotPlatform> _convertDocuments(
    FirebaseFirestorePlatform firestore,
    List<msgs.PigeonDocumentSnapshot?> documents,
  ) {
    return documents
        .where((doc) => doc != null)
        .map((doc) => FirebaseFirestoreWebosDocumentSnapshot(firestore, doc!))
        .toList();
  }

  static List<DocumentChangePlatform> _convertDocumentChanges(
    FirebaseFirestorePlatform firestore,
    List<msgs.PigeonDocumentChange?> changes,
  ) {
    return changes
        .where((change) => change != null)
        .map((change) => FirebaseFirestoreWebosDocumentChange(firestore, change!))
        .toList();
  }
}
