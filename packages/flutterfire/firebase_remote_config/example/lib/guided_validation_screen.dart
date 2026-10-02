import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'results_screen.dart';

/// Guided Remote Config validation.
///
/// Kept intentionally lightweight for webOS TV hardware: the live screen shows
/// only a single instruction line and a single action button — no streams held
/// open long, no per-second timers, no live log widget. Results are collected
/// silently and shown on a separate [ResultsScreen] at the end.
class GuidedValidationScreen extends StatefulWidget {
  const GuidedValidationScreen({super.key});

  @override
  State<GuidedValidationScreen> createState() => _GuidedValidationScreenState();
}

// ─── Constants ───────────────────────────────────────────────────────────────

const String _kKey = 'validation_key';
const String _kInitialValue = 'hello-webos';
const String _kChangedValue = 'changed-value';
const Duration _kFetchTimeout = Duration(seconds: 20);
// onConfigUpdated is poll-based (~30s) on webOS, so wait comfortably longer.
const Duration _kRealtimeTimeout = Duration(seconds: 90);

// ─── Result model (plain data, no widgets) ───────────────────────────────────

class ValidationResult {
  final String name;
  final bool passed;
  final String detail;
  ValidationResult(this.name, this.passed, this.detail);
}

// ─── Guided runner phases ────────────────────────────────────────────────────

enum _Phase {
  intro, // Ready to start
  addKey, // Ask user to add key + publish
  changeKey, // Ask user to change value + publish
  done, // Finished
}

class _GuidedValidationScreenState extends State<GuidedValidationScreen> {
  final FirebaseRemoteConfig _rc = FirebaseRemoteConfig.instance;

  _Phase _phase = _Phase.intro;
  String _instruction =
      'This validates Remote Config against the Firebase console.\n\n'
      'Press Start to begin.';
  String _buttonLabel = 'Start';
  bool _busy = false;

  final List<ValidationResult> _results = [];

  void _set({String? instruction, String? button}) {
    if (!mounted) return;
    setState(() {
      if (instruction != null) _instruction = instruction;
      if (button != null) _buttonLabel = button;
    });
  }

  void _record(String name, bool passed, String detail) {
    _results.add(ValidationResult(name, passed, detail));
  }

  // ─── Button dispatch based on current phase ────────────────────────────────

