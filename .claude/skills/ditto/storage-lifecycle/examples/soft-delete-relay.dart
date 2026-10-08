// SDK Version: ditto_live 5.1.0
// Platform: Flutter (the DQL applies to all SDKs)
// Last Updated: 2026-10-08
//
// Soft delete that propagates reliably through the mesh.
//
// Guide: .claude/guides/best-practices/ditto.md#soft-delete
//        .claude/guides/best-practices/ditto.md#soft-delete-subscriptions-and-cleanup
//
// Key rules:
// - Soft delete is an ordinary UPDATE, so it syncs like any other change and
//   does not depend on the tombstone TTL.
// - Filter with coalesce(isDeleted, false) = false. `isDeleted != true` and
//   `NOT isDeleted` silently drop documents where the field is missing or null.
// - Keep flagged documents in the subscription at least until every device
//   (including relays) has received the flag. Two designs:
//   Variant A: subscribe to the whole collection or partition; clean up with a
//   DELETE on the Ditto Server (or another authorized peer) that syncs to
//   every device. Device-side EVICT does not work here (documents sync back).
//   Variant B: subscribe to active documents plus documents deleted within a
//   retention window; each device evicts exactly the complement.

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

String nowUtc() => DateTime.now().toUtc().toIso8601String();

// ============================================================================
// Writes
// ============================================================================

/// ✅ GOOD: New documents start with isDeleted = false.
Future<void> createOrder(Ditto ditto, String orderId, String status) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId,
        'status': status,
        'isDeleted': false,
        'createdAt': nowUtc(),
      },
    },
  );
}

/// ✅ GOOD: Set a flag and a UTC timestamp instead of deleting.
Future<void> softDeleteOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
    arguments: {'id': orderId, 'deletedAt': nowUtc()},
  );
}

/// ✅ GOOD: A soft delete can be undone.
Future<void> restoreOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = false UNSET deletedAt WHERE _id = :id',
    arguments: {'id': orderId},
  );
}

// ============================================================================
// Reads
// ============================================================================

/// ✅ GOOD: coalesce() treats missing and null as "not deleted".
Future<List<Map<String, dynamic>>> activeOrders(Ditto ditto, String status) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE status = :status AND coalesce(isDeleted, false) = false '
    'ORDER BY createdAt DESC',
    arguments: {'status': status},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Index-friendly equivalent of the coalesce() filter when an index
/// on isDeleted exists. Returns the same documents.
Future<List<Map<String, dynamic>>> activeOrdersIndexFriendly(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false',
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: Misses every document where isDeleted is missing or null
/// (for example documents written before the flag was introduced).
Future<List<Map<String, dynamic>>> activeOrdersWrongFilter(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE isDeleted != true',
  );
  return result.items.map((item) => item.value).toList();
}

// ============================================================================
// Variant A: whole-collection subscription, cleanup by a synced DELETE
// ============================================================================

/// ✅ GOOD (Variant A): The subscription (owned by a long-lived service such as
/// OrderSync) includes soft-deleted orders; local queries hide them. Cleanup is
/// a DELETE executed on the Ditto Server after the retention period, for
/// example `DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff
/// LIMIT 30000`, which syncs to every device.
SyncSubscription subscribeToStoreOrders(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}

// ============================================================================
// Variant B: retention-window subscription, cleanup by device-side EVICT
// ============================================================================

/// ✅ GOOD (Variant B): A long-lived service keeps active orders and orders
/// deleted within the retention window, and evicts older deleted orders.
class OrderSoftDeleteRetention {
  OrderSoftDeleteRetention(this.ditto, this.storeId);

  final Ditto ditto;
  final String storeId;

  /// Longer than the longest time a device is expected to stay offline.
  static const retention = Duration(days: 30);

  SyncSubscription? _subscription;

  String _cutoff() =>
      DateTime.now().toUtc().subtract(retention).toIso8601String();

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribe(_cutoff());
  }

  /// Call on a schedule, at most about once a day. The cutoff moves only here,
  /// never on screen changes.
  Future<int> evictExpired() async {
    final cutoff = _cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();

    // 2. Evict only documents outside the new subscription, so they do not
    //    sync back.
    final result = await ditto.store.execute(
      'EVICT FROM orders '
      'WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff',
      arguments: {'storeId': storeId, 'cutoff': cutoff},
    );

    // 3. Subscribe again with the moved boundary.
    _subscription = _subscribe(cutoff);
    return result.mutatedDocumentIDs().length;
  }

  SyncSubscription _subscribe(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId '
        'AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)',
        arguments: {'storeId': storeId, 'cutoff': cutoff},
      );

  void dispose() => _subscription?.cancel();
}

/// ❌ BAD: A flagged document leaves the subscription immediately, so devices
/// (and relays) that do not have the flag yet can miss it.
SyncSubscription subscribeToActiveOrdersOnly(Ditto ditto) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE coalesce(isDeleted, false) = false',
  );
}

// ============================================================================
// UI: the observer hides flagged documents
// ============================================================================

/// ✅ GOOD: The subscription keeps flagged documents; the observer hides them.
/// Results are consumed through the `changes` stream and both the stream
/// subscription and the observer are cancelled in dispose().
class ActiveOrdersList extends StatefulWidget {
  const ActiveOrdersList({
    super.key,
    required this.ditto,
    required this.storeId,
  });

  final Ditto ditto;
  final String storeId;

  @override
  State<ActiveOrdersList> createState() => _ActiveOrdersListState();
}

class _ActiveOrdersListState extends State<ActiveOrdersList> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders '
      'WHERE storeId = :storeId AND coalesce(isDeleted, false) = false '
      'ORDER BY createdAt DESC',
      arguments: {'storeId': widget.storeId},
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
  Widget build(BuildContext context) => ListView(
        children: [
          for (final order in _orders)
            ListTile(
              key: ValueKey(order['_id']),
              title: Text('${order['_id']}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => softDeleteOrder(widget.ditto, '${order['_id']}'),
              ),
            ),
        ],
      );
}
