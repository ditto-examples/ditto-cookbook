// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Field-level updates and MAP merge semantics (default DQL_STRICT_MODE = false)
//
// Under the default settings an object is stored as a MAP: assigning an object
// merges it into the stored map, and only UNSET removes keys. Write only what
// changed. DO UPDATE_LOCAL_DIFF suits upserts and re-imports of data that
// another system owns; it does not protect a stale in-memory copy.
//
// Guide: .claude/guides/best-practices/ditto.md
//   #local-write-semantics-you-must-know, #document-structure,
//   #insert-and-conflict-handling

import 'package:ditto_live/ditto_live.dart';

String utcNow() => DateTime.now().toUtc().toIso8601String();

// ---------------------------------------------------------------------------
// Field-level updates
// ---------------------------------------------------------------------------

/// ✅ GOOD: Only the changed fields are written. Concurrent edits that other
/// devices make to other fields of the order survive the merge.
Future<void> markOrderReady(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET status = :status, updatedAt = :updatedAt WHERE _id = :id',
    arguments: {'id': orderId, 'status': 'ready', 'updatedAt': utcNow()},
  );
}

/// ✅ GOOD: Update one field of a nested object (a MAP). Concurrent edits to
/// other fields of shippingAddress merge cleanly.
Future<void> updateShippingCity(Ditto ditto, String orderId, String city) async {
  await ditto.store.execute(
    'UPDATE orders SET shippingAddress.city = :city WHERE _id = :id',
    arguments: {'id': orderId, 'city': city},
  );
}

/// ✅ GOOD: UNSET is the only way to remove a key from a map.
Future<void> removeAddressLine2(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders UNSET shippingAddress.line2 WHERE _id = :id',
    arguments: {'id': orderId},
  );
}

// ---------------------------------------------------------------------------
// Upserting a full document
// ---------------------------------------------------------------------------

/// ✅ GOOD: Re-importing reference data that your backend owns.
/// DO UPDATE_LOCAL_DIFF compares the incoming document with the local one and
/// skips fields whose values are equal. Re-writing unchanged data writes
/// nothing (no mutation, no observer callback).
Future<bool> importProduct(Ditto ditto, Map<String, dynamic> product) async {
  final result = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'product': product},
  );
  // Empty when the stored document already had the same values.
  return result.mutatedDocumentIDs().isNotEmpty;
}

/// ❌ BAD: Writing back a whole in-memory copy after the user changed only the
/// status. If another device changed tableNumber after this copy was loaded,
/// the stale value is written back: DO UPDATE writes every supplied field, and
/// DO UPDATE_LOCAL_DIFF writes every field that differs from the stored one,
/// which includes the stale tableNumber. Use a field-level UPDATE instead.
Future<void> saveOrderIncorrectly(
  Ditto ditto,
  Map<String, dynamic> staleOrder,
) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'order': staleOrder},
  );
}

// ---------------------------------------------------------------------------
// Replacing an object
// ---------------------------------------------------------------------------

/// ❌ BAD: Expecting this to replace the address. Under the default settings
/// the object is merged into the existing map: keys missing from newAddress
/// (for example, line2) remain. `SET shippingAddress = {}` clears nothing
/// either.
Future<void> replaceShippingAddressIncorrectly(
  Ditto ditto,
  String orderId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.execute(
    'UPDATE orders SET shippingAddress = :address WHERE _id = :id',
    arguments: {'id': orderId, 'address': newAddress},
  );
}

/// ✅ GOOD: Clear the map, then write the new object, in one transaction so no
/// reader sees the intermediate state. The field is still a map, so a nested
/// edit that another device makes at the same time can merge into the new
/// object; only a REGISTER declaration (below) prevents that.
Future<void> replaceShippingAddress(
  Ditto ditto,
  String orderId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.transaction(hint: 'replaceShippingAddress', (tx) async {
    await tx.execute(
      'UPDATE orders UNSET shippingAddress WHERE _id = :id',
      arguments: {'id': orderId},
    );
    await tx.execute(
      'UPDATE orders SET shippingAddress = :address WHERE _id = :id',
      arguments: {'id': orderId, 'address': newAddress},
    );
  });
}

// The alternative for an object that must always be replaced as one unit is
// to declare it as a REGISTER in every statement; see
// strict-mode-and-declarations.dart.
