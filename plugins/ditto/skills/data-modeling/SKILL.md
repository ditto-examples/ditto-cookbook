---
name: data-modeling
description: Designs CRDT-safe Ditto documents, covering merge behavior, maps vs arrays, SET and ON ID CONFLICT upserts that merge, DQL_STRICT_MODE and REGISTER, MAP, or COUNTER declarations, relationships and JOIN, counters, document IDs, document size, and timestamps. Use when designing or reviewing a Ditto schema or collection, editing arrays from several devices, adding counters or totals, generating IDs, or storing timestamps.
---

# Ditto Data Modeling

How to shape Ditto documents so concurrent offline edits merge correctly. Targets Ditto SDK 5.1.0 with the default `DQL_STRICT_MODE = false`; examples are Flutter (Dart), and the rules are the same on every platform.

## Before You Apply

- Check the project's Ditto SDK version (`ditto_live` in `pubspec.lock`, `@dittolive/ditto` in `package-lock.json`, `DittoSwift` in `Package.resolved`, `com.ditto` in Gradle files); these rules were verified with 5.1.0. **Note (SDK 5.1.0)** marks easy-to-miss 5.1.0 behavior (wrong results, lost data, crashes, hangs) and its safe pattern; on another version, confirm it (release notes, docs.ditto.live) first. **(SDK 5.1+)** marks features introduced in 5.1.
- Examples are Dart. For JavaScript, Swift, or Kotlin, translate with `§ Platform Differences` and do not port Flutter observer or transaction code one-to-one.
- `§ <Heading>` cites a section of the full guide: Grep the heading in `../guide/reference/ditto.md` and read it for the reasoning or a complete example.

## Prevents

- Lost edits in arrays changed on several devices (an array is one last-writer-wins register)
- Keys that never go away because `SET obj = {...}` and `ON ID CONFLICT DO UPDATE` merge into maps
- Values that seem to vanish when type declarations differ between statements
- Lost increments from read-modify-write instead of the `COUNTER` type
- JOIN errors and empty results (unindexed join key, JOIN in a subscription, unsynced collection)
- Derived totals that diverge from the merged data
- ID collisions from sequential or timestamp-only IDs
- Documents over the 256 KiB soft limit or the 5 MiB hard limit
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
| `SET obj = 5`, later `SET obj = {'w': 1}` | `{"a": 1, "b": 2, "w": 1}`: a scalar does not clear the map |
| `UNSET obj.b` | `{"a": 1}`: `UNSET` is the only way to remove a key |
| `UNSET obj`, then `SET obj = {'w': 1}`, in one transaction | `{"w": 1}`: clearing first replaces the object |
| `ON ID CONFLICT DO UPDATE` with `{"obj": {"c": 3}}` | `{"a": 1, "b": 2, "c": 3}`: upserts merge too |

**✅ DO**:
- Update individual fields (`UPDATE ... SET obj.field = :value`), only the ones the user changed.
- Use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports of data another system owns (it skips equal fields; nothing is written when nothing changed).
- Remove keys with `UNSET`. To replace an object, run `UNSET` then `SET` in one transaction, or declare it `REGISTER` (Rule 3). Only `REGISTER` guarantees concurrent edits never mix: after `UNSET` and `SET` the field is still a map, so another device's concurrent nested edit can merge into the new object.

**❌ DON'T**:
- Assume `SET obj = {...}` or `DO UPDATE` removes keys you left out, or clear a map with `SET obj = {}` or by assigning a scalar.
- Write back a stale in-memory copy with `DO UPDATE` (rewrites every supplied field) or `DO UPDATE_LOCAL_DIFF` (writes every field that differs locally, including an old value another device already changed). Either overrides a concurrent change.

`§ CRDT Types and Merge Behavior`, `§ Local write semantics you must know`, `§ Document Structure` · Example: [examples/field-level-updates.dart](examples/field-level-updates.dart) · More: [reference/common-patterns.md](reference/common-patterns.md) (conflict policies, replacing an object, `UNSET` metadata)

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
- Mark entries removed (`removed = true`) when concurrent edits are likely; make readers skip entries with missing or `null` required fields. **Note (SDK 5.1.0)**: a removal does not win over a concurrent edit; the entry stays with only the edited fields (removal first) or with them `null` (removal later).
- Convert an array to a map as soon as more than one device writes it, into a **new field** (`lineItems` next to the old `items`).

