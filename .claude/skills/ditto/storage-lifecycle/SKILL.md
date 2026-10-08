---
name: storage-lifecycle
description: |
  Validates Ditto deletion strategies (DELETE, soft delete, EVICT), tombstone TTL settings, and local storage management for Ditto SDK 5.1.

  CRITICAL ISSUES PREVENTED:
  - Deleted data resurrected by devices that stay offline longer than the tombstone TTL (7 days by default)
  - Small Peer tombstone TTL (TOMBSTONE_TTL_HOURS) configured above the Ditto Server TTL
  - Evicted documents syncing straight back because a subscription still matches them
  - DELETE/EVICT with USE IDS and no WHERE predicate silently removing nothing (SDK 5.1.0)
  - Soft-delete filters (isDeleted != true) that hide documents where the flag is missing or null
  - Husk documents caused by DELETE racing a concurrent UPDATE
  - Evicting too often and overloading connected peers with resyncs

  TRIGGERS:
  - Writing DELETE or EVICT statements
  - Implementing soft delete (isDeleted / deletedAt flags) and filtering deleted documents
  - Designing retention policies, time-based or flag-based eviction
  - Changing subscriptions around eviction (store switch, retention window)
  - Configuring TOMBSTONE_TTL_HOURS or other tombstone/reaping system parameters
  - Monitoring local storage usage

  PLATFORMS: Flutter (Dart) primary; the DQL rules apply to all SDKs (JavaScript, Swift, Kotlin)
---

# Ditto Storage Lifecycle Management

