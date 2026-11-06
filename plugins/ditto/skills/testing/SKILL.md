---
name: testing
description: "Ditto SDK testing strategies in Flutter, JavaScript, Kotlin, or Swift: local-store test helper, tests for DQL statements, MISSING/NULL filters, merge-sensitive writes, soft delete, observer lifecycle, subscription rules, and multi-peer sync tests in one process. Use when writing or reviewing tests for code that uses Ditto, setting up a test harness, or reproducing a sync or merge bug."
---

# Ditto Testing Strategies

How to test code that uses Ditto: a real local store per test for DQL, write shapes, filters, and lifecycle, and several synced peers in one process for merges. Targets Ditto SDK 5.2.0 in every SDK; tests are described as statements and expected results, and the test code is per SDK.

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). These rules target SDK 5.2.0; for devices that still run 5.1.0, also apply `§ Known Issues in SDK 5.1.0`. **Note (SDK 5.1.0 and 5.2.0)** marks easy-to-miss behavior confirmed on both releases, **Note (SDK 5.1.0)** behavior seen on 5.1.0 only; each gives the safe pattern. **(SDK 5.1+)** / **(SDK 5.2+)** mark features introduced in that release.
- Read that SDK's page, `../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), for the API calls; its sections are named `<Topic> in <SDK>`, such as *Testing in Swift*. DQL examples are `examples/*.sql` (every SDK); API examples are in `examples/<sdk>/` with the same base name in every SDK.
- `§ <Heading>` cites the full guide: Grep the heading in `../guide/reference/best-practices/` (including `platforms/`) and `../guide/reference/knowledge/`, then read that section.

## Prevents

- DQL statements that fail to parse or plan only at runtime, and hot queries that silently lose their index scan
- Soft-delete filters that hide documents where the flag is missing or null
- `DELETE`/`EVICT` statements that complete without removing anything (for example `USE IDS` without a `WHERE` predicate on devices that run SDK 5.1.0)
- Write shapes that merge badly (whole-document rewrites, arrays instead of maps, `SET` that keeps old map keys) introduced by a refactoring
- Upserts that rewrite unchanged data
- Observers and stream subscriptions that are never cancelled
- Subscription queries rejected at registration (projections, `ORDER BY`/`LIMIT`, `JOIN`, ...)
- Merge and deletion bugs that only appear when several devices write concurrently
- Hanging tests from a shared or doubly opened persistence directory

## Workflow

```
Adding tests to a Ditto app:
- [ ] 1. Put Ditto behind a repository or service interface; unit-test UI and business logic with a mock
- [ ] 2. Add the local store helper (local-store-test-helper in examples/<sdk>/), with the app's system parameters and its index setup
- [ ] 3. Run every app DQL statement through EXPLAIN; assert index scans for hot queries
- [ ] 4. Test filters with the flag true, false, null, and missing
- [ ] 5. Test merge-sensitive writes (map keys kept, no-op re-upserts, object replacement)
- [ ] 6. Test deletion counts with the result's mutated document IDs
- [ ] 7. Test observer delivery and cleanup; register every app subscription
- [ ] 8. With an offline license token, add multi-peer tests for concurrent edits and deletions
- [ ] 9. Keep a few tests on real devices for transports, permissions, and clocks
```

Test layers (`§ Testing Strategies`):

| Layer | Covers | Ditto instance | License or server |
|---|---|---|---|
| Unit tests with a mock | UI and business logic behind your repository interface | None (mock your own interface) | No |
| Local store tests | Your DQL statements, write shapes, soft-delete filters, observer and subscription lifecycle | Real, small-peers-only, sync never started | No |
| Multi-peer tests in one process | Concurrent edits and merges, deletion propagation, relay, attachments across peers | Several real instances syncing over TCP on localhost | An offline license token |
| Tests on real devices | Transports (Bluetooth LE, P2P Wi-Fi, LAN), permissions, Ditto Server, real clocks | Your app on devices | An offline license token, or a Ditto Server test database |

## Rules

### 1. Give every test its own local store, and never start sync in it (CRITICAL)

Many problems in Ditto apps come from the data model and the queries, and are cheap to catch against a **real local store** on one device. Open a small-peers-only instance (the default connection mode) in a fresh temporary persistence directory per test, and close it when the test ends, also when it fails. **Note (SDK 5.2.0):** in Flutter, close the test stores after the last test of the file instead: a process that closed one store per test, each with a subscription or a transaction, stopped at a later `Ditto.open()` (`§ A local-store test helper in Flutter`). The local store works without a license, so such tests need no token and no network and can run in CI.

