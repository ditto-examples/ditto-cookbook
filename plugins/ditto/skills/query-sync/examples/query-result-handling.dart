// Handling QueryResult and QueryResultItem in Ditto SDK 5.1.0
// (Flutter, ditto_live 5.1.0).
//
// Rules:
// - items is an Iterable, not a List. Each pass creates new QueryResultItem
//   wrappers, so iterate once and convert rows to plain Dart data right away.
// - item.value is decoded on first access and cached on that item object.
// - item.jsonString and item.cborBytes are properties, not methods.
// - mutatedDocumentIDs() builds a new list on every call: call it once.
// - commitID is null for reads; inside a transaction it is only available
//   after the transaction commits. A write that changed nothing still gets a
//   commitID, which peers confirm only with a later commit (up to about 30 s
//   in SDK 5.1.0), so track it only when mutatedDocumentIDs() is not empty.
// - Never keep QueryResult or QueryResultItem objects in state, caches, or
//   across observer callbacks: they reference native memory that is released
//   only when the Dart object is garbage-collected.

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

/// A plain, immutable model built from a result row.
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
      other is Order &&
      other.id == id &&
      other.status == status &&
      other.total == total;

  @override
  int get hashCode => Object.hash(id, status, total);
}

/// ✅ GOOD: Project only the needed fields, iterate once, return models.
Future<List<Order>> loadOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => Order.fromValue(item.value)).toList();
}

/// ✅ GOOD: Read a single row once and keep the value, not the item.
Future<Order?> loadOrder(Ditto ditto, String id) async {
  final result = await ditto.store.execute(
    'SELECT _id, status, total FROM orders WHERE _id = :id',
    arguments: {'id': id},
  );
  final rows = result.items.toList(); // One pass over items.
  return rows.isEmpty ? null : Order.fromValue(rows.first.value);
}

/// ✅ GOOD: Inspect which documents changed, calling mutatedDocumentIDs() once.
/// IDs are raw values: a String, or a Map for composite IDs.
Future<({List<dynamic> changedIds, int? commitId})> closeOrders(
  Ditto ditto,
  List<String> ids,
) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id IN :ids',
    arguments: {'status': 'closed', 'ids': ids},
  );
  final List<dynamic> changedIds = result.mutatedDocumentIDs();
  // Nothing to track when no document changed (for example, unknown IDs).
  return (
    changedIds: changedIds,
    commitId: changedIds.isEmpty ? null : result.commitID,
  );
}

/// ✅ GOOD: Alternative encodings, for example to hand rows to a JSON decoder
/// or to another isolate as plain strings.
Future<List<String>> openOrdersAsJson(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.jsonString).toList();
}

/// ✅ GOOD: A cache holds plain models, never query results.
class OrderCache {
  final Map<String, Order> _byId = {};

  void update(QueryResult result) {
    _byId
      ..clear()
      ..addEntries(result.items.map((item) {
        final order = Order.fromValue(item.value);
        return MapEntry(order.id, order);
      }));
    // The QueryResult goes out of scope after this method returns.
  }

  Order? operator [](String id) => _byId[id];
}

/// ❌ BAD: Keeping QueryResultItem objects alive. They pin native memory, and
/// every pass over items would decode rows again.
class RetainingCache {
  final List<QueryResultItem> _items = [];

  void update(QueryResult result) {
    _items
      ..clear()
      ..addAll(result.items);
  }

  int get count => _items.length;
}

/// ❌ BAD: Iterating items repeatedly and calling mutatedDocumentIDs() twice.
/// Each result.items.first creates a new wrapper and decodes the row again.
Future<void> wastefulAccess(Ditto ditto, String id) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :id',
    arguments: {'id': id},
  );
  if (result.items.isEmpty) return;
  debugPrint('${result.items.first.value['status']}');
  debugPrint('${result.items.first.value['total']}');

  final update = await ditto.store.execute(
    'UPDATE orders SET viewed = true WHERE _id = :id',
    arguments: {'id': id},
  );
  if (update.mutatedDocumentIDs().isNotEmpty) {
    debugPrint('${update.mutatedDocumentIDs().first}');
  }
}
