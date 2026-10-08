// Store observer anti-patterns for Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// Every example compiles, but leaks memory, never cleans up, throws at
// runtime, or rebuilds far more UI than needed. The corrected versions are in
// observer-patterns-good.dart and observer-backpressure.dart.

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

/// ❌ BAD: onChange only. Every result is also queued in the unconsumed
/// `changes` stream and stays in memory for the lifetime of the observer, so
/// memory use grows with every update (Note (SDK 5.1.0)).
StoreObserver observeOrdersWithCallbackOnly(
  Ditto ditto,
  void Function(int) onCount,
) {
  return ditto.store.registerObserver(
    'SELECT * FROM orders ORDER BY createdAt DESC',
    onChange: (result) => onCount(result.items.length),
  );
}

/// ❌ BAD: Registered in build(), never cancelled. Each rebuild creates another
/// observer, and the StreamBuilder gets a fresh stream every time.
class OrdersInBuild extends StatelessWidget {
  const OrdersInBuild({super.key, required this.ditto});

  final Ditto ditto;

  @override
  Widget build(BuildContext context) {
    final observer = ditto.store.registerObserver(
      'SELECT * FROM orders ORDER BY createdAt DESC, _id',
    );
    return StreamBuilder<QueryResult>(
      stream: observer.changes,
      builder: (context, snapshot) =>
          Text('${snapshot.data?.items.length ?? 0} orders'),
    );
  }
}

/// ❌ BAD: Only the stream subscription is cancelled. Cancelling the
/// StreamSubscription does not cancel a StoreObserver.
class HalfCleanedUp extends StatefulWidget {
  const HalfCleanedUp({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<HalfCleanedUp> createState() => _HalfCleanedUpState();
}

class _HalfCleanedUpState extends State<HalfCleanedUp> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT _id FROM orders ORDER BY _id',
    );
    _changes = _observer.changes.listen((result) {
      setState(() => _count = result.items.length);
    });
  }

  @override
  void dispose() {
    _changes.cancel(); // Missing: _observer.cancel()
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('$_count');
}

/// ❌ BAD: Listening to `changes` twice. It is a single-subscription stream,
/// so the second listen() throws "Bad state: Stream has already been
/// listened to" (also after the first subscription was cancelled).
void listenTwice(StoreObserver observer) {
  observer.changes.listen((result) => debugPrint('list: ${result.items.length}'));
  observer.changes.listen((result) => debugPrint('badge: ${result.items.length}'));
}

/// ❌ BAD: Keeping the QueryResult in state. It references native memory
/// until garbage-collected; copy item.value (or models) instead.
class RetainsResult extends StatefulWidget {
  const RetainsResult({super.key, required this.observer});

  final StoreObserver observer;

  @override
  State<RetainsResult> createState() => _RetainsResultState();
}

class _RetainsResultState extends State<RetainsResult> {
  QueryResult? _lastResult;
  late final StreamSubscription<QueryResult> _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.observer.changes.listen((result) {
      setState(() => _lastResult = result);
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text('${_lastResult?.items.length ?? 0} rows');
}

/// ❌ BAD: No ORDER BY. Rows may change position between updates.
StoreObserver observeTasksUnordered(Ditto ditto) =>
    ditto.store.registerObserver('SELECT * FROM tasks WHERE done = false');

/// ❌ BAD: Slow async work in a registerObserver listener. There is no
/// backpressure: uploads overlap and results queue up while each one waits.
/// Use registerObserverV2 or registerObserverWithSignalNext (Experimental).
StreamSubscription<QueryResult> uploadOnEveryChange(
  StoreObserver observer,
  Future<void> Function(List<Map<String, dynamic>>) upload,
) {
  return observer.changes.listen((result) async {
    await upload(result.items.map((item) => item.value).toList());
  });
}

/// ❌ BAD: Writing to the observed collection from its own observer without a
/// guard. Each write triggers the observer again.
StreamSubscription<QueryResult> touchOnEveryChange(
  Ditto ditto,
  StoreObserver ordersObserver,
) {
  return ordersObserver.changes.listen((result) {
    unawaited(ditto.store.execute(
      'UPDATE orders SET lastSeenAt = :now WHERE status = :status',
      arguments: {
        'now': DateTime.now().toUtc().toIso8601String(),
        'status': 'open',
      },
    ));
  });
}

/// ❌ BAD: One observer per list item. Observe the list once and pass values
/// down to the rows.
class OrderRow extends StatefulWidget {
  const OrderRow({super.key, required this.ditto, required this.orderId});

  final Ditto ditto;
  final String orderId;

  @override
  State<OrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends State<OrderRow> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  Map<String, dynamic>? _order;

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': widget.orderId},
    );
    _changes = _observer.changes.listen((result) {
      setState(() => _order = result.items.isEmpty ? null : result.items.first.value);
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('${_order?['status']}');
}

/// ❌ BAD: Observing a whole collection at the root and rebuilding the entire
/// screen (app bar, filters, list) on every change. Use one small observer
/// per region instead.
class WholeScreenObserver extends StatefulWidget {
  const WholeScreenObserver({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<WholeScreenObserver> createState() => _WholeScreenObserverState();
}

class _WholeScreenObserverState extends State<WholeScreenObserver> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver('SELECT * FROM orders');
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
    final open = _orders.where((o) => o['status'] == 'open').toList();
    return Scaffold(
      appBar: AppBar(title: Text('Open orders: ${open.length}')),
      body: ListView(
        children: [for (final o in open) ListTile(title: Text('${o['_id']}'))],
      ),
    );
  }
}