**✅ DO**:
- Use one helper (`local-store-test-helper` in `examples/<sdk>/`): temporary directory, cleanup that closes Ditto and deletes the directory, the app's system parameters, and its index setup.
- Use the same system parameters (for example `DQL_STRICT_MODE`) as the app, through the system parameters of `DittoConfig` (SDK 5.2+; on 5.1, `ALTER SYSTEM` after opening), and the same indexes; system parameters change how statements behave and are not persisted.

**❌ DON'T**:
- Share one persistence directory between tests or open it twice. **Note (SDK 5.1.0):** in Flutter, a second open of an open directory never completed (5.2.0 fails after about a second).
- Start sync in local store tests. It is not needed, and in small-peers-only mode it throws until a valid offline license token is set.

`§ Testing Strategies`, `§ A Test Helper for a Local Store`, `§ Initializing Ditto`, `§ One instance per persistence directory`, `§ Applying System Parameters` · Helper: `local-store-test-helper` in `examples/<sdk>/`, [reference/test-helpers.md](reference/test-helpers.md)

### 2. Run Ditto tests where the SDK runs (CRITICAL)

A real `Ditto` instance needs the SDK's native library, so tests that open Ditto run where the SDK runs; tests that only use a mock of your own interface run anywhere.

| SDK | Where tests that open Ditto run |
|---|---|
| Flutter | `integration_test` on a desktop or device target (`flutter test integration_test/orders_test.dart -d macos`) |
| JavaScript | Node.js (or the browser the app targets) |
| Kotlin | Android instrumented tests on an emulator or device |
| Swift | Swift Testing or XCTest on macOS or an iOS simulator |

In-memory stores (Flutter Web, the JavaScript SDK in browsers) do not support indexes, so skip index assertions there. `§ A Test Helper for a Local Store`, `§ Requirements`, *Testing in <SDK>* on the SDK page

### 3. Test your code, not the SDK (HIGH)

**✅ DO**: Keep Ditto behind a repository or service interface so UI and business logic can be unit-tested with a mock. In Ditto tests, call your app's repository functions (not inline copies of the statements), so a test fails when the app code changes.
**❌ DON'T**: Write tests that only re-check SDK behavior. Test your own repository functions, data model, and business rules.

`§ Testing Strategies`, `§ A Test Helper for a Local Store`

### 4. Test filters with every flag state, including MISSING and NULL (CRITICAL)

Deletion logic fails silently: a filter that excludes documents without the flag. Insert documents with the flag `true`, `false`, `null`, and missing, and assert exactly which ones the query returns.

```sql
-- Rows: {"_id": "deleted", "isDeleted": true}, {"_id": "active", "isDeleted": false},
-- {"_id": "nullFlag", "isDeleted": null}, {"_id": "noFlag"}
-- Expected: active, noFlag, nullFlag
SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id
```

