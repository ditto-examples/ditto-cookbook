// DQL write patterns for Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// Covers: INSERT with parameters, ON ID CONFLICT policies, field-level UPDATE,
// UNSET, object merge semantics (default DQL_STRICT_MODE = false),
// RETURNING (SDK 5.1+), and DELETE / EVICT by ID.
//
// Statements that fail outright are described in comments only:
// - SET _id = ... : "The document id _id cannot be modified".
// - Setting the same path twice in one statement: "More than one modification
//   specified for the path ...".
// - SET items[0] = ... : array elements cannot be assigned (syntax error).

import 'package:ditto_live/ditto_live.dart';

/// Every timestamp that is sorted or compared comes from this one helper:
/// ISO-8601 UTC with exactly millisecond precision (native Dart would otherwise
/// emit microseconds, the web milliseconds).
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// ---------------------------------------------------------------------------
// INSERT and ON ID CONFLICT
// ---------------------------------------------------------------------------

/// ✅ GOOD: Several documents in one atomic statement, as an array parameter.
/// DO UPDATE_LOCAL_DIFF writes only fields that differ; unchanged documents
/// are a no-op (no mutation, observers do not fire).
Future<List<dynamic>> importProducts(
  Ditto ditto,
  List<Map<String, dynamic>> products,
) async {
  final result = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'products': products},
  );
  // Call mutatedDocumentIDs() once; it builds a new list on every call.
  return result.mutatedDocumentIDs();
}

/// ✅ GOOD: "Create if absent" leaves an existing document unchanged.
Future<void> createDraftIfAbsent(Ditto ditto, String id) async {
  await ditto.store.execute(
    'INSERT INTO drafts DOCUMENTS (:draft) ON ID CONFLICT DO NOTHING',
    arguments: {
      'draft': {'_id': id, 'createdAt': utcTimestamp()},
    },
  );
}

/// ✅ GOOD: Seed defaults on every launch; existing (possibly edited) data is kept.
Future<void> seedDefaults(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO settings INITIAL DOCUMENTS (:defaults)',
    arguments: {
      'defaults': {'_id': 'app', 'theme': 'light', 'currency': 'USD'},
    },
  );
}

/// ❌ BAD: Periodic re-upsert with DO UPDATE. Every supplied field is
/// rewritten even when identical, a mutation is recorded, and observers fire.
Future<void> refreshCatalogWithDoUpdate(
  Ditto ditto,
  List<Map<String, dynamic>> products,
) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE',
    arguments: {'products': products},
  );
}

/// ❌ BAD: Expecting DO UPDATE to replace the document. It merges: fields
/// missing from the new document (here 'name') stay, nested objects merge.
Future<void> replaceProductWrong(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE',
    arguments: {
      'doc': {
        '_id': 'p1',
        'price': 6,
        'address': {'street': 'Main St'},
      },
    },
  );
  // Starting from {"_id": "p1", "name": "Pen", "price": 5,
  //                "address": {"city": "Oslo", "zip": "0150"}}, the stored document is:
  // {"_id": "p1", "name": "Pen", "price": 6,
  //  "address": {"city": "Oslo", "zip": "0150", "street": "Main St"}}
}

// ---------------------------------------------------------------------------
// UPDATE
// ---------------------------------------------------------------------------

/// ✅ GOOD: Change only the fields that changed, and skip documents that
/// already have the value. coalesce() keeps missing/null status eligible.
Future<bool> setStatus(Ditto ditto, String orderId, String status) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status, updatedAt = :now '
    'WHERE _id = :id AND coalesce(status, :none) != :status',
    arguments: {'id': orderId, 'status': status, 'none': '', 'now': utcTimestamp()},
  );
  return result.mutatedDocumentIDs().isNotEmpty;
}

/// ✅ GOOD: Nested paths; missing intermediate objects are created.
Future<void> setShippingCity(Ditto ditto, String orderId, String city) async {
  await ditto.store.execute(
    'UPDATE orders SET shipping.address.city = :city WHERE _id = :id',
    arguments: {'id': orderId, 'city': city},
  );
}

