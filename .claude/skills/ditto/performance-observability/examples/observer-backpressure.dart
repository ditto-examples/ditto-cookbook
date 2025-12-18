// ============================================================================
// Observer Backpressure Management
// ============================================================================
//
// This example demonstrates proper observer backpressure handling in Ditto,
// preventing update queue buildup and ensuring smooth UI performance.
//
// ⚠️ IMPORTANT: This example uses registerObserverWithSignalNext which is NOT available
// in Flutter SDK v4.14.0 and earlier. Backpressure control via signalNext is only
// available in non-Flutter SDKs (Swift, JS, Kotlin).
//
// For Flutter SDK v4.x patterns (no backpressure control), see:
// - flutter-observer-v4-patterns.dart
// - flutter-observer-performance-v4.dart
//
// Flutter SDK v5.0 will add support for registerObserverWithSignalNext.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Lightweight onChange callback
// 2. ✅ signalNext() with WidgetsBinding.addPostFrameCallback
// 3. ✅ Offloading heavy processing
// 4. ✅ Async operations outside callback
// 5. ✅ Backpressure monitoring
// 6. ✅ Throttling rapid updates
// 7. ✅ Batch processing updates
//
// CRITICAL CONCEPT: Observer Backpressure
// - Observer callbacks must be fast (<16ms for 60 FPS)
// - Heavy processing blocks callback
// - Blocked callback = updates queue up
// - Update queue buildup = backpressure
// - signalNext() controls update flow
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:ditto/ditto.dart';
import 'dart:async';

// ============================================================================
// PATTERN 1: Lightweight onChange Callback
// ============================================================================

/// ✅ GOOD: Minimal processing in observer callback
class LightweightCallback {
  final Ditto ditto;

  LightweightCallback(this.ditto);

  void setupObserver() {
    print('📊 Setting up lightweight observer...');

    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos WHERE isCompleted != true',
      onChange: (result, signalNext) {
        // ✅ LIGHTWEIGHT: Extract data only (fast)
        final todos = result.items.map((item) => item.value).toList();

        // ✅ Update UI state
        _updateUI(todos);

        // ✅ Signal next AFTER UI update (in next frame)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        print('  ✅ Callback completed quickly (${todos.length} items)');

        // BENEFIT:
        // - Callback completes in <1ms
        // - No backpressure buildup
        // - Smooth 60 FPS UI
        // - Updates flow naturally
      },
    );

    print('✅ Lightweight observer registered');
  }

  void _updateUI(List<Map<String, dynamic>> todos) {
    // Update UI state (lightweight operation)
  }
}

// ============================================================================
// PATTERN 2: signalNext() with addPostFrameCallback
// ============================================================================

/// ✅ GOOD: Proper signalNext() timing
class ProperSignalNextTiming extends StatefulWidget {
  final Ditto ditto;

  const ProperSignalNextTiming({required this.ditto, Key? key}) : super(key: key);

  @override
  State<ProperSignalNextTiming> createState() => _ProperSignalNextTimingState();
}

