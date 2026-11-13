---
name: data-modeling
description: "Designs CRDT-safe Ditto documents, covering merge behavior, maps vs arrays, SET and ON ID CONFLICT upserts that merge, DQL_STRICT_MODE and REGISTER, MAP, or COUNTER declarations, relationships and JOIN, counters, document IDs, document size, and timestamps. Use when designing or reviewing a Ditto schema or collection, or when Ditto documents need arrays edited on several devices, counters or totals, document IDs, or timestamps."
---

# Ditto Data Modeling

How to shape Ditto documents so concurrent offline edits merge correctly. Targets Ditto SDK 5.2.0 with the default `DQL_STRICT_MODE = false`; the rules are the same in every SDK.

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). These rules target SDK 5.2.0; for devices that still run 5.1.0, also apply `§ Known Issues in SDK 5.1.0`. **Note (SDK 5.1.0 and 5.2.0)** and **Note (SDK 5.1.0)** mark easy-to-miss behavior seen on those releases, with the safe pattern; **(SDK 5.1+)** / **(SDK 5.2+)** mark features introduced in that release.
- For API calls, Grep the outline of that SDK's page, `../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), with `^#{1,3} ` and read only the section you need, not the whole page; sections are named `<Topic> in <SDK>`. DQL examples: `examples/*.sql` (every SDK); API examples: `examples/<sdk>/`, with the same base names in every SDK.
- `§ <Heading>` cites the full guide: Grep the heading in `../guide/reference/best-practices/` (including `platforms/`) and `../guide/reference/knowledge/`, then read that section.
- Report each finding at the severity of its item in `§ Anti-Pattern Checklist` (the checklist decides; Grep a phrase of the item there). A rule's label below is the highest severity among the items it covers.
- **Is the app deployed?** Older app versions keep writing your documents. Mark each change to stored data, fixes included, as additive or breaking (`§ Breaking and additive changes`). In a deployed app, a field that replaces another needs `§ A field that replaces another`; only an unreleased app, or a demo sharing no database with a released app, changes in place.

## Prevents

- Lost edits in arrays changed on several devices (an array is one last-writer-wins register)
- Keys that never go away because `SET obj = {...}` and `DO UPDATE` merge into maps
- Values that seem to vanish when type declarations differ between statements
- Lost increments from read-modify-write instead of `COUNTER`; derived totals that diverge
- ID collisions from sequential or timestamp-only IDs; documents over the size limits
- Zone-less timestamps that make DQL date functions return `MISSING`

## Workflow

```
Schema Design Progress:
- [ ] 1. For each field, decide the merge you need: REGISTER, MAP, COUNTER, or ATTACHMENT
- [ ] 2. Replace arrays that several devices edit with maps keyed by a stable ID
- [ ] 3. Keep DQL_STRICT_MODE = false; declare REGISTER only for objects that must never mix
- [ ] 4. Embed by default; split into a collection only per the decision guide, then JOIN locally
- [ ] 5. Remove stored derived values; keep snapshot values (price at time of sale)
- [ ] 6. Use COUNTER (declared consistently) for tallies changed concurrently
- [ ] 7. Generate collision-free IDs (UUID v4); keep display numbers separate from _id
- [ ] 8. Keep documents well under 256 KiB; move unbounded data and binaries out
- [ ] 9. Store timestamps in UTC with a zone designator
```

## Rules

### 1. Model every field for its merge (CRITICAL)

Every value is stored as a CRDT. With the default settings the type is inferred:

| You write | Stored as | Concurrent writes |
|---|---|---|
| Scalar (string, number, boolean, null) | `REGISTER` | Last writer wins (Hybrid Logical Clock); the loser is discarded silently |
| Array | `REGISTER` | The **whole array** is one value; one version wins |
| Object | `MAP` | Each key merges independently (add-wins); nested objects are nested maps |
| `APPLY f INCREMENT BY n` / `RESTART` | `COUNTER` | Increments from all devices are added together |
| Attachment | `ATTACHMENT` | Last writer wins |

