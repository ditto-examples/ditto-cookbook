// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Embedding related data (the default relationship model)
//
// Embed a sub-entity in its parent when it is read together with the parent,
// owned by exactly one parent, small and bounded, covered by the same
// permissions, and edited by the same group of writers. Store embedded
// collections as maps keyed by ID, never as arrays.
//
// Guide: .claude/guides/best-practices/ditto.md
//   #relationships-embedding-separate-collections-and-join

import 'package:ditto_live/ditto_live.dart';

/// Order with embedded line items:
///
/// {
///   "_id": "order-1",
///   "storeId": "store-12",
///   "status": "open",
///   "createdAt": "2026-10-08T10:00:00.000Z",
///   "items": {
///     "9b2f6c1e-...": {"productId": "p1", "name": "Espresso",
///                      "unitPriceCents": 350, "quantity": 2}
///   }
/// }
///
/// - One subscription syncs the order with all of its items.
/// - Every item write is an atomic update of one document.
/// - Add-wins maps merge concurrent edits to different items, so concurrent
///   edits alone are not a reason to split items into a separate collection.
class EmbeddedOrders {
  EmbeddedOrders(this.ditto, this.storeId);

  final Ditto ditto;
  final String storeId;
  SyncSubscription? _subscription;

  /// Call from an app- or feature-level service, not from a screen.
  void subscribe() {
    _subscription ??= ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
  }

  void cancelSubscription() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> createOrder(String orderId) async {
    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': orderId,
          'storeId': storeId,
          'status': 'open',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      },
    );
  }

  /// Adds a line item. The unit price is a snapshot copied at the time of
  /// sale, so later catalog price changes do not alter this order.
  Future<void> addItem({
    required String orderId,
    required String itemId,
    required String productId,
    required String name,
    required int unitPriceCents,
    required int quantity,
  }) async {
    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
      arguments: {
        'patch': {
          '_id': orderId,
          'items': {
            itemId: {
              'productId': productId,
              'name': name,
              'unitPriceCents': unitPriceCents,
              'quantity': quantity,
            },
          },
        },
      },
    );
  }

  /// One read returns the order and all of its items.
  Future<Map<String, dynamic>?> findOrder(String orderId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': orderId},
    );
    return result.items.isEmpty ? null : result.items.first.value;
  }
}

// When to split instead (see foreign-key-join.dart):
// - The data is accessed independently of the parent.
// - It is shared by many parents (products referenced by many orders).
// - It grows without bound (events, readings, messages).
// - It needs different permissions or is written by different writers.
// Splitting only because JOIN exists is not a reason on its own.
