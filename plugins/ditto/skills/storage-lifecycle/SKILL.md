---
name: storage-lifecycle
description: "Ditto SDK data removal and local storage management covering DELETE vs soft delete vs EVICT, tombstones and their TTL, husk documents, eviction with complementary subscriptions, retention cleanup, and storage monitoring. Use when writing Ditto DELETE or EVICT statements, soft-delete flags or retention cleanup for Ditto documents, or TOMBSTONE_TTL_HOURS, or when deleted Ditto data came back or evicted documents sync back."
---

# Ditto Storage Lifecycle

Choosing how to remove data (`DELETE`, soft delete, `EVICT`), tombstone settings, and keeping local storage bounded. Targets Ditto SDK 5.2.0; the rules are the same in every SDK.

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). These rules target SDK 5.2.0; for devices that still run 5.1.0, also apply `§ Known Issues in SDK 5.1.0`. **Note (SDK 5.1.0 and 5.2.0)** and **Note (SDK 5.1.0)** mark easy-to-miss behavior seen on those releases, with the safe pattern; **(SDK 5.1+)** / **(SDK 5.2+)** mark features introduced in that release.
- For API calls, Grep the outline of that SDK's page, `../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), with `^#{1,3} ` and read only the section you need, not the whole page; sections are named `<Topic> in <SDK>`. DQL examples: `examples/*.sql` (every SDK); API examples: `examples/<sdk>/`, with the same base names in every SDK.
- `§ <Heading>` cites the full guide: Grep the heading in `../guide/reference/best-practices/` (including `platforms/`) and `../guide/reference/knowledge/`, then read that section.
- Report each finding at the severity of its item in `§ Anti-Pattern Checklist` (the checklist decides; Grep a phrase of the item there). A rule's label below is the highest severity among the items it covers.

## Prevents

- Deleted data resurrected by devices offline longer than the tombstone TTL; a Small Peer TTL above the Ditto Server TTL
- `DELETE`/`EVICT` with `USE IDS` and no `WHERE` predicate silently removing nothing (SDK 5.1.0)
- Soft-delete filters (`isDeleted != true`) that hide documents where the flag is missing or `null`
- Soft-deleted documents excluded from subscriptions, so relays cannot pass the flag on
- Husk documents from `DELETE` racing a concurrent `UPDATE`; evicted documents syncing straight back
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
- **Shared business records** (orders, tasks, inventory) or long offline periods: soft delete, cleaned up by a synced `DELETE` (Variant A) or device-side `EVICT` (Variant B); see rule 5.
- **Storage management on edge devices**: `EVICT` with complementary subscriptions.

With a Ditto Server (formerly Big Peer), use `DELETE` for permanent removal (typically on the Ditto Server) and `EVICT` to manage storage on edge devices. If you plan to use `DELETE` in a deployment with Small Peers only, contact Ditto support to review the design.

`§ Deletion and Storage Management`, `§ Choosing DELETE, Soft Delete, or EVICT`

## Workflow

```text
- [ ] Pick DELETE, soft delete, or EVICT with the table above
- [ ] DELETE: target with WHERE _id IN :ids; every device connects within the tombstone TTL
- [ ] Soft delete: set isDeleted + deletedAt; filter with coalesce(isDeleted, false) = false
- [ ] Soft delete: keep flagged documents in the subscriptions of relaying devices; choose Variant A or B cleanup
- [ ] EVICT: cancel/narrow subscriptions, evict the exact complement, re-subscribe with the same cutoff
- [ ] Schedule eviction at most about once per day; batch large runs with LIMIT
- [ ] Verify with system:system_info (on demand) and deletion tests
```

## Rules

### 1. Target DELETE and EVICT with WHERE (CRITICAL)

