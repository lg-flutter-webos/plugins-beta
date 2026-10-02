import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics_webos/firebase_analytics_webos.dart';

import 'firebase_options.dart';
import 'analytics_validation_screen.dart';

void main() {
  // Render the UI first. Do NOT block startup on Firebase — initialization
  // runs after the first frame so the screen is always visible and responsive,
  // even if native init is slow on webOS.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Analytics Validation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const _Bootstrap(),
    );
  }
}

/// Initializes Firebase after the first frame, showing a visible status.
/// Nothing calls Firebase until this completes.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  String _status = 'Starting...';
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Defer to after first frame so the UI paints before any native call.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFirebase());
  }

  Future<void> _initFirebase() async {
    setState(() => _status = 'Initializing Firebase...');
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseAnalyticsWebos.configure(
        measurementId: kMeasurementId,
        apiSecret: kApiSecret,
      );
      if (!mounted) return;
      setState(() {
        _ready = true;
        _status = 'Ready.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _status = 'Firebase init failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const AnalyticsValidationScreen();

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics Validation')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_failed) const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_status, textAlign: TextAlign.center),
              if (_failed) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _initFirebase,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
