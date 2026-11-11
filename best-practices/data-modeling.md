# Data Modeling

Ditto is a schemaless document database, but every value you write is stored as a CRDT (conflict-free replicated data type). The CRDT type of a field decides what happens when two devices change it while they are disconnected and then sync. Data modeling in Ditto is therefore mostly about one question: **when concurrent edits meet, does the merge produce the result your business needs?**

How each CRDT type merges is described in [CRDT Types and Merge Behavior](../knowledge/crdt-types.md); read it before this page. This page covers strict mode, the choice between arrays and maps, document structure and size, relationships (including JOIN, SDK 5.1+), document IDs, counters, checks and claims across devices, event history, default data, schema evolution, and timestamps.

**Design checklist:**

- Multiple devices will modify the same data while offline. Model every field for the merge you want.
- Prefer field-level updates over whole-document writes.
- Use maps keyed by ID (not arrays) for collections of items that several devices edit.
- Keep documents well under 256 KiB and store binary data as attachments.
- Use UUIDs or other collision-free IDs, never sequential numbers.
- A check before a write holds only on the device that makes it. Do not use a local query, a conditional `UPDATE`, or a transaction as a lock or a uniqueness check across devices.
- Store timestamps in UTC with a zone designator, and produce every timestamp that is sorted or compared with one fixed-precision helper.

## Strict Mode

