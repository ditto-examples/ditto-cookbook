// ============================================================================
// Flutter State Management with Ditto Observers (Correct Patterns)
// ============================================================================
//
// This example demonstrates proper state management patterns for Ditto observers
// in Flutter, using Riverpod for granular rebuilds and optimal performance.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Riverpod providers for Ditto observers
// 2. ✅ Granular widget rebuilds (not full screen setState)
// 3. ✅ Family providers for per-item updates
// 4. ✅ signalNext() with WidgetsBinding.addPostFrameCallback
// 5. ✅ Proper subscription lifecycle management
// 6. ✅ Observer cleanup on dispose
// 7. ✅ Scoped state updates
//
// WHY RIVERPOD:
// - Granular rebuilds (only affected widgets)
// - No full-screen setState() performance issues
// - Automatic disposal and lifecycle management
// - Clean separation of business logic and UI
//
// ALTERNATIVE: ValueListenableBuilder, DittoDiffer (see partial-ui-updates.dart)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Riverpod Providers for Ditto Observers
// ============================================================================

/// ✅ GOOD: Ditto instance provider
final dittoProvider = Provider<Ditto>((ref) {
  // Initialize Ditto (assume already initialized)
  throw UnimplementedError('Provide initialized Ditto instance');
});

/// ✅ GOOD: Todo list observer with StateNotifier
class TodoListNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  final Ditto ditto;
  DittoSyncSubscription? _subscription;
  DittoStoreObserver? _observer;

  TodoListNotifier(this.ditto) : super([]) {
    _initialize();
  }

  void _initialize() {
    print('📋 Initializing todo list observer...');

    // Create subscription
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM todos WHERE isCompleted != true ORDER BY createdAt DESC',
    );

    // Create observer with signalNext
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos WHERE isCompleted != true ORDER BY createdAt DESC',
      onChange: (result, signalNext) {
        // ✅ Extract data (lightweight operation)
        final todos = result.items.map((item) => item.value).toList();

        // ✅ Update state (only this provider notifies listeners)
        state = todos;

        // ✅ Signal next after UI update
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        print('  ✅ Todos updated: ${todos.length} items');
      },
    );

    print('✅ Todo list observer initialized');
  }

  @override
  void dispose() {
    print('🧹 Cleaning up todo list observer...');
    _observer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

/// ✅ Provider for todo list
final todoListProvider = StateNotifierProvider<TodoListNotifier, List<Map<String, dynamic>>>((ref) {
  final ditto = ref.watch(dittoProvider);
  return TodoListNotifier(ditto);
});

// ============================================================================
// PATTERN 2: Granular Widget Rebuilds
// ============================================================================

/// ✅ GOOD: Only todo list widget rebuilds (not entire screen)
class TodoListWidget extends ConsumerWidget {
  const TodoListWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Only this widget rebuilds when todos change
    final todos = ref.watch(todoListProvider);

    print('🔄 TodoListWidget rebuilding (${todos.length} todos)');

    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (context, index) {
        final todo = todos[index];
        return TodoItemWidget(todoId: todo['_id'] as String);
      },
    );
  }
}

/// ✅ Screen widget does NOT rebuild when todos change
class TodoScreenGood extends StatelessWidget {
  const TodoScreenGood({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print('🏗️ TodoScreenGood building (one-time)');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos'),
        // ✅ Stats widget rebuilds independently
        actions: const [TodoStatsWidget()],
      ),
      body: const TodoListWidget(), // ✅ Only this rebuilds on data change
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add todo logic
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ============================================================================
// PATTERN 3: Family Providers for Per-Item Updates
// ============================================================================

/// ✅ GOOD: Individual todo observer (only rebuilds affected item)
class TodoItemNotifier extends StateNotifier<Map<String, dynamic>?> {
  final Ditto ditto;
  final String todoId;
  DittoStoreObserver? _observer;

  TodoItemNotifier(this.ditto, this.todoId) : super(null) {
    _initialize();
  }

  void _initialize() {
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos WHERE _id = :id',
      arguments: {'id': todoId},
      onChange: (result, signalNext) {
        if (result.items.isNotEmpty) {
          state = result.items.first.value;
        } else {
          state = null;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });
      },
    );
  }

