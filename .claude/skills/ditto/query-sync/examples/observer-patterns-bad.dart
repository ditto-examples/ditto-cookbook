// ============================================================================
// Observer Anti-Patterns
// ============================================================================
//
// This example demonstrates common anti-patterns when using Ditto observers,
// showing problems that lead to memory leaks, performance issues, and bugs.
//
// ⚠️ IMPORTANT: Anti-patterns related to signalNext (patterns #1, #6) do NOT apply
// to Flutter SDK v4.14.0 and earlier, as registerObserverWithSignalNext is not available.
// These patterns apply to non-Flutter SDKs (Swift, JS, Kotlin).
//
// For Flutter SDK v4.x patterns, see: flutter-observer-v4-patterns.dart
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ No signalNext() call (observer backpressure)
// 2. ❌ Full screen setState() (Flutter performance issue)
// 3. ❌ Retained QueryResultItems (memory leaks)
// 4. ❌ Heavy processing in callback (UI lag)
// 5. ❌ Missing observer cancellation (memory leaks)
// 6. ❌ registerObserver without signalNext control
// 7. ❌ Synchronous blocking operations in observer
//
// WHY THESE ARE PROBLEMS:
// - Memory leaks from retained references
// - UI performance degradation
// - Observer backpressure buildup
// - Application crashes from memory exhaustion
// - Poor user experience
//
// SOLUTION: See query-sync/SKILL.md and dql-queries-good.dart for correct patterns
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'package:flutter/material.dart';

// ============================================================================
// ANTI-PATTERN 1: No signalNext() Call (Observer Backpressure)
// ============================================================================

/// ❌ BAD: Observer without signalNext() stops receiving updates
class TodoListBadNoSignalNext extends StatefulWidget {
  final Ditto ditto;

  const TodoListBadNoSignalNext({required this.ditto, super.key});

  @override
  State<TodoListBadNoSignalNext> createState() => _TodoListBadNoSignalNextState();
}

class _TodoListBadNoSignalNextState extends State<TodoListBadNoSignalNext> {
  List<Map<String, dynamic>> _todos = [];
  DittoStoreObserver? _observer;

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos ORDER BY createdAt DESC',
      onChange: (result, signalNext) {
        setState(() {
          _todos = result.items.map((item) => item.value).toList();
        });

        // ❌ BAD: Never calling signalNext()!
        // Observer will stop receiving updates after first callback
        // This is observer backpressure - Ditto waits for signalNext()
        // to ensure callback has finished processing before sending more updates
      },
    );

    print('❌ Observer created WITHOUT signalNext() call');
    print('   Observer will receive first update, then stop');
    print('   Subsequent database changes will NOT trigger callbacks');
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _todos.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(_todos[index]['title'] as String));
      },
    );
  }
}

// ============================================================================
// ANTI-PATTERN 2: Full Screen setState() (Performance Issue)
// ============================================================================

/// ❌ BAD: Entire screen rebuilds on every data change
class HomeScreenBadFullRebuild extends StatefulWidget {
  final Ditto ditto;

  const HomeScreenBadFullRebuild({required this.ditto, super.key});

  @override
  State<HomeScreenBadFullRebuild> createState() => _HomeScreenBadFullRebuildState();
}

class _HomeScreenBadFullRebuildState extends State<HomeScreenBadFullRebuild> {
  List<Map<String, dynamic>> _todos = [];
  int _unreadCount = 0;
  String _userName = '';
  DittoStoreObserver? _observer;

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos WHERE done = false',
      onChange: (result, signalNext) {
        // ❌ BAD: setState() rebuilds ENTIRE widget tree!
        setState(() {
          _todos = result.items.map((item) => item.value).toList();
        });

        // Even though only _todos changed, setState() triggers rebuild of:
        // - AppBar (userName)
        // - Notifications badge (unreadCount)
        // - Bottom navigation
        // - All other widgets in this screen
        //
        // 🚨 PROBLEM: Full screen rebuild for every todo change
        // - Poor performance (unnecessary repaints)
        // - Animations may stutter
        // - Battery drain

        signalNext();
      },
    );

    print('❌ Observer triggers full screen setState()');
    print('   Entire widget tree rebuilds on every change');
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hello, $_userName'), // Rebuilt unnecessarily
        actions: [
          Badge(
            label: Text('$_unreadCount'),
            child: const Icon(Icons.notifications),
          ), // Rebuilt unnecessarily
        ],
      ),
      body: ListView.builder(
        itemCount: _todos.length,
        itemBuilder: (context, index) {
          return ListTile(title: Text(_todos[index]['title'] as String));
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ), // Rebuilt unnecessarily
    );
  }
}