Actionable patterns for removing data and managing local storage with Ditto SDK 5.1. The authoritative explanation is the guide section [Deletion and Storage Management](../../../guides/best-practices/ditto.md#deletion-and-storage-management).

## Table of Contents

- [When This Skill Applies](#when-this-skill-applies)
- [Platform Detection](#platform-detection)
- [Choosing a Removal Strategy](#choosing-a-removal-strategy)
- [Critical Patterns](#critical-patterns)
  - [1. Target DELETE and EVICT with WHERE](#1-target-delete-and-evict-with-where-priority-critical)
  - [2. Respect the Tombstone TTL](#2-respect-the-tombstone-ttl-priority-critical)
  - [3. Filter Soft-Deleted Documents with coalesce](#3-filter-soft-deleted-documents-with-coalesce-priority-critical)
  - [4. Keep Soft-Deleted Documents in Subscriptions](#4-keep-soft-deleted-documents-in-subscriptions-priority-critical)
  - [5. Evict Only Outside Every Active Subscription](#5-evict-only-outside-every-active-subscription-priority-critical)
  - [6. Avoid Husk Documents](#6-avoid-husk-documents-priority-high)
  - [7. Evict on a Schedule, in Batches](#7-evict-on-a-schedule-in-batches-priority-high)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

## When This Skill Applies

- A statement contains `DELETE FROM` or `EVICT FROM`
- Code sets or filters a deletion flag (`isDeleted`, `deletedAt`, `evictionFlag`)
- Code cancels or re-registers subscriptions to free storage (store switch, retention window)
- Code reads or changes `TOMBSTONE_TTL_HOURS`, `TOMBSTONE_TTL_ENABLED`, `DAYS_BETWEEN_REAPING`, or `DISABLE_REPLICATION_GC_ON_EVICT`
- Code reads storage metrics from `system:system_info`

## Platform Detection

| Platform | Indicator |
|---|---|
| Flutter (Dart) | `import 'package:ditto_live/ditto_live.dart';` |
| JavaScript / TypeScript | `from '@dittolive/ditto'` |
| Swift | `import DittoSwift` |
| Kotlin | `import com.ditto.kotlin.*` |

The DQL statements and storage rules below are the same on every platform. Code samples use Dart.

---

## Choosing a Removal Strategy

| Requirement | `DELETE` | Soft delete | `EVICT` |
|---|---|---|---|
| Remove data for every peer | ✅ (tombstone) | ✅ (flag, then cleanup) | ❌ (local only) |
| Safe when devices stay offline longer than the tombstone TTL (7 days by default) | ❌ (data can be resurrected) | ✅ | ✅ (other peers are unaffected) |
| Safe with concurrent updates on other devices | ❌ (husk documents) | ✅ | ✅ |
| Can be undone | ❌ | ✅ | ✅ (data syncs back if a subscription matches it again) |
| Frees local storage | ✅ (values immediately; tombstones after reaping) | ❌ (until cleanup) | ✅ (immediately) |
| Extra query complexity | None | Every query filters the flag | Subscription and eviction scopes must be complementary |

Typical choices (from the guide):

- **Data owned by one user and rarely edited concurrently**, in a deployment where devices sync regularly: `DELETE`.
- **Shared business records** (orders, tasks, inventory) or long offline periods: soft delete, with cleanup by a synced `DELETE` (Variant A) or device-side `EVICT` (Variant B); see [pattern 4](#4-keep-soft-deleted-documents-in-subscriptions-priority-critical).
- **Storage management on edge devices**: `EVICT` with complementary subscriptions.

In deployments with a Ditto Server (formerly Big Peer), use `DELETE` for permanent removal (typically on the Ditto Server) and `EVICT` to manage storage on edge devices. If you plan to use `DELETE` in a deployment with Small Peers only, contact Ditto support to review the design.

Guide: [Choosing DELETE, Soft Delete, or EVICT](../../../guides/best-practices/ditto.md#choosing-delete-soft-delete-or-evict)

---

## Critical Patterns

### 1. Target DELETE and EVICT with WHERE (Priority: CRITICAL)

**Problem**: `DELETE` and `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) complete without an error but remove nothing.

> **Note (SDK 5.1.0):** `DELETE` and `EVICT` statements that use `USE IDS` without a `WHERE` predicate (no `WHERE` clause, or `WHERE true`) remove nothing. Use `WHERE _id IN :ids` instead; it is planned as an ID scan, so it is just as efficient.

**✅ DO**:
- Target documents with `WHERE _id = :id` or `WHERE _id IN :ids`.
- Add `RETURNING` (SDK 5.1+) when you need the removed content (undo banner, audit record). It returns the removed content from the same atomic statement; the tombstone keeps no values.

**❌ DON'T**:
- Write `DELETE FROM orders USE IDS LIST :ids` or `EVICT FROM orders USE IDS 'a'`.
- Use `DELETE` to free space on one device; it removes the data for every peer.

```dart
// ✅ GOOD: Delete by ID and capture what was removed (SDK 5.1+).
Future<List<Map<String, dynamic>>> deleteOrders(
  Ditto ditto,
  List<String> orderIds,
) async {
  final result = await ditto.store.execute(
    'DELETE FROM orders WHERE _id IN :ids RETURNING _id, status, total',
    arguments: {'ids': orderIds},
  );
  // With RETURNING, each item holds the document as it was before deletion.
  // Read the removed documents from items, not from mutatedDocumentIDs().
  return result.items.map((item) => item.value).toList();
}

// ❌ BAD: Completes without an error, but deletes nothing in SDK 5.1.0.
Future<void> deleteOrdersWithUseIds(Ditto ditto, List<String> orderIds) async {
  await ditto.store.execute(
    'DELETE FROM orders USE IDS LIST :ids',
    arguments: {'ids': orderIds},
  );
}
```

`RETURNING` also accepts aggregates, which is convenient for counting:

```sql
DELETE FROM orders WHERE status = 'cancelled' AND createdAt < :cutoff RETURNING COUNT(*) AS removed
```

Guide: [DELETE and Tombstones](../../../guides/best-practices/ditto.md#delete-and-tombstones), [RETURNING (SDK 5.1+)](../../../guides/best-practices/ditto.md#returning-sdk-51)

---

### 2. Respect the Tombstone TTL (Priority: CRITICAL)

**Problem**: `DELETE` leaves a tombstone (document ID, metadata such as the deletion time, and the field names; no values). Each device reaps expired tombstones periodically. A device that stays offline longer than the TTL can reconnect after every other peer has reaped the tombstone and share its old copy again ("zombie data").

Defaults:

| System parameter | Default | Meaning |
|---|---|---|
| `TOMBSTONE_TTL_ENABLED` | `true` | Expired tombstones are removed automatically |
| `TOMBSTONE_TTL_HOURS` | `168` (7 days) | Age after which a tombstone expires on this device |
| `DAYS_BETWEEN_REAPING` | `1` | Days between reaping runs |
| `TOMBSTONE_REAP_BATCH_SIZE` (SDK 5.1+) | `10000` | Expired tombstones are removed in bounded batches |

```sql
SHOW ALL LIKE '%tombstone%'
```

**✅ DO**:
- Make sure every device connects within the tombstone TTL, or use a soft delete for that data.
- If devices can legitimately stay offline longer than 7 days, raise `TOMBSTONE_TTL_HOURS` on the device, staying at or below the Ditto Server TTL.
- Apply `ALTER SYSTEM` settings after every `Ditto.open` and before `ditto.sync.start()`; they are not persisted.

**❌ DON'T**:
- Configure the Edge TTL (`TOMBSTONE_TTL_HOURS` on Small Peers) above the Ditto Server TTL. The Ditto Server always syncs documents, so tombstones that outlive its copy are sent back to it repeatedly. The Ditto Server tombstone TTL defaults to 30 days; changes to the server side go through Ditto support. <!-- lint-ignore -->
- Choose a very short TTL; the tombstone can expire before it reaches the other peers.
- Look for a tombstone-lifetime method on the SDK: the TTL is a system parameter, set with `ALTER SYSTEM`.

```dart
// ✅ GOOD: Keep tombstones for 14 days on this device (must not exceed the
// Ditto Server TTL). Call after every Ditto.open() and before sync.start().
Future<void> applyTombstoneSettings(Ditto ditto) async {
  await ditto.store.execute('ALTER SYSTEM SET TOMBSTONE_TTL_HOURS = 336');
}
```

The TTL is measured from the deleting device's clock, so inaccurate clocks make tombstones expire earlier or later than expected. Scheduling reaping during off-hours (`ENABLE_REAPER_PREFERRED_HOUR_SCHEDULING`, `REAPER_PREFERRED_HOUR`) requires environment variables set before Ditto starts and is not supported on WASM-based platforms; contact Ditto support before relying on it.

Guide: [Tombstone TTL and reaping](../../../guides/best-practices/ditto.md#tombstone-ttl-and-reaping), [System Parameters Reference](../../../guides/best-practices/ditto.md#system-parameters-reference)

---

### 3. Filter Soft-Deleted Documents with coalesce (Priority: CRITICAL)

**Problem**: In DQL, a comparison with a missing or `null` field never passes a `WHERE` clause. `isDeleted != true` and `NOT isDeleted` silently drop every document that has no `isDeleted` field.

Which documents each filter matches, when `isDeleted` is `true`, `false`, `null`, or missing:

| Filter | Matches |
|---|---|
| `isDeleted != true` | `false` only |
| `NOT isDeleted` | `false` only |
| `isDeleted = false` | `false` only |
| `coalesce(isDeleted, false) = false` | `false`, `null`, missing |

**✅ DO**:
- Set both `isDeleted = true` and `deletedAt` (UTC ISO-8601 with a zone designator).
- Write `isDeleted: false` when you create documents.
- Filter with `coalesce(isDeleted, false) = false`.
- Restore with `SET isDeleted = false UNSET deletedAt`.

**❌ DON'T**:
- Filter with `isDeleted != true` or `NOT isDeleted`.

```dart
// ✅ GOOD: Create, soft delete, restore, and query helpers.
Future<void> createOrder(Ditto ditto, String orderId, String status) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId,
        'status': status,
        'isDeleted': false,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    },
  );
}

Future<void> softDeleteOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
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

**Indexes**: `coalesce(isDeleted, false) = false` alone cannot use an index on `isDeleted` (collection scan). Index-friendly options:

| Approach | Plan |
|---|---|
| `status = :status AND coalesce(isDeleted, false) = false` with an index that starts with `status` | Index scan on `status`; `coalesce` applied as a filter |
| `isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false` with an index on `isDeleted` | Index scan (same documents as the `coalesce` form) |
| `isDeleted = false` with an index on `isDeleted`, when every document is guaranteed to have the field | Index scan |

```sql
SELECT * FROM orders
WHERE isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false
```

Confirm the plan with `ADVISE` or `EXPLAIN`.

Guide: [Soft Delete](../../../guides/best-practices/ditto.md#soft-delete), [Indexing soft-delete filters](../../../guides/best-practices/ditto.md#indexing-soft-delete-filters), [MISSING and NULL](../../../guides/best-practices/ditto.md#missing-and-null)

---

### 4. Keep Soft-Deleted Documents in Subscriptions (Priority: CRITICAL)

**Problem**: The deletion flag is itself a change that every device must receive. A subscription that excludes soft-deleted documents (for example `WHERE coalesce(isDeleted, false) = false`) stops requesting a document as soon as it is flagged. Devices that already have the document keep it (cancelling or narrowing a subscription never deletes local data), and a subscription filter does not hide documents in local results: every local query and observer must filter flagged documents itself.

**✅ DO**:
- Keep soft-deleted documents inside the subscription at least until every device has received the flag.
- Hide them in local queries and observers with `coalesce(isDeleted, false) = false`.
- Choose one of the two subscription designs below and clean up accordingly.

**❌ DON'T**:
- Subscribe with `WHERE coalesce(isDeleted, false) = false` (or any filter on the flag) alone.
- Evict old soft-deleted documents on a device while a subscription still matches them (Variant A); they sync back.

| | Variant A: whole-collection subscription | Variant B: retention-window subscription |
|---|---|---|
| Subscription | Every document of the collection (or of the device's partition, such as one store), including soft-deleted ones | Active documents plus documents deleted within a retention window |
| Cleanup | A `DELETE` after the retention period, executed on the Ditto Server or by another authorized peer, that syncs to every device | Each device evicts documents deleted before the cutoff; the record stays on the Ditto Server until it is deleted there |
| Device-side `EVICT` of old soft-deleted documents | ❌ They still match the subscription and sync back | ✅ They are outside the subscription |
| Subscription changes | None | Re-registered when the cutoff moves (for example once a day) |
| Trade-offs | Simplest design. Soft-deleted documents use storage on every device until the `DELETE` runs, and the `DELETE` is subject to the tombstone rules | More moving parts. Choose a window longer than the longest expected offline period, so that every device receives the flag while the document is still inside its subscription |

```dart
// ✅ GOOD (Variant A): The subscription (owned by a long-lived service such as
// OrderSync) includes soft-deleted orders; local queries hide them.
SyncSubscription subscribeToStoreOrders(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}

// ❌ BAD: The document leaves the subscription as soon as it is flagged.
// Keep flagged documents in the subscription until every device has the flag.
SyncSubscription subscribeToActiveOrdersOnly(Ditto ditto) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE coalesce(isDeleted, false) = false',
  );
}
```

Variant A cleanup runs on the Ditto Server (for example through its HTTP API) once the retention period has passed and flagged documents are no longer edited:

```sql
DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000
```

Variant B subscribes with `coalesce(isDeleted, false) = false OR deletedAt >= :cutoff` and evicts exactly the complement (`isDeleted = true AND deletedAt < :cutoff`), cancelling the old subscription first and re-registering it with the moved cutoff. Move the cutoff only when you run cleanup, not on every screen change. The full service class is in [examples/soft-delete-relay.dart](examples/soft-delete-relay.dart).

Observers use the `changes` stream pattern (register without `onChange`, listen to `changes`, cancel both in `dispose()`); see [Store Observers in Flutter](../../../guides/best-practices/ditto.md#store-observers-in-flutter).

Guide: [Soft delete, subscriptions, and cleanup](../../../guides/best-practices/ditto.md#soft-delete-subscriptions-and-cleanup), [Multi-hop relay](../../../guides/best-practices/ditto.md#multi-hop-relay)

---

### 5. Evict Only Outside Every Active Subscription (Priority: CRITICAL)

**Problem**: `EVICT` removes documents from the local store only; no tombstone is created and other peers keep them. If an active subscription on this device still matches an evicted document, connected peers notice it is missing and sync it back, which can become a loop of evicting and re-syncing.

**✅ DO**:
- Cancel or narrow the affected subscriptions **before** evicting.
- Make the eviction query the exact complement of the remaining subscription (same cutoff value, `>=` in the subscription and `<` in the eviction).
- Keep subscription references in an app-level or feature-level service so you can cancel them.
- For a large boundary change (for example a store switch), data that was already being transferred can still arrive after cancelling; if the device must not keep it, run the same `EVICT` again later (for example, on the next app start or in a periodic cleanup).

**❌ DON'T**:
- Evict and then register a subscription that matches the evicted documents again (for example `SELECT * FROM orders`).
- Evict documents that an active subscription still covers.

```dart
// ✅ GOOD: Keep the last 7 days of orders on this device.
class OrderRetention {
  OrderRetention(this.ditto);

  final Ditto ditto;
  static const retention = Duration(days: 7);
  SyncSubscription? _subscription;

  String _cutoff() =>
      DateTime.now().toUtc().subtract(retention).toIso8601String();

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribeFrom(_cutoff());
  }

  /// Call on a schedule, for example once a day.
  Future<int> evictExpired() async {
    final cutoff = _cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();

    // 2. Evict exactly the complement of the new subscription.
    final result = await ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoff},
    );

    // 3. Subscribe again with the moved boundary.
    _subscription = _subscribeFrom(cutoff);
    return result.mutatedDocumentIDs().length;
  }

  SyncSubscription _subscribeFrom(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE createdAt >= :cutoff',
        arguments: {'cutoff': cutoff},
      );

  void dispose() => _subscription?.cancel();
}

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

**Flag-based eviction**: when a central component (typically the Ditto Server, which can make sure documents have synced first) sets `evictionFlag = true`, devices subscribe with `coalesce(evictionFlag, false) = false` and evict `evictionFlag = true`. The subscription never matches flagged documents, so it does not need to be cancelled before each eviction. See [examples/flag-based-eviction.dart](examples/flag-based-eviction.dart) and [examples/ttl-eviction-ditto-server.dart](examples/ttl-eviction-ditto-server.dart).

Guide: [EVICT](../../../guides/best-practices/ditto.md#evict), [Time-based eviction](../../../guides/best-practices/ditto.md#time-based-eviction), [Flag-based eviction](../../../guides/best-practices/ditto.md#flag-based-eviction), [Cancelling subscriptions and local data](../../../guides/best-practices/ditto.md#cancelling-subscriptions-and-local-data)

---

### 6. Avoid Husk Documents (Priority: HIGH)

**Problem**: When one device deletes a document while another concurrently updates it, the add-wins merge produces a *husk document*: fields written by the update keep their new values, all other fields are `null`, and the document is **not** deleted.

**✅ DO**:
- Use a soft delete for data that may be edited concurrently.
- Manage edge storage with `EVICT` and perform permanent deletion on the Ditto Server.
- Coordinate workflows so the same document is not deleted and updated at the same time.
- Make the UI tolerate documents whose fields are `null` if husks are possible.

**❌ DON'T**:
- Use `DELETE` for shared records that other devices edit.

Details and a null-tolerant rendering example: [reference/deletion-patterns.md](reference/deletion-patterns.md#husk-documents). Guide: [Husk documents](../../../guides/best-practices/ditto.md#husk-documents)

---

### 7. Evict on a Schedule, in Batches (Priority: HIGH)

**Problem**: Each eviction triggers a resync with every connected peer. Frequent evictions cost network traffic and processing on those peers. (SDK 5.1+) Ditto writes a warning-level log entry when post-eviction session cleanup runs too frequently.

**✅ DO**:
- Evict on a regular schedule, no more than about once per day, at a quiet time.
- Split a large cleanup with `LIMIT` and stop when `RETURNING COUNT(*)` reports zero.
- Treat the eviction-frequency warning as a sign to evict less often.

**❌ DON'T**:
- Evict on every screen change or app resume.
- Change `DISABLE_REPLICATION_GC_ON_EVICT` (default `false`) unless profiling shows eviction-time write latency.

```dart
// ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict.
// First cancel or narrow every subscription that matches these documents (pattern 5).
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

Batching keeps write transactions short; one cleanup run is still one eviction event for connected peers.

Guide: [Batching evictions](../../../guides/best-practices/ditto.md#batching-evictions), [Eviction frequency](../../../guides/best-practices/ditto.md#eviction-frequency)

---

## Quick Reference Checklist

### DELETE
- [ ] Targets documents with `WHERE _id = :id` / `WHERE _id IN :ids`, never `USE IDS` without a `WHERE` predicate
- [ ] Not used to free storage on one device (it removes the documents for every peer; use `EVICT`)
- [ ] Uses `RETURNING` (SDK 5.1+) when the removed content is needed
- [ ] Not used for shared records edited concurrently (husk documents)
- [ ] Every device connects within the tombstone TTL (7 days by default), or the data uses soft delete
- [ ] `TOMBSTONE_TTL_HOURS` on devices never exceeds the Ditto Server TTL; applied after every `Ditto.open`
- [ ] Large deletions on the Ditto Server run in batches of 30,000 documents or fewer

### Soft Delete
- [ ] Sets `isDeleted` and `deletedAt` (UTC, with zone); new documents get `isDeleted: false`
- [ ] Filters with `coalesce(isDeleted, false) = false` (or the index-friendly `IS MISSING OR IS NULL OR = false` form)
- [ ] Subscriptions keep flagged documents (Variant A: whole collection or partition; Variant B: retention window)
- [ ] Old flagged documents are cleaned up (Variant A: synced `DELETE`; Variant B: device-side `EVICT` of the complement)

### EVICT
- [ ] Affected subscriptions are cancelled or narrowed before evicting
- [ ] Eviction query is the exact complement of the remaining subscriptions
- [ ] No re-subscription that matches the evicted documents
- [ ] Runs on a schedule, at most about once per day; large runs use `LIMIT`
- [ ] Subscription references are kept in a long-lived service

### Monitoring
- [ ] Storage read from `system:system_info` with `execute` on demand, not with a long-lived observer

---

## See Also

### Main Guide
- [Deletion and Storage Management](../../../guides/best-practices/ditto.md#deletion-and-storage-management)
- [Subscription Lifecycle](../../../guides/best-practices/ditto.md#subscription-lifecycle)
- [Monitoring Storage](../../../guides/best-practices/ditto.md#monitoring-storage)
- [Applying System Parameters](../../../guides/best-practices/ditto.md#applying-system-parameters)

### Other Skills
- [query-sync](../query-sync/SKILL.md) - Subscription scope and lifecycle
- [data-modeling](../data-modeling/SKILL.md) - Deletion flag field design

### Examples
- [examples/soft-delete-relay.dart](examples/soft-delete-relay.dart) - Soft delete helpers, Variant A and Variant B subscriptions, observer filtering
- [examples/evict-subscription-management-good.dart](examples/evict-subscription-management-good.dart) - Complementary subscription and eviction, store switch
- [examples/evict-subscription-management-bad.dart](examples/evict-subscription-management-bad.dart) - Eviction anti-patterns
- [examples/ttl-eviction-small-peer.dart](examples/ttl-eviction-small-peer.dart) - Device-local time-based retention with batching
- [examples/ttl-eviction-ditto-server.dart](examples/ttl-eviction-ditto-server.dart) - Server-driven flagging and device eviction
- [examples/flag-based-eviction.dart](examples/flag-based-eviction.dart) - Flag-based eviction without subscription churn

### Reference
- [reference/deletion-patterns.md](reference/deletion-patterns.md) - Husk documents, Ditto Server deletion, eviction scheduling, storage monitoring
