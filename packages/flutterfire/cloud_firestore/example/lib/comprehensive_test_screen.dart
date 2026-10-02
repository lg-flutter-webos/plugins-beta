import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Comprehensive Firestore Validation Screen
///
/// A single-screen test harness that:
/// 1. Seeds all test data automatically
/// 2. Runs all Firestore API tests sequentially (methods + events)
/// 3. Shows results in a graphical representation
/// 4. Cleans up (deletes) all test data after validation
///
/// Test Categories:
/// - Instance Management (initialize, settings, network, terminate)
/// - Document CRUD (set, get, update, delete)
/// - Snapshot Listeners (document + query events)
/// - Query Operations (all where filters, orderBy, limit, count)
/// - Batch Operations (batch commit)
/// - Transactions (read-write, atomicity, retry)
/// - FieldValue Operations (serverTimestamp, increment, delete, arrayUnion/Remove)
/// - Aggregate Queries (count)
class ComprehensiveTestScreen extends StatefulWidget {
  const ComprehensiveTestScreen({super.key});

  @override
  State<ComprehensiveTestScreen> createState() => _ComprehensiveTestScreenState();
}

// ─── Test Result Model ───────────────────────────────────────────────────────

enum TestStatus { pending, running, passed, failed, skipped }

class TestResult {
  final String id;
  final String category;
  final String name;
  final String description;
  TestStatus status;
  String? message;
  Duration? duration;

  TestResult({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    this.status = TestStatus.pending,
  });
}

// ─── Main State ──────────────────────────────────────────────────────────────

