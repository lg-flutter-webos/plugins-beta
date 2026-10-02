import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics_platform_interface/firebase_analytics_platform_interface.dart';

import 'analytics_results_screen.dart';

/// GA4 credentials (same values used to configure the plugin in main.dart).
/// The example uses these to independently validate event payloads against
/// GA4's debug endpoint, since the plugin sends to the production endpoint and
/// silently discards the response.
const String kMeasurementId = 'REPLACE_ME';
const String kApiSecret = 'REPLACE_ME';

const Duration _kHttpTimeout = Duration(seconds: 12);

// ─── Result model (plain data) ───────────────────────────────────────────────

class AnalyticsResult {
  final String name;
  final bool passed;
  final String detail;
  AnalyticsResult(this.name, this.passed, this.detail);
}

// ─── A test event definition ─────────────────────────────────────────────────

class _TestEvent {
  final String label;
  final String name;
  final Map<String, Object> params;
  const _TestEvent(this.label, this.name, this.params);
}

const List<_TestEvent> _testEvents = [
  _TestEvent('Simple event', 'test_event', <String, Object>{}),
  _TestEvent('Event with params', 'movie_played_custom', <String, Object>{
    'movie_name': 'xyz',
    'language': 'english',
    'duration_sec': 120,
    'is_premium': true, // bool -> 1
  }),
  _TestEvent('Purchase event', 'custom_purchase', <String, Object>{
    'transaction_id': 'txn_1001',
    'value': 299,
    'currency': 'INR',
  }),
  _TestEvent('Ad error event', 'ad_error', <String, Object>{
    'error_message': 'Ad failed to load',
    'is_ad_crash': 1,
    'ad_type': 'banner',
    'video_title': 'Breaking News',
  }),
];

// ─── Phases ──────────────────────────────────────────────────────────────────

enum _Phase { intro, done }

class AnalyticsValidationScreen extends StatefulWidget {
  const AnalyticsValidationScreen({super.key});

  @override
  State<AnalyticsValidationScreen> createState() =>
      _AnalyticsValidationScreenState();
}

class _AnalyticsValidationScreenState extends State<AnalyticsValidationScreen> {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  _Phase _phase = _Phase.intro;
  String _instruction =
      'This validates Firebase Analytics (GA4) on webOS.\n\n'
      'Each test event is checked against the GA4 debug endpoint for a valid '
      'payload, and also sent live so it appears in GA4 DebugView.\n\n'
      'Press Start to begin.';
  String _button = 'Start';
  bool _busy = false;

  final List<AnalyticsResult> _results = [];

  void _set({String? instruction, String? button}) {
    if (!mounted) return;
    setState(() {
      if (instruction != null) _instruction = instruction;
      if (button != null) _button = button;
    });
  }