// ============================================================================
// ANTI-PATTERN 3: Retained QueryResultItems (Memory Leak)
// ============================================================================

/// ❌ BAD: Storing QueryResultItems instead of extracting values
class TaskManagerBadRetainedItems extends StatefulWidget {
  final Ditto ditto;

  const TaskManagerBadRetainedItems({required this.ditto, super.key});

  @override
  State<TaskManagerBadRetainedItems> createState() => _TaskManagerBadRetainedItemsState();
}

class _TaskManagerBadRetainedItemsState extends State<TaskManagerBadRetainedItems> {
  // ❌ BAD: Storing QueryResultItems directly
  List<QueryResultItem> _taskItems = [];
  DittoStoreObserver? _observer;

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM tasks',
      onChange: (result, signalNext) {
        setState(() {
          // ❌ BAD: Storing QueryResultItems keeps references to internal Ditto objects
          _taskItems = result.items.toList();
          // This prevents garbage collection of internal Ditto data structures
          // Memory leak grows with every observer callback
          // Eventually causes OutOfMemoryError and crashes
        });

        signalNext();
      },
    );

    print('❌ Retained QueryResultItems cause memory leak');
    print('   Internal Ditto objects cannot be garbage collected');
    print('   Memory usage grows continuously');
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _taskItems.length,
      itemBuilder: (context, index) {
        // ❌ Accessing .value on retained item
        final task = _taskItems[index].value;
        return ListTile(title: Text(task['title'] as String));
      },
    );
  }
}

// ============================================================================
// ANTI-PATTERN 4: Heavy Processing in Observer Callback
// ============================================================================

/// ❌ BAD: Complex computations block observer callback
class AnalyticsDashboardBadHeavyProcessing extends StatefulWidget {
  final Ditto ditto;

  const AnalyticsDashboardBadHeavyProcessing({required this.ditto, super.key});

  @override
  State<AnalyticsDashboardBadHeavyProcessing> createState() =>
      _AnalyticsDashboardBadHeavyProcessingState();
}

class _AnalyticsDashboardBadHeavyProcessingState extends State<AnalyticsDashboardBadHeavyProcessing> {
  Map<String, int> _analytics = {};
  DittoStoreObserver? _observer;

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM events',
      onChange: (result, signalNext) {
        // ❌ BAD: Heavy processing directly in observer callback
        final events = result.items.map((item) => item.value).toList();

        // Complex aggregation (imagine 10,000 events)
        final analytics = <String, int>{};
        for (final event in events) {
          final eventType = event['type'] as String;
          analytics[eventType] = (analytics[eventType] ?? 0) + 1;

          // Imagine more complex computations here
          // - Statistical analysis
          // - Graph calculations
          // - Data transformations
        }

        setState(() {
          _analytics = analytics;
        });

        // 🚨 PROBLEMS:
        // - Observer callback takes seconds to complete
        // - UI freezes during computation
        // - signalNext() delayed, observer backpressure builds up
        // - Poor user experience

        signalNext();
      },
    );

    print('❌ Heavy processing blocks observer callback');
    print('   UI freezes during computation');
    print('   Observer backpressure builds up');
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: _analytics.entries
          .map((e) => ListTile(title: Text('${e.key}: ${e.value}')))
          .toList(),
    );
  }
}

// ============================================================================
// ANTI-PATTERN 5: Missing Observer Cancellation (Memory Leak)
// ============================================================================

/// ❌ BAD: Observer never canceled
class UserProfileBadNoCancellation extends StatefulWidget {
  final Ditto ditto;
  final String userId;

