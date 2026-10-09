---
name: testing
description: "Ditto SDK testing strategies: local-store test helper, tests for DQL statements, MISSING/NULL filters, merge-sensitive writes, soft delete, observer lifecycle, subscription rules, and multi-peer sync tests in one process. Use when writing or reviewing tests for code that uses Ditto, setting up a test harness, or reproducing a sync or merge bug."
---

# Ditto Testing Strategies

How to test code that uses Ditto: a real local store per test for DQL, write shapes, filters, and lifecycle, and several synced peers in one process for merges. Targets Ditto SDK 5.1.0; examples are Flutter (Dart).

## Before You Apply

- Check the project's Ditto SDK version (`ditto_live` in `pubspec.lock`, `@dittolive/ditto` in `package-lock.json`, `DittoSwift` in `Package.resolved`, `com.ditto` in Gradle files); these rules were verified with 5.1.0. **Note (SDK 5.1.0)** marks easy-to-miss 5.1.0 behavior (wrong results, lost data, crashes, hangs) and its safe pattern; on another version, confirm it (release notes, docs.ditto.live) first. **(SDK 5.1+)** marks features introduced in 5.1.
- Examples are Dart. For JavaScript, Swift, or Kotlin, translate with `§ Platform Differences` and do not port Flutter observer or transaction code one-to-one.
- `§ <Heading>` cites a section of the full guide: Grep the heading in `../guide/reference/ditto.md` and read it for the reasoning or a complete example.

## Prevents

- DQL statements that fail to parse or plan only at runtime, and hot queries that silently lose their index scan
- Soft-delete filters that hide documents where the flag is missing or null
- `DELETE`/`EVICT` statements that complete without removing anything (`USE IDS` without a `WHERE` predicate, SDK 5.1.0)
- Write shapes that merge badly (whole-document rewrites, arrays instead of maps, `SET` that keeps old map keys) introduced by a refactoring
- Upserts that rewrite unchanged data
- Observers and stream subscriptions that are never cancelled
- Subscription queries rejected at registration (projections, `ORDER BY`/`LIMIT`, `JOIN`, ...)
- Merge and deletion bugs that only appear when several devices write concurrently
- Hanging tests from a shared or doubly opened persistence directory

## Workflow