`WHERE _id IN :ids` is planned as an ID scan and works on every release. On SDK 5.1.0, `DELETE` and `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) complete without an error but remove nothing (`§ Known Issues in SDK 5.1.0`).

**✅ DO**:
- Target documents with `WHERE _id = :id` or `WHERE _id IN :ids`.
- Add `RETURNING` (SDK 5.1+) when you need the removed content (undo banner, audit record); the tombstone keeps no values. Read it from the result's `items` (each document as it was before deletion), not from its mutated document IDs.

**❌ DON'T**:
- Write `DELETE FROM orders USE IDS LIST :ids` or `EVICT FROM orders USE IDS 'a'` while any device runs SDK 5.1.0.
- Use `DELETE` to free space on one device; it removes the data for every peer.

```sql
-- ✅ GOOD: Delete by ID and capture what was removed (SDK 5.1+).
-- Arguments: {"ids": ["order-1", "order-2"]}
DELETE FROM orders WHERE _id IN :ids RETURNING _id, status, total
```

`RETURNING` also accepts aggregates: `DELETE FROM orders WHERE status = 'cancelled' AND createdAt < :cutoff RETURNING COUNT(*) AS removed`.

`§ DELETE and Tombstones`, `§ Capturing deleted content with RETURNING (SDK 5.1+)`, `§ RETURNING (SDK 5.1+)` · Example: [examples/evict-subscription-management-bad.sql](examples/evict-subscription-management-bad.sql) (anti-pattern 5, EVICT form)

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
- If devices can legitimately stay offline longer than 7 days, raise `TOMBSTONE_TTL_HOURS` on the device, staying at or below the Ditto Server TTL (for 14 days: `{"TOMBSTONE_TTL_HOURS": 336}` in the system parameters of `DittoConfig`).
- Pass system parameters in the system parameters of `DittoConfig` (SDK 5.2+) on every open; they are not persisted. On SDK 5.1, run `ALTER SYSTEM` after every open, before sync starts.

**❌ DON'T**:
- Configure the Edge TTL (`TOMBSTONE_TTL_HOURS` on Small Peers) above the Ditto Server TTL. The Ditto Server always syncs documents, so tombstones that outlive its copy are sent back to it repeatedly. The Ditto Server tombstone TTL defaults to 30 days; changes to the server side go through Ditto support. <!-- lint-ignore -->
- Choose a very short TTL; the tombstone can expire before it reaches the other peers.
- Look for a tombstone-lifetime method on the SDK: the TTL is a system parameter.

Clock skew, off-hours reaping, and what else `DELETE` leaves behind (re-insert, `INITIAL DOCUMENTS`): [reference/deletion-patterns.md](reference/deletion-patterns.md#what-delete-leaves-behind).

`§ Tombstone TTL and reaping`, `§ System Parameters Reference`, `§ Applying System Parameters` · Example: [examples/ttl-eviction-small-peer.sql](examples/ttl-eviction-small-peer.sql)

### 3. Filter Soft-Deleted Documents with coalesce (CRITICAL)

In DQL, a comparison with a missing or `null` field never passes a `WHERE` clause, so `isDeleted != true` and `NOT isDeleted` silently drop every document that has no `isDeleted` field.

| Filter (`isDeleted` is `true`, `false`, `null`, or missing) | Matches |
|---|---|
| `isDeleted != true` | `false` only |
| `NOT isDeleted` | `false` only |
| `isDeleted = false` | `false` only |
| `coalesce(isDeleted, false) = false` | `false`, `null`, missing |

**✅ DO**:
- Soft delete with `UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id`, both fields in one statement; `deletedAt` is UTC ISO-8601 with a zone designator, from the same fixed-precision helper as `createdAt`. Cleanup cutoffs never match a flag without `deletedAt`.
- Write `isDeleted: false` when you create documents.
- Filter with `coalesce(isDeleted, false) = false` in every query, observer, aggregate, lookup by `_id`, and joined collection that reads the documents.
- Restore with `UPDATE orders SET isDeleted = false UNSET deletedAt WHERE _id = :id`.

**❌ DON'T**: Filter with `isDeleted != true` or `NOT isDeleted`.

**Indexes**: `coalesce(isDeleted, false) = false` alone cannot use an index on `isDeleted` (collection scan). Lead with an indexed field (`status = :status AND coalesce(...)`) or use the equivalent `isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false`; options in [reference/deletion-patterns.md](reference/deletion-patterns.md#indexing-soft-delete-filters).

`§ Soft Delete`, `§ Indexing soft-delete filters`, `§ MISSING and NULL`, `§ Timestamps` · Example: [examples/soft-delete-relay.sql](examples/soft-delete-relay.sql) (create, soft delete, restore, query helpers)

### 4. Avoid Husk Documents (CRITICAL)

When one device deletes a document while another concurrently updates it, the add-wins merge produces a *husk document*, and the document is **not** deleted, even when the `DELETE` is the later write. In SDK 5.1.0 and 5.2.0, the updated fields keep their new values (or become `null` if the deletion was later), and all other fields are **MISSING**, not `null` as Ditto's docs say.

**✅ DO**:
- Use a soft delete for data that may be edited concurrently.
- Manage edge storage with `EVICT` and perform permanent deletion on the Ditto Server.
- Coordinate workflows so the same document is not deleted and updated at the same time.
- Make the UI tolerate documents whose fields are `null` or missing if husks are possible, and keep husks out of lists with `WHERE make IS NOT MISSING AND make IS NOT NULL` on a field every live document has (`IS NOT NULL` alone is true for a missing field). <!-- lint-ignore -->
- Run the `DELETE` again after the merge to remove a husk on every device.

**❌ DON'T**: Use `DELETE` for shared records that other devices edit.

Merge outcomes and a null-tolerant list: [reference/deletion-patterns.md](reference/deletion-patterns.md#husk-documents).

`§ Husk documents`

### 5. Keep Soft-Deleted Documents in Subscriptions (HIGH)

A subscription that excludes soft-deleted documents (for example `WHERE coalesce(isDeleted, false) = false`) still delivers the flag and a later restore for documents the device holds (SDK 5.1.0 and 5.2.0), but the device cannot relay the flag for documents it did not already hold, and a `DELETE` of a flagged document never reaches it. A subscription filter does not hide documents in local results (rule 3).

**✅ DO**:
- Keep soft-deleted documents in the subscriptions of devices that relay data to others, at least for as long as a device may stay offline.
- Hide them in every local query and observer (rule 3); register and release those observers as the SDK page shows (*Store Observers in <SDK>*).
- Choose one subscription design and clean up accordingly:
  - **Variant A (whole collection or partition)**: subscribe with `SELECT * FROM orders WHERE storeId = :storeId` (includes flagged documents), owned by a long-lived service. Clean up after the retention period, once flagged documents are no longer edited, with a `DELETE` that syncs to every device, run on the Ditto Server (for example through its HTTP API) or by another authorized peer: `DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000`.
  - **Variant B (retention window)**: subscribe with `coalesce(isDeleted, false) = false OR deletedAt >= :cutoff` and evict exactly the complement (`isDeleted = true AND deletedAt < :cutoff`), cancelling the old subscription first and re-registering it with the moved cutoff. Choose a window longer than the longest expected offline period, so that other devices can still relay the flag, and move the cutoff only when you run cleanup, not on every screen change.

**❌ DON'T**:
- Subscribe with `WHERE coalesce(isDeleted, false) = false` (or any filter on the flag) alone, unless every device syncs directly with the Ditto Server and evicts flagged documents itself.
- Evict old soft-deleted documents on a device while a subscription still matches them (Variant A); they sync back.

Trade-offs and the full comparison: [reference/deletion-patterns.md](reference/deletion-patterns.md#cleaning-up-soft-deleted-documents).

`§ Soft delete, subscriptions, and cleanup`, `§ Multi-hop relay` · Examples: [examples/soft-delete-relay.sql](examples/soft-delete-relay.sql) (Variant A and B, observer filtering), `retention-service` in `examples/<sdk>/`

### 6. Evict Only Outside Every Active Subscription (HIGH)

`EVICT` removes documents from the local store only; no tombstone is created and other peers keep them. If an active subscription on this device still matches an evicted document, connected peers notice it is missing and sync it back, which can become a loop of evicting and re-syncing.

**✅ DO**:
- Cancel or narrow the affected subscriptions **before** evicting.
- Make the eviction query the exact complement of the remaining subscription (same cutoff value, `>=` in the subscription and `<` in the eviction).
- Keep subscription references in an app-level or feature-level service so you can cancel them.
- For a large boundary change (for example a store switch), data that was already being transferred can still arrive after cancelling; if the device must not keep it, run the same `EVICT` again later (for example, on the next app start or in a periodic cleanup).

**❌ DON'T**:
- Evict and then register a subscription that matches the evicted documents again (for example `SELECT * FROM orders`).
- Evict documents that an active subscription still covers.

```sql
-- ✅ GOOD: Keep the last 7 days of orders. 1. Cancel the subscription.
-- 2. Evict exactly the complement of the new subscription:
-- Arguments: {"cutoff": "2026-10-01T10:30:00.123Z"}
EVICT FROM orders WHERE createdAt < :cutoff