  const UserProfileBadNoCancellation({
    required this.ditto,
    required this.userId,
    super.key,
  });

  @override
  State<UserProfileBadNoCancellation> createState() => _UserProfileBadNoCancellationState();
}

class _UserProfileBadNoCancellationState extends State<UserProfileBadNoCancellation> {
  Map<String, dynamic>? _profile;
  DittoStoreObserver? _observer;

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM users WHERE _id = :userId',
      arguments: {'userId': widget.userId},
      onChange: (result, signalNext) {
        if (mounted) {
          setState(() {
            _profile = result.items.firstOrNull?.value;
          });
        }
        signalNext();
      },
    );
  }

  @override
  void dispose() {
    // ❌ BAD: Not canceling observer!
    // _observer?.cancel(); // This line is missing!
    super.dispose();
  }

  // 🚨 PROBLEMS:
  // - Observer continues running after widget disposed
  // - Callbacks try to update disposed widget
  // - Memory leak (observer + state never garbage collected)
  // - Can cause crashes if setState() called after dispose

  @override
  Widget build(BuildContext context) {
    if (_profile == null) {
      return const CircularProgressIndicator();
    }

    return Text(_profile!['name'] as String);
  }
}

// ============================================================================
// ANTI-PATTERN 6: Using registerObserver Without signalNext Control
// ============================================================================

/// ❌ BAD: registerObserver (deprecated, no backpressure control)
class TodoListBadRegisterObserver extends StatefulWidget {
  final Ditto ditto;

  const TodoListBadRegisterObserver({required this.ditto, super.key});

  @override
  State<TodoListBadRegisterObserver> createState() => _TodoListBadRegisterObserverState();
}

class _TodoListBadRegisterObserverState extends State<TodoListBadRegisterObserver> {
  List<Map<String, dynamic>> _todos = [];
  DittoStoreObserver? _observer;

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    // ❌ BAD: registerObserver doesn't provide signalNext()
    // No backpressure control!
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM todos',
      onChange: (result) {
        setState(() {
          _todos = result.items.map((item) => item.value).toList();
        });

        // 🚨 PROBLEM: No signalNext() available
        // Cannot control when next update arrives
        // If updates come faster than setState() can process,
        // updates queue up and overwhelm the app
      },
    );

    print('❌ registerObserver has no backpressure control');
    print('   Use registerObserverWithSignalNext instead');
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _todos.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(_todos[index]['title'] as String));
      },
    );
  }
}

// ============================================================================
// ANTI-PATTERN 7: Synchronous Blocking in Observer
// ============================================================================

/// ❌ BAD: Synchronous file I/O in observer callback
class ExportManagerBadSyncBlocking extends StatefulWidget {
  final Ditto ditto;

  const ExportManagerBadSyncBlocking({required this.ditto, super.key});

  @override
  State<ExportManagerBadSyncBlocking> createState() => _ExportManagerBadSyncBlockingState();
}

class _ExportManagerBadSyncBlockingState extends State<ExportManagerBadSyncBlocking> {
  DittoStoreObserver? _observer;

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM exportQueue WHERE status = "pending"',
      onChange: (result, signalNext) {
        // ❌ BAD: Synchronous blocking operations
        for (final item in result.items) {
          final data = item.value;

          // Synchronous file write (blocks observer callback!)
          // final file = File('/path/to/export.json');
          // file.writeAsStringSync(jsonEncode(data)); // ❌ Blocks!

          // Network request (blocks observer callback!)
          // final response = http.get(Uri.parse('...')); // ❌ Blocks!

          // Database query (blocks observer callback!)
          // final result = widget.ditto.store.execute('...'); // ❌ Blocks!
        }

        // 🚨 PROBLEMS:
        // - Observer callback blocked for seconds
        // - UI freezes
        // - Other observers can't fire
        // - App feels unresponsive

        signalNext();
      },
    );

    print('❌ Synchronous blocking operations in observer');
    print('   Observer callback takes too long');
    print('   UI becomes unresponsive');
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
