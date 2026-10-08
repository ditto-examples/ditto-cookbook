---
name: ditto-data-modeling
description: |
  CRDT-safe document design for Ditto SDK 5.1: merge behavior, maps vs arrays, strict mode, relationships (embedding, separate collections, JOIN), IDs, counters, size limits, and timestamps.

  CRITICAL ISSUES PREVENTED:
  - Silent data loss from arrays edited on several devices (an array is one last-writer-wins register)
  - Keys that never go away because SET obj = {...} and ON ID CONFLICT DO UPDATE merge into maps
  - Values that seem to vanish when type declarations (REGISTER, MAP, COUNTER) differ between statements
  - Lost increments from read-modify-write instead of the COUNTER type
  - JOIN errors and empty results (missing index on the join key, JOIN in a subscription, unsynced collections)
  - Derived totals that diverge from the merged data
  - ID collisions from sequential or timestamp-only IDs
  - Documents over the 256 KiB soft limit or the 5 MiB hard limit
  - Zone-less timestamps that make DQL date functions return MISSING

  TRIGGERS:
  - Designing or reviewing document schemas and collections
  - Arrays of objects that several devices edit (line items, participants, checklists)
  - Assigning objects with SET or upserting with ON ID CONFLICT
  - Choosing between embedding, separate collections, and JOIN
  - Changing DQL_STRICT_MODE or declaring field types
  - Counters (likes, views, inventory), totals, or balances
  - Event history, audit logs, status transitions
  - Generating document IDs or display numbers
  - Large documents, binary data, growing maps
  - Storing or comparing timestamps

  PLATFORMS: Flutter (Dart), JavaScript, Swift, Kotlin (CRDT and DQL rules are the same on every platform)
---

# Ditto Data Modeling Skill

