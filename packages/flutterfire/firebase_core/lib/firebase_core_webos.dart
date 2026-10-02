// ignore_for_file: require_trailing_commas
import 'dart:async';

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:path_provider_webos/path_provider_webos.dart';
import 'firebase_app_webos.dart';
import 'src/messages.g.dart';

class FirebaseCoreWebos extends FirebasePlatform {
  final FirebaseCoreHostApi _api = FirebaseCoreHostApi();
  final Map<String, FirebaseAppPlatform> _appCache = {};

  /// Runs the data-directory redirect once for the whole process.
  Future<void>? _dataDirectoryFuture;

  static void registerWith() {
    FirebasePlatform.instance = FirebaseCoreWebos();
  }

  FirebaseCoreWebos() : super() {}

  /// Redirects the Firebase C++ SDK's on-disk storage to a writable location.
  ///
  /// Resolves the app support directory via [PathProviderWebOS] and passes it
  /// to the native side, which sets `XDG_DATA_HOME`/`HOME` before any
  /// `firebase::App::Create()` call. Centralizing this in core means every
  /// Firebase product (Firestore, Remote Config, etc.) inherits a
  /// JAIL-writable data directory without per-plugin wiring.
  ///
  /// The result is cached so concurrent/repeat calls share a single native
  /// invocation, and it always completes before [initializeApp] proceeds.
  Future<void> _ensureDataDirectory() {
    return _dataDirectoryFuture ??= _doEnsureDataDirectory();
  }

  Future<void> _doEnsureDataDirectory() async {
    try {
      final PathProviderWebOS pathProvider = PathProviderWebOS();
      final String? appSupportPath =
          await pathProvider.getApplicationSupportPath();
      if (appSupportPath != null && appSupportPath.isNotEmpty) {
        await _api.setDataDirectory(appSupportPath);
      }
      // Otherwise fall back to the Firebase SDK's default data directory.
    } catch (_) {
      // Fall back to the SDK default location if path resolution fails.
    }
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    if (options == null) {
      throw ArgumentError('FirebaseOptions are required on WebOS.');
    }

    final appName = name ?? defaultFirebaseAppName;

    if (_appCache.containsKey(appName)) {
      return _appCache[appName]!;
    }

    // Redirect the SDK's data directory to a writable path BEFORE the native
    // initializeApp triggers firebase::App::Create().
    await _ensureDataDirectory();

    final pigeonOptions = FirebaseOptionsPigeon(
      apiKey: options.apiKey,
      appId: options.appId,
      projectId: options.projectId,
      messagingSenderId: options.messagingSenderId,
      storageBucket: options.storageBucket,
      databaseUrl: options.databaseURL,
    );

    try {
      await _api.initializeApp(appName, pigeonOptions).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException("Firebase initializeApp timed out after 30 seconds");
        },
      );
    } on TimeoutException catch (e) {
      rethrow;
    } catch (e) {
      rethrow;
    }

    final appPlatform = FirebaseAppWebos(appName, options, _api, _appCache);
    _appCache[appName] = appPlatform;

    return appPlatform;
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    final cached = _appCache[name];

    if (cached == null) {
      throw FirebaseException(
        plugin: 'core',
        code: 'no-app',
        message:
            'No Firebase App \'$name\' has been created. '
            'Call Firebase.initializeApp() first.',
      );
    }

    return cached;
  }

  @override
  List<FirebaseAppPlatform> get apps => _appCache.values.toList();

  @override
  Future<void> delete(String name) async {
    await _api.deleteApp(name);
    _appCache.remove(name);
  }

}