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
// A query result contains plain values, not CRDT types. Declare the same types
// in the SELECT and in the INSERT that every other statement on the collection
// uses; otherwise the copy stores a counter as a plain number and an attachment
// token as a map, and a field read with a different declaration (for example,
// a MAP read as a REGISTER) is missing from the copy. (With
// DQL_STRICT_MODE = true, declare the MAP fields too.)
//
// Guide: § IDs are immutable, § DELETE and Tombstones, § Soft Delete

import 'package:ditto_live/ditto_live.dart';

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

/// ✅ GOOD: Copies an order to a new ID, repoints its events, and deletes the
/// original, atomically. Both statements declare the order's COUNTER,
/// ATTACHMENT, and REGISTER fields exactly as the other statements on orders
/// do, so the copy keeps their CRDT types. Undeclared objects such as
/// shippingAddress are MAPs.
Future<bool> moveOrder(Ditto ditto, String oldId, String newId) async {
  return ditto.store.transaction(hint: 'moveOrder', (tx) async {
    final result = await tx.execute(
      '''
      SELECT * FROM COLLECTION orders
        (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
      WHERE _id = :id
      ''',
      arguments: {'id': oldId},
    );
    if (result.items.isEmpty) return false;
    final copy = Map<String, dynamic>.from(result.items.first.value)
      ..['_id'] = newId;
    await tx.execute(
      '''
      INSERT INTO COLLECTION orders
        (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
      DOCUMENTS (:doc)
      ''',
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
  });
}

/// Variant for shared records that several devices edit: soft-delete the old
/// document (a flag plus a UTC timestamp) instead of deleting it, so devices
/// that stay offline longer than the tombstone TTL still learn about it.
Future<void> moveOrderWithSoftDelete(
  Ditto ditto,
  String oldId,
  String newId,
) async {
  await ditto.store.transaction(hint: 'moveOrderWithSoftDelete', (tx) async {
    final result = await tx.execute(
      '''
      SELECT * FROM COLLECTION orders
        (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
      WHERE _id = :id
      ''',
      arguments: {'id': oldId},
    );
    if (result.items.isEmpty) return;
    final copy = Map<String, dynamic>.from(result.items.first.value)
      ..['_id'] = newId
      ..['isDeleted'] = false;
    await tx.execute(
      '''
      INSERT INTO COLLECTION orders
        (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
      DOCUMENTS (:doc)
      ''',
      arguments: {'doc': copy},
    );
    await tx.execute(
      'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
      arguments: {
        'id': oldId,
        'deletedAt': utcTimestamp(),
      },
    );
  });
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
