// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Changing a document ID
//
// `_id` is immutable: `UPDATE orders SET _id = ...` fails with
// "The document id `_id` cannot be modified". To "change" an ID, copy the
// document to a new _id and remove the old one in one transaction. Removing
// the old document has the usual deletion trade-offs (tombstones, or a soft
// delete flag), and every reference must be updated, so choose IDs carefully
// up front.
//
// Guide: .claude/guides/best-practices/ditto.md#ids-are-immutable,
//   #delete-and-tombstones, #soft-delete

import 'package:ditto_live/ditto_live.dart';

/// ✅ GOOD: Copies an order to a new ID, repoints its events, and deletes the
/// original, atomically.
Future<bool> moveOrder(Ditto ditto, String oldId, String newId) async {
  return ditto.store.transaction((tx) async {
    final result = await tx.execute(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': oldId},
    );
    if (result.items.isEmpty) return false;
    final copy = Map<String, dynamic>.from(result.items.first.value)
      ..['_id'] = newId;
    await tx.execute(
      'INSERT INTO orders DOCUMENTS (:doc)',
      arguments: {'doc': copy},
    );
    await tx.execute(
      'UPDATE orderEvents SET orderId = :newId WHERE orderId = :oldId',
      arguments: {'newId': newId, 'oldId': oldId},
    );
    await tx.execute(
      'DELETE FROM orders WHERE _id = :id',
      arguments: {'id': oldId},
    );
    return true;
  }, hint: 'moveOrder');
}

/// Variant for shared records that several devices edit: soft-delete the old
/// document (a flag plus a UTC timestamp) instead of deleting it, so devices
/// that stay offline longer than the tombstone TTL still learn about it.
Future<void> moveOrderWithSoftDelete(
  Ditto ditto,
  String oldId,
  String newId,
) async {
  await ditto.store.transaction((tx) async {
    final result = await tx.execute(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': oldId},
    );
    if (result.items.isEmpty) return;
    final copy = Map<String, dynamic>.from(result.items.first.value)
      ..['_id'] = newId
      ..['isDeleted'] = false;
    await tx.execute(
      'INSERT INTO orders DOCUMENTS (:doc)',
      arguments: {'doc': copy},
    );
    await tx.execute(
      'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
      arguments: {
        'id': oldId,
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }, hint: 'moveOrderWithSoftDelete');
}

/// Readers then exclude soft-deleted documents; a missing flag counts as
/// "not deleted".
Future<List<Map<String, dynamic>>> activeOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE coalesce(isDeleted, false) = false '
    'ORDER BY createdAt DESC',
  );
  return result.items.map((item) => item.value).toList();
}