  Future<void> _onAction() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_phase == _Phase.intro) {
        await _runAll();
      } else {
        _openResults();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAll() async {
    _results.clear();

    // ── Config check ──
    _set(instruction: 'Checking configuration...');
    final configured = kMeasurementId.isNotEmpty && kApiSecret.isNotEmpty;
    _results.add(AnalyticsResult('Configuration', configured,
        configured ? 'measurementId + apiSecret set' : 'Missing credentials'));

    // ── Client ID ──
    _set(instruction: 'Reading client ID...');
    try {
      final id = await FirebaseAnalyticsPlatform.instance
          .getAppInstanceId()
          .timeout(_kHttpTimeout);
      final ok = id != null && id.isNotEmpty;
      _results.add(AnalyticsResult(
          'Client ID', ok, ok ? 'clientId=$id' : 'No client ID returned'));
    } catch (e) {
      _results.add(AnalyticsResult('Client ID', false, '$e'));
    }

    // ── Event name validation (local GA4 rules) ──
    _set(instruction: 'Validating event names...');
    for (final ev in _testEvents) {
      final valid = _isValidEventName(ev.name);
      _results.add(AnalyticsResult('Name: ${ev.name}', valid,
          valid ? 'Valid GA4 event name' : 'INVALID per GA4 rules'));
    }

    // ── Payload validation against GA4 debug endpoint + live send ──
    final clientId = await _safeClientId();
    for (final ev in _testEvents) {
      _set(instruction: 'Validating & sending "${ev.name}"...');

      // 1) Debug-endpoint validation (real feedback).
      try {
        final messages =
            await _validateWithDebugEndpoint(clientId, ev).timeout(_kHttpTimeout);
        if (messages.isEmpty) {
          _results.add(AnalyticsResult(
              'Validate: ${ev.name}', true, 'GA4 debug: no validation messages'));
        } else {
          _results.add(AnalyticsResult(
              'Validate: ${ev.name}', false, 'GA4 debug: ${messages.join('; ')}'));
        }
      } on TimeoutException {
        _results.add(AnalyticsResult('Validate: ${ev.name}', false,
            'Debug endpoint timed out after ${_kHttpTimeout.inSeconds}s'));
      } catch (e) {
        _results.add(AnalyticsResult('Validate: ${ev.name}', false, '$e'));
      }

      // 2) Live send via the plugin (so it shows in DebugView). The plugin
      //    swallows errors, so this can only be reported as "dispatched".
      try {
        await _analytics
            .logEvent(name: ev.name, parameters: ev.params)
            .timeout(_kHttpTimeout);
        _results.add(
            AnalyticsResult('Send: ${ev.name}', true, 'Dispatched via plugin'));
      } catch (e) {
        _results.add(AnalyticsResult('Send: ${ev.name}', false, '$e'));
      }
    }

    // ── Collection toggle ──
    _set(instruction: 'Testing collection enable/disable...');
    try {
      await _analytics.setAnalyticsCollectionEnabled(false);
      await _analytics.setAnalyticsCollectionEnabled(true);
      _results.add(AnalyticsResult(
          'Collection toggle', true, 'Disabled then re-enabled'));
    } catch (e) {
      _results.add(AnalyticsResult('Collection toggle', false, '$e'));
    }

    _phase = _Phase.done;
    final passed = _results.where((r) => r.passed).length;
    _set(
      instruction: 'Validation complete: $passed/${_results.length} checks passed.\n\n'
          'IMPORTANT: Analytics delivery can only be fully confirmed in the '
          'Firebase/GA4 console. Open GA4 → Admin → DebugView (or Realtime) to '
          'see the events that were just sent.\n\n'
          'Press below for detailed results.',
      button: 'View Results',
    );
  }

  Future<String> _safeClientId() async {
    try {
      final id = await FirebaseAnalyticsPlatform.instance.getAppInstanceId();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return 'validation-client';
  }

  /// Posts the event to GA4's debug validation endpoint and returns the list
  /// of validationMessages (empty == valid payload).
  Future<List<String>> _validateWithDebugEndpoint(
      String clientId, _TestEvent ev) async {
    final cleaned = <String, Object?>{};
    ev.params.forEach((k, v) {
      if (v is String || v is int || v is double) {
        cleaned[k] = v;
      } else if (v is bool) {
        cleaned[k] = v ? 1 : 0;
      }
    });

    final payload = <String, dynamic>{
      'client_id': clientId,
      'events': [
        {'name': ev.name, 'params': cleaned}
      ],
    };

    final uri = Uri.parse(
      'https://www.google-analytics.com/debug/mp/collect'
      '?measurement_id=$kMeasurementId&api_secret=$kApiSecret',
    );

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode(payload));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (body.isEmpty) return const [];
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final list = (decoded['validationMessages'] as List?) ?? const [];
      return list
          .map((m) => (m as Map<String, dynamic>)['description']?.toString() ??
              m.toString())
          .toList();
    } finally {
      client.close();
    }
  }

  bool _isValidEventName(String name) {
    if (name.isEmpty || name.length > 40) return false;
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(name)) return false;
    for (final p in ['firebase_', 'google_', 'ga_']) {
      if (name.startsWith(p)) return false;
    }
    return true;
  }

  void _openResults() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalyticsResultsScreen(results: List.of(_results)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics — Guided Validation')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_instruction,
                style: const TextStyle(fontSize: 16, height: 1.4)),
            const SizedBox(height: 32),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _onAction,
                autofocus: true,
                style: ButtonStyle(
                  padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 16)),
                  // Visible focus highlight for D-pad/remote navigation on TV.
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return const BorderSide(color: Colors.amber, width: 3);
                    }
                    return null;
                  }),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return Colors.deepPurple.shade700;
                    }
                    return null;
                  }),
                ),
                child: Text(_button, style: const TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }
}
