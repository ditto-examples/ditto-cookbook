// Ditto SDK: 5.2.0 (Flutter package ditto_live), verified with ditto_live 5.2.0
//
// Local store tests: merge-sensitive writes, deletion and soft delete, observer lifecycle, subscription rules, and DQL validation with EXPLAIN. Run with: flutter test integration_test/local_store_test.dart -d macos
//
// What each test checks, as DQL and expected results, is in
// ../../reference/local-store-tests.md and in the guide's Testing Strategies; the same
// tests for the other SDKs are in examples/<sdk>/ with the same base name.
//
// Guide: § Testing Merge-Sensitive Writes, § Testing Deletion and Soft Delete, § Testing Observer Lifecycle, § Testing Subscription Rules, § Validating DQL in Tests, § Testing in Flutter

// integration_test/local_store_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';


/// The stores that the tests of this file opened. They close together after
/// the last test: on SDK 5.2.0, opening a store after another store of the
/// process was closed could stop (guide: § A local-store test helper in Flutter).
final _testStores = <(Ditto, Directory)>[];

/// Opens a Ditto instance for one test. Sync is never started, so no
/// license token or network connection is needed.
Future<Ditto> openTestDitto({
  Map<String, Object> systemParameters = const {},
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final directory = await Directory.systemTemp.createTemp('ditto_test_');
  final ditto = await Ditto.open(
    DittoConfig(
      // Any UUID works for local tests; each test gets its own directory.
      databaseID: '00000000-0000-4000-8000-000000000001',
      persistenceDirectory: directory.path,
      // The same parameters as the app's DittoConfig (SDK 5.2+).
      systemParameters: systemParameters,
    ),
  );

  _testStores.add((ditto, directory)); // closed by closeTestDittos()

  // Create the app's indexes, as at app startup.
  await configure?.call(ditto);
  return ditto;
}

/// Closes every store that openTestDitto() opened and deletes its directory.
/// Register it once per file: tearDownAll(closeTestDittos).
Future<void> closeTestDittos() async {
  for (final (ditto, directory) in _testStores) {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort: the OS removes temporary directories eventually.
    }
  }
  _testStores.clear();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(closeTestDittos);

  late Ditto ditto;
  setUp(() async {
    ditto = await openTestDitto();
  });

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
}