  Future<void> toggleComplete() async {
    if (state == null) return;

    final isCompleted = state!['isCompleted'] as bool? ?? false;

    await ditto.store.execute(
      'UPDATE todos SET isCompleted = :completed WHERE _id = :id',
      arguments: {'id': todoId, 'completed': !isCompleted},
    );

    print('✅ Todo $todoId: isCompleted = ${!isCompleted}');
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

/// ✅ Family provider for individual todo items
final todoItemProvider = StateNotifierProvider.family<TodoItemNotifier, Map<String, dynamic>?, String>(
  (ref, todoId) {
    final ditto = ref.watch(dittoProvider);
    return TodoItemNotifier(ditto, todoId);
  },
);

/// ✅ GOOD: Individual todo item widget (rebuilds independently)
class TodoItemWidget extends ConsumerWidget {
  final String todoId;

  const TodoItemWidget({required this.todoId, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Only THIS item rebuilds when its data changes
    final todo = ref.watch(todoItemProvider(todoId));

    if (todo == null) {
      return const SizedBox.shrink();
    }

    final title = todo['title'] as String;
    final isCompleted = todo['isCompleted'] as bool? ?? false;

    print('🔄 TodoItem $todoId rebuilding');

    return ListTile(
      title: Text(
        title,
        style: isCompleted
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      leading: Checkbox(
        value: isCompleted,
        onChanged: (_) {
          ref.read(todoItemProvider(todoId).notifier).toggleComplete();
        },
      ),
    );
  }
}

// ============================================================================
// PATTERN 4: Statistics Widget with Separate Observer
// ============================================================================

/// ✅ GOOD: Stats observer (rebuilds only stats widget)
class TodoStatsNotifier extends StateNotifier<TodoStats> {
  final Ditto ditto;
  DittoStoreObserver? _observer;

  TodoStatsNotifier(this.ditto) : super(TodoStats(total: 0, completed: 0)) {
    _initialize();
  }

  void _initialize() {
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT COUNT(*) as total, SUM(CASE WHEN isCompleted = true THEN 1 ELSE 0 END) as completed FROM todos',
      onChange: (result, signalNext) {
        if (result.items.isNotEmpty) {
          final doc = result.items.first.value;
          state = TodoStats(
            total: doc['total'] as int? ?? 0,
            completed: doc['completed'] as int? ?? 0,
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });
      },
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

class TodoStats {
  final int total;
  final int completed;

  TodoStats({required this.total, required this.completed});

  int get remaining => total - completed;
}

final todoStatsProvider = StateNotifierProvider<TodoStatsNotifier, TodoStats>((ref) {
  final ditto = ref.watch(dittoProvider);
  return TodoStatsNotifier(ditto);
});

/// ✅ GOOD: Stats widget rebuilds independently of todo list
class TodoStatsWidget extends ConsumerWidget {
  const TodoStatsWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(todoStatsProvider);

    print('🔄 TodoStatsWidget rebuilding');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Text(
          '${stats.remaining}/${stats.total}',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

// ============================================================================
// PATTERN 5: Filtered List with Separate Provider
// ============================================================================

/// ✅ GOOD: Completed todos observer (separate from active todos)
class CompletedTodosNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  final Ditto ditto;
  DittoSyncSubscription? _subscription;
  DittoStoreObserver? _observer;

  CompletedTodosNotifier(this.ditto) : super([]) {
    _initialize();
  }

  void _initialize() {
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM todos WHERE isCompleted = true ORDER BY completedAt DESC',
    );

    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM todos WHERE isCompleted = true ORDER BY completedAt DESC',
      onChange: (result, signalNext) {
        state = result.items.map((item) => item.value).toList();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });

        print('  ✅ Completed todos updated: ${state.length} items');
      },
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

final completedTodosProvider = StateNotifierProvider<CompletedTodosNotifier, List<Map<String, dynamic>>>((ref) {
  final ditto = ref.watch(dittoProvider);
  return CompletedTodosNotifier(ditto);
});

/// ✅ GOOD: Tabbed interface with independent observers
class TodoTabsScreen extends StatelessWidget {
  const TodoTabsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Todos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            TodoListWidget(), // ✅ Only active todos observer
            CompletedTodosListWidget(), // ✅ Only completed todos observer
          ],
        ),
      ),
    );
  }
}

class CompletedTodosListWidget extends ConsumerWidget {
  const CompletedTodosListWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(completedTodosProvider);

    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (context, index) {
        final todo = todos[index];
        return ListTile(
          title: Text(
            todo['title'] as String,
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
          trailing: const Icon(Icons.check_circle, color: Colors.green),
        );
      },
    );
  }
}

