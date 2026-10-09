// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter
// Last Updated: 2026-10-08
//
// ============================================================================
// State Management Anti-Patterns with Ditto Observers
// ============================================================================
//
// Guide sections (.claude/guides/best-practices/ditto.md):
// - #store-observers-in-flutter
// - #observer-lifecycle-and-cleanup
// - #keep-observer-callbacks-fast
// - #partial-ui-updates
//
// Every class below compiles, but each one shows a mistake. The fix for each
// is in flutter-state-management-good.dart or flutter-observer-performance.dart.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ One broad observer at the root; full-screen setState on every change
// 2. ❌ QueryResult objects kept in state
// 3. ❌ onChange only and no cancel() (results retained, observer leaked)
// 4. ❌ Listening to `changes` twice (StateError)
// 5. ❌ Heavy synchronous work inside the listener
// 6. ❌ One observer per list item
// 7. ❌ Writing to the observed collection from its own listener
//
// ============================================================================

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

// ============================================================================
// ANTI-PATTERN 1 + 2: Broad observer, full-screen setState, QueryResult in state
// ============================================================================

/// ❌ BAD: Observes the whole collection without ORDER BY or LIMIT, keeps the
/// QueryResult in state, and rebuilds the app bar, filters, and list on every
/// change to any order.
class OrdersDashboardBad extends StatefulWidget {
  const OrdersDashboardBad({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OrdersDashboardBad> createState() => _OrdersDashboardBadState();
}

class _OrdersDashboardBadState extends State<OrdersDashboardBad> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  QueryResult? _result; // ❌ References native memory until garbage-collected.

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver('SELECT * FROM orders');
    _changes = _observer.changes.listen((result) {
      setState(() => _result = result); // ❌ Rebuilds the entire screen.
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
    final result = _result;
    // ❌ Each access to `items` creates new wrappers and decodes rows again.
    final open = result?.items.where((item) => item.value['status'] == 'open') ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text('Open orders (${open.length})')), // ❌ Count in Dart.
      body: ListView(
        children: [
          for (final item in result?.items ?? const <QueryResultItem>[])
            ListTile(title: Text('${item.value['_id']}')), // ❌ No ValueKey.
        ],
      ),
    );
  }
}

// ============================================================================
// ANTI-PATTERN 3: onChange only and no cancel()
// ============================================================================

/// ❌ BAD: onChange only, so every result is also queued in the unconsumed
/// `changes` stream and retained (SDK 5.1.0). dispose() never cancels the
/// observer, so it keeps running after the widget is gone and setState is
/// called on an unmounted State.
class LeakyOrderList extends StatefulWidget {
  const LeakyOrderList({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<LeakyOrderList> createState() => _LeakyOrderListState();
}

class _LeakyOrderListState extends State<LeakyOrderList> {
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    widget.ditto.store.registerObserver(
      'SELECT * FROM orders ORDER BY createdAt DESC',
      onChange: (result) {
        setState(() => _orders = result.items.map((item) => item.value).toList());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [for (final o in _orders) Text('${o['_id']}')]);
  }
}

// ============================================================================
// ANTI-PATTERN 4: Listening to `changes` twice
// ============================================================================

/// ❌ BAD: `changes` is a single-subscription stream. The second listen()
/// throws a StateError (`Bad state: Stream has already been listened to.`),
/// even if the first subscription was cancelled. Use one listener and fan out
/// plain values yourself (for example through a ValueNotifier).
void listenTwice(Ditto ditto) {
  final observer = ditto.store.registerObserver(
    'SELECT * FROM orders ORDER BY createdAt DESC',
  );
  observer.changes.listen((result) => debugPrint('list: ${result.items.length}'));
  observer.changes.listen((result) => debugPrint('badge: ${result.items.length}'));
}

// ============================================================================
// ANTI-PATTERN 5: Heavy synchronous work in the listener
// ============================================================================

/// ❌ BAD: Expensive computation on the UI isolate for every update. Keep the
/// listener short and move heavy work to `compute()` on copied values.
StreamSubscription<QueryResult> heavyListener(StoreObserver observer) {
  return observer.changes.listen((result) {
    final orders = result.items.map((item) => item.value).toList();
    var checksum = 0;
    for (var round = 0; round < 1000; round++) {
      for (final order in orders) {
        checksum ^= order.toString().hashCode + round;
      }
    }
    debugPrint('checksum $checksum');
  });
}

// ============================================================================
// ANTI-PATTERN 6: One observer per list item
// ============================================================================

/// ❌ BAD: Every row registers its own observer. Observe the list once and
/// pass values down to the rows instead.
class OrderRowWithOwnObserver extends StatefulWidget {
  const OrderRowWithOwnObserver({super.key, required this.ditto, required this.orderId});

  final Ditto ditto;
  final String orderId;

  @override
  State<OrderRowWithOwnObserver> createState() => _OrderRowWithOwnObserverState();
}

class _OrderRowWithOwnObserverState extends State<OrderRowWithOwnObserver> {
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
  Widget build(BuildContext context) => ListTile(title: Text('${_order?['status']}'));
}

// ============================================================================
// ANTI-PATTERN 7: Writing to the observed collection from its own listener
// ============================================================================

/// ❌ BAD: Each write triggers the observer again. This UPDATE has no guard
/// (it rewrites the same value), so every update causes another update.
/// Guard writes with a WHERE condition that skips documents already in the
/// target state, or move the logic out of the observer.
StreamSubscription<QueryResult> selfTriggeringObserver(Ditto ditto, StoreObserver observer) {
  return observer.changes.listen((result) {
    unawaited(ditto.store.execute(
      'UPDATE orders SET reviewed = true WHERE status = :status',
      arguments: {'status': 'open'},
    ));
  });
}
