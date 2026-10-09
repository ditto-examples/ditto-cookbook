# Storage Lifecycle: Additional Patterns

Supplementary patterns for the [storage-lifecycle skill](../SKILL.md). The authoritative source is `§ Deletion and Storage Management` in the guide (`../../guide/reference/ditto.md`).

## Table of Contents

- [What DELETE Leaves Behind](#what-delete-leaves-behind)
- [Husk Documents](#husk-documents)
- [Deleting on the Ditto Server](#deleting-on-the-ditto-server)
- [Indexing Soft-Delete Filters](#indexing-soft-delete-filters)
- [Cleaning Up Soft-Deleted Documents](#cleaning-up-soft-deleted-documents)
- [Switching Partitions (Store Switch)](#switching-partitions-store-switch)
- [Eviction Scheduling](#eviction-scheduling)
- [Monitoring Storage](#monitoring-storage)

---

## What DELETE Leaves Behind

- The values are removed. A small tombstone remains: the document ID, metadata such as the deletion time, and the field names the document had. Tombstones are internal and cannot be queried.
- Tombstones are only shared with peers that have seen the document before it was deleted; a peer never receives a tombstone for a document it never knew about. Such a peer can accept a stale copy from a device that was offline, and pass it on, until it meets a peer that holds the tombstone (SDK 5.1.0 tests).
- After `DELETE`, the document no longer appears in `SELECT`, is not counted by `COUNT(*)`, and an `UPDATE` no longer matches it.
- A later `INSERT` with the same `_id` creates a new document; fields of the deleted document do not reappear, unless another device edited the old document concurrently (those edits merge into the new document). Re-inserting an *evicted* `_id` merges with the copies other peers still hold.
- Inserting with `INITIAL DOCUMENTS` for an `_id` that was previously deleted on this device does not bring the document back: the deletion wins. If the seed is identical to the `INITIAL` insert that created the document, the document stays deleted; if the content differs, or the document was originally created with a regular `INSERT`, a document remains whose fields are all `null`. The same applies when the deletion came from another device, and the `null` document then appears on every device (SDK 5.1.0).
- The tombstone TTL is measured from the deleting device's clock, so inaccurate clocks make tombstones expire earlier or later than expected.
- Scheduling reaping during off-hours (`ENABLE_REAPER_PREFERRED_HOUR_SCHEDULING`, `REAPER_PREFERRED_HOUR`) requires environment variables set before Ditto starts and is not supported on WASM-based platforms; contact Ditto support before relying on it.

Tombstone defaults, reaping, and the Edge/Ditto Server TTL rule: [SKILL.md rule 2](../SKILL.md#2-respect-the-tombstone-ttl-critical) and `§ Tombstone TTL and reaping`.

---

## Husk Documents

When one device deletes a document while another device concurrently updates it, the add-wins CRDT merges both operations field by field. The result is a *husk document*, and the document is not deleted. In SDK 5.1.0, the husk's shape depends on which operation was written first:

```text
Initial:            {"_id": "abc123", "color": "red", "make": "Toyota", "year": 2020}

Device A:           DELETE FROM cars WHERE _id = 'abc123'
Device B (offline, later): UPDATE cars SET color = 'blue' WHERE _id = 'abc123'
After merge:        {"_id": "abc123", "color": "blue"}      // make, year: MISSING

Device B (offline): UPDATE cars SET color = 'blue' WHERE _id = 'abc123'
Device A (later):   DELETE FROM cars WHERE _id = 'abc123'
After merge:        {"_id": "abc123", "color": null}        // make, year: MISSING
```

- The document survives even when the `DELETE` is the later write.
- Fields the update did not touch are MISSING (`make IS MISSING` is `true`) in SDK 5.1.0, although Ditto's [deletion documentation](https://docs.ditto.live/sdk/latest/crud/delete) shows them as `null`. Make code that reads husk documents handle both cases.
- Husks count in `SELECT COUNT(*)`, but value filters exclude them.
- Running the `DELETE` again after the merge removes the husk on every device.

To avoid husk documents:

1. Use a soft delete for data that may be edited concurrently.
2. Manage edge storage with `EVICT` and perform permanent deletion on the Ditto Server (for example through its HTTP API).
3. Coordinate your workflow so that the same document is not deleted and updated at the same time.

If husk documents are possible in your data, keep them out of lists with a filter on a field that every live document has. Test for both cases: `WHERE make IS NOT MISSING AND make IS NOT NULL`. `IS NOT NULL` alone is `true` for a missing field. Also make the UI tolerate `null` and missing fields instead of assuming every field is present (a missing key reads as `null` from the item's map): <!-- lint-ignore -->

```dart
import 'package:flutter/material.dart';

// ✅ GOOD: Render a car even when some fields are null (possible husk document).
class CarTile extends StatelessWidget {
  const CarTile({super.key, required this.car});

  final Map<String, dynamic> car;

  @override
  Widget build(BuildContext context) {
    final make = car['make'] as String?;
    final year = car['year'] as int?;
    final color = car['color'] as String?;
    return ListTile(
      title: Text(make ?? 'Unknown make'),
      subtitle: Text('${year ?? '-'} · ${color ?? '-'}'),
    );
  }
}
```

Guide: `§ Husk documents`

---

## Deleting on the Ditto Server

`DELETE` statements sent through the Ditto Server HTTP API run as a single atomic operation. Delete in batches of 30,000 documents or fewer to avoid slowing down sync for connected devices:

```sql
DELETE FROM orders WHERE status = 'archived' LIMIT 30000
```

Cleanup statements typically sent to the Ditto Server in a server-driven retention setup (see [examples/ttl-eviction-ditto-server.dart](../examples/ttl-eviction-ditto-server.dart)):

```sql
-- Mark documents that devices no longer need; devices evict flagged documents
UPDATE orders SET evictionFlag = true WHERE createdAt < :cutoff

-- Variant A soft-delete cleanup: permanently remove soft-deleted records after the retention period
DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000
```

- Repeat a batch until no documents are affected.
- There is no `DROP COLLECTION` statement. `DELETE FROM orders` without a `WHERE` clause deletes every document, but the collection remains.
- See the Ditto Server HTTP API documentation for the endpoint and authentication.

Guide: `§ Deleting on the Ditto Server`

---

## Indexing Soft-Delete Filters

`coalesce(isDeleted, false) = false` alone cannot use an index on `isDeleted` (collection scan). Index-friendly options:

| Approach | Plan |
|---|---|
| `status = :status AND coalesce(isDeleted, false) = false` with an index that starts with `status` | Index scan on `status`; `coalesce` applied as a filter |
| `isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false` with an index on `isDeleted` | Index scan (same documents as the `coalesce` form) |
| `isDeleted = false` with an index on `isDeleted`, when every document is guaranteed to have the field | Index scan |

Confirm the plan with `ADVISE` or `EXPLAIN`.

```sql
SELECT * FROM orders
WHERE isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false
```

Guide: `§ Indexing soft-delete filters`

---

## Cleaning Up Soft-Deleted Documents

How soft-deleted documents are eventually removed depends on the subscription design (both keep flagged documents inside the subscription until every device has received the flag):

| | Variant A: whole-collection subscription | Variant B: retention-window subscription |
|---|---|---|
| Subscription | `SELECT * FROM orders WHERE storeId = :storeId` (includes soft-deleted documents) | `... WHERE storeId = :storeId AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)` |
| Cleanup | A `DELETE` after the retention period, on the Ditto Server or by another authorized peer, that syncs to every device | Each device evicts the complement of its subscription; the record stays on the Ditto Server until it is deleted there |
| Device-side `EVICT` | ❌ Evicted documents still match the subscription and sync back | ✅ Evicted documents are outside the subscription |
| Subscription changes | None | Re-registered when the cutoff moves (for example once a day) |
| Trade-offs | Simplest design. Soft-deleted documents use storage on every device until the `DELETE` runs, and the `DELETE` is subject to the tombstone rules | More moving parts. Choose a window longer than the longest expected offline period, so that every device receives the flag while the document is still inside its subscription |

Variant A cleanup (run once flagged documents are no longer edited, to avoid husk documents):

```sql
DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000
```

Variant B device-side cleanup, the complement of the retention-window subscription:

```sql
EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff
```

In Variant B, cancel the old subscription before evicting, use the same cutoff value for the eviction and the new subscription, and choose a retention window longer than the longest expected offline period. See [examples/soft-delete-relay.dart](../examples/soft-delete-relay.dart).

Guide: `§ Soft delete, subscriptions, and cleanup`

---

## Switching Partitions (Store Switch)

Changing the set of data a device needs (a different store or tenant) is a legitimate reason to change subscriptions. Cancel first, evict the old partition, then subscribe to the new one:

```dart
import 'package:ditto_live/ditto_live.dart';

// ✅ GOOD: Cancel, evict the old store's data, subscribe to the new store.
Future<List<SyncSubscription>> switchStore(
  Ditto ditto,
  List<SyncSubscription> currentSubscriptions,
  String newStoreId,
) async {
  for (final subscription in currentSubscriptions) {
    subscription.cancel();
  }

  await ditto.store.execute(
    'EVICT FROM orders WHERE storeId != :storeId',
    arguments: {'storeId': newStoreId},
  );

  return [
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': newStoreId},
    ),
  ];
}
```

Data that was already being transferred when the subscriptions were cancelled can still arrive afterwards. If the device must not keep the old store's data, run the same eviction again later (for example, on the next app start or in a periodic cleanup); see [examples/evict-subscription-management-good.dart](../examples/evict-subscription-management-good.dart).

Switch partitions only when the needed data really changes. Search boxes, tabs, filters, and sort orders should change local observers, not subscriptions (avoid changing subscriptions more often than about every 15 minutes).

Guide: `§ Cancelling subscriptions and local data`, `§ Subscription Lifecycle`

---

## Eviction Scheduling

- Evict on a regular schedule, but no more than about once per day, during periods of minimal disruption such as after hours.
- (SDK 5.1+) Ditto writes a warning-level log entry when post-eviction session cleanup runs too frequently within a sliding window. Treat it as a sign to evict less often.
- Local `DELETE` and `EVICT` execution is fast, but the sync cost of each eviction on connected peers still applies.
- `EVICT` supports `LIMIT` and `RETURNING`, so a large cleanup can be split into short transactions (see [SKILL.md rule 7](../SKILL.md#7-evict-on-a-schedule-in-batches-high)). Batching does not reduce the sync cost of eviction: run the whole batched cleanup on the usual schedule, not as many separate cleanups.
- **Advanced:** `DISABLE_REPLICATION_GC_ON_EVICT` (default `false`) stops each eviction from triggering immediate per-peer replication metadata cleanup; periodic background garbage collection still runs. Leave it at the default unless profiling shows eviction-time write latency.

Guide: `§ Eviction frequency`

---

## Monitoring Storage

`system:system_info` reports storage usage and document counts for the local device. Values are collected periodically and can lag behind recent writes. Each key can appear more than once with different timestamps; read the newest row.

```sql
SELECT key, value FROM system:system_info WHERE key LIKE 'fs_usage%'
```

Keys include `fs_usage_total`, `fs_usage_store`, `fs_usage_replication`, `fs_usage_attachment`, `fs_usage_auth`, `fs_device_available`, `fs_device_total` (namespace `core`), and `collection_num_docs[<collection>]` (namespace `store`).

```dart
import 'package:ditto_live/ditto_live.dart';

// ✅ GOOD: Read the latest storage snapshot on demand.
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

**❌ DON'T** register a long-lived observer on `system:system_info`: such observers run every 500 ms regardless of whether anything changed.

Guide: `§ Monitoring Storage`
