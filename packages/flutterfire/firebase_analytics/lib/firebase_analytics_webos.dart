import 'dart:convert';
import 'dart:io';
import 'package:firebase_analytics_platform_interface/firebase_analytics_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'analytics_storage.dart';

class FirebaseAnalyticsWebos
    extends FirebaseAnalyticsPlatform {
  FirebaseAnalyticsWebos({
    FirebaseApp? app,
  })  : _app = app,
        super(appInstance: app);

  FirebaseAnalyticsWebos._empty()
      : _app = null,
        super(appInstance: null);

  final FirebaseApp? _app;

  FirebaseApp get app =>
      _app ?? Firebase.app();

  static String? _apiSecret;
  static String? _measurementId;
  static bool _analyticsEnabled = true;
  static String? _userId;
  static final Map<String, Object?> _defaultEventParameters = {};
  /// Configure analytics before usage.
  ///
  /// Example:
  /// FirebaseAnalyticsWebos.configure(
  ///   apiSecret: 'YOUR_SECRET',
  /// );
  static void configure({
    required String apiSecret,
    required String measurementId,
  }) {
    if (apiSecret.trim().isEmpty) {
      throw ArgumentError(
        'apiSecret cannot be empty.',
      );
    }
    if (measurementId.trim().isEmpty) {
      throw ArgumentError(
        'measurementId cannot be empty.',
      );
    }
    _apiSecret = apiSecret;
    _measurementId = measurementId;
  }

  /// Plugin registration
  static void registerWith() {
    FirebaseAnalyticsPlatform.instance =
        FirebaseAnalyticsWebos._empty();
  }

  @override
  FirebaseAnalyticsPlatform delegateFor({
    required FirebaseApp app,
    Map<String, dynamic>? webOptions,
  }) {
    return FirebaseAnalyticsWebos(
      app: app,
    );
  }
  /// Validates an event name according to GA4 rules:
  bool _isValidEventName(String name) {
    if (name.isEmpty) {
      return false;
    }

    if (name.length > 40) {
      return false;
    }

    if (!RegExp(r'^[A-Za-z]').hasMatch(name)) {
      return false;
    }

    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$')
        .hasMatch(name)) {
      return false;
    }

    const reservedPrefixes = [
      'firebase_',
      'google_',
      'ga_',
    ];

    for (final prefix in reservedPrefixes) {
      if (name.startsWith(prefix)) {
        return false;
      }
    }

    return true;
  }

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object?>? parameters,
    AnalyticsCallOptions? callOptions,
  }) async {
    if (!_analyticsEnabled) {
      return;
    }
    try {
      // Validate event name before proceeding
      if (!_isValidEventName(name)) {
        return;
      }
      final measurementId =
          _measurementId;
      if (measurementId == null ||
          measurementId.isEmpty) {
        return;
      }
      if (_apiSecret == null ||
          _apiSecret!.isEmpty) {
        return;
      }
      final clientId =
          await AnalyticsStorage.getClientId();
      final mergedParams =
          <String, Object?>{
        ..._defaultEventParameters,
        ...?parameters,
      };
      // GA4 allows a maximum of 25 event parameters.
      // We take the first 25 entries after merging.
      final mergedEntries =
          mergedParams.entries.toList();
      final trimmedEntries =
          mergedEntries.take(25);
      final cleanedParams =
          <String, Object?>{};
      trimmedEntries.forEach((entry) {
        final key = entry.key;
        final value = entry.value;
        // GA4 Measurement Protocol only accepts:
        //   String, int, double (as JSON string/number)
        if (value is String ||
            value is int ||
            value is double) {
          cleanedParams[key] = value;
        } else if (value is bool) {
          // GA4 does not support boolean values;
          // convert to int (0 or 1).
          cleanedParams[key] =
              value ? 1 : 0;
        }
        // null and other types are silently excluded
      });
      final payload =
          <String, dynamic>{
        'client_id': clientId,
        'events': [
          {
            'name': name,
            'params': cleanedParams,
          }
        ],
      };
      if (_userId != null &&
          _userId!.isNotEmpty) {
        payload['user_id'] = _userId;
      }

      final uri = Uri.parse(
        'https://www.google-analytics.com/mp/collect'
        '?measurement_id=$measurementId'
        '&api_secret=$_apiSecret',
      );
      final httpClient = HttpClient();
      try {
        final request =
            await httpClient.postUrl(uri);
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        request.write(
          jsonEncode(payload),
        );
        final response =
            await request
                .close()
                .timeout(
                  const Duration(
                    seconds: 10,
                  ),
                );
      } finally {
        httpClient.close();
      }
    } catch (e, stackTrace) {
    }
  }

  @override
  Future<void> setUserId({
    String? id,
    AnalyticsCallOptions? callOptions,
  }) async {
    _userId = id;
  }


  @override
  Future<void> setDefaultEventParameters(
    Map<String, Object?>? defaultParameters,
  ) async {
    _defaultEventParameters.clear();
    if (defaultParameters != null) {
      _defaultEventParameters.addAll(
        defaultParameters,
      );
    }
  }

  @override
  Future<void> setAnalyticsCollectionEnabled(
    bool enabled,
  ) async {
    _analyticsEnabled = enabled;
  }

  @override
  Future<void> resetAnalyticsData() async {
    _userId = null;

    _defaultEventParameters.clear();

  }

  @override
  Future<bool> isSupported() async {
    return true;
  }

  @override
  Future<String?> getAppInstanceId() async {
    return AnalyticsStorage.getClientId();
  }

  @override
  Future<int?> getSessionId() async {
    return null;
  }

  @override
  Future<void> setSessionTimeoutDuration(
    Duration timeout,
  ) async {}

  @override
  Future<void> setConsent({
    bool? adStorageConsentGranted,
    bool? analyticsStorageConsentGranted,
    bool? adPersonalizationSignalsConsentGranted,
    bool? adUserDataConsentGranted,
    bool? functionalityStorageConsentGranted,
    bool? personalizationStorageConsentGranted,
    bool? securityStorageConsentGranted,
  }) async {}

  @override
  Future<void>
      initiateOnDeviceConversionMeasurement({
    String? emailAddress,
    String? phoneNumber,
    String? hashedEmailAddress,
    String? hashedPhoneNumber,
  }) async {}

  @override
  Future<void> logTransaction({
    required String transactionId,
  }) async {
    await logEvent(
      name: 'purchase',
      parameters: {
        'transaction_id':
            transactionId,
      },
    );
  }
}