Local write semantics on an existing object `{"a": 1, "b": 2}`:

| Statement | Result |
|---|---|
| `SET obj.a = 10` | `{"a": 10, "b": 2}` |
| `SET obj = {'c': 3}` | `{"a": 1, "b": 2, "c": 3}`: assigning an object **merges** |
| `SET obj = {}` | `{"a": 1, "b": 2}`: clears nothing |
| `UNSET obj.b` | `{"a": 1}`: `UNSET` is the only way to remove a key |
| `ON ID CONFLICT DO UPDATE` with `{"obj": {"c": 3}}` | `{"a": 1, "b": 2, "c": 3}`: upserts merge too |

**✅ DO**:
- Update individual fields (`UPDATE ... SET obj.field = :value`), only the ones the user changed.
- Use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports of data another system owns (it skips equal fields).
- Remove keys with `UNSET`. To replace an object, run `UNSET` then `SET` in one transaction, or declare it `REGISTER` (Rule 3). Only `REGISTER` keeps concurrent edits from mixing: after `UNSET` and `SET` the field is still a map.

**❌ DON'T**:
- Assume `SET obj = {...}` or `DO UPDATE` removes keys you left out, or clear a map with `SET obj = {}` or a scalar (`SET obj = 5`).
- Write back a stale in-memory copy with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF` (it writes every field that differs locally, old values included): either overrides a concurrent change.

`§ CRDT Types and Merge Behavior`, `§ Local Write Semantics You Must Know`, `§ Document Structure` · Example: [examples/field-level-updates.sql](examples/field-level-updates.sql) · More: [reference/common-patterns.md](reference/common-patterns.md) (conflict policies, replacing an object, `UNSET` metadata)

### 2. Use maps keyed by ID, not arrays, for data several devices edit (CRITICAL)

| Use a **map keyed by ID** when | Use an **array** when |
|---|---|
| Several devices may add, edit, or remove items | Only one device writes; others read |
| Items have a natural or synthetic unique ID | Order matters and the list is never edited concurrently |
| You update or index individual items | It is a list of scalars replaced wholesale |

```json
// ❌ BAD: concurrent edits to different items: one device's change is lost
{ "_id": "order-1", "items": [ { "productId": "p1", "quantity": 2 } ] }
// ✅ GOOD: entries merge independently; display order is a field
{ "_id": "order-1", "items": { "<item uuid>": { "productId": "p1", "quantity": 2, "position": 0 } } }
```

**✅ DO**:
- Pass a variable key as data: `INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF` with `patch = {'_id': orderId, 'items': {itemId: item}}`. Parameters bind values, not paths (`items[:key]` is a parser error).
- Remove an entry with ``UNSET items.`<key>` `` only after validating the key against a strict pattern (for example, a UUID).
- Mark entries removed (`removed = true`) when concurrent edits are likely; readers skip entries whose required fields are missing or `null`. **Note (SDK 5.1.0 and 5.2.0)**: a removal does not win over a concurrent edit; the entry stays with only the edited fields (removal first) or with them `null` (removal later).
- Move an entry by writing only its `position`, between its new neighbors; renumbering all entries loses a concurrent reorder.
- Convert an array to a map as soon as more than one device writes it, into a **new field** (`lineItems` next to `items`, in stages).

**❌ DON'T**: splice unchecked input into a query; write the map under the array's name (both then share one key).

`§ Arrays and Maps` · Example: [examples/array-to-map.sql](examples/array-to-map.sql)

### 3. Keep the default strict mode and declare types consistently (CRITICAL)

**The default is `DQL_STRICT_MODE = false`.**

| Behavior | `false` (default) | `true` |
|---|---|---|
| Undeclared objects | `MAP` (field-level merge) | `REGISTER` (whole-object replacement) |
| `SET obj.a = 1` on an undeclared object | Merges the field | Fails: `Unsupported DML operation on REGISTER field` |
| MAP / COUNTER / ATTACHMENT fields | Inferred | Must be declared in every statement |
| `SELECT` / `WHERE` on undeclared MAP / COUNTER / ATTACHMENT fields | Visible | **Invisible** |
| Secondary index use | Used | Not used (see the note) |

**Note (SDK 5.1.0 and 5.2.0)**: with `DQL_STRICT_MODE = true` the planner does not use secondary indexes (`EXPLAIN` shows a collection scan); ID lookups and full-collection `COUNT(*)` are not affected.

Choose `true` only if nearly every object needs replacement and you will declare every MAP, COUNTER, and ATTACHMENT field. Set it on every open in `DittoConfig.systemParameters` (SDK 5.2+; on 5.1, `ALTER SYSTEM` after `Ditto.open`, before sync, queries, and observers), with the same value on every peer (each peer interprets synced data with its own setting).

**✅ DO**: for a few replace-as-a-whole objects, keep the default and declare `REGISTER` **in every statement** on the field, reads included: `UPDATE COLLECTION customers (shippingAddress REGISTER) SET shippingAddress = :address WHERE _id = :id` and `SELECT * FROM COLLECTION customers (shippingAddress REGISTER) WHERE _id = :id`.

**❌ DON'T**: mix declarations for one field. Each statement reads or writes the value of its declared type, so values seem to vanish even on one device: a `REGISTER` insert followed by an undeclared `SET obj.a = 11` makes an undeclared `SELECT` return `"obj": {"a": 11}`.

`§ Strict Mode`, `§ Keep type declarations consistent` · Example: [examples/strict-mode-and-declarations.sql](examples/strict-mode-and-declarations.sql)

### 4. Use COUNTER with APPLY for concurrent tallies (CRITICAL)

Counters (`COUNTER`, and the legacy `PN_COUNTER`) are the only types that add concurrent changes together. Use `APPLY`, not `SET`, and the `COLLECTION` keyword for declarations: `APPLY f INCREMENT BY n` (integer `n`; negative to decrement), `APPLY f RESTART WITH n` (concurrent `RESTART`s: last writer wins), `APPLY f RESTART` (zero).

**✅ DO**: initialize with `INSERT INTO COLLECTION products (viewCount COUNTER) DOCUMENTS (:product)` (`INITIAL DOCUMENTS` if every device creates it) and increment with `UPDATE COLLECTION products (viewCount COUNTER) APPLY viewCount INCREMENT BY 1 WHERE _id = :id`.

**❌ DON'T**:
- `SET stock = stock - 1` (two devices both write 9 from 10; one decrement is lost).
- Initialize with an undeclared `INSERT` (stored as a REGISTER; the first `INCREMENT` starts a new counter at 0), or overwrite with `SET` (use `RESTART WITH`).
- Write a counter value while devices hold unsynced increments: `RESTART WITH`, an upsert (even `DO UPDATE_LOCAL_DIFF`), or a plain `INSERT` of another device's document discards them, even later ones (**Note (SDK 5.1.0 and 5.2.0)**). Recount only while every device is in sync, or derive the value from events.
- Use counters for unique sequence numbers, values a `COUNT(*)` can derive, or fractional amounts (integer-only; count in cents). A counter adds every change but enforces no rule ("never below zero").
- Mix `COUNTER` and `PN_INCREMENT` on one field.

**A check before a write holds on this device only.** A conditional `UPDATE`, a query before an `INSERT`, `COUNT(*) + 1`, or a transaction is not a lock, uniqueness check, or sequence across devices: both devices pass, and one claim is lost without an error. Record claims per device; a value is `_id` only for one shared entity.

`§ Counters`, `§ Checks and Claims across Devices` · Example: [examples/counter-patterns.sql](examples/counter-patterns.sql) · More: [reference/common-patterns.md](reference/common-patterns.md) (Pattern 5)

### 5. Generate collision-free document IDs (CRITICAL)

| Strategy | Use when |
|---|---|
| **UUID v4** (primary) | Almost always |
| ULID / time-ordered random ID | Rough creation-time ordering (device clocks make it approximate) |
| Composite object `{"storeId": ..., "orderId": "<uuid>"}` | Permissions or subscriptions scoped by owner, location, or tenant |
| Natural key (SKU) | Globally unique, immutable domain key |
| Generated by Ditto (omit `_id`) | Nothing needs the ID before insert; read the result's mutated document IDs |

- **Never** use sequential or timestamp-only IDs: two offline devices produce the same ID, and the documents merge into one.
- `_id` is immutable: copy to a new `_id` and remove the old document in one transaction, declaring `COUNTER`, `ATTACHMENT`, and `REGISTER` fields in both the `SELECT` and the `INSERT` (see the reference).
- Put only immutable attributes into a composite `_id`; filter and index its subfields (`_id.storeId`).
- Keep human-readable numbers (`#A-0042`) in a separate field: labels, not keys.