-- 3. Subscribe again with the moved boundary, even if the eviction failed:
-- Arguments: {"cutoff": "2026-10-01T10:30:00.123Z"}
SELECT * FROM orders WHERE createdAt >= :cutoff
```

**Flag-based eviction**: when a central component (typically the Ditto Server, which can make sure documents have synced first) sets `evictionFlag = true`, devices subscribe with `coalesce(evictionFlag, false) = false` and evict `evictionFlag = true`. The subscription never matches flagged documents, so it need not be cancelled before each eviction. Not on relays whose peers can miss the flag: they send the unflagged version back.

`§ EVICT`, `§ Time-based eviction`, `§ Flag-based eviction`, `§ Cancelling subscriptions and local data` · Examples: `retention-service` in `examples/<sdk>/` (the service), [ttl-eviction-small-peer.sql](examples/ttl-eviction-small-peer.sql), [evict-subscription-management-good.sql](examples/evict-subscription-management-good.sql), [-bad.sql](examples/evict-subscription-management-bad.sql), [flag-based-eviction.sql](examples/flag-based-eviction.sql), [ttl-eviction-ditto-server.sql](examples/ttl-eviction-ditto-server.sql)

### 7. Evict on a Schedule, in Batches (HIGH)

Each eviction triggers a resync with every connected peer, which costs network traffic and processing on those peers. (SDK 5.1+) Ditto writes a warning-level log entry when post-eviction session cleanup runs too frequently.

**✅ DO**:
- Evict on a regular schedule, no more than about once per day, at a quiet time.
- Split a large cleanup with `LIMIT` and stop when `RETURNING COUNT(*)` reports zero (first cancel or narrow every matching subscription, rule 6).
- Treat the eviction-frequency warning as a sign to evict less often.

**❌ DON'T**:
- Evict on every screen change or app resume.
- Change `DISABLE_REPLICATION_GC_ON_EVICT` (default `false`) unless profiling shows eviction-time write latency.

```sql
-- ✅ GOOD: Evict in batches of 1,000; repeat until evicted is 0.
-- Arguments: {"cutoff": "2026-10-01T10:30:00.123Z"}
EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000
RETURNING COUNT(*) AS evicted
```

Batching keeps write transactions short. It does not reduce the sync cost of eviction: run the whole batched cleanup on the usual schedule, not as many separate cleanups.

`§ Batching evictions`, `§ Eviction frequency` · Examples: [examples/ttl-eviction-small-peer.sql](examples/ttl-eviction-small-peer.sql), `retention-service` in `examples/<sdk>/`

## Checklist

DELETE:
- [ ] Targets documents with `WHERE _id = :id` / `WHERE _id IN :ids`, never `USE IDS` without a `WHERE` predicate
- [ ] Not used to free storage on one device (use `EVICT`)
- [ ] Uses `RETURNING` (SDK 5.1+) when the removed content is needed
- [ ] Not used for shared records edited concurrently (husk documents)
- [ ] Every device connects within the tombstone TTL (7 days by default), or the data uses soft delete
- [ ] `TOMBSTONE_TTL_HOURS` on devices never exceeds the Ditto Server TTL; set on every open
- [ ] Large deletions on the Ditto Server run in batches of 30,000 documents or fewer

Soft delete:
- [ ] Sets `isDeleted` and `deletedAt` (UTC, with zone); new documents get `isDeleted: false`
- [ ] Every query, observer, aggregate, and joined collection filters with `coalesce(isDeleted, false) = false` (or the index-friendly `IS MISSING OR IS NULL OR = false` form)
- [ ] Subscriptions of relaying devices keep flagged documents (Variant A: whole collection or partition; Variant B: retention window)
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

- Reference: [reference/deletion-patterns.md](reference/deletion-patterns.md) - what `DELETE` leaves behind, husks, Ditto Server deletion, soft-delete indexing and cleanup, store switch, eviction, storage monitoring
- Examples: [examples/](examples/) - one DQL file per pattern, linked from each rule; `examples/<sdk>/retention-service` for the services that run them
- Guide sections: `§ Subscription Lifecycle`, `§ Monitoring Storage`, `§ Testing Deletion and Soft Delete`
- Related skills: `query-sync` (subscriptions, `RETURNING`), `data-modeling` (flag fields, timestamps), `performance-observability` (indexes, observers)
