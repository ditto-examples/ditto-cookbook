# Local Store Test Examples

Complete examples from `§ Testing Strategies` (verified with `ditto_live` 5.1.0). Each example goes inside `main()` of the test file in [test-helpers.md](test-helpers.md), with `ditto` provided by `setUp`; move the `import` lines to the top of the file. In your suite, call your app's repository functions instead of the inline statements.

## Contents

- [Merge-sensitive writes](#merge-sensitive-writes)
- [Deletion and soft delete](#deletion-and-soft-delete)
- [Observer lifecycle](#observer-lifecycle)
- [Subscription rules](#subscription-rules)
- [Validating DQL with EXPLAIN](#validating-dql-with-explain)

## Merge-sensitive writes

`§ Testing Merge-Sensitive Writes`. A single device cannot reproduce a concurrent merge, but it can verify that your code produces the **write shape** that merges well: field-level updates instead of whole-document rewrites, maps keyed by ID instead of arrays, and upserts that skip unchanged values (`§ CRDT Types and Merge Behavior`, `§ Arrays and Maps`). Assert the local semantics your code relies on, so that a refactoring that switches to a whole-document write or an array is caught.

```dart
import 'package:flutter_test/flutter_test.dart';

test('adding a line item keeps the existing items (map keyed by ID)', () async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': 'order-1',
        'items': {
          'item-1': {'productId': 'p1', 'quantity': 2},
        },
      },
    },
  );

  // The code under test: an upsert of a partial document (see "Arrays and Maps").
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': 'order-1',
        'items': {
          'item-2': {'productId': 'p2', 'quantity': 1},
        },
      },
    },
  );

  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :id',
    arguments: {'id': 'order-1'},
  );
  final items = result.items.first.value['items'];
  expect(items, isA<Map<String, dynamic>>()); // not an array
  expect((items as Map).keys, containsAll(<String>['item-1', 'item-2']));
});

test('re-upserting unchanged data is a no-op', () async {
  const product = {'_id': 'p1', 'name': 'Pen', 'priceCents': 250};
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'product': product},
  );

  final again = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'product': product},
  );
  expect(again.mutatedDocumentIDs(), isEmpty);
});

// The code under test: the app's replaceAddress() (see "Assigning an object merges it").
Future<void> replaceAddress(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> address,
) async {
  await ditto.store.transaction(hint: 'replaceAddress', (tx) async {
    await tx.execute(
      'UPDATE customers UNSET address WHERE _id = :id',
      arguments: {'id': customerId},
    );
    await tx.execute(
      'UPDATE customers SET address = :address WHERE _id = :id',
      arguments: {'id': customerId, 'address': address},
    );
  });
}

test('replaceAddress removes keys that are not in the new address', () async {
  await ditto.store.execute(
    'INSERT INTO customers DOCUMENTS (:customer)',
    arguments: {
      'customer': {
        '_id': 'c1',
        'address': {'city': 'Oslo', 'zip': '0150'},
      },
    },
  );

  await replaceAddress(ditto, 'c1', {'city': 'Bergen'});

  final result = await ditto.store.execute(
    'SELECT * FROM customers WHERE _id = :id',
    arguments: {'id': 'c1'},
  );
  // A plain SET would keep "zip": objects merge under the default settings.
  expect(result.items.first.value['address'], {'city': 'Bergen'});
});
```

If your app declares types (`REGISTER`, `COUNTER`, `ATTACHMENT`) or enables strict mode, test those statements with the same declarations and settings; mixed declarations produce results that look like data loss (`§ Keep type declarations consistent`).

## Deletion and soft delete

`§ Testing Deletion and Soft Delete`. Deletion logic fails silently: a filter that excludes documents without the flag, or a statement that completes without removing anything. Insert documents in every state your data can be in (flag `true`, `false`, `null`, and missing) and assert exactly which ones your queries return (`§ Soft Delete`, `§ MISSING and NULL`).

```dart
import 'package:flutter_test/flutter_test.dart';

test('active-orders query treats a missing or null flag as not deleted', () async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:orders)',
    arguments: {
      'orders': [
        {'_id': 'deleted', 'isDeleted': true},
        {'_id': 'active', 'isDeleted': false},
        {'_id': 'nullFlag', 'isDeleted': null},
        {'_id': 'noFlag'},
      ],
    },
  );

  // The query used by the app's repository.
  final result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id',
  );
  expect(
    result.items.map((item) => item.value['_id']).toList(),
    ['active', 'noFlag', 'nullFlag'],
  );
});

test('deleting by ID removes exactly the listed documents', () async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:orders)',
    arguments: {
      'orders': [
        {'_id': 'o1'},
        {'_id': 'o2'},
        {'_id': 'o3'},
      ],
    },
  );

  // The statement used by the app; WHERE _id IN :ids, not USE IDS.
  final deleted = await ditto.store.execute(
    'DELETE FROM orders WHERE _id IN :ids',
    arguments: {'ids': ['o1', 'o2']},
  );
  expect(deleted.mutatedDocumentIDs(), hasLength(2));

  final remaining = await ditto.store.execute('SELECT _id FROM orders');
  expect(remaining.items.map((item) => item.value['_id']), ['o3']);
});
```

Assertions on the number of removed documents also catch the SDK 5.1.0 behavior where `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) removes nothing (`§ DELETE and Tombstones`). Tombstone expiry, husk documents, and "zombie data" from devices that were offline longer than the tombstone TTL involve several peers; cover them in multi-device tests ([multi-peer-tests.md](multi-peer-tests.md)).

## Observer lifecycle

`§ Testing Observer Lifecycle`. Test that your observers deliver updates, and that your cleanup code cancels both the stream subscription and the observer (`§ Observer lifecycle and cleanup`). Wait for a specific result with a timeout instead of a fixed delay, and do not assert on the number of callbacks; it is not guaranteed.

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

test('observer sees a new order and is cancelled cleanly', () async {
  final observer = ditto.store.registerObserver(
    'SELECT * FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  final sawOrder = Completer<void>();
  final changes = observer.changes.listen((result) {
    if (result.items.length == 1 && !sawOrder.isCompleted) {
      sawOrder.complete();
    }
  });

  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {'_id': 'order-1', 'status': 'open'},
    },
  );
  await sawOrder.future.timeout(const Duration(seconds: 5));

  // The same cleanup that the widget's dispose() performs.
  await changes.cancel();
  observer.cancel();
  expect(observer.isCancelled, isTrue);
});
```

For widget tests of screens that own observers, keep the observer behind your own interface and inject a stream you control. `Differ` only accepts items produced by Ditto, so code that uses it needs a real store (`§ Diffing Results`).

## Subscription rules

`§ Testing Subscription Rules`. `registerSubscription` validates the query when it is called, even before sync starts. It throws a `DittoException` for projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, `USE IDS`, and (while the system parameter `DQL_RESTRICT_SUBSCRIPTIONS` has its default value `true`) `ORDER BY` and `LIMIT`. `WHERE` filters are allowed (`§ Subscription Rules`). A test that registers every subscription your app uses catches invalid subscription queries without a network. You can also assert that the forms your app must not use are rejected:

<!-- expect-error -->
```dart
import 'package:flutter_test/flutter_test.dart';

test('subscriptions with projections or ORDER BY/LIMIT are rejected', () async {
  expect(
    () => ditto.sync.registerSubscription('SELECT _id, status FROM orders'),
    throwsA(isA<DittoException>()),
  );
  expect(
    () => ditto.sync.registerSubscription(
      'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50',
    ),
    throwsA(isA<DittoException>()),
  );
});
```

The positive counterpart registers the app's real subscriptions and cancels them:

```dart
import 'package:flutter_test/flutter_test.dart';

test("the app's subscriptions are valid", () async {
  final subscriptions = [
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': 'store-1'},
    ),
    ditto.sync.registerSubscription('SELECT * FROM products'),
  ];
  for (final subscription in subscriptions) {
    subscription.cancel();
    expect(subscription.isCancelled, isTrue);
  }
});
```

## Validating DQL with EXPLAIN

`§ Validating DQL in Tests`. Keep the DQL statements of your app as constants in one place (for example, a repository class), and run each of them through `EXPLAIN` with representative arguments. `EXPLAIN` parses and plans a statement without executing it (`§ EXPLAIN and PROFILE`), so the test catches syntax errors and other statements that cannot be planned, without touching any data. For hot queries, also assert that the plan uses the index you created; a later change to the query or to strict mode (which disables index scans in 5.1.0, `§ Strict Mode`) then fails the test.

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// The app's statements with representative arguments. In a real app, keep
/// the statement strings in your repository and reference them here.
const appStatements = <String, Map<String, Object?>>{
  'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC': {
    'status': 'open',
  },
  'UPDATE orders SET status = :status WHERE _id = :id': {
    'status': 'closed',
    'id': 'order-1',
  },
  'DELETE FROM orders WHERE _id IN :ids': {
    'ids': ['order-1'],
  },
};

test('every app statement can be planned', () async {
  for (final MapEntry(key: statement, value: arguments) in appStatements.entries) {
    // EXPLAIN throws if a statement cannot be parsed or planned.
    await ditto.store.execute('EXPLAIN $statement', arguments: arguments);
  }
});

test('the open-orders query uses its index', () async {
  // In your suite, create indexes with the same startup code as the app
  // (for example, through the configure callback of openTestDitto).
  await ditto.store.execute(
    'CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt '
    'ON orders (status, createdAt DESC)',
  );
  final plan = await ditto.store.execute(
    'EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  expect(jsonEncode(plan.items.first.value), contains('indexScan'));
});
```

During development, `ADVISE` (SDK 5.1+) suggests the indexes these statements need (`§ ADVISE (SDK 5.1+)`).