`§ Document IDs` · Examples: [examples/id-generation-patterns.sql](examples/id-generation-patterns.sql), `ids-and-timestamps` in `examples/<sdk>/`, [examples/composite-id-patterns.sql](examples/composite-id-patterns.sql), [examples/id-immutability-workaround.sql](examples/id-immutability-workaround.sql) · More: [reference/advanced-patterns.md](reference/advanced-patterns.md) (ID types, changing an ID, composite IDs, display numbers)

### 6. Embed by default; JOIN separate collections locally (CRITICAL)

Embed sub-entities as maps keyed by ID. `JOIN` **(SDK 5.1+)** removes the main read-side cost of separate collections, but each collection is still a separate sync unit with its own subscription, and the join key needs an index.

| Embed when the data is... | Use a separate collection when the data is... |
|---|---|
| Read together with the parent | Accessed independently of the parent |
| Owned by exactly one parent | Shared by many parents (products in many orders) |
| Small and bounded (tens of entries) | Unbounded (events, readings, messages) |
| Covered by the parent's permissions | Governed by different permissions |

Concurrent edits alone are **not** a reason to split: map entries merge.

**JOIN rules (SDK 5.1+)**: local data only (never fetches from peers); not in subscriptions (`Unsupported feature: Joining`) or on Ditto Server; qualify every field with its alias; index the inner collection's join key, or join on its `_id`, or the JOIN fails (`disallowed without appropriate index support`).