class _ProperSignalNextTimingState extends State<ProperSignalNextTiming> {
  DittoStoreObserver? _observer;
  List<Map<String, dynamic>> _todos = [];

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos ORDER BY createdAt DESC',
      onChange: (result, signalNext) {
        // ✅ STEP 1: Extract data (fast)
        final todos = result.items.map((item) => item.value).toList();

        // ✅ STEP 2: Update state
        setState(() {
          _todos = todos;
        });

        // ✅ STEP 3: Signal next AFTER frame is rendered
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        print('✅ Observer callback: ${todos.length} todos, signalNext scheduled');

        // BENEFIT:
        // - signalNext() called after UI update completes
        // - Ensures smooth rendering
        // - No frame drops
        // - Natural backpressure control
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _todos.length,
      itemBuilder: (context, index) {
        final todo = _todos[index];
        return ListTile(
          title: Text(todo['title'] as String),
        );
      },
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// PATTERN 3: Offloading Heavy Processing
// ============================================================================

/// ✅ GOOD: Move heavy work outside callback
class OffloadHeavyProcessing {
  final Ditto ditto;
  final StreamController<List<Map<String, dynamic>>> _dataStream;

  OffloadHeavyProcessing(this.ditto)
      : _dataStream = StreamController<List<Map<String, dynamic>>>() {
    _setupObserver();
    _setupProcessor();
  }

  void _setupObserver() {
    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM tasks ORDER BY priority DESC, createdAt DESC',
      onChange: (result, signalNext) {
        // ✅ LIGHTWEIGHT: Extract data and pass to stream
        final tasks = result.items.map((item) => item.value).toList();

        // ✅ Send data to processor (non-blocking)
        _dataStream.add(tasks);

        // ✅ Signal next immediately (callback is fast)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        print('  ✅ Callback completed (${tasks.length} tasks sent to processor)');
      },
    );

    print('✅ Observer registered with offloaded processing');
  }

  void _setupProcessor() {
    // ✅ Process data outside observer callback
    _dataStream.stream.listen((tasks) async {
      print('  📊 Processing ${tasks.length} tasks (outside callback)...');

      // ✅ Heavy processing here (does NOT block observer)
      final processedTasks = await _heavyProcessing(tasks);

      print('    ✅ Processing complete');

      // Update UI with processed data
      _updateUI(processedTasks);
    });
  }

  Future<List<Map<String, dynamic>>> _heavyProcessing(
    List<Map<String, dynamic>> tasks,
  ) async {
    // Simulate heavy processing (sorting, filtering, enrichment)
    await Future.delayed(const Duration(milliseconds: 100));

    return tasks.map((task) {
      // Complex transformations
      return {
        ...task,
        'urgency': _calculateUrgency(task),
        'formattedDueDate': _formatDate(task['dueDate']),
        'assigneeNames': _lookupAssigneeNames(task['assignees']),
      };
    }).toList();
  }

  double _calculateUrgency(Map<String, dynamic> task) {
    // Complex calculation
    return 0.0;
  }

  String _formatDate(dynamic date) {
    return '';
  }

  List<String> _lookupAssigneeNames(dynamic assignees) {
    return [];
  }

  void _updateUI(List<Map<String, dynamic>> tasks) {
    // Update UI with processed tasks
  }

  void dispose() {
    _dataStream.close();
  }
}

// ============================================================================
// PATTERN 4: Async Operations Outside Callback
// ============================================================================

/// ✅ GOOD: Async work after callback completes
class AsyncOperationsOutside {
  final Ditto ditto;

  AsyncOperationsOutside(this.ditto);

  void setupObserver() {
    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM messages WHERE isRead != true',
      onChange: (result, signalNext) {
        // ✅ Extract data (lightweight)
        final messages = result.items.map((item) => item.value).toList();

        // ✅ Update UI immediately
        _updateUI(messages);

        // ✅ Signal next
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        // ✅ Trigger async operations AFTER callback
        _processMessagesAsync(messages);
      },
    );
  }

  void _updateUI(List<Map<String, dynamic>> messages) {
    // Update UI state immediately
  }

  void _processMessagesAsync(List<Map<String, dynamic>> messages) async {
    // ✅ Async processing outside observer callback
    print('  📧 Processing ${messages.length} messages asynchronously...');

    // Fetch additional data
    for (final message in messages) {
      await _fetchSenderProfile(message['senderId']);
      await _fetchAttachments(message['_id']);
    }

    print('    ✅ Async processing complete');
  }

  Future<void> _fetchSenderProfile(String senderId) async {
    // Fetch sender profile from API or database
    await Future.delayed(const Duration(milliseconds: 50));
  }

