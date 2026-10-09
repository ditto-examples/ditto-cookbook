// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// COUNTER fields
//
// A COUNTER combines increments and decrements from all devices, so
// concurrent changes add up instead of overwriting each other. Counter
// operations use APPLY, not SET:
//   APPLY f INCREMENT BY n   (negative n decrements; n must be an integer)
//   APPLY f RESTART WITH n   (set a value; concurrent RESTARTs: last write wins;
//                             increments the restarting device has not received
//                             yet are discarded)
//   APPLY f RESTART          (reset to zero)
// Declarations use the COLLECTION keyword: UPDATE COLLECTION t (f COUNTER) ...
// This file declares the counter in every statement, which works with strict
// mode on or off and keeps declarations consistent.
//
// Guide: § Counters

import 'package:ditto_live/ditto_live.dart';

// ---------------------------------------------------------------------------
// ✅ GOOD: Declared counter
// ---------------------------------------------------------------------------

/// An INSERT that sets an initial counter value requires the declaration.
Future<void> createProduct(Ditto ditto, String productId, String name) async {
  await ditto.store.execute(
    'INSERT INTO COLLECTION products (viewCount COUNTER) DOCUMENTS (:product)',
    arguments: {
      'product': {'_id': productId, 'name': name, 'viewCount': 0},
    },
  );
}

Future<void> recordView(Ditto ditto, String productId) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION products (viewCount COUNTER)
    APPLY viewCount INCREMENT BY 1
    WHERE _id = :id
    ''',
    arguments: {'id': productId},
  );
}

Future<int?> viewCount(Ditto ditto, String productId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM COLLECTION products (viewCount COUNTER) WHERE _id = :id',
    arguments: {'id': productId},
  );
  if (result.items.isEmpty) return null;
  return (result.items.first.value['viewCount'] as num?)?.toInt();
}

/// ✅ GOOD: Each device records its own sales; concurrent decrements combine.
/// APPLY can be combined with SET in one statement; write APPLY first.
Future<void> sellOne(Ditto ditto, String itemId) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION inventory (stockCount COUNTER)
    APPLY stockCount INCREMENT BY -1
    SET lastAdjustedAt = :now
    WHERE _id = :id
    ''',
    arguments: {
      'id': itemId,
      'now': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

/// ✅ GOOD: RESTART WITH for an occasional correction by one authority, such
/// as recalibrating stock after a physical count, run only while every device
/// that changes the counter is online and in sync.
///
/// Note (SDK 5.1.0): a RESTART discards every increment that this device had
/// not received when it ran the restart, including increments that other
/// devices make later (by the clock) until the restart reaches them. If tills
/// keep selling offline during a recount, store recounts and sales as event
/// documents and derive the stock instead.
Future<void> recordStockCount(Ditto ditto, String itemId, int counted) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION inventory (stockCount COUNTER)
    APPLY stockCount RESTART WITH :counted
    WHERE _id = :id
    ''',
    arguments: {'id': itemId, 'counted': counted},
  );
}

// ---------------------------------------------------------------------------
// ❌ BAD: Counter mistakes
// ---------------------------------------------------------------------------

/// ❌ BAD: Read-modify-write on a register. Two devices that each sell one
/// item from a stock of 10 concurrently both write 9; after sync the stock is
/// 9 instead of 8.
Future<void> sellOneIncorrectly(Ditto ditto, String itemId) async {
  await ditto.store.execute(
    'UPDATE inventory SET stockLevel = stockLevel - 1 WHERE _id = :id',
    arguments: {'id': itemId},
  );
}

/// ❌ BAD: An undeclared INSERT stores viewCount as a REGISTER. A later
/// `APPLY viewCount INCREMENT BY 1` starts a separate counter at 0, so the
/// value becomes 1, not 6.
Future<void> createProductIncorrectly(Ditto ditto, String productId) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product)',
    arguments: {
      'product': {'_id': productId, 'viewCount': 5},
    },
  );
}

/// ❌ BAD: Overwriting a counter with SET. Use APPLY ... RESTART WITH.
Future<void> resetViewsIncorrectly(Ditto ditto, String productId) async {
  await ditto.store.execute(
    'UPDATE products SET viewCount = 0 WHERE _id = :id',
    arguments: {'id': productId},
  );
}

// Other poor fits for COUNTER (not shown as code):
// - Unique sequence numbers (invoice or ticket numbers): two offline devices
//   both produce the same "next" number. Use UUIDs plus a display label.
// - Balances that must be validated ("never below zero"): a counter cannot
//   enforce a constraint. Record transactions as events and validate when you
//   derive the balance.
// - Values derivable from stored documents: use SELECT COUNT(*) ...
// - Fractional amounts: COUNTER is integer-only (INCREMENT BY 1.5 fails with
//   "Expected 1.5 to be an integer value").
//   Count in minor units such as cents.
// - Mixing COUNTER and the legacy PN_INCREMENT operator on one field.
