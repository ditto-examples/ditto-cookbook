// Subscription anti-patterns for Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// Every example compiles and runs, but wastes bandwidth and storage, churns
// the mesh, or leaks subscriptions. The corrected versions are in
// subscription-lifecycle-good.dart.
//
// Subscription queries that are rejected when registerSubscription is called
// (described here instead of executed):
// - Projection:        SELECT _id, status FROM orders
//   -> "Unsupported feature: A projection other than wildcard (*)"
// - Aggregate:         SELECT COUNT(*) AS n FROM orders (same error)
// - DISTINCT:          SELECT DISTINCT status FROM orders
//   -> "Unsupported feature: DISTINCT"
// - GROUP BY:          SELECT * FROM orders GROUP BY status
//   -> "Unsupported feature: Grouping"
// - JOIN:              SELECT * FROM orders o JOIN customers c ON c._id = o.customerId
//   -> "Unsupported feature: Joining"
// - USE IDS:           SELECT * FROM orders USE IDS 'order-1'
//   -> "Unsupported feature: USE IDS"
// - LIMIT / ORDER BY:  SELECT * FROM orders WHERE storeId = :storeId ORDER BY createdAt DESC LIMIT 50
//   -> "Unsupported feature: Limit or Order by" (while DQL_RESTRICT_SUBSCRIPTIONS
//      has its default value true; keep the default)
// Subscribe with SELECT * FROM c WHERE ... and sort, limit, project, or join in
// local queries instead.

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

/// ❌ BAD: A new subscription on every rebuild, never cancelled. build() can
/// run many times per second; each call adds a subscription that keeps
/// replicating until the Ditto instance is closed.
class OrdersBadge extends StatelessWidget {
  const OrdersBadge({super.key, required this.ditto, required this.storeId});

  final Ditto ditto;
  final String storeId;

  @override
  Widget build(BuildContext context) {
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
    return const Icon(Icons.receipt_long);
  }
}

/// ❌ BAD: Subscription owned by a screen. Every visit registers and cancels
/// it, making peers across the mesh re-evaluate what they owe the device and
/// interrupting in-flight transfers. Own it in an app/feature service.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.ditto, required this.storeId});

  final Ditto ditto;
  final String storeId;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final SyncSubscription _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': widget.storeId},
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// ❌ BAD: Re-registering the subscription whenever the user changes a filter
/// or search term. Change the local observer instead.
class OrderSearchSync {
  OrderSearchSync(this._ditto);

  final Ditto _ditto;
  SyncSubscription? _subscription;

  void onSearchChanged(String storeId, String status, String customerName) {
    _subscription?.cancel();
    _subscription = _ditto.sync.registerSubscription(
      'SELECT * FROM orders '
      'WHERE storeId = :storeId AND status = :status AND customerName = :name',
      arguments: {'storeId': storeId, 'status': status, 'name': customerName},
    );
  }
}

/// ❌ BAD: The reference is dropped without cancelling. Always release
/// subscriptions explicitly; do not rely on garbage collection to cancel them.
void subscribeAndForget(Ditto ditto, String storeId) {
  ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}

/// ❌ BAD: Every device receives and stores every order of every tenant.
/// Filter by stable partition keys (tenant, store, region, team).
SyncSubscription subscribeToEverything(Ditto ditto) {
  return ditto.sync.registerSubscription('SELECT * FROM orders');
}

/// ❌ BAD: Filtering the subscription on fields that change often. Documents
/// leave the subscription's scope when they change state, so devices and
/// relays stop following them. Excluding soft-deleted documents has a similar
/// effect: devices that did not already hold a flagged document never store
/// it, so they cannot relay the flag, and a cleanup DELETE does not reach the
/// flagged copies that other devices keep (local queries must still filter
/// them). Keep soft-deleted documents in the subscription (Variant A) or use a
/// retention window (Variant B), as described in the guide section
/// "Soft delete, subscriptions, and cleanup".
SyncSubscription subscribeToOpenUndeletedOrders(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId AND status = :status '
    'AND coalesce(isDeleted, false) = false',
    arguments: {'storeId': storeId, 'status': 'open'},
  );
}

/// ❌ BAD: Values interpolated into the subscription string. Use parameters.
SyncSubscription subscribeWithInterpolation(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    "SELECT * FROM orders WHERE storeId = '$storeId'",
  );
}

/// ❌ BAD: Evicting while the matching subscription is still active. Connected
/// peers notice the missing documents and send them back. Cancel first.
Future<void> evictWhileSubscribed(Ditto ditto, String oldStoreId) async {
  await ditto.store.execute(
    'EVICT FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': oldStoreId},
  );
}

/// ❌ BAD: Expecting execute() to fetch data from peers. Without a matching
/// subscription it only sees what is already stored locally, and an empty
/// result does not mean that no data exists.
Future<bool> orderExistsAnywhere(Ditto ditto, String orderId) async {
  final result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE _id = :id LIMIT 1',
    arguments: {'id': orderId},
  );
  return result.items.isNotEmpty;
}
