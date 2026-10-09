// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Derived values vs snapshot values
//
// A stored value computed from other fields (line total, order total,
// remaining stock) is a separate register. Two devices update the inputs
// concurrently, each recomputes from its own partial view, and after the merge
// the stored total can match neither. Compute derived values when you read.
// Snapshot values (the price at the time of sale) are facts, not derivations:
// copy them into the document.
//
// Guide: .claude/guides/best-practices/ditto.md#document-structure

import 'package:ditto_live/ditto_live.dart';

// ---------------------------------------------------------------------------
// ❌ BAD: Storing derived totals
// ---------------------------------------------------------------------------

/// ❌ BAD: subtotalCents and totalCents are derived from items. If another
/// device adds an item concurrently, the merged items and the stored totals
/// disagree.
Future<void> setItemQuantityAndTotals(
  Ditto ditto, {
  required String orderId,
  required int quantity,
  required int subtotalCents,
  required int totalCents,
}) async {
  await ditto.store.execute(
    '''
    UPDATE orders
    SET items.`item-1`.quantity = :quantity,
        subtotalCents = :subtotal,
        totalCents = :total
    WHERE _id = :id
    ''',
    arguments: {
      'id': orderId,
      'quantity': quantity,
      'subtotal': subtotalCents,
      'total': totalCents,
    },
  );
}

// ---------------------------------------------------------------------------
// ✅ GOOD: Store source data, derive at read time
// ---------------------------------------------------------------------------

/// ✅ GOOD: Only the input changes. Totals are computed from what merged.
Future<void> setItemQuantity(
  Ditto ditto,
  String orderId,
  int quantity,
) async {
  await ditto.store.execute(
    'UPDATE orders SET items.`item-1`.quantity = :quantity WHERE _id = :id',
    arguments: {'id': orderId, 'quantity': quantity},
  );
}

/// Entries with a missing or null price or quantity (an entry removed on one
/// device while another device edited it) are skipped instead of throwing.
int orderSubtotalCents(Map<String, dynamic> order) {
  final items = (order['items'] as Map<String, dynamic>?) ?? const {};
  var subtotal = 0;
  for (final entry in items.values) {
    if (entry is! Map<String, dynamic>) continue;
    final price = entry['unitPriceCents'];
    final quantity = entry['quantity'];
    if (price is! int || quantity is! int) continue;
    subtotal += price * quantity;
  }
  return subtotal;
}

/// ✅ GOOD: Aggregates over a collection are computed in DQL instead of being
/// maintained in a stored field or counter.
Future<int> countOpenOrders(Ditto ditto, String storeId) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(*) AS openOrders FROM orders '
    'WHERE storeId = :storeId AND status = :status',
    arguments: {'storeId': storeId, 'status': 'open'},
  );
  return result.items.first.value['openOrders'] as int;
}

// ---------------------------------------------------------------------------
// ✅ GOOD: Snapshot values are copied
// ---------------------------------------------------------------------------

/// ✅ GOOD: The unit price at the time of sale is copied into the line item,
/// so a later price change in products does not alter historical orders.
Future<void> addItemWithPriceSnapshot(
  Ditto ditto, {
  required String orderId,
  required String itemId,
  required String productId,
  required int quantity,
}) async {
  await ditto.store.transaction(hint: 'addItemWithPriceSnapshot', (tx) async {
    final product = await tx.execute(
      'SELECT priceCents FROM products WHERE _id = :id',
      arguments: {'id': productId},
    );
    if (product.items.isEmpty) {
      throw StateError('Product $productId is not available locally');
    }
    await tx.execute(
      'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
      arguments: {
        'patch': {
          '_id': orderId,
          'items': {
            itemId: {
              'productId': productId,
              'quantity': quantity,
              'unitPriceCents': product.items.first.value['priceCents'],
            },
          },
        },
      },
    );
  });
}

// Values that should always be current (a product's name on a catalog screen)
// are not copied: reference the product by ID and JOIN at read time
// (see foreign-key-join.dart).
