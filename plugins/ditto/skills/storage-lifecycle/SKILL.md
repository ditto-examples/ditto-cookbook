---
name: storage-lifecycle
description: Ditto SDK data removal and local storage management covering DELETE vs soft delete vs EVICT, tombstones and their TTL, husk documents, eviction with complementary subscriptions, retention cleanup, and storage monitoring. Use when writing DELETE or EVICT statements, isDeleted or deletedAt flags, or retention policies, when setting TOMBSTONE_TTL_HOURS, or when deleted data came back or evicted documents sync back.
---

# Ditto Storage Lifecycle

Choosing how to remove data (`DELETE`, soft delete, `EVICT`), tombstone settings, and keeping local storage bounded. Targets Ditto SDK 5.1.0; examples are Flutter (Dart), and the DQL rules apply to every SDK.

## Before You Apply

- Check the project's Ditto SDK version (`ditto_live` in `pubspec.lock`, `@dittolive/ditto` in `package-lock.json`, `DittoSwift` in `Package.resolved`, `com.ditto` in Gradle files); these rules were verified with 5.1.0. **Note (SDK 5.1.0)** marks easy-to-miss 5.1.0 behavior (wrong results, lost data, crashes, hangs) and its safe pattern; on another version, confirm it (release notes, docs.ditto.live) first. **(SDK 5.1+)** marks features introduced in 5.1.
- Examples are Dart. For JavaScript, Swift, or Kotlin, translate with `§ Platform Differences` and do not port Flutter observer or transaction code one-to-one.
- `§ <Heading>` cites a section of the full guide: Grep the heading in `../guide/reference/ditto.md` and read it for the reasoning or a complete example.

## Prevents

- Deleted data resurrected by devices that stay offline longer than the tombstone TTL (7 days by default)
- Small Peer tombstone TTL (`TOMBSTONE_TTL_HOURS`) configured above the Ditto Server TTL
- `DELETE`/`EVICT` with `USE IDS` and no `WHERE` predicate silently removing nothing (SDK 5.1.0)
- Soft-delete filters (`isDeleted != true`) that hide documents where the flag is missing or `null`
- Soft-deleted documents dropped from subscriptions, so later changes and restores never arrive
- Evicted documents syncing straight back because a subscription still matches them
- Husk documents caused by `DELETE` racing a concurrent `UPDATE`
- Evicting too often and overloading connected peers with resyncs

## Choosing a Removal Strategy

| Requirement | `DELETE` | Soft delete | `EVICT` |
|---|---|---|---|
| Remove data for every peer | ✅ (tombstone) | ✅ (flag, then cleanup) | ❌ (local only) |
| Safe when devices stay offline longer than the tombstone TTL (7 days by default) | ❌ (data can be resurrected) | ✅ | ✅ (other peers are unaffected) |
| Safe with concurrent updates on other devices | ❌ (husk documents) | ✅ | ✅ |
| Can be undone | ❌ | ✅ | ✅ (data syncs back if a subscription matches it again) |
| Frees local storage | ✅ (values immediately; tombstones after reaping) | ❌ (until cleanup) | ✅ (immediately) |
| Extra query complexity | None | Every query filters the flag | Subscription and eviction scopes must be complementary |

- **Data owned by one user and rarely edited concurrently**, in a deployment where devices sync regularly: `DELETE`.
- **Shared business records** (orders, tasks, inventory) or long offline periods: soft delete, cleaned up by a synced `DELETE` (Variant A) or device-side `EVICT` (Variant B); see rule 4.
- **Storage management on edge devices**: `EVICT` with complementary subscriptions.

With a Ditto Server (formerly Big Peer), use `DELETE` for permanent removal (typically on the Ditto Server) and `EVICT` to manage storage on edge devices. If you plan to use `DELETE` in a deployment with Small Peers only, contact Ditto support to review the design.

`§ Deletion and Storage Management`, `§ Choosing DELETE, Soft Delete, or EVICT`

## Workflow

