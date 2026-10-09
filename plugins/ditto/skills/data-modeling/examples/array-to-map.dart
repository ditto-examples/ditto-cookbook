// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Arrays vs maps keyed by ID
//
// An array is a REGISTER: every write replaces the whole array, and when two
// devices change it concurrently one version wins and the other change is
// lost silently. A map keyed by a stable ID merges each entry independently.
//
// When you convert an existing array, write the map to a new field (for
// example, lineItems next to the old items array). Writing a map under the
// array's field name changes its CRDT type: the old array and the new map then
// coexist under the same key.
//
// Guide: .claude/guides/best-practices/ditto.md#arrays-and-maps

import 'dart:math';

import 'package:ditto_live/ditto_live.dart';

final _random = Random.secure();

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

/// Returns a random (version 4) UUID.
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

// ---------------------------------------------------------------------------
// ❌ BAD: Line items in an array
// ---------------------------------------------------------------------------

/// ❌ BAD: Two devices that add different items while offline both rewrite the
/// whole array. After sync, one device's item is gone, without an error.
Future<void> addItemToArray(
  Ditto ditto,
  String orderId,
  List<dynamic> currentItems,
  Map<String, dynamic> item,
) async {
  await ditto.store.execute(
    'UPDATE orders SET items = :items WHERE _id = :id',
    arguments: {
      'id': orderId,
      'items': [...currentItems, item],
    },
  );
}

// ---------------------------------------------------------------------------
// ✅ GOOD: Line items in a map keyed by item ID
// ---------------------------------------------------------------------------

/// ✅ GOOD: Each item is a map entry keyed by a UUID; display order is a field.
/// Concurrent additions, edits to different items, and edits to different
/// fields of one item all merge.
Future<String> createOrder(Ditto ditto, String storeId) async {
  final orderId = uuidV4();
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId,
        'storeId': storeId,
        'status': 'open',
        'createdAt': utcTimestamp(),
        'items': {
          uuidV4(): {'productId': 'p1', 'quantity': 2, 'position': 0},
          uuidV4(): {'productId': 'p2', 'quantity': 1, 'position': 1},
        },
      },
    },
  );
  return orderId;
}

/// ✅ GOOD: Add or update one entry. DQL parameters bind values, not paths, so
/// the key travels as data inside a partial document. Objects merge, and
/// DO UPDATE_LOCAL_DIFF writes only what differs.
/// Note: if the order does not exist yet, this creates it.
Future<void> upsertOrderItem(
  Ditto ditto, {
  required String orderId,
  required String itemId,
  required Map<String, dynamic> item,
}) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': orderId,
        'items': {itemId: item},
      },
    },
  );
}

// Map keys used in paths are validated: only UUID-shaped keys are accepted.
final _uuidKey = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// ✅ GOOD: Remove one entry with UNSET. A path cannot be a parameter, so the
/// key is validated against a strict pattern before it is placed inside a
/// backtick-quoted path segment. This prevents DQL injection.
///
/// Note (SDK 5.1.0): a removal does not win over a concurrent edit of the same
/// entry on another device; the entry stays with only the edited fields (or
/// with them set to null). Readers must skip such entries, and a `removed`
/// flag is safer when concurrent edits are likely.
Future<void> removeOrderItem(
  Ditto ditto, {
  required String orderId,
  required String itemId,
}) async {
  if (!_uuidKey.hasMatch(itemId)) {
    throw ArgumentError.value(itemId, 'itemId', 'must be a lowercase UUID');
  }
  await ditto.store.execute(
    'UPDATE orders UNSET items.`$itemId` WHERE _id = :id',
    arguments: {'id': orderId},
  );
}

/// ✅ GOOD: When the key is a fixed literal, address the entry with a path.
Future<void> setFixedItemQuantity(Ditto ditto, String orderId, int qty) async {
  await ditto.store.execute(
    'UPDATE orders SET items.`item-1`.quantity = :quantity WHERE _id = :id',
    arguments: {'id': orderId, 'quantity': qty},
  );
}

/// Reads the items of an order in display order.
List<Map<String, dynamic>> sortedItems(Map<String, dynamic> order) {
  final items = (order['items'] as Map<String, dynamic>?) ?? const {};
  final list = [
    for (final entry in items.entries)
      {'itemId': entry.key, ...(entry.value as Map<String, dynamic>)},
  ];
  list.sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
  return list;
}

// ---------------------------------------------------------------------------
// ✅ ACCEPTABLE: An array that a single device owns or replaces wholesale
// ---------------------------------------------------------------------------

/// Tags are a list of scalars, replaced as a whole and edited by one device.
/// DQL has no element assignment (`SET tags[0] = ...` is a parser error), so
/// build the new array in Dart; the write replaces the whole register.
/// Reading and writing in one transaction keeps two local calls from
/// interleaving and dropping a tag; a concurrent edit on another device can
/// still win the merge.
Future<void> addTag(Ditto ditto, String productId, String tag) async {
  await ditto.store.transaction(hint: 'addTag', (tx) async {
    final result = await tx.execute(
      'SELECT tags FROM products WHERE _id = :id',
      arguments: {'id': productId},
    );
    if (result.items.isEmpty) return;
    final current = (result.items.first.value['tags'] as List?) ?? const [];
    await tx.execute(
      'UPDATE products SET tags = :tags WHERE _id = :id',
      arguments: {'id': productId, 'tags': [...current, tag]},
    );
  });
}

/// Membership filter on an array field: use IN or array_contains.
Future<List<Map<String, dynamic>>> productsWithTag(
  Ditto ditto,
  String tag,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM products WHERE array_contains(tags, :tag)',
    arguments: {'tag': tag},
  );
  return result.items.map((item) => item.value).toList();
}