Actionable patterns extracted from the [Data Modeling](../../../guides/best-practices/ditto.md#data-modeling) section of the Ditto best practices guide. The guide is the source of truth; follow its links for details. Everything here targets SDK 5.1.0 with the default `DQL_STRICT_MODE = false`.

## Table of Contents

- [When This Skill Applies](#when-this-skill-applies)
- [Workflow: Designing a Document Schema](#workflow-designing-a-document-schema)
- [Critical Patterns](#critical-patterns)
  - [1. Model Every Field for Its Merge](#1-model-every-field-for-its-merge)
  - [2. Maps Keyed by ID, Not Arrays](#2-maps-keyed-by-id-not-arrays)
  - [3. Strict Mode and Type Declarations](#3-strict-mode-and-type-declarations)
  - [4. Relationships: Embedding, Separate Collections, and JOIN](#4-relationships-embedding-separate-collections-and-join)
  - [5. Do Not Store Derived Values](#5-do-not-store-derived-values)
  - [6. Counters](#6-counters)
  - [7. Document IDs](#7-document-ids)
  - [8. Document Size Limits](#8-document-size-limits)
  - [9. Timestamps](#9-timestamps)
- [Quick Reference Checklist](#quick-reference-checklist)
- [Examples](#examples)
- [See Also](#see-also)

---

## When This Skill Applies

- A document schema is designed or reviewed, or a new collection is added.
- Several devices may modify the same data while offline (always assume they will).
- Code assigns whole objects (`SET obj = :obj`, `ON ID CONFLICT DO UPDATE`) or edits arrays.
- Related data is split across collections, or a `JOIN` is written.
- Code declares field types (`COLLECTION t (f REGISTER)`) or changes `DQL_STRICT_MODE`.
- A field is incremented, totaled, or used as an ID or timestamp.

The rules are the same on every platform. Examples use Flutter (`import 'package:ditto_live/ditto_live.dart';`).

---

## Workflow: Designing a Document Schema

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

---

## Critical Patterns

### 1. Model Every Field for Its Merge

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

**✅ DO:**
- Update individual fields: `UPDATE ... SET obj.field = :value`.
- When writing a full in-memory copy, use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` (writes only differing fields; no-op when nothing changed).
- Remove keys with `UNSET`. To replace an object, run `UNSET` then `SET` in one transaction, or declare the field as `REGISTER` (see [Strict Mode and Type Declarations](#3-strict-mode-and-type-declarations)).

**❌ DON'T:**
- Assume `SET obj = {...}` or `DO UPDATE` removes keys you left out.
- Use `DO UPDATE` to save a stale copy: it rewrites every supplied field and can override a concurrent change.
- Clear a map with `SET obj = {}` or by assigning a scalar.

> **Note:** `UNSET` creates removal metadata. Unsetting a very large number of dynamically generated keys over time can degrade performance; unsetting the parent field (or deleting the document) mitigates the accumulation.

```dart
// ✅ GOOD: Replace a MAP value: clear it, then write it, atomically.
Future<void> replaceShippingAddress(
  Ditto ditto,
  String orderId,
  Map<String, dynamic> address,
) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders UNSET shippingAddress WHERE _id = :id',
      arguments: {'id': orderId},
    );
    await tx.execute(
      'UPDATE orders SET shippingAddress = :address WHERE _id = :id',
      arguments: {'id': orderId, 'address': address},
    );
  }, hint: 'replaceShippingAddress');
}
```

Guide: [CRDT Types and Merge Behavior](../../../guides/best-practices/ditto.md#crdt-types-and-merge-behavior), [Document Structure](../../../guides/best-practices/ditto.md#document-structure). Example: [field-level-updates.dart](examples/field-level-updates.dart).

---

### 2. Maps Keyed by ID, Not Arrays

| Use a **map keyed by ID** when | Use an **array** when |
|---|---|
| Several devices may add, edit, or remove items | Only one device writes; others read |
| Items have a natural or synthetic unique ID | Order matters and the list is never edited concurrently |
| You update or index individual items | It is a list of scalars replaced wholesale |

```json
// ❌ BAD: concurrent edits to different items: one device's change is lost
{ "_id": "order-1", "items": [ { "productId": "p1", "quantity": 2 } ] }

// ✅ GOOD: entries merge independently; display order is a field
{ "_id": "order-1",
  "items": { "9b2f6c1e-4d0a-4f7e-8a51-3c2d1e0f9a87": { "productId": "p1", "quantity": 2, "position": 0 } } }
```

DQL parameters bind values, not paths (`items[:key]` is a parser error). With a variable key:

```dart
// ✅ GOOD: Add or update one entry; the key travels as data.
Future<void> upsertOrderItem(
  Ditto ditto,
  String orderId,
  String itemId,
  Map<String, dynamic> item,
) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': orderId,
        'items': {itemId: item},
      },
    },
  );
}
```

To remove an entry, use ``UNSET items.`<key>` `` after validating the key against a strict pattern (for example, a UUID) before placing it inside backticks; never splice unchecked input into a query. You can convert arrays to maps incrementally, as soon as you know more than one device writes them.

Guide: [Arrays and Maps](../../../guides/best-practices/ditto.md#arrays-and-maps). Example: [array-to-map.dart](examples/array-to-map.dart).

---

### 3. Strict Mode and Type Declarations

**The default is `DQL_STRICT_MODE = false`.** Keep it for new apps.

| Behavior | `false` (default) | `true` |
|---|---|---|
| Undeclared objects | `MAP` (field-level merge) | `REGISTER` (whole-object replacement) |
| `SET obj.a = 1` on an undeclared object | Merges the field | Fails: `Unsupported DML operation on REGISTER field` |
| MAP / COUNTER / ATTACHMENT fields | Inferred | Must be declared in every statement |
| `SELECT` / `WHERE` on undeclared MAP / COUNTER / ATTACHMENT fields | Visible | **Invisible** |
| Index use | Used | Not used (see the note) |

> **Note (SDK 5.1.0):** With `DQL_STRICT_MODE = true`, the query planner does not use indexes (`EXPLAIN` shows a full scan). Keep the default if you rely on indexes.

Choose `true` rarely: only when nearly every object needs replacement semantics and you will declare every MAP, COUNTER, and ATTACHMENT field everywhere. `ALTER SYSTEM` is not persisted: apply it after every `Ditto.open`, before `ditto.sync.start()`. Use the same value on every peer; each peer interprets synced data with its own setting.

For a few replace-as-a-whole objects, keep the default and declare `REGISTER` **in every statement** that touches the field:

```sql
UPDATE COLLECTION customers (shippingAddress REGISTER)
SET shippingAddress = :address
WHERE _id = :id
```

```sql
SELECT * FROM COLLECTION customers (shippingAddress REGISTER)
WHERE _id = :id
```

**❌ DON'T** mix declarations for one field. Each statement reads or writes the value of the type it declares, so values seem to vanish even on one device: a `REGISTER` insert followed by an undeclared `SET obj.a = 11` makes an undeclared `SELECT` return `"obj": {"a": 11}`. Keep the statements in one repository class.

Guide: [Strict Mode](../../../guides/best-practices/ditto.md#strict-mode), [Keep type declarations consistent](../../../guides/best-practices/ditto.md#keep-type-declarations-consistent). Example: [strict-mode-and-declarations.dart](examples/strict-mode-and-declarations.dart).

---

### 4. Relationships: Embedding, Separate Collections, and JOIN

**Embed by default** (sub-entities as maps keyed by ID). `JOIN` (SDK 5.1+) removes the main read-side cost of separate collections, which makes normalized models practical when the decision guide below calls for them; the other trade-offs remain: each collection is a separate sync unit with its own subscription, and the join key needs an index.

| Embed when the data is... | Use a separate collection when the data is... |
|---|---|
| Read together with the parent | Accessed independently of the parent |
| Owned by exactly one parent | Shared by many parents (products in many orders) |
| Small and bounded (tens of entries) | Unbounded (events, readings, messages) |
| Covered by the parent's permissions | Governed by different permissions |
| Edited by the same writers | Written by different writers or systems |

Concurrent edits alone are **not** a reason to split: map entries merge.

**JOIN rules (SDK 5.1+):** local data only (never fetches from peers); not allowed in subscriptions or on Ditto Server; the inner collection needs an index on the join key, or join on its `_id`; qualify every field with its alias.

```sql
CREATE INDEX IF NOT EXISTS orderItems_orderId ON orderItems (orderId)
```

```sql
SELECT o._id AS orderId, o.status, i.productId, i.quantity
FROM orders AS o
JOIN orderItems AS i ON i.orderId = o._id
WHERE o._id = :orderId
ORDER BY i.productId
```

Without a usable index the query fails with `Joining to "c" disallowed without appropriate index support`:

<!-- expect-error -->
```sql
SELECT o._id, c.name
FROM orders AS o
JOIN customers AS c ON c.email = o.customerEmail
```

```dart
// ✅ GOOD: One subscription per joined collection (app or feature scope).
// Subscriptions filter only on their own fields, so storeId is copied into
// orderItems when items are created.
List<SyncSubscription> subscribeForStore(Ditto ditto, String storeId) => [
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription(
        'SELECT * FROM orderItems WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription('SELECT * FROM products'),
    ];
```

**✅ DO:**
- Treat a missing joined document as normal (it may not have synced yet); use `LEFT JOIN` when the parent must appear without children.
- Write a parent and its children created together in one transaction.
- Check plans with `EXPLAIN` and index suggestions with `ADVISE`.

**❌ DON'T:**
- Put a JOIN in `registerSubscription` (rejected: `Unsupported feature: Joining`).
- Silence the index error with `USE INDEX ''` on a large collection.
- Split a small, bounded, single-owner sub-entity only because JOIN exists.

**Copying values:** copy a value only when it is a snapshot (price at time of sale) or a subscription filter key (`storeId`). For values that must stay current, reference by ID and JOIN at read time.

Guide: [Relationships](../../../guides/best-practices/ditto.md#relationships-embedding-separate-collections-and-join), [Joining Collections](../../../guides/best-practices/ditto.md#joining-collections-sdk-51). Examples: [embedded-relationship.dart](examples/embedded-relationship.dart), [foreign-key-join.dart](examples/foreign-key-join.dart).

---

### 5. Do Not Store Derived Values

A stored total, line total, or remaining stock is a separate register. Devices recompute it from partial views, and after the merge it can match neither. Compute it at read time, in Dart or with DQL:

```sql
SELECT COUNT(*) AS openOrders FROM orders WHERE status = 'open'
```

Snapshot values are facts, not derivations: copy `unitPriceCents` into the line item when it is added. Also keep UI state, progress flags, and device-local paths out of synced documents, and initialize flags you filter on (`isDeleted: false`) or filter with `coalesce(isDeleted, false) = false`.

Guide: [Document Structure](../../../guides/best-practices/ditto.md#document-structure). Example: [derived-values.dart](examples/derived-values.dart).

---

### 6. Counters

`COUNTER` is the only type that adds concurrent changes together. Use `APPLY`, not `SET`, and the `COLLECTION` keyword for declarations:

| Operation | Statement |
|---|---|
| Increment / decrement | `APPLY f INCREMENT BY n` (integer `n`; negative to decrement) |
| Set a value | `APPLY f RESTART WITH n` (concurrent `RESTART`s: last writer wins) |
| Reset to zero | `APPLY f RESTART` |

```sql
INSERT INTO COLLECTION products (viewCount COUNTER)
DOCUMENTS (:product)
```

```sql
UPDATE COLLECTION products (viewCount COUNTER)
APPLY viewCount INCREMENT BY 1
WHERE _id = :id
```

**❌ DON'T:**
- `SET stock = stock - 1` (two devices both write 9 from 10; one decrement is lost).
- Initialize with an undeclared `INSERT` (stored as a REGISTER; the first `INCREMENT` starts a new counter at 0).
- Overwrite with `SET`; use `RESTART WITH`.
- Use counters for unique sequence numbers, balances that must stay valid, values a `COUNT(*)` can derive, or fractional amounts (integer-only; count in cents).
- Mix `COUNTER` and the legacy `PN_INCREMENT` operator on one field.

Guide: [Counters](../../../guides/best-practices/ditto.md#counters). Example: [counter-patterns.dart](examples/counter-patterns.dart).

---

### 7. Document IDs

| Strategy | Use when |
|---|---|
| **UUID v4** (primary) | Almost always |
| ULID / time-ordered random ID | Rough creation-time ordering (device clocks make it approximate) |
| Composite object `{"storeId": ..., "orderId": "<uuid>"}` | Permissions or subscriptions scoped by owner, location, or tenant |
| Natural key (SKU) | Globally unique, immutable domain key |
| Generated by Ditto (omit `_id`) | Nothing needs the ID before insert; read `result.mutatedDocumentIDs()` |

- Strings and objects are recommended; floats and `null` are rejected. Do not depend on the format of generated IDs.
- `_id` is immutable: to change it, copy to a new `_id` and remove the old document in one transaction.
- Put only immutable attributes into a composite `_id`; filter and index subfields (`_id.locationId`).
- **Never** use sequential or timestamp-only IDs: two offline devices produce the same ID, and the documents merge into one.
- Keep human-readable numbers (`#A-0042`) in a separate field; they are labels, not keys.

Guide: [Document IDs](../../../guides/best-practices/ditto.md#document-ids). Examples: [id-generation-patterns.dart](examples/id-generation-patterns.dart), [composite-id-patterns.dart](examples/composite-id-patterns.dart), [id-immutability-workaround.dart](examples/id-immutability-workaround.dart).

---

### 8. Document Size Limits

| Threshold | Default | Behavior |
|---|---|---|
| Soft limit | 256 KiB | Write succeeds; warning `exceeds recommended limit` is logged |
| Hard limit | 5 MiB | `INSERT` / `UPDATE` fails (`DittoException`); the stored document is unchanged |

Sizes are measured on disk, including CRDT metadata. Design documents to stay well below 256 KiB; store binaries as attachments; move unbounded data (history, readings, comments) into its own collection; leave both limits at their defaults. `object_size()` gives an approximate size of the value (without CRDT metadata), so leave headroom. An oversized document does not shrink by writing smaller values: write a new document under a new `_id`.

Guide: [Document Size Limits](../../../guides/best-practices/ditto.md#document-size-limits). Example: [document-size.dart](examples/document-size.dart).

---

### 9. Timestamps

Store UTC with a zone designator (`DateTime.now().toUtc().toIso8601String()`) or epoch milliseconds, consistently per field. Zone-less ISO strings make every DQL date function return `MISSING` without an error. Clocks drift: never decide between conflicting writes with your own timestamp fields.

ISO strings sort chronologically as text only when they share one precision. Native Dart emits microseconds (`2026-10-08T10:30:00.123456Z`) while the web emits milliseconds (`...00.123Z`), so use one helper with fixed precision for every timestamp field that is sorted or compared:

```dart
/// ISO-8601 UTC string with exactly millisecond precision.
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// ✅ GOOD: UTC with a zone designator and fixed precision.
Future<void> markReady(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET readyAt = :readyAt WHERE _id = :id',
    arguments: {'id': orderId, 'readyAt': utcTimestamp()},
  );
}
```

Guide: [Timestamps](../../../guides/best-practices/ditto.md#timestamps). Example: [timestamps.dart](examples/timestamps.dart).

---

## Quick Reference Checklist

- [ ] No array of items edited by several devices; maps keyed by stable IDs instead
- [ ] No reliance on `SET obj = {...}` / `DO UPDATE` to remove keys; `UNSET` used
- [ ] Upserts of full documents use `DO UPDATE_LOCAL_DIFF`
- [ ] `DQL_STRICT_MODE` left at `false`, or applied on every launch and identical on every peer
- [ ] Each declared field (`REGISTER`, `MAP`, `COUNTER`, `ATTACHMENT`) declared the same way in every statement
- [ ] Embedded by default; separate collections justified by the decision guide
- [ ] Every JOIN: inner join key indexed (or `_id`), every joined collection subscribed, JOINs kept out of subscriptions
- [ ] No stored derived values; snapshot values copied deliberately
- [ ] Concurrent tallies use `COUNTER` with `APPLY`
- [ ] UUID (or composite / natural) IDs; display numbers separate from `_id`
- [ ] Documents well under 256 KiB; binaries as attachments
- [ ] Timestamps in UTC with a zone designator, written by one fixed-precision helper

More patterns: [reference/common-patterns.md](reference/common-patterns.md) (field-level updates, event history, document size) and [reference/advanced-patterns.md](reference/advanced-patterns.md) (current state plus history, INITIAL documents, schema evolution, field names).

---

## Examples

| File | Shows |
|---|---|
| [field-level-updates.dart](examples/field-level-updates.dart) | Field updates, `UNSET`, `DO UPDATE_LOCAL_DIFF` vs `DO UPDATE`, replacing an object |
| [array-to-map.dart](examples/array-to-map.dart) | Array vs map keyed by ID, dynamic keys, safe `UNSET` |
| [strict-mode-and-declarations.dart](examples/strict-mode-and-declarations.dart) | `REGISTER` declarations, mixed declarations, opting in to strict mode |
| [embedded-relationship.dart](examples/embedded-relationship.dart) | Embedding with one subscription |
| [foreign-key-join.dart](examples/foreign-key-join.dart) | Separate collections, `CREATE INDEX`, JOIN, LEFT JOIN, JOIN observer |
| [derived-values.dart](examples/derived-values.dart) | Derived vs snapshot values, `COUNT(*)` |
| [counter-patterns.dart](examples/counter-patterns.dart) | `COUNTER` declarations, `INCREMENT`, `RESTART WITH`, mistakes |
| [event-history.dart](examples/event-history.dart) | Audit-log map, append-only event documents, eviction |
| [two-collection-pattern.dart](examples/two-collection-pattern.dart) | Current state plus history in one transaction |
| [document-size.dart](examples/document-size.dart) | Splitting, attachments, size errors, `object_size()` |
| [id-generation-patterns.dart](examples/id-generation-patterns.dart) | UUID, natural key, generated IDs, display numbers |
| [composite-id-patterns.dart](examples/composite-id-patterns.dart) | Composite IDs, subfield index, schema version in `_id` |
| [id-immutability-workaround.dart](examples/id-immutability-workaround.dart) | Moving a document to a new ID |
| [initial-documents.dart](examples/initial-documents.dart) | Seeding defaults with `INITIAL DOCUMENTS` |
| [timestamps.dart](examples/timestamps.dart) | UTC timestamps, range filters, `date_diff` |

---

## See Also

- Guide: [Data Modeling](../../../guides/best-practices/ditto.md#data-modeling), [Writing Data](../../../guides/best-practices/ditto.md#writing-data), [Joining Collections (SDK 5.1+)](../../../guides/best-practices/ditto.md#joining-collections-sdk-51), [Transactions](../../../guides/best-practices/ditto.md#transactions), [Deletion and Storage Management](../../../guides/best-practices/ditto.md#deletion-and-storage-management)
- Other skills: `query-sync` (DQL, subscriptions, observers), `storage-lifecycle` (DELETE, soft delete, EVICT), `transactions-attachments` (transactions, attachments), `performance-observability` (indexes, EXPLAIN, ADVISE)
