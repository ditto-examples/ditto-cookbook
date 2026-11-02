# Deletion and Storage Management

Removing data from a database that syncs across an offline mesh is fundamentally different from removing a row in a central server database. There is no single place where a deletion "happens": every Small Peer holds its own copy, devices can be offline for days, and any device that still holds a document can share it again with peers that have already removed it.

Keep these properties in mind before choosing a removal strategy:

- **Deletions propagate like any other change.** A deletion only reaches a device when that device connects to a peer that knows about it.
- **Offline devices can reintroduce data.** A device that missed the deletion and reconnects later may still hold the old document and sync it back to the mesh.
- **Concurrent edits merge.** A delete on one device and an update on another are merged by the CRDT rules, not ordered by a central authority.
- **Local storage is finite.** Edge devices usually need only a subset of the data, so they must also be able to drop data locally without affecting anyone else.

Ditto offers three tools for these needs:

| Tool | What it does | Scope |
|---|---|---|
| `DELETE` | Removes the document's values and leaves a tombstone that propagates the deletion to other peers | Mesh-wide |
| Soft delete | An `UPDATE` that sets a flag such as `isDeleted`; queries filter flagged documents out | Mesh-wide (it is an ordinary update) |
| `EVICT` | Removes documents from the local store only; the removal is not propagated to other peers | This device only |

