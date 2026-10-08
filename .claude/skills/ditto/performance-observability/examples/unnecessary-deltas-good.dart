// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter (DQL applies to all platforms)
// Last Updated: 2026-10-08
//
// ============================================================================
// Avoiding Unnecessary Writes (Correct Patterns)
// ============================================================================
//
// Guide sections (.claude/guides/best-practices/ditto.md):
// - #on-id-conflict
// - #prefer-field-level-updates-over-whole-document-rewrites
// - #assigning-an-object-merges-it
// - #prefer-field-level-updates
//
// Ditto syncs changes at field level. Writing only what changed keeps sync
// deltas small and reduces the chance that an unchanged value written by this
// device overwrites a concurrent edit from another peer. It also avoids
// mutations that wake observers for no visible change.
//
// | Write                                  | Values unchanged                    |
// |----------------------------------------|-------------------------------------|
// | ON ID CONFLICT DO UPDATE               | All supplied fields written again;  |
// |                                        | document mutated, observers can fire|
// | ON ID CONFLICT DO UPDATE_LOCAL_DIFF    | Nothing written                     |
// | UPDATE ... SET f = <current value>     | Mutation recorded, observers can    |
// |                                        | fire                                |
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Upserts and re-imports with DO UPDATE_LOCAL_DIFF
// 2. ✅ Field-level UPDATE for the fields that changed
// 3. ✅ Skipping documents that are already in the target state
// 4. ✅ Nested field updates and UNSET
// 5. ✅ Replacing an object deliberately (UNSET, then SET)
// 6. ✅ Saving a form: writing only the fields the user changed
//
// ============================================================================

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// PATTERN 1: Upserts and re-imports
// ============================================================================

/// ✅ GOOD: Refreshing reference data from a backend. Documents whose values
/// did not change are not written, so they do not appear in
/// mutatedDocumentIDs() and observers are not woken for them.
Future<int> importProducts(Ditto ditto, List<Map<String, dynamic>> products) async {
  final result = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'products': products},
  );
  return result.mutatedDocumentIDs().length; // Only documents that changed.
}

/// ✅ GOOD: "Create if absent" without touching existing documents.
Future<void> ensureDefaultSettings(Ditto ditto, String userId) async {
  await ditto.store.execute(
    'INSERT INTO settings DOCUMENTS (:settings) ON ID CONFLICT DO NOTHING',
    arguments: {
      'settings': {'_id': userId, 'theme': 'system', 'notifications': true},
    },
  );
}

// ============================================================================
// PATTERN 2: Field-level UPDATE
// ============================================================================

/// ✅ GOOD: Only the fields that changed are written.
Future<void> completeOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET status = :status, completedAt = :completedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      'status': 'completed',
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

// ============================================================================
// PATTERN 3: Skip documents already in the target state
// ============================================================================

/// ✅ GOOD: The WHERE condition skips the write when the value is already
/// stored. `coalesce` keeps documents whose status is missing or null
/// eligible; a plain `status != :status` would skip them.
Future<bool> setStatus(Ditto ditto, String orderId, String status) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status '
    'WHERE _id = :id AND coalesce(status, :none) != :status',
    arguments: {'id': orderId, 'status': status, 'none': ''},
  );
  return result.mutatedDocumentIDs().isNotEmpty;
}

/// ✅ GOOD: A frequent "presence" write that only touches the document when
/// the state actually changes.
Future<void> markDeviceOnline(Ditto ditto, String deviceId, bool online) async {
  final result = await ditto.store.execute(
    'UPDATE devices SET online = :online '
    'WHERE _id = :id AND coalesce(online, :fallback) != :online',
    // A missing or null value counts as the opposite state, so it is written.
    arguments: {'id': deviceId, 'online': online, 'fallback': !online},
  );
  if (result.mutatedDocumentIDs().isEmpty) {
    debugPrint('device $deviceId already in state online=$online');
  }
}

// ============================================================================
// PATTERN 4: Nested field updates and UNSET
// ============================================================================

/// ✅ GOOD: Update one nested field; missing intermediate objects are created.
Future<void> setShippingCity(Ditto ditto, String orderId, String city) async {
  await ditto.store.execute(
    'UPDATE orders SET shipping.address.city = :city WHERE _id = :id',
    arguments: {'id': orderId, 'city': city},
  );
}

/// ✅ GOOD: UNSET removes fields (they become MISSING). No INSERT policy and
/// no `SET obj = {...}` removes keys.
Future<void> clearDiscount(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders UNSET discountCode, pricing.discount WHERE _id = :id',
    arguments: {'id': orderId},
  );
}

// ============================================================================
// PATTERN 5: Replacing an object deliberately
// ============================================================================

/// ✅ GOOD: With the default strict mode, `SET address = :address` merges into
/// the existing object. To replace it completely, run UNSET and then SET
/// inside one transaction, so no reader sees the document without an address.
/// The field is still a map, so a nested edit that another device makes at the
/// same time can merge into the new object; declare the field as REGISTER if
/// that must never happen.
Future<void> replaceAddress(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE customers UNSET address WHERE _id = :id',
      arguments: {'id': customerId},
    );
    await tx.execute(
      'UPDATE customers SET address = :address WHERE _id = :id',
      arguments: {'id': customerId, 'address': newAddress},
    );
  }, hint: 'replaceAddress');
}

// ============================================================================
// PATTERN 6: Saving a form
// ============================================================================

/// ✅ GOOD: When the user edits a form, write only the fields the user changed.
/// Writing the whole in-memory copy back, even with DO UPDATE_LOCAL_DIFF, would
/// also write a stale value of a field that another device changed after the
/// form was loaded, because the stale value differs from the stored one.
Future<bool> saveOrderStatus(Ditto ditto, String orderId, String status) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status '
    'WHERE _id = :id AND coalesce(status, :none) != :status',
    arguments: {'id': orderId, 'status': status, 'none': ''},
  );
  return result.mutatedDocumentIDs().isNotEmpty; // false when nothing changed.
}
