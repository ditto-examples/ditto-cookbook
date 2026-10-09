// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter (DQL applies to all platforms)
// Last Updated: 2026-10-08
//
// ============================================================================
// Unnecessary Writes (Anti-Patterns)
// ============================================================================
//
// Guide sections (../../guide/reference/ditto.md):
// - § ON ID CONFLICT
// - § Prefer field-level updates over whole-document rewrites
// - § Assigning an object merges it
//
// Each function below compiles and runs, but writes more than it should.
// Corrected versions are in unnecessary-deltas-good.dart.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Periodic re-imports with DO UPDATE
// 2. ❌ Read-modify-write of a whole document
// 3. ❌ Writing a value that is already stored
// 4. ❌ Expecting DO UPDATE to replace a document
// 5. ❌ Expecting SET obj = {...} to replace or clear an object
//
// ============================================================================

import 'package:ditto_live/ditto_live.dart';

// ============================================================================
// ANTI-PATTERN 1: Periodic re-imports with DO UPDATE
// ============================================================================

/// ❌ BAD: DO UPDATE writes every supplied field, even if the value is
/// identical. Every run reports all documents as mutated and can wake
/// observers.
/// Use ON ID CONFLICT DO UPDATE_LOCAL_DIFF instead.
Future<void> refreshCatalogEveryMinute(
  Ditto ditto,
  List<Map<String, dynamic>> products,
) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE',
    arguments: {'products': products},
  );
}

// ============================================================================
// ANTI-PATTERN 2: Read-modify-write of a whole document
// ============================================================================

/// ❌ BAD: Only `status` changed, but every field is written again. An
/// unchanged field written by this device can win a merge against a real
/// concurrent change made on another device. Use a field-level UPDATE.
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

/// ❌ BAD: A stale in-memory copy is written back with DO UPDATE. A concurrent
/// change that another device made to tableNumber can be overwritten.
/// DO UPDATE_LOCAL_DIFF does not prevent this either: the stale value differs
/// from the stored one, so it is written. Update only the changed field.
Future<void> saveStaleCopy(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
    arguments: {
      'order': {'_id': 'order-1', 'status': 'ready', 'tableNumber': 7},
    },
  );
}

// ============================================================================
// ANTI-PATTERN 3: Writing a value that is already stored
// ============================================================================

/// ❌ BAD: Called on every heartbeat. An UPDATE that sets a field to its
/// current value is still recorded as a mutation, appears in
/// mutatedDocumentIDs(), and can wake observers. Add a WHERE condition that skips
/// documents already in the target state.
Future<void> heartbeat(Ditto ditto, String deviceId) async {
  await ditto.store.execute(
    'UPDATE devices SET online = true WHERE _id = :id',
    arguments: {'id': deviceId},
  );
}

// ============================================================================
// ANTI-PATTERN 4: Expecting DO UPDATE to replace a document
// ============================================================================

/// ❌ BAD: The intent is to drop `discountCode`, but DO UPDATE merges: fields
/// missing from the new document stay, and nested objects are merged. Remove
/// fields with UPDATE ... UNSET instead.
Future<void> removeDiscountByUpsert(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
    arguments: {
      'order': {'_id': orderId, 'status': 'open'}, // discountCode is NOT removed.
    },
  );
}

// ============================================================================
// ANTI-PATTERN 5: Expecting SET obj = {...} to replace or clear an object
// ============================================================================

/// ❌ BAD: With the default strict mode, an object field is a CRDT map.
/// `SET address = :address` merges the new keys into the existing object, so
/// old keys such as `zip` remain. To replace, run UNSET and then SET inside
/// one transaction.
Future<void> replaceAddressBySet(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.execute(
    'UPDATE customers SET address = :address WHERE _id = :id',
    arguments: {'id': customerId, 'address': newAddress},
  );
}

/// ❌ BAD: `SET address = {}` leaves the object unchanged. Use UNSET address.
Future<void> clearAddressBySet(Ditto ditto, String customerId) async {
  await ditto.store.execute(
    'UPDATE customers SET address = {} WHERE _id = :id',
    arguments: {'id': customerId},
  );
}