In deployments with a Ditto Server (formerly Big Peer), use `DELETE` for permanent removal (typically on the Ditto Server) and `EVICT` to manage storage on edge devices. If you plan to use `DELETE` in a deployment with Small Peers only, contact Ditto support to review the design. See [Choosing DELETE, Soft Delete, or EVICT](#choosing-delete-soft-delete-or-evict) for a decision table.

## DELETE and Tombstones

`DELETE` permanently removes documents from the user's perspective:

```sql
DELETE FROM orders WHERE _id = :orderId
```

What happens when a document is deleted:

- **The values are removed.** Ditto keeps a small *tombstone* that consists of the document ID, metadata such as the deletion time, and the field names the document had at the time of deletion. All values are removed. Tombstones are internal and cannot be queried.
- **The tombstone propagates.** Peers learn about the deletion through the tombstone. Tombstones are only shared with peers that have seen the document before it was deleted; a peer never receives a tombstone for a document it never knew about. As a consequence, in our testing, a device that never had the document accepted a stale copy from a device that had been offline and passed it on until it met a peer that held the tombstone (see [Soft delete, husk, eviction, and tombstone behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/storage-and-deletion.md#soft-delete-husk-eviction-and-tombstone-behavior-held-on-sdk-510-and-520)).
- **The document disappears locally at once.** After `DELETE`, the document no longer appears in `SELECT`, is not counted by `COUNT(*)`, and an `UPDATE` no longer matches it.
- **The ID can be reused.** A later `INSERT` with the same `_id` creates a new document; fields of the deleted document do not reappear. The exception is edits that another device made to the old document concurrently (for example, while offline): in our testing, those edits merged into the new document (see [Husk documents](#husk-documents), [A key added concurrently survives a later removal as null](../knowledge/observations/merge-behavior.md#a-key-added-concurrently-survives-a-later-removal-as-null), and [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)).

**✅ DO:**
- Target documents by ID with `WHERE _id = :id` or `WHERE _id IN :ids` (both are planned as an ID scan; see [Long ID lists are faster with USE IDS LIST than with WHERE _id IN](../knowledge/observations/performance-measurements.md#long-id-lists-are-faster-with-use-ids-list-than-with-where-_id-in)).
- Use `RETURNING` (SDK 5.1+) when you need the content of the deleted documents, for example for an undo message or an audit record.
- Make sure every device connects within the tombstone TTL (7 days by default; see [Tombstone TTL and reaping](#tombstone-ttl-and-reaping)), or use a soft delete instead.

**❌ DON'T:**
- Use `DELETE ... USE IDS ...` without a `WHERE` predicate while any device runs SDK 5.1.0, where it removes nothing (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510) and [On SDK 5.1.0, DELETE and EVICT with USE IDS and no WHERE predicate remove nothing](../knowledge/observations/dql-behavior.md#on-sdk-510-delete-and-evict-with-use-ids-and-no-where-predicate-remove-nothing)). Use `WHERE _id IN :ids`, which works on every release; it gets slower with long lists, so split more than about 1,000 IDs into chunks of 1,000 (see [USE IDS](dql.md#use-ids)).
- Use `DELETE` for data that is updated concurrently on other devices (see [Husk documents](#husk-documents)).
- Use `DELETE` to free space on one device; it removes the data for every peer. Use [EVICT](#evict) instead.

```dart
// ✅ GOOD: Delete several documents by ID and capture what was removed (SDK 5.1+).
Future<List<Map<String, dynamic>>> deleteOrders(
  Ditto ditto,
  List<String> orderIds,
) async {
  final result = await ditto.store.execute(
    'DELETE FROM orders WHERE _id IN :ids RETURNING _id, status, total',
    arguments: {'ids': orderIds},
  );
  // With RETURNING, each item holds the document as it was before deletion.
  return result.items.map((item) => item.value).toList();
}
```

```sql
-- ✅ GOOD: planned as an ID scan, deletes the listed documents on every SDK 5.x release
DELETE FROM orders WHERE _id IN :ids

-- Deletes the listed documents on SDK 5.2.0, nothing on SDK 5.1.0, and is a syntax error on SDK 5.0
DELETE FROM orders USE IDS LIST :ids
```

**Why:** The ID-based `WHERE` form is the reliable way to target specific documents for removal on every release (see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../knowledge/observations/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503)), and `RETURNING` is the only way to read a document's content after `DELETE`, because the tombstone keeps no values.

### Capturing deleted content with RETURNING (SDK 5.1+)

`RETURNING` on `DELETE` (and `EVICT`) returns the documents as they were **before** removal. Aggregates are allowed, which is convenient for counting:

```sql
DELETE FROM orders WHERE status = 'cancelled' AND createdAt < :cutoff RETURNING COUNT(*) AS removed
```

`mutatedDocumentIDs()` is still populated when `RETURNING` is used, but include `_id` in the `RETURNING` projection when you need the IDs. See [RETURNING (SDK 5.1+)](dql.md#returning-sdk-51) for the full syntax.

### Tombstone TTL and reaping

Tombstones do not live forever. Each device removes expired tombstones in a periodic process called *reaping*, controlled by these system parameters:

| System parameter | Default | Meaning |
|---|---|---|
| `TOMBSTONE_TTL_ENABLED` | `true` | Expired tombstones are removed automatically |
| `TOMBSTONE_TTL_HOURS` | `168` (7 days) | Age after which a tombstone is considered expired on this device |
| `DAYS_BETWEEN_REAPING` | `1` | Days between reaping runs, by the device clock. On a new store, the first run happens at a random time within the first 10 minutes after the instance starts (`REAPER_TIMING_RANDOM_VARIATION_SECONDS`, default 600); later runs happen at startup, or while the instance runs, once this many days have passed since the previous run |
| `TOMBSTONE_REAP_BATCH_SIZE` (SDK 5.1+) | `10000` | Expired tombstones are removed in bounded batches to limit peak memory |

```sql
SHOW ALL LIKE '%tombstone%'
```

Consequences for your design:

- **A device that is offline for longer than the TTL can resurrect deleted data.** If it reconnects after every other peer has already reaped the tombstone, nobody can tell it the document was deleted, and it shares its old copy again. This is known as "zombie data". In our testing with SDK 5.1.0 and 5.2.0, the deleted document came back on every device without an error or a warning; the only trace was the log line `Evicted ~1 tombstones from <collection> due to expired TTL` on the device that reaped (see [A device with an old copy resurrects a document after its tombstone is reaped](../knowledge/observations/storage-and-deletion.md#a-device-with-an-old-copy-resurrects-a-document-after-its-tombstone-is-reaped)).
- **The TTL is measured from the tombstone's timestamp,** which follows the deleting device's clock unless that device has just received newer changes from a peer (see [Clock drift](data-modeling.md#clock-drift)). A deletion by a device whose clock is ahead therefore expires later, and one by a device whose clock is behind expires earlier (in our testing; see [A device with an old copy resurrects a document after its tombstone is reaped](../knowledge/observations/storage-and-deletion.md#a-device-with-an-old-copy-resurrects-a-document-after-its-tombstone-is-reaped)).
- **Apps that run for short periods reap rarely.** The random delay before the first run is drawn again at every start, so an app that usually runs for less than 10 minutes reaps only at some of its starts; in our testing, six starts of 8 seconds each never reaped (see [A device with an old copy resurrects a document after its tombstone is reaped](../knowledge/observations/storage-and-deletion.md#a-device-with-an-old-copy-resurrects-a-document-after-its-tombstone-is-reaped)).
- **Very short TTLs can make deletions fail to propagate**, because the tombstone may expire before it reaches the other peers. (`TOMBSTONE_TTL_HOURS` accepts values from 1 hour; `ALTER SYSTEM` rejects 0.)
- **Never configure the Edge TTL (`TOMBSTONE_TTL_HOURS` on Small Peers) to exceed the Ditto Server TTL.** The Ditto Server always syncs documents, so a Small Peer tombstone that outlives the Ditto Server's own tombstone is sent back to the server repeatedly, which wastes resources. The Ditto Server tombstone TTL defaults to 30 days; changes to the server side go through Ditto support. <!-- lint-ignore -->

If devices can legitimately stay offline longer than 7 days, you can raise `TOMBSTONE_TTL_HOURS` (staying at or below the Ditto Server TTL), or prefer a soft delete for that data. System parameters are not persisted, so set the value on every open, in `DittoConfig.systemParameters` (SDK 5.2+) or with `ALTER SYSTEM` (see [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters)):

```dart
// Example: keep tombstones for 14 days on this device (must not exceed the
// Ditto Server TTL).
const config = DittoConfig(
  databaseID: 'YOUR_DATABASE_ID',
  connect: DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
  systemParameters: {'TOMBSTONE_TTL_HOURS': 336},
);
```

Reaping can be expensive on devices with very many tombstones. The parameters `ENABLE_REAPER_PREFERRED_HOUR_SCHEDULING` and `REAPER_PREFERRED_HOUR` schedule reaping during off-hours. Ditto reads them only at startup: `ALTER SYSTEM` accepts new values at runtime, but they are not applied. Set them through environment variables before the process starts, or, since SDK 5.2, in `DittoConfig.systemParameters` (see [DITTO_ environment variables set system parameters at startup](../knowledge/observations/configuration-and-diagnostics.md#ditto_-environment-variables-set-system-parameters-at-startup)). `REAPER_PREFERRED_HOUR` is an hour of the device's **local** time (0 to 23; 0 by default), and a device reaps only when it runs during that hour: in our testing with SDK 5.1.0 and 5.2.0, it checked at startup and then every hour after it had started, not at the start of that hour (see [Reaping at a preferred hour runs only at hourly checks within that hour](../knowledge/observations/storage-and-deletion.md#reaping-at-a-preferred-hour-runs-only-at-hourly-checks-within-that-hour)). A point-of-sale app that is closed at night and keeps the default hour 0 would never remove its tombstones. WASM-based platforms (JavaScript Web and Flutter Web) do not support these parameters. Contact Ditto support before relying on them.

### Husk documents

When one device deletes a document while another device concurrently updates it, the add-wins CRDT merges both operations field by field. The result is a *husk document*, and the document is **not** deleted. In SDK 5.1.0 and 5.2.0, the husk's shape depends on which operation was written first:

```text
Initial:            {"_id": "abc123", "color": "red", "make": "Toyota", "year": 2020}

Device A:           DELETE FROM cars WHERE _id = 'abc123'
Device B (offline, later): UPDATE cars SET color = 'blue' WHERE _id = 'abc123'
After merge:        {"_id": "abc123", "color": "blue"}      // make, year: MISSING

Device B (offline): UPDATE cars SET color = 'blue' WHERE _id = 'abc123'
Device A (later):   DELETE FROM cars WHERE _id = 'abc123'
After merge:        {"_id": "abc123", "color": null}        // make, year: MISSING
```

- **The document survives even when the DELETE is the later write.** In that case, the updated fields are `null` too, so the document is visible but holds no values.
- **Fields the update did not touch are MISSING, not `null`.** `make IS NULL` is `false` and `make IS MISSING` is `true`. The [deletion documentation](https://docs.ditto.live/sdk/latest/crud/delete) shows these fields as `null`, but SDK 5.1.0 leaves them missing; make code that reads husk documents handle both cases.
- Husks count in `SELECT COUNT(*)`, but a value filter such as `WHERE year >= 2000` excludes them.
- Running the `DELETE` again after the merge removes the husk on every device.

In our testing, these shapes were consistent for both orders of operations, regardless of which device issued the `DELETE` (see [A key added concurrently survives a later removal as null](../knowledge/observations/merge-behavior.md#a-key-added-concurrently-survives-a-later-removal-as-null) and [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)). Every point of the list above held on SDK 5.1.0 and 5.2.0 (see [Soft delete, husk, eviction, and tombstone behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/storage-and-deletion.md#soft-delete-husk-eviction-and-tombstone-behavior-held-on-sdk-510-and-520)).

> **Note (SDK 5.1.0 and 5.2.0):** A counter in a husk document is 0. In our testing, when one device deleted a stock document whose counter stood at 10 while another device added -3, the document came back as `{_id, cnt: 0}` in both orders, and `UNSET` of a map entry that held a counter left `{qty: 0}` the same way; with a soft-delete flag instead, the count was kept (see [Deleting a counter during a concurrent increment leaves a husk](../knowledge/observations/merge-behavior.md#deleting-a-counter-during-a-concurrent-increment-leaves-a-husk)). Remove documents and entries that hold counts, such as stock items, with a flag (see [Soft Delete](#soft-delete)).

A related effect can occur on a single device: inserting a document with `INITIAL DOCUMENTS` for an `_id` that was previously deleted can produce a document whose fields are all `null`, because the tombstone is newer than the "initial" data (see [Default Data with INITIAL Documents](data-modeling.md#default-data-with-initial-documents) for when this happens).

To avoid husk documents:

1. Use a [soft delete](#soft-delete) for data that may be edited concurrently.
2. Manage edge storage with [EVICT](#evict) and perform permanent deletion on the Ditto Server (for example through its HTTP API).
3. Coordinate your workflow so that the same document is not deleted and updated at the same time.

If husk documents are possible in your data, make your UI tolerate documents whose fields are `null` **or missing**. To keep husks out of lists, filter on a field that every live document has, and test for both cases: `WHERE make IS NOT MISSING AND make IS NOT NULL`. `IS NOT NULL` alone is `true` for a missing field (see [MISSING and NULL](dql.md#missing-and-null)). <!-- lint-ignore -->

### Deleting on the Ditto Server

`DELETE` statements sent through the Ditto Server HTTP API run as a single atomic operation. Delete in batches of 30,000 documents or fewer to avoid slowing down sync for connected devices:

```sql
DELETE FROM orders WHERE status = 'archived' LIMIT 30000
```

There is no `DROP COLLECTION` statement. `DELETE FROM orders` without a `WHERE` clause deletes every document in the collection, but the collection itself remains.

## Soft Delete

A soft delete marks a document as deleted with an ordinary `UPDATE` instead of removing it. Because the flag is just a field, it syncs like any other change and has none of the tombstone limitations:

- **No TTL dependency:** the flag stays on the document, so a device that was offline for weeks still learns that the document is deleted.
- **No husk documents:** a concurrent update merges with the flag instead of resurrecting a partially deleted document. In our testing, an edit made offline on another device was kept, and the document stayed flagged (see [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520) and [Deleting a counter during a concurrent increment leaves a husk](../knowledge/observations/merge-behavior.md#deleting-a-counter-during-a-concurrent-increment-leaves-a-husk)).
- **Recoverable:** setting the flag back to `false` restores the document. If one device soft-deletes a document while another restores it, the later write wins.

The trade-off is that soft-deleted documents still occupy storage and must be filtered out of every query, so you need a cleanup step (see [Soft delete, subscriptions, and cleanup](#soft-delete-subscriptions-and-cleanup)).

**✅ DO:**
- Set the flag and a timestamp in the same `UPDATE`: `isDeleted = true` and `deletedAt` as a UTC ISO-8601 string written by the same timestamp helper everywhere (see [Timestamps](data-modeling.md#timestamps)). Cleanup conditions such as `deletedAt < :cutoff` never match a flagged document that has no `deletedAt`.
- Write `isDeleted: false` when you create documents.
- Filter with `coalesce(isDeleted, false) = false`, which also matches documents where the field is missing or `null`.
- Keep soft-deleted documents in the subscriptions of devices that relay data to other devices, and filter them out in local queries and observers.

**❌ DON'T:**
- Filter with `isDeleted != true` or `NOT isDeleted`; both silently exclude documents where `isDeleted` is missing or `null`.
- Exclude soft-deleted documents from every subscription when devices sync through other Small Peers. A device that subscribes only to active documents cannot relay the flag for documents it did not already hold, and a cleanup `DELETE` does not reach it.

```dart
// ✅ GOOD: Soft delete, restore, and query helpers for an orders collection.
Future<void> softDeleteOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      // utcTimestamp() is defined in the Timestamps section; deletedAt is
      // compared with cleanup cutoffs, so it needs the fixed-precision helper.
      'deletedAt': utcTimestamp(),
    },
  );
}

Future<void> restoreOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = false UNSET deletedAt WHERE _id = :id',
    arguments: {'id': orderId},
  );
}

Future<List<Map<String, dynamic>>> activeOrders(Ditto ditto, String status) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE status = :status AND coalesce(isDeleted, false) = false '
    'ORDER BY createdAt DESC',
    arguments: {'status': status},
  );
  return result.items.map((item) => item.value).toList();
}
```

```sql
-- ❌ BAD: misses documents where isDeleted is missing or null
SELECT * FROM orders WHERE isDeleted != true

-- ✅ GOOD: treats missing and null as "not deleted"
SELECT * FROM orders WHERE coalesce(isDeleted, false) = false
```

**Why:** In DQL, a comparison with a missing or `null` field does not evaluate to `true`, so it never passes a `WHERE` clause. Which documents each soft-delete filter matches, when `isDeleted` is `true`, `false`, `null`, or missing:

| Filter | Matches |
|---|---|
| `isDeleted != true` | `false` only |
| `NOT isDeleted` | `false` only |
| `coalesce(isDeleted, false) = false` | `false`, `null`, missing |

See [MISSING and NULL](dql.md#missing-and-null) for the general rules.

### Indexing soft-delete filters

`coalesce(isDeleted, false) = false` applies a function to the field, so it cannot use an index on `isDeleted` by itself (the planner falls back to a collection scan). Alternatives:

| Approach | Plan |
|---|---|
| `coalesce(isDeleted, false) = false` alone | Collection scan |
| `status = :status AND coalesce(isDeleted, false) = false` with an index that starts with `status` | Index scan on `status`; the `coalesce` condition is applied as a filter |
| `(isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false)` with an index on `isDeleted` | Index scan (returns the same documents as the `coalesce` form) |
| `isDeleted = false` with an index on `isDeleted`, when every document is guaranteed to have the field | Index scan |

In our testing, every row of this table held on SDK 5.1.0 and 5.2.0 (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

Flagged documents cost query time until they are removed, while tombstones and evicted documents do not: in our testing with SDK 5.1.0 and 5.2.0, 49,000 flagged documents next to 1,000 live ones made `COUNT(*)` and filtered queries 15 to 20 times slower, and an index on `isDeleted` (with every document carrying the field) brought them back to the same speed (see [Tombstones and evicted documents do not slow queries, but flagged documents do](../knowledge/observations/storage-and-deletion.md#tombstones-and-evicted-documents-do-not-slow-queries-but-flagged-documents-do)).

In most screens, the soft-delete condition is combined with a more selective predicate (a status, a customer ID, a date range). Index that predicate, keep the `coalesce` form for correctness, and confirm the plan with [ADVISE](indexing-and-performance.md#advise-sdk-51) or [EXPLAIN](indexing-and-performance.md#explain-and-profile).

```sql
-- Index-friendly equivalent of coalesce(isDeleted, false) = false
SELECT * FROM orders
WHERE isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false
```

### Soft delete, subscriptions, and cleanup

The deletion flag is an ordinary update, but a subscription that excludes soft-deleted documents (for example `WHERE coalesce(isDeleted, false) = false`) changes which documents a device receives and stores. In our testing with SDK 5.1.0 and 5.2.0, a device with such a subscription received these changes to a document it already held (see [Soft delete, husk, eviction, and tombstone behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/storage-and-deletion.md#soft-delete-husk-eviction-and-tombstone-behavior-held-on-sdk-510-and-520)):

| Change made on another peer | Reached the device |
|---|---|
| The update that sets the flag | ✅ From any peer that held the flagged version, also after the device had been offline or restarted |
| Edits to the document while it is flagged | ❌ The device kept the copy as it was when it was flagged (a frozen copy; see [Multi-hop relay](sync-and-subscriptions.md#multi-hop-relay)) |
| A restore (`isDeleted = false`) | ✅ Together with the edits made while the document was flagged |
| A `DELETE` of the flagged document (cleanup) | ❌ The device kept the flagged copy until it evicted it |

Such a device does not receive soft-deleted documents that it did not already hold, for example because it joined the mesh later or evicted them, so it cannot pass the flag for those documents on to other devices. In our testing, a device that had missed the flag kept showing the document as active while it synced only with such a peer, until that peer subscribed to the whole collection or to a retention window. The relay itself is affected too: after it had evicted the flagged document, it received the old, unflagged version back from a device that had missed the flag (see [A relay that evicts flagged documents receives old versions back](../knowledge/observations/storage-and-deletion.md#a-relay-that-evicts-flagged-documents-receives-old-versions-back)). Keep in mind:

- A subscription filter does not hide documents in local results. Every local query and observer must filter flagged documents itself, for example with `coalesce(isDeleted, false) = false`.
- Cancelling or narrowing a subscription never deletes local data; only `DELETE` and `EVICT` remove documents.

Therefore, keep soft-deleted documents in the subscriptions of the devices that relay data to others, at least for as long as a device may stay offline. Two subscription designs meet this requirement; they differ in how soft-deleted documents are eventually removed:

| | Variant A: whole-collection subscription | Variant B: retention-window subscription |
|---|---|---|
| Subscription | Every document of the collection (or of the device's partition, such as one store), including soft-deleted ones | Active documents plus documents deleted within a retention window |
| Cleanup | A `DELETE` after the retention period, executed on the Ditto Server or by another authorized peer, that syncs to every device | Each device evicts documents deleted before the cutoff; the record stays on the Ditto Server until it is deleted there |
| Device-side `EVICT` of old soft-deleted documents | ❌ They still match the subscription and sync back | ✅ They are outside the subscription |
| Subscription changes | None | Re-registered when the cutoff moves (for example once a day) |
| Trade-offs | Simplest design. Soft-deleted documents use storage on every device until the `DELETE` runs, and the `DELETE` is subject to the tombstone rules (see [DELETE and Tombstones](#delete-and-tombstones)) | More moving parts. Choose a window longer than the longest expected offline period, so that other devices still hold the flagged document and can relay the flag when a device that missed it comes back |

**Variant A:** subscribe to the whole collection (here, one store's partition of it) and filter locally.

```dart
// ✅ GOOD (Variant A): The subscription (owned by a long-lived service such as
// OrderSync) includes soft-deleted orders; local queries hide them.
SyncSubscription subscribeToStoreOrders(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}

StoreObserver observeActiveOrders(Ditto ditto, String storeId) {
  // coalesce() treats a missing or null isDeleted field as false.
  return ditto.store.registerObserver(
    'SELECT * FROM orders '
    'WHERE storeId = :storeId AND coalesce(isDeleted, false) = false '
    'ORDER BY createdAt DESC',
    arguments: {'storeId': storeId},
  );
}
```

Cleanup then runs on the Ditto Server (for example through its HTTP API) once the retention period has passed and flagged documents are no longer edited (see [Husk documents](#husk-documents)):

```sql
DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000
```

**Variant B:** subscribe to active documents plus documents deleted within the retention window, and evict exactly the complement.

```dart
// ✅ GOOD (Variant B): A long-lived service keeps active orders and orders
// deleted within the retention window, and evicts older deleted orders.
class OrderSoftDeleteRetention {
  OrderSoftDeleteRetention(this.ditto, this.storeId);

  final Ditto ditto;
  final String storeId;

  /// Longer than the longest time a device is expected to stay offline.
  static const retention = Duration(days: 30);
  SyncSubscription? _subscription;

  // Same fixed-precision format as deletedAt (utcTimestamp() from "Timestamps").
  String _cutoff() => utcTimestamp(DateTime.now().subtract(retention));

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribe(_cutoff());
  }

  /// Call on a schedule, at most about once a day.
  Future<void> evictExpired() async {
    final cutoff = _cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();

    try {
      // 2. Evict only documents outside the new subscription.
      await ditto.store.execute(
        'EVICT FROM orders '
        'WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff',
        arguments: {'storeId': storeId, 'cutoff': cutoff},
      );
    } finally {
      // 3. Subscribe again with the moved boundary, even if the eviction failed.
      _subscription = _subscribe(cutoff);
    }
  }

  SyncSubscription _subscribe(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId '
        'AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)',
        arguments: {'storeId': storeId, 'cutoff': cutoff},
      );

  void dispose() => _subscription?.cancel();
}
```

**Why:** In Variant B, the eviction condition (`isDeleted = true AND deletedAt < :cutoff`) never matches a document that the new subscription covers, so evicted documents do not sync back. If an evicted document is restored later, it matches the subscription again and syncs back in its latest state. A flagged document without `deletedAt` matches neither condition, so it is never evicted and stays on the device as a frozen copy; set both fields in the same `UPDATE`. In Variant A, every soft-deleted document stays inside the subscription, so devices cannot evict them; the `DELETE` removes them everywhere instead. Because the cutoff is part of the Variant B subscription, move it only when you run cleanup, not on every screen change (see [Subscription Lifecycle](sync-and-subscriptions.md#subscription-lifecycle)).

**Subscribing to active documents only:** Ditto's [deletion documentation](https://docs.ditto.live/sdk/latest/crud/delete) also describes subscribing to documents that are not deleted and evicting the deleted ones. This is [flag-based eviction](#flag-based-eviction) with `isDeleted` as the flag: it needs no cutoff, and devices can evict flagged documents without re-registering the subscription. Use it only when every device syncs directly with a peer that subscribes to the whole collection, such as the Ditto Server. Devices with this subscription cannot relay the flag for documents they did not already hold, and a `DELETE` on the Ditto Server does not remove the flagged copies they hold, so each device must evict them itself.

## EVICT

`EVICT` removes documents from the **local** store only. It has the same shape as `DELETE`, including `WHERE`, `LIMIT`, and `RETURNING` (SDK 5.1+):

```sql
EVICT FROM orders WHERE createdAt < :cutoff
```

What eviction does and does not do:

- The documents are removed from this device immediately and disappear from local queries.
- The removal is not propagated to other peers and no tombstone is created. The documents remain on every other peer, including the Ditto Server. (Each eviction still triggers a resync with every connected peer; see the **Why** below.)
- The same `_id` can be inserted again later without a conflict. The new insert is not a new document across the mesh: in our testing with SDK 5.1.0 and 5.2.0, it merged with the copies that other peers still held, so fields from both appeared (see [Inserting with an evicted document's ID merges with the old version](../knowledge/observations/storage-and-deletion.md#inserting-with-an-evicted-documents-id-merges-with-the-old-version)). To start over without the old fields, use a new ID.
- **If an active subscription on this device still matches an evicted document, connected peers notice that it is missing and sync it back.** In our testing with SDK 5.1.0 and 5.2.0, such a document came back in about 0.26 seconds (see [Soft delete, husk, eviction, and tombstone behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/storage-and-deletion.md#soft-delete-husk-eviction-and-tombstone-behavior-held-on-sdk-510-and-520)). This can turn into a loop of evicting and re-syncing.

**✅ DO:**
- Cancel or narrow the affected subscriptions **before** evicting, and evict only documents that are outside the scope of every remaining subscription.
- Make the eviction query the complement of the subscription query (for example, subscribe to `createdAt >= :cutoff` and evict `createdAt < :cutoff` with the same cutoff value). Produce the timestamp with one fixed-precision helper (see [Timestamps](data-modeling.md#timestamps)).
- Run eviction on a schedule, at most about once per day, preferably at a quiet time.
- Evict by ID with `WHERE _id IN :ids`.

**❌ DON'T:**
- Evict documents and then register a subscription that matches them again (for example `SELECT * FROM orders`): the evicted data syncs straight back.
- Evict frequently (for example on every screen change).
- Use `EVICT ... USE IDS ...` without a `WHERE` clause while any device runs SDK 5.1.0, where it removes nothing (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)); use `WHERE _id IN :ids`.

```dart
// ❌ BAD: The new subscription matches the evicted documents again,
// so connected peers sync them straight back.
Future<SyncSubscription> evictAndResubscribeEverything(
  Ditto ditto,
  SyncSubscription subscription,
  String cutoff,
) async {
  subscription.cancel();
  await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt < :cutoff',
    arguments: {'cutoff': cutoff},
  );
  return ditto.sync.registerSubscription('SELECT * FROM orders');
}
```

**Why:** Each eviction triggers a resync with every connected peer, which costs network traffic and processing. If the subscription still covers the evicted documents, that resync simply sends them back, and you pay the cost without freeing any space (see [Deletion flags and DELETE transfer little, and eviction under a subscription refetches](../knowledge/observations/storage-and-deletion.md#deletion-flags-and-delete-transfer-little-and-eviction-under-a-subscription-refetches)).

### Time-based eviction

Keep only recent data on the device by scoping the subscription to a time window and evicting everything older than the same boundary:

```dart
// ✅ GOOD: Keep the last 7 days of orders on this device.
class OrderRetention {
  OrderRetention(this.ditto);

  final Ditto ditto;
  static const retention = Duration(days: 7);
  SyncSubscription? _subscription;

  // Same fixed-precision format as createdAt (utcTimestamp() from "Timestamps").
  String _cutoff() => utcTimestamp(DateTime.now().subtract(retention));

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribeFrom(_cutoff());
  }

  /// Call on a schedule, for example once a day.
  Future<int> evictExpired() async {
    final cutoff = _cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();

    try {
      // 2. Evict exactly the complement of the new subscription.
      final result = await ditto.store.execute(
        'EVICT FROM orders WHERE createdAt < :cutoff',
        arguments: {'cutoff': cutoff},
      );
      return result.mutatedDocumentIDs().length;
    } finally {
      // 3. Subscribe again with the moved boundary, even if the eviction failed.
      _subscription = _subscribeFrom(cutoff);
    }
  }

  SyncSubscription _subscribeFrom(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE createdAt >= :cutoff',
        arguments: {'cutoff': cutoff},
      );

  void dispose() => _subscription?.cancel();
}
```

**Why:** The subscription and the eviction use the same cutoff with complementary operators (`>=` and `<`), so no evicted document matches an active subscription.

Documents that were already in flight through the cancelled subscription can still arrive shortly after the eviction. If your boundary changes significantly (for example when the user switches stores), run the same `EVICT` again in the next scheduled cleanup or at the next app start, rather than immediately, so that evictions stay infrequent.

### Flag-based eviction

When a central component decides what is no longer needed, it can mark documents with a flag. Ditto's [device storage management documentation](https://docs.ditto.live/sdk/latest/sync/device-storage-management) describes this flag-based eviction: devices evict the flagged documents and subscribe only to unflagged ones. This approach works well when a Ditto Server is available, because the server can make sure documents have synced before they are marked:

```sql
-- Executed on the Ditto Server (for example through the HTTP API) or by an authorized device
UPDATE orders SET evictionFlag = true WHERE createdAt < :cutoff
```

```dart
// ✅ GOOD: Devices subscribe to unflagged documents and evict flagged ones.
SyncSubscription subscribeToUnflaggedOrders(Ditto ditto) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE coalesce(evictionFlag, false) = false',
  );
}

Future<void> evictFlaggedOrders(Ditto ditto) async {
  await ditto.store.execute('EVICT FROM orders WHERE evictionFlag = true');
}
```

Because the subscription never matches flagged documents, the device does not need to cancel and re-register it before each eviction.

Evicting flagged documents on a device that relays data can bring old versions back. A device that missed the flag still holds the unflagged version, and after the eviction, the relay receives that version again as a matching document (see [Soft delete, subscriptions, and cleanup](#soft-delete-subscriptions-and-cleanup) and [A relay that evicts flagged documents receives old versions back](../knowledge/observations/storage-and-deletion.md#a-relay-that-evicts-flagged-documents-receives-old-versions-back)). Use flag-based eviction where every device can receive the flag before the relays evict, for example through a Ditto Server.

### Batching evictions

`EVICT` supports `LIMIT`, so a large cleanup can be split into smaller transactions. Combine it with `RETURNING COUNT(*)` to know when to stop:

```dart
// ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict.
// First cancel or narrow every subscription that matches these documents (see the EVICT section).
Future<int> evictInBatches(Ditto ditto, String cutoff) async {
  var total = 0;
  while (true) {
    final result = await ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 '
      'RETURNING COUNT(*) AS evicted',
      arguments: {'cutoff': cutoff},
    );
    final evicted = result.items.first.value['evicted'] as int;
    total += evicted;
    if (evicted == 0) return total;
  }
}
```

Batching keeps individual write transactions short (see [Evicting in chunks costs little more than one statement](../knowledge/observations/performance-measurements.md#evicting-in-chunks-costs-little-more-than-one-statement)). It does not reduce the sync cost of eviction: run the whole batched cleanup on the usual schedule (see [Eviction frequency](#eviction-frequency)), not as many separate cleanups.

### Eviction frequency

- Evict on a regular schedule, but no more than about once per day, during periods of minimal disruption such as after hours.
- Since SDK 5.1, Ditto writes a warning-level log entry when post-eviction session cleanup runs too frequently within a sliding window, signaling that excessive evictions may cause sync overhead on connected peers. Treat this warning as a sign to evict less often.
- Local `DELETE` and `EVICT` execution is fast, but the sync cost of each eviction on connected peers still applies.

> **Advanced:** The system parameter `DISABLE_REPLICATION_GC_ON_EVICT` (default `false`) stops each eviction from triggering immediate per-peer replication metadata cleanup; the periodic background garbage collection still reclaims metadata for disconnected peers once they exceed its TTL (about 7 days by default). It is an opt-in setting for deployments where eviction-time filesystem work contributes to write latency. Leave it at the default unless profiling shows that problem.

## Choosing DELETE, Soft Delete, or EVICT

| Requirement | `DELETE` | Soft delete | `EVICT` |
|---|---|---|---|
| Remove data for every peer | ✅ (tombstone) | ✅ (flag, then cleanup) | ❌ (local only) |
| Safe when devices stay offline longer than the tombstone TTL (7 days by default) | ❌ (data can be resurrected; see [A device with an old copy resurrects a document after its tombstone is reaped](../knowledge/observations/storage-and-deletion.md#a-device-with-an-old-copy-resurrects-a-document-after-its-tombstone-is-reaped)) | ✅ | ✅ (other peers are unaffected) |
| Safe with concurrent updates on other devices | ❌ (husk documents) | ✅ | ✅ |
| Can be undone | ❌ | ✅ | ✅ (data syncs back if a subscription matches it again) |
| Frees local storage (see [Evicting data does not free disk space at once](../knowledge/observations/storage-and-deletion.md#evicting-data-does-not-free-disk-space-at-once)) | ✅ (the space is reused at once and reclaimed later; tombstones after reaping) | ❌ (until cleanup) | ✅ (the space is reused at once and reclaimed later) |
| Effect on queries | None: tombstones are not read | Queries read the flagged documents until cleanup (much slower with many flagged documents and no index on the flag; see [Tombstones and evicted documents do not slow queries, but flagged documents do](../knowledge/observations/storage-and-deletion.md#tombstones-and-evicted-documents-do-not-slow-queries-but-flagged-documents-do)) | None |
| Extra query complexity | None | Every query filters the flag | Subscription and eviction scopes must be complementary |
| Data sent to other devices (see [Deletion flags and DELETE transfer little, and eviction under a subscription refetches](../knowledge/observations/storage-and-deletion.md#deletion-flags-and-delete-transfer-little-and-eviction-under-a-subscription-refetches)) | Small (about 43 bytes per document) | Small (about 28 bytes per document) | None, unless a subscription still matches: then every evicted document is downloaded again |

Typical choices:

- **Data owned by one user and rarely edited concurrently** (for example a draft that the user discards), in a deployment where devices sync regularly: `DELETE`.
- **Shared business records** (orders, tasks, inventory) that several devices edit, or deployments with long offline periods: soft delete, with cleanup as described in [Soft delete, subscriptions, and cleanup](#soft-delete-subscriptions-and-cleanup).
- **Storage management on edge devices** (old history, data for other locations): `EVICT` with complementary subscriptions.

## Monitoring Storage

`system:system_info` reports storage usage and document counts for the local device. The values are collected periodically, so they can lag behind recent writes:

```sql
SELECT key, value FROM system:system_info WHERE key LIKE 'fs_usage%'

SELECT key, value FROM system:system_info WHERE key LIKE 'collection_num_docs%'
```

Keys include `fs_usage_total`, `fs_usage_store`, `fs_usage_replication`, `fs_usage_attachment`, `fs_usage_auth`, `fs_device_available`, and `fs_device_total` (namespace `core`), and `collection_num_docs[<collection>]` (namespace `store`). Each key can appear more than once with different timestamps; read the newest row.

```dart
// ✅ GOOD: Read the latest storage snapshot on demand (for example from a
// diagnostics screen or a daily maintenance task).
Future<Map<String, Object?>> storageSnapshot(Ditto ditto) async {
  final result = await ditto.store.execute(
    "SELECT key, value, timestamp FROM system:system_info "
    "WHERE key LIKE 'fs_%' OR key LIKE 'collection_num_docs%' "
    "ORDER BY timestamp ASC",
  );
  final snapshot = <String, Object?>{};
  for (final item in result.items) {
    // Later rows overwrite earlier ones, so the newest value wins.
    snapshot[item.value['key'] as String] = item.value['value'];
  }
  return snapshot;
}
```

**SQLite write-ahead log (SDK 5.2+)**: Ditto's store is built on SQLite, which writes changes to a write-ahead log (WAL) before folding them into the database file. On devices that run for weeks, this log could grow without bound. Since 5.2, Small Peers keep the WAL in check and reclaim free disk space automatically (system parameters `BACKEND_SQLITE3_ENABLE_WAL_SIZE_MONITOR` and `BACKEND_SQLITE3_ENABLE_INCREMENTAL_VACUUM_RECLAIM`, both on by default). If the WAL keeps growing past `BACKEND_SQLITE3_WAL_SIZE_THRESHOLD_BYTES` (1 GiB by default), Ditto logs a warning; the usual cause is a read transaction that stays open for a long time. The current size is in `system:system_info`, where each key can appear several times with different timestamps (recorded about once a minute in our testing; see [On SDK 5.2.0, system:system_info keeps old rows of each storage value](../knowledge/observations/storage-and-deletion.md#on-sdk-520-systemsystem_info-keeps-old-rows-of-each-storage-value)), so take the latest row of each key:

```sql
-- wal_current_size_bytes, wal_peak_size_bytes, checkpoint_busy_percent, auto_vacuum
SELECT key, value, timestamp FROM system:system_info
WHERE namespace = 'backend_sqlite3'
ORDER BY timestamp DESC
```

Deleted and evicted data leaves free space inside the database files. Later writes reuse it, but the files shrink only when the automatic reclaim runs: by default only once the free space exceeds `BACKEND_SQLITE3_INCREMENTAL_VACUUM_THRESHOLD_BYTES` (100 MB), so `fs_usage_store` does not drop after you evict less than that, and SDK 5.1.0 does not reclaim at all (in our testing; see [Evicting data does not free disk space at once](../knowledge/observations/storage-and-deletion.md#evicting-data-does-not-free-disk-space-at-once)). Even a small store uses tens of megabytes: since 5.1, after a few thousand writes, the WAL of the document store and that of the attachment store each reached about 20 MB (see [The write-ahead log grows to about 20 MB](../knowledge/observations/storage-and-deletion.md#the-write-ahead-log-grows-to-about-20-mb)).

**❌ DON'T:**

- Register a long-lived observer on `system:system_info`: it fires often even when nothing changed (every 500 ms in 5.1.0, and twice about every second in 5.2.0, mostly with identical results; see [Observers of system:system_info keep firing while nothing changes](../knowledge/observations/observer-behavior.md#observers-of-systemsystem_info-keep-firing-while-nothing-changes)). Query it with `execute` when you need it.

To keep storage under control, combine monitoring with a retention policy ([EVICT](#evict)) and keep individual documents small (see [Document Size Limits](data-modeling.md#document-size-limits)).