// ============================================================================
// PATTERN 6: Search/Filter with Reactive Provider
// ============================================================================

/// ✅ GOOD: Search query provider (triggers observer updates)
final searchQueryProvider = StateProvider<String>((ref) => '');

/// ✅ GOOD: Filtered todos based on search
class FilteredTodosNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  final Ditto ditto;
  final Ref ref;
  DittoStoreObserver? _observer;

  FilteredTodosNotifier(this.ditto, this.ref) : super([]) {
    // Listen to search query changes
    ref.listen<String>(searchQueryProvider, (previous, next) {
      _updateObserver(next);
    });

    _updateObserver('');
  }

  void _updateObserver(String searchQuery) {
    _observer?.cancel();

    if (searchQuery.isEmpty) {
      // No filter
      _observer = ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM todos WHERE isCompleted != true ORDER BY createdAt DESC',
        onChange: _handleChange,
      );
    } else {
      // Filter by search query
      _observer = ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM todos WHERE isCompleted != true AND title LIKE :query ORDER BY createdAt DESC',
        arguments: {'query': '%$searchQuery%'},
        onChange: _handleChange,
      );
    }

    print('🔍 Observer updated with search: "$searchQuery"');
  }

  void _handleChange(QueryResult result, void Function() signalNext) {
    state = result.items.map((item) => item.value).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

final filteredTodosProvider = StateNotifierProvider<FilteredTodosNotifier, List<Map<String, dynamic>>>((ref) {
  final ditto = ref.watch(dittoProvider);
  return FilteredTodosNotifier(ditto, ref);
});

/// ✅ GOOD: Search screen with reactive filtering
class TodoSearchScreen extends ConsumerWidget {
  const TodoSearchScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(filteredTodosProvider);
    final searchQuery = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(
            hintText: 'Search todos...',
            border: InputBorder.none,
          ),
          onChanged: (value) {
            // ✅ Update search query (triggers observer update)
            ref.read(searchQueryProvider.notifier).state = value;
          },
        ),
      ),
      body: ListView.builder(
        itemCount: todos.length,
        itemBuilder: (context, index) {
          final todo = todos[index];
          return ListTile(
            title: Text(todo['title'] as String),
          );
        },
      ),
    );
  }
}

// ============================================================================
// PATTERN 7: Complex Screen with Multiple Independent Observers
// ============================================================================

/// ✅ GOOD: Dashboard with multiple independent data sources
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    print('🏗️ DashboardScreen building (one-time)');

    // ✅ Each widget has its own observer and rebuilds independently
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: const [TodoStatsWidget()],
      ),
      body: Column(
        children: [
          // ✅ Recent todos section (independent observer)
          const Expanded(
            flex: 2,
            child: Card(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Recent Todos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: TodoListWidget()),
                ],
              ),
            ),
          ),
          // ✅ Completed todos section (independent observer)
          const Expanded(
            flex: 1,
            child: Card(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Completed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: CompletedTodosListWidget()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Complete Example: Production App Structure
// ============================================================================

/// ✅ Production-ready app with proper state management
class TodoApp extends StatelessWidget {
  const TodoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Ditto Todos',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: const TodoTabsScreen(),
      ),
    );
  }
}

// ============================================================================
// Best Practices Summary
// ============================================================================

void printBestPractices() {
  print('✅ Riverpod State Management Best Practices:');
  print('');
  print('DO:');
  print('  ✓ Use StateNotifierProvider for Ditto observers');
  print('  ✓ Granular providers (per-list, per-item, per-stat)');
  print('  ✓ signalNext() with WidgetsBinding.addPostFrameCallback');
  print('  ✓ Cancel observers in dispose()');
  print('  ✓ Extract lightweight data in onChange callback');
  print('  ✓ Use family providers for per-item observers');
  print('  ✓ Separate subscriptions and observers per provider');
  print('');
  print('DON\'T:');
  print('  ✗ setState() on entire screen');
  print('  ✗ Single provider for all data');
  print('  ✗ Heavy processing in onChange callback');
  print('  ✗ Forget to cancel observers');
  print('  ✗ Retain QueryResultItem references');
  print('');
  print('BENEFITS:');
  print('  • Only affected widgets rebuild');
  print('  • 10-100x better performance vs full screen setState');
  print('  • Clean separation of concerns');
  print('  • Automatic disposal and lifecycle management');
  print('  • Scalable to complex UIs');
}
