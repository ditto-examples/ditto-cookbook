// Recommended store observer patterns for Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// The recommended pattern registers the observer WITHOUT onChange, consumes
// the single-subscription `changes` stream with one StreamSubscription, and
// cancels both in dispose().
//
// Note (SDK 5.1.0): with onChange, every result is also queued in `changes`.
// If nothing listens to `changes`, the queued results are retained for the
// lifetime of the observer. Consume `changes` instead of using onChange.
//
// Observers read the local store only. Pair them with a long-lived
// subscription (see subscription-lifecycle-good.dart).

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

/// ✅ GOOD: The recommended observer pattern for widgets.
class OrdersList extends StatefulWidget {
  const OrdersList({super.key, required this.ditto});
  final Ditto ditto;
  @override
  State<OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<OrdersList> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      setState(() {
        _orders = result.items.map((item) => item.value).toList();
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          return ListTile(key: ValueKey(order['_id']), title: Text('${order['_id']}'));
        },
      );
}

/// ✅ GOOD: Lazy list with a ValueKey per row, deterministic order with an _id
/// tie-breaker, and a LIMIT that keeps the observer's result set small.
class TaskList extends StatefulWidget {
  const TaskList({super.key, required this.ditto, required this.teamId});

  final Ditto ditto;
  final String teamId;

  @override
  State<TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT _id, title, createdAt FROM tasks '
      'WHERE teamId = :teamId AND coalesce(isDeleted, false) = false '
      'ORDER BY createdAt DESC, _id LIMIT 200',
      arguments: {'teamId': widget.teamId},
    );
    _changes = _observer.changes.listen((result) {
      // Keep the listener synchronous and short: copy values, then setState.
      setState(() {
        _tasks = result.items.map((item) => item.value).toList();
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: _tasks.length,
        itemBuilder: (context, index) {
          final task = _tasks[index];
          return ListTile(
            key: ValueKey(task['_id']),
            title: Text('${task['title']}'),
          );
        },
      );
}

/// ✅ GOOD: StreamBuilder variant. The observer is created once in initState
/// and its stream is handed to exactly one StreamBuilder that stays mounted
/// for the observer's lifetime (a second listen() would throw).
class OpenOrdersStream extends StatefulWidget {
  const OpenOrdersStream({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OpenOrdersStream> createState() => _OpenOrdersStreamState();
}

class _OpenOrdersStreamState extends State<OpenOrdersStream> {
  late final StoreObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      arguments: {'status': 'open'},
    );
  }

  @override
  void dispose() {
    _observer.cancel(); // StreamBuilder's unsubscribe does not cancel the observer.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryResult>(
      stream: _observer.changes,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = result.items.map((item) => item.value).toList();
        return ListView(
          children: [
            for (final order in orders)
              ListTile(key: ValueKey(order['_id']), title: Text('${order['_id']}')),
          ],
        );
      },
    );
  }
}

/// ✅ GOOD: Partial UI updates. The badge observes COUNT(*) on its own, and a
/// ValueNotifier rebuilds only when the count actually changes.
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

/// ✅ GOOD: The screen observes nothing itself; each region has its own
/// observer and rebuilds independently.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, required this.ditto});

  final Ditto ditto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: OpenOrdersCount(ditto: ditto)),
      body: OrdersList(ditto: ditto),
    );
  }
}

/// ✅ GOOD: An observer owned by a non-widget controller (for example, used by
/// a state-management provider). The owner calls dispose().
/// The observed JOIN (SDK 5.1+) fires when either collection changes; each row
/// carries a composite _id. Subscribe to both collections separately.
class OpenOrdersWithCustomers {
  OpenOrdersWithCustomers(
    Ditto ditto,
    void Function(List<Map<String, dynamic>> rows) onRows,
  ) : _observer = ditto.store.registerObserver(
          'SELECT o._id AS orderId, o.total, c.name AS customerName '
          'FROM orders o JOIN customers c ON c._id = o.customerId '
          'WHERE o.status = :status ORDER BY o.createdAt DESC, o._id',
          arguments: {'status': 'open'},
        ) {
    _changes = _observer.changes.listen(
      (result) => onRows(result.items.map((item) => item.value).toList()),
    );
  }

  final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;

  void dispose() {
    _changes.cancel();
    _observer.cancel();
  }
}

/// ✅ GOOD: If an API forces you to use onChange, drain the changes stream too,
/// so results are not retained. Cancel the drain subscription with the observer.
class CallbackObserver {
  CallbackObserver(Ditto ditto, void Function(int count) onCount)
      : _observer = ditto.store.registerObserver(
          'SELECT * FROM orders WHERE status = :status ORDER BY _id',
          arguments: {'status': 'open'},
          onChange: (result) => onCount(result.items.length),
        ) {
    _drain = _observer.changes.listen((_) {});
  }

  final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _drain;

  void dispose() {
    _drain.cancel();
    _observer.cancel();
  }
}
