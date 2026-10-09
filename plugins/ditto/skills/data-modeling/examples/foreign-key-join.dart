// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Separate collections with foreign keys and JOIN (SDK 5.1+)
//
// Use a separate collection when data is accessed independently, shared by
// many parents, unbounded, governed by different permissions, or written by
// different writers. JOIN then reads the related documents locally.
//
// JOIN rules:
// - Local data only: it never fetches documents from other peers, so every
//   joined collection needs its own subscription.
// - Not allowed in subscriptions (`Unsupported feature: Joining`) and not on
//   Ditto Server.
// - The inner collection needs an index on the join key, or the join must be
//   on its `_id`. Otherwise the query fails with
//   `Joining to "..." disallowed without appropriate index support`.
//
// Guide: § Relationships: Embedding, Separate Collections, and JOIN,
//   § Joining Collections (SDK 5.1+)

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

/// ISO-8601 UTC timestamp with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z". Fixed precision keeps values sortable as text
/// (native Dart omits zero microseconds, so even one device would otherwise
/// mix precisions).
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// Documents:
//   orders:     {"_id": "order-1", "storeId": "store-12", "status": "open"}
//   orderItems: {"_id": "item-1", "orderId": "order-1", "storeId": "store-12",
//                "productId": "p1", "quantity": 2}
//   products:   {"_id": "p1", "name": "Espresso", "priceCents": 350}
//
// storeId is copied into orderItems because a subscription can filter only on
// fields of its own collection.

// ---------------------------------------------------------------------------
// ✅ GOOD: Index the join key, subscribe per collection
// ---------------------------------------------------------------------------

/// Keeps the collections needed by the order screens in sync. Subscriptions
/// belong to an app- or feature-level service, not to a screen.
class StoreSync {
  StoreSync(this.ditto, this.storeId);

  final Ditto ditto;
  final String storeId;
  final List<SyncSubscription> _subscriptions = [];

  Future<void> start() async {
    // Indexes persist; IF NOT EXISTS makes this idempotent at every startup.
    await ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)',
    );
    _subscriptions.addAll([
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription(
        'SELECT * FROM orderItems WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription('SELECT * FROM products'),
    ]);
  }

  void stop() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}

/// ✅ GOOD: Parent and children created together are written in one
/// transaction, so local observers never see one without the other.
Future<void> createOrderWithItems(
  Ditto ditto, {
  required String storeId,
  required String orderId,
  required List<Map<String, dynamic>> items,
}) async {
  await ditto.store.transaction(hint: 'createOrderWithItems', (tx) async {
    await tx.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': orderId,
          'storeId': storeId,
          'status': 'open',
          'createdAt': utcTimestamp(),
        },
      },
    );
    await tx.execute(
      'INSERT INTO orderItems DOCUMENTS (:items)',
      arguments: {
        'items': [
          for (final item in items)
            {...item, 'orderId': orderId, 'storeId': storeId},
        ],
      },
    );
  });
}

/// ✅ GOOD: One-off join. Drives from orderItems through the
/// idx_orderItems_orderId index and looks up each product by _id (no extra
/// index needed). Qualify every field with its alias and alias colliding names
/// such as _id.
Future<List<Map<String, dynamic>>> orderLines(
  Ditto ditto,
  String orderId,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT i._id AS itemId, i.quantity, p.name, p.priceCents
    FROM orderItems AS i
    JOIN products AS p ON p._id = i.productId
    WHERE i.orderId = :orderId
    ORDER BY p.name
    ''',
    arguments: {'orderId': orderId},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: LEFT JOIN keeps a parent whose children have not synced yet (or do
/// not exist). Right-side fields are MISSING for unmatched rows. orderItems is
/// the inner collection, so it uses the idx_orderItems_orderId index.
Future<List<Map<String, dynamic>>> openOrdersWithItems(
  Ditto ditto,
  String storeId,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT o._id AS orderId, o.status, i.productId, i.quantity
    FROM orders AS o
    LEFT JOIN orderItems AS i ON i.orderId = o._id
    WHERE o.storeId = :storeId AND o.status = 'open'
    ORDER BY o._id, i.productId
    ''',
    arguments: {'storeId': storeId},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: A screen that observes the joined result. The observer delivers a
/// new result when a change in any of the joined collections changes the
/// joined rows. Results are consumed through the
/// `changes` stream; both are cancelled in dispose(). The observer is
/// registered once for widget.orderId: if that ID can change while the widget
/// is mounted, re-register it in didUpdateWidget.
class OrderItemsView extends StatefulWidget {
  const OrderItemsView({super.key, required this.ditto, required this.orderId});

  final Ditto ditto;
  final String orderId;

  @override
  State<OrderItemsView> createState() => _OrderItemsViewState();
}

class _OrderItemsViewState extends State<OrderItemsView> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _lines = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      '''
      SELECT i._id AS itemId, i.quantity, p.name, p.priceCents
      FROM orderItems AS i
      JOIN products AS p ON p._id = i.productId
      WHERE i.orderId = :orderId
      ORDER BY p.name
      ''',
      arguments: {'orderId': widget.orderId},
    );
    _changes = _observer.changes.listen((result) {
      setState(() {
        _lines = result.items.map((item) => item.value).toList();
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
          for (final line in _lines)
            ListTile(
              title: Text('${line['name']}'),
              trailing: Text('x${line['quantity']}'),
            ),
        ],
      );
}

// ---------------------------------------------------------------------------
// ❌ BAD: Common JOIN mistakes
// ---------------------------------------------------------------------------

// These statements fail at runtime by design. They are kept in constants so
// that the failure is visible at the call site; SKILL.md shows the same
// statements with their error messages.

/// ❌ BAD: A JOIN in a subscription. Subscriptions accept only
/// `SELECT * FROM <collection> [WHERE ...]`; registering this throws
/// `Unsupported feature: Joining`. Subscribe to each collection instead.
const joinInSubscription =
    'SELECT * FROM orderItems AS i JOIN products AS p ON p._id = i.productId '
    'WHERE i.orderId = :orderId';

SyncSubscription subscribeWithJoin(Ditto ditto, String orderId) =>
    ditto.sync.registerSubscription(
      joinInSubscription,
      arguments: {'orderId': orderId},
    );

/// ❌ BAD: Joining to customers on a non-ID field without an index fails before
/// it runs (`Joining to "c" disallowed without appropriate index support`).
/// Fix: `CREATE INDEX IF NOT EXISTS idx_customers_email ON customers (email)`, or
/// join on c._id. Do not silence the error with `USE INDEX ''` on a large
/// collection: every outer row would then scan the whole inner collection.
const joinWithoutIndexQuery = 'SELECT o._id, c.name FROM orders AS o '
    'JOIN customers AS c ON c.email = o.customerEmail';

Future<void> joinWithoutIndex(Ditto ditto) async {
  await ditto.store.execute(joinWithoutIndexQuery);
}

/// ❌ BAD: Assuming JOIN fetches related documents from other peers. Without a
/// products subscription, products that never synced to this device are
/// simply absent: inner-join rows disappear and LEFT JOIN fields are MISSING.
Future<List<Map<String, dynamic>>> linesWithoutProductSubscription(
  Ditto ditto,
  String orderId,
) =>
    orderLines(ditto, orderId); // Correct query, but nothing synced products.
