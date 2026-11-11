# Data Modeling Advanced Patterns

Less frequent patterns that complement [SKILL.md](../SKILL.md). Targets Ditto SDK 5.2.0 with the default `DQL_STRICT_MODE = false`. The source of truth is `§ Data Modeling` in the full guide (`../../guide/reference/best-practices/data-modeling.md`).

## Table of Contents

- [Pattern 1: Current State Plus History](#pattern-1-current-state-plus-history)
- [Pattern 2: Default Data with INITIAL Documents](#pattern-2-default-data-with-initial-documents)
- [Pattern 3: Schema Evolution](#pattern-3-schema-evolution)
- [Pattern 4: Composite IDs and Display Numbers](#pattern-4-composite-ids-and-display-numbers)
- [Pattern 5: Changing a Document ID](#pattern-5-changing-a-document-id)
- [Pattern 6: Separate Collections with JOIN](#pattern-6-separate-collections-with-join)

---

## Pattern 1: Current State Plus History

When you need both the latest value with low latency and a complete history, write each change to two collections in **one transaction**:

1. **Current state** (`vehicles`): one bounded document per entity; real-time screens observe it.
2. **History** (`vehiclePositions`): one append-only document per change; analysis reads it.

```sql
-- In one transaction, with one recordedAt from the fixed-precision helper.
-- Arguments: {"event": {"_id": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f", "vehicleId": "truck-7", "position": {"lat": 38.71, "lon": -9.14}, "recordedAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO vehiclePositions DOCUMENTS (:event)

-- position is a REGISTER: latitude and longitude from two readings never mix.
-- Arguments: {"vehicle": {"_id": "truck-7", "position": {"lat": 38.71, "lon": -9.14}, "lastSeenAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO COLLECTION vehicles (position REGISTER) DOCUMENTS (:vehicle)
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

Devices subscribe to what they need: a live map only to `vehicles`, an analysis tool to both. Ditto's [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) describes that a peer that subscribes to only part of the documents a transaction changed receives, and can relay, only that part, so peers that need both halves together subscribe to both collections.

Guide: `§ Event History and Audit Logs`, `§ Transactions and Sync`. Example: [two-collection-pattern.sql](../examples/two-collection-pattern.sql).

---

## Pattern 2: Default Data with INITIAL Documents

`INSERT ... INITIAL DOCUMENTS` seeds defaults that every peer may create independently (built-in categories, default settings). Ditto's [INSERT documentation](https://docs.ditto.live/dql/insert) describes initial documents as inserted "at the beginning of time" and viewed by all peers as the same insert, so several devices can initialize the same defaults without overwriting later edits.

| Situation on a device | Result |
|---|---|
| No document with that `_id` exists | Inserted |
| A document exists, even an edited one | Nothing happens; no error |
| The document was deleted earlier on this device | The deletion wins. With a seed identical to the `INITIAL` insert that created the document, it stays deleted; with different content, or if the document was created with a regular `INSERT`, a document with `null` fields remains |
| The document was evicted earlier on this device | Inserted again |
| Combined with `ON ID CONFLICT` | Parser error |

```sql
INSERT INTO categories INITIAL DOCUMENTS (:categories)
```

```sql
INSERT INTO COLLECTION inventory (stockCount COUNTER)
INITIAL DOCUMENTS (:item)
```

**✅ DO:**
- Use fixed, well-known `_id` values, and ship identical seed content in every app version that seeds them. Do not rely on how peers reconcile initial documents with *different* content for the same `_id`.
- Let users "remove" seed documents with a flag (`isArchived`) if the seed content may change in a later app version: seeding a deleted ID with different content leaves a document with `null` fields.

**❌ DON'T:**
- Seed shared defaults with a regular `INSERT` (the second run fails with an ID conflict) or with `ON ID CONFLICT DO UPDATE` (overwrites users' edits).
- Use `INITIAL DOCUMENTS` for data only one device should create (orders, events), or to keep data off the network: subscriptions decide what syncs.

Guide: `§ Default Data with INITIAL Documents`. Example: [initial-documents.sql](../examples/initial-documents.sql).

---

## Pattern 3: Schema Evolution

Devices run different app versions for weeks or months, so a schema change must work while old and new versions read and write the same data.

**Classify every change to stored data, fixes included, before a release** (`§ Breaking and additive changes`):

| Additive (works with every deployed version) | Breaking (needs a versioning pattern and a staged rollout) |
|---|---|
| A new optional top-level field, or a key in a map, that readers default when it is `MISSING`; with the default strict mode, older versions' `SET` and `DO UPDATE` keep it, because they merge | A renamed, removed, or reused field; a new type, unit, or meaning; a new key inside a `REGISTER` object or an array element |
| A new collection that older versions do not need; new documents with a new kind of `_id` where older versions treat `_id` as opaque | A new CRDT type or a declaration that differs from how the field is stored (array or register to map, number to `COUNTER`), or a new `DQL_STRICT_MODE` |
| A new value of an enumerated field, only if every deployed version maps unknown values to an "unknown" state | A new enumerated value that older versions fail to read; a new `_id` shape that older versions filter or subscribe on; a new collection name; a new deletion strategy; new seed content |

Indexes, queries, and observers that read the same fields are not schema changes. A field that no released version has written can still change shape freely. A field that the new version requires is read with a default until every device writes it. An app that has not been released, or a sample or demo that shares its database with no released app, can change in place, with every peer, including a Ditto Server, starting from an empty store.

**✅ Prefer additive changes.** Old versions ignore unknown fields; new versions must tolerate documents without the field (`MISSING`). Instead of changing a field's meaning or unit (`mileage` from miles to kilometers), add a new field (`mileageKm`).

**❌ DON'T** change a field's type, remove it, or rename it without a versioning pattern. A change of CRDT type (for example, from a REGISTER to a MAP) leaves both values under the key, and statements with different declarations read different values: in testing with SDK 5.1.0 and 5.2.0, after an `UPDATE COLLECTION t (price MAP) SET price.amount = 25` of a REGISTER `price`, a `SELECT` that declared `price REGISTER` kept returning the old amount, also on another device. According to Ditto's documentation, an index on such a field can also return wrong results.

**Note (SDK 5.1.0 and 5.2.0)**: renaming in place (`SET quantity = qty UNSET qty`) loses old versions' edits without an error. In testing, an offline old version's `qty = 5` made before the rename merged into `{qty: null, quantity: 1}`; made after it, into `{qty: 5, quantity: 1}`, which the new version still read as 1. Add a new field and let each version read its own, or version the documents (`§ Schema Evolution`).

| | Version in a composite `_id` | New collection per version |
|---|---|---|
| Example | `_id: {"id": "...", "schemaVersion": 2}` | `cars` to `carsV2` |
| Subscription | `WHERE _id.schemaVersion = 2` | `SELECT * FROM carsV2` |
| References from other collections | Unchanged | Must point at the new collection |
| CRDT type change on an indexed field | Risky while both versions coexist locally | Safe (separate indexes) |

```sql
SELECT * FROM cars WHERE _id.schemaVersion = :version
```

**Rolling out a breaking change:**

1. Ship a bridge version that reads v1 and v2 but still writes v1.
2. Wait until the bridge version has reached every deployed device.
3. Ship the version that writes v2 and still reads both.
4. Retire v1 once old documents have been removed (`EVICT` per device, or `DELETE` with tombstones).

**Do not backfill** (reading every v1 document and writing a v2 copy): devices that are offline during the backfill reintroduce v1 documents later.

**Changing CRDT types** (an array or a REGISTER object to a MAP, a number to a COUNTER) is also breaking: old and new values coexist under the same key. Introduce a new field with the new type (`stockCount` as a COUNTER next to the old `stock` register).

Guide: `§ Schema Evolution`. Example: [composite-id-patterns.sql](../examples/composite-id-patterns.sql).

---

## Pattern 4: Composite IDs and Display Numbers

**ID values compare by type and exact value.** In testing with SDK 5.1.0 and 5.2.0, `1` and `'1'`, `'A'` and `'a'`, `'1'` and `' 1'`, and two Unicode forms of `'é'` (one code point, or `e` plus a combining accent) were different documents; Ditto does not normalize IDs. Use one ID type per collection, and normalize IDs built from user input (Unicode NFC, one letter case, trimmed) before use. `''` was accepted as an ID; `-0` was rejected as a float.

Permission rules are queries on `_id` and its subfields. A hierarchical composite `_id` grants access at any level (`"_id.region == 'eu'"`, `"_id.storeId == 'store-12'"` in the permission rules; see § Design `_id` for permission scoping for the rule format); the same subfields filter subscriptions and queries (`WHERE _id.storeId = :storeId`) and can be indexed. Key order inside a composite `_id` does not matter.

```sql
CREATE INDEX IF NOT EXISTS idx_orders_id_storeId ON orders (_id.storeId)
```

```sql
SELECT * FROM orders WHERE _id.storeId = :storeId
```

- Combine stable scope fields with a UUID: `{"region": "eu", "storeId": "store-12", "orderId": "<uuid>"}`.
- Put only **immutable** attributes into `_id`; a store that may change region or an order that may be reassigned needs those values as regular fields.
- Human-readable numbers ("#A-0042") are labels in a separate field, never `_id` or a lookup key. A terminal code that you assign plus a local sequence, shown with the date, avoids coordination.

Guide: `§ Composite IDs for permission scoping and grouping`, `§ Human-readable display IDs`, `§ Security`. Examples: [composite-id-patterns.sql](../examples/composite-id-patterns.sql), [id-generation-patterns.sql](../examples/id-generation-patterns.sql).

---

## Pattern 5: Changing a Document ID

`_id` is immutable. To change it, copy the document to a new `_id` and remove the old document in one transaction. Declare the document's `COUNTER`, `ATTACHMENT`, and `REGISTER` fields in both the `SELECT` and the `INSERT`: a query result holds plain values, so an undeclared copy stores a counter as a plain number and an attachment token as a map.

Guide: `§ IDs are immutable`. Example: [id-immutability-workaround.sql](../examples/id-immutability-workaround.sql).

---

## Pattern 6: Separate Collections with JOIN

When the decision guide in SKILL.md Rule 6 calls for a separate collection, create an index on the inner collection's join key and JOIN locally **(SDK 5.1+)**:

```sql
CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)
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

JOIN reads local data only, so every joined collection needs its own subscription:

<!-- subscription -->
```sql
-- ✅ GOOD: One subscription per joined collection (app or feature scope).
-- Subscriptions filter only on their own fields, so storeId is copied into
-- orderItems when items are created.
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE storeId = :storeId

-- Arguments: {"storeId": "store-12"}
SELECT * FROM orderItems WHERE storeId = :storeId

SELECT * FROM products
```

Guide: `§ Relationships: Embedding, Separate Collections, and JOIN`, `§ Joining Collections (SDK 5.1+)`. Example: [foreign-key-join.sql](../examples/foreign-key-join.sql).