  Future<void> _onAction() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (_phase) {
        case _Phase.intro:
          await _startAndFetchCheck();
          break;
        case _Phase.addKey:
          await _verifyAddedKey();
          break;
        case _Phase.changeKey:
          await _verifyChangedValue();
          break;
        case _Phase.done:
          _openResults();
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Phase 1: Start → settings/defaults → fetch check ──────────────────────

  Future<void> _startAndFetchCheck() async {
    _set(instruction: 'Configuring and running fetch check...');
    // Settings + default (source transitions default -> remote later).
    try {
      await _rc
          .setConfigSettings(RemoteConfigSettings(
            fetchTimeout: const Duration(seconds: 15),
            minimumFetchInterval: Duration.zero,
          ))
          .timeout(_kFetchTimeout);
      await _rc.setDefaults(
          const <String, dynamic>{_kKey: 'default-value'}).timeout(_kFetchTimeout);
      _record('Settings & Defaults', true, 'setConfigSettings + setDefaults ok');
    } catch (e) {
      _record('Settings & Defaults', false, '$e');
    }

    // Fetch check.
    try {
      await _rc.fetch().timeout(_kFetchTimeout);
      final activated = await _rc.activate().timeout(_kFetchTimeout);
      _record('Fetch Check', true,
          'activated=$activated, status=${_rc.lastFetchStatus.name}, lastFetch=${_rc.lastFetchTime}');
    } on TimeoutException {
      _record('Fetch Check', false,
          'Timed out — native fetch did not complete within ${_kFetchTimeout.inSeconds}s');
    } on PlatformException catch (e) {
      _record('Fetch Check', false, 'PlatformException: ${e.code} ${e.message ?? ''}');
    } catch (e) {
      _record('Fetch Check', false, '$e');
    }

    // Move to add-key phase.
    _phase = _Phase.addKey;
    _set(
      instruction: 'STEP 1 — In the Firebase console:\n'
          '  • Add a String parameter named "$_kKey"\n'
          '  • Set its value to "$_kInitialValue"\n'
          '  • Publish changes\n\n'
          'Then press the button below.',
      button: "I've Published — Verify",
    );
  }

  // ─── Phase 2: Verify added key (exact match) ───────────────────────────────

  Future<void> _verifyAddedKey() async {
    _set(instruction: 'Fetching and verifying "$_kKey"...');
    try {
      await _rc.fetchAndActivate().timeout(_kFetchTimeout);
      final v = _rc.getValue(_kKey);
      final str = v.asString();
      final remote = v.source == ValueSource.valueRemote;
      final match = str == _kInitialValue;
      if (match && remote) {
        _record('Add Key (exact match)', true,
            'Got "$str" from ${v.source.name}');
      } else {
        _record('Add Key (exact match)', false,
            'Got "$str" (${v.source.name}), expected "$_kInitialValue" from valueRemote');
      }
    } on TimeoutException {
      _record('Add Key (exact match)', false,
          'Timed out after ${_kFetchTimeout.inSeconds}s');
    } catch (e) {
      _record('Add Key (exact match)', false, '$e');
    }

    // Move to change-key phase.
    _phase = _Phase.changeKey;
    _set(
      instruction: 'STEP 2 — In the Firebase console:\n'
          '  • Change "$_kKey" to "$_kChangedValue"\n'
          '  • Publish changes\n\n'
          'Then press the button. The app will wait up to '
          '${_kRealtimeTimeout.inSeconds}s for a realtime onConfigUpdated '
          'notification.',
      button: "I've Published — Verify Realtime",
    );
  }

  // ─── Phase 3: Verify changed value + realtime notification ─────────────────

  Future<void> _verifyChangedValue() async {
    _set(instruction: 'Waiting for onConfigUpdated notification...');

    // Wait for a realtime update (poll-based on webOS). We subscribe, wait for
    // the first event or timeout, then cancel — the stream is never held open
    // beyond this step.
    bool realtimeNotified = false;
    Set<String> notifiedKeys = <String>{};
    final completer = Completer<void>();
    StreamSubscription<RemoteConfigUpdate>? sub;

    sub = _rc.onConfigUpdated.listen(
      (update) {
        realtimeNotified = true;
        notifiedKeys = update.updatedKeys;
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    try {
      await completer.future.timeout(_kRealtimeTimeout);
      _record('Realtime onConfigUpdated', true,
          'Notified keys: ${notifiedKeys.join(', ')}');
    } on TimeoutException {
      _record('Realtime onConfigUpdated', false,
          'No notification within ${_kRealtimeTimeout.inSeconds}s');
    } catch (e) {
      _record('Realtime onConfigUpdated', false, '$e');
    } finally {
      await sub.cancel();
    }

    // Poll-based updates do not auto-activate — activate, then exact-match.
    try {
      await _rc.activate().timeout(_kFetchTimeout);
      final v = _rc.getValue(_kKey);
      final str = v.asString();
      final match = str == _kChangedValue;
      final keyNotified = notifiedKeys.contains(_kKey);
      _record(
        'Change Value (exact match)',
        match,
        match
            ? 'Got "$str"${keyNotified ? ' (key in updatedKeys)' : ' (key NOT in updatedKeys)'}'
            : 'Got "$str", expected "$_kChangedValue"',
      );
      // If realtime didn't notify but value did change, note it.
      if (!realtimeNotified && match) {
        _record('Realtime note', false,
            'Value changed but no realtime notification was received');
      }
    } on TimeoutException {
      _record('Change Value (exact match)', false,
          'activate() timed out after ${_kFetchTimeout.inSeconds}s');
    } catch (e) {
      _record('Change Value (exact match)', false, '$e');
    }

    _phase = _Phase.done;
    final passed = _results.where((r) => r.passed).length;
    _set(
      instruction: 'Validation complete: $passed/${_results.length} passed.\n\n'
          'Press below to view detailed results.',
      button: 'View Results',
    );
  }

  void _openResults() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResultsScreen(results: List.of(_results)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Config — Guided Validation')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _instruction,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 32),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _onAction,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(_buttonLabel, style: const TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }
}
