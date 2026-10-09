// Recommended subscription patterns for Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// Rules:
// - A subscription query is SELECT * FROM <collection> [WHERE <condition>].
//   Projections, DISTINCT, aggregates, JOIN, USE IDS, LIMIT and ORDER BY are
//   rejected when registerSubscription is called.
// - Subscriptions are long-lived (app or feature scope) and scoped by stable
//   partition keys. Avoid changing subscriptions more often than about every
//   15 minutes.
// - Keep a reference to every SyncSubscription and cancel() it when its data is
//   no longer relevant. Cancelling does not delete local data.
// - UI filters, search, tabs, and sorting change local observers, not
//   subscriptions.

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

/// ✅ GOOD: A session-level service owns the long-lived subscriptions of one
/// workspace (store). Create it after login; call leaveStore() on logout.
class OrderSync {
  OrderSync(this._ditto);

  final Ditto _ditto;
  final List<SyncSubscription> _subscriptions = [];
  String? _storeId;

  String? get storeId => _storeId;

  /// Call once after login or when the user enters a store.
  void enterStore(String storeId) {
    if (_storeId == storeId) return; // Already subscribed: keep it stable.
    leaveStore();
    _storeId = storeId;
    // Scope by a stable partition key; screens filter further locally.
    // orderItems carries a copied storeId because subscriptions cannot join.
    _subscriptions
      ..add(_ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ))
      ..add(_ditto.sync.registerSubscription(
        'SELECT * FROM orderItems WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ))
      // A small reference-data collection that every device needs may be
      // subscribed to without a filter.
      ..add(_ditto.sync.registerSubscription('SELECT * FROM productCategories'));
  }

  /// Call on logout or when the user leaves the store.
  void leaveStore() {
    for (final subscription in _subscriptions) {
      subscription.cancel(); // No-op if already cancelled or Ditto was closed.
    }
    _subscriptions.clear();
    _storeId = null;
  }
}

/// ✅ GOOD: Switching stores: cancel first, evict the old store's data from this
/// device, then subscribe to the new store. Evicting documents that still match
/// an active subscription is futile: peers send them back.
Future<List<SyncSubscription>> switchStore(
  Ditto ditto,
  List<SyncSubscription> currentSubscriptions,
  String newStoreId,
) async {
  for (final subscription in currentSubscriptions) {
    subscription.cancel();
  }

  await ditto.store.execute(
    'EVICT FROM orders WHERE storeId != :storeId',
    arguments: {'storeId': newStoreId},
  );
  await ditto.store.execute(
    'EVICT FROM orderItems WHERE storeId != :storeId',
    arguments: {'storeId': newStoreId},
  );

  return [
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': newStoreId},
    ),
    ditto.sync.registerSubscription(
      'SELECT * FROM orderItems WHERE storeId = :storeId',
      arguments: {'storeId': newStoreId},
    ),
  ];
}

/// ✅ GOOD (soft delete, Variant A): Soft-deleted documents stay in the
/// subscription; local queries hide them with coalesce(isDeleted, false) = false.
/// The deletion flag is a change every device must receive. Old flagged
/// documents are removed by a synced DELETE (for example on the Ditto Server);
/// for device-side EVICT, use a retention-window subscription (Variant B, see
/// the storage-lifecycle skill).
SyncSubscription subscribeToTeamTasks(Ditto ditto, String teamId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM tasks WHERE teamId = :teamId',
    arguments: {'teamId': teamId},
  );
}

/// ✅ GOOD: Subscriptions for a local JOIN: one per collection the join reads.
List<SyncSubscription> subscribeForOrderList(Ditto ditto, String storeId) => [
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription(
        'SELECT * FROM customers WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
    ];

/// ✅ GOOD: The subscription (owned by OrderSync) stays stable while the user
/// switches status filters; only the local observer is replaced.
class OrdersByStatus extends StatefulWidget {
  const OrdersByStatus({
    super.key,
    required this.ditto,
    required this.storeId,
    required this.status,
  });

  final Ditto ditto;
  final String storeId;
  final String status;

  @override
  State<OrdersByStatus> createState() => _OrdersByStatusState();
}

class _OrdersByStatusState extends State<OrdersByStatus> {
  StoreObserver? _observer;
  StreamSubscription<QueryResult>? _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observe();
  }

  @override
  void didUpdateWidget(OrdersByStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status || oldWidget.storeId != widget.storeId) {
      _stopObserving();
      _observe(); // Replacing a local observer is cheap.
    }
  }

  void _observe() {
    final observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE storeId = :storeId AND status = :status '
      'ORDER BY createdAt DESC, _id',
      arguments: {'storeId': widget.storeId, 'status': widget.status},
    );
    _observer = observer;
    _changes = observer.changes.listen((result) {
      setState(() {
        _orders = result.items.map((item) => item.value).toList();
      });
    });
  }

  void _stopObserving() {
    unawaited(_changes?.cancel());
    _observer?.cancel();
  }

  @override
  void dispose() {
    _stopObserving();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
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

/// ✅ GOOD: Inspect active subscriptions for debugging only. Read queryString
/// and isCancelled. Note (SDK 5.1.0): do not read queryArguments or
/// queryArgumentsJsonString here; for subscriptions registered without
/// arguments this can terminate the app. Keep your own references instead.
void logActiveSubscriptions(Ditto ditto) {
  for (final subscription in ditto.sync.subscriptions) {
    debugPrint('subscription: ${subscription.queryString} '
        'cancelled=${subscription.isCancelled}');
  }
}

/// ✅ GOOD: Pausing sync does not require cancelling subscriptions.
/// stop() pauses them; start() resumes them.
void pauseSync(Ditto ditto) => ditto.sync.stop();
void resumeSync(Ditto ditto) => ditto.sync.start();
