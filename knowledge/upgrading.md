# Upgrading from SDK 5.1

To upgrade, change the dependency to 5.2.0; most apps need no code changes. SDK 5.2 syncs with devices on earlier 5.x releases, so you can roll it out gradually. While you do, some devices still run 5.1.0, and the [known issues of that release](#known-issues-in-sdk-510) apply to them.

In our testing, peers on 5.1.0 and 5.2.0, and on 5.0.3 and 5.2.0, synced in both directions, merged concurrent edits to the same documents, and fetched attachments from each other; each peer saw the other's `dittoSdkVersion` in its presence graph, which helps to find the devices that still run an older release (see [Mixed Releases and Migration in Our Testing](#mixed-releases-and-migration-in-our-testing)).

One result differs while releases are mixed: a merge that pushes a document over the hard size limit ends differently on each release (see [An oversized merge ends differently on each release](#an-oversized-merge-ends-differently-on-each-release)). The protection is the same on every release: keep documents far below the limit (see [Document Size Limits](../best-practices/data-modeling.md#document-size-limits)).

Devices on 5.0.3 also could not read a collection that held a document 30 or more levels deep, also when the document had arrived through sync from a device on a later release (see [Very deep documents end a peer's process during sync](documents-and-limits.md#very-deep-documents-end-a-peers-process-during-sync)). Keep nesting shallow (see [Flat or nested](../best-practices/data-modeling.md#flat-or-nested)).

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
- **`ANY ... SATISFIES` with a condition on several properties matches every document.** In our testing, `WHERE ANY car IN cars SATISFIES car.color = 'blue' AND car.type = 'SUV' END` matched all three test documents instead of one, so the same condition in an `UPDATE` or `DELETE` changes every document. The same expression in a projection returned the correct value, and 5.0.3 returned the one document, so the issue came with 5.1.0. Do not use such conditions in `WHERE` on 5.1.0; select the candidates and test the condition in a projection or in your code.
- **A comparison with the constant on the left can return wrong results through an index.** In our testing, with an index on `a`, `WHERE 1 < a` returned no documents and `WHERE 2 >= a` returned one, instead of two and three; 5.0.3 had the same issue. Write the field on the left (`a > 1`).
- **Values stored incorrectly by some SDKs.** Kotlin and Java stored and compared negative integers passed in map arguments as one less (`-5` as `-6`). Swift stored booleans created with `JSONSerialization` as `0` and `1`. C# decoded unsigned integers above `Int64.MaxValue` as `null`. Upgrading does not correct data that was already written: find and fix the affected values.

**Failures and hangs**

- `INSERT` into an indexed collection that was empty before an upgrade from 5.0.x fails with `no such table: ___idx_coll_...`. In our testing, a store migrated by 5.1.0 kept failing after a later upgrade to 5.2.0, while a store upgraded from 5.0.3 directly to 5.2.0 worked; drop and re-create the index to repair it (see [Upgrading and downgrading](../best-practices/indexing-and-performance.md#upgrading-and-downgrading)).
- `SELECT` statements with long `AND` or `OR` chains in `WHERE` can crash the app. In our testing with the JavaScript SDK 5.1.0, 15,000 `OR` terms (or 20,000 `AND` terms) ended the process without an exception, while 10,000 worked; 5.2.0 handled 50,000. Devices with smaller thread stacks may fail with fewer terms. Use `IN :values` for long lists of alternatives.
- Observers can stall when many are active at the same time. In our testing with the JavaScript SDK on one Mac, with 60 or more store observers on 5.1.0 (35 or more on 5.0.3), a change no longer reached any callback, and the error appeared only in the log (`BeginTransactionTimeout`); cancelling most of them did not recover the others. On 5.2.0, 1,000 observers worked. The threshold may differ on other devices. While devices still run 5.1.0, do not register one observer per row of a list.
- In rare cases, completing a write transaction could hang or cancel another write transaction in progress.
- A fetch of an attachment that no document references anymore retries forever instead of ending. The 5.2.0 release notes list this as fixed, but in our testing such fetches stayed pending on 5.2.0 as well; keep a stall timeout on both releases (see [Fetching Attachments](../best-practices/attachments.md#fetching-attachments)).
- Peers that authenticate right after a certificate revocation is created are rejected, although a revocation should apply only to certificates issued before it (see [Certificate Revocation (SDK 5.1+)](../best-practices/security.md#certificate-revocation-sdk-51)).
- Flutter: hot restarting an app while a store observer is active during sync can crash it, and `Ditto.open()` can crash on 32-bit Android devices that report the `armv8l` architecture.

## Mixed Releases and Migration in Our Testing

The observations behind the mixed-release results at the top of this page, and behind the migration issue in [Known Issues in SDK 5.1.0](#known-issues-in-sdk-510). How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md).

### Peers on different releases merged to the same documents

| | |
|---|---|
| Observed on | Three pairs of releases, one run each: 5.2.0 with 5.1.0, 5.1.0 with 5.2.0 (the same two releases in the other order), and 5.0.3 with 5.2.0 |
| Setup | Two peers on different releases, each in its own process. They made the concurrent edits of the 22 rows of [What concurrent edits produce](crdt-types.md#what-concurrent-edits-produce) that statements alone can reproduce, including counters, `RESTART`, husks, and `INITIAL DOCUMENTS`, and fetched a 200 KB attachment in both directions |
| Documentation | According to the release notes, SDK 5.1 and 5.2 sync with each other |

- In every pair, all 22 rows gave the results that the table describes, and both peers held the same documents.
- The 200 KB attachment could be fetched in both directions, and its hash matched.

**Used in:** [Upgrading from SDK 5.1](#upgrading-from-sdk-51).

### An oversized merge ends differently on each release

| | |
|---|---|
| Observed on | The same three pairs of releases as in the previous entry, one run each |
| Setup | Two peers on different releases, each in its own process. Each peer added 3 MiB to the same document, so that the merged document would be 6 MiB, over the hard size limit of 5 MiB |

- **5.1.0 and 5.2.0**: the 5.1.0 peer held the 6 MiB document that combined both 3 MiB parts, and a later `UPDATE` of it failed. The 5.2.0 peer kept only its own part and listed the document in `system:sync_degradations` with `documentTooBig`.
- **5.0.3 and 5.2.0**: the 5.0.3 peer held the 6 MiB document, and **a later `UPDATE` of it succeeded**. 5.0.3 does not check the hard limit when a document is written (see [SDK 5.0.3 differs in the size limit, constant comparisons, and defaults](dql-behavior.md#sdk-503-differs-in-the-size-limit-constant-comparisons-and-defaults)).

**Used in:** [Upgrading from SDK 5.1](#upgrading-from-sdk-51).

### Presence shows each peer's SDK version

| | |
|---|---|
| Observed on | Three pairs of releases, one run each: 5.0.3 with 5.2.0, 5.1.0 with 5.2.0, and 5.2.0 with 5.1.0 |
| Setup | Two peers on different releases, each in its own process, each with peer metadata set. We read the other peer in each peer's presence graph |

- In every pair, the presence graph showed the other peer's `dittoSdkVersion` (`5.0.3`, `5.1.0`, or `5.2.0`), `os`, and `isCompatible` (`true`), and the peer metadata that the other peer had set arrived.
- During a rollout, `dittoSdkVersion` therefore identifies the devices that still run an older release.

**Used in:** [Presence](../best-practices/setup-and-lifecycle.md#presence), [Upgrading from SDK 5.1](#upgrading-from-sdk-51).

### An index created on an empty collection breaks in the 5.1.0 migration

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs; every run gave the same result. The repair by dropping and re-creating the index, and the 5.0.3 `SELECT _id` result in the last item: one run |
| Setup | Each release ran in its own process. One persistence directory was opened on 5.0.3, 5.1.0, 5.2.0, 5.1.0, 5.0.3, and 5.2.0, in that order, and another one on 5.0.3 and then on 5.2.0. On 5.0.3, an index `idx_empty` was created on an empty collection `emptyc`, and another collection held documents and an index. A composite index was created on 5.2.0 |
| Documentation | The 5.2.0 release notes list as fixed (CCB-88) that an `INSERT` into an indexed collection that was empty before the upgrade failed |

- After the index on the empty collection `emptyc` was created on 5.0.3 and the directory was closed and opened on 5.1.0, an `INSERT` into that collection failed with `no such table: ___idx_coll_...`. Opened next on 5.2.0, and then again on 5.1.0, the same `INSERT` still failed. The collection that held documents kept its indexes and documents on every release.
- In the directory opened on 5.0.3 and then directly on 5.2.0, the same `INSERT` succeeded: the fix of CCB-88 works in the migration by 5.2.0. A directory that 5.1.0 has migrated once is not repaired by 5.2.0.
- In the broken directory, `DROP INDEX idx_empty ON emptyc` on 5.2.0 made the `INSERT` succeed, and it kept succeeding after the index was created again (one run). Opening and closing the directory on 5.0.3, and then opening it again on 5.2.0, also repaired it; this was also checked once with 5.0.3 only opening the directory, without writing. We think this is because going back to 5.0.3 returns the index to the 5.0 format, so that 5.2.0 migrates it again.
- Moving between 5.2.0 and 5.1.0, in both directions, kept the documents, the indexes, and the composite index created on 5.2.0 usable.
- Back on 5.0.3, the composite index `idx_status_n (status, n)` became two single-field indexes, `idx_status_n_status` and `idx_status_n_n`. All documents could be read, including those written on 5.1.0 and 5.2.0.
- A separate issue (one run): on 5.0.3, `SELECT _id FROM c` without `WHERE` on an indexed collection does not return the correct number of rows: 0 of 2 in a new store, and 1 of 5 in the directory that had moved between releases. The plan was an index scan and a `groupBy`. `SELECT *` and `COUNT(*)` returned the correct results, and so did 5.1.0 and 5.2.0. The same pattern appeared in [Rows with equal sort keys come back in _id order since SDK 5.1](dql-behavior.md#rows-with-equal-sort-keys-come-back-in-_id-order-since-sdk-51): there, the rows did not come back in `_id` order in any of the three runs, and in one run of a separate reproduction, the query returned a single row, `{}`, for 40 documents. In every case so far, the query returned at most one row.

**Used in:** [Upgrading and downgrading](../best-practices/indexing-and-performance.md#upgrading-and-downgrading), [Known Issues in SDK 5.1.0](#known-issues-in-sdk-510), [Rolling Back](#rolling-back).

## Rolling Back

SDK 5.2 does not change the on-disk store format, so an app can go back from 5.2 to 5.1 without special steps. To go back to 5.0 or v4, go through SDK 5.0.2 or later (or 4.14.6 or later), which convert the 5.1 index format back (see [Upgrading and downgrading](../best-practices/indexing-and-performance.md#upgrading-and-downgrading)). As with any upgrade, test the procedure with representative application data before you deploy it.
