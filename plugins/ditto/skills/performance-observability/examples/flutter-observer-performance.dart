// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter
// Last Updated: 2026-10-08
//
// ============================================================================
// Store Observer Performance in Flutter
// ============================================================================
//
// Guide sections (.claude/guides/best-practices/ditto.md):
// - #store-observers-in-flutter
// - #stable-ordering
// - #observer-lifecycle-and-cleanup
// - #keep-observer-callbacks-fast
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Recommended pattern: no onChange, consume `changes`, cancel both
// 2. ✅ StreamBuilder variant (observer created once in initState)
// 3. ✅ Fast listeners: copy values, move heavy work off the UI isolate
// 4. ✅ Throttling UI updates for very busy collections
// 5. ✅ Draining `changes` when onChange is unavoidable
// 6. ❌ onChange only (results retained in memory, SDK 5.1.0)
// 7. ❌ Slow async work in a registerObserver listener
// 8. ❌ Observer without ORDER BY, observer created in build()
//
// For slow or async per-update work, see observer-backpressure.dart
// (registerObserverV2 / registerObserverWithSignalNext, Experimental).
//
// ============================================================================

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ============================================================================
// PATTERN 1: The recommended observer pattern
// ============================================================================

/// ✅ GOOD: Register without onChange, consume `changes` with one
/// StreamSubscription, and cancel both in dispose().
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
    // Listen right away: without onChange, the query starts on first listen.
    _changes = _observer.changes.listen((result) {
      setState(() {
        // Copy plain values; never keep QueryResult or QueryResultItem in state.
        _orders = result.items.map((item) => item.value).toList();
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel(); // Cancelling the stream does not cancel a StoreObserver.
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
          subtitle: Text('${order['status']}'),
        );
      },
    );
  }
}

// ============================================================================
// PATTERN 2: StreamBuilder variant
// ============================================================================

/// ✅ GOOD: The observer is created once; exactly one StreamBuilder listens.
///
/// `changes` is single-subscription. If the StreamBuilder were removed from the
/// tree and rebuilt with the same stream, the second listen would throw.
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

// ============================================================================
// PATTERN 3: Fast listeners, heavy work off the UI isolate
// ============================================================================

/// Plain summary computed from copied values (safe to send to another isolate).
class SalesSummary {
  const SalesSummary({required this.orderCount, required this.revenue});

  final int orderCount;
  final double revenue;
}

/// Top-level function so that `compute()` can run it on a background isolate.
SalesSummary summarizeOrders(List<Map<String, dynamic>> orders) {
  var revenue = 0.0;
  for (final order in orders) {
    revenue += (order['total'] as num?)?.toDouble() ?? 0;
  }
  return SalesSummary(orderCount: orders.length, revenue: revenue);
}

/// ✅ GOOD: The listener only copies values; the expensive part runs in
/// `compute()` on plain maps. Results that finish out of order are dropped.
class SalesSummaryView extends StatefulWidget {
  const SalesSummaryView({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<SalesSummaryView> createState() => _SalesSummaryViewState();
}

class _SalesSummaryViewState extends State<SalesSummaryView> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  SalesSummary? _summary;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT _id, total FROM orders WHERE status = :status',
      arguments: {'status': 'completed'},
    );
    _changes = _observer.changes.listen((result) {
      final values = result.items.map((item) => item.value).toList();
      final generation = ++_generation;
      unawaited(_summarize(values, generation));
    });
  }

  Future<void> _summarize(List<Map<String, dynamic>> values, int generation) async {
    final summary = await compute(summarizeOrders, values);
    // Ignore stale results and results that arrive after dispose().
    if (!mounted || generation != _generation) return;
    setState(() => _summary = summary);
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) return const Text('Calculating...');
    return Text('${summary.orderCount} orders, ${summary.revenue.toStringAsFixed(2)} total');
  }
}

// ============================================================================
// PATTERN 4: Throttling UI updates for very busy collections
// ============================================================================