```text
- [ ] Pick DELETE, soft delete, or EVICT with the table above
- [ ] DELETE: target with WHERE _id IN :ids; every device connects within the tombstone TTL
- [ ] Soft delete: set isDeleted + deletedAt; filter with coalesce(isDeleted, false) = false
- [ ] Soft delete: keep flagged documents in the subscription; choose Variant A or B cleanup
- [ ] EVICT: cancel/narrow subscriptions, evict the exact complement, re-subscribe with the same cutoff
- [ ] Schedule eviction at most about once per day; batch large runs with LIMIT
- [ ] Verify with system:system_info (on demand) and deletion tests
```

## Rules

### 1. Target DELETE and EVICT with WHERE (CRITICAL)

> **Note (SDK 5.1.0):** `DELETE` and `EVICT` statements that use `USE IDS` without a `WHERE` predicate (no `WHERE` clause, or `WHERE true`) complete without an error but remove nothing. Use `WHERE _id IN :ids` instead; it is planned as an ID scan, so it is just as efficient.

**✅ DO**:
- Target documents with `WHERE _id = :id` or `WHERE _id IN :ids`.
- Add `RETURNING` (SDK 5.1+) when you need the removed content (undo banner, audit record). It returns the removed content from the same atomic statement; the tombstone keeps no values. Read the removed documents from `result.items` (each holds the document as it was before deletion), not from `mutatedDocumentIDs()`.

**❌ DON'T**:
- Write `DELETE FROM orders USE IDS LIST :ids` or `EVICT FROM orders USE IDS 'a'`.
- Use `DELETE` to free space on one device; it removes the data for every peer.

```dart
// ✅ GOOD: Delete by ID and capture what was removed (SDK 5.1+).
final result = await ditto.store.execute(
  'DELETE FROM orders WHERE _id IN :ids RETURNING _id, status, total',
  arguments: {'ids': orderIds},
);
final removed = result.items.map((item) => item.value).toList();
```

`RETURNING` also accepts aggregates: `DELETE FROM orders WHERE status = 'cancelled' AND createdAt < :cutoff RETURNING COUNT(*) AS removed`.

`§ DELETE and Tombstones`, `§ Capturing deleted content with RETURNING (SDK 5.1+)`, `§ RETURNING (SDK 5.1+)` · Example: [examples/evict-subscription-management-bad.dart](examples/evict-subscription-management-bad.dart) (anti-pattern 5, EVICT form)

### 2. Respect the Tombstone TTL (CRITICAL)

`DELETE` leaves a tombstone (document ID, metadata such as the deletion time, and the field names; no values). Each device reaps expired tombstones periodically. A device that stays offline longer than the TTL can reconnect after every other peer has reaped the tombstone and share its old copy again ("zombie data").

| System parameter | Default | Meaning |
|---|---|---|
| `TOMBSTONE_TTL_ENABLED` | `true` | Expired tombstones are removed automatically |
| `TOMBSTONE_TTL_HOURS` | `168` (7 days) | Age after which a tombstone expires on this device |
| `DAYS_BETWEEN_REAPING` | `1` | Days between reaping runs |
| `TOMBSTONE_REAP_BATCH_SIZE` (SDK 5.1+) | `10000` | Expired tombstones are removed in bounded batches |

Inspect with `SHOW ALL LIKE '%tombstone%'`.

**✅ DO**:
- Make sure every device connects within the tombstone TTL, or use a soft delete for that data.
- If devices can legitimately stay offline longer than 7 days, raise `TOMBSTONE_TTL_HOURS` on the device, staying at or below the Ditto Server TTL (for 14 days: `ALTER SYSTEM SET TOMBSTONE_TTL_HOURS = 336`).
- Apply `ALTER SYSTEM` settings after every `Ditto.open` and before `ditto.sync.start()`; they are not persisted.

