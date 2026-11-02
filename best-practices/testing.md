# Testing Strategies

Many problems in Ditto apps come from the data model and the queries: a write that replaces a map instead of updating one entry, a soft-delete filter that hides documents without the flag, an observer that is never cancelled. These are cheap to catch in automated tests that run against a **real local Ditto store** on a single device. Multi-device behavior (concurrent edits, deletions that meet updates, multi-hop relay) needs a separate, smaller set of tests with real sync; most of them can run as several Ditto instances in one test process (see [Several peers in one test process](#several-peers-in-one-test-process)).

| Test layer | What it covers | Ditto instance | License or server needed |
|---|---|---|---|
| Unit tests with a mock | UI and business logic that only needs your repository interface | None (mock your own interface) | No |
| Local store tests | Your DQL statements, write shapes, soft-delete filters, observer and subscription lifecycle | Real, small-peers-only, sync never started | No |
| Multi-peer tests in one process | Concurrent edits and merges, deletion propagation, relay, attachments across peers | Several real instances syncing over TCP on localhost | Yes: an offline license token |
| Tests on real devices | Transports (Bluetooth LE, P2P Wi-Fi, LAN), permissions, Ditto Server, real clocks | Your app on devices | An offline license token, or a Ditto Server test database |

**✅ DO:**
- Keep Ditto behind a repository or service interface in your app, so widgets and business logic can be unit-tested with a mock.
- Test every DQL statement your app uses against a real local store, with a fresh temporary persistence directory per test.
- Apply the same system parameters in tests as in the app (for example `DQL_STRICT_MODE`), because they change how statements behave and are not persisted (see [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters)).
- Close every instance in `tearDown` (or `addTearDown`) so that no persistence directory stays open.

**❌ DON'T:**
- Share one persistence directory between tests or open it twice; in Flutter, a second `Ditto.open()` on an open directory may never complete (see [One instance per persistence directory](setup-and-lifecycle.md#one-instance-per-persistence-directory)).
- Start sync in local store tests. It is not needed, and in small-peers-only mode `ditto.sync.start()` throws without an offline license token (see [Initializing Ditto](setup-and-lifecycle.md#initializing-ditto)).
- Write tests that only re-check SDK behavior. Test your own repository functions, your data model, and your business rules.

## A Test Helper for a Local Store

The test file below contains a helper that opens a small-peers-only instance (the default `connect` mode) in its own temporary directory and closes it automatically when the test ends. Because sync is never started, it needs no license token and no network, so it can run in CI. Pass the same `systemParameters` that your app passes in its `DittoConfig`, and a `configure` callback for the indexes that your app creates at startup. As your suite grows, move the helper into a shared file under `integration_test/`.

```dart
// integration_test/orders_test.dart
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

  // Runs after the test, even when it fails.
  addTearDown(() async {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort: the OS removes temporary directories eventually.
    }
  });

  // Create the app's indexes, as at app startup.
  await configure?.call(ditto);
  return ditto;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Every test starts with an empty store.
  late Ditto ditto;
  setUp(() async {
    // Pass `systemParameters:` and `configure:` with the settings and
    // indexes your app uses; see "Applying System Parameters".
    ditto = await openTestDitto();
  });

  test('a new store is empty', () async {
    final result = await ditto.store.execute('SELECT COUNT(*) AS n FROM orders');
    expect(result.items.first.value['n'], 0);
  });

  // The tests in the following sections go here.
}
```

**Running the tests:** A real `Ditto` instance needs the SDK's native library, which is packaged with your app build for each platform. Run tests that open Ditto with the `integration_test` package on a supported desktop or device target, for example `flutter test integration_test/orders_test.dart -d macos`. Tests that use only a mock of your own interface run with a plain `flutter test`. On Flutter Web the store is in memory and does not support indexes (see [Requirements](setup-and-lifecycle.md#requirements)), so skip index assertions there.

The following examples are written as `test(...)` calls (and, in one case, a helper function) that go inside `main()` of such a file, with `ditto` provided by `setUp`. Their `import` lines belong at the top of the file. The examples define the statements and functions under test inline so that each one is complete; in your suite, call your app's repository functions instead, so that a test fails when the app code changes.

## Testing Merge-Sensitive Writes

A single device cannot reproduce a concurrent merge, but it can verify that your code produces the **write shape** that merges well: field-level updates instead of whole-document rewrites, maps keyed by ID instead of arrays, and upserts that skip unchanged values (see [CRDT Types and Merge Behavior](../knowledge/crdt-types.md) and [Arrays and Maps](data-modeling.md#arrays-and-maps)). Assert the local semantics your code relies on, so that a refactoring that switches to a whole-document write or an array is caught.

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

If your app declares types (`REGISTER`, `COUNTER`, `ATTACHMENT`) or enables strict mode, test those statements with the same declarations and settings; mixed declarations produce results that look like data loss (see [Keep type declarations consistent](data-modeling.md#keep-type-declarations-consistent)).

## Testing Deletion and Soft Delete

Deletion logic fails silently: a filter that excludes documents without the flag, or a statement that completes without removing anything. Insert documents in every state your data can be in (flag `true`, `false`, `null`, and missing) and assert exactly which ones your queries return (see [Soft Delete](deletion-and-storage.md#soft-delete) and [MISSING and NULL](dql.md#missing-and-null)).

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

Assertions on the number of removed documents also catch SDK 5.1.0, where `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) removes nothing (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)). Run the same tests on every SDK release that devices in the field use. Tombstone expiry, husk documents, and "zombie data" from devices that were offline longer than the tombstone TTL involve several peers; cover them in multi-device tests (see [Testing on Multiple Devices](#testing-on-multiple-devices)).

## Testing Observer Lifecycle

Test that your observers deliver updates, and that your cleanup code cancels both the stream subscription and the observer (see [Observer lifecycle and cleanup](observers.md#observer-lifecycle-and-cleanup)). Wait for a specific result with a timeout instead of a fixed delay, and do not assert on the number of callbacks; it is not guaranteed.

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

For widget tests of screens that own observers, keep the observer behind your own interface and inject a stream you control. `Differ` only accepts items produced by Ditto, so code that uses it needs a real store (see [Diffing Results](observers.md#diffing-results)).

## Testing Subscription Rules

`registerSubscription` validates the query when it is called, even before sync starts. It throws a `DittoException` for projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, `USE IDS`, and (while the system parameter `DQL_RESTRICT_SUBSCRIPTIONS` has its default value `true`) `ORDER BY` and `LIMIT`. `WHERE` filters are allowed (see [Subscription Rules](sync-and-subscriptions.md#subscription-rules) and [The sending peer evaluates a subscription's WHERE clause like a local query](../knowledge/observations/subscriptions-and-replication.md#the-sending-peer-evaluates-a-subscriptions-where-clause-like-a-local-query)). A test that registers every subscription your app uses catches invalid subscription queries without a network. You can also assert that the forms your app must not use are rejected:

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

## Validating DQL in Tests

Keep the DQL statements of your app as constants in one place (for example, a repository class), and run each of them through `EXPLAIN` with representative arguments. `EXPLAIN` parses and plans a statement without executing it (see [EXPLAIN and PROFILE](indexing-and-performance.md#explain-and-profile)), so the test catches syntax errors and other statements that cannot be planned, without touching any data. For hot queries, also assert that the plan uses the index you created; a later change to the query or to strict mode (which disables index scans in 5.1.0, see [Strict Mode](data-modeling.md#strict-mode)) then fails the test.

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

During development, `ADVISE` (SDK 5.1+) suggests the indexes these statements need (see [ADVISE (SDK 5.1+)](indexing-and-performance.md#advise-sdk-51)).

## Testing on Multiple Devices

Concurrent edits, merges, deletion propagation, multi-hop relay, and attachment fetching across peers can only be tested with sync running between real Ditto instances. Most of these tests do not need several physical devices: several instances in one test process can sync with each other over TCP on localhost (see the next section).

- **Small-peers-only sync** requires an **offline license token** from Ditto: `ditto.sync.start()` throws until `ditto.setOfflineOnlyLicenseToken(token)` has been called with a valid token (see [Initializing Ditto](setup-and-lifecycle.md#initializing-ditto)). Without a token, tests are limited to a single local store. Keep the token out of source control; pass it to tests from a CI secret.
- **Sync through Ditto Server** requires a Ditto Server database for testing. Use separate databases (apps) for development, staging, and production, or one database per developer; developers who share a database can prefix collection names to isolate their test data. There is no Ditto Server mock for CI, so run these tests against a test database.
- **Offline scenarios:** To simulate a Ditto Server outage while keeping peer-to-peer sync, let the app authenticate first and then block the Ditto Server host at the network level; blocking it before authentication makes sync fail entirely.

### Several peers in one test process

The helpers below open several small peers in one `integration_test` process and connect them over TCP on `127.0.0.1` only (see [A device that only connects over TCP also listens for TCP connections](../knowledge/observations/connections-and-presence.md#a-device-that-only-connects-over-tcp-also-listens-for-tcp-connections)):
- Each peer has its own persistence directory, and all peers share one Database ID.
- Each group of peers needs its own port and Database ID. Pass different values when a test opens two groups (two stores, for example) and in test processes that can run at the same time on one machine (parallel CI jobs). In our testing, a second hub listened on a port that another Ditto hub already used, without an error, and a client that reconnected then moved to the newer hub and mixed the documents of both groups; with different Database IDs, the groups did not mix, and the test failed visibly (see [A second hub listened on a port already in use without an error](../knowledge/observations/connections-and-presence.md#a-second-hub-listened-on-a-port-already-in-use-without-an-error) and [Devices with different Database IDs do not sync](../knowledge/observations/persistence-directory.md#devices-with-different-database-ids-do-not-sync)).
- Peer-to-peer transports are disabled, so a test never connects to devices nearby.
- `whileDisconnected` stops sync on every peer, runs the writes, and reconnects the peers. Writes made inside it are concurrent, like edits on devices that are offline at the same time. Writes made while the peers are connected reach the other peers within milliseconds and do not test a merge.
- `waitForConvergence` waits, with a timeout, until every peer returns the same rows.

This file was verified with `ditto_live` 5.1.0 and has not yet been run with 5.2.0. Run it with `flutter test integration_test/multipeer_test.dart -d macos --dart-define-from-file=license.json`, where `license.json` (not committed) contains `{"DITTO_LICENSE_TOKEN": "..."}`.

```dart
// integration_test/multipeer_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Offline license token, passed with --dart-define (never commit it).
const licenseToken = String.fromEnvironment('DITTO_LICENSE_TOKEN');

/// Opens [count] peers in this process that sync with each other over TCP on
/// localhost only: peer 0 listens, the others connect to it. A device accepts
/// at most 6 TCP connections by default, so keep [count] at 7 or below.
Future<List<Ditto>> openSyncedPeers(
  int count, {
  int port = 4041,
  String databaseID = '00000000-0000-4000-8000-000000000002',
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final peers = <Ditto>[];
  for (var i = 0; i < count; i++) {
    final directory = await Directory.systemTemp.createTemp('ditto_peer${i}_');
    final ditto = await Ditto.open(
      DittoConfig(
        // All peers of a group use the same database ID; give every group
        // that can run at the same time its own ID and port.
        databaseID: databaseID,
        persistenceDirectory: directory.path,
      ),
    );
    addTearDown(() async {
      await ditto.close();
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Best effort.
      }
    });
    ditto.setOfflineOnlyLicenseToken(licenseToken);
    ditto.updateTransportConfig((config) {
      config.setAllPeerToPeerEnabled(false); // no Bluetooth, LAN, or AWDL
      if (i == 0) {
        config.listen.tcp
          ..isEnabled = true
          ..interfaceIP = '127.0.0.1'
          ..port = port;
      } else {
        config.connect.tcpServers = {'127.0.0.1:$port'};
        // A device that only connects still listens on every interface, so
        // bind its listener to this machine: test peers stay off the network.
        config.listen.tcp
          ..isEnabled = true
          ..interfaceIP = '127.0.0.1'
          ..port = 0;
      }
    });
    // App setup after open, such as indexes. On SDK 5.2+, pass system
    // parameters in the DittoConfig above instead.
    await configure?.call(ditto);
    ditto.sync.start();
    peers.add(ditto);
  }
  await _waitUntil(() => peers.every(_isConnected));
  return peers;
}

bool _isConnected(Ditto ditto) => ditto.presence.graph.remotePeers.isNotEmpty;

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Stops sync on every peer, runs [writes] while the peers are disconnected,
/// then reconnects them, so the writes are concurrent.
Future<void> whileDisconnected(
  List<Ditto> peers,
  Future<void> Function() writes,
) async {
  for (final peer in peers) {
    peer.sync.stop();
  }
  await _waitUntil(() => peers.every((peer) => !_isConnected(peer)));
  await writes();
  for (final peer in peers) {
    peer.sync.start();
  }
  await _waitUntil(() => peers.every(_isConnected));
}

/// Waits until [query] returns the same rows on every peer and [until] holds
/// for them, then returns the rows.
Future<List<Map<String, dynamic>>> waitForConvergence(
  List<Ditto> peers,
  String query, {
  Map<String, dynamic> arguments = const {},
  bool Function(List<Map<String, dynamic>> rows)? until,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final results = <List<Map<String, dynamic>>>[];
    for (final peer in peers) {
      final result = await peer.store.execute(query, arguments: arguments);
      results.add(result.items.map((item) => item.value).toList());
    }
    final first = jsonEncode(results.first);
    final same = results.every((rows) => jsonEncode(rows) == first);
    if (same && (until == null || until(results.first))) return results.first;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Peers did not converge: $results', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final skip = licenseToken.isEmpty ? 'Needs DITTO_LICENSE_TOKEN' : null;

  test('concurrent edits of different line items both survive', () async {
    final [tablet, phone] = await openSyncedPeers(2);
    for (final peer in [tablet, phone]) {
      peer.sync.registerSubscription('SELECT * FROM orders');
    }
    await tablet.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': 'order-1',
          'items': {
            'item-1': {'productId': 'p1', 'quantity': 1},
          },
        },
      },
    );
    await waitForConvergence(
      [tablet, phone],
      'SELECT * FROM orders',
      until: (rows) => rows.length == 1,
    );

    // The code under test would be the app's repository functions.
    await whileDisconnected([tablet, phone], () async {
      await tablet.store.execute(
        'UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id',
        arguments: {'id': 'order-1'},
      );
      await phone.store.execute(
        'UPDATE orders SET items.`item-2` = :item WHERE _id = :id',
        arguments: {
          'id': 'order-1',
          'item': {'productId': 'p2', 'quantity': 1},
        },
      );
    });

    final rows = await waitForConvergence(
      [tablet, phone],
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': 'order-1'},
      until: (rows) => (rows.single['items'] as Map).length == 2,
    );
    final items = rows.single['items'] as Map;
    expect(items['item-1']['quantity'], 3);
    expect(items['item-2']['productId'], 'p2');
  }, skip: skip);
}
```

This setup does not cover the following, so keep a few tests on real devices:
- All peers share one clock. Clock skew between devices is not simulated.
- Only TCP is exercised. Bluetooth LE, P2P Wi-Fi, LAN discovery, permissions, and app lifecycle need real devices.
- A listening peer accepts at most 6 TCP connections by default (in our testing with SDK 5.1.0 and 5.2.0; see [A device accepts six TCP connections by default](../knowledge/observations/connections-and-presence.md#a-device-accepts-six-tcp-connections-by-default)). On 5.2.0, the connections that a peer opened itself count toward the limit too (see [Transport Configuration](setup-and-lifecycle.md#transport-configuration)). For a relay test, chain the peers: A listens, B listens and connects to A, and C connects to B.

Scenarios worth covering (with the helpers above, or on real devices):
- Two devices edit **different fields** and the **same field** of one document while offline, then reconnect.
- Two devices add, edit, and remove entries of the same map (and, for comparison, the same array) while offline.
- One device deletes a document while another updates it (expect a [husk document](deletion-and-storage.md#husk-documents)), and the same with a soft delete.
- A device that missed a soft delete while offline and then syncs only through a relay (see [Soft delete, subscriptions, and cleanup](deletion-and-storage.md#soft-delete-subscriptions-and-cleanup)).
- A counter that one device recounts with `RESTART WITH` while another keeps incrementing it (see [RESTART](data-modeling.md#restart)).
- A device behind a relay with narrower subscriptions (see [Multi-hop relay](sync-and-subscriptions.md#multi-hop-relay)).
- Attachments created offline and fetched by other peers later (see [Availability](attachments.md#availability)).
- Each transport your users rely on, including Bluetooth LE as the only transport (on real devices).

See the [testing guide](https://docs.ditto.live/sdk/latest/deployment/testing) for environment setup and offline simulation.