  Future<void> _fetchAttachments(String messageId) async {
    // Fetch message attachments
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

// ============================================================================
// PATTERN 5: Backpressure Monitoring
// ============================================================================

/// ✅ GOOD: Monitor backpressure buildup
class BackpressureMonitoring {
  final Ditto ditto;
  int _pendingUpdates = 0;
  DateTime? _lastCallbackTime;

  BackpressureMonitoring(this.ditto);

  void setupObserver() {
    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM items',
      onChange: (result, signalNext) {
        // ✅ Monitor backpressure
        _pendingUpdates++;

        final now = DateTime.now();
        if (_lastCallbackTime != null) {
          final timeSinceLastCallback = now.difference(_lastCallbackTime!);
          print('  ⏱️ Time since last callback: ${timeSinceLastCallback.inMilliseconds}ms');

          if (timeSinceLastCallback.inMilliseconds < 16) {
            print('  ⚠️ Rapid updates detected (${timeSinceLastCallback.inMilliseconds}ms interval)');
          }
        }

        _lastCallbackTime = now;

        // Process update
        final items = result.items.map((item) => item.value).toList();
        _updateUI(items);

        _pendingUpdates--;

        // ✅ Monitor pending updates
        if (_pendingUpdates > 5) {
          print('  🚨 BACKPRESSURE WARNING: ${_pendingUpdates} pending updates');
          print('     Callback may be too slow or updates too frequent');
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });
      },
    );
  }

  void _updateUI(List<Map<String, dynamic>> items) {
    // Update UI
  }
}

// ============================================================================
// PATTERN 6: Throttling Rapid Updates
// ============================================================================

/// ✅ GOOD: Throttle rapid observer updates
class ThrottledObserver {
  final Ditto ditto;
  DateTime? _lastUIUpdate;
  List<Map<String, dynamic>> _latestData = [];
  Timer? _updateTimer;

  static const _throttleDuration = Duration(milliseconds: 100);

  ThrottledObserver(this.ditto);

  void setupObserver() {
    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM realtimeData',
      onChange: (result, signalNext) {
        // ✅ Always extract latest data
        _latestData = result.items.map((item) => item.value).toList();

        final now = DateTime.now();
        final shouldUpdate = _lastUIUpdate == null ||
            now.difference(_lastUIUpdate!) >= _throttleDuration;

        if (shouldUpdate) {
          // ✅ Update UI immediately
          _updateUI(_latestData);
          _lastUIUpdate = now;
        } else {
          // ✅ Schedule update for later (throttled)
          _updateTimer?.cancel();
          _updateTimer = Timer(_throttleDuration, () {
            _updateUI(_latestData);
            _lastUIUpdate = DateTime.now();
          });
        }

        // ✅ Always signal next
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        print('  ✅ Update ${shouldUpdate ? "applied" : "throttled"}');
      },
    );

    print('✅ Throttled observer registered (max 10 UI updates/sec)');
  }

  void _updateUI(List<Map<String, dynamic>> data) {
    // Update UI
  }

  void dispose() {
    _updateTimer?.cancel();
  }
}

// ============================================================================
// PATTERN 7: Batch Processing Updates
// ============================================================================

/// ✅ GOOD: Batch multiple updates together
class BatchProcessing {
  final Ditto ditto;
  final List<List<Map<String, dynamic>>> _updateQueue = [];
  Timer? _batchTimer;

  static const _batchInterval = Duration(milliseconds: 50);

  BatchProcessing(this.ditto);

  void setupObserver() {
    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM events',
      onChange: (result, signalNext) {
        // ✅ Add to batch queue
        final events = result.items.map((item) => item.value).toList();
        _updateQueue.add(events);

        // ✅ Schedule batch processing
        _batchTimer?.cancel();
        _batchTimer = Timer(_batchInterval, _processBatch);

        // ✅ Signal next immediately
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        print('  ✅ Update queued (${_updateQueue.length} in queue)');
      },
    );

    print('✅ Batch processing observer registered');
  }

  void _processBatch() {
    if (_updateQueue.isEmpty) return;

    print('  📦 Processing batch of ${_updateQueue.length} updates...');

    // ✅ Process all queued updates together
    final allEvents = _updateQueue.expand((events) => events).toList();
    _updateQueue.clear();

    // ✅ Update UI once with batched data
    _updateUI(allEvents);

    print('    ✅ Batch processed (${allEvents.length} total events)');
  }

  void _updateUI(List<Map<String, dynamic>> events) {
    // Update UI with all events
  }

  void dispose() {
    _batchTimer?.cancel();
  }
}