**❌ DON'T**: splice unchecked input into a query; write a map under the array's field name (it changes the CRDT type, so the old array and the new map coexist under the same key).

`§ Arrays and Maps` · Example: [examples/array-to-map.dart](examples/array-to-map.dart)

### 3. Keep the default strict mode and declare types consistently (CRITICAL)

**The default is `DQL_STRICT_MODE = false`.** Keep it for new apps.

| Behavior | `false` (default) | `true` |
|---|---|---|
| Undeclared objects | `MAP` (field-level merge) | `REGISTER` (whole-object replacement) |
| `SET obj.a = 1` on an undeclared object | Merges the field | Fails: `Unsupported DML operation on REGISTER field` |
| MAP / COUNTER / ATTACHMENT fields | Inferred | Must be declared in every statement |
| `SELECT` / `WHERE` on undeclared MAP / COUNTER / ATTACHMENT fields | Visible | **Invisible** |
| Secondary index use | Used | Not used (see the note) |

**Note (SDK 5.1.0)**: with `DQL_STRICT_MODE = true` the planner does not use secondary indexes (`EXPLAIN` shows a collection scan); ID lookups and full-collection `COUNT(*)` are not affected. Keep the default if you rely on indexes.

Choose `true` only when nearly every object needs replacement semantics and you will declare every MAP, COUNTER, and ATTACHMENT field everywhere. `ALTER SYSTEM` is not persisted: apply it after every `Ditto.open`, before `ditto.sync.start()`, queries, and observers, with the same value on every peer (each peer interprets synced data with its own setting).

**✅ DO**: for a few replace-as-a-whole objects, keep the default and declare `REGISTER` **in every statement** on the field, reads included: `UPDATE COLLECTION customers (shippingAddress REGISTER) SET shippingAddress = :address WHERE _id = :id` and `SELECT * FROM COLLECTION customers (shippingAddress REGISTER) WHERE _id = :id`. Keep the statements in one repository class.

**❌ DON'T**: mix declarations for one field. Each statement reads or writes the value of its declared type, so values seem to vanish even on one device: a `REGISTER` insert followed by an undeclared `SET obj.a = 11` makes an undeclared `SELECT` return `"obj": {"a": 11}`.

`§ Strict Mode`, `§ Keep type declarations consistent` · Example: [examples/strict-mode-and-declarations.dart](examples/strict-mode-and-declarations.dart)

### 4. Use COUNTER with APPLY for concurrent tallies (CRITICAL)

Counters (`COUNTER`, and the legacy `PN_COUNTER`) are the only types that add concurrent changes together. Use `APPLY`, not `SET`, and the `COLLECTION` keyword for declarations:

| Operation | Statement |
|---|---|
| Increment / decrement | `APPLY f INCREMENT BY n` (integer `n`; negative to decrement) |
| Set a value | `APPLY f RESTART WITH n` (concurrent `RESTART`s: last writer wins) |
| Reset to zero | `APPLY f RESTART` |

**✅ DO**: initialize with `INSERT INTO COLLECTION products (viewCount COUNTER) DOCUMENTS (:product)` and increment with `UPDATE COLLECTION products (viewCount COUNTER) APPLY viewCount INCREMENT BY 1 WHERE _id = :id`.

**❌ DON'T**:
- `SET stock = stock - 1` (two devices both write 9 from 10; one decrement is lost).
- Initialize with an undeclared `INSERT` (stored as a REGISTER; the first `INCREMENT` starts a new counter at 0), or overwrite with `SET` (use `RESTART WITH`).
- Recalibrate with `RESTART WITH` while other devices change the counter offline: increments the restarting device has not received yet are discarded, even later ones (**Note (SDK 5.1.0)**). Recount only while all devices are in sync, or keep recounts and changes as events and derive the value.
- Use counters for unique sequence numbers, balances that must stay valid, values a `COUNT(*)` can derive, or fractional amounts (integer-only; count in cents).
- Mix `COUNTER` and the legacy `PN_INCREMENT` operator on one field.

`§ Counters` · Example: [examples/counter-patterns.dart](examples/counter-patterns.dart)

