import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'firebase_firestore_webos_platform_interface.dart';

/// An implementation of [FirebaseFirestoreWebosPlatform] that uses method channels.
class MethodChannelFirebaseFirestoreWebos extends FirebaseFirestoreWebosPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('firebase_firestore_webos');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