/// ✅ GOOD: UNSET removes fields (they become MISSING). Writing null would
/// keep the field present with a null value.
Future<void> clearDiscount(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders UNSET discountCode, pricing.discount WHERE _id = :id',
    arguments: {'id': orderId},
  );
}

/// ✅ GOOD: Replace an object: UNSET it, then SET the new value, as two
/// statements inside one transaction. A single SET address = :address would
/// merge into the existing object.
Future<void> replaceAddress(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.transaction(
    (tx) async {
      await tx.execute(
        'UPDATE customers UNSET address WHERE _id = :id',
        arguments: {'id': customerId},
      );
      await tx.execute(
        'UPDATE customers SET address = :address WHERE _id = :id',
        arguments: {'id': customerId, 'address': newAddress},
      );
    },
    hint: 'replaceCustomerAddress',
  );
}

/// ❌ BAD: SET obj = {} does not clear an object (the merge adds no keys and
/// removes none). Use UNSET address.
Future<void> clearAddressWrong(Ditto ditto, String customerId) async {
  await ditto.store.execute(
    'UPDATE customers SET address = {} WHERE _id = :id',
    arguments: {'id': customerId},
  );
}

/// ❌ BAD: Read-modify-write of the whole document. Every field is written
/// again, which enlarges the change and lets unchanged values win merges
/// against concurrent edits on other devices. Use a field-level UPDATE.
Future<void> completeOrderByRewrite(Ditto ditto, String orderId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :id',
    arguments: {'id': orderId},
  );
  if (result.items.isEmpty) return;
  final order = Map<String, dynamic>.from(result.items.first.value);
  order['status'] = 'completed';
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
    arguments: {'order': order},
  );
}

// ---------------------------------------------------------------------------
// RETURNING (SDK 5.1+)
// ---------------------------------------------------------------------------

/// ✅ GOOD: Update and read the new values in one statement (rows reflect the
/// documents after the update). mutatedDocumentIDs() and commitID are still set.
Future<List<Map<String, dynamic>>> markShipped(
  Ditto ditto,
  List<String> ids,
) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status, shippedAt = :now '
    'WHERE _id IN :ids AND status = :expected '
    'RETURNING _id, status, shippedAt',
    arguments: {
      'ids': ids,
      'status': 'shipped',
      'expected': 'packed',
      'now': utcTimestamp(),
    },
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Keep a copy of what was deleted (rows reflect the documents
/// before removal), for an undo banner or an audit log.
Future<List<Map<String, dynamic>>> deleteDrafts(
  Ditto ditto,
  List<String> ids,
) async {
  final result = await ditto.store.execute(
    'DELETE FROM drafts WHERE _id IN :ids RETURNING *',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Aggregates in RETURNING summarize all affected documents.
Future<int> deleteExpiredSessions(Ditto ditto) async {
  final result = await ditto.store.execute(
    'DELETE FROM sessions WHERE expiresAt < :now RETURNING COUNT(*) AS removed',
    arguments: {'now': utcTimestamp()},
  );
  final removed = result.items.isEmpty ? null : result.items.first.value['removed'];
  return removed is int ? removed : 0;
}

/// ❌ BAD: Write, then query again to read what was written. Use RETURNING.
Future<Map<String, dynamic>?> markShippedThenQuery(Ditto ditto, String id) async {
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :id',
    arguments: {'id': id, 'status': 'shipped'},
  );
  final result = await ditto.store.execute(
    'SELECT _id, status FROM orders WHERE _id = :id',
    arguments: {'id': id},
  );
  return result.items.isEmpty ? null : result.items.first.value;
}

// ---------------------------------------------------------------------------
// DELETE and EVICT by ID
// ---------------------------------------------------------------------------

/// ✅ GOOD: Select documents by ID with WHERE.
Future<void> deleteOrders(Ditto ditto, List<String> ids) async {
  await ditto.store.execute(
    'DELETE FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
}

/// ❌ BAD: DELETE (or EVICT) with USE IDS and no WHERE clause completes
/// without an error but removes nothing in SDK 5.1.0.
Future<void> deleteOrderWithUseIds(Ditto ditto) async {
  await ditto.store.execute("DELETE FROM orders USE IDS 'order-1'");
}
