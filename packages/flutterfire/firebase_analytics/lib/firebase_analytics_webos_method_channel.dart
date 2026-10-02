import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'firebase_analytics_webos_platform_interface.dart';

/// An implementation of [FirebaseAnalyticsWebosPlatform] that uses method channels.
class MethodChannelFirebaseAnalyticsWebos extends FirebaseAnalyticsWebosPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('firebase_analytics_webos');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
