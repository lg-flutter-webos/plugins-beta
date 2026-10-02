import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'messages.g.dart' as msgs;
import 'firestore_value_codec.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosWriteBatch extends WriteBatchPlatform {
  FirebaseFirestoreWebosWriteBatch(this._firestore) : super();

  final FirebaseFirestorePlatform _firestore;
  final List<msgs.PigeonTransactionUpdate> _writes = [];
  static final msgs.FirestoreHostApi _api = msgs.FirestoreHostApi();

  @override
  Future<void> commit() async {
    try {
      await _api.batchCommit(
        _firestore.app.name,
        _firestore.databaseId,
        _writes,
      );
      _writes.clear();
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  void delete(String documentPath) {
    _writes.add(msgs.PigeonTransactionUpdate(
      type: 'delete',
      path: documentPath,
    ));
  }

  @override
  void set(
    String documentPath,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) {
    final mergedData = <String, dynamic>{...data};
    
    if (options != null && (options.merge ?? false)) {
      mergedData['__merge__'] = true;
    }
    if (options != null && options.mergeFields != null) {
      mergedData['__mergeFields__'] = options.mergeFields;
    }

    _writes.add(msgs.PigeonTransactionUpdate(
      type: 'set',
      path: documentPath,
      data: convertDataToPigeonMap(mergedData),
    ));
  }

  @override
  void update(
    String documentPath,
    Map<String, dynamic> data,
  ) {
    _writes.add(msgs.PigeonTransactionUpdate(
      type: 'update',
      path: documentPath,
      data: convertDataToPigeonMap(data),
    ));
  }

  Exception _convertError(dynamic error) {
    if (error is Exception) return error;
    return Exception(error.toString());
  }
}
