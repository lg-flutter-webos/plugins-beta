import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'messages.g.dart' as msgs;
import 'firebase_firestore_webos_document_snapshot.dart';
import 'firestore_value_codec.dart';

// ignore_for_file: require_trailing_commas

class FirebaseFirestoreWebosTransaction extends TransactionPlatform {
  FirebaseFirestoreWebosTransaction(
    this._firestore,
    this._transactionId,
  ) : super();

  final FirebaseFirestorePlatform _firestore;
  final int _transactionId;
  final List<PigeonTransactionCommand> _commands = [];
  final List<msgs.PigeonTransactionUpdate> _writes = [];
  bool _hasWritten = false;
  static final msgs.FirestoreHostApi _api = msgs.FirestoreHostApi();

  @override
  List<PigeonTransactionCommand> get commands => List<PigeonTransactionCommand>.unmodifiable(_commands);

  @override
  TransactionPlatform delete(String documentPath) {
    _hasWritten = true;
    _commands.add(PigeonTransactionCommand(
      type: PigeonTransactionType.deleteType,
      path: documentPath,
    ));
    _writes.add(msgs.PigeonTransactionUpdate(
      type: 'delete',
      path: documentPath,
    ));
    return this;
  }

  @override
  Future<DocumentSnapshotPlatform> get(String documentPath) async {
    if (_hasWritten) {
      throw StateError('Transactions require all reads to be executed before any writes.');
    }
    try {
      final snapshot = await _api.transactionGet(
        _firestore.app.name,
        _firestore.databaseId,
        _transactionId,
        documentPath,
      );
      return FirebaseFirestoreWebosDocumentSnapshot(_firestore, snapshot);
    } catch (e) {
      throw _convertError(e);
    }
  }

  @override
  TransactionPlatform set(
    String documentPath,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) {
    _hasWritten = true;
    final mergedData = <String, dynamic>{...data};
    
    if (options != null && (options.merge ?? false)) {
      mergedData['__merge__'] = true;
    }
    if (options != null && options.mergeFields != null) {
      mergedData['__mergeFields__'] =
          options.mergeFields?.map((e) => e.components).toList();
    }

    _commands.add(PigeonTransactionCommand(
      type: PigeonTransactionType.set,
      path: documentPath,
      data: mergedData,
      option: PigeonDocumentOption(
        merge: options?.merge,
        mergeFields: options?.mergeFields?.map((e) => e.components).toList(),
      ),
    ));
    _writes.add(msgs.PigeonTransactionUpdate(
      type: 'set',
      path: documentPath,
      data: convertDataToPigeonMap(mergedData),
    ));
    return this;
  }

  @override
  TransactionPlatform update(
    String documentPath,
    Map<String, dynamic> data,
  ) {
    _hasWritten = true;
    _commands.add(PigeonTransactionCommand(
      type: PigeonTransactionType.update,
      path: documentPath,
      data: data,
    ));
    _writes.add(msgs.PigeonTransactionUpdate(
      type: 'update',
      path: documentPath,
      data: convertDataToPigeonMap(data),
    ));
    return this;
  }

  List<msgs.PigeonTransactionUpdate> getPendingWrites() {
    return _writes;
  }

  Exception _convertError(dynamic error) {
    if (error is Exception) return error;
    return Exception(error.toString());
  }
}
