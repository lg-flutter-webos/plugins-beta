import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'messages.g.dart' as msgs;
import 'firestore_value_codec.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosDocumentSnapshot extends DocumentSnapshotPlatform {
  FirebaseFirestoreWebosDocumentSnapshot(
    FirebaseFirestorePlatform firestore,
    this._pigeonSnapshot,
  ) : super(
          firestore,
          _pigeonSnapshot.path,
          _convertMapFromPigeon(_pigeonSnapshot.data),
          PigeonSnapshotMetadata(
            hasPendingWrites: _pigeonSnapshot.metadata.hasPendingWrites,
            isFromCache: _pigeonSnapshot.metadata.isFromCache,
          ),
        );

  final msgs.PigeonDocumentSnapshot _pigeonSnapshot;

  static Map<String?, Object?>? _convertMapFromPigeon(Map<String?, Object?>? map) {
    if (map == null) return null;
    final result = <String?, Object?>{};
    map.forEach((key, value) {
      result[key] = convertValueFromPigeon(value);
    });
    return result;
  }

  @override
  Map<String, dynamic>? data() {
    if (!exists) return null;
    final raw = _pigeonSnapshot.data;
    if (raw == null) return null;
    final result = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key != null) {
        result[key] = convertValueFromPigeon(value);
      }
    });
    return result;
  }

  @override
  bool get exists => _pigeonSnapshot.exists;
}
