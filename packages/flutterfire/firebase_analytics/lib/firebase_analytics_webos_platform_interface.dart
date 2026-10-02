import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'firebase_analytics_webos_method_channel.dart';

abstract class FirebaseAnalyticsWebosPlatform extends PlatformInterface {
  /// Constructs a FirebaseAnalyticsWebosPlatform.
  FirebaseAnalyticsWebosPlatform() : super(token: _token);

  static final Object _token = Object();

  static FirebaseAnalyticsWebosPlatform _instance = MethodChannelFirebaseAnalyticsWebos();

  /// The default instance of [FirebaseAnalyticsWebosPlatform] to use.
  ///
  /// Defaults to [MethodChannelFirebaseAnalyticsWebos].
  static FirebaseAnalyticsWebosPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FirebaseAnalyticsWebosPlatform] when
  /// they register themselves.
  static set instance(FirebaseAnalyticsWebosPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