/// ✅ GOOD: Keep only the latest values and rebuild at most every 250 ms when
/// the user cannot perceive every intermediate state.
class ThrottledReadings extends StatefulWidget {
  const ThrottledReadings({super.key, required this.ditto, required this.deviceId});

  final Ditto ditto;
  final String deviceId;

  @override
  State<ThrottledReadings> createState() => _ThrottledReadingsState();
}

class _ThrottledReadingsState extends State<ThrottledReadings> {
  static const _interval = Duration(milliseconds: 250);

  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _readings = const [];
  List<Map<String, dynamic>>? _pending;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM sensorReadings WHERE deviceId = :deviceId '
      'ORDER BY recordedAt DESC LIMIT 50',
      arguments: {'deviceId': widget.deviceId},
    );
    _changes = _observer.changes.listen((result) {
      _pending = result.items.map((item) => item.value).toList();
      _timer ??= Timer(_interval, _flush);
    });
  }

  void _flush() {
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (!mounted || pending == null) return;
    setState(() => _readings = pending);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final reading in _readings)
          ListTile(key: ValueKey(reading['_id']), title: Text('${reading['value']}')),
      ],
    );
  }
}

// ============================================================================
// PATTERN 5: When onChange is unavoidable, drain the stream
// ============================================================================

/// ✅ GOOD: If an API forces you to use onChange, also consume `changes` so
/// that queued results are released. Cancel both when done.
class CallbackOrderCounter {
  CallbackOrderCounter(Ditto ditto, void Function(int count) onCount) {
    _observer = ditto.store.registerObserver(
      'SELECT _id FROM orders WHERE status = :status',
      arguments: {'status': 'open'},
      onChange: (result) => onCount(result.items.length),
    );
    _drain = _observer.changes.listen((_) {});
  }

  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _drain;

  void cancel() {
    unawaited(_drain.cancel());
    _observer.cancel();
  }
}

// ============================================================================
// ANTI-PATTERNS
// ============================================================================

/// ❌ BAD: onChange only. Every result is also queued in the unconsumed
/// `changes` stream and stays in memory for the observer's lifetime, so
/// memory use grows with every update (Note (SDK 5.1.0)).
StoreObserver observeOrdersWithCallbackOnly(Ditto ditto, void Function(int) onCount) {
  return ditto.store.registerObserver(
    'SELECT * FROM orders ORDER BY createdAt DESC',
    onChange: (result) => onCount(result.items.length),
  );
}

/// ❌ BAD: Slow async work per update without backpressure. registerObserver
/// never waits for the listener, so uploads overlap and results queue up.
/// Use registerObserverV2 or registerObserverWithSignalNext instead.
StreamSubscription<QueryResult> uploadOnEveryChange(
  StoreObserver observer,
  Future<void> Function(List<Map<String, dynamic>>) upload,
) {
  return observer.changes.listen((result) async {
    await upload(result.items.map((item) => item.value).toList());
  });
}

/// ❌ BAD: No ORDER BY; rows may change position between updates.
StoreObserver observeTasksUnordered(Ditto ditto) =>
    ditto.store.registerObserver('SELECT * FROM tasks WHERE done = false');

/// ✅ GOOD: Deterministic order; _id breaks ties between equal timestamps.
StoreObserver observeTasksOrdered(Ditto ditto) => ditto.store.registerObserver(
      'SELECT * FROM tasks WHERE done = false ORDER BY createdAt DESC, _id',
    );

/// ❌ BAD: The observer is created in build(). Every rebuild registers a new
/// observer that is never cancelled. Even an observer that is never listened
/// to holds resources until it is cancelled.
class LeakyOrdersBadge extends StatelessWidget {
  const LeakyOrdersBadge({super.key, required this.ditto});

  final Ditto ditto;

  @override
  Widget build(BuildContext context) {
    ditto.store.registerObserver('SELECT COUNT(*) AS n FROM orders');
    return const Text('Orders');
  }
}