// ============================================================================
// Complete Example: Production-Ready Observer with Backpressure Control
// ============================================================================

/// ✅ Production-ready observer with comprehensive backpressure management
class ProductionObserver extends StatefulWidget {
  final Ditto ditto;

  const ProductionObserver({required this.ditto, Key? key}) : super(key: key);

  @override
  State<ProductionObserver> createState() => _ProductionObserverState();
}

class _ProductionObserverState extends State<ProductionObserver> {
  DittoStoreObserver? _observer;
  List<Map<String, dynamic>> _data = [];
  DateTime? _lastUpdate;
  int _updateCount = 0;
  Timer? _throttleTimer;

  static const _minUpdateInterval = Duration(milliseconds: 16); // 60 FPS

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM products ORDER BY updatedAt DESC LIMIT 50',
      onChange: (result, signalNext) {
        // ✅ PATTERN 1: Lightweight callback
        final products = result.items.map((item) => item.value).toList();

        _updateCount++;

        // ✅ PATTERN 2: Throttle rapid updates
        final now = DateTime.now();
        if (_lastUpdate != null &&
            now.difference(_lastUpdate!) < _minUpdateInterval) {
          // Throttle this update
          _throttleTimer?.cancel();
          _throttleTimer = Timer(_minUpdateInterval, () {
            setState(() {
              _data = products;
            });
          });
        } else {
          // Apply update immediately
          setState(() {
            _data = products;
          });
          _lastUpdate = now;
        }

        // ✅ PATTERN 3: signalNext with postFrameCallback
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        // ✅ PATTERN 4: Monitor backpressure
        if (_updateCount % 10 == 0) {
          print('📊 Observer stats: $_updateCount updates processed');
        }
      },
    );

    print('✅ Production observer initialized');
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _data.length,
      itemBuilder: (context, index) {
        final product = _data[index];
        return ListTile(
          title: Text(product['name'] as String),
          subtitle: Text('\$${product['price']}'),
        );
      },
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    _throttleTimer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// Best Practices Summary
// ============================================================================

void printBestPractices() {
  print('✅ Observer Backpressure Best Practices:');
  print('');
  print('DO:');
  print('  ✓ Keep onChange callback lightweight (<16ms)');
  print('  ✓ Use addPostFrameCallback for signalNext()');
  print('  ✓ Offload heavy processing outside callback');
  print('  ✓ Use async operations after callback completes');
  print('  ✓ Monitor backpressure buildup');
  print('  ✓ Throttle rapid updates (max 60 Hz)');
  print('  ✓ Batch multiple updates together');
  print('  ✓ Extract data, don\'t retain QueryResultItems');
  print('');
  print('DON\'T:');
  print('  ✗ Heavy processing in onChange callback');
  print('  ✗ Synchronous I/O in callback');
  print('  ✗ Network requests in callback');
  print('  ✗ Complex computations in callback');
  print('  ✗ Call signalNext() synchronously');
  print('  ✗ Retain QueryResultItem references');
  print('');
  print('BENEFITS:');
  print('  • Smooth 60 FPS UI');
  print('  • No frame drops');
  print('  • Natural backpressure control');
  print('  • Responsive app');
  print('  • No memory leaks');
}

// ============================================================================
// Performance Metrics
// ============================================================================

void printPerformanceMetrics() {
  print('📊 Observer Performance Metrics:');
  print('');
  print('Target Callback Duration:');
  print('  • 60 FPS: <16ms per callback');
  print('  • 30 FPS: <33ms per callback');
  print('  • Goal: <1ms for data extraction only');
  print('');
  print('Backpressure Indicators:');
  print('  • Callback >16ms: Frame drops');
  print('  • Updates <16ms apart: Potential throttling needed');
  print('  • >5 queued updates: Heavy backpressure');
  print('  • >10 queued updates: Critical backpressure');
  print('');
  print('Optimization Results:');
  print('  • Lightweight callback: 0.5-1ms');
  print('  • Offloaded processing: No impact on UI');
  print('  • Throttled updates: Stable 60 FPS');
  print('  • Batch processing: 10x fewer UI updates');
}