### 5. Generate collision-free document IDs (CRITICAL)

| Strategy | Use when |
|---|---|
| **UUID v4** (primary) | Almost always |
| ULID / time-ordered random ID | Rough creation-time ordering (device clocks make it approximate) |
| Composite object `{"storeId": ..., "orderId": "<uuid>"}` | Permissions or subscriptions scoped by owner, location, or tenant |
| Natural key (SKU) | Globally unique, immutable domain key |
| Generated by Ditto (omit `_id`) | Nothing needs the ID before insert; read `result.mutatedDocumentIDs()` |

- **Never** use sequential or timestamp-only IDs: two offline devices produce the same ID, and the documents merge into one.
- Strings and objects are recommended; floats and `null` are rejected. Do not depend on the format of generated IDs.
- `_id` is immutable: copy to a new `_id` and remove the old document in one transaction, declaring `COUNTER`, `ATTACHMENT`, and `REGISTER` fields in both the `SELECT` and the `INSERT` (see the reference).
- Put only immutable attributes into a composite `_id`; filter and index its subfields (`_id.storeId`).
- Keep human-readable numbers (`#A-0042`) in a separate field: labels, not keys.

`§ Document IDs`, `§ IDs are immutable`, `§ Never use sequential or timestamp-only IDs` · Examples: [examples/id-generation-patterns.dart](examples/id-generation-patterns.dart), [examples/composite-id-patterns.dart](examples/composite-id-patterns.dart), [examples/id-immutability-workaround.dart](examples/id-immutability-workaround.dart) · More: [reference/advanced-patterns.md](reference/advanced-patterns.md) (changing an ID, composite IDs, display numbers)

### 6. Embed by default; JOIN separate collections locally (HIGH)

Embed sub-entities as maps keyed by ID. `JOIN` **(SDK 5.1+)** removes the main read-side cost of separate collections, but each collection is still a separate sync unit with its own subscription, and the join key needs an index.

| Embed when the data is... | Use a separate collection when the data is... |
|---|---|
| Read together with the parent | Accessed independently of the parent |
| Owned by exactly one parent | Shared by many parents (products in many orders) |
| Small and bounded (tens of entries) | Unbounded (events, readings, messages) |
| Covered by the parent's permissions | Governed by different permissions |
| Edited by the same writers | Written by different writers or systems |

Concurrent edits alone are **not** a reason to split: map entries merge.

**JOIN rules (SDK 5.1+)**: local data only (never fetches from peers); not allowed in subscriptions or on Ditto Server; qualify every field with its alias; the inner collection needs an index on the join key (`CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)`), or join on its `_id`. Without a usable index the JOIN fails with `Joining to "<alias>" disallowed without appropriate index support`.

**✅ DO**:
- Subscribe to every joined collection (app or feature scope); copy the filter key (`storeId`) into children, since subscriptions filter only on their own fields.
- Treat a missing joined document as normal (not synced yet); use `LEFT JOIN` when the parent must appear without children.
- Write a parent and children created together in one transaction; check plans with `EXPLAIN` and `ADVISE`.
- Copy a value only when it is a snapshot (price at time of sale) or a subscription filter key; otherwise reference by ID and JOIN at read time.

**❌ DON'T**:
- Put a JOIN in `registerSubscription` (rejected: `Unsupported feature: Joining`).
- Silence the index error with `USE INDEX ''` on a large collection.
- Split a small, bounded, single-owner sub-entity only because JOIN exists.

`§ Relationships: Embedding, Separate Collections, and JOIN`, `§ Joining Collections (SDK 5.1+)` · Examples: [examples/embedded-relationship.dart](examples/embedded-relationship.dart), [examples/foreign-key-join.dart](examples/foreign-key-join.dart) · More: [reference/advanced-patterns.md](reference/advanced-patterns.md) (JOIN queries, index error, subscriptions)

### 7. Do not store derived values (HIGH)

A stored total is a separate register that devices recompute from partial views; after the merge it can match neither. Compute it at read time, in Dart or DQL (`SELECT COUNT(*) AS openOrders FROM orders WHERE status = 'open'`).

**✅ DO**: copy snapshot values, which are facts, not derivations (`unitPriceCents` into the line item when it is added); initialize flags you filter on (`isDeleted: false`) or filter with `coalesce(isDeleted, false) = false`.