**❌ DON'T**:
- Configure the Edge TTL (`TOMBSTONE_TTL_HOURS` on Small Peers) above the Ditto Server TTL. The Ditto Server always syncs documents, so tombstones that outlive its copy are sent back to it repeatedly. The Ditto Server tombstone TTL defaults to 30 days; changes to the server side go through Ditto support. <!-- lint-ignore -->
- Choose a very short TTL; the tombstone can expire before it reaches the other peers.
- Look for a tombstone-lifetime method on the SDK: the TTL is a system parameter, set with `ALTER SYSTEM`.

Clock skew, off-hours reaping, and what else `DELETE` leaves behind (re-insert, `INITIAL DOCUMENTS`): [reference/deletion-patterns.md](reference/deletion-patterns.md#what-delete-leaves-behind).

`§ Tombstone TTL and reaping`, `§ System Parameters Reference`, `§ Applying System Parameters` · Example: [examples/ttl-eviction-small-peer.dart](examples/ttl-eviction-small-peer.dart)

### 3. Filter Soft-Deleted Documents with coalesce (CRITICAL)

In DQL, a comparison with a missing or `null` field never passes a `WHERE` clause, so `isDeleted != true` and `NOT isDeleted` silently drop every document that has no `isDeleted` field.

| Filter (`isDeleted` is `true`, `false`, `null`, or missing) | Matches |
|---|---|
| `isDeleted != true` | `false` only |
| `NOT isDeleted` | `false` only |
| `isDeleted = false` | `false` only |
| `coalesce(isDeleted, false) = false` | `false`, `null`, missing |

**✅ DO**:
- Soft delete with `UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id`; `deletedAt` is UTC ISO-8601 with a zone designator, from the same fixed-precision helper as `createdAt` (it is compared with cleanup cutoffs).
- Write `isDeleted: false` when you create documents.
- Filter with `coalesce(isDeleted, false) = false`.
- Restore with `UPDATE orders SET isDeleted = false UNSET deletedAt WHERE _id = :id`.

**❌ DON'T**: Filter with `isDeleted != true` or `NOT isDeleted`.

**Indexes**: `coalesce(isDeleted, false) = false` alone cannot use an index on `isDeleted` (collection scan). Lead with an indexed field (`status = :status AND coalesce(...)`) or use the equivalent `isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false`; options in [reference/deletion-patterns.md](reference/deletion-patterns.md#indexing-soft-delete-filters).

`§ Soft Delete`, `§ Indexing soft-delete filters`, `§ MISSING and NULL`, `§ Timestamps` · Example: [examples/soft-delete-relay.dart](examples/soft-delete-relay.dart) (create, soft delete, restore, query helpers)

### 4. Keep Soft-Deleted Documents in Subscriptions (CRITICAL)

The deletion flag is itself a change that every device must receive. A subscription that excludes soft-deleted documents (for example `WHERE coalesce(isDeleted, false) = false`) stops requesting a document as soon as it is flagged. In SDK 5.1.0 the flagging update itself still reached such devices, but later changes to the flagged document, including a restore (`isDeleted = false`), did not; keep restorable documents inside the subscription. Devices that already have the document keep it (cancelling or narrowing a subscription never deletes local data), and a subscription filter does not hide documents in local results: every local query and observer must filter flagged documents itself.

**✅ DO**:
- Keep soft-deleted documents inside the subscription at least until every device has received the flag.
- Hide them in local queries and observers with `coalesce(isDeleted, false) = false`. Observers use the `changes` stream pattern (register without `onChange`, listen to `changes`, cancel both in `dispose()`); see `§ Store Observers in Flutter`.
- Choose one subscription design and clean up accordingly:
  - **Variant A (whole collection or partition)**: subscribe with `SELECT * FROM orders WHERE storeId = :storeId` (includes flagged documents), owned by a long-lived service. Clean up after the retention period, once flagged documents are no longer edited, with a `DELETE` that syncs to every device, run on the Ditto Server (for example through its HTTP API) or by another authorized peer: `DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000`.
  - **Variant B (retention window)**: subscribe with `coalesce(isDeleted, false) = false OR deletedAt >= :cutoff` and evict exactly the complement (`isDeleted = true AND deletedAt < :cutoff`), cancelling the old subscription first and re-registering it with the moved cutoff. Choose a window longer than the longest expected offline period, and move the cutoff only when you run cleanup, not on every screen change.

**❌ DON'T**:
- Subscribe with `WHERE coalesce(isDeleted, false) = false` (or any filter on the flag) alone.
- Evict old soft-deleted documents on a device while a subscription still matches them (Variant A); they sync back.

Trade-offs and the full comparison: [reference/deletion-patterns.md](reference/deletion-patterns.md#cleaning-up-soft-deleted-documents).

`§ Soft delete, subscriptions, and cleanup`, `§ Multi-hop relay` · Example: [examples/soft-delete-relay.dart](examples/soft-delete-relay.dart) (Variant A and B, observer filtering)

### 5. Evict Only Outside Every Active Subscription (CRITICAL)

`EVICT` removes documents from the local store only; no tombstone is created and other peers keep them. If an active subscription on this device still matches an evicted document, connected peers notice it is missing and sync it back, which can become a loop of evicting and re-syncing.

**✅ DO**:
- Cancel or narrow the affected subscriptions **before** evicting.
- Make the eviction query the exact complement of the remaining subscription (same cutoff value, `>=` in the subscription and `<` in the eviction).
- Keep subscription references in an app-level or feature-level service so you can cancel them.
- For a large boundary change (for example a store switch), data that was already being transferred can still arrive after cancelling; if the device must not keep it, run the same `EVICT` again later (for example, on the next app start or in a periodic cleanup).

**❌ DON'T**:
- Evict and then register a subscription that matches the evicted documents again (for example `SELECT * FROM orders`).
- Evict documents that an active subscription still covers.

```dart
// ✅ GOOD: Keep the last 7 days of orders (from OrderRetention.evictExpired).
_subscription?.cancel(); // 1. Stop asking peers for these documents.
try {
  // 2. Evict exactly the complement of the new subscription.
  await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt < :cutoff',
    arguments: {'cutoff': cutoff},
  );
} finally {
  // 3. Subscribe again with the moved boundary, even if the eviction failed.
  _subscription = ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE createdAt >= :cutoff',
    arguments: {'cutoff': cutoff},
  );
}
```

**Flag-based eviction**: when a central component (typically the Ditto Server, which can make sure documents have synced first) sets `evictionFlag = true`, devices subscribe with `coalesce(evictionFlag, false) = false` and evict `evictionFlag = true`. The subscription never matches flagged documents, so it does not need to be cancelled before each eviction.

`§ EVICT`, `§ Time-based eviction`, `§ Flag-based eviction`, `§ Cancelling subscriptions and local data` · Examples: [ttl-eviction-small-peer.dart](examples/ttl-eviction-small-peer.dart) (full `OrderRetention`), [evict-subscription-management-good.dart](examples/evict-subscription-management-good.dart), [-bad.dart](examples/evict-subscription-management-bad.dart), [flag-based-eviction.dart](examples/flag-based-eviction.dart), [ttl-eviction-ditto-server.dart](examples/ttl-eviction-ditto-server.dart)

### 6. Avoid Husk Documents (HIGH)

When one device deletes a document while another concurrently updates it, the add-wins merge produces a *husk document*, and the document is **not** deleted, even when the `DELETE` is the later write. In SDK 5.1.0, the updated fields keep their new values (or become `null` if the deletion was later), and all other fields are **MISSING**, not `null` as Ditto's docs say.

**✅ DO**:
- Use a soft delete for data that may be edited concurrently.
- Manage edge storage with `EVICT` and perform permanent deletion on the Ditto Server.
- Coordinate workflows so the same document is not deleted and updated at the same time.
- Make the UI tolerate documents whose fields are `null` or missing if husks are possible, and keep husks out of lists with `WHERE make IS NOT MISSING AND make IS NOT NULL` on a field every live document has (`IS NOT NULL` alone is true for a missing field). <!-- lint-ignore -->
- Run the `DELETE` again after the merge to remove a husk on every device.

**❌ DON'T**: Use `DELETE` for shared records that other devices edit.

Merge outcomes and a null-tolerant widget: [reference/deletion-patterns.md](reference/deletion-patterns.md#husk-documents).

`§ Husk documents`

### 7. Evict on a Schedule, in Batches (HIGH)

Each eviction triggers a resync with every connected peer, which costs network traffic and processing on those peers. (SDK 5.1+) Ditto writes a warning-level log entry when post-eviction session cleanup runs too frequently.

**✅ DO**:
- Evict on a regular schedule, no more than about once per day, at a quiet time.
- Split a large cleanup with `LIMIT` and stop when `RETURNING COUNT(*)` reports zero (first cancel or narrow every matching subscription, rule 5).
- Treat the eviction-frequency warning as a sign to evict less often.

**❌ DON'T**:
- Evict on every screen change or app resume.
- Change `DISABLE_REPLICATION_GC_ON_EVICT` (default `false`) unless profiling shows eviction-time write latency.

```dart
// ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict.
var total = 0;
while (true) {
  final result = await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 '
    'RETURNING COUNT(*) AS evicted',
    arguments: {'cutoff': cutoff},
  );
  final evicted = result.items.first.value['evicted'] as int;
  total += evicted;
  if (evicted == 0) break;
}
```

Batching keeps write transactions short. It does not reduce the sync cost of eviction: run the whole batched cleanup on the usual schedule, not as many separate cleanups.

`§ Batching evictions`, `§ Eviction frequency` · Example: [examples/ttl-eviction-small-peer.dart](examples/ttl-eviction-small-peer.dart)

## Checklist

DELETE:
- [ ] Targets documents with `WHERE _id = :id` / `WHERE _id IN :ids`, never `USE IDS` without a `WHERE` predicate
- [ ] Not used to free storage on one device (use `EVICT`)
- [ ] Uses `RETURNING` (SDK 5.1+) when the removed content is needed
- [ ] Not used for shared records edited concurrently (husk documents)
- [ ] Every device connects within the tombstone TTL (7 days by default), or the data uses soft delete
- [ ] `TOMBSTONE_TTL_HOURS` on devices never exceeds the Ditto Server TTL; applied after every `Ditto.open`
- [ ] Large deletions on the Ditto Server run in batches of 30,000 documents or fewer

Soft delete:
- [ ] Sets `isDeleted` and `deletedAt` (UTC, with zone); new documents get `isDeleted: false`
- [ ] Filters with `coalesce(isDeleted, false) = false` (or the index-friendly `IS MISSING OR IS NULL OR = false` form)
- [ ] Subscriptions keep flagged documents (Variant A: whole collection or partition; Variant B: retention window)
- [ ] Old flagged documents are cleaned up (Variant A: synced `DELETE`; Variant B: device-side `EVICT` of the complement)

EVICT:
- [ ] Affected subscriptions are cancelled or narrowed before evicting
- [ ] Eviction query is the exact complement of the remaining subscriptions
- [ ] No re-subscription that matches the evicted documents
- [ ] Runs on a schedule, at most about once per day; large runs use `LIMIT`
- [ ] Subscription references are kept in a long-lived service

Monitoring:
- [ ] Storage read from `system:system_info` with `execute` on demand, not with a long-lived observer

## More

- Reference: [reference/deletion-patterns.md](reference/deletion-patterns.md) - what `DELETE` leaves behind, husks, Ditto Server deletion, soft-delete indexing and cleanup, store switch, eviction scheduling, storage monitoring (`system:system_info`)
- Examples: [examples/](examples/) - one Dart file per pattern; each rule links its file
- Guide sections: `§ Subscription Lifecycle`, `§ Monitoring Storage`, `§ Testing Deletion and Soft Delete`
- Related skills: `query-sync` (subscription scope and lifecycle, `RETURNING`), `data-modeling` (deletion flag field design, timestamps), `performance-observability` (indexes, `ADVISE`/`EXPLAIN`, observers)