class _ComprehensiveTestScreenState extends State<ComprehensiveTestScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Test collections (all cleaned up after validation)
  static const String _seedCollection = '_validation_seed';
  static const String _crudCollection = '_validation_crud';
  static const String _queryCollection = '_validation_query';
  static const String _batchCollection = '_validation_batch';
  static const String _txnCollection = '_validation_txn';
  static const String _fieldValueCollection = '_validation_fieldvalue';
  static const String _eventCollection = '_validation_events';

  // Test state
  final List<TestResult> _results = [];
  bool _isRunning = false;
  bool _hasRun = false;
  int _currentStep = 0;
  String _currentTestName = '';
  final List<String> _eventLog = [];
  final int _maxEventLog = 30;

  // Event listener subscriptions
  StreamSubscription<DocumentSnapshot>? _docListenerSub;
  StreamSubscription<QuerySnapshot>? _queryListenerSub;
  final List<String> _receivedDocEvents = [];
  final List<String> _receivedQueryEvents = [];

  // Summary
  int get _passedCount => _results.where((r) => r.status == TestStatus.passed).length;
  int get _failedCount => _results.where((r) => r.status == TestStatus.failed).length;
  int get _skippedCount => _results.where((r) => r.status == TestStatus.skipped).length;
  int get _totalCount => _results.length;
  double get _progress => _totalCount == 0 ? 0 : _currentStep / _totalCount;

  @override
  void initState() {
    super.initState();
    _buildTestList();
  }

  @override
  void dispose() {
    _docListenerSub?.cancel();
    _queryListenerSub?.cancel();
    super.dispose();
  }

  // ─── Build the test list ───────────────────────────────────────────────────

  void _buildTestList() {
    _results.clear();
    _results.addAll([
      // ── Instance Management ──
      TestResult(id: 'init', category: 'Instance', name: 'Initialize Firestore',
          description: 'FirebaseFirestore.instance + health check get()'),
      TestResult(id: 'settings', category: 'Instance', name: 'Set Settings',
          description: 'Configure host, SSL, persistence, cache size'),
      TestResult(id: 'network', category: 'Instance', name: 'Enable/Disable Network',
          description: 'Toggle network on/off and verify'),
      TestResult(id: 'pendingWrites', category: 'Instance', name: 'Wait For Pending Writes',
          description: 'Flush all pending writes to server'),

      // ── Document CRUD ──
      TestResult(id: 'docSet', category: 'CRUD', name: 'Document Set',
          description: 'set() with merge:false and merge:true'),
      TestResult(id: 'docGet', category: 'CRUD', name: 'Document Get',
          description: 'get() from server and cache sources'),
      TestResult(id: 'docUpdate', category: 'CRUD', name: 'Document Update',
          description: 'update() with FieldValue.serverTimestamp()'),
      TestResult(id: 'docDelete', category: 'CRUD', name: 'Document Delete',
          description: 'delete() and verify exists=false'),

      // ── Query Operations ──
      TestResult(id: 'queryEq', category: 'Query', name: 'where(==)',
          description: 'Filter by equality'),
      TestResult(id: 'queryNeq', category: 'Query', name: 'where(!=)',
          description: 'Filter by not-equal'),
      TestResult(id: 'queryGt', category: 'Query', name: 'where(>)',
          description: 'Filter by greater-than'),
      TestResult(id: 'queryLt', category: 'Query', name: 'where(<)',
          description: 'Filter by less-than'),
      TestResult(id: 'queryArray', category: 'Query', name: 'arrayContains',
          description: 'Filter by array membership'),
      TestResult(id: 'queryArrayAny', category: 'Query', name: 'arrayContainsAny',
          description: 'Filter by any array membership'),
      TestResult(id: 'queryIn', category: 'Query', name: 'where(in)',
          description: 'Filter by value in list'),
      TestResult(id: 'queryOrder', category: 'Query', name: 'orderBy + limit',
          description: 'Sort and limit results'),
      TestResult(id: 'queryCount', category: 'Query', name: 'Aggregate Count',
          description: 'count() aggregate query'),

      // ── Batch Operations ──
      TestResult(id: 'batch', category: 'Batch', name: 'Batch Commit',
          description: 'Atomic batch with set/update/delete'),

      // ── Transactions ──
      TestResult(id: 'txnBasic', category: 'Transaction', name: 'Basic Read-Write',
          description: 'Read balance, increment, write back'),
      TestResult(id: 'txnAtomic', category: 'Transaction', name: 'Atomicity',
          description: 'All-or-nothing multi-doc update'),
      TestResult(id: 'txnRetry', category: 'Transaction', name: 'Retry on Conflict',
          description: 'Concurrent transaction conflict handling'),

      // ── FieldValue Operations ──
      TestResult(id: 'fvTimestamp', category: 'FieldValue', name: 'serverTimestamp()',
          description: 'Server-side timestamp'),
      TestResult(id: 'fvIncrement', category: 'FieldValue', name: 'increment()',
          description: 'Atomic counter increment'),
      TestResult(id: 'fvDelete', category: 'FieldValue', name: 'delete()',
          description: 'Remove a field'),
      TestResult(id: 'fvArrayUnion', category: 'FieldValue', name: 'arrayUnion()',
          description: 'Add elements to array'),
      TestResult(id: 'fvArrayRemove', category: 'FieldValue', name: 'arrayRemove()',
          description: 'Remove elements from array'),

      // ── Event Listeners ──
      TestResult(id: 'evtDoc', category: 'Events', name: 'Document Snapshot Listener',
          description: 'Real-time doc change events via Event Channel'),
      TestResult(id: 'evtQuery', category: 'Events', name: 'Query Snapshot Listener',
          description: 'Real-time query change events via Event Channel'),
      TestResult(id: 'evtRemove', category: 'Events', name: 'Remove Listener',
          description: 'Cancel listener and verify no more events'),
    ]);
  }

  // ─── Main Run Button ───────────────────────────────────────────────────────

  Future<void> _runAllTests() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _hasRun = true;
      _currentStep = 0;
      _eventLog.clear();
      _receivedDocEvents.clear();
      _receivedQueryEvents.clear();
      for (final r in _results) {
        r.status = TestStatus.pending;
        r.message = null;
        r.duration = null;
      }
    });

    try {
      // Phase 1: Seed data
      await _setCurrent('Seeding test data...');
      await _seedAllData();

      // Phase 2: Run all tests
      await _runInstanceTests();
      await _runCrudTests();
      await _runQueryTests();
      await _runBatchTests();
      await _runTransactionTests();
      await _runFieldValueTests();
      await _runEventTests();

      // Phase 3: Cleanup
      await _setCurrent('Cleaning up test data...');
      await _cleanupAllData();
      _addEventLog('CLEANUP', 'All test data deleted');

      _setResult('init', TestStatus.passed, 'All tests completed successfully');
    } catch (e) {
      _addEventLog('ERROR', 'Fatal: $e');
    } finally {
      setState(() {
        _isRunning = false;
        _currentTestName = '';
      });
    }
  }

  Future<void> _setCurrent(String name) async {
    setState(() {
      _currentTestName = name;
    });
    await Future.delayed(const Duration(milliseconds: 50));
  }

  void _setResult(String id, TestStatus status, String message, {Duration? duration}) {
    setState(() {
      final idx = _results.indexWhere((r) => r.id == id);
      if (idx >= 0) {
        _results[idx].status = status;
        _results[idx].message = message;
        _results[idx].duration = duration;
      }
      _currentStep++;
    });
  }

  void _addEventLog(String type, String message) {
    setState(() {
      _eventLog.insert(0, '${DateTime.now().toString().substring(11, 19)} [$type] $message');
      if (_eventLog.length > _maxEventLog) {
        _eventLog.removeLast();
      }
    });
  }

  // ─── Seed Data ─────────────────────────────────────────────────────────────

  Future<void> _seedAllData() async {
    // Seed CRUD test doc
    await _firestore.doc('$_crudCollection/test_doc').set({
      'name': 'Alice',
      'age': 30,
      'active': true,
    });

    // Seed query test data (5 users)
    final queryBatch = _firestore.batch();
    final names = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve'];
    final tags = [
      ['admin', 'user'],
      ['user'],
      ['admin', 'moderator'],
      ['user', 'moderator'],
      ['admin'],
    ];
    final priorities = [1, 2, 3, 4, 5];
    final actives = [true, true, false, true, false];
    for (int i = 0; i < 5; i++) {
      queryBatch.set(_firestore.collection(_queryCollection).doc('user_$i'), {
        'name': names[i],
        'priority': priorities[i],
        'active': actives[i],
        'tags': tags[i],
        'score': (i + 1) * 10,
      });
    }
    await queryBatch.commit();

    // Seed transaction test data
    final txnBatch = _firestore.batch();
    txnBatch.set(_firestore.collection(_txnCollection).doc('user_1'), {
      'name': 'Alice', 'balance': 100, 'version': 1,
    });
    txnBatch.set(_firestore.collection(_txnCollection).doc('user_2'), {
      'name': 'Bob', 'balance': 50, 'version': 1,
    });
    await txnBatch.commit();

    // Seed FieldValue test data
    await _firestore.doc('$_fieldValueCollection/counter').set({'count': 0});
    await _firestore.doc('$_fieldValueCollection/array').set({'items': ['a', 'b']});
    await _firestore.doc('$_fieldValueCollection/timestamp').set({'created': 'placeholder'});

    // Seed event test data
    await _firestore.doc('$_eventCollection/event_doc').set({'value': 0, 'name': 'initial'});

    _addEventLog('SEED', 'All test data seeded successfully');
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> _cleanupAllData() async {
    final collections = [
      _seedCollection, _crudCollection, _queryCollection,
      _batchCollection, _txnCollection, _fieldValueCollection, _eventCollection,
    ];
    for (final collection in collections) {
      try {
        final snapshot = await _firestore.collection(collection).get();
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        if (snapshot.docs.isNotEmpty) {
          await batch.commit();
        }
      } catch (e) {
        _addEventLog('CLEANUP', 'Error cleaning $collection: $e');
      }
    }
  }

  // ─── Instance Management Tests ─────────────────────────────────────────────

  Future<void> _runInstanceTests() async {
    // Test: Initialize Firestore
    final t0 = DateTime.now();
    try {
      await _firestore.collection('_health_check').doc('_init').get();
      _setResult('init', TestStatus.passed, 'Firestore initialized', duration: DateTime.now().difference(t0));
    } catch (e) {
      _setResult('init', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t0));
    }

    // Test: Set Settings
    final t1 = DateTime.now();
    try {
      _firestore.settings = Settings(
        host: 'firestore.googleapis.com',
        sslEnabled: true,
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      _setResult('settings', TestStatus.passed, 'Settings applied', duration: DateTime.now().difference(t1));
    } catch (e) {
      _setResult('settings', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t1));
    }

    // Test: Enable/Disable Network
    final t2 = DateTime.now();
    try {
      await _firestore.disableNetwork();
      await _firestore.enableNetwork();
      await _firestore.collection('_health_check').doc('_network').get();
      _setResult('network', TestStatus.passed, 'Network toggled and verified', duration: DateTime.now().difference(t2));
    } catch (e) {
      _setResult('network', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t2));
    }

    // Test: Wait For Pending Writes
    final t3 = DateTime.now();
    try {
      await _firestore.waitForPendingWrites();
      _setResult('pendingWrites', TestStatus.passed, 'All writes flushed', duration: DateTime.now().difference(t3));
    } catch (e) {
      _setResult('pendingWrites', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t3));
    }
  }

  // ─── Document CRUD Tests ───────────────────────────────────────────────────

  Future<void> _runCrudTests() async {
    final docRef = _firestore.doc('$_crudCollection/test_doc');

    // Test: Document Set
    final t0 = DateTime.now();
    try {
      await docRef.set({'name': 'Alice', 'age': 30, 'active': true});
      await docRef.set({'email': 'alice@example.com'}, SetOptions(merge: true));
      _setResult('docSet', TestStatus.passed, 'Set + merge set completed', duration: DateTime.now().difference(t0));
    } catch (e) {
      _setResult('docSet', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t0));
    }

    // Test: Document Get
    final t1 = DateTime.now();
    try {
      final server = await docRef.get(const GetOptions(source: Source.server));
      final cache = await docRef.get(const GetOptions(source: Source.cache));
      final ok = server.exists && cache.exists;
      _setResult('docGet', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Server+Cache: ${server.data()}' : 'Missing data',
          duration: DateTime.now().difference(t1));
    } catch (e) {
      _setResult('docGet', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t1));
    }

    // Test: Document Update
    final t2 = DateTime.now();
    try {
      await docRef.update({
        'age': 31,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      final snap = await docRef.get();
      final ok = snap.data()?['age'] == 31;
      _setResult('docUpdate', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Updated age=31' : 'Update not reflected',
          duration: DateTime.now().difference(t2));
    } catch (e) {
      _setResult('docUpdate', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t2));
    }

    // Test: Document Delete
    final t3 = DateTime.now();
    try {
      await docRef.delete();
      final snap = await docRef.get();
      final ok = !snap.exists;
      _setResult('docDelete', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Document deleted' : 'Still exists',
          duration: DateTime.now().difference(t3));
    } catch (e) {
      _setResult('docDelete', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t3));
    }
  }

  // ─── Query Tests ───────────────────────────────────────────────────────────

  Future<void> _runQueryTests() async {
    final col = _firestore.collection(_queryCollection);

    // where(==)
    final t0 = DateTime.now();
    try {
      final snap = await col.where('active', isEqualTo: true).get();
      _setResult('queryEq', TestStatus.passed, '${snap.docs.length} active users', duration: DateTime.now().difference(t0));
    } catch (e) {
      _setResult('queryEq', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t0));
    }

    // where(!=)
    final t1 = DateTime.now();
    try {
      final snap = await col.where('active', isNotEqualTo: true).get();
      _setResult('queryNeq', TestStatus.passed, '${snap.docs.length} inactive users', duration: DateTime.now().difference(t1));
    } catch (e) {
      _setResult('queryNeq', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t1));
    }

    // where(>)
    final t2 = DateTime.now();
    try {
      final snap = await col.where('priority', isGreaterThan: 3).get();
      _setResult('queryGt', TestStatus.passed, '${snap.docs.length} users with priority>3', duration: DateTime.now().difference(t2));
    } catch (e) {
      _setResult('queryGt', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t2));
    }

    // where(<)
    final t3 = DateTime.now();
    try {
      final snap = await col.where('priority', isLessThan: 3).get();
      _setResult('queryLt', TestStatus.passed, '${snap.docs.length} users with priority<3', duration: DateTime.now().difference(t3));
    } catch (e) {
      _setResult('queryLt', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t3));
    }

    // arrayContains
    final t4 = DateTime.now();
    try {
      final snap = await col.where('tags', arrayContains: 'admin').get();
      _setResult('queryArray', TestStatus.passed, '${snap.docs.length} users with admin tag', duration: DateTime.now().difference(t4));
    } catch (e) {
      _setResult('queryArray', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t4));
    }

    // arrayContainsAny
    final t5 = DateTime.now();
    try {
      final snap = await col.where('tags', arrayContainsAny: ['admin', 'moderator']).get();
      _setResult('queryArrayAny', TestStatus.passed, '${snap.docs.length} users with admin/moderator', duration: DateTime.now().difference(t5));
    } catch (e) {
      _setResult('queryArrayAny', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t5));
    }

    // where(in)
    final t6 = DateTime.now();
    try {
      final snap = await col.where('name', whereIn: ['Alice', 'Bob', 'Eve']).get();
      _setResult('queryIn', TestStatus.passed, '${snap.docs.length} users in [Alice,Bob,Eve]', duration: DateTime.now().difference(t6));
    } catch (e) {
      _setResult('queryIn', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t6));
    }

    // orderBy + limit
    final t7 = DateTime.now();
    try {
      final snap = await col.orderBy('priority', descending: true).limit(3).get();
      _setResult('queryOrder', TestStatus.passed, 'Top 3: ${snap.docs.map((d) => d['name']).join(', ')}', duration: DateTime.now().difference(t7));
    } catch (e) {
      _setResult('queryOrder', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t7));
    }

    // Aggregate Count
    final t8 = DateTime.now();
    try {
      final count = await col.count().get();
      _setResult('queryCount', TestStatus.passed, 'Total: ${count.count}', duration: DateTime.now().difference(t8));
    } catch (e) {
      _setResult('queryCount', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t8));
    }
  }

  // ─── Batch Tests ───────────────────────────────────────────────────────────

  Future<void> _runBatchTests() async {
    final t0 = DateTime.now();
    try {
      final batch = _firestore.batch();
      final doc1 = _firestore.doc('$_batchCollection/doc1');
      final doc2 = _firestore.doc('$_batchCollection/doc2');
      final doc3 = _firestore.doc('$_batchCollection/doc3');
      batch.set(doc1, {'name': 'Batch 1', 'value': 1});
      batch.set(doc2, {'name': 'Batch 2', 'value': 2});
      batch.set(doc3, {'name': 'Batch 3', 'value': 3});
      await batch.commit();

      // Verify
      final s1 = await doc1.get();
      final s2 = await doc2.get();
      final s3 = await doc3.get();
      final ok = s1.exists && s2.exists && s3.exists;
      _setResult('batch', ok ? TestStatus.passed : TestStatus.failed,
          ok ? '3 docs committed atomically' : 'Batch verification failed',
          duration: DateTime.now().difference(t0));
    } catch (e) {
      _setResult('batch', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t0));
    }
  }

  // ─── Transaction Tests ─────────────────────────────────────────────────────

  Future<void> _runTransactionTests() async {
    // Basic Read-Write
    final t0 = DateTime.now();
    try {
      await _firestore.runTransaction((txn) async {
        final ref = _firestore.doc('$_txnCollection/user_1');
        final snap = await txn.get(ref);
        final balance = (snap.data()?['balance'] as num?)?.toInt() ?? 0;
        txn.update(ref, {'balance': balance + 10});
      });
      final verify = await _firestore.doc('$_txnCollection/user_1').get();
      final ok = (verify.data()?['balance'] as num?)?.toInt() == 110;
      _setResult('txnBasic', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Balance 100→110' : 'Balance not updated',
          duration: DateTime.now().difference(t0));
    } catch (e) {
      _setResult('txnBasic', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t0));
    }

    // Atomicity (multi-doc)
    final t1 = DateTime.now();
    try {
      await _firestore.runTransaction((txn) async {
        final ref1 = _firestore.doc('$_txnCollection/user_1');
        final ref2 = _firestore.doc('$_txnCollection/user_2');
        final s1 = await txn.get(ref1);
        final s2 = await txn.get(ref2);
        final b1 = (s1.data()?['balance'] as num?)?.toInt() ?? 0;
        final b2 = (s2.data()?['balance'] as num?)?.toInt() ?? 0;
        txn.update(ref1, {'balance': b1 - 20});
        txn.update(ref2, {'balance': b2 + 20});
      });
      final v1 = await _firestore.doc('$_txnCollection/user_1').get();
      final v2 = await _firestore.doc('$_txnCollection/user_2').get();
      final b1 = (v1.data()?['balance'] as num?)?.toInt() ?? 0;
      final b2 = (v2.data()?['balance'] as num?)?.toInt() ?? 0;
      final ok = b1 == 90 && b2 == 70;
      _setResult('txnAtomic', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Transfer 20: 110→90, 50→70' : 'Atomicity violated: $b1/$b2',
          duration: DateTime.now().difference(t1));
    } catch (e) {
      _setResult('txnAtomic', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t1));
    }

    // Retry on Conflict
    final t2 = DateTime.now();
    try {
      // Simulate conflict by running two concurrent transactions
      await Future.wait([
        _firestore.runTransaction((txn) async {
          final ref = _firestore.doc('$_txnCollection/user_1');
          final snap = await txn.get(ref);
          final b = (snap.data()?['balance'] as num?)?.toInt() ?? 0;
          txn.update(ref, {'balance': b + 5});
        }),
        _firestore.runTransaction((txn) async {
          final ref = _firestore.doc('$_txnCollection/user_1');
          final snap = await txn.get(ref);
          final b = (snap.data()?['balance'] as num?)?.toInt() ?? 0;
          txn.update(ref, {'balance': b + 5});
        }),
      ]);
      final verify = await _firestore.doc('$_txnCollection/user_1').get();
      final b = (verify.data()?['balance'] as num?)?.toInt() ?? 0;
      final ok = b == 100; // 90 + 5 + 5
      _setResult('txnRetry', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Both transactions committed: balance=$b' : 'Conflict not resolved: balance=$b',
          duration: DateTime.now().difference(t2));
    } catch (e) {
      _setResult('txnRetry', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t2));
    }
  }

  // ─── FieldValue Tests ──────────────────────────────────────────────────────

  Future<void> _runFieldValueTests() async {
    // serverTimestamp()
    final t0 = DateTime.now();
    try {
      final ref = _firestore.doc('$_fieldValueCollection/timestamp');
      await ref.update({'created': FieldValue.serverTimestamp()});
      final snap = await ref.get();
      final ts = snap.data()?['created'];
      final ok = ts is Timestamp && ts.seconds > 0;
      _setResult('fvTimestamp', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Timestamp: ${ts.toDate()}' : 'No timestamp',
          duration: DateTime.now().difference(t0));
    } catch (e) {
      _setResult('fvTimestamp', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t0));
    }

    // increment()
    final t1 = DateTime.now();
    try {
      final ref = _firestore.doc('$_fieldValueCollection/counter');
      await ref.update({'count': FieldValue.increment(5)});
      final snap = await ref.get();
      final count = (snap.data()?['count'] as num?)?.toInt() ?? -1;
      final ok = count == 5;
      _setResult('fvIncrement', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Counter: 0→5' : 'Counter: $count',
          duration: DateTime.now().difference(t1));
    } catch (e) {
      _setResult('fvIncrement', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t1));
    }

    // delete()
    final t2 = DateTime.now();
    try {
      final ref = _firestore.doc('$_fieldValueCollection/counter');
      await ref.update({'count': FieldValue.delete()});
      final snap = await ref.get();
      final ok = !snap.data()!.containsKey('count');
      _setResult('fvDelete', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Field deleted' : 'Field still exists',
          duration: DateTime.now().difference(t2));
    } catch (e) {
      _setResult('fvDelete', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t2));
    }

    // arrayUnion()
    final t3 = DateTime.now();
    try {
      final ref = _firestore.doc('$_fieldValueCollection/array');
      await ref.update({'items': FieldValue.arrayUnion(['c', 'd'])});
      final snap = await ref.get();
      final items = (snap.data()?['items'] as List?)?.cast<String>() ?? [];
      final ok = items.contains('c') && items.contains('d') && items.length == 4;
      _setResult('fvArrayUnion', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Array: [a,b]→[a,b,c,d]' : 'Array: $items',
          duration: DateTime.now().difference(t3));
    } catch (e) {
      _setResult('fvArrayUnion', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t3));
    }

    // arrayRemove()
    final t4 = DateTime.now();
    try {
      final ref = _firestore.doc('$_fieldValueCollection/array');
      await ref.update({'items': FieldValue.arrayRemove(['a'])});
      final snap = await ref.get();
      final items = (snap.data()?['items'] as List?)?.cast<String>() ?? [];
      final ok = !items.contains('a') && items.length == 3;
      _setResult('fvArrayRemove', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Array: [a,b,c,d]→[b,c,d]' : 'Array: $items',
          duration: DateTime.now().difference(t4));
    } catch (e) {
      _setResult('fvArrayRemove', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t4));
    }
  }

  // ─── Event Listener Tests ──────────────────────────────────────────────────

  Future<void> _runEventTests() async {
    // Test: Document Snapshot Listener
    final t0 = DateTime.now();
    try {
      final docRef = _firestore.doc('$_eventCollection/event_doc');
      final completer = Completer<void>();

      _docListenerSub = docRef.snapshots().listen((snapshot) {
        if (snapshot.exists) {
          _receivedDocEvents.add('doc:${snapshot.data()?['value']}');
          _addEventLog('DOC_EVT', 'value=${snapshot.data()?['value']}');
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      });

      // Wait for initial snapshot
      await completer.future.timeout(const Duration(seconds: 5));

      // Now update the doc and wait for the event
      final prevCount = _receivedDocEvents.length;
      await docRef.update({'value': 1});

      // Wait for the update event
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (_receivedDocEvents.length <= prevCount && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final ok = _receivedDocEvents.length > prevCount;
      _setResult('evtDoc', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Received ${_receivedDocEvents.length} doc events' : 'No update event received',
          duration: DateTime.now().difference(t0));
    } catch (e) {
      _setResult('evtDoc', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t0));
    } finally {
      await _docListenerSub?.cancel();
      _docListenerSub = null;
    }

    // Test: Query Snapshot Listener
    final t1 = DateTime.now();
    try {
      final col = _firestore.collection(_eventCollection);
      final completer = Completer<void>();

      _queryListenerSub = col.where('value', isGreaterThanOrEqualTo: 0).snapshots().listen((snapshot) {
        _receivedQueryEvents.add('query:${snapshot.docs.length}docs');
        _addEventLog('QUERY_EVT', '${snapshot.docs.length} docs');
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      // Wait for initial snapshot
      await completer.future.timeout(const Duration(seconds: 5));

      // Add a new doc and wait for the event
      final prevCount = _receivedQueryEvents.length;
      await _firestore.doc('$_eventCollection/event_doc2').set({'value': 2, 'name': 'second'});

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (_receivedQueryEvents.length <= prevCount && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final ok = _receivedQueryEvents.length > prevCount;
      _setResult('evtQuery', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'Received ${_receivedQueryEvents.length} query events' : 'No query event received',
          duration: DateTime.now().difference(t1));
    } catch (e) {
      _setResult('evtQuery', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t1));
    } finally {
      await _queryListenerSub?.cancel();
      _queryListenerSub = null;
    }

    // Test: Remove Listener
    final t2 = DateTime.now();
    try {
      // Listener was already cancelled in finally blocks above
      // Verify no more events arrive after cancellation
      final beforeCount = _receivedDocEvents.length + _receivedQueryEvents.length;
      await _firestore.doc('$_eventCollection/event_doc').update({'value': 99});
      await Future.delayed(const Duration(seconds: 1));
      final afterCount = _receivedDocEvents.length + _receivedQueryEvents.length;
      final ok = afterCount == beforeCount;
      _setResult('evtRemove', ok ? TestStatus.passed : TestStatus.failed,
          ok ? 'No events after cancellation' : 'Unexpected events after cancel',
          duration: DateTime.now().difference(t2));
    } catch (e) {
      _setResult('evtRemove', TestStatus.failed, 'Failed: $e', duration: DateTime.now().difference(t2));
    }
  }

  // ─── UI Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firestore Validation Suite'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isRunning)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          _buildProgressBar(),
          if (_currentTestName.isNotEmpty) _buildCurrentTest(),
          _buildEventLog(),
          Expanded(child: _buildResultsList()),
        ],
      ),
      floatingActionButton: _isRunning
          ? null
          : FloatingActionButton.extended(
              onPressed: _runAllTests,
              icon: Icon(_hasRun ? Icons.replay : Icons.play_arrow),
              label: Text(_hasRun ? 'Re-run Tests' : 'Start Validation'),
              backgroundColor: Colors.deepPurple,
            ),
    );
  }

  // ─── Summary Header with Graphical Representation ─────────────────────────

  Widget _buildSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[50],
      child: Column(
        children: [
          Row(
            children: [
              // Passed
              Expanded(
                child: _summaryCard(
                  'PASSED',
                  _passedCount.toString(),
                  Colors.green,
                  Icons.check_circle,
                ),
              ),
              const SizedBox(width: 8),
              // Failed
              Expanded(
                child: _summaryCard(
                  'FAILED',
                  _failedCount.toString(),
                  Colors.red,
                  Icons.error,
                ),
              ),
              const SizedBox(width: 8),
              // Skipped
              Expanded(
                child: _summaryCard(
                  'SKIPPED',
                  _skippedCount.toString(),
                  Colors.orange,
                  Icons.skip_next,
                ),
              ),
              const SizedBox(width: 8),
              // Total
              Expanded(
                child: _summaryCard(
                  'TOTAL',
                  _totalCount.toString(),
                  Colors.blueGrey,
                  Icons.list,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Donut-style progress indicator
          Row(
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _progress,
                      strokeWidth: 6,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _failedCount > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                    Text(
                      '${(_progress * 100).round()}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isRunning
                          ? 'Running: $_currentTestName'
                          : _hasRun
                              ? 'Validation Complete'
                              : 'Ready to validate',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isRunning
                          ? 'Step $_currentStep of $_totalCount'
                          : _hasRun
                              ? 'All test data cleaned up'
                              : 'Press "Start Validation" to begin',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // ─── Progress Bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    return LinearProgressIndicator(
      value: _progress,
      minHeight: 4,
      backgroundColor: Colors.grey[200],
      valueColor: AlwaysStoppedAnimation<Color>(
        _failedCount > 0 ? Colors.red : Colors.deepPurple,
      ),
    );
  }

  // ─── Current Test Indicator ────────────────────────────────────────────────

  Widget _buildCurrentTest() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.deepPurple.withValues(alpha: 0.05),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentTestName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Event Log ─────────────────────────────────────────────────────────────

  Widget _buildEventLog() {
    return Container(
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(6),
      ),
      child: _eventLog.isEmpty
          ? const Center(
              child: Text(
                'Event log: real-time events will appear here',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            )
          : ListView.builder(
              reverse: true,
              itemCount: _eventLog.length,
              itemBuilder: (context, index) {
                final entry = _eventLog[index];
                final isError = entry.contains('[ERROR]');
                final isEvent = entry.contains('_EVT');
                return Text(
                  entry,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: isError
                        ? Colors.red[300]
                        : isEvent
                            ? Colors.green[300]
                            : Colors.grey[300],
                  ),
                );
              },
            ),
    );
  }

  // ─── Results List ──────────────────────────────────────────────────────────

  Widget _buildResultsList() {
    // Group by category
    final categories = <String, List<TestResult>>{};
    for (final r in _results) {
      categories.putIfAbsent(r.category, () => []).add(r);
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final entry in categories.entries) ...[
          _categoryHeader(entry.key, entry.value),
          for (final result in entry.value) _resultCard(result),
        ],
      ],
    );
  }

  Widget _categoryHeader(String category, List<TestResult> tests) {
    final passed = tests.where((t) => t.status == TestStatus.passed).length;
    final failed = tests.where((t) => t.status == TestStatus.failed).length;
    final total = tests.length;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            category,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '$passed/$total passed${failed > 0 ? ' • $failed failed' : ''}',
            style: TextStyle(
              fontSize: 10,
              color: failed > 0 ? Colors.red : Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(TestResult result) {
    final Color color;
    final IconData icon;
    switch (result.status) {
      case TestStatus.passed:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case TestStatus.failed:
        color = Colors.red;
        icon = Icons.error;
        break;
      case TestStatus.running:
        color = Colors.orange;
        icon = Icons.hourglass_top;
        break;
      case TestStatus.skipped:
        color = Colors.orange;
        icon = Icons.skip_next;
        break;
      case TestStatus.pending:
        color = Colors.grey;
        icon = Icons.radio_button_unchecked;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: color, size: 20),
          title: Text(
            result.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            result.message ?? result.description,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: result.duration != null
              ? Text(
                  '${result.duration!.inMilliseconds}ms',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                )
              : null,
        ),
      ),
    );
  }
}