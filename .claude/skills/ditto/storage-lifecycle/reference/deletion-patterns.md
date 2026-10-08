# Storage Lifecycle: Additional Patterns

Supplementary patterns for the [storage-lifecycle skill](../SKILL.md). The authoritative source is the guide section [Deletion and Storage Management](../../../../guides/best-practices/ditto.md#deletion-and-storage-management).

## Table of Contents

- [What DELETE Leaves Behind](#what-delete-leaves-behind)
- [Husk Documents](#husk-documents)
- [Deleting on the Ditto Server](#deleting-on-the-ditto-server)
- [Cleaning Up Soft-Deleted Documents](#cleaning-up-soft-deleted-documents)
- [Switching Partitions (Store Switch)](#switching-partitions-store-switch)
- [Eviction Scheduling](#eviction-scheduling)
- [Monitoring Storage](#monitoring-storage)

---

## What DELETE Leaves Behind

- The values are removed. A small tombstone remains: the document ID, metadata such as the deletion time, and the field names the document had. Tombstones are internal and cannot be queried.
- Tombstones are only shared with peers that have seen the document before it was deleted; a peer never receives a tombstone for a document it never knew about.
- After `DELETE`, the document no longer appears in `SELECT`, is not counted by `COUNT(*)`, and an `UPDATE` no longer matches it.
- A later `INSERT` with the same `_id` creates a new document; fields of the deleted document do not reappear.
- Inserting with `INITIAL DOCUMENTS` for an `_id` that was previously deleted on this device does not bring the document back: the deletion wins. If the seed is identical to the `INITIAL` insert that created the document, the document stays deleted; if the content differs, or the document was originally created with a regular `INSERT`, a document remains whose fields are all `null`.

Tombstone defaults, reaping, and the Edge/Ditto Server TTL rule: [SKILL.md pattern 2](../SKILL.md#2-respect-the-tombstone-ttl-priority-critical) and the guide's [Tombstone TTL and reaping](../../../../guides/best-practices/ditto.md#tombstone-ttl-and-reaping).

---

## Husk Documents

When one device deletes a document while another device concurrently updates it, the add-wins CRDT merges both operations field by field. Ditto's [deletion documentation](https://docs.ditto.live/sdk/latest/crud/delete) describes the result as a *husk document*: the updated fields keep their new values, every other field is `null`, and the document is not deleted:

```text
Initial:            {"_id": "abc123", "color": "red", "make": "Toyota", "year": 2020}
Device A:           DELETE FROM cars WHERE _id = 'abc123'
Device B (offline): UPDATE cars SET color = 'blue' WHERE _id = 'abc123'
After merge:        {"_id": "abc123", "color": "blue", "make": null, "year": null}
```

To avoid husk documents:

1. Use a soft delete for data that may be edited concurrently.
2. Manage edge storage with `EVICT` and perform permanent deletion on the Ditto Server (for example through its HTTP API).
3. Coordinate your workflow so that the same document is not deleted and updated at the same time.

If husk documents are possible in your data, make the UI tolerate `null` fields instead of assuming every field is present:

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

Guide: [Husk documents](../../../../guides/best-practices/ditto.md#husk-documents)

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

Guide: [Deleting on the Ditto Server](../../../../guides/best-practices/ditto.md#deleting-on-the-ditto-server)

---

## Cleaning Up Soft-Deleted Documents

How soft-deleted documents are eventually removed depends on the subscription design (both keep flagged documents inside the subscription until every device has received the flag):

| | Variant A: whole-collection subscription | Variant B: retention-window subscription |
|---|---|---|
| Subscription | `SELECT * FROM orders WHERE storeId = :storeId` (includes soft-deleted documents) | `... WHERE storeId = :storeId AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)` |
| Cleanup | A `DELETE` after the retention period, on the Ditto Server or by another authorized peer, that syncs to every device | Each device evicts the complement of its subscription; the record stays on the Ditto Server until it is deleted there |
| Device-side `EVICT` | ❌ Evicted documents still match the subscription and sync back | ✅ Evicted documents are outside the subscription |

Variant A cleanup (run once flagged documents are no longer edited, to avoid husk documents):

```sql
DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000
```

Variant B device-side cleanup, the complement of the retention-window subscription:

```sql
EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff
```

In Variant B, cancel the old subscription before evicting, use the same cutoff value for the eviction and the new subscription, and choose a retention window longer than the longest expected offline period. See [examples/soft-delete-relay.dart](../examples/soft-delete-relay.dart).

Guide: [Soft delete, subscriptions, and cleanup](../../../../guides/best-practices/ditto.md#soft-delete-subscriptions-and-cleanup)

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

Guide: [Cancelling subscriptions and local data](../../../../guides/best-practices/ditto.md#cancelling-subscriptions-and-local-data), [Subscription Lifecycle](../../../../guides/best-practices/ditto.md#subscription-lifecycle)

---

## Eviction Scheduling

- Evict on a regular schedule, but no more than about once per day, during periods of minimal disruption such as after hours.
- (SDK 5.1+) Ditto writes a warning-level log entry when post-eviction session cleanup runs too frequently within a sliding window. Treat it as a sign to evict less often.
- Local `DELETE` and `EVICT` execution is fast, but the sync cost of each eviction on connected peers still applies.
- `EVICT` supports `LIMIT` and `RETURNING`, so a large cleanup can be split into short transactions (see [SKILL.md pattern 7](../SKILL.md#7-evict-on-a-schedule-in-batches-priority-high)). Batching does not reduce the sync cost of eviction: run the whole batched cleanup on the usual schedule, not as many separate cleanups.
- **Advanced:** `DISABLE_REPLICATION_GC_ON_EVICT` (default `false`) stops each eviction from triggering immediate per-peer replication metadata cleanup; periodic background garbage collection still runs. Leave it at the default unless profiling shows eviction-time write latency.

Guide: [Eviction frequency](../../../../guides/best-practices/ditto.md#eviction-frequency)

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

Guide: [Monitoring Storage](../../../../guides/best-practices/ditto.md#monitoring-storage)
