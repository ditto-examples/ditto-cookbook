// ============================================================================
// Flutter State Management Anti-Patterns with Ditto Observers
// ============================================================================
//
// This example demonstrates common state management mistakes that cause
// severe performance problems in Flutter apps using Ditto observers.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Full screen setState() in observer callback
// 2. ❌ Single observer for entire app state
// 3. ❌ Heavy processing in observer callback
// 4. ❌ No signalNext() call
// 5. ❌ Retaining QueryResultItem references
// 6. ❌ Observer not cancelled on dispose
// 7. ❌ Synchronous blocking operations in callback
//
// WHY THESE ARE PROBLEMS:
// - Full screen rebuilds cause lag and stuttering
// - Performance degrades with app complexity
// - Memory leaks from retained observers
// - Observer backpressure buildup
//
// SOLUTION: See flutter-state-management-good.dart for correct patterns
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN 1: Full Screen setState() in Observer
// ============================================================================

/// ❌ BAD: setState() on entire screen causes full rebuild
class TodoScreenBad extends StatefulWidget {
  final Ditto ditto;

  const TodoScreenBad({required this.ditto, Key? key}) : super(key: key);

  @override
  State<TodoScreenBad> createState() => _TodoScreenBadState();
}

class _TodoScreenBadState extends State<TodoScreenBad> {
  DittoSyncSubscription? _subscription;
  DittoStoreObserver? _observer;
  List<Map<String, dynamic>> _todos = [];
  int _totalTodos = 0;
  int _completedTodos = 0;

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _subscription = widget.ditto.sync.registerSubscription(
      'SELECT * FROM todos ORDER BY createdAt DESC',
    );

    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos ORDER BY createdAt DESC',
      onChange: (result, signalNext) {
        // ❌ BAD: Full screen setState()
        setState(() {
          _todos = result.items.map((item) => item.value).toList();
          _totalTodos = _todos.length;
          _completedTodos = _todos.where((t) => t['isCompleted'] == true).length;
        });

        signalNext();

        // 🚨 PROBLEM:
        // - Entire screen rebuilds (AppBar, FloatingActionButton, all list items)
        // - Every widget's build() method re-executes
        // - Causes visible lag and stuttering
        // - Performance degrades with screen complexity
      },
    );

    print('❌ Observer with full screen setState() initialized');
  }

  @override
  Widget build(BuildContext context) {
    print('🔄 FULL SCREEN REBUILD (expensive!)');
    print('  Rebuilding AppBar, body, FAB, and ALL ${_todos.length} list items');

    // 🚨 PROBLEM: This entire build() re-executes on every data change
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos'), // ❌ Rebuilds unnecessarily
        actions: [
          // ❌ Stats widget rebuilds even if stats didn't change
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('$_completedTodos/$_totalTodos'),
            ),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _todos.length,
        itemBuilder: (context, index) {
          final todo = _todos[index];
          // ❌ Every list item rebuilds, even if unchanged
          return ListTile(
            title: Text(todo['title'] as String),
            leading: Checkbox(
              value: todo['isCompleted'] as bool? ?? false,
              onChanged: (_) => _toggleTodo(todo['_id'] as String),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        // ❌ FAB rebuilds unnecessarily
        onPressed: _addTodo,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _toggleTodo(String todoId) async {
    await widget.ditto.store.execute(
      'UPDATE todos SET isCompleted = NOT isCompleted WHERE _id = :id',
      arguments: {'id': todoId},
    );
  }

  Future<void> _addTodo() async {
    // Add todo logic
  }

  @override
  void dispose() {
    _observer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

// ============================================================================
// ANTI-PATTERN 2: Single Observer for All App State
// ============================================================================

/// ❌ BAD: One massive observer for entire app
class AppStateBad extends StatefulWidget {
  final Ditto ditto;

  const AppStateBad({required this.ditto, Key? key}) : super(key: key);

  @override
  State<AppStateBad> createState() => _AppStateBadState();
}

class _AppStateBadState extends State<AppStateBad> {
  DittoStoreObserver? _observer;

  // ❌ BAD: All app state in single widget
  List<Map<String, dynamic>> _todos = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    // ❌ BAD: Single observer queries multiple collections
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos',
      onChange: (result, signalNext) {
        setState(() {
          _todos = result.items.map((item) => item.value).toList();
        });
        signalNext();

        // Then query other collections...
        _queryUsers();
        _queryMessages();
        _queryNotifications();

        // 🚨 PROBLEMS:
        // - One collection change triggers full app rebuild
        // - Inefficient cascading queries
        // - No granular control
        // - Poor performance
      },
    );
  }

  void _queryUsers() {
    // Query and setState for users (causes another rebuild)
  }

  void _queryMessages() {
    // Query and setState for messages (causes another rebuild)
  }

  void _queryNotifications() {
    // Query and setState for notifications (causes another rebuild)
  }

  @override
  Widget build(BuildContext context) {
    print('🔄 ENTIRE APP REBUILDING (very expensive!)');

    // ❌ Entire app tree rebuilds
    return Scaffold(
      body: Column(
        children: [
          _buildTodosSection(), // ❌ Rebuilds
          _buildUsersSection(), // ❌ Rebuilds
          _buildMessagesSection(), // ❌ Rebuilds
          _buildNotificationsSection(), // ❌ Rebuilds
        ],
      ),
    );
  }

  Widget _buildTodosSection() {
    // Build todos UI
    return Container();
  }

  Widget _buildUsersSection() {
    // Build users UI
    return Container();
  }

  Widget _buildMessagesSection() {
    // Build messages UI
    return Container();
  }

  Widget _buildNotificationsSection() {
    // Build notifications UI
    return Container();
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// ANTI-PATTERN 3: Heavy Processing in Observer Callback
// ============================================================================

/// ❌ BAD: Heavy processing blocks observer callback
class HeavyProcessingBad extends StatefulWidget {
  final Ditto ditto;

  const HeavyProcessingBad({required this.ditto, Key? key}) : super(key: key);

  @override
  State<HeavyProcessingBad> createState() => _HeavyProcessingBadState();
}

class _HeavyProcessingBadState extends State<HeavyProcessingBad> {
  DittoStoreObserver? _observer;
  List<Map<String, dynamic>> _processedTodos = [];

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos',
      onChange: (result, signalNext) {
        print('❌ Starting heavy processing in observer callback...');

        // ❌ BAD: Heavy processing in callback
        final todos = result.items.map((item) => item.value).toList();

        // ❌ Complex sorting (expensive for large lists)
        todos.sort((a, b) {
          final priorityA = a['priority'] as int? ?? 0;
          final priorityB = b['priority'] as int? ?? 0;
          final dateA = DateTime.parse(a['createdAt'] as String);
          final dateB = DateTime.parse(b['createdAt'] as String);

          if (priorityA != priorityB) {
            return priorityB.compareTo(priorityA);
          }
          return dateB.compareTo(dateA);
        });

        // ❌ Complex filtering and transformation
        final processed = todos.map((todo) {
          // Expensive string operations
          final title = todo['title'] as String;
          final processedTitle = title.toUpperCase().trim();

          // Complex calculations
          final createdAt = DateTime.parse(todo['createdAt'] as String);
          final daysOld = DateTime.now().difference(createdAt).inDays;
          final urgency = _calculateUrgency(todo, daysOld);

          return {
            ...todo,
            'processedTitle': processedTitle,
            'daysOld': daysOld,
            'urgency': urgency,
          };
        }).toList();

        setState(() {
          _processedTodos = processed;
        });

        signalNext();

        print('  ❌ Heavy processing complete (blocked callback for ${todos.length} items)');

        // 🚨 PROBLEMS:
        // - Callback blocked during processing
        // - Observer backpressure builds up
        // - UI freezes during processing
        // - Subsequent updates delayed
      },
    );
  }

  double _calculateUrgency(Map<String, dynamic> todo, int daysOld) {
    // ❌ Expensive calculation
    final priority = todo['priority'] as int? ?? 0;
    final isOverdue = todo['dueDate'] != null &&
        DateTime.parse(todo['dueDate'] as String).isBefore(DateTime.now());

    return priority * (daysOld / 30) * (isOverdue ? 2.0 : 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _processedTodos.length,
        itemBuilder: (context, index) {
          final todo = _processedTodos[index];
          return ListTile(
            title: Text(todo['processedTitle'] as String),
            subtitle: Text('Urgency: ${todo['urgency']}'),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// ANTI-PATTERN 4: No signalNext() Call
// ============================================================================

/// ❌ BAD: Missing signalNext() causes observer to stop
class NoSignalNextBad extends StatefulWidget {
  final Ditto ditto;

  const NoSignalNextBad({required this.ditto, Key? key}) : super(key: key);

  @override
  State<NoSignalNextBad> createState() => _NoSignalNextBadState();
}

class _NoSignalNextBadState extends State<NoSignalNextBad> {
  DittoStoreObserver? _observer;
  List<Map<String, dynamic>> _todos = [];

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos',
      onChange: (result, signalNext) {
        setState(() {
          _todos = result.items.map((item) => item.value).toList();
        });

        // ❌ BAD: Forgot to call signalNext()
        // signalNext(); // <-- MISSING!

        print('❌ Updated todos but did NOT call signalNext()');

        // 🚨 PROBLEM:
        // - Observer stops receiving updates after first callback
        // - Subsequent data changes not reflected in UI
        // - Silent failure (no error, just stops working)
        // - Very difficult bug to diagnose
      },
    );

    print('❌ Observer initialized (will stop after first update)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Todos (${_todos.length})'),
      ),
      body: ListView.builder(
        itemCount: _todos.length,
        itemBuilder: (context, index) {
          final todo = _todos[index];
          return ListTile(title: Text(todo['title'] as String));
        },
      ),
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// ANTI-PATTERN 5: Retaining QueryResultItem References
// ============================================================================

/// ❌ BAD: Storing QueryResultItems causes memory leak
class RetainedItemsBad extends StatefulWidget {
  final Ditto ditto;

  const RetainedItemsBad({required this.ditto, Key? key}) : super(key: key);

  @override
  State<RetainedItemsBad> createState() => _RetainedItemsBadState();
}

class _RetainedItemsBadState extends State<RetainedItemsBad> {
  DittoStoreObserver? _observer;
  List<QueryResultItem> _todoItems = []; // ❌ BAD: Storing items directly

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos',
      onChange: (result, signalNext) {
        setState(() {
          // ❌ BAD: Storing QueryResultItem references
          _todoItems = result.items.toList();
        });

        signalNext();

        print('❌ Stored ${_todoItems.length} QueryResultItem references (memory leak)');

        // 🚨 PROBLEMS:
        // - QueryResultItems hold internal references
        // - Prevents garbage collection
        // - Memory usage grows unbounded
        // - App crashes with OutOfMemoryError
        // - Performance degrades over time
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _todoItems.length,
        itemBuilder: (context, index) {
          final item = _todoItems[index];
          final todo = item.value; // ❌ Accessing through retained item
          return ListTile(title: Text(todo['title'] as String));
        },
      ),
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// ANTI-PATTERN 6: Observer Not Cancelled on Dispose
// ============================================================================

/// ❌ BAD: Observer not cancelled causes memory leak
class NotCancelledBad extends StatefulWidget {
  final Ditto ditto;

  const NotCancelledBad({required this.ditto, Key? key}) : super(key: key);

  @override
  State<NotCancelledBad> createState() => _NotCancelledBadState();
}

class _NotCancelledBadState extends State<NotCancelledBad> {
  DittoStoreObserver? _observer;
  List<Map<String, dynamic>> _todos = [];

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos',
      onChange: (result, signalNext) {
        setState(() {
          _todos = result.items.map((item) => item.value).toList();
        });
        signalNext();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _todos.length,
        itemBuilder: (context, index) {
          final todo = _todos[index];
          return ListTile(title: Text(todo['title'] as String));
        },
      ),
    );
  }

  @override
  void dispose() {
    // ❌ BAD: Forgot to cancel observer
    // _observer?.cancel(); // <-- MISSING!

    print('❌ Widget disposed but observer NOT cancelled');

    super.dispose();

    // 🚨 PROBLEMS:
    // - Observer continues running after widget destroyed
    // - Callback may call setState() on disposed widget (crash)
    // - Memory leak (observer never released)
    // - Multiple observers accumulate over time
    // - Performance degrades
  }
}

// ============================================================================
// ANTI-PATTERN 7: Synchronous Blocking Operations in Callback
// ============================================================================

/// ❌ BAD: Blocking operations in observer callback
class BlockingOperationsBad extends StatefulWidget {
  final Ditto ditto;

  const BlockingOperationsBad({required this.ditto, Key? key}) : super(key: key);

  @override
  State<BlockingOperationsBad> createState() => _BlockingOperationsBadState();
}

class _BlockingOperationsBadState extends State<BlockingOperationsBad> {
  DittoStoreObserver? _observer;
  List<Map<String, dynamic>> _todos = [];

  @override
  void initState() {
    super.initState();
    _setupObserver();
  }

  void _setupObserver() {
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos',
      onChange: (result, signalNext) {
        print('❌ Starting blocking operations...');

        // ❌ BAD: Synchronous file I/O
        // final file = File('todos.json');
        // file.writeAsStringSync(jsonEncode(result.items.map((i) => i.value).toList()));

        // ❌ BAD: Network request (blocking)
        // final response = http.get(Uri.parse('https://api.example.com/sync'));

        // ❌ BAD: Database write (blocking)
        // database.insert('todos_cache', todos);

        // ❌ BAD: Complex computation (blocking)
        _performComplexCalculations(result.items.length);

        setState(() {
          _todos = result.items.map((item) => item.value).toList();
        });

        signalNext();

        print('  ❌ Blocking operations complete');

        // 🚨 PROBLEMS:
        // - Observer callback blocked
        // - UI freezes
        // - Subsequent updates delayed
        // - Poor user experience
      },
    );
  }

  void _performComplexCalculations(int count) {
    // ❌ Expensive calculation blocking callback
    var sum = 0.0;
    for (var i = 0; i < count * 10000; i++) {
      sum += i * 3.14159;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _todos.length,
        itemBuilder: (context, index) {
          final todo = _todos[index];
          return ListTile(title: Text(todo['title'] as String));
        },
      ),
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// Performance Impact Summary
// ============================================================================

void printPerformanceImpact() {
  print('❌ Performance Impact of Anti-Patterns:');
  print('');
  print('Full Screen setState():');
  print('  • 10-100x slower than granular rebuilds');
  print('  • Visible lag and stuttering');
  print('  • Worsens with app complexity');
  print('');
  print('Single Observer for All State:');
  print('  • Unnecessary rebuilds on every change');
  print('  • Cascading queries and rebuilds');
  print('  • Poor scalability');
  print('');
  print('Heavy Processing in Callback:');
  print('  • Observer backpressure buildup');
  print('  • UI freezes');
  print('  • Delayed updates');
  print('');
  print('No signalNext():');
  print('  • Observer stops after first update');
  print('  • Silent failure (hard to debug)');
  print('');
  print('Retained QueryResultItems:');
  print('  • Memory leak');
  print('  • App crashes (OutOfMemoryError)');
  print('  • Performance degrades over time');
  print('');
  print('Observer Not Cancelled:');
  print('  • setState() on disposed widget (crash)');
  print('  • Memory leak');
  print('  • Multiple observers accumulate');
  print('');
  print('Blocking Operations:');
  print('  • UI freezes');
  print('  • Observer callback blocked');
  print('  • Poor user experience');
}