```
Adding tests to a Ditto app:
- [ ] 1. Put Ditto behind a repository or service interface; unit-test widgets and business logic with a mock
- [ ] 2. Add the local store helper (openTestDitto) under integration_test/, with configure = the app's startup setup
- [ ] 3. Run every app DQL statement through EXPLAIN; assert index scans for hot queries
- [ ] 4. Test filters with the flag true, false, null, and missing
- [ ] 5. Test merge-sensitive writes (map keys kept, no-op re-upserts, object replacement)
- [ ] 6. Test deletion counts with mutatedDocumentIDs()
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

Many problems in Ditto apps come from the data model and the queries, and are cheap to catch against a **real local store** on one device. Open a small-peers-only instance (the default `connect`, `DittoConfigConnectSmallPeersOnly()`) in a fresh temporary persistence directory per test, and close it in `tearDown`/`addTearDown`. The local store works without a license, so such tests need no token and no network and can run in CI.

**✅ DO**:
- Use the `openTestDitto` helper: temporary directory, `addTearDown` that closes Ditto and deletes the directory, optional `configure` callback.
- Apply the same system parameters (for example `DQL_STRICT_MODE`) and indexes as the app, through `configure`; system parameters change how statements behave and are not persisted.

**❌ DON'T**:
- Share one persistence directory between tests or open it twice. **Note (SDK 5.1.0):** in Flutter, a second `Ditto.open()` on an open directory may never complete.
- Call `ditto.sync.start()` in local store tests. It is not needed, and in small-peers-only mode it throws until a valid offline license token is set.

`§ Testing Strategies`, `§ A Test Helper for a Local Store`, `§ Initializing Ditto`, `§ One instance per persistence directory`, `§ Applying System Parameters` · Helper: [reference/test-helpers.md](reference/test-helpers.md)

### 2. Run Ditto tests with integration_test on a real target (CRITICAL)

A real `Ditto` instance needs the SDK's native library, which is packaged with the app build per platform. Run tests that open Ditto with the `integration_test` package on a supported desktop or device target; tests that only use a mock of your own interface run with plain `flutter test`.

```bash
flutter test integration_test/orders_test.dart -d macos
```

On Flutter Web the store is in memory and does not support indexes, so skip index assertions there. `§ A Test Helper for a Local Store`, `§ Requirements`

### 3. Test your code, not the SDK (HIGH)

**✅ DO**: Keep Ditto behind a repository or service interface so widgets and business logic can be unit-tested with a mock. In Ditto tests, call your app's repository functions (not inline copies of the statements), so a test fails when the app code changes.
**❌ DON'T**: Write tests that only re-check SDK behavior. Test your own repository functions, data model, and business rules.

`§ Testing Strategies`, `§ A Test Helper for a Local Store`

### 4. Test filters with every flag state, including MISSING and NULL (CRITICAL)

Deletion logic fails silently: a filter that excludes documents without the flag. Insert documents with the flag `true`, `false`, `null`, and missing, and assert exactly which ones the query returns.

```dart
// Rows: {isDeleted: true}, {isDeleted: false}, {isDeleted: null}, {} (no flag)
final result = await ditto.store.execute(
  'SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id',
);
expect(
  result.items.map((item) => item.value['_id']).toList(),
  ['active', 'noFlag', 'nullFlag'],
);
```

`§ Testing Deletion and Soft Delete`, `§ Soft Delete`, `§ MISSING and NULL` · Example: [reference/local-store-tests.md](reference/local-store-tests.md#deletion-and-soft-delete)

### 5. Assert how many documents a DELETE or EVICT removed (CRITICAL)

A deletion statement can complete without removing anything. Assert `mutatedDocumentIDs()` and the remaining rows. This also catches the **Note (SDK 5.1.0)** behavior where `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) removes nothing.

**✅ DO**: `DELETE FROM orders WHERE _id IN :ids`, then `expect(deleted.mutatedDocumentIDs(), hasLength(2))`.
**❌ DON'T**: Assume a statement that did not throw removed the documents.

Tombstone expiry, husk documents, and "zombie data" from devices offline longer than the tombstone TTL involve several peers; cover them in multi-peer tests (rule 10). `§ Testing Deletion and Soft Delete`, `§ DELETE and Tombstones`

### 6. Test the write shape of merge-sensitive writes (HIGH)

One device cannot reproduce a concurrent merge, but it can verify that your code produces the write shape that merges well: field-level updates instead of whole-document rewrites, maps keyed by ID instead of arrays, and upserts that skip unchanged values. Assert the local semantics your code relies on, so a refactoring that switches to a whole-document write or an array is caught.

**✅ DO** assert that:
- Adding a line item with `INSERT ... ON ID CONFLICT DO UPDATE_LOCAL_DIFF` of a partial document keeps the existing items, and `items` is a map, not an array.
- Re-upserting unchanged data with `DO UPDATE_LOCAL_DIFF` returns an empty `mutatedDocumentIDs()`.
- A function that replaces an object (`UNSET` then `SET` in one transaction) removes keys that are not in the new object; a plain `SET` would keep them, because objects merge under the default settings.
- Statements use the same type declarations (`REGISTER`, `COUNTER`, `ATTACHMENT`) and strict mode setting as the app; mixed declarations produce results that look like data loss.

