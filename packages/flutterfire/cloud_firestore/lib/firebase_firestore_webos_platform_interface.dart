import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'firebase_firestore_webos_method_channel.dart';

abstract class FirebaseFirestoreWebosPlatform extends PlatformInterface {
  /// Constructs a FirebaseFirestoreWebosPlatform.
  FirebaseFirestoreWebosPlatform() : super(token: _token);

  static final Object _token = Object();

  static FirebaseFirestoreWebosPlatform _instance = MethodChannelFirebaseFirestoreWebos();

  /// The default instance of [FirebaseFirestoreWebosPlatform] to use.
  ///
  /// Defaults to [MethodChannelFirebaseFirestoreWebos].
  static FirebaseFirestoreWebosPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FirebaseFirestoreWebosPlatform] when
  /// they register themselves.
  static set instance(FirebaseFirestoreWebosPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
