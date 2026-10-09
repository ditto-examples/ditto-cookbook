// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter
// Last Updated: 2026-10-08
//
// ============================================================================
// Partial UI Updates and Diffing (Flutter)
// ============================================================================
//
// Guide sections (.claude/guides/best-practices/ditto.md):
// - #partial-ui-updates
// - #diffing-results
// - #animated-lists
//
// An observer delivers a new result for any change that affects its query.
// Keep each observer narrow and attach it to the smallest widget that needs
// the data, so a change rebuilds only that region.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ One small observer per screen region (badge, list)
// 2. ✅ ListView.builder with a ValueKey(_id) per row (no Differ needed)
// 3. ✅ Differ to log what changed between results
// 4. ✅ Differ driving an AnimatedList
// 5. ❌ One broad observer at the root of the screen
//
// Differ facts:
// - diff() takes a List<QueryResultItem>; pass result.items.toList().
// - The first call reports every item as an insertion.
// - deletions index the OLD list; insertions and updates index the NEW list.
// - Identity is _id; values are compared deeply.
// - Differ keeps the previous result in memory and diffing is expensive:
//   keep diffed queries bounded (for example with LIMIT).
// - Differ does not return old items; keep previous values yourself.
//
// ============================================================================

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

// ============================================================================
// PATTERN 1: One observer per region
// ============================================================================

/// ✅ GOOD: The badge observes a count and rebuilds only its own Text.
class OpenOrdersCount extends StatefulWidget {
  const OpenOrdersCount({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OpenOrdersCount> createState() => _OpenOrdersCountState();
}

class _OpenOrdersCountState extends State<OpenOrdersCount> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  final _count = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      final n = result.items.isEmpty ? 0 : result.items.first.value['n'];
      // ValueNotifier only notifies listeners when the value actually changes.
      _count.value = n is int ? n : 0;
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _count,
        builder: (context, count, _) => Text('Open orders: $count'),
      );
}

// ============================================================================
// PATTERN 2: Lazy list with keys
// ============================================================================

/// ✅ GOOD: Only visible rows are built, and ValueKey(_id) preserves row state
/// across updates. A plain ListView.builder like this does not need Differ.
class OrdersByStatus extends StatefulWidget {
  const OrdersByStatus({super.key, required this.ditto, required this.status});

  final Ditto ditto;
  final String status;

  @override
  State<OrdersByStatus> createState() => _OrdersByStatusState();
}

class _OrdersByStatusState extends State<OrdersByStatus> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT _id, status, total FROM orders WHERE status = :status '
      'ORDER BY createdAt DESC, _id LIMIT 200',
      arguments: {'status': widget.status},
    );
    _changes = _observer.changes.listen((result) {
      setState(() => _orders = result.items.map((item) => item.value).toList());
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        return ListTile(
          key: ValueKey(order['_id']),
          title: Text('${order['_id']}'),
          trailing: Text('${order['total']}'),
        );
      },
    );
  }
}

/// ✅ GOOD: The screen itself observes nothing; each region rebuilds
/// independently.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, required this.ditto});

  final Ditto ditto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: OpenOrdersCount(ditto: ditto)),
      body: OrdersByStatus(ditto: ditto, status: 'open'),
    );
  }
}

// ============================================================================
// PATTERN 3: Logging changes with Differ
// ============================================================================

/// ✅ GOOD: Report inserted, deleted, updated, and moved documents.
StreamSubscription<QueryResult> logOrderChanges(StoreObserver observer) {
  final differ = Differ();
  var previousIds = <Object?>[];

  return observer.changes.listen((result) {
    final items = result.items.toList(); // diff() takes a List.
    final Diff diff = differ.diff(items);
    final currentIds = items.map((item) => item.value['_id']).toList();

    for (final index in diff.deletions) {
      debugPrint('deleted ${previousIds[index]}'); // Index into the OLD list.
    }
    for (final index in diff.insertions) {
      debugPrint('inserted ${currentIds[index]}'); // Index into the NEW list.
    }
    for (final index in diff.updates) {
      debugPrint('updated ${currentIds[index]}'); // Index into the NEW list.
    }
    for (final DiffMove move in diff.moves) {
      debugPrint('moved ${move.from} -> ${move.to}');
    }
    previousIds = currentIds;
  });
}

/// Registers a bounded observer for logOrderChanges.
StoreObserver observeRecentOrders(Ditto ditto) => ditto.store.registerObserver(
      'SELECT * FROM orders ORDER BY updatedAt DESC, _id LIMIT 100',
    );

// ============================================================================
// PATTERN 4: Differ driving an AnimatedList
// ============================================================================

/// ✅ GOOD: Removals in descending order of old indexes, insertions in
/// ascending order of new indexes. A move is treated as removal + insertion.
class AnimatedOrders extends StatefulWidget {
  const AnimatedOrders({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<AnimatedOrders> createState() => _AnimatedOrdersState();
}

class _AnimatedOrdersState extends State<AnimatedOrders> {
  final _listKey = GlobalKey<AnimatedListState>();
  final _differ = Differ();
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen(_apply);
  }

  void _apply(QueryResult result) {
    final items = result.items.toList();
    final diff = _differ.diff(items);
    final previous = _orders;
    final next = items.map((item) => item.value).toList();
    final list = _listKey.currentState;

    if (list != null) {
      // Remove from the end so earlier old indexes stay valid.
      final removed = {...diff.deletions, for (final m in diff.moves) m.from}.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final index in removed) {
        final order = previous[index];
        list.removeItem(index, (context, animation) => _row(order, animation));
      }
      // Insert in ascending order of new indexes.
      final inserted = {...diff.insertions, for (final m in diff.moves) m.to}.toList()
        ..sort();
      for (final index in inserted) {
        list.insertItem(index);
      }
    }
    // Updated rows are rebuilt with the new values.
    setState(() => _orders = next);
  }

  Widget _row(Map<String, dynamic> order, Animation<double> animation) => SizeTransition(
        sizeFactor: animation,
        child: ListTile(title: Text('${order['_id']}'), subtitle: Text('${order['status']}')),
      );

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedList(
        key: _listKey,
        initialItemCount: _orders.length,
        itemBuilder: (context, index, animation) => _row(_orders[index], animation),
      );
}

// ============================================================================
// ANTI-PATTERN 5: One broad observer at the root
// ============================================================================

/// ❌ BAD: The root widget observes every order and rebuilds the app bar and
/// the whole list for any change. The badge is computed in Dart instead of
/// with COUNT(*), and rows have no keys.
class OrdersScreenBad extends StatefulWidget {
  const OrdersScreenBad({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OrdersScreenBad> createState() => _OrdersScreenBadState();
}

class _OrdersScreenBadState extends State<OrdersScreenBad> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _all = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver('SELECT * FROM orders');
    _changes = _observer.changes.listen((result) {
      setState(() => _all = result.items.map((item) => item.value).toList());
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _all.where((o) => o['status'] == 'open').toList();
    return Scaffold(
      appBar: AppBar(title: Text('Open orders: ${open.length}')),
      body: ListView(children: [for (final o in open) ListTile(title: Text('${o['_id']}'))]),
    );
  }
}
