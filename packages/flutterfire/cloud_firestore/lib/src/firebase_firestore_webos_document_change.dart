import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'messages.g.dart' as msgs;
import 'firebase_firestore_webos_document_snapshot.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosDocumentChange extends DocumentChangePlatform {
  FirebaseFirestoreWebosDocumentChange(
    FirebaseFirestorePlatform firestore,
    this._pigeonChange,
  ) : super(
          _convertType(_pigeonChange.type),
          _pigeonChange.oldIndex,
          _pigeonChange.newIndex,
          FirebaseFirestoreWebosDocumentSnapshot(firestore, _pigeonChange.document),
        );

  final msgs.PigeonDocumentChange _pigeonChange;

  static DocumentChangeType _convertType(msgs.PigeonDocumentChangeType type) {
    switch (type) {
      case msgs.PigeonDocumentChangeType.added:
        return DocumentChangeType.added;
      case msgs.PigeonDocumentChangeType.modified:
        return DocumentChangeType.modified;
      case msgs.PigeonDocumentChangeType.removed:
        return DocumentChangeType.removed;
    }
  }
}