**Keep `DQL_STRICT_MODE` at its default, `false`, unless almost every object in your data model needs whole-object replacement, and use the same value on every peer.** The rest of this guide assumes the default. The system parameter controls how Ditto types values that a statement does not declare explicitly; with the default, declare the few fields that need whole-object replacement as `REGISTER` (see [When to choose strict mode](#when-to-choose-strict-mode)). You can check the current value:

```sql
SHOW DQL_STRICT_MODE
```

### What strict mode changes

| Behavior | `DQL_STRICT_MODE = false` (default) | `DQL_STRICT_MODE = true` |
|---|---|---|
| Undeclared objects | Inferred as `MAP` (field-level merge) | Stored as `REGISTER` (whole-object replacement) |
| Nested update `SET obj.a = 1` on an undeclared object | Merges the single field | Fails with `Unsupported DML operation on REGISTER field` |
| `MAP`, `COUNTER`, `ATTACHMENT` fields | Inferred from the value or operation | Must be declared in every statement, for example `UPDATE COLLECTION orders (metadata MAP) SET metadata.a = 1` |
| `SELECT` / `WHERE` on fields stored as MAP, COUNTER, or ATTACHMENT without a declaration | Values are visible | **Fields are invisible**: `SELECT *` omits them and `WHERE` conditions on them do not match |
| Index use | Indexes are used | Indexes are not used (see the note below) |

In our testing, every row of this table held on SDK 5.1.0 and 5.2.0 (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

> **Note (SDK 5.1.0 and 5.2.0):** With `DQL_STRICT_MODE = true`, the query planner does not use indexes. In our testing, with strict mode set by `ALTER SYSTEM`, `EXPLAIN` showed a full collection scan even for a query on an indexed field, and `ADVISE` gave no advice; ID lookups and `COUNT(*)` were not affected, and the index was used again as soon as strict mode was off (see [Strict mode and data types](indexing-and-performance.md#strict-mode-and-data-types) and [With strict mode on, the planner does not use secondary indexes](../knowledge/observations/dql-behavior.md#with-strict-mode-on-the-planner-does-not-use-secondary-indexes)). Keep the default (`false`) if you rely on indexes for query performance.

### When to choose strict mode

Choose `DQL_STRICT_MODE = true` **rarely**: only when whole-object replacement semantics are required for almost every object in your data model and you are prepared to declare every MAP, COUNTER, and ATTACHMENT field in every statement. For new applications, keep the default.

If only a few fields need replacement semantics, keep the default and declare those fields as `REGISTER` in each statement that touches them:

```sql
INSERT INTO COLLECTION customers (shippingAddress REGISTER)
DOCUMENTS (:customer)
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

```sql
UPDATE COLLECTION customers (shippingAddress REGISTER)
SET shippingAddress = :address
WHERE _id = :id
```

```sql
SELECT * FROM COLLECTION customers (shippingAddress REGISTER)
WHERE _id = :id
```

With the declaration, an upsert or `SET` replaces the address as a whole: keys that are absent from the new value disappear. A nested update such as `SET shippingAddress.city = :city` fails with `Unsupported DML operation on REGISTER field "shippingAddress"`; to change one part of a register object, write the whole object again.

```sql
-- ✅ GOOD: The address is a REGISTER, so a concurrent edit can never produce a
-- mix of two different addresses (for example, the street of one and the city
-- of the other). The declaration appears in every statement.
-- Arguments: {"id": "c-1", "address": {"street": "Main St", "city": "Oslo", "zip": "0150"}}
UPDATE COLLECTION customers (shippingAddress REGISTER)
SET shippingAddress = :address
WHERE _id = :id
```

### Keep type declarations consistent

**Declare a field the same way in every `INSERT`, `UPDATE`, and `SELECT` that touches it, and change a counter only with `APPLY`.** A field can hold more than one CRDT value at the same time when statements disagree about its type. Each statement reads or writes the value of the type it declares (or infers), and an undeclared `SELECT` shows the most recently written type (see [Changing a register to a counter leaves both values](../knowledge/observations/merge-behavior.md#changing-a-register-to-a-counter-leaves-both-values)). Mixed declarations therefore produce results that look like data loss, even on a single device:

| Sequence (default settings) | Result |
|---|---|
| `INSERT INTO COLLECTION orders (obj REGISTER) ... {"obj": {"a": 1, "b": 2}}`, then an undeclared `UPDATE orders SET obj.a = 11` | Undeclared `SELECT` returns `"obj": {"a": 11}`: `b` seems to have vanished. The REGISTER value `{"a": 1, "b": 2}` still exists beside a new MAP value |
| Undeclared `INSERT ... {"cnt": 10}`, then `APPLY cnt INCREMENT BY 1` | `cnt` becomes `1`, not `11`: the increment created a new COUNTER that started at 0 |
| `APPLY pn PN_INCREMENT BY 4` twice, then `APPLY pn INCREMENT BY 1` | `pn` becomes `1`: the COUNTER hides the legacy PN_COUNTER value |
| `INSERT INTO COLLECTION t (price REGISTER) ... {"price": {"amount": 1}}`, then `UPDATE COLLECTION t (price MAP) SET price.amount = 25`, on this or another device | Undeclared and `MAP` reads return `25`, while a `SELECT` that declares `price REGISTER` keeps returning `1`. An app version that declares the field differently from the others shows stale values and never sees their updates (in our testing; see [Mixed type declarations change what a query reads, not the index results](../knowledge/observations/dql-behavior.md#mixed-type-declarations-change-what-a-query-reads-not-the-index-results)) |
| A counter at 3, an undeclared `UPDATE ... SET cnt = 0` to reset it, then `APPLY cnt INCREMENT BY 1` on any device | An undeclared `SELECT` returns `0` until the increment, then `4`: the `SET` wrote a REGISTER next to the COUNTER, and the increment made the COUNTER the latest value again (see [Resetting a counter with SET leaves two values](../knowledge/observations/merge-behavior.md#resetting-a-counter-with-set-leaves-two-values)). Reset a counter with `APPLY cnt RESTART` (see [RESTART](#restart)) |

In our testing, the first three rows of this table held on SDK 5.1.0 and 5.2.0 (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

**✅ DO:**
- Use the same declaration for a field in **every** `INSERT`, `UPDATE`, and `SELECT` that touches it.
- Keep these statements in one place in your code (for example, a repository class) so they cannot drift apart.

**❌ DON'T:**
- Declare a field as `REGISTER` in one statement and leave it undeclared in another.
- Write a counter field with `SET`, or initialize it with an undeclared `INSERT`.

### Changing the setting

System parameters are not persisted. If you choose `DQL_STRICT_MODE = true`, set it **every time** you open Ditto, in the system parameters of `DittoConfig` (SDK 5.2+), so that it is in effect before any query, observer, or sync runs. On SDK 5.1, run `ALTER SYSTEM` after opening Ditto and before you start sync, run queries, or register observers (subscriptions may be registered before it). See [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters) for the full startup sequence.

```sql
-- SDK 5.1 only: run after every open, before sync starts and before queries
-- and observers run. On SDK 5.2+, pass DQL_STRICT_MODE in the system
-- parameters of DittoConfig instead.
ALTER SYSTEM SET DQL_STRICT_MODE = true
```

The code for passing system parameters when Ditto opens: [Flutter](platforms/flutter.md#dittoconfig-in-flutter) · [JavaScript](platforms/javascript.md#dittoconfig-in-javascript) · [Kotlin](platforms/kotlin.md#dittoconfig-in-kotlin) · [Swift](platforms/swift.md#dittoconfig-in-swift).

### Peers with different settings

**Use the same `DQL_STRICT_MODE` value on every peer that writes to the database; if a peer must differ, declare the map fields it reads in every statement there.** Strict mode is a local setting of each peer. Data syncs between peers regardless of their settings, but **each peer interprets the data with its own setting**. A peer with `DQL_STRICT_MODE = true` does not show undeclared objects that another peer wrote as maps, so nested updates from a `false` peer appear to be missing on the `true` peer, although they have synced correctly. In our testing with SDK 5.1.0 and 5.2.0, one strict and one non-strict peer showed these effects (see [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)):
- A nested update such as `SET obj.a = 2` on the strict peer failed with `Unsupported DML operation on REGISTER field "obj"` when `obj` had been written as an object by a strict peer.
- After concurrent edits, an undeclared `SELECT *` kept showing different values for the same document on the two peers.

**✅ DO:**
- Use the same `DQL_STRICT_MODE` value on every peer, in every app and backend integration that writes to the same database.
- If a backend writes through the HTTP API, use the `/api/v5/store/execute` endpoint, which supports `DQL_STRICT_MODE = false`.

**❌ DON'T:**
- Mix settings across peers unless every statement on the strict peers declares the map fields it reads.

## Arrays and Maps

**Store items that several devices add, edit, or remove as a map keyed by a stable ID, not as an array.** Arrays are registers: the whole array is replaced on every write, and when two devices change the same array concurrently, one version wins and the other change is lost silently (see [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)). Maps keyed by ID merge each entry independently (see [With three offline devices, counters and maps keep every change](../knowledge/observations/merge-behavior.md#with-three-offline-devices-counters-and-maps-keep-every-change)). Choose the shape as follows:

| Use a **map keyed by ID** when | Use an **array** when |
|---|---|
| Several devices may add, edit, or remove items | Only one device writes; others read |
| Items have a natural or synthetic unique ID | Order matters and the list is never edited concurrently |
| You want to update or index individual items | It is a simple list of scalars that you replace wholesale |

**✅ DO:**
- Store collections of editable items as maps keyed by a stable ID (a natural key such as a SKU, or a UUID).
- Keep the item's own data inside the entry, and store any display order as a field (for example, `position`).
- When the user moves an item, write only that entry's `position`, with a value between its new neighbors (for example, the midpoint). Renumbering every entry makes a reorder that another device made at the same time disappear, and renumbering only the shifted entries mixes the numbers of both devices (see [Reordering on Two Devices](../knowledge/crdt-types.md#reordering-on-two-devices) and [Reordering on two offline devices keeps both moves only with gap positions](../knowledge/observations/merge-behavior.md#reordering-on-two-offline-devices-keeps-both-moves-only-with-gap-positions)). Sort entries with equal positions by a fixed key, such as the entry key, and renumber the whole list only when no other device reorders it at the same time.
- Use arrays for immutable lists or lists that a single device owns.

**❌ DON'T:**
- Store line items, participants, or checklist entries that several devices edit in an array.
- Expect concurrent array edits to merge or to produce duplicates: one device's change disappears without an error.

### Shapes

```jsonc
// ❌ BAD: Two devices that change different items concurrently both rewrite the
// whole array. After sync, one device's change is gone.
{
  "_id": "order-1",
  "items": [
    { "productId": "p1", "quantity": 2 },
    { "productId": "p2", "quantity": 1 }
  ]
}
```

```jsonc
// ✅ GOOD: Each item is a map entry keyed by its ID. Concurrent additions,
// edits to different items, and edits to different fields of one item merge.
{
  "_id": "order-1",
  "items": {
    "9b2f6c1e-4d0a-4f7e-8a51-3c2d1e0f9a87": { "productId": "p1", "quantity": 2, "position": 0 },
    "e41c7a90-2b3d-4c5e-9f60-7a8b9c0d1e2f": { "productId": "p2", "quantity": 1, "position": 1 }
  }
}
```

```jsonc
// ✅ ACCEPTABLE: A list of scalars that is replaced as a whole and usually
// edited by one device.
{
  "_id": "product-42",
  "tags": ["electronics", "gadget"]
}
```

### Adding, updating, and removing map entries

When the key is known when you write the query, address the entry with a path. Quote keys that contain characters such as `-` or `.` with backticks, and write a backtick inside a key twice (`` `tick``name` ``). A quoted `` `a.b` `` is one key that contains a dot, while `a.b` is the key `b` inside `a`; in our testing, both could exist in the same document (see [Field names can contain dots and backticks, or be empty](../knowledge/observations/dql-behavior.md#field-names-can-contain-dots-and-backticks-or-be-empty)):

```sql
UPDATE orders
SET items.`item-3` = :item
WHERE _id = :id
```

```sql
UPDATE orders
SET items.`item-1`.quantity = :quantity
WHERE _id = :id
```

```sql
UPDATE orders
UNSET items.`item-2`
WHERE _id = :id
```

DQL parameters bind **values**, not field paths, and DQL has no bracket syntax for dynamic keys (`items[:key]` is a parser error). In application code the key is usually a variable. Two patterns cover this without building queries from untrusted strings:

1. **Add or update an entry** by upserting a partial document with `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`. Because objects merge, only the entry you pass is written (see [With three offline devices, counters and maps keep every change](../knowledge/observations/merge-behavior.md#with-three-offline-devices-counters-and-maps-keep-every-change)), and unchanged values are not rewritten.
2. **Remove an entry** with `UNSET`, after validating that the key matches a strict pattern (for example, a UUID), and only then placing it inside backticks.

```sql
-- Adds or updates one line item. The key is passed as data inside a partial
-- document, never spliced into the query. If the order does not exist yet,
-- this creates it.
-- Arguments: {"patch": {"_id": "order-1", "items": {"9b2f6c1e-4d0a-4f7e-8a51-3c2d1e0f9a87": {"productId": "p1", "quantity": 2}}}}
INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

```sql
-- Removes one line item. A path cannot be passed as a parameter, so the key is
-- checked against a strict pattern (here, a lowercase UUID) in app code before
-- it is placed inside the backtick-quoted path segment.
-- Arguments: {"id": "order-1"}
UPDATE orders UNSET items.`9b2f6c1e-4d0a-4f7e-8a51-3c2d1e0f9a87` WHERE _id = :id
```

The code for validating a key before it goes into a path: [Flutter](platforms/flutter.md#executing-dql-in-flutter) · [JavaScript](platforms/javascript.md#executing-dql-in-javascript) · [Kotlin](platforms/kotlin.md#executing-dql-in-kotlin) · [Swift](platforms/swift.md#executing-dql-in-swift).

> **Note (SDK 5.1.0 and 5.2.0):** Removing an entry does not win over a concurrent edit of that entry. In our testing, one device ran `` UNSET items.`item-1` `` while another device changed `` items.`item-1`.quantity `` (see [A key added concurrently survives a later removal as null](../knowledge/observations/merge-behavior.md#a-key-added-concurrently-survives-a-later-removal-as-null)):
> - **Removal first, edit later:** the entry stays with only the edited fields, for example `{"quantity": 5}`.
> - **Edit first, removal later:** the entry stays with the edited fields set to `null`, for example `{"quantity": null}`.
> - **Whole entry rewritten after the removal** (`` SET items.`item-1` = :item `` or `DO UPDATE`): the full entry comes back.
>
> These are "husk" entries, like [husk documents](deletion-and-storage.md#husk-documents). When devices may edit an entry while another removes it, mark it removed instead (`` SET items.`item-1`.removed = true ``). Either way, make readers skip entries whose required fields are missing or `null` (see [Do not store derived values that can diverge](#do-not-store-derived-values-that-can-diverge)).

> **Note (SDK 5.1.0 and 5.2.0):** A removed entry leaves a small record in the document. In our testing, each map key removed with `UNSET` added about 54 bytes to a new device's first sync of the document (for a UUID key), the records stayed after reaping, and writes slowed down as removed keys accumulated (see [Removed map keys keep adding to a new device's first sync](../knowledge/observations/storage-and-deletion.md#removed-map-keys-keep-adding-to-a-new-devices-first-sync)). A map with a bounded set of keys, such as the line items of an order, is not affected. For a long-lived list whose entries come and go, such as open tickets or a task list, store each entry in its own document instead; deleted documents' tombstones are reaped.

**Why:** Splicing unchecked input into a query enables DQL injection. A strict allow-list pattern for map keys keeps the path safe, and all other values still travel as parameters (see [Parameters and Literals](dql.md#parameters-and-literals)).

### Working with arrays

DQL has no element-level assignment (`SET tags[0] = ...` is a parser error). Build the new array in app code and write it back; the write replaces the whole register:

```sql
-- The array is a register: the write replaces it as a whole. Read the current
-- array, append the tag in app code, and write the new array back, both in one
-- transaction, which keeps two local calls from interleaving and dropping a
-- tag; a concurrent edit on another device can still win the merge.
-- Arguments: {"id": "p1"}
SELECT tags FROM products WHERE _id = :id

-- Arguments: {"id": "p1", "tags": ["new", "sale"]}
UPDATE products SET tags = :tags WHERE _id = :id
```

The code for reading and writing in one transaction: [Flutter](platforms/flutter.md#transactions-in-flutter) · [JavaScript](platforms/javascript.md#transactions-in-javascript) · [Kotlin](platforms/kotlin.md#transactions-in-kotlin) · [Swift](platforms/swift.md#transactions-in-swift).

To find documents whose array contains a value, use `IN` with the array field or `array_contains`:

```sql
SELECT * FROM products WHERE :tag IN tags
```

```sql
SELECT * FROM products WHERE array_contains(tags, :tag)
```

An index on an array field matches only the complete array value, so element lookups such as these scan the collection. Scalar fields inside map entries, by contrast, can be indexed with their full path (see [Creating Indexes](indexing-and-performance.md#creating-indexes) and [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

### Incremental adoption

You do not have to convert every array at once. Start with the simple shape, and convert an array to a map as soon as you know that more than one device writes it. Keep the collection name and `_id` structure unchanged so that documents stay compatible, but write the map to a **new field** (for example, `lineItems` next to the old `items` array). In a deployed app, the new field replaces the old one, so roll it out in stages (see [A field that replaces another](#a-field-that-replaces-another)). Writing a map under the array's field name changes its CRDT type: the old array and the new map then coexist under the same key, and app versions that still write the array make the field switch back and forth (see [Changing CRDT types](#changing-crdt-types)).

## Document Structure

### Prefer field-level updates

Update only the fields that the user changed, so that concurrent edits to other fields survive. The rule and its examples are in [Prefer field-level updates over whole-document rewrites](dql.md#prefer-field-level-updates-over-whole-document-rewrites); this subsection covers the one case that an upsert does not make safe, a stale in-memory copy.

`ON ID CONFLICT DO UPDATE_LOCAL_DIFF` compares the incoming document with the local document and skips fields whose values are equal (those fields keep their timestamps); every field that differs is written. That suits upserts and re-imports of data that another system owns, but it does not protect a stale copy: if a change from another device has already reached the local store and your in-memory copy still holds the old value, the old value differs from the stored one and is written back (see [Rewriting an unchanged value overwrites concurrent edits](../knowledge/observations/merge-behavior.md#rewriting-an-unchanged-value-overwrites-concurrent-edits)). (`DO UPDATE` writes every field you pass, even unchanged ones, which gives those fields new timestamps and can override a concurrent change from another device.) See [INSERT and Conflict Handling](dql.md#insert-and-conflict-handling) for all conflict policies.

**✅ DO:**
- Write only the fields that the user changed, with `UPDATE ... SET` (or with a partial document in an upsert).

**❌ DON'T:**
- Write back a whole in-memory copy of a document, even with `DO UPDATE_LOCAL_DIFF`.

```sql
-- ❌ BAD: Writing back a whole in-memory copy after the user changed only the
-- status. If another device changed tableNumber to 12 after this copy was
-- loaded, the stale value 7 is written back. DO UPDATE_LOCAL_DIFF does not
-- prevent this, because 7 differs from the stored 12 (and DO UPDATE would also
-- rewrite every unchanged field).
-- Arguments: {"order": {"_id": "order-1", "status": "ready", "tableNumber": 7}}
INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- ✅ GOOD: Only the field the user changed is written, so a concurrent change
-- to tableNumber on another device is kept.
-- Arguments: {"id": "order-1", "status": "ready"}
UPDATE orders SET status = :status WHERE _id = :id
```

### Flat or nested

Both shapes are valid; choose by how the data is edited and read:

- **Group related fields in an object** when they belong together but may be edited separately (for example, `customer.name` and `customer.phone`). Under the default settings each nested field merges independently, and nesting has no special performance cost.
- **Keep fields at the top level** when they are queried and indexed on their own; paths such as `customer.phone` are indexable too, so this is a readability choice more than a performance one.
- **Use a REGISTER object** only when the parts must never mix (see [Strict Mode](#strict-mode)).
- **Avoid unbounded growth** inside one document: a map that keeps receiving new entries forever belongs in its own collection (see [Document Size Limits](#document-size-limits)).
- **Keep nesting shallow.** Real data models rarely need more than a few levels, and deep nesting runs into limits. In our testing with SDK 5.1.0 and 5.2.0, an argument could nest 125 levels and a literal in a statement 97, so a document built deeper with `UPDATE` paths could not be written back in an upsert of what was read, and documents 800 or more levels deep made a peer's process end during sync (see [Nesting depth is limited differently for arguments, literals, and paths](../knowledge/observations/documents-and-limits.md#nesting-depth-is-limited-differently-for-arguments-literals-and-paths) and [Very deep documents end a peer's process during sync](../knowledge/observations/documents-and-limits.md#very-deep-documents-end-a-peers-process-during-sync)). Model trees such as folders, comment threads, or org charts as separate documents with a `parentId` reference, not as nested maps.

### Do not store derived values that can diverge

A stored value computed from other fields (a line total, an order total, a remaining stock level) is a separate register. Two devices can update the inputs concurrently, and each recomputes the total from its own partial view. After the merge, the stored total keeps one device's partial result and disagrees with the merged inputs: in our testing, the line items merged to 800 while the stored subtotal stayed at 600 (see [A stored total keeps one device's partial result](../knowledge/observations/merge-behavior.md#a-stored-total-keeps-one-devices-partial-result)). Compute derived values when you read them.

```jsonc
// ❌ BAD: subtotal and total are derived. After concurrent edits to items they
// can disagree with the items that actually merged.
{
  "_id": "order-1",
  "items": {
    "item-1": { "unitPriceCents": 1299, "quantity": 2 }
  },
  "subtotalCents": 2598,
  "totalCents": 2858
}
```

✅ Store the source data and derive totals when you read the document: sum `unitPriceCents * quantity` over the entries of `items`, and skip entries whose price or quantity is missing or `null` (an entry removed on one device while another device edited it) instead of failing. The code for such a read-time derivation: [Flutter](platforms/flutter.md#query-results-in-flutter) · [JavaScript](platforms/javascript.md#query-results-in-javascript) · [Kotlin](platforms/kotlin.md#query-results-in-kotlin) · [Swift](platforms/swift.md#query-results-in-swift).

Aggregates over a collection can be computed in DQL instead of maintained in a stored field or counter:

```sql
SELECT COUNT(*) AS openOrders FROM orders WHERE status = 'open'
```

Distinguish derived values from **snapshot values**. The unit price at the time of sale is a fact about the order, not a derivation: copy it into the line item (`unitPriceCents`) when the item is added, so a later price change in `products` does not alter historical orders.

### Exclude transient and unnecessary fields

Once a document has replicated, Ditto syncs only the fields that change, but every stored field still costs storage and memory on every device that holds the document, adds to the initial replication of new documents, and adds to merge cost. Keep documents to durable, shared business data.

**❌ DON'T store in synced documents:**
- UI state: `isExpanded`, `isSelected`, scroll positions.
- Temporary progress flags: `isSaving`, `uploadProgress`.
- Device-local data: local file paths, cache locations.
- Derived values: totals, averages, ages, "days until" values.

**✅ DO:**
- Keep UI and device-local state in your UI framework's state, a state-management layer, or local preferences.
- Initialize flags you will filter on when you create the document (for example, `isDeleted: false`), or filter with `coalesce(isDeleted, false) = false`. A missing field is `MISSING`, not `false` (see [MISSING and NULL](dql.md#missing-and-null)).

### Field names

- Field names are always strings. Use one convention (this guide uses camelCase).
- If a field name collides with a DQL keyword or contains special characters (see [Field names can contain dots and backticks, or be empty](../knowledge/observations/dql-behavior.md#field-names-can-contain-dots-and-backticks-or-be-empty)), quote it with backticks in queries (for example, `` `value` ``).
- Never name a collection `collection`; it is a DQL keyword.
- Names are case-sensitive: `Orders` and `orders` are different collections, and `createdAt` and `createdat` are different fields (see [Names are case-sensitive, and most DQL keywords are accepted as bare names](../knowledge/observations/dql-behavior.md#names-are-case-sensitive-and-most-dql-keywords-are-accepted-as-bare-names)).

## Document Size Limits

**Keep every document well below the 256 KiB soft limit, store binary content as attachments, and leave both limits at their defaults.** Ditto enforces two thresholds on the **size of each stored document**:

| Threshold | Default | System parameter | Behavior |
|---|---|---|---|
| Soft limit | 256 KiB (262,144 bytes) | `DOCUMENT_SIZE_SOFT_LIMIT_BYTES` | The write succeeds and a warning is logged |
| Hard limit | 5 MiB (5,242,880 bytes) | `DOCUMENT_SIZE_HARD_LIMIT_BYTES` | `INSERT` and `UPDATE` statements on this device that would exceed it **fail**; the stored document is unchanged. On 5.2.0, a change from another device that would exceed it is dropped on the receiving device; 5.1.0 does not check such changes (see below and [An oversized merge ends differently on each release](../knowledge/observations/documents-and-limits.md#an-oversized-merge-ends-differently-on-each-release)). SDK 5.0.3 did not check the limit in our testing (see [SDK 5.0.3 does not check the hard size limit when a document is written](../knowledge/observations/documents-and-limits.md#sdk-503-does-not-check-the-hard-size-limit-when-a-document-is-written)) |

Log and error messages:

```text
[Warning] Document `_id = "s300k"` size is 307.4 KB exceeds recommended limit of 262.1 KB bytes and might have reduced performance

Query failed: DQL Internal execution error: Insert failed: <store> Document `_id = "s5m1"` size is 5243067 bytes and exceeds limit of 5242880 bytes
```

A failed statement fails with the SDK's error type; catch it like any other DQL error (see [When a Statement Fails or Returns Nothing](dql.md#when-a-statement-fails-or-returns-nothing)).

> **Note (SDK 5.2.0):** A device on 5.2.0 drops a change that would push a document over its hard limit, so the devices keep different versions of the document, and both list it in `system:sync_degradations` with the reason `documentTooBig` (see [System Virtual Collections](../knowledge/system-reference.md#system-virtual-collections)); no API reports an error. In our testing, updates of that document then reached neither device, while other documents kept syncing, until one device evicted it, and **the evicting device lost its own changes to the document** (see [On SDK 5.2.0, an oversized document stops syncing until one side evicts it](../knowledge/observations/documents-and-limits.md#on-sdk-520-an-oversized-document-stops-syncing-until-one-side-evicts-it)). To recover, evict the document on the device whose changes you can afford to lose, and include `system:sync_degradations` in your diagnostics.
>
> **Note (SDK 5.1.0):** The hard limit is checked only when a device writes, not when changes from other devices merge. In our testing, two devices that each added 3 MiB to the same document while offline both stored the 6 MiB document without an error, and from then on **every `UPDATE` of that document failed on every device** until an `UNSET` removed enough data (see [On SDK 5.2.0, an oversized merge leaves devices with different versions](../knowledge/observations/documents-and-limits.md#on-sdk-520-an-oversized-merge-leaves-devices-with-different-versions)). By the same rule, a 5.1.0 device whose hard limit is lower than that of other devices would store larger documents that it receives and could not update them; we did not test different limits.

On both releases, the protection is the same: keep large or growing data out of documents (attachments, separate collections), so that even combined offline additions stay far below the limit.

**Why the limits matter:** Size affects local storage and memory on every device holding the document, serialization time, CRDT merge cost (which scales with document size, not change size), and initial replication. Over Bluetooth LE (roughly 20 KB/s in practice), a 256 KiB document takes more than 10 seconds to replicate the first time (sync traffic is compressed, so content that compresses well goes faster; see [Sync traffic is compressed and carries field-level changes](../knowledge/observations/subscriptions-and-replication.md#sync-traffic-is-compressed-and-carries-field-level-changes)). Later edits sync only the changed fields, but a document that many devices have written stays heavier: in our testing, a field that 300 devices had written cost about 11 times as much on a new device's first sync as a field that one device had written as often, also after the value had been overwritten (see [A document grows with the number of devices that wrote it](../knowledge/observations/documents-and-limits.md#a-document-grows-with-the-number-of-devices-that-wrote-it)). A shared document that every device writes (store settings, a tally that every device increments) grows with the number of devices that ever wrote it, including reinstalled devices, which write as new devices.

**✅ DO:**
- Design documents to stay well below 256 KiB.
- Store images, PDFs, and other binary content as attachments; attachments are fetched separately and do not count toward the document size (see [Attachments](attachments.md)).
- Move data that grows without bound (order history, readings, comments) into its own collection.
- Leave both limits at their defaults. If you change them, change them on every peer in the same release: by the behavior in the notes above, a device with a lower hard limit would keep documents that arrive larger than its limit without being able to update them (5.1.0), or drop the changes that make them larger (5.2.0). (In SDK 5.1.0 and 5.2.0, a hard limit set below the soft limit is not enforced; see [The documented parameter defaults match SHOW ALL](../knowledge/observations/configuration-and-diagnostics.md#the-documented-parameter-defaults-match-show-all).)

**❌ DON'T:**
- Embed base64-encoded files in documents.
- Append to a nested map forever.
- Raise the hard limit to make a large document fit.

```sql
-- A write that may take the document over the hard limit
-- Arguments: {"id": "visit-1", "notes": "Customer asked for a callback."}
UPDATE visits SET notes = :notes WHERE _id = :id
```

Catch the error at the call site that may produce it, and report it in your app's error UI; its message contains `exceeds limit of ... bytes` for oversized documents. The code for handling the size error: [Flutter](platforms/flutter.md#executing-dql-in-flutter) · [JavaScript](platforms/javascript.md#executing-dql-in-javascript) · [Kotlin](platforms/kotlin.md#executing-dql-in-kotlin) · [Swift](platforms/swift.md#executing-dql-in-swift).

### Monitoring size

- Search application logs for `exceeds recommended limit` to find documents above the soft limit.
- Estimate the size of a document with `object_size()` (SDK 5.1+; see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../knowledge/observations/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503)). It returns an approximate size in bytes of the value, which can differ from the stored size, so leave headroom:

```sql
SELECT _id, object_size(o) AS approxBytes
FROM orders AS o
WHERE _id = :id
```

### Splitting strategies

| Cause of growth | Fix |
|---|---|
| A nested map that keeps receiving entries (history, comments, readings) | Move the entries to their own collection with a reference to the parent (`orderId`) |
| Binary data in a field | Move it to an `ATTACHMENT` field |
| One document that holds data for many unrelated users or locations | Split by owner or location; this usually also simplifies permissions |
| Status history | Keep a bounded audit-log map, or move events to an event collection (see [Event History and Audit Logs](#event-history-and-audit-logs)) |

To bring an oversized document back under the limits, remove the data that made it grow: move large values to attachments or to a separate collection, and remove them from the document with `UNSET`.

## Relationships: Embedding, Separate Collections, and JOIN

Embedding related data in one document remains the default recommendation. JOIN (SDK 5.1+) removes the main read-side cost of separate collections, which makes normalized models practical when one of the criteria below calls for them:

- **Embed when** sub-entities belong to one parent and are read and written with it. Store them as maps keyed by ID: a single write is atomic, the whole document syncs as one unit, and add-wins maps merge concurrent edits to different sub-entities.
- **Use separate collections when** a sub-entity has independent permission scopes, is accessed independently at scale, is shared by many parents, or would push the parent toward the size limits. Product catalogs, order histories, and task assignments can then live in separate collections, and a `JOIN` reads them together without several sequential queries.

JOIN does not change the other trade-offs: a separate collection is a separate sync unit, needs its own subscription, and needs an index on the join key.

### Decision guide

| Embed in the parent document when the data is... | Use a separate collection when the data is... |
|---|---|
| Read together with the parent (an order and its line items on one screen) | Accessed independently of the parent (a fleet view across all vehicles) |
| Owned by exactly one parent | Shared by many parents (products referenced by many orders) |
| Small and bounded (tens of entries) | Unbounded (events, readings, messages) |
| Covered by the same permissions as the parent | Governed by different permissions (a mechanic may see the car, not the owner's profile) |
| Edited by the same group of writers | Written by different writers or systems (a catalog maintained centrally, orders created in stores) |

Concurrent edits are **not** by themselves a reason to split: a map keyed by ID merges concurrent edits to different entries.

### Embedding example

```json
{
  "_id": "order-1",
  "storeId": "store-12",
  "status": "open",
  "createdAt": "2026-10-08T10:00:00.000Z",
  "items": {
    "9b2f6c1e-4d0a-4f7e-8a51-3c2d1e0f9a87": {
      "productId": "p1",
      "name": "Espresso",
      "unitPriceCents": 350,
      "quantity": 2
    }
  }
}
```

```sql
-- One subscription syncs the order with all of its items, and every write to an
-- item is an atomic update of the order document. Register it once in a
-- long-lived service and cancel it when it is no longer needed.
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE storeId = :storeId
```

### Separate collections with JOIN (SDK 5.1+)

`JOIN` works only on data that is already in the local store. It never fetches missing documents from other peers, and it is not allowed in subscriptions (or on Ditto Server). Each joined collection must therefore be synced by its own subscription, and the inner collection needs an index on the join key (a join on `_id` uses an ID lookup and needs no extra index). See [Joining Collections (SDK 5.1+)](dql.md#joining-collections-sdk-51) for the full syntax and limits.

```jsonc
// orders
{ "_id": "order-1", "storeId": "store-12", "status": "open" }

// orderItems: storeId is copied from the order so the subscription can filter on it
{ "_id": "item-1", "orderId": "order-1", "storeId": "store-12", "productId": "p1", "quantity": 2 }

// products
{ "_id": "p1", "name": "Espresso", "priceCents": 350 }
```

Create the index once at startup (`IF NOT EXISTS` makes this idempotent):

```sql
CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)
```

Subscribe to each collection separately. A subscription reads a single collection with `SELECT *` (no JOIN or projection), so a child collection cannot be filtered by a field of its parent: copy the filter key (`storeId`) into the child documents when you create them.

```sql
-- Keeps the three collections needed by the order screens in sync.
-- Subscriptions belong to an app- or feature-level service, not to a screen.
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE storeId = :storeId

-- Arguments: {"storeId": "store-12"}
SELECT * FROM orderItems WHERE storeId = :storeId

SELECT * FROM products
```

The code for a service that owns these subscriptions: [Flutter](platforms/flutter.md#subscriptions-in-flutter) · [JavaScript](platforms/javascript.md#subscriptions-in-javascript) · [Kotlin](platforms/kotlin.md#subscriptions-in-kotlin) · [Swift](platforms/swift.md#subscriptions-in-swift).

Join locally, in a one-off query or an observer. Qualify every field with its alias and project the fields you need: with `SELECT *`, each collection's fields are nested under its alias, and an unqualified `_id` in the result is a composite such as `{"i": ..., "p": ...}`.

```sql
SELECT i._id AS itemId, i.quantity, p.name, p.priceCents
FROM orderItems AS i
JOIN products AS p ON p._id = i.productId
WHERE i.orderId = :orderId
ORDER BY p.name
```

```sql
SELECT o._id AS orderId, o.status, i.productId, i.quantity
FROM orders AS o
JOIN orderItems AS i ON i.orderId = o._id
WHERE o._id = :orderId
ORDER BY i.productId
```

The first query drives from `orderItems` through the `idx_orderItems_orderId` index and looks up each product by `_id`. The second needs the same index because `orderItems` is the inner collection. Without a usable index, the statement fails with `Joining to "i" disallowed without appropriate index support`, unless you explicitly allow a scan of that join term with `USE INDEX ""` (see [Joining Collections (SDK 5.1+)](dql.md#joining-collections-sdk-51)).

Observe the join like any other query (see [Joins in observers](dql.md#joins-in-observers) and [Observer Lifecycle](observers.md#observer-lifecycle)). If the `orderId` can change while the screen is shown, register the observer again for the new value (see [Filter locally instead of re-registering](sync-and-subscriptions.md#filter-locally-instead-of-re-registering)).

**✅ DO:**
- Subscribe to every collection a JOIN reads, and copy the subscription filter key into child documents.
- Index the inner join key, or join on `_id`. Check plans with `EXPLAIN` and suggestions with `ADVISE` (see [ADVISE (SDK 5.1+)](indexing-and-performance.md#advise-sdk-51)).
- Treat a missing joined document as normal: the other side may not have synced yet. Use `LEFT JOIN` when the parent must appear without its children.
- When parent and children are created together, write them in one transaction (see [Transactions](transactions.md)).

**❌ DON'T:**
- Put a JOIN in `registerSubscription`; it is rejected with `Unsupported feature: Joining`.
- Assume JOIN fetches data from other peers.
- Split a small, bounded, single-owner sub-entity into its own collection only because JOIN now exists.

**Why:** A separate collection is a separate unit of sync. The parent can arrive before its children, permissions apply per document, and a peer can receive only part of a multi-document transaction when it, or a peer it receives the data through, does not subscribe to all of the documents involved (see [Transactions](transactions.md)). Embedding avoids all three concerns; JOIN makes the separate-collection model practical to query when one of the decision criteria calls for it.

### Copying values versus embedding

Embedding (the order owns its items) is different from copying another entity's values into a document. Copy a value only when it is a snapshot that must not change with the source (the price at the time of sale), or when a subscription needs it as a filter key (`storeId` in `orderItems`). For values that should always be current (a product's name in a catalog screen), reference the other document by ID and JOIN at read time.

## Document IDs

**Give every document a collision-free `_id` that never needs to change: a UUID, or a composite object of immutable scope fields plus a UUID. Never use sequential numbers or timestamps.** Every document has an `_id` that is unique within its collection. If you omit `_id`, Ditto generates one. Do not depend on the format of generated IDs; generate your own when other code needs to know or construct the ID.

### Allowed values

| `_id` value | Accepted |
|---|---|
| String | ✅ Recommended |
| Object (composite key), for example `{"storeId": "s1", "orderId": "..."}` | ✅ Recommended when you need scoping or grouping |
| Integer, boolean, array | ✅ Accepted, but not recommended |
| Floating-point number | ❌ `Floats are not supported in document IDs` |
| `null` | ❌ `Null document ID not allowed` |

Key order inside a composite `_id` does not matter: `{"storeId": "s1", "orderId": "o1"}` and `{"orderId": "o1", "storeId": "s1"}` identify the same document. In our testing, every row of this table and this key order held on SDK 5.0.3, 5.1.0, and 5.2.0 (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)).

Otherwise IDs compare by type and exact value. In our testing, `1` and `'1'`, `true` and `'true'`, `'A'` and `'a'`, and `'1'` and `' 1'` were different documents, and so were two strings that look the same but use different Unicode forms: Ditto does not normalize them (see [Document IDs compare by type and exact value](../knowledge/observations/dql-behavior.md#document-ids-compare-by-type-and-exact-value)). The empty string was accepted as an ID; `-0` was rejected as a float (`Invalid document id`).

**✅ DO:**
- Use one type for the IDs of a collection.
- Normalize an ID that you build from user input (for example, a name or a code) before you use it: one Unicode form (NFC), one letter case, no surrounding spaces. Different keyboards and platforms can produce the same text in different forms, and each form becomes a separate document.

### IDs are immutable

`UPDATE orders SET _id = ...` fails with ``The document id `_id` cannot be modified``. To "change" an ID, copy the document to a new `_id` and remove the old one, in one transaction. Removing the old document has the usual deletion trade-offs (see [DELETE and Tombstones](deletion-and-storage.md#delete-and-tombstones) and [Soft Delete](deletion-and-storage.md#soft-delete)), and every reference to the old ID must be updated, so choose IDs carefully up front.

When you copy a document this way, remember that a query result contains plain values, not CRDT types. Declare in the `SELECT` and in the `INSERT` the same types that every other statement on the collection uses (see [Keep type declarations consistent](#keep-type-declarations-consistent)); otherwise the copy stores a counter as a plain number and an attachment token as a map, and a field read with a different declaration (for example, a MAP read as a `REGISTER`) is missing from the copy. With `DQL_STRICT_MODE = true`, declare the `MAP` fields as well.

Copy and remove in one transaction: read the document with the declarations, change `_id` in the copy in app code, insert the copy with the same declarations, and delete the original.

```sql
-- Both statements declare the order's COUNTER, ATTACHMENT, and REGISTER fields
-- exactly as the other statements on orders do, so the copy keeps their CRDT
-- types. Undeclared objects such as shippingAddress are MAPs.
-- Arguments: {"id": "order-1"}
SELECT * FROM COLLECTION orders
  (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
WHERE _id = :id

-- Arguments: {"doc": {"_id": "order-1-moved", "status": "open", "printCount": 2}}
INSERT INTO COLLECTION orders
  (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
DOCUMENTS (:doc)

-- Arguments: {"id": "order-1"}
DELETE FROM orders WHERE _id = :id
```

The code for the copy in one transaction: [Flutter](platforms/flutter.md#transactions-in-flutter) · [JavaScript](platforms/javascript.md#transactions-in-javascript) · [Kotlin](platforms/kotlin.md#transactions-in-kotlin) · [Swift](platforms/swift.md#transactions-in-swift).

### Generation strategies

| Strategy | Use when | Notes |
|---|---|---|
| **UUID v4** (primary recommendation) | Almost always | 122 random bits; independent devices never coordinate. Use your platform's UUID generator (see the code below) |
| **ULID** or another time-ordered random ID | You want IDs that sort roughly by creation time | Ordering follows each device's clock, so it is only approximate across devices; the ID reveals its creation time |
| **Composite object** | Permissions or subscriptions are scoped by owner, location, or tenant; you group documents by a parent | Combine stable scope fields with a UUID: `{"storeId": "s1", "orderId": "<uuid>"}` |
| **Natural key** | The domain already has a globally unique, immutable key (a SKU, an email address used as an account key) | Two devices that create the same entity intentionally end up with one document whose fields merge |
| **Generated by Ditto** (omit `_id`) | Nothing else needs to know the ID before the insert | Read it back from the mutated document IDs of the result |

```sql
-- ✅ GOOD: The app generates a UUID for _id before the insert.
-- createdAt comes from the fixed-precision timestamp helper (see Timestamps).
-- Arguments: {"order": {"_id": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f", "storeId": "store-12", "status": "open", "createdAt": "2026-01-15T10:30:00.000Z"}}
INSERT INTO orders DOCUMENTS (:order)
```

The code for generating UUIDs: [Flutter](platforms/flutter.md#ids-and-timestamps-in-flutter) · [JavaScript](platforms/javascript.md#ids-and-timestamps-in-javascript) · [Kotlin](platforms/kotlin.md#ids-and-timestamps-in-kotlin) · [Swift](platforms/swift.md#ids-and-timestamps-in-swift).

### Composite IDs for permission scoping and grouping

Ditto permission rules are queries on `_id` and its subfields. A hierarchical composite `_id` lets you grant access at any level, for example a whole region (`"_id.region == 'eu'"`) or a single store (`"_id.storeId == 'store-12'"`); see [Design `_id` for permission scoping](security.md#design-_id-for-permission-scoping) for the rule format. The same subfields can filter subscriptions and queries (`WHERE _id.storeId = :storeId`), and they can be indexed (see [The sending peer evaluates a subscription's WHERE clause like a local query](../knowledge/observations/subscriptions-and-replication.md#the-sending-peer-evaluates-a-subscriptions-where-clause-like-a-local-query)). Filtering on the complete `_id` value uses a direct ID lookup.

```sql
-- Arguments: {"order": {"_id": {"region": "eu", "storeId": "store-12", "orderId": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f"}, "status": "open"}}
INSERT INTO orders DOCUMENTS (:order)

-- Each store device syncs only its own store's orders. The service that
-- registers this subscription cancels it when it is no longer needed.
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE _id.storeId = :storeId
```

```sql
CREATE INDEX IF NOT EXISTS idx_orders_id_storeId ON orders (_id.storeId)
```

Put only **immutable** attributes into a composite `_id`. A store that might move to another region, or an order that might be reassigned to another store, needs those values as regular fields instead.

### Never use sequential or timestamp-only IDs

Devices that are offline cannot coordinate a sequence. Two of them will generate the same "next" ID, and after sync the two documents become one document whose fields merge: data from different orders ends up mixed together (see [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)). Timestamp-only IDs fail the same way whenever two devices create a record in the same millisecond, and device clocks are not reliable anyway (see [Timestamps](#timestamps)).

```sql
-- ❌ BAD: Collides when two offline devices create the 42nd order of the day
-- Arguments: {"order": {"_id": "order-42", "status": "open"}}
INSERT INTO orders DOCUMENTS (:order)

-- ❌ BAD: Collides when two devices write within the same millisecond
-- Arguments: {"order": {"_id": "order-1760000000123", "status": "open"}}
INSERT INTO orders DOCUMENTS (:order)
```

### Human-readable display IDs

Customers and staff need short numbers such as "#A-0042". Keep them **separate from `_id`**, and treat them as labels rather than unique keys. One approach that avoids coordination is to prefix with a stable device or terminal code that you assign, and to show the date alongside the number:

```sql
-- The display label (here, terminal code A plus a local sequence of 42) is a
-- regular field, not an identifier: uniqueness is not guaranteed across
-- devices, so never use it as _id or as a lookup key.
-- Arguments: {"order": {"_id": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f", "displayNumber": "A-0042", "createdAt": "2026-01-15T10:30:00.000Z"}}
INSERT INTO orders DOCUMENTS (:order)
```

The code for formatting the label: [Flutter](platforms/flutter.md#ids-and-timestamps-in-flutter) · [JavaScript](platforms/javascript.md#ids-and-timestamps-in-javascript) · [Kotlin](platforms/kotlin.md#ids-and-timestamps-in-kotlin) · [Swift](platforms/swift.md#ids-and-timestamps-in-swift).

## Counters

**Use a `COUNTER` for an integer that several devices increment or decrement, change it only with `APPLY`, and declare it in every statement.** A `COUNTER` field holds an integer that any device can increment or decrement. Increments and decrements from all devices are combined, so concurrent changes add up instead of overwriting each other (see [With three offline devices, counters and maps keep every change](../knowledge/observations/merge-behavior.md#with-three-offline-devices-counters-and-maps-keep-every-change)). Counter operations use the `APPLY` clause, not `SET`:

| Operation | Statement |
|---|---|
| Increment or decrement | `APPLY f INCREMENT BY n` (use a negative `n` to decrement; `n` must be an integer; see [A COUNTER accepts only integers](../knowledge/observations/merge-behavior.md#a-counter-accepts-only-integers)) |
| Set to a specific value | `APPLY f RESTART WITH n` |
| Reset to zero | `APPLY f RESTART` |

Type declarations use the `COLLECTION` keyword: `UPDATE COLLECTION products (viewCount COUNTER) ...`. Writing `UPDATE products (viewCount COUNTER) ...` without `COLLECTION` is a parser error (`Missing SET and/or UNSET clause`).

### Declarations

With the default settings:

| Statement | Declaration `(f COUNTER)` |
|---|---|
| `INSERT` that sets an initial value | **Required**. An undeclared `INSERT` stores the number as a REGISTER; a later `INCREMENT` then starts a separate counter at 0 (an initial 5 followed by `INCREMENT BY 1` reads as 1) |
| `UPDATE ... APPLY` | Optional. `APPLY` creates the counter if the field does not exist yet |
| `SELECT` | Optional. The current value is returned as a number |

With `DQL_STRICT_MODE = true`, the declaration is required in every statement. This guide declares the counter in every statement so that the code works in both modes and follows [Keep type declarations consistent](#keep-type-declarations-consistent).

```sql
INSERT INTO COLLECTION products (viewCount COUNTER)
DOCUMENTS (:product)
```

```sql
UPDATE COLLECTION products (viewCount COUNTER)
APPLY viewCount INCREMENT BY 1
WHERE _id = :id
```

```sql
SELECT * FROM COLLECTION products (viewCount COUNTER)
WHERE _id = :id
```

```sql
-- Arguments: {"product": {"_id": "p1", "name": "Pen", "viewCount": 0}}
INSERT INTO COLLECTION products (viewCount COUNTER) DOCUMENTS (:product)

-- Arguments: {"id": "p1"}
UPDATE COLLECTION products (viewCount COUNTER)
APPLY viewCount INCREMENT BY 1
WHERE _id = :id
```

`APPLY` can be combined with `SET` in one statement; write `APPLY` first:

```sql
UPDATE COLLECTION inventory (stockCount COUNTER)
APPLY stockCount INCREMENT BY :delta
SET lastAdjustedAt = :now
WHERE _id = :id
```

### Writing documents that contain counters

A value that a statement writes into a counter, other than with `INCREMENT BY`, works like `RESTART WITH`: it replaces the count, and increments that have not reached this device yet are discarded. That includes an upsert of a whole document and a plain `INSERT` of a document that another device has already created.

> **Note (SDK 5.1.0 and 5.2.0):** An upsert that writes a number into a declared counter restarts it. In our testing, a counter stood at 7; while two devices were offline, one upserted the document with `cnt: 10` (`INSERT INTO COLLECTION t (cnt COUNTER) DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE`) and the other added 5, and after sync the counter was 10 on both devices, exactly as with `RESTART WITH 10`; `DO UPDATE_LOCAL_DIFF` restarted it too (see [An upsert that declares a counter restarts it](../knowledge/observations/merge-behavior.md#an-upsert-that-declares-a-counter-restarts-it)). When two offline devices each created the same stock document with `stockCount: 10` and each sold one item, a plain `INSERT` or `ON ID CONFLICT DO NOTHING` ended at 9, while `INITIAL DOCUMENTS` kept both sales and ended at 8 (see [INITIAL DOCUMENTS keeps concurrent counter increments](../knowledge/observations/merge-behavior.md#initial-documents-keeps-concurrent-counter-increments)).

**✅ DO:**
- Create a document that holds a counter on each device, such as a stock document that every till creates on first launch, with `INSERT INTO COLLECTION ... INITIAL DOCUMENTS`. `ON ID CONFLICT DO NOTHING` protects only against a copy that is already on this device.
- Leave counter fields out of documents that you re-import or upsert (for example a product list from your backend), and apply a change to the count with `APPLY ... INCREMENT BY` the difference.
- Count per item inside one document in map entries, with `APPLY items.<key>.qty INCREMENT BY n`. A path inside a map cannot be declared (`(items.sku1.qty COUNTER)` is a parser error), so write the statement without a declaration; in our testing, the increments of two offline devices were both kept, and an undeclared `SELECT` returned the count (see [Counters inside map entries add up](../knowledge/observations/merge-behavior.md#counters-inside-map-entries-add-up)).
- Remove documents and map entries that hold a counter with a flag, not with `DELETE` or `UNSET`: a deletion that merges with a concurrent increment leaves the count at 0 (see [Husk documents](deletion-and-storage.md#husk-documents) and [Deleting a counter during a concurrent increment leaves a husk](../knowledge/observations/merge-behavior.md#deleting-a-counter-during-a-concurrent-increment-leaves-a-husk)).

**❌ DON'T:**
- Upsert a whole document that contains a counter, declared or not. Without the declaration, the upsert stores the number as a separate REGISTER next to the counter, and the field then reads differently depending on whether a statement declares it (see [Keep type declarations consistent](#keep-type-declarations-consistent)).

### RESTART

**Use `RESTART` only for occasional corrections made by one authority while every device that changes the counter is online and in sync.** `RESTART WITH n` sets the counter to a specific value and `RESTART` sets it to zero. When devices perform `RESTART` operations concurrently, the last write wins.

> **Note (SDK 5.1.0 and 5.2.0):** A `RESTART` discards **every increment that the restarting device had not received when it ran the restart**. That includes increments that other devices make *after* the restart (by the clock) until the restart reaches them. Only increments made after a device has received the restart are added to the new value. In our testing, a counter at 10 restarted with 100 on one peer while another peer, which had not yet received the restart, incremented it by 5, ended at 100 whichever peer wrote first by the clock, and at 105 only when the restart had already synced before the increment (see [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)).

A typical consequence: a stock recount with `RESTART WITH :counted` silently erases the sales that offline devices record until they receive the recount. Re-importing the stock list with an upsert has the same effect (see [Writing documents that contain counters](#writing-documents-that-contain-counters) and [An upsert that declares a counter restarts it](../knowledge/observations/merge-behavior.md#an-upsert-that-declares-a-counter-restarts-it)).

Run a stock recount, for example, only while every till is online and in sync. If devices keep recording changes offline during a recount, keep the recounts and the changes as separate event documents and derive the stock from them (see [When counters are appropriate](#when-counters-are-appropriate)).

```sql
-- Run only while every device that increments stockCount is online and in
-- sync; increments that this device has not received yet are discarded.
-- Arguments: {"id": "item-1", "counted": 40}
UPDATE COLLECTION inventory (stockCount COUNTER)
APPLY stockCount RESTART WITH :counted
WHERE _id = :id
```

### When counters are appropriate

| ✅ Good fit | ❌ Poor fit, and what to use instead |
|---|---|
| Likes, votes, view counts | **Unique sequence numbers** (invoice or ticket numbers): two offline devices both read 41 and both produce 42. Use UUIDs plus a display label (see [Document IDs](#document-ids)) |
| Usage metrics and tallies from many devices (a counter grows with the number of devices that incremented it; see [A document grows with the number of devices that wrote it](../knowledge/observations/documents-and-limits.md#a-document-grows-with-the-number-of-devices-that-wrote-it)) | **Balances that must be validated** (account balances, "never below zero"): a counter cannot enforce a constraint, and concurrent decrements can drive it negative (see [Conditional updates on two offline devices both succeed](../knowledge/observations/merge-behavior.md#conditional-updates-on-two-offline-devices-both-succeed)). Record transactions as events and validate when you derive the balance |
| Inventory adjustments where every device records its own sales or receipts | **Values derivable from documents you already store** (number of open orders): compute them with a query such as `SELECT COUNT(*) ...` |
| Values recalibrated occasionally with `RESTART WITH`, while all devices that change them are in sync | **Fractional amounts**: `COUNTER` is integer-only (`INCREMENT BY 1.5` fails with `Expected 1.5 to be an integer value`, and a declared `INSERT` of 2.5 fails too; values are never rounded). Count in minor units such as cents or grams. The legacy `PN_COUNTER` accepts fractions, but rounding errors accumulate: in our testing, ten increments of 0.1 gave `0.9999999999999999` (see [A COUNTER accepts only integers](../knowledge/observations/merge-behavior.md#a-counter-accepts-only-integers)) |

**❌ DON'T:**
- Initialize a counter with an undeclared `INSERT`.
- Overwrite a counter with `SET`; use `RESTART WITH`.
- Mix `COUNTER` and the legacy `PN_INCREMENT` operator on one field.
- Use `RESTART WITH` to recalibrate a counter that other devices keep changing while offline.

**Why:** Counters (`COUNTER`, and the legacy `PN_COUNTER`) are the only CRDT types that add concurrent changes together, also between devices that are online (see [Conditions and Arithmetic across Devices](../knowledge/crdt-types.md#conditions-and-arithmetic-across-devices)). Everything else (registers, map entries) keeps one of the concurrent values, so `SET stockLevel = stockLevel - 1` (SDK 5.1+) on two devices loses one of the decrements (see [Read-modify-write increments lose most concurrent updates](../knowledge/observations/merge-behavior.md#read-modify-write-increments-lose-most-concurrent-updates)).

```sql
-- ❌ BAD: Read-modify-write on a register. Two devices that each sell one item
-- while the stock is 10 both write 9; after sync the stock is 9 instead of 8.
-- Arguments: {"id": "item-1"}
UPDATE inventory SET stockLevel = stockLevel - 1 WHERE _id = :id

-- ✅ GOOD: Concurrent decrements are combined.
-- Arguments: {"id": "item-1"}
UPDATE COLLECTION inventory (stockCount COUNTER)
APPLY stockCount INCREMENT BY -1
WHERE _id = :id
```

## Checks and Claims across Devices

**A check that a device makes before it writes holds only for the documents on that device at that moment. Do not use a local query, a conditional `UPDATE`, or a transaction as a lock, as a uniqueness check, or to guard a rule that must hold on every device.** Statements run against the local store (see [Where Queries Run](dql.md#where-queries-run)), devices sync the documents that a statement changed and not the statement, and a transaction locks nothing on other devices (see [Transactions](transactions.md)). Two devices that have not received each other's changes can therefore both pass the same check, and the merge then keeps what the field types say, without an error on either device. [Conditions and Arithmetic across Devices](../knowledge/crdt-types.md#conditions-and-arithmetic-across-devices) describes what remains after the merge.

Each statement in such code is valid, and a test on one device passes. Look for the pattern instead: a read, a condition on what it returned, and a write that is correct only if the condition still holds everywhere.

| Habit from a single database | What happens across devices | Do this instead |
|---|---|---|
| A claim or state change with a condition, such as `UPDATE tasks SET status = 'assigned', assignee = :me WHERE _id = :id AND status = 'open'`, and code that acts on whether a document was changed | Each device changes its own copy and concludes that it won. After sync, one claim remains, and the other device is not told | Write each device's claim under its own key (`claims.<deviceId>`) or as its own document, and let every device pick the winner by the same rule. A rule such as the smallest device ID needs no clock; a rule based on the time of the claim favors the device whose clock is behind (see [Clock drift](#clock-drift)), so use one only where that is acceptable. Write a claim only while no claim is visible on the device: the rule settles only claims that were made without seeing each other, and a claim written later must not take over a settled one. |
| "No document has this value, so insert one": a login name, a table number, one open shift per till | Both devices find nothing and insert. After sync, there are two documents with the value | Where both devices mean the same entity (the settings of one store, a SKU), make the value the `_id`, so that both inserts become one document whose fields merge (see [Generation strategies](#generation-strategies)), and create it with `INITIAL DOCUMENTS` when every device creates it (see [Default Data with INITIAL Documents](#default-data-with-initial-documents)). Where they mean different entities (two people who choose the same login name), keep a UUID as `_id`, accept that duplicates can appear, and resolve them by one rule when you read, or let one device or service assign the value. Do not use the `_id` again for a later entity, such as the next shift (see [DELETE and Tombstones](deletion-and-storage.md#delete-and-tombstones)) |
| The next number from `COUNT(*) + 1`, `MAX(number) + 1`, or a counter | Two devices produce the same number | A UUID as `_id`, and a display label with a device or terminal prefix (see [Human-readable display IDs](#human-readable-display-ids)) |
| Read a value, check a rule, and write the new value, also inside a transaction: "stock never below zero", one booking per seat, a budget | Each device passes its own check, and the merged result breaks the rule. A value written back, such as `SET stock = :newStock`, also loses one of two concurrent changes, exactly as `SET stock = stock - 1` does | Record each change as its own document or as a counter increment, and detect the broken rule when you derive the value (see [When counters are appropriate](#when-counters-are-appropriate)). A `COUNTER` adds the changes of every device, but it does not enforce the rule |
| One `status` field that several devices overwrite, in a workflow that must not go backwards | A device that has not received a newer state writes an older one later, and that write wins | Record transitions in a log and derive the most advanced state when you read (see [Pattern 1: Audit-log map inside the document](#pattern-1-audit-log-map-inside-the-document)) |
| A bulk `UPDATE ... WHERE` as a closing job or a migration, run on a device | It changes only the documents that the device holds at that moment; a matching document that another device adds or still holds unsynced stays as it was | Run the job where every change has arrived, or evaluate the condition when you read |

```sql
-- ❌ BAD: Used as a lock. On two devices that have not synced with each other,
-- both statements change one document, and both devices show the task as theirs.
-- Arguments: {"id": "task-1", "me": "device-a"}
UPDATE tasks SET status = 'assigned', assignee = :me WHERE _id = :id AND status = 'open'

-- ✅ GOOD: Each device records its own claim under its own key. Both claims
-- survive the merge, and every device derives the same assignee from them
-- by one rule (here, the smallest device ID among the claims). A device writes
-- a claim only while it sees none, so a later claim cannot take over.
-- Arguments: {"patch": {"_id": "task-1", "claims": {"device-a": "2026-01-15T10:30:00.000Z"}}}
INSERT INTO tasks DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

**✅ DO:**
- Decide, for every rule that spans devices, how the app detects and shows that it was broken, because no write fails when it is.
- Write a claim only while no claim is visible on the device, and treat its outcome as able to change at any time: derive the winner in an observer, and let the screen change when a different winner arrives. A device cannot know that it holds every other device's claim.
- Where the outcome must be final before the user acts (taking a payment), or a rule must never be broken, let one device or service make the decision, and let the other devices write requests as documents and observe the answer.

**❌ DON'T:**
- Act on the number of documents that a conditional `UPDATE` changed as if no other device could have changed the same document.
- Treat an empty result as proof that a value is unused (see [Where Queries Run](dql.md#where-queries-run)).
- Expect a transaction to keep a rule across devices. It makes a read-check-write sequence safe on one device only.

## Event History and Audit Logs

When every change matters (status transitions, adjustments, sensor readings), record each change as a new fact instead of overwriting one field. Three patterns cover most needs; the table at the end of this section compares them.

### Pattern 1: Audit-log map inside the document

For a bounded history that belongs to one document, such as an order's status transitions, store a **map keyed by a millisecond-precision ISO-8601 UTC timestamp**. Each device adds its own keys, and add-wins merge keeps every entry whose key is distinct (see [With three offline devices, counters and maps keep every change](../knowledge/observations/merge-behavior.md#with-three-offline-devices-counters-and-maps-keep-every-change)). Two transitions recorded in the same millisecond on different devices share a key, and only one of them is kept; if that matters, append a device identifier to the key (for example, `2026-10-08T10:05:12.437Z_t3`), which keeps the keys sortable by time. Derive the current status when you read the document.

```json
{
  "_id": "order-1",
  "statusLog": {
    "2026-10-08T10:00:00.000Z": "created",
    "2026-10-08T10:05:12.437Z": "confirmed",
    "2026-10-08T10:30:45.891Z": "shipped"
  }
}
```

```sql
-- Appends a status transition. The timestamp key (from the fixed-precision
-- helper, see Timestamps, which keeps keys consistent across platforms) is
-- passed as data inside a partial document; unchanged entries are not rewritten.
-- Arguments: {"patch": {"_id": "order-1", "statusLog": {"2026-10-08T10:05:12.437Z": "confirmed"}}}
INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

Derive the current status as the **most advanced state** when you read the document: walk the values of `statusLog` and keep the one that comes latest in the workflow (`created`, `confirmed`, `shipped`, `delivered`), so a late write from a device that was offline cannot move the order backwards. The code for such a derivation: [Flutter](platforms/flutter.md#query-results-in-flutter) · [JavaScript](platforms/javascript.md#query-results-in-javascript) · [Kotlin](platforms/kotlin.md#query-results-in-kotlin) · [Swift](platforms/swift.md#query-results-in-swift).

Common derivation strategies are: the latest timestamp (simple linear workflows), the **most advanced state** (progressions that must not regress), the earliest occurrence ("when did this first happen?"), or custom rules that combine entries. A variant uses the status as the key and the timestamp as the value; it records "did this state happen, and when" but keeps only the latest time for a state that is entered more than once.

### Pattern 2: Append-only event documents

When history is unbounded, accessed independently, or needed by other devices without the parent, write each event as its **own document** with a UUID `_id`. Events are never updated, so there is nothing to merge, and the parent document stays small.

For events that arrive often, such as sensor readings, collect them for a short interval (for example, one second) and write them with one `INSERT` that has several documents (`INSERT INTO readings DOCUMENTS (:r1), (:r2), ...`). Each statement is one commit, and both the writing and the receiving device spend CPU on every commit: in our testing, one document per statement topped out at about 600 documents a second, while 50 documents per statement reached 5,000 a second at about a twelfth of the CPU per document, and the receiver saw every document, in the order written (see [One document per statement tops out at about 600 writes a second](../knowledge/observations/performance-measurements.md#one-document-per-statement-tops-out-at-about-600-writes-a-second)).

```sql
-- The event ID is a new UUID; occurredAt comes from the fixed-precision
-- timestamp helper (see Timestamps).
-- Arguments: {"event": {"_id": "6d1f0b2a-8c3e-4f5a-9b7d-2e4c6a8b0d1f", "orderId": "order-1", "storeId": "store-12", "type": "confirmed", "userId": "u-7", "occurredAt": "2026-10-08T10:05:12.437Z"}}
INSERT INTO orderEvents DOCUMENTS (:event)
```

The fixed-precision timestamp helper (see [Timestamps](#timestamps)) gives every `occurredAt` value the same millisecond precision, so `ORDER BY occurredAt` sorts chronologically:

```sql
SELECT * FROM orderEvents
WHERE orderId = :orderId
ORDER BY occurredAt ASC, _id ASC
```

```sql
-- ❌ BAD: Appending to an array: the app reads history, appends the event, and
-- writes the whole array back. Arrays are registers: if two devices append
-- concurrently, one of the appended events is lost after sync.
-- Arguments: {"id": "order-1", "history": [{"type": "created"}, {"type": "confirmed"}]}
UPDATE orders SET history = :history WHERE _id = :id
```

Event collections grow forever; plan their cleanup from the start with eviction (see [EVICT](deletion-and-storage.md#evict)).

### Pattern 3: Current state plus history (two collections)

When you need both the latest value with low latency and a complete history, write each change to two collections:

1. **Current state** (`vehicles`): one document per entity, bounded in size. Real-time screens observe this collection.
2. **History** (`vehiclePositions`): one append-only document per change. Analysis queries read this collection.

Write both in one transaction so that local observers never see one without the other (see [Transactions](transactions.md)). The position is declared as a `REGISTER` because latitude and longitude from two different readings must never be mixed.

```sql
-- Both statements in one transaction; recordedAt is the same fixed-precision
-- timestamp in both, and the event ID is a new UUID.
-- Arguments: {"event": {"_id": "0c8e4a2f-7b1d-4e3a-8f6c-5d9b1a3e7c2f", "vehicleId": "v-1", "position": {"lat": 59.91, "lon": 10.75}, "recordedAt": "2026-10-08T10:05:12.437Z"}}
INSERT INTO vehiclePositions DOCUMENTS (:event)

-- Arguments: {"vehicle": {"_id": "v-1", "position": {"lat": 59.91, "lon": 10.75}, "lastSeenAt": "2026-10-08T10:05:12.437Z"}}
INSERT INTO COLLECTION vehicles (position REGISTER)
DOCUMENTS (:vehicle)
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

How to run statements in a transaction in each SDK: [Transactions](transactions.md).

Devices can subscribe to what they need: a live map subscribes only to `vehicles`, and an analysis tool also subscribes to `vehiclePositions`. Keep in mind how transactions replicate: a peer that subscribes to only part of the documents a transaction changed receives only that part, and it can relay only that part to other peers (see [Transactions and Sync](transactions.md#transactions-and-sync)). Peers that need both halves together should subscribe to both collections.

| | Audit-log map | Event documents | Current state + history |
|---|---|---|---|
| Size | Grows the parent document | Parent unaffected | Current state bounded; history grows |
| Atomic with the parent | Yes (one document) | Only with a transaction | Only with a transaction |
| Readable without the parent | No | Yes | Yes |
| Best for | Status and workflow history of one record | Unbounded logs, analytics, compliance trails | Live dashboards plus history |

## Default Data with INITIAL Documents

**Create default data that every device seeds (built-in categories, default settings, shared counters) with `INSERT ... INITIAL DOCUMENTS`, fixed `_id` values, and identical content in every app version.** `INSERT ... INITIAL DOCUMENTS` inserts default data that every peer can create independently, such as built-in categories or default settings. Ditto's [INSERT documentation](https://docs.ditto.live/dql/insert) describes initial documents as inserted "at the beginning of time" and viewed by all peers as the same insert, so several devices can initialize the same default data without overwriting later edits. Initial documents are regular documents: they sync like any other document that a subscription matches. See [INITIAL DOCUMENTS](dql.md#initial-documents) for the syntax.

Behavior on a device:

| Situation | Result |
|---|---|
| No document with that `_id` exists locally | The document is inserted |
| A document with that `_id` already exists (including one changed after it was created) | Nothing happens; the existing values are kept |
| The document was deleted earlier on this device | The deletion wins. If the seed is identical to the `INITIAL` insert that created the document, the document stays deleted. If the content differs, or the document was originally created with a regular `INSERT`, a document remains whose fields are `null` (for example, `{"_id": "cfg", "theme": null}`) |
| The document was evicted earlier on this device | The document is inserted again |
| Combined with `ON ID CONFLICT ...` | Parser error; the conflict policy cannot be changed |

In our testing, every row of this table held on SDK 5.1.0 and 5.2.0 (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

Across devices, the same rules apply when the deletion came from another device. In our testing with SDK 5.1.0 and 5.2.0, the effects were these (see [Soft delete, husk, eviction, and tombstone behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/storage-and-deletion.md#soft-delete-husk-eviction-and-tombstone-behavior-held-on-sdk-510-and-520)):
- **A seed for an `_id` that another device deleted** stays deleted if its content is identical. If its content differs, it becomes a document with `null` fields **on every device**. This also happens when a newly installed device seeds before it first connects.
- **Two devices that seed the same `_id` with different content** are merged field by field: `{v: 'A', onlyA: 1}` and `{v: 'B', onlyB: 1}` became `{v: 'B', onlyA: 1, onlyB: 1}`. A field that both seeds set is decided by its value, not by which device seeded later. A regular `INSERT` of the same `_id` wins over the seed (see [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)).

```sql
-- Default categories that every device creates at startup. Running this on
-- every launch is safe: existing documents, including edited ones, are untouched.
-- Arguments: {"categories": [{"_id": "food", "name": "Food", "sortOrder": 1}, {"_id": "drinks", "name": "Drinks", "sortOrder": 2}, {"_id": "desserts", "name": "Desserts", "sortOrder": 3}]}
INSERT INTO categories INITIAL DOCUMENTS (:categories)
```

Counters can be seeded the same way, with a declaration (see [INITIAL DOCUMENTS keeps concurrent counter increments](../knowledge/observations/merge-behavior.md#initial-documents-keeps-concurrent-counter-increments)):

```sql
INSERT INTO COLLECTION inventory (stockCount COUNTER)
INITIAL DOCUMENTS (:item)
```

**✅ DO:**
- Use fixed, well-known `_id` values for seed data so that every device creates the same documents.
- Ship identical seed content in every app version that seeds the same IDs. Do not rely on how peers reconcile initial documents with *different* content for the same `_id`: a key removed from the seed in a new version comes back from devices that still run the old version, and a changed seed turns IDs deleted elsewhere into documents with `null` fields.
- Use soft delete (an `isArchived` flag) for seed documents that users may remove, if the seed content may change in a later app version.

**❌ DON'T:**
- Use a regular `INSERT` for shared defaults on every device: the second run fails with `Identifier conflict on document "...": using FAIL conflict policy`, and `ON ID CONFLICT DO UPDATE` would overwrite users' edits.
- Use `INITIAL DOCUMENTS` for data that only one device should create (orders, events); use a regular `INSERT` with a new UUID.
- Use `INITIAL DOCUMENTS` to keep data off the network. Whether data syncs is decided by subscriptions.

## Schema Evolution

**Add fields instead of renaming, retyping, or reusing them; for a breaking change, version the documents and roll it out in stages.** Ditto is schemaless: documents in a collection can have different fields, and sync stores and replicates them without validation. In a mesh, however, devices run different app versions for weeks or months, so a schema change must work while old and new versions read and write the same data.

### Breaking and additive changes

**Before you ship a change, decide whether it changes what is stored, and if it does, whether it is additive or breaking.** A schema change is any change to the collection names, the shape of `_id`, a field's name, type, unit, or meaning, a CRDT type or declaration, the values that an enumerated field takes, the deletion strategy, or seed content. An **additive** change works with every app version that is deployed; a **breaking** change needs a versioning pattern and a staged rollout (see [Rolling out a breaking change](#rolling-out-a-breaking-change)), because devices that still run an older version keep reading and writing the same documents and nothing in Ditto rejects their writes.

| Change | Kind | What a device on an older app version does |
|---|---|---|
| Add an optional top-level field, or a key in a map, that holds new data older versions do not need, does not change which documents are valid, visible, or counted, and that readers default when it is `MISSING` | Additive, if older versions accept unknown keys and never replace the object | Ignores the field, unless its model rejects unknown keys. With the default `DQL_STRICT_MODE`, its own writes keep it: `SET obj = {...}` and `ON ID CONFLICT DO UPDATE` merge and do not remove keys they leave out (see [Assigning an object merges it](dql.md#assigning-an-object-merges-it)); an `UNSET` followed by a `SET` of the object removes it |
| Add a field that replaces an old one (`weightKg` for `weight` in pounds, `lineItems` for `items`), or a collection that replaces an old one | Breaking, even when the new version reads both | Reads and writes only the old one, so what the new version writes only to the new one never reaches it. Roll out a field in stages (see [A field that replaces another](#a-field-that-replaces-another)), and a collection as in [Rolling out a breaking change](#rolling-out-a-breaking-change) |
| Add a flag or field that changes which documents are valid, visible, or counted (voided, hidden, archived) | Breaking | Ignores it, so it shows, counts, and edits documents that newer versions exclude |
| Add a collection that holds only new data that older versions do not need | Additive | Does not subscribe to it |
| Add a key inside an object declared `REGISTER`, an object written in strict mode, or an array element | Breaking | Writes the whole value without the key, which removes it or loses the newer version's edit of it, because the value is one register |
| Add a field that the new version requires: reads without a default, or filters, sorts, or subscribes on | Breaking for the new version | Keeps creating documents without the field, which the new version's queries miss and its model may fail to read. Read the field with a default, and filter on it only once every device writes it |
| Rename, remove, or reuse a field; change its type, unit, or meaning | Breaking | Keeps writing the old field, which the new version does not read, and reads a missing or wrong value. A rename in place loses its edits (see the note below) |
| Change a CRDT type: an array or a register to a map, a number to a `COUNTER`, or a declaration that differs from how the field is stored | Breaking | Writes the old type; both values then remain under the key, and versions read different values (see [Changing CRDT types](#changing-crdt-types)) |
| Change `DQL_STRICT_MODE` | Breaking | Interprets the same documents with its own setting: objects that one side writes as registers or maps behave differently on the other, and a nested `SET` can fail (see [Peers with different settings](#peers-with-different-settings)) |
| A new value of an enumerated field, such as a new `status` | Breaking, unless every deployed version shows values it does not know without changing them, and the value does not change which documents older versions should show or count (a `voided` status that older totals include is breaking) | Depends on its code: a model that maps the field to a fixed set of values can fail to read the document, and code written for the old values can treat the document as one of them or overwrite the new value |
| A new collection name, or documents split into or merged from other collections | Breaking | Subscribes to and queries the old collection, so documents in the new one never reach it |
| A new shape of `_id` | Breaking where older versions filter, subscribe, check permissions, or parse by `_id` fields | Its subscriptions and queries on `_id.<field>` miss documents of the new shape, and permissions based on `_id` fields stop matching. Where older versions treat `_id` as an opaque value, new documents with a new kind of ID (UUIDs instead of sequential numbers) are additive. Existing IDs cannot change in place (see [IDs are immutable](#ids-are-immutable)) |
| A new deletion strategy, such as a soft-delete flag where documents were deleted | Breaking | Does not filter the flag, so it shows and edits documents that newer versions treat as removed (see [Soft Delete](deletion-and-storage.md#soft-delete)) |
| Different seed content for the same `_id` | Breaking | Brings back the keys that the new seed removed (see [Default Data with INITIAL Documents](#default-data-with-initial-documents)) |

Not schema changes: indexes, which each device creates for itself, and queries, observers, and screens that read and write the same fields with the same meaning.

**Count the fixes as well.** Several fixes in this guide change what is stored: an array to a map, a register to a counter, one `status` field to a status log, sequential IDs to UUIDs, `DELETE` to soft delete, a timestamp format. In an app that is already deployed, do not change the stored data in place. A new field or collection next to the old one (see [Incremental adoption](#incremental-adoption)) avoids the losses of a change in place, but it replaces the old one, so it is breaking too and needs a staged rollout: [A field that replaces another](#a-field-that-replaces-another) for a field, [Rolling out a breaking change](#rolling-out-a-breaking-change) for a collection. A soft-delete flag is breaking, because older versions do not filter it. Only new documents with a new kind of `_id`, where older versions treat `_id` as opaque, are additive.

A field, value, or collection that no released version has written yet can still change shape freely, in the same change or before the release.

**A breaking change needs no rollout only where no peer that holds data runs an older version**: an app that has not been released, or a sample or demo app whose stores are discarded, either of which shares its database with no released app. After the change, start every peer from an empty store, including the Ditto Server (a new database, or its data cleared), because a peer that still holds the old documents syncs them to the others. A sample in the same database as a released app is deployed for this purpose.

**✅ DO:**
- From the first release, read enumerated fields so that a value the app does not know does not stop it from reading the document: map the value to an "unknown" state that the app shows but does not change. A later version can then add a value as an additive change, if the value does not change which documents older versions should show or count.
- Say in a change's description which changes to stored data it makes, and whether each is additive or breaking.

**❌ DON'T:**
- Ship a breaking change to a deployed app because the new version works on its own: test it with a device on the previous version that writes while offline.

### Prefer additive changes

Adding a field that holds new data older versions do not need (see [Breaking and additive changes](#breaking-and-additive-changes)) needs no special pattern. Old app versions ignore fields they do not know; new versions must tolerate documents that do not have the field yet (`MISSING`).

✅ Read a new field with a default for older documents: a model type that the app maps each row into treats `mileageKm` as optional (it was added in app version 2 and is absent in older documents). The code for such a model: [Flutter](platforms/flutter.md#query-results-in-flutter) · [JavaScript](platforms/javascript.md#query-results-in-javascript) · [Kotlin](platforms/kotlin.md#query-results-in-kotlin) · [Swift](platforms/swift.md#query-results-in-swift).

Instead of changing the meaning or unit of a field (`weight` from pounds to kilograms), **add a new field** (`weightKg`) and let each version read the field it understands. Because the new field replaces the old one, this is still a breaking change, but one without the losses of a change in place: roll it out in stages, so that every version sees current values (see [A field that replaces another](#a-field-that-replaces-another)).

**❌ DON'T:**

- Change a field's type, remove it, or rename it without a versioning pattern. Old peers may crash or show wrong data. A change of CRDT type (for example, from a REGISTER to a MAP) leaves both values under the key, so app versions that declare the field differently read different values (see [Keep type declarations consistent](#keep-type-declarations-consistent)); according to Ditto's documentation, an index on such a field can also return wrong results (see [Strict mode and data types](indexing-and-performance.md#strict-mode-and-data-types)).

> **Note (SDK 5.1.0 and 5.2.0):** Renaming a field in place silently loses what old app versions write. In our testing, a new version renamed `qty` to `quantity` with `UPDATE orders SET quantity = qty UNSET qty` while an old version, offline, set `qty = 5`: depending on the order, the 5 was gone, or it came back in the old field that the new version did not read, and an old version that had already received the rename kept writing `qty` (see [Renaming a field in place hides older versions' edits](../knowledge/observations/merge-behavior.md#renaming-a-field-in-place-hides-older-versions-edits)). Reading both fields (`coalesce(quantity, qty)`) cannot recover the first case. Add the new field and roll it out in stages (see [A field that replaces another](#a-field-that-replaces-another)), or version the documents ([Pattern 1](#pattern-1-schema-version-in-a-composite-_id)).

### Pattern 1: Schema version in a composite `_id`

Store the schema version as a subfield of `_id`. Because `_id` is immutable, an `UPDATE` cannot change a document's version by accident, and a new-version document is a new record that coexists with the old one. Each app version subscribes only to the versions it understands:

```sql
-- Arguments: {"version": 2}
SELECT * FROM cars WHERE _id.schemaVersion = :version

-- Arguments: {"car": {"_id": {"id": "car-1", "schemaVersion": 2}, "make": "Hyundai", "fuelEconomyMpg": 32}}
INSERT INTO cars DOCUMENTS (:car)
```

### Pattern 2: A separate collection per breaking version

Write the new schema to a new collection (`cars` to `carsV2`). Subscriptions are per collection, so peers that do not subscribe to `carsV2` never receive it. Prefer this pattern when you change the CRDT type of an indexed field, because each version's index stays isolated.

| | Pattern 1: version in `_id` | Pattern 2: new collection |
|---|---|---|
| Collection name | Unchanged | New per version |
| Subscription | `WHERE _id.schemaVersion = 2` | `SELECT * FROM carsV2` |
| References from other collections | Unchanged | Must point at the new collection |
| CRDT type change on an indexed field | Risky while both versions coexist locally | Safe (separate indexes) |

### Rolling out a breaking change

1. **Ship a bridge version** that reads both versions (subscriptions for v1 and v2) but still writes v1.
2. **Wait** until the bridge version has reached every deployed device. A v2 write made earlier is invisible to devices that subscribe only to v1.
3. **Ship the writer version** that writes v2 and still reads both.
4. **Retire v1**: once old documents have been removed from the mesh, drop the v1 subscription and model.

Remove old-version documents with `EVICT` (local only, per device) or `DELETE` (propagates as a tombstone); see [Deletion and Storage Management](deletion-and-storage.md). **Do not backfill** (reading every v1 document and writing a v2 copy): devices that are offline during the backfill reintroduce v1 documents when they reconnect, so you need the cleanup anyway.

#### A field that replaces another

When a new field in the same documents replaces an old one (`weightKg` for `weight` in pounds, `lineItems` for the `items` array), every write must reach the field that each running version reads:

1. **Bridge version**: writes both fields and reads the old one, which every running version still writes. The first time it writes the new field in a document, it fills the new field from the old one (for an array, every element into the map, under a key derived from the element), so that the new field is complete. This is a write of a document the app changes anyway, not a backfill of every document.
2. **Wait** until the bridge version runs on every device, and until those devices have synced what they wrote before they were updated.
3. **Reader version**: writes both fields, reads the new one, and falls back to the old one where the new one is `MISSING`. Bridge devices that remain still see its writes in the old field.
4. **Wait** until the reader version runs on every device, then stop writing the old field.

A version that writes only the new field while older versions run hides its edits from them, and one that reads the new field while older versions write only the old one misses theirs. This follows from the merge rules (each field merges on its own, and a version sees only the field it reads); we have not tested the sequence on devices.

A counter that replaces a register (`stockCount` for `stock`) does not fit these stages, because a new counter starts at 0 and increments made on the bridge give only the change since then. Set its starting value from one device with `RESTART WITH` while every device is online and in sync (see [RESTART](#restart)), or derive the value from event documents instead.

### Changing CRDT types

**Introduce a new field with the new type instead of changing the type of an existing one.** Changing how a field is typed (an array or a REGISTER object to a MAP, or a number to a COUNTER) is a breaking change too: the old and new values coexist under the same key and statements see different values depending on their declarations (see [Keep type declarations consistent](#keep-type-declarations-consistent)). In our testing with SDK 5.0.3, 5.1.0, and 5.2.0, an old app version wrote `SET stock = 9` while a new version concurrently ran `APPLY stock INCREMENT BY -1` as a COUNTER: after sync, the field held both `9` and `-1` (the new counter started at 0), and an undeclared `SELECT` returned whichever had been written later (see [Changing a register to a counter leaves both values](../knowledge/observations/merge-behavior.md#changing-a-register-to-a-counter-leaves-both-values)). For example, add `stockCount` as a COUNTER next to the old `stock` register, and give it its starting value as described in [A field that replaces another](#a-field-that-replaces-another).

## Timestamps

Every device stamps documents with its own clock, and device clocks disagree. Store timestamps in a format that DQL date functions understand, and design so that clock differences cannot corrupt your data.

### Store UTC with a zone designator

Use one of two representations consistently within a field (in JavaScript, never pass a `Date` object: in our testing, it was stored as an empty object `{}` without an error; see [JavaScript values that are not plain JSON change when stored](../knowledge/observations/javascript-sdk.md#javascript-values-that-are-not-plain-json-change-when-stored)):

| Format | Notes |
|---|---|
| ISO-8601 string in UTC with a zone designator (recommended), with a fixed millisecond precision, for example `2026-10-08T10:30:00.123Z` | Human-readable; compares as text when every value uses the same precision |
| Epoch milliseconds (integer) | Compact; DQL date functions accept epoch milliseconds, and `date_add`, `date_sub`, and `date_trunc` return them for numeric input |

> **Note:** A language's default date formatting can produce local time **without** a zone designator (for example, `2026-10-08T19:30:00.123456`; Dart's `toIso8601String()` does so for a local `DateTime`). DQL date functions return `MISSING` for such strings (`date_part`, `date_diff`, `date_add`, `date_cast`, and the others), and no error is raised. Convert to UTC and include the zone designator. <!-- lint-ignore -->

**Use one fixed-precision helper for timestamps that are sorted or compared.** A language's default formatting may vary the precision: Dart's `toIso8601String()`, for example, includes microseconds on native platforms only when they are non-zero, so one device produces both `.123456Z` and `.123Z`. ISO strings sort chronologically as text only when they share the same format: `'2026-10-08T10:30:45.123456Z'` sorts before `'2026-10-08T10:30:45.123Z'` although it is later, because `4` comes before `Z` in string order, and `'2026-10-08T10:30:45Z'` sorts after `'2026-10-08T10:30:45.123Z'` because `Z` comes after `.` (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)). When a field is used in `ORDER BY`, range filters, or comparisons, produce every value with one helper that fixes the precision. The examples in this guide use such a helper for every timestamp; define it once in your app (see the code below).

```sql
-- ✅ GOOD: Consistent UTC timestamps from the one helper
-- Arguments: {"id": "order-1", "readyAt": "2026-10-08T10:30:00.123Z"}
UPDATE orders SET readyAt = :readyAt WHERE _id = :id
```

```sql
-- ❌ BAD: Local time without a zone. DQL date functions return MISSING for it,
-- and values written in different time zones do not compare correctly.
-- Arguments: {"id": "order-1", "readyAt": "2026-10-08T19:30:00.123456"}
UPDATE orders SET readyAt = :readyAt WHERE _id = :id
```

The code for a fixed-precision UTC helper: [Flutter](platforms/flutter.md#ids-and-timestamps-in-flutter) · [JavaScript](platforms/javascript.md#ids-and-timestamps-in-javascript) · [Kotlin](platforms/kotlin.md#ids-and-timestamps-in-kotlin) · [Swift](platforms/swift.md#ids-and-timestamps-in-swift).

### Querying by time

Compare stored timestamps with parameters in the same format. Range filters on a timestamp field can use an index:

```sql
SELECT * FROM orders
WHERE createdAt >= :since
ORDER BY createdAt DESC
```

DQL date functions work with zoned ISO strings and epoch milliseconds. For example, `date_diff(date1, date2, part)` returns `date1 - date2` in the given unit, and `date_format(:epochMs, '')` converts epoch milliseconds to an ISO string. See [DQL Functions and Operators](../knowledge/dql-functions.md) for the signatures.

```sql
SELECT _id, date_diff(:now, createdAt, 'minute') AS ageMinutes
FROM orders
WHERE status = 'open'
```

### Clock drift

Device clocks drift and can be set wrong. iOS clocks are usually within 100 ms of accurate time, while Android devices can deviate by several seconds; a device whose time was set manually can be off by much more. Expect timestamps that appear to be in the future, and records created at the same moment on two devices with timestamps seconds apart.

**✅ DO:**
- Treat stored timestamps as approximate information for display, filtering, and retention, not as a source of truth for ordering.
- If precise time is critical, query a time server (NTP) and keep a correction offset in your app.
- Tolerate small negative durations (an "ended" time slightly before a "started" time written by another device).

**❌ DON'T:**
- Rely on your own timestamp fields to decide which of two conflicting writes should win. Ditto resolves concurrent register writes with its own Hybrid Logical Clock, independently of your fields; and if you compare your own timestamps at read time, a device with a fast clock always wins. Where order matters, model the data so that the merge cannot go wrong: a counter, a map keyed by ID, or an audit log with a derivation such as "most advanced state" (see [Event History and Audit Logs](#event-history-and-audit-logs)).
- Use timestamps as document IDs (see [Document IDs](#document-ids)).

> **Note (SDK 5.1.0 and 5.2.0):** Ditto's last-writer-wins follows device clocks too: its Hybrid Logical Clock starts from the device's clock and, as our tests suggest, moves ahead to the clock of each running peer that the device syncs with, not to the timestamps of stored documents (see [A stored document with future timestamps does not advance Ditto's clock](../knowledge/observations/clocks-and-time.md#a-stored-document-with-future-timestamps-does-not-advance-dittos-clock)). In our testing, a device whose clock was 5 seconds ahead won over a write of the same field made 2 seconds later (see [A device whose clock runs ahead wins concurrent edits made within the clock difference](../knowledge/observations/clocks-and-time.md#a-device-whose-clock-runs-ahead-wins-concurrent-edits-made-within-the-clock-difference)), and a clock that ran ahead spread to every device that synced with that device, directly or through a hub, for every document, until every app that had run with the future time restarted or real time caught up (see [Clocks and Time](../knowledge/observations/clocks-and-time.md), [A clock running ahead spreads to devices that sync with it](../knowledge/observations/clocks-and-time.md#a-clock-running-ahead-spreads-to-devices-that-sync-with-it), and [Ditto's clock stays ahead until the app restarts](../knowledge/observations/clocks-and-time.md#dittos-clock-stays-ahead-until-the-app-restarts)). Fields that devices may write at the same time therefore need a shape whose merge does not depend on which write is later, as the list above describes.