**✅ DO**:
- Subscribe to every joined collection; copy the filter key (`storeId`) into children, since subscriptions filter only on their own fields.
- Treat a missing joined document as normal (not synced yet); use `LEFT JOIN` when the parent must appear without children.
- Write a parent and children created together in one transaction; check plans with `EXPLAIN` and `ADVISE`.
- Copy a value only when it is a snapshot (price at time of sale) or a subscription filter key; otherwise reference by ID and JOIN at read time.

**❌ DON'T**: silence the index error with `USE INDEX ''` on a large collection; split a small sub-entity only because JOIN exists.

`§ Relationships: Embedding, Separate Collections, and JOIN`, `§ Joining Collections (SDK 5.1+)` · Examples: [examples/embedded-relationship.sql](examples/embedded-relationship.sql), [examples/foreign-key-join.sql](examples/foreign-key-join.sql) · More: [reference/advanced-patterns.md](reference/advanced-patterns.md) (JOIN queries, index error)

### 7. Keep documents well under the size limits (CRITICAL)

| Threshold | Default | Behavior |
|---|---|---|
| Soft limit | 256 KiB | Write succeeds; warning `exceeds recommended limit` is logged |
| Hard limit | 5 MiB | A local `INSERT` / `UPDATE` fails with the SDK's error; the stored document is unchanged |

**Note (SDK 5.1.0)**: merges are not checked against the hard limit; concurrent offline additions can produce a larger document everywhere, after which every `UPDATE` fails until `UNSET` removes data. On 5.2.0, receivers drop them; copies diverge until one is evicted, losing its changes (see the reference).

