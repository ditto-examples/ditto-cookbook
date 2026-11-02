# Upgrading from SDK 5.1

To upgrade, change the dependency to 5.2.0; most apps need no code changes. SDK 5.2 syncs with devices on earlier 5.x releases, so you can roll it out gradually. While you do, some devices still run 5.1.0, and the [known issues of that release](#known-issues-in-sdk-510) apply to them.

## Changes in SDK 5.2.0

Review these changes when you upgrade:

- **System parameters** can be passed in `DittoConfig.systemParameters`, which applies them before Ditto starts and makes `Ditto.open()` fail on an unknown name or a wrong type. Move the settings your app applies with `ALTER SYSTEM` after every open into the configuration (see [Applying System Parameters](../best-practices/setup-and-lifecycle.md#applying-system-parameters)).
- **`DQL_REQUEST_HISTORY_SIZE`** defaults to 128 entries instead of 4096. Set it explicitly if your diagnostics read more of `system:request_history`.
- **Flutter persistence directory**: the default root directory moves to the application support directory. With `persistenceDirectory: null`, existing data is still found; with a relative path, check that upgraded installations still open their data (see [DittoConfig](../best-practices/setup-and-lifecycle.md#dittoconfig)).
- **Oversized documents**: according to the release notes, a device drops a replication diff that would push a document over the hard size limit, and lists the document in `system:sync_degradations` (see [Document Size Limits](../best-practices/data-modeling.md#document-size-limits)).
- **Observers on virtual collections** fire when the data changes instead of on a timer, for most collections. Code that relied on periodic callbacks should query on its own schedule. Observers on `system:system_info` still fire often (see [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage)).
- **SQLite write-ahead log**: the size monitor and the automatic reclaim of free space are on by default (see [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage)).
- **Android permissions**: `DittoSyncPermissions.requiredPermissions()` no longer includes the permissions for multicast (see [Multicast (Beta) (SDK 5.1+)](../best-practices/setup-and-lifecycle.md#multicast-beta-sdk-51)).
- **Kotlin**: `newAttachment` overloads that take `Map<String, Any?>` metadata are deprecated and throw `IllegalArgumentException` for values that are not strings; use the `Map<String, String>` overloads.
- **Data Streams**: if you set `NGN_SYNC_ENABLED`, also set `NGN_DATA_STREAMS_ENABLED`; otherwise `ditto.sync.start()` now fails with a configuration error.
- **New features** that this guide describes: [support bundles](../best-practices/logging-and-observability.md#support-bundles-sdk-52), `system:sync_degradations` and new metrics ([System Virtual Collections](system-reference.md#system-virtual-collections)), WAL values in [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage), `ditto.store.observers` ([Resource Cleanup and Shutdown](../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown)), `logout(cleanup:)` ([Authentication](../best-practices/setup-and-lifecycle.md#authentication)), and encryption at rest for Swift and Kotlin ([Data at Rest](../best-practices/security.md#data-at-rest)).

See the [release notes](https://docs.ditto.live/sdk/latest/release-notes/flutter) for the complete list.

## Known Issues in SDK 5.1.0

SDK 5.2.0 fixes the following issues of 5.1.0. They apply to every device that still runs 5.1.0. Items that say "in our testing" were reproduced with the JavaScript SDK 5.1.0 on Node.js and did not occur with 5.2.0; the others come from the 5.2.0 release notes.

**Wrong results without an error**

- **`DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate removes nothing.** This applies to `USE IDS 'a'`, `USE IDS LIST :ids`, and `USE IDS ... WHERE true`; the statement completes without an error and `mutatedDocumentIDs()` is empty (in our testing). Use `WHERE _id IN :ids`, which is planned as an ID scan and works on every release.
- **A composite index that mixes `ASC` and `DESC` keys returns results in the wrong order.** In our testing, with an index on `(status, createdAt DESC)`, `SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC` returned the oldest documents first, and with `LIMIT 2` it returned the two oldest; the plan had no sort step. A range condition on the second key (`createdAt >= :since`) behaved the same way. `ADVISE` suggests such indexes on 5.1.0 as well. On 5.1.0, define composite indexes with keys in one direction, such as `(status, createdAt)`: the planner then adds a sort step, and the order is correct.
- **`ORDER BY` on projected fields can be ignored in index plans.** In our testing, with an index on `(status, createdAt)`, `SELECT _id, createdAt FROM orders WHERE status = :status ORDER BY createdAt DESC` returned the rows in insertion order, while `SELECT *` sorted them correctly. Use `SELECT *` for sorted queries that use an index, or sort in your code.
- **`ANY ... SATISFIES` with a condition on several properties matches every document.** In our testing, `WHERE ANY car IN cars SATISFIES car.color = 'blue' AND car.type = 'SUV' END` matched all three test documents instead of one, so the same condition in an `UPDATE` or `DELETE` changes every document. The same expression in a projection returned the correct value. Do not use such conditions in `WHERE` on 5.1.0; select the candidates and test the condition in a projection or in your code.
- **A comparison with the constant on the left can return wrong results through an index.** In our testing, with an index on `a`, `WHERE 1 < a` returned no documents and `WHERE 2 >= a` returned one, instead of two and three. Write the field on the left (`a > 1`).
- **Values stored incorrectly by some SDKs.** Kotlin and Java stored and compared negative integers passed in map arguments as one less (`-5` as `-6`). Swift stored booleans created with `JSONSerialization` as `0` and `1`. C# decoded unsigned integers above `Int64.MaxValue` as `null`. Upgrading does not correct data that was already written: find and fix the affected values.

**Failures and hangs**

- `INSERT` into an indexed collection that was empty before an SDK upgrade fails.
- `SELECT` statements with long `AND` or `OR` chains in `WHERE` can crash the app. Use `IN :values` for long lists of alternatives.
- Observers can stall when many are active at the same time.
- In rare cases, completing a write transaction could hang or cancel another write transaction in progress.
- A fetch of an attachment that no document references anymore retries forever instead of ending; keep a stall timeout (see [Fetching Attachments](../best-practices/attachments.md#fetching-attachments)).
- Peers that authenticate right after a certificate revocation is created are rejected, although a revocation should apply only to certificates issued before it (see [Certificate Revocation (SDK 5.1+)](../best-practices/security.md#certificate-revocation-sdk-51)).
- Flutter: hot restarting an app while a store observer is active during sync can crash it, and `Ditto.open()` can crash on 32-bit Android devices that report the `armv8l` architecture.

## Rolling Back

SDK 5.2 does not change the on-disk store format, so an app can go back from 5.2 to 5.1 without special steps. To go back to 5.0 or v4, go through SDK 5.0.2 or later (or 4.14.6 or later), which convert the 5.1 index format back (see [Upgrading and downgrading](../best-practices/indexing-and-performance.md#upgrading-and-downgrading)). As with any upgrade, test the procedure with representative application data before you deploy it.