**❌ DON'T**: store UI state, progress flags, or device-local paths in synced documents.

`§ Document Structure` · Example: [examples/derived-values.dart](examples/derived-values.dart) · More: [reference/common-patterns.md](reference/common-patterns.md) (document structure, field names)

### 8. Keep documents well under the size limits (HIGH)

| Threshold | Default | Behavior |
|---|---|---|
| Soft limit | 256 KiB | Write succeeds; warning `exceeds recommended limit` is logged |
| Hard limit | 5 MiB | A local `INSERT` / `UPDATE` fails (`DittoException`); the stored document is unchanged |

**Note (SDK 5.1.0)**: merges are not checked against the hard limit; concurrent offline additions can produce a larger document everywhere, after which every `UPDATE` fails until `UNSET` removes data.

**✅ DO**: stay well below 256 KiB per stored document; store binaries as attachments; move unbounded data (history, readings, comments) to its own collection; keep the default limits. `object_size()` is approximate, so leave headroom; to shrink an oversized document, move large values out and `UNSET` them.

`§ Document Size Limits` · Example: [examples/document-size.dart](examples/document-size.dart) · More: [reference/common-patterns.md](reference/common-patterns.md) (causes of growth, system parameters)

### 9. Store timestamps in UTC with a zone designator and fixed precision (MEDIUM)

Store UTC with a zone designator (`DateTime.now().toUtc().toIso8601String()`) or epoch milliseconds, consistently per field. Zone-less ISO strings make every DQL date function return `MISSING` silently. Clocks drift: never resolve conflicting writes with your own timestamp fields.

ISO strings sort as text only at one precision. Native Dart emits microseconds (`...00.123456Z`) but omits them when zero (`...00.123Z`), and the web emits milliseconds, so even one device mixes precisions. Write every sorted or compared timestamp with one fixed-precision helper:

```dart
/// ISO-8601 UTC string with exactly millisecond precision.
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}
```

`§ Timestamps` · Example: [examples/timestamps.dart](examples/timestamps.dart)

## Checklist

- [ ] Items edited by several devices live in maps keyed by stable IDs, not arrays
- [ ] No reliance on `SET obj = {...}` / `DO UPDATE` to remove keys; `UNSET` used
- [ ] User edits are field-level `UPDATE`s; upserts and re-imports use `DO UPDATE_LOCAL_DIFF`
- [ ] `DQL_STRICT_MODE` left at `false`, or applied on every launch and identical on every peer
- [ ] Each declared field (`REGISTER`, `MAP`, `COUNTER`, `ATTACHMENT`) declared the same way in every statement
- [ ] Embedded by default; separate collections justified by the decision guide
- [ ] JOINs: inner join key indexed (or `_id`), each joined collection subscribed, no JOIN in subscriptions
- [ ] No stored derived values; snapshot values copied deliberately
- [ ] Concurrent tallies use `COUNTER` with `APPLY`
- [ ] Counters recalibrated with `RESTART WITH` only while every device that changes them is in sync
- [ ] UUID (or composite / natural) IDs; display numbers separate from `_id`
- [ ] Shared defaults seeded with `INITIAL DOCUMENTS` (not `INSERT` or `DO UPDATE`), identical in every app version
- [ ] Documents well under 256 KiB; binaries as attachments
- [ ] Timestamps in UTC with a zone designator, written by one fixed-precision helper

## More

- Reference: [reference/common-patterns.md](reference/common-patterns.md) - conflict policies, event history and audit logs, document structure, field names, document size
- Reference: [reference/advanced-patterns.md](reference/advanced-patterns.md) - current state plus history, `INITIAL DOCUMENTS`, schema evolution, IDs, JOIN
- Examples: [examples/](examples/) - Dart files linked from each rule and reference pattern
- Guide sections: `§ Data Modeling`, `§ Writing Data`, `§ Transactions`, `§ Deletion and Storage Management`
- Related skills: `query-sync` (DQL, subscriptions, observers), `storage-lifecycle` (DELETE, soft delete, EVICT), `transactions-attachments` (transactions, attachments), `performance-observability` (indexes, EXPLAIN, ADVISE)