**✅ DO**: stay well below 256 KiB per stored document; store binaries as attachments; move unbounded data (history, readings, comments) to its own collection; keep the default limits. `object_size()` is approximate.

`§ Document Size Limits` · Example: [examples/document-size.sql](examples/document-size.sql) · More: [reference/common-patterns.md](reference/common-patterns.md) (causes of growth, system parameters)

### 8. Store timestamps in UTC with a zone designator and fixed precision (CRITICAL)

Store UTC with a zone designator (an ISO-8601 string ending in `Z`) or epoch milliseconds, consistently per field. Zone-less ISO strings make every DQL date function return `MISSING` silently. Clocks drift: never resolve conflicting writes with your own timestamp fields.

ISO strings sort as text only at one precision; some formatters vary it even on one device (native Dart omits zero microseconds). Write every sorted or compared timestamp with one helper that writes UTC with exactly millisecond precision (`2026-10-08T10:30:00.123Z`): `ids-and-timestamps` in `examples/<sdk>/`.

`§ Timestamps` · Examples: [examples/timestamps.sql](examples/timestamps.sql), `ids-and-timestamps` in `examples/<sdk>/`

### 9. Do not store derived values (MEDIUM)

A stored total is a separate register that devices recompute from partial views; after the merge it can match neither. Compute it at read time, in app code or DQL.

**✅ DO**: copy snapshot values, which are facts, not derivations (`unitPriceCents` into the line item when it is added); initialize flags you filter on (`isDeleted: false`) or filter with `coalesce(isDeleted, false) = false`.

**❌ DON'T**: store UI state, progress flags, or device-local paths in synced documents.

`§ Document Structure` · Example: [examples/derived-values.sql](examples/derived-values.sql) · More: [reference/common-patterns.md](reference/common-patterns.md) (document structure, field names)

## Checklist

- [ ] Each change to stored data marked additive or breaking; breaking ones versioned and rolled out in stages (deployed apps)
- [ ] Items edited by several devices live in maps keyed by stable IDs, not arrays
- [ ] No reliance on `SET obj = {...}` / `DO UPDATE` to remove keys; `UNSET` used
- [ ] User edits are field-level `UPDATE`s; upserts and re-imports use `DO UPDATE_LOCAL_DIFF`
- [ ] `DQL_STRICT_MODE` left at `false`, or applied on every launch and identical on every peer
- [ ] Each declared field (`REGISTER`, `MAP`, `COUNTER`, `ATTACHMENT`) declared the same way in every statement
- [ ] Embedded by default; separate collections justified by the decision guide
- [ ] JOINs: inner join key indexed (or `_id`), each joined collection subscribed, no JOIN in subscriptions
- [ ] No stored derived values; snapshot values copied deliberately
- [ ] Concurrent tallies use `COUNTER` with `APPLY`; `RESTART WITH` only while every device is in sync
- [ ] No lock, uniqueness check, or sequence number resting on a local check
- [ ] UUID (or composite / natural) IDs; display numbers separate from `_id`
- [ ] Shared defaults seeded with `INITIAL DOCUMENTS` (not `INSERT` or `DO UPDATE`), identical in every app version
- [ ] Documents well under 256 KiB; binaries as attachments
- [ ] Timestamps in UTC with a zone designator, written by one fixed-precision helper

## More

- Reference: [reference/common-patterns.md](reference/common-patterns.md) (conflict policies, audit logs, document structure, size), [reference/advanced-patterns.md](reference/advanced-patterns.md) (history, `INITIAL DOCUMENTS`, schema evolution, IDs, JOIN)
- Examples: [examples/](examples/) - DQL files linked from each rule; `examples/<sdk>/` for the ID and timestamp helpers
- Related skills: `query-sync` (DQL, subscriptions, observers), `storage-lifecycle` (deletion), `transactions-attachments`, `performance-observability` (indexes, EXPLAIN, ADVISE)