`§ Testing Deletion and Soft Delete`, `§ Soft Delete`, `§ MISSING and NULL` · Example: [reference/local-store-tests.md](reference/local-store-tests.md#testing-deletion-and-soft-delete), `local-store-tests` in `examples/<sdk>/`

### 5. Assert how many documents a DELETE or EVICT removed (CRITICAL)

A deletion statement can complete without removing anything. Assert the result's mutated document IDs and the remaining rows. This also catches SDK 5.1.0, where `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) removes nothing (`§ Known Issues in SDK 5.1.0`). Run the same tests on every SDK release that devices in the field use.

**✅ DO**: run `DELETE FROM orders WHERE _id IN :ids` with two IDs, then assert two mutated document IDs.
**❌ DON'T**: Assume a statement that did not throw removed the documents.

Tombstone expiry, husk documents, and "zombie data" from devices offline longer than the tombstone TTL involve several peers; cover them in multi-peer tests (rule 10). `§ Testing Deletion and Soft Delete`, `§ DELETE and Tombstones`, `§ Known Issues in SDK 5.1.0`

### 6. Test the write shape of merge-sensitive writes (HIGH)

One device cannot reproduce a concurrent merge, but it can verify that your code produces the write shape that merges well: field-level updates instead of whole-document rewrites, maps keyed by ID instead of arrays, and upserts that skip unchanged values. Assert the local semantics your code relies on, so a refactoring that switches to a whole-document write or an array is caught.

**✅ DO** assert that:
- Adding a line item with `INSERT ... ON ID CONFLICT DO UPDATE_LOCAL_DIFF` of a partial document keeps the existing items, and `items` is a map, not an array.
- Re-upserting unchanged data with `DO UPDATE_LOCAL_DIFF` returns no mutated document IDs.
- A function that replaces an object (`UNSET` then `SET` in one transaction) removes keys that are not in the new object; a plain `SET` would keep them, because objects merge under the default settings.
- Statements use the same type declarations (`REGISTER`, `COUNTER`, `ATTACHMENT`) and strict mode setting as the app; mixed declarations produce results that look like data loss.

`§ Testing Merge-Sensitive Writes`, `§ CRDT Types and Merge Behavior`, `§ Arrays and Maps`, `§ Keep type declarations consistent` · Examples: [reference/local-store-tests.md](reference/local-store-tests.md#testing-merge-sensitive-writes)

### 7. Validate every app statement with EXPLAIN (HIGH)

Keep the app's DQL statements as constants in one place (for example a repository class) and run each through `EXPLAIN` with representative arguments. `EXPLAIN` parses and plans without executing, so the test catches syntax errors and statements that cannot be planned without touching data.

**✅ DO**: For hot queries, create the indexes with the app's startup code and assert that the plan contains `indexScan`:

```sql
-- Expected: the plan contains "indexScan"
-- Arguments: {"status": "open"}
EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC
```

A later change to the query or to strict mode (which disables index scans in 5.1.0 and 5.2.0) then fails the test. During development, `ADVISE` (SDK 5.1+) suggests the indexes these statements need.

`§ Validating DQL in Tests`, `§ EXPLAIN and PROFILE`, `§ Strict Mode`, `§ ADVISE (SDK 5.1+)` · Example: [reference/local-store-tests.md](reference/local-store-tests.md#validating-dql-in-tests)

### 8. Test observer delivery and cleanup (HIGH)

Test that observers deliver updates, and that your cleanup code releases them: run the screen's cleanup, then assert that the observer reports itself as cancelled (in Flutter, cancel both the stream subscription and the observer).

**✅ DO**: Wait for a specific result with a timeout (for example 5 seconds).
**❌ DON'T**: Use a fixed delay, or assert on the number of callbacks; it is not guaranteed.

For UI tests of screens that own observers, keep the observer behind your own interface and inject a stream or fake you control. The differs only accept items produced by Ditto, so code that uses one needs a real store.

`§ Testing Observer Lifecycle`, `§ Observer Lifecycle`, `§ Diffing Results` · Example: [reference/local-store-tests.md](reference/local-store-tests.md#testing-observer-lifecycle)

### 9. Register every app subscription in a test (HIGH)

`registerSubscription` validates the query when it is called, even before sync starts. It fails for projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, `USE IDS`, and (while `DQL_RESTRICT_SUBSCRIPTIONS` has its default `true`) `ORDER BY` and `LIMIT`. `WHERE` filters are allowed.

**✅ DO**: Register the app's real subscriptions, then cancel them and assert that they are cancelled; this catches invalid subscription queries without a network. Optionally assert that forbidden forms fail to register:

<!-- subscription expect-error -->
```sql
-- Expected: registering this subscription fails
SELECT _id, status FROM orders
```

`§ Testing Subscription Rules`, `§ Subscription Rules` · Examples: [reference/local-store-tests.md](reference/local-store-tests.md#testing-subscription-rules)

### 10. Test merges with several peers in one process (HIGH)

Concurrent edits, merges, deletion propagation, multi-hop relay, and attachment fetching across peers need sync between real instances. Most of these tests do not need physical devices: several instances in one test process can sync over TCP on `127.0.0.1`.

- Each peer has its own persistence directory; all peers of a group share one Database ID. Give each group in a test, and each test process that can run at the same time, its own port and Database ID: a second hub listened on a port already in use without an error, and reconnecting clients moved to it and mixed the groups (SDK 5.1.0 and 5.2.0).
- Disable peer-to-peer transports; peer 0 listens on `127.0.0.1`, the others connect to it (and listen on `127.0.0.1` only).
- Small-peers-only sync needs an **offline license token**: starting sync fails until `setOfflineOnlyLicenseToken` has set a valid token. Without one, tests are limited to a single local store.
- **✅ DO**: Make the concurrent writes while the peers are disconnected (stop sync on every peer, write, reconnect), then wait with a timeout until every peer returns the same rows.
- **❌ DON'T**: Write while the peers are connected and call it a merge test; the writes reach the other peers within milliseconds.
- A listening peer accepted at most 6 TCP connections by default in testing with SDK 5.1.0 and 5.2.0 (`MESH_CHOOSER_MAX_WLAN_CONNECTIONS`), so keep the peer count at 7 or below. The Flutter multi-peer test file was verified with `ditto_live` 5.1.0 and has not yet been run with 5.2.0. For a relay test, chain the peers: A listens, B listens and connects to A, C connects to B.

`§ Testing on Multiple Devices`, `§ Several peers in one test process`, `§ Transport Configuration` · Helpers and test: `multi-peer-test` in `examples/<sdk>/`, [reference/multi-peer-tests.md](reference/multi-peer-tests.md)

### 11. Keep what one process cannot simulate on real devices (MEDIUM)

The in-process setup shares one clock (no clock skew) and exercises only TCP. Bluetooth LE, P2P Wi-Fi, LAN discovery, permissions, app lifecycle, and Bluetooth LE as the only transport need real devices.

- **Sync through Ditto Server** needs a Ditto Server test database. Use separate databases (apps) for development, staging, and production, or one per developer; developers who share one can prefix collection names. There is no Ditto Server mock for CI.
- **Offline scenarios:** to simulate a Ditto Server outage while keeping peer-to-peer sync, let the app authenticate first, then block the Ditto Server host at the network level; blocking it before authentication makes sync fail entirely.

Scenarios worth covering: different fields and the same field edited offline on two devices; map (and, for comparison, array) entries added, edited, and removed on two devices; delete racing an update (expect a husk document), also with soft delete; a counter recounted with `RESTART WITH` while another device increments it; a device behind a relay with narrower subscriptions; a soft delete that reaches a device only through a relay; attachments created offline and fetched later.

`§ Testing on Multiple Devices`, `§ Husk documents`, `§ RESTART`, `§ Multi-hop relay`, `§ Availability` · [reference/multi-peer-tests.md](reference/multi-peer-tests.md#several-peers-in-one-test-process)

### 12. Keep license tokens out of source control (MEDIUM)

Pass the offline license token to tests from a CI secret, for example an environment variable or, in Flutter, `--dart-define-from-file=license.json` with an uncommitted `license.json`. Skip multi-peer tests when the token is empty, so local store tests still run in CI without it.

`§ Testing on Multiple Devices`, `§ Several peers in one test process`

## Checklist

- [ ] Ditto is behind a repository interface; UI and business logic tests use a mock
- [ ] Each Ditto test opens its own temporary persistence directory and closes it when the test ends (Flutter 5.2.0: after the file's last test)
- [ ] Local store tests never start sync
- [ ] Tests apply the app's system parameters and indexes
- [ ] Ditto tests run where the SDK runs (Flutter `integration_test`, Node.js, instrumented tests, Swift Testing or XCTest)
- [ ] Every app statement passes `EXPLAIN`; hot queries assert `indexScan`
- [ ] Filters are tested with the flag `true`, `false`, `null`, and missing
- [ ] Deletions assert the mutated document IDs and the remaining rows
- [ ] Merge-sensitive writes assert map shape, no-op re-upserts, and object replacement
- [ ] Observer tests wait with a timeout and assert that cleanup released the observer
- [ ] Every app subscription is registered and cancelled in a test
- [ ] Multi-peer tests write while disconnected and wait for convergence
- [ ] The license token comes from a CI secret; tests skip without it
- [ ] Transports, permissions, and clock skew are covered on real devices

## More

- Reference: [reference/test-helpers.md](reference/test-helpers.md) - what the local store helper does, and where tests run
- Reference: [reference/local-store-tests.md](reference/local-store-tests.md) - tests for merge-sensitive writes, deletion and soft delete, observers, subscriptions, and `EXPLAIN`, as statements and expected results
- Reference: [reference/multi-peer-tests.md](reference/multi-peer-tests.md) - multi-peer helpers, a concurrent-edit test, limits, and scenarios
- Examples: `examples/<sdk>/` - `local-store-test-helper`, `local-store-tests`, `multi-peer-test`
- Related skills: `query-sync` (DQL, MISSING vs NULL, subscription rules, observers), `data-modeling` (merge behavior, maps vs arrays, type declarations), `storage-lifecycle` (DELETE, soft delete, EVICT, tombstones), `sdk-setup` (DittoConfig, license token, transports), `audit` (reviewing a Ditto codebase)
