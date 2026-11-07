# Testing Strategies

**Test every DQL statement and write shape against a real local store with sync off, test merges and deletions with several instances that sync over localhost, and keep real devices for transports, permissions, and clocks.** Many problems in Ditto apps come from the data model and the queries: a write that replaces a map instead of updating one entry, a soft-delete filter that hides documents without the flag, an observer that is never cancelled. These are cheap to catch in automated tests that run against a **real local Ditto store** on a single device. Multi-device behavior (concurrent edits, deletions that meet updates, multi-hop relay) needs a separate, smaller set of tests with real sync; most of them can run as several Ditto instances in one test process (see [Several peers in one test process](#several-peers-in-one-test-process)).

| Test layer | What it covers | Ditto instance | License or server needed |
|---|---|---|---|
| Unit tests with a mock | UI and business logic that only needs your repository interface | None (mock your own interface) | No |
| Local store tests | Your DQL statements, write shapes, soft-delete filters, observer and subscription lifecycle | Real, small-peers-only, sync never started | No |
| Multi-peer tests in one process | Concurrent edits and merges, deletion propagation, relay, attachments across peers | Several real instances syncing over TCP on localhost | Yes: an offline license token |
| Tests on real devices | Transports (Bluetooth LE, P2P Wi-Fi, LAN), permissions, Ditto Server, real clocks | Your app on devices | An offline license token, or a Ditto Server test database |

**✅ DO:**
- Keep Ditto behind a repository or service interface in your app, so UI components and business logic can be unit-tested with a mock.
- Test every DQL statement your app uses against a real local store, with a fresh temporary persistence directory per test.
- Apply the same system parameters in tests as in the app (for example `DQL_STRICT_MODE`), because they change how statements behave and are not persisted (see [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters)).
- Close every instance when its test ends, also when the test fails, so that no persistence directory stays open. On Flutter 5.2.0, close the test stores after the last test of the file instead: in our testing, a process that closed one store per test, each with a subscription or a transaction, stopped at a later `Ditto.open()` (see [A local-store test helper in Flutter](platforms/flutter.md#a-local-store-test-helper-in-flutter) and [In Flutter 5.2.0, dropped subscription and transaction objects of a closed instance stop the next open or close](../knowledge/observations/flutter-sdk.md#in-flutter-520-dropped-subscription-and-transaction-objects-of-a-closed-instance-stop-the-next-open-or-close)).

**❌ DON'T:**
- Share one persistence directory between tests or open it twice; in some SDKs, a second open of an open directory never completes (see [One instance per persistence directory](setup-and-lifecycle.md#one-instance-per-persistence-directory)).
- Start sync in local store tests. It is not needed, and in small-peers-only mode starting sync fails without an offline license token (see [Initializing Ditto](setup-and-lifecycle.md#initializing-ditto)).
- Write tests that only re-check SDK behavior. Test your own repository functions, your data model, and your business rules.

## A Test Helper for a Local Store

Write one helper that every local store test uses. It:

1. Creates a new temporary directory for each test and opens a small-peers-only instance (the default connection mode) in it, with any UUID as the Database ID.
2. Passes the same system parameters that your app passes in its `DittoConfig`, and runs the same startup code that creates your app's indexes.
3. Never starts sync, so it needs no license token and no network and can run in CI.
4. Closes the instance and deletes the directory when the test ends, also when it fails (on Flutter 5.2.0, after the last test of the file, as described above).

```sql
-- A first test: a new store is empty
SELECT COUNT(*) AS n FROM orders
-- Expected: one row, {"n": 0}
```

A real Ditto instance needs the SDK's native library, so tests that open Ditto run where the SDK runs: a desktop or device target in Flutter, a simulator or macOS in Swift, an emulator or device in Kotlin, and Node.js or a browser in JavaScript. Tests that use only a mock of your own interface run without it.

The examples in the following sections show each test as the statements it runs and the result it expects. They define the statements under test inline so that each one is complete; in your suite, call your app's repository functions instead, so that a test fails when the app code changes. The helper and the tests for each SDK: [A local-store test helper in Flutter](platforms/flutter.md#a-local-store-test-helper-in-flutter) · [JavaScript](platforms/javascript.md#a-local-store-test-helper-in-javascript) · [Kotlin](platforms/kotlin.md#a-local-store-test-helper-in-kotlin) · [Swift](platforms/swift.md#a-local-store-test-helper-in-swift).

## Testing Merge-Sensitive Writes

A single device cannot reproduce a concurrent merge, but it can verify that your code produces the **write shape** that merges well: field-level updates instead of whole-document rewrites, maps keyed by ID instead of arrays, and upserts that skip unchanged values (see [CRDT Types and Merge Behavior](../knowledge/crdt-types.md) and [Arrays and Maps](data-modeling.md#arrays-and-maps)). Assert the local semantics your code relies on, so that a refactoring that switches to a whole-document write or an array is caught.

```sql
-- Test: adding a line item keeps the existing items (map keyed by ID)
-- Arguments: {"order": {"_id": "order-1", "items": {"item-1": {"productId": "p1", "quantity": 2}}}}
INSERT INTO orders DOCUMENTS (:order)

-- The code under test: an upsert of a partial document (see "Arrays and Maps")
-- Arguments: {"patch": {"_id": "order-1", "items": {"item-2": {"productId": "p2", "quantity": 1}}}}
INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Expected: items is a map (not an array) with the keys item-1 and item-2
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id
```

```sql
-- Test: re-upserting unchanged data is a no-op
-- Arguments: {"product": {"_id": "p1", "name": "Pen", "priceCents": 250}}
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Run the same statement again. Expected: no mutated document IDs
-- Arguments: {"product": {"_id": "p1", "name": "Pen", "priceCents": 250}}
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

```sql
-- Test: replacing an address removes keys that are not in the new address
-- Arguments: {"customer": {"_id": "c1", "address": {"city": "Oslo", "zip": "0150"}}}
INSERT INTO customers DOCUMENTS (:customer)

-- The code under test: both statements in one transaction
-- (see "Assigning an object merges it")
-- Arguments: {"id": "c1"}
UPDATE customers UNSET address WHERE _id = :id

-- Arguments: {"id": "c1", "address": {"city": "Bergen"}}
UPDATE customers SET address = :address WHERE _id = :id

-- Expected: address is {"city": "Bergen"}. A plain SET would keep "zip":
-- objects merge under the default settings.
-- Arguments: {"id": "c1"}
SELECT * FROM customers WHERE _id = :id
```

If your app declares types (`REGISTER`, `COUNTER`, `ATTACHMENT`) or enables strict mode, test those statements with the same declarations and settings; mixed declarations produce results that look like data loss (see [Keep type declarations consistent](data-modeling.md#keep-type-declarations-consistent)).

## Testing Deletion and Soft Delete

Deletion logic fails silently: a filter that excludes documents without the flag, or a statement that completes without removing anything. Insert documents in every state your data can be in (flag `true`, `false`, `null`, and missing) and assert exactly which ones your queries return (see [Soft Delete](deletion-and-storage.md#soft-delete) and [MISSING and NULL](dql.md#missing-and-null)).

```sql
-- Test: the active-orders query treats a missing or null flag as not deleted
-- Arguments: {"orders": [{"_id": "deleted", "isDeleted": true}, {"_id": "active", "isDeleted": false}, {"_id": "nullFlag", "isDeleted": null}, {"_id": "noFlag"}]}
INSERT INTO orders DOCUMENTS (:orders)

-- The query used by the app's repository. Expected: active, noFlag, nullFlag
SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id
```

```sql
-- Test: deleting by ID removes exactly the listed documents
-- Arguments: {"orders": [{"_id": "o1"}, {"_id": "o2"}, {"_id": "o3"}]}
INSERT INTO orders DOCUMENTS (:orders)

-- The statement used by the app; WHERE _id IN :ids, not USE IDS.
-- Expected: two mutated document IDs
-- Arguments: {"ids": ["o1", "o2"]}
DELETE FROM orders WHERE _id IN :ids

-- Expected: only o3
SELECT _id FROM orders
```

Assertions on the number of removed documents also catch SDK 5.1.0, where `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) removes nothing (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)). Run the same tests on every SDK release that devices in the field use. Tombstone expiry, husk documents, and "zombie data" from devices that were offline longer than the tombstone TTL involve several peers; cover them in multi-device tests (see [Testing on Multiple Devices](#testing-on-multiple-devices)).

## Testing Observer Lifecycle

Test that your observers deliver updates, and that your cleanup code releases them (see [Observer Lifecycle](observers.md#observer-lifecycle)). Register the observer, write a matching document, wait for a specific result with a timeout instead of a fixed delay, then run the same cleanup that the screen runs and check that the observer reports itself as cancelled. Do not assert on the number of callbacks; it is not guaranteed.

```sql
-- The observer under test
-- Arguments: {"status": "open"}
SELECT * FROM orders WHERE status = :status ORDER BY _id

-- The write that it must see within the timeout
-- Arguments: {"order": {"_id": "order-1", "status": "open"}}
INSERT INTO orders DOCUMENTS (:order)
```

For UI tests of screens that own observers, keep the observer behind your own interface and inject a stream or a fake you control. The differs accept only items produced by Ditto, so code that uses one needs a real store (see [Diffing Results](observers.md#diffing-results)).

## Testing Subscription Rules

Registering a subscription validates the query when it is called, even before sync starts. It fails for projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, `USE IDS`, and (while the system parameter `DQL_RESTRICT_SUBSCRIPTIONS` has its default value `true`) `ORDER BY` and `LIMIT`. `WHERE` filters are allowed (see [Subscription Rules](sync-and-subscriptions.md#subscription-rules) and [The sending peer evaluates a subscription's WHERE clause like a local query](../knowledge/observations/subscriptions-and-replication.md#the-sending-peer-evaluates-a-subscriptions-where-clause-like-a-local-query)). A test that registers every subscription your app uses, and then cancels it, catches invalid subscription queries without a network. You can also assert that the forms your app must not use are rejected:

<!-- subscription expect-error -->
```sql
-- Test: subscriptions with projections or ORDER BY and LIMIT are rejected
SELECT _id, status FROM orders

SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50
```

<!-- subscription -->
```sql
-- Test: the app's subscriptions are valid; cancel each one afterwards
-- Arguments: {"storeId": "store-1"}
SELECT * FROM orders WHERE storeId = :storeId

SELECT * FROM products
```

## Validating DQL in Tests

Keep the DQL statements of your app as constants in one place (for example, a repository class), and run each of them through `EXPLAIN` with representative arguments. `EXPLAIN` parses and plans a statement without executing it (see [EXPLAIN and PROFILE](indexing-and-performance.md#explain-and-profile)), so the test catches syntax errors and other statements that cannot be planned, without touching any data. For hot queries, also assert that the plan uses the index you created; a later change to the query or to strict mode (which disables index scans on SDK 5.1.0 and 5.2.0; see [Strict mode and data types](indexing-and-performance.md#strict-mode-and-data-types)) then fails the test.

```sql
-- Test: every app statement can be planned; EXPLAIN fails if it cannot
-- Arguments: {"status": "open"}
EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC

-- Arguments: {"status": "closed", "id": "order-1"}
EXPLAIN UPDATE orders SET status = :status WHERE _id = :id

-- Arguments: {"ids": ["order-1"]}
EXPLAIN DELETE FROM orders WHERE _id IN :ids
```

```sql
-- Test: the open-orders query uses its index. Create the index with the same
-- startup code as the app; expected: the plan contains "indexScan"
CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)

-- Arguments: {"status": "open"}
EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC
```

During development, `ADVISE` (SDK 5.1+) suggests the indexes these statements need (see [ADVISE (SDK 5.1+)](indexing-and-performance.md#advise-sdk-51)).

## Testing on Multiple Devices

Concurrent edits, merges, deletion propagation, multi-hop relay, and attachment fetching across peers can only be tested with sync running between real Ditto instances. Most of these tests do not need several physical devices: several instances in one test process can sync with each other over TCP on localhost (see the next section).

- **Small-peers-only sync** requires an **offline license token** from Ditto: starting sync fails until a valid token has been set with `setOfflineOnlyLicenseToken` (see [Initializing Ditto](setup-and-lifecycle.md#initializing-ditto)). Without a token, tests are limited to a single local store. Keep the token out of source control; pass it to tests from a CI secret.
- **Sync through Ditto Server** requires a Ditto Server database for testing. Use separate databases (apps) for development, staging, and production, or one database per developer; developers who share a database can prefix collection names to isolate their test data. There is no Ditto Server mock for CI, so run these tests against a test database.
- **Offline scenarios:** To simulate a Ditto Server outage while keeping peer-to-peer sync, let the app authenticate first and then block the Ditto Server host at the network level; blocking it before authentication makes sync fail entirely.

### Several peers in one test process

Helpers for multi-peer tests open several small peers in one test process and connect them over TCP on `127.0.0.1` only (see [A device that only connects over TCP also listens for TCP connections](../knowledge/observations/connections-and-presence.md#a-device-that-only-connects-over-tcp-also-listens-for-tcp-connections)):
- Each peer has its own persistence directory, and all peers share one Database ID.
- Each group of peers needs its own port and Database ID. Pass different values when a test opens two groups (two stores, for example) and in test processes that can run at the same time on one machine (parallel CI jobs). In our testing, a second hub listened on a port that another Ditto hub already used, without an error, and a client that reconnected then moved to the newer hub and mixed the documents of both groups; with different Database IDs, the groups did not mix, and the test failed visibly (see [A second hub listened on a port already in use without an error](../knowledge/observations/connections-and-presence.md#a-second-hub-listened-on-a-port-already-in-use-without-an-error) and [Devices with different Database IDs do not sync](../knowledge/observations/persistence-directory.md#devices-with-different-database-ids-do-not-sync)).
- Peer-to-peer transports are disabled, so a test never connects to devices nearby.
- `whileDisconnected` stops sync on every peer, runs the writes, and reconnects the peers. Writes made inside it are concurrent, like edits on devices that are offline at the same time. Writes made while the peers are connected reach the other peers within milliseconds and do not test a merge.
- `waitForConvergence` waits, with a timeout, until every peer returns the same rows.

```sql
-- Test: concurrent edits of different line items both survive
-- On the first peer, before the peers disconnect:
-- Arguments: {"order": {"_id": "order-1", "items": {"item-1": {"productId": "p1", "quantity": 1}}}}
INSERT INTO orders DOCUMENTS (:order)

-- While disconnected, on the first peer:
-- Arguments: {"id": "order-1"}
UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id

-- While disconnected, on the second peer:
-- Arguments: {"id": "order-1", "item": {"productId": "p2", "quantity": 1}}
UPDATE orders SET items.`item-2` = :item WHERE _id = :id

-- After reconnecting, every peer converges on two items: item-1 with
-- quantity 3 and item-2 with productId p2
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id
```

The helpers and this test for each SDK: [Several peers in one test in Flutter](platforms/flutter.md#several-peers-in-one-test-in-flutter) · [JavaScript](platforms/javascript.md#several-peers-in-one-test-in-javascript) · [Kotlin](platforms/kotlin.md#several-peers-in-one-test-in-kotlin) · [Swift](platforms/swift.md#several-peers-in-one-test-in-swift).

This setup does not cover the following, so keep a few tests on real devices:
- All peers share one clock. Clock skew between devices is not simulated.
- Only TCP is exercised. Bluetooth LE, P2P Wi-Fi, LAN discovery, permissions, and app lifecycle need real devices. Two iOS simulators on one Mac can also sync over AWDL: in our testing with SDK 5.1.0 and 5.2.0, two simulators with only AWDL enabled synced, and with AWDL disabled too they did not. The simulators share the Mac's network, so such a test checks that your app syncs with the transport configuration it sets, not how AWDL behaves over the air (see [Two iOS simulators synced over AWDL alone](../knowledge/observations/connections-and-presence.md#two-ios-simulators-synced-over-awdl-alone)).
- A listening peer accepts at most 6 TCP connections by default (in our testing with SDK 5.1.0 and 5.2.0; see [A device accepts six TCP connections by default](../knowledge/observations/connections-and-presence.md#a-device-accepts-six-tcp-connections-by-default)). On 5.2.0, the connections that a peer opened itself count toward the limit too (see [Transport Configuration](setup-and-lifecycle.md#transport-configuration)). For a relay test, chain the peers: A listens, B listens and connects to A, and C connects to B.

Scenarios worth covering (with the helpers above, or on real devices):
- Two devices edit **different fields** and the **same field** of one document while offline, then reconnect.
- Two devices add, edit, and remove entries of the same map (and, for comparison, the same array) while offline.
- One device deletes a document while another updates it (expect a [husk document](deletion-and-storage.md#husk-documents)), and the same with a soft delete.
- A device that missed a soft delete while offline and then syncs only through a relay (see [Soft delete, subscriptions, and cleanup](deletion-and-storage.md#soft-delete-subscriptions-and-cleanup)).
- A counter that one device recounts with `RESTART WITH`, or re-imports with an upsert, while another keeps incrementing it (see [RESTART](data-modeling.md#restart) and [Writing documents that contain counters](data-modeling.md#writing-documents-that-contain-counters)).
- Shutdown right after a write: the code waits until the hub confirms the write's `commitID` before `close()`, and the hub then has the document (see [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown)).
- A user signs out of a shared device and another signs in: the first user's documents are gone and do not sync back after sync starts again (see [Switching users on a shared device](setup-and-lifecycle.md#switching-users-on-a-shared-device)).
- A device behind a relay with narrower subscriptions (see [Multi-hop relay](sync-and-subscriptions.md#multi-hop-relay)).
- Attachments created offline and fetched by other peers later (see [Availability](attachments.md#availability)).
- Each transport your users rely on, including Bluetooth LE as the only transport (on real devices).

See the [testing guide](https://docs.ditto.live/sdk/latest/deployment/testing) for environment setup and offline simulation.