`§ Testing Merge-Sensitive Writes`, `§ CRDT Types and Merge Behavior`, `§ Arrays and Maps`, `§ Keep type declarations consistent` · Examples: [reference/local-store-tests.md](reference/local-store-tests.md#merge-sensitive-writes)

### 7. Validate every app statement with EXPLAIN (HIGH)

Keep the app's DQL statements as constants in one place (for example a repository class) and run each through `EXPLAIN` with representative arguments. `EXPLAIN` parses and plans without executing, so the test catches syntax errors and statements that cannot be planned without touching data.

**✅ DO**: For hot queries, create the indexes with the app's startup code (the `configure` callback) and assert that the plan uses them:

```dart
final plan = await ditto.store.execute(
  'EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
  arguments: {'status': 'open'},
);
expect(jsonEncode(plan.items.first.value), contains('indexScan'));
```

A later change to the query or to strict mode (which disables index scans in 5.1.0) then fails the test. During development, `ADVISE` (SDK 5.1+) suggests the indexes these statements need.

`§ Validating DQL in Tests`, `§ EXPLAIN and PROFILE`, `§ Strict Mode`, `§ ADVISE (SDK 5.1+)` · Example: [reference/local-store-tests.md](reference/local-store-tests.md#validating-dql-with-explain)

### 8. Test observer delivery and cleanup (HIGH)

Test that observers deliver updates, and that your cleanup code cancels both the stream subscription and the observer (`await changes.cancel(); observer.cancel(); expect(observer.isCancelled, isTrue);`).

**✅ DO**: Wait for a specific result with a `Completer` and a timeout (`sawOrder.future.timeout(const Duration(seconds: 5))`).
**❌ DON'T**: Use a fixed delay, or assert on the number of callbacks; it is not guaranteed.

For widget tests of screens that own observers, keep the observer behind your own interface and inject a stream you control. `Differ` only accepts items produced by Ditto, so code that uses it needs a real store.

`§ Testing Observer Lifecycle`, `§ Observer lifecycle and cleanup`, `§ Diffing Results` · Example: [reference/local-store-tests.md](reference/local-store-tests.md#observer-lifecycle)

### 9. Register every app subscription in a test (HIGH)

`registerSubscription` validates the query when it is called, even before sync starts. It throws a `DittoException` for projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, `USE IDS`, and (while `DQL_RESTRICT_SUBSCRIPTIONS` has its default `true`) `ORDER BY` and `LIMIT`. `WHERE` filters are allowed.

**✅ DO**: Register the app's real subscriptions, then cancel them and assert `isCancelled`; this catches invalid subscription queries without a network. Optionally assert that forbidden forms throw:

<!-- expect-error -->
```dart
expect(
  () => ditto.sync.registerSubscription('SELECT _id, status FROM orders'),
  throwsA(isA<DittoException>()),
);
```

`§ Testing Subscription Rules`, `§ Subscription Rules` · Examples: [reference/local-store-tests.md](reference/local-store-tests.md#subscription-rules)

### 10. Test merges with several peers in one process (HIGH)

Concurrent edits, merges, deletion propagation, multi-hop relay, and attachment fetching across peers need sync between real instances. Most of these tests do not need physical devices: several instances in one `integration_test` process can sync over TCP on `127.0.0.1`.

- Each peer has its own persistence directory; all peers share one Database ID.
- Disable peer-to-peer transports (`config.setAllPeerToPeerEnabled(false)`); peer 0 listens on `127.0.0.1`, the others connect to it.
- Small-peers-only sync needs an **offline license token**: `ditto.sync.start()` throws until `ditto.setOfflineOnlyLicenseToken(token)` is called with a valid token. Without one, tests are limited to a single local store.
- **✅ DO**: Make the concurrent writes inside `whileDisconnected` (stop sync on every peer, write, reconnect), then `waitForConvergence` with a timeout until every peer returns the same rows.
- **❌ DON'T**: Write while the peers are connected and call it a merge test; the writes reach the other peers within milliseconds.
- A device accepts at most 6 TCP connections by default (SDK 5.1.0 default of `MESH_CHOOSER_MAX_WLAN_CONNECTIONS`), so keep the peer count at 7 or below. For a relay test, chain the peers: A listens, B listens and connects to A, C connects to B.

`§ Testing on Multiple Devices`, `§ Several peers in one test process`, `§ Transport Configuration` · Helpers and test: [reference/multi-peer-tests.md](reference/multi-peer-tests.md)

### 11. Keep what one process cannot simulate on real devices (MEDIUM)

The in-process setup shares one clock (no clock skew) and exercises only TCP. Bluetooth LE, P2P Wi-Fi, LAN discovery, permissions, app lifecycle, and Bluetooth LE as the only transport need real devices.

- **Sync through Ditto Server** needs a Ditto Server test database. Use separate databases (apps) for development, staging, and production, or one per developer; developers who share one can prefix collection names. There is no Ditto Server mock for CI.
- **Offline scenarios:** to simulate a Ditto Server outage while keeping peer-to-peer sync, let the app authenticate first, then block the Ditto Server host at the network level; blocking it before authentication makes sync fail entirely.

Scenarios worth covering: different fields and the same field edited offline on two devices; map (and, for comparison, array) entries added, edited, and removed on two devices; delete racing an update (expect a husk document), also with soft delete; a counter recounted with `RESTART WITH` while another device increments it; a device behind a relay with narrower subscriptions; attachments created offline and fetched later.

`§ Testing on Multiple Devices`, `§ Husk documents`, `§ RESTART`, `§ Multi-hop relay`, `§ Availability` · [reference/multi-peer-tests.md](reference/multi-peer-tests.md#scenarios-worth-covering)

### 12. Keep license tokens out of source control (MEDIUM)

Pass the offline license token to tests from a CI secret, for example `--dart-define-from-file=license.json` with an uncommitted `license.json` containing `{"DITTO_LICENSE_TOKEN": "..."}`, read with `String.fromEnvironment('DITTO_LICENSE_TOKEN')`. Skip multi-peer tests when the token is empty, so local store tests still run in CI without it.

`§ Testing on Multiple Devices`, `§ Several peers in one test process`

## Checklist

- [ ] Ditto is behind a repository interface; UI and business logic tests use a mock
- [ ] Each Ditto test opens its own temporary persistence directory and closes it in `addTearDown`
- [ ] Local store tests never call `ditto.sync.start()`
- [ ] Tests apply the app's system parameters and indexes (`configure`)
- [ ] Ditto tests run with `integration_test` on a desktop or device target
- [ ] Every app statement passes `EXPLAIN`; hot queries assert `indexScan`
- [ ] Filters are tested with the flag `true`, `false`, `null`, and missing
- [ ] Deletions assert `mutatedDocumentIDs()` and the remaining rows
- [ ] Merge-sensitive writes assert map shape, no-op re-upserts, and object replacement
- [ ] Observer tests wait with a timeout and assert cancellation of stream and observer
- [ ] Every app subscription is registered and cancelled in a test
- [ ] Multi-peer tests write inside `whileDisconnected` and wait for convergence
- [ ] The license token comes from a CI secret; tests skip without it
- [ ] Transports, permissions, and clock skew are covered on real devices

## More

- Reference: [reference/test-helpers.md](reference/test-helpers.md) - the `openTestDitto` helper, test file skeleton, and how to run the tests
- Reference: [reference/local-store-tests.md](reference/local-store-tests.md) - complete tests for merge-sensitive writes, deletion and soft delete, observers, subscriptions, and `EXPLAIN`
- Reference: [reference/multi-peer-tests.md](reference/multi-peer-tests.md) - `openSyncedPeers`, `whileDisconnected`, `waitForConvergence`, a concurrent-edit test, limits, and scenarios
- Related skills: `query-sync` (DQL, MISSING vs NULL, subscription rules, observers), `data-modeling` (merge behavior, maps vs arrays, type declarations), `storage-lifecycle` (DELETE, soft delete, EVICT, tombstones), `sdk-setup` (DittoConfig, license token, transports), `audit` (reviewing a Ditto codebase)
