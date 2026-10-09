// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter
// Last Updated: 2026-10-08
//
// ============================================================================
// State Management with Ditto Observers (Correct Patterns)
// ============================================================================
//
// Guide sections (../../guide/reference/ditto.md):
// - § Store Observers in Flutter
// - § Observer lifecycle and cleanup
// - § Partial UI Updates
// - § Working with Query Results
//
// This example uses only the Flutter SDK (ChangeNotifier, ValueNotifier) so it
// works with any state management approach. The same rules apply to Riverpod,
// Bloc, or Provider: one provider or controller owns each observer, consumes
// its `changes` stream exactly once, and cancels the stream subscription and
// the observer in its dispose hook (for example, ref.onDispose in Riverpod).
//
// PATTERNS DEMONSTRATED:
// 1. ✅ A controller that owns one observer and cancels it in dispose()
// 2. ✅ Immutable model objects (with ==) instead of QueryResult objects
// 3. ✅ Separate observers for separate screen regions (badge vs list)
// 4. ✅ Scoped rebuilds with ListenableBuilder / ValueListenableBuilder
// 5. ✅ Subscription at feature scope, observers at screen scope
//
// ============================================================================

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

// ============================================================================
// Model
// ============================================================================

/// Immutable order model. `item.value` creates a new Map for every result, and
/// two maps with identical contents are never `==`, so compare models instead.
@immutable
class Order {
  const Order({required this.id, required this.status, required this.total});

  factory Order.fromValue(Map<String, dynamic> value) => Order(
        id: value['_id'] as String,
        status: value['status'] as String? ?? 'unknown',
        total: (value['total'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String status;
  final double total;

  @override
  bool operator ==(Object other) =>
      other is Order && other.id == id && other.status == status && other.total == total;

  @override
  int get hashCode => Object.hash(id, status, total);
}

bool _sameOrders(List<Order> a, List<Order> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ============================================================================
// PATTERN 1 + 2: A controller that owns one observer
// ============================================================================

/// ✅ GOOD: Owns exactly one observer, listens to `changes` once, exposes
/// plain model objects, and notifies only when the visible data changed.
class OrdersController extends ChangeNotifier {
  OrdersController(Ditto ditto, {required String status}) {
    _observer = ditto.store.registerObserver(
      'SELECT _id, status, total FROM orders WHERE status = :status '
      'ORDER BY createdAt DESC, _id LIMIT 200',
      arguments: {'status': status},
    );
    _changes = _observer.changes.listen((result) {
      final next = result.items.map((item) => Order.fromValue(item.value)).toList();
      if (_sameOrders(next, _orders)) return; // Skip rebuilds for identical data.
      _orders = next;
      notifyListeners();
    });
  }

  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Order> _orders = const [];

  List<Order> get orders => _orders;

  @override
  void dispose() {
    unawaited(_changes.cancel());
    _observer.cancel(); // Cancelling the stream does not cancel a StoreObserver.
    super.dispose();
  }
}

/// ✅ GOOD: A separate, tiny observer for a summary value. COUNT(*) instead of
/// loading the list just to read `.length`.
class OpenOrderCount {
  OpenOrderCount(Ditto ditto) {
    _observer = ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      final n = result.items.isEmpty ? 0 : result.items.first.value['n'];
      count.value = n is int ? n : 0; // ValueNotifier notifies only on change.
    });
  }

  final ValueNotifier<int> count = ValueNotifier<int>(0);
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;

  void dispose() {
    unawaited(_changes.cancel());
    _observer.cancel();
    count.dispose();
  }
}

// ============================================================================
// PATTERN 3 + 4: Scoped rebuilds
// ============================================================================

/// ✅ GOOD: The screen itself observes nothing. The badge and the list each
/// rebuild independently when their own data changes.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final OrdersController _orders;
  late final OpenOrderCount _openCount;

  @override
  void initState() {
    super.initState();
    // Observers follow screen scope: created here, released in dispose().
    _orders = OrdersController(widget.ditto, status: 'open');
    _openCount = OpenOrderCount(widget.ditto);
  }

  @override
  void dispose() {
    _orders.dispose();
    _openCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<int>(
          valueListenable: _openCount.count,
          builder: (context, count, _) => Text('Open orders ($count)'),
        ),
      ),
      body: ListenableBuilder(
        listenable: _orders,
        builder: (context, _) {
          final orders = _orders.orders;
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              // ValueKey keeps row state attached to the right document.
              return OrderTile(key: ValueKey(order.id), order: order);
            },
          );
        },
      ),
    );
  }
}

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(order.id),
      subtitle: Text('${order.status} - ${order.total.toStringAsFixed(2)}'),
    );
  }
}

// ============================================================================
// PATTERN 5: Subscription at feature scope
// ============================================================================

/// ✅ GOOD: Subscriptions live longer than screens. Observers never sync data;
/// the subscription decides what reaches this device.
class OrdersFeature {
  OrdersFeature(this._ditto);

  final Ditto _ditto;
  SyncSubscription? _subscription;

  void start() {
    _subscription ??= _ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'open'},
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
