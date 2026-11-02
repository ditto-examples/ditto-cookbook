# Data Modeling

Ditto is a schemaless document database, but every value you write is stored as a CRDT (conflict-free replicated data type). The CRDT type of a field decides what happens when two devices change it while they are disconnected and then sync. Data modeling in Ditto is therefore mostly about one question: **when concurrent edits meet, does the merge produce the result your business needs?**

How each CRDT type merges is described in [CRDT Types and Merge Behavior](../knowledge/crdt-types.md); read it before this page. This page covers strict mode, the choice between arrays and maps, document structure and size, relationships (including JOIN, SDK 5.1+), document IDs, counters, event history, default data, schema evolution, and timestamps.

**Design checklist:**

- Multiple devices will modify the same data while offline. Model every field for the merge you want.
- Prefer field-level updates over whole-document writes.
- Use maps keyed by ID (not arrays) for collections of items that several devices edit.
- Keep documents well under 256 KiB and store binary data as attachments.
- Use UUIDs or other collision-free IDs, never sequential numbers.
- Store timestamps in UTC with a zone designator, and produce every timestamp that is sorted or compared with one fixed-precision helper.

## Strict Mode

`DQL_STRICT_MODE` controls how Ditto types values that a statement does not declare explicitly. **The default is `false`**, and the rest of this guide assumes it. You can check the current value:

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

> **Note (SDK 5.1.0 and 5.2.0):** With `DQL_STRICT_MODE = true`, the query planner does not use indexes: `EXPLAIN` shows a full collection scan even for a query on an indexed field (ID lookups are not affected; see [Strict mode and data types](indexing-and-performance.md#strict-mode-and-data-types) and [With strict mode on, the planner does not use secondary indexes](../knowledge/observations/dql-behavior.md#with-strict-mode-on-the-planner-does-not-use-secondary-indexes)). Keep the default (`false`) if you rely on indexes for query performance.

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

```dart
// ✅ GOOD: The address is a REGISTER, so a concurrent edit can never produce a
// mix of two different addresses (for example, the street of one and the city
// of the other). The declaration appears in every statement.
Future<void> setShippingAddress(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> address,
) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION customers (shippingAddress REGISTER)
    SET shippingAddress = :address
    WHERE _id = :id
    ''',
    arguments: {'id': customerId, 'address': address},
  );
}
```

### Keep type declarations consistent

A field can hold more than one CRDT value at the same time when statements disagree about its type. Each statement reads or writes the value of the type it declares (or infers), and an undeclared `SELECT` shows the most recently written type (see [Changing a register to a counter leaves both values](../knowledge/observations/merge-behavior.md#changing-a-register-to-a-counter-leaves-both-values)). Mixed declarations therefore produce results that look like data loss, even on a single device:

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

System parameters are not persisted. If you choose `DQL_STRICT_MODE = true`, set it **every time** you open Ditto, in `DittoConfig.systemParameters` (SDK 5.2+), so that it is in effect before any query, observer, or sync runs. On SDK 5.1, run `ALTER SYSTEM` after `Ditto.open` and before `ditto.sync.start()`, running queries, or registering observers (subscriptions may be registered before it). See [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters) for the full startup sequence.

```dart
// Set on every launch: the value resets to the default when Ditto is reopened.
const strictModeConfig = DittoConfig(
  databaseID: 'YOUR_DATABASE_ID',
  connect: DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
  systemParameters: {'DQL_STRICT_MODE': true},
);
```

### Peers with different settings

Strict mode is a local setting of each peer. Data syncs between peers regardless of their settings, but **each peer interprets the data with its own setting**. A peer with `DQL_STRICT_MODE = true` does not show undeclared objects that another peer wrote as maps, so nested updates from a `false` peer appear to be missing on the `true` peer, although they have synced correctly. In our testing with SDK 5.1.0 and 5.2.0, one strict and one non-strict peer showed these effects (see [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)):
- A nested update such as `SET obj.a = 2` on the strict peer failed with `Unsupported DML operation on REGISTER field "obj"` when `obj` had been written as an object by a strict peer.
- After concurrent edits, an undeclared `SELECT *` kept showing different values for the same document on the two peers.

The remedies are to use the same setting on all peers (recommended) or to declare the fields as `MAP` on the strict peers.

**✅ DO:**
- Use the same `DQL_STRICT_MODE` value on every peer, in every app and backend integration that writes to the same database.
- If a backend writes through the HTTP API, use the `/api/v5/store/execute` endpoint, which supports `DQL_STRICT_MODE = false`.

**❌ DON'T:**
- Mix settings across peers unless every statement on the strict peers declares the map fields it reads.

## Arrays and Maps

Arrays are registers: the whole array is replaced on every write, and when two devices change the same array concurrently, one version wins and the other change is lost silently (see [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)). Maps keyed by ID merge each entry independently (see [With three offline devices, counters and maps keep every change](../knowledge/observations/merge-behavior.md#with-three-offline-devices-counters-and-maps-keep-every-change)). Choose the shape as follows:

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

```dart
/// Adds or updates one line item. The key is passed as data, never spliced
/// into the query. Note: if the order does not exist yet, this creates it.
Future<void> upsertOrderItem(
  Ditto ditto, {
  required String orderId,
  required String itemId,
  required Map<String, dynamic> item,
}) async {
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

```dart
// Map keys used in paths are validated: only UUID-shaped keys are accepted.
final _uuidKey = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Removes one line item. A path cannot be passed as a parameter, so the key
/// is validated before it is placed inside a backtick-quoted path segment.
Future<void> removeOrderItem(
  Ditto ditto, {
  required String orderId,
  required String itemId,
}) async {
  if (!_uuidKey.hasMatch(itemId)) {
    throw ArgumentError.value(itemId, 'itemId', 'must be a lowercase UUID');
  }
  await ditto.store.execute(
    'UPDATE orders UNSET items.`$itemId` WHERE _id = :id',
    arguments: {'id': orderId},
  );
}
```

> **Note (SDK 5.1.0 and 5.2.0):** Removing an entry does not win over a concurrent edit of that entry. In our testing, one device ran `` UNSET items.`item-1` `` while another device changed `` items.`item-1`.quantity `` (see [A key added concurrently survives a later removal as null](../knowledge/observations/merge-behavior.md#a-key-added-concurrently-survives-a-later-removal-as-null)):
> - **Removal first, edit later:** the entry stays with only the edited fields, for example `{"quantity": 5}`.
> - **Edit first, removal later:** the entry stays with the edited fields set to `null`, for example `{"quantity": null}`.
> - **Whole entry rewritten after the removal** (`` SET items.`item-1` = :item `` or `DO UPDATE`): the full entry comes back.
>
> These are "husk" entries, like [husk documents](deletion-and-storage.md#husk-documents). When devices may edit an entry while another removes it, mark it removed instead (`` SET items.`item-1`.removed = true ``). Either way, make readers skip entries whose required fields are missing or `null` (see `orderSubtotalCents` in [Do not store derived values that can diverge](#do-not-store-derived-values-that-can-diverge)).

> **Note (SDK 5.1.0 and 5.2.0):** A removed entry leaves a small record in the document. In our testing, each map key removed with `UNSET` added about 54 bytes to a new device's first sync of the document (for a UUID key), the records stayed after reaping, and writes slowed down as removed keys accumulated (see [Removed map keys keep adding to a new device's first sync](../knowledge/observations/storage-and-deletion.md#removed-map-keys-keep-adding-to-a-new-devices-first-sync)). A map with a bounded set of keys, such as the line items of an order, is not affected. For a long-lived list whose entries come and go, such as open tickets or a task list, store each entry in its own document instead; deleted documents' tombstones are reaped.

**Why:** Splicing unchecked input into a query enables DQL injection. A strict allow-list pattern for map keys keeps the path safe, and all other values still travel as parameters (see [Parameters and Literals](dql.md#parameters-and-literals)).

### Working with arrays

DQL has no element-level assignment (`SET tags[0] = ...` is a parser error). Build the new array in Dart and write it back; the write replaces the whole register:

```dart
// The array is a register: this write replaces it as a whole. Reading and
// writing in one transaction keeps two local calls from interleaving and
// dropping a tag; a concurrent edit on another device can still win the merge.
Future<void> addTag(Ditto ditto, String productId, String tag) async {
  await ditto.store.transaction(hint: 'addTag', (tx) async {
    final result = await tx.execute(
      'SELECT tags FROM products WHERE _id = :id',
      arguments: {'id': productId},
    );
    if (result.items.isEmpty) return;
    final current = (result.items.first.value['tags'] as List?) ?? const [];
    await tx.execute(
      'UPDATE products SET tags = :tags WHERE _id = :id',
      arguments: {'id': productId, 'tags': [...current, tag]},
    );
  });
}
```

To find documents whose array contains a value, use `IN` with the array field or `array_contains`:

```sql
SELECT * FROM products WHERE :tag IN tags
```

```sql
SELECT * FROM products WHERE array_contains(tags, :tag)
```

An index on an array field matches only the complete array value, so element lookups such as these scan the collection. Scalar fields inside map entries, by contrast, can be indexed with their full path (see [Creating Indexes](indexing-and-performance.md#creating-indexes) and [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

### Incremental adoption

You do not have to convert every array at once. Start with the simple shape, and convert an array to a map as soon as you know that more than one device writes it. Keep the collection name and `_id` structure unchanged so that documents stay compatible, but write the map to a **new field** (for example, `lineItems` next to the old `items` array). Writing a map under the array's field name changes its CRDT type: the old array and the new map then coexist under the same key, and app versions that still write the array make the field switch back and forth (see [Changing CRDT types](#changing-crdt-types)).

## Document Structure

### Prefer field-level updates

Update only the fields that the user changed, so that concurrent edits to other fields survive. The rule and its examples are in [Prefer field-level updates over whole-document rewrites](dql.md#prefer-field-level-updates-over-whole-document-rewrites); this subsection covers the one case that an upsert does not make safe, a stale in-memory copy.

`ON ID CONFLICT DO UPDATE_LOCAL_DIFF` compares the incoming document with the local document and skips fields whose values are equal (those fields keep their timestamps); every field that differs is written. That suits upserts and re-imports of data that another system owns, but it does not protect a stale copy: if a change from another device has already reached the local store and your in-memory copy still holds the old value, the old value differs from the stored one and is written back (see [Rewriting an unchanged value overwrites concurrent edits](../knowledge/observations/merge-behavior.md#rewriting-an-unchanged-value-overwrites-concurrent-edits)). (`DO UPDATE` writes every field you pass, even unchanged ones, which gives those fields new timestamps and can override a concurrent change from another device.) See [INSERT and Conflict Handling](dql.md#insert-and-conflict-handling) for all conflict policies.

**✅ DO:**
- Write only the fields that the user changed, with `UPDATE ... SET` (or with a partial document in an upsert).

**❌ DON'T:**
- Write back a whole in-memory copy of a document, even with `DO UPDATE_LOCAL_DIFF`.

```dart
// ❌ BAD: Writing back a whole in-memory copy after the user changed only the
// status. If another device changed tableNumber to 12 after this copy was
// loaded, the stale value 7 is written back. DO UPDATE_LOCAL_DIFF does not
// prevent this, because 7 differs from the stored 12 (and DO UPDATE would also
// rewrite every unchanged field).
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'order': {'_id': 'order-1', 'status': 'ready', 'tableNumber': 7},
  },
);

// ✅ GOOD: Only the field the user changed is written, so a concurrent change
// to tableNumber on another device is kept.
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :id',
  arguments: {'id': 'order-1', 'status': 'ready'},
);
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

```dart
// ✅ GOOD: Store the source data; derive totals at read time. Entries with a
// missing or null price or quantity (an entry removed on one device while
// another device edited it) are skipped instead of crashing the screen.
int orderSubtotalCents(Map<String, dynamic> order) {
  final items = (order['items'] as Map<String, dynamic>?) ?? const {};
  var subtotal = 0;
  for (final entry in items.values) {
    if (entry is! Map<String, dynamic>) continue;
    final price = entry['unitPriceCents'];
    final quantity = entry['quantity'];
    if (price is! int || quantity is! int) continue;
    subtotal += price * quantity;
  }
  return subtotal;
}
```

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
- Keep UI and device-local state in widget state, a state-management layer, or local preferences.
- Initialize flags you will filter on when you create the document (for example, `isDeleted: false`), or filter with `coalesce(isDeleted, false) = false`. A missing field is `MISSING`, not `false` (see [MISSING and NULL](dql.md#missing-and-null)).

### Field names

- Field names are always strings. Use one convention (this guide uses camelCase).
- If a field name collides with a DQL keyword or contains special characters (see [Field names can contain dots and backticks, or be empty](../knowledge/observations/dql-behavior.md#field-names-can-contain-dots-and-backticks-or-be-empty)), quote it with backticks in queries (for example, `` `value` ``).
- Never name a collection `collection`; it is a DQL keyword.
- Names are case-sensitive: `Orders` and `orders` are different collections, and `createdAt` and `createdat` are different fields (see [Names are case-sensitive, and most DQL keywords work as bare names](../knowledge/observations/dql-behavior.md#names-are-case-sensitive-and-most-dql-keywords-work-as-bare-names)).

## Document Size Limits

Ditto enforces two thresholds on the **size of each stored document**:

| Threshold | Default | System parameter | Behavior |
|---|---|---|---|
| Soft limit | 256 KiB (262,144 bytes) | `DOCUMENT_SIZE_SOFT_LIMIT_BYTES` | The write succeeds and a warning is logged |
| Hard limit | 5 MiB (5,242,880 bytes) | `DOCUMENT_SIZE_HARD_LIMIT_BYTES` | `INSERT` and `UPDATE` statements on this device that would exceed it **fail**; the stored document is unchanged. Changes that arrive from other devices are not checked in 5.1.0, and are dropped on the receiving device in 5.2.0 (see below and [An oversized merge ends differently on each release](../knowledge/observations/documents-and-limits.md#an-oversized-merge-ends-differently-on-each-release)). SDK 5.0.3 did not check the limit in our testing (see [SDK 5.0.3 does not check the hard size limit when a document is written](../knowledge/observations/documents-and-limits.md#sdk-503-does-not-check-the-hard-size-limit-when-a-document-is-written)) |

Log and error messages:

```text
[Warning] Document `_id = "s300k"` size is 307.4 KB exceeds recommended limit of 262.1 KB bytes and might have reduced performance

Query failed: DQL Internal execution error: Insert failed: <store> Document `_id = "s5m1"` size is 5243067 bytes and exceeds limit of 5242880 bytes
```

In Flutter, a failed statement throws a `DittoException`; catch it like any other DQL error.

> **Note (SDK 5.1.0):** The hard limit is checked only when a device writes, not when changes from other devices merge. In our testing, two devices that each added 3 MiB to the same document while offline both stored the 6 MiB document without an error, and from then on **every `UPDATE` of that document failed on every device** until an `UNSET` removed enough data (see [On SDK 5.2.0, an oversized merge leaves devices with different versions](../knowledge/observations/documents-and-limits.md#on-sdk-520-an-oversized-merge-leaves-devices-with-different-versions)). The same happens when devices use different hard limits: a device with a lower limit receives larger documents from other devices but cannot update them. Keep large or growing data out of documents (attachments, separate collections), so that even combined offline additions stay far below the limit.
>
> **Note (SDK 5.2.0):** A device on 5.2.0 drops a change that would push a document over its hard limit, so the devices keep different versions of the document, and both list it in `system:sync_degradations` with the reason `documentTooBig` (see [System Virtual Collections](../knowledge/system-reference.md#system-virtual-collections)); no API reports an error. In our testing, updates of that document then reached neither device, while other documents kept syncing, until one device evicted it, and **the evicting device lost its own changes to the document** (see [An oversized document stops syncing until one side evicts it](../knowledge/observations/documents-and-limits.md#an-oversized-document-stops-syncing-until-one-side-evicts-it)). To recover, evict the document on the device whose changes you can afford to lose, and include `system:sync_degradations` in your diagnostics. On both releases, the protection is the same: keep documents far below the limit.

**Why the limits matter:** Size affects local storage and memory on every device holding the document, serialization time, CRDT merge cost (which scales with document size, not change size), and initial replication. Over Bluetooth LE (roughly 20 KB/s in practice), a 256 KiB document takes more than 10 seconds to replicate the first time (sync traffic is compressed, so content that compresses well goes faster; see [Sync traffic is compressed and carries field-level changes](../knowledge/observations/subscriptions-and-replication.md#sync-traffic-is-compressed-and-carries-field-level-changes)). Later edits sync only the changed fields, but a document that many devices have written stays heavier: in our testing, a field that 300 devices had written cost about 11 times as much on a new device's first sync as a field that one device had written as often, also after the value had been overwritten (see [A document grows with the number of devices that wrote it](../knowledge/observations/documents-and-limits.md#a-document-grows-with-the-number-of-devices-that-wrote-it)). A shared document that every device writes (store settings, a tally that every device increments) grows with the number of devices that ever wrote it, including reinstalled devices, which write as new devices.

**✅ DO:**
- Design documents to stay well below 256 KiB.
- Store images, PDFs, and other binary content as attachments; attachments are fetched separately and do not count toward the document size (see [Attachments](attachments.md)).
- Move data that grows without bound (order history, readings, comments) into its own collection.
- Leave both limits at their defaults. If you change them, change them on every peer in the same release: a device with a lower hard limit cannot update documents that arrive larger than its limit. (In SDK 5.1.0 and 5.2.0, a hard limit set below the soft limit is not enforced; see [The documented parameter defaults match SHOW ALL](../knowledge/observations/configuration-and-diagnostics.md#the-documented-parameter-defaults-match-show-all).)

**❌ DON'T:**
- Embed base64-encoded files in documents.
- Append to a nested map forever.
- Raise the hard limit to make a large document fit.

```dart
// ✅ GOOD: Handle the size error at the call site that may produce it.
Future<bool> saveNotes(Ditto ditto, String visitId, String notes) async {
  try {
    await ditto.store.execute(
      'UPDATE visits SET notes = :notes WHERE _id = :id',
      arguments: {'id': visitId, 'notes': notes},
    );
    return true;
  } on DittoException catch (error) {
    // The message contains "exceeds limit of ... bytes" for oversized documents.
    showError(error); // your app's error UI
    return false;
  }
}
```

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

```dart
// One subscription syncs the order with all of its items, and every write to an
// item is an atomic update of the order document. Register it once in a
// long-lived service and cancel it when it is no longer needed (see StoreSync below).
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE storeId = :storeId',
  arguments: {'storeId': 'store-12'},
);
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

```dart
/// Keeps the three collections needed by the order screens in sync.
/// Subscriptions belong to an app- or feature-level service, not to a screen.
class StoreSync {
  StoreSync(this.ditto, this.storeId);

  final Ditto ditto;
  final String storeId;
  final List<SyncSubscription> _subscriptions = [];

  Future<void> start() async {
    await ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)',
    );
    _subscriptions.addAll([
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription(
        'SELECT * FROM orderItems WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription('SELECT * FROM products'),
    ]);
  }

  void stop() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
```

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

Observe the join with the standard observer pattern (see [Joins in observers](dql.md#joins-in-observers) and [Store Observers in Flutter](observers.md#store-observers-in-flutter)). If the `orderId` can change while the widget is mounted, re-register the observer in `didUpdateWidget` (see [Filter locally instead of re-registering](sync-and-subscriptions.md#filter-locally-instead-of-re-registering)).

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

Every document has an `_id` that is unique within its collection. If you omit `_id`, Ditto generates one. Do not depend on the format of generated IDs; generate your own when other code needs to know or construct the ID.

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

```dart
/// Copies an order to a new ID and deletes the original, atomically.
/// Both statements declare the order's COUNTER, ATTACHMENT, and REGISTER
/// fields exactly as the other statements on orders do, so the copy keeps
/// their CRDT types. Undeclared objects such as shippingAddress are MAPs.
Future<void> moveOrder(Ditto ditto, String oldId, String newId) async {
  await ditto.store.transaction(hint: 'moveOrder', (tx) async {
    final result = await tx.execute(
      '''
      SELECT * FROM COLLECTION orders
        (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
      WHERE _id = :id
      ''',
      arguments: {'id': oldId},
    );
    if (result.items.isEmpty) return;
    final copy = Map<String, dynamic>.from(result.items.first.value)
      ..['_id'] = newId;
    await tx.execute(
      '''
      INSERT INTO COLLECTION orders
        (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
      DOCUMENTS (:doc)
      ''',
      arguments: {'doc': copy},
    );
    await tx.execute(
      'DELETE FROM orders WHERE _id = :id',
      arguments: {'id': oldId},
    );
  });
}
```

### Generation strategies

| Strategy | Use when | Notes |
|---|---|---|
| **UUID v4** (primary recommendation) | Almost always | 122 random bits; independent devices never coordinate. Use a maintained package (for example, `uuid` on pub.dev) or the helper below |
| **ULID** or another time-ordered random ID | You want IDs that sort roughly by creation time | Ordering follows each device's clock, so it is only approximate across devices; the ID reveals its creation time |
| **Composite object** | Permissions or subscriptions are scoped by owner, location, or tenant; you group documents by a parent | Combine stable scope fields with a UUID: `{"storeId": "s1", "orderId": "<uuid>"}` |
| **Natural key** | The domain already has a globally unique, immutable key (a SKU, an email address used as an account key) | Two devices that create the same entity intentionally end up with one document whose fields merge |
| **Generated by Ditto** (omit `_id`) | Nothing else needs to know the ID before the insert | Read it back with `result.mutatedDocumentIDs()` |

```dart
import 'dart:math';

final _random = Random.secure();

/// Returns a random (version 4) UUID such as "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f".
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<String> createOrder(Ditto ditto, String storeId) async {
  final orderId = uuidV4();
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId,
        'storeId': storeId,
        'status': 'open',
        // utcTimestamp() is defined in the Timestamps section.
        'createdAt': utcTimestamp(),
      },
    },
  );
  return orderId;
}
```

### Composite IDs for permission scoping and grouping

Ditto permission rules are queries on `_id` and its subfields. A hierarchical composite `_id` lets you grant access at any level, for example a whole region (`"_id.region == 'eu'"`) or a single store (`"_id.storeId == 'store-12'"`); see [Design `_id` for permission scoping](security.md#design-_id-for-permission-scoping) for the rule format. The same subfields can filter subscriptions and queries (`WHERE _id.storeId = :storeId`), and they can be indexed (see [The sending peer evaluates a subscription's WHERE clause like a local query](../knowledge/observations/subscriptions-and-replication.md#the-sending-peer-evaluates-a-subscriptions-where-clause-like-a-local-query)). Filtering on the complete `_id` value uses a direct ID lookup.

```dart
Future<void> createStoreOrder(
  Ditto ditto, {
  required String region,
  required String storeId,
  required String orderId,
}) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': {'region': region, 'storeId': storeId, 'orderId': orderId},
        'status': 'open',
      },
    },
  );
}

// Each store device syncs only its own store's orders. The caller owns the
// returned subscription and cancels it when it is no longer needed.
SyncSubscription subscribeToStore(Ditto ditto, String storeId) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE _id.storeId = :storeId',
      arguments: {'storeId': storeId},
    );
```

```sql
CREATE INDEX IF NOT EXISTS idx_orders_id_storeId ON orders (_id.storeId)
```

Put only **immutable** attributes into a composite `_id`. A store that might move to another region, or an order that might be reassigned to another store, needs those values as regular fields instead.

### Never use sequential or timestamp-only IDs

Devices that are offline cannot coordinate a sequence. Two of them will generate the same "next" ID, and after sync the two documents become one document whose fields merge: data from different orders ends up mixed together (see [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)). Timestamp-only IDs fail the same way whenever two devices create a record in the same millisecond, and device clocks are not reliable anyway (see [Timestamps](#timestamps)).

```dart
// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
String badSequentialId(int dailyCount) => 'order-$dailyCount';

// ❌ BAD: Collides when two devices write within the same millisecond.
String badTimestampId() => 'order-${DateTime.now().millisecondsSinceEpoch}';
```

### Human-readable display IDs

Customers and staff need short numbers such as "#A-0042". Keep them **separate from `_id`**, and treat them as labels rather than unique keys. One approach that avoids coordination is to prefix with a stable device or terminal code that you assign, and to show the date alongside the number:

```dart
/// A display label, not an identifier: uniqueness is not guaranteed across
/// devices, so never use it as _id or as a lookup key.
String displayNumber(String terminalCode, int localSequence) =>
    '$terminalCode-${localSequence.toString().padLeft(4, '0')}';

Future<void> createOrderWithLabel(
  Ditto ditto, {
  required String orderId,
  required String terminalCode,
  required int localSequence,
}) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId, // UUID
        'displayNumber': displayNumber(terminalCode, localSequence),
        'createdAt': utcTimestamp(), // see the Timestamps section
      },
    },
  );
}
```

## Counters

A `COUNTER` field holds an integer that any device can increment or decrement. Increments and decrements from all devices are combined, so concurrent changes add up instead of overwriting each other (see [With three offline devices, counters and maps keep every change](../knowledge/observations/merge-behavior.md#with-three-offline-devices-counters-and-maps-keep-every-change)). Counter operations use the `APPLY` clause, not `SET`:

| Operation | Statement |
|---|---|
| Increment or decrement | `APPLY f INCREMENT BY n` (use a negative `n` to decrement; `n` must be an integer; see [Counters accept only integers](../knowledge/observations/merge-behavior.md#counters-accept-only-integers)) |
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

```dart
Future<void> createProduct(Ditto ditto, String productId, String name) async {
  await ditto.store.execute(
    'INSERT INTO COLLECTION products (viewCount COUNTER) DOCUMENTS (:product)',
    arguments: {
      'product': {'_id': productId, 'name': name, 'viewCount': 0},
    },
  );
}

Future<void> recordView(Ditto ditto, String productId) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION products (viewCount COUNTER)
    APPLY viewCount INCREMENT BY 1
    WHERE _id = :id
    ''',
    arguments: {'id': productId},
  );
}
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

`RESTART WITH n` sets the counter to a specific value and `RESTART` sets it to zero. When devices perform `RESTART` operations concurrently, the last write wins.

> **Note (SDK 5.1.0 and 5.2.0):** A `RESTART` discards **every increment that the restarting device had not received when it ran the restart**. That includes increments that other devices make *after* the restart (by the clock) until the restart reaches them. Only increments made after a device has received the restart are added to the new value. In our testing, a counter at 10 restarted with 100 on one peer while another peer, which had not yet received the restart, incremented it by 5, ended at 100 whichever peer wrote first by the clock, and at 105 only when the restart had already synced before the increment (see [The merge table held on SDK 5.1.0 and 5.2.0](../knowledge/observations/merge-behavior.md#the-merge-table-held-on-sdk-510-and-520)).

A typical consequence: a stock recount with `RESTART WITH :counted` silently erases the sales that offline devices record until they receive the recount. Re-importing the stock list with an upsert has the same effect (see [Writing documents that contain counters](#writing-documents-that-contain-counters) and [An upsert that declares a counter restarts it](../knowledge/observations/merge-behavior.md#an-upsert-that-declares-a-counter-restarts-it)).

Use `RESTART` only for occasional corrections made by one authority while no other device is incrementing the same counter unsynced, for example a recount done while every till is online and in sync. If devices keep recording changes offline during a recount, keep the recounts and the changes as separate event documents and derive the stock from them (see [When counters are appropriate](#when-counters-are-appropriate)).

```dart
// Run only while every device that increments stockCount is online and in
// sync; increments that this device has not received yet are discarded.
Future<void> recordStockCount(Ditto ditto, String itemId, int counted) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION inventory (stockCount COUNTER)
    APPLY stockCount RESTART WITH :counted
    WHERE _id = :id
    ''',
    arguments: {'id': itemId, 'counted': counted},
  );
}
```

### When counters are appropriate

| ✅ Good fit | ❌ Poor fit, and what to use instead |
|---|---|
| Likes, votes, view counts | **Unique sequence numbers** (invoice or ticket numbers): two offline devices both read 41 and both produce 42. Use UUIDs plus a display label (see [Document IDs](#document-ids)) |
| Usage metrics and tallies from many devices (a counter grows with the number of devices that incremented it; see [A document grows with the number of devices that wrote it](../knowledge/observations/documents-and-limits.md#a-document-grows-with-the-number-of-devices-that-wrote-it)) | **Balances that must be validated** (account balances, "never below zero"): a counter cannot enforce a constraint, and concurrent decrements can drive it negative (see [Conditional updates on two offline devices both succeed](../knowledge/observations/merge-behavior.md#conditional-updates-on-two-offline-devices-both-succeed)). Record transactions as events and validate when you derive the balance |
| Inventory adjustments where every device records its own sales or receipts | **Values derivable from documents you already store** (number of open orders): compute them with a query such as `SELECT COUNT(*) ...` |
| Values recalibrated occasionally with `RESTART WITH`, while all devices that change them are in sync | **Fractional amounts**: `COUNTER` is integer-only (`INCREMENT BY 1.5` fails with `Expected 1.5 to be an integer value`, and a declared `INSERT` of 2.5 fails too; values are never rounded). Count in minor units such as cents or grams. The legacy `PN_COUNTER` accepts fractions, but rounding errors accumulate: in our testing, ten increments of 0.1 gave `0.9999999999999999` (see [Counters accept only integers](../knowledge/observations/merge-behavior.md#counters-accept-only-integers)) |

**❌ DON'T:**
- Initialize a counter with an undeclared `INSERT`.
- Overwrite a counter with `SET`; use `RESTART WITH`.
- Mix `COUNTER` and the legacy `PN_INCREMENT` operator on one field.
- Use `RESTART WITH` to recalibrate a counter that other devices keep changing while offline.

**Why:** Counters (`COUNTER`, and the legacy `PN_COUNTER`) are the only CRDT types that add concurrent changes together, also between devices that are online (see [Conditions and Arithmetic across Devices](../knowledge/crdt-types.md#conditions-and-arithmetic-across-devices)). Everything else (registers, map entries) keeps one of the concurrent values, so `SET stockLevel = stockLevel - 1` on two devices loses one of the decrements. (A field reference in a `SET` value needs SDK 5.1 or later; in our testing, 5.0.3 rejected it with `Forbidden: Document references in mutation values`; see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../knowledge/observations/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503) and [Read-modify-write increments lose most concurrent updates](../knowledge/observations/merge-behavior.md#read-modify-write-increments-lose-most-concurrent-updates).)

```dart
// ❌ BAD: Read-modify-write on a register. Two devices that each sell one item
// while the stock is 10 both write 9; after sync the stock is 9 instead of 8.
Future<void> sellOneIncorrectly(Ditto ditto, String itemId) async {
  await ditto.store.execute(
    'UPDATE inventory SET stockLevel = stockLevel - 1 WHERE _id = :id',
    arguments: {'id': itemId},
  );
}

// ✅ GOOD: Concurrent decrements are combined.
Future<void> sellOne(Ditto ditto, String itemId) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION inventory (stockCount COUNTER)
    APPLY stockCount INCREMENT BY -1
    WHERE _id = :id
    ''',
    arguments: {'id': itemId},
  );
}
```

## Event History and Audit Logs

When every change matters (status transitions, adjustments, sensor readings), record each change as a new fact instead of overwriting one field. Three patterns cover most needs.

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

```dart
/// Appends a status transition. The timestamp key is passed as data inside a
/// partial document; unchanged entries are not rewritten.
Future<void> appendStatus(Ditto ditto, String orderId, String status) async {
  // utcTimestamp() (see the Timestamps section) fixes millisecond precision,
  // which keeps keys consistent across platforms.
  final key = utcTimestamp();
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': orderId,
        'statusLog': {key: status},
      },
    },
  );
}

// The workflow states, from earliest to most advanced.
const _statusOrder = ['created', 'confirmed', 'shipped', 'delivered'];

/// Derives the current status as the most advanced state, so a late write from
/// a device that was offline cannot move the order backwards.
String? currentStatus(Map<String, dynamic> order) {
  final log = (order['statusLog'] as Map<String, dynamic>?) ?? const {};
  String? best;
  for (final status in log.values.whereType<String>()) {
    if (best == null ||
        _statusOrder.indexOf(status) > _statusOrder.indexOf(best)) {
      best = status;
    }
  }
  return best;
}
```

Common derivation strategies are: the latest timestamp (simple linear workflows), the **most advanced state** (progressions that must not regress), the earliest occurrence ("when did this first happen?"), or custom rules that combine entries. A variant uses the status as the key and the timestamp as the value; it records "did this state happen, and when" but keeps only the latest time for a state that is entered more than once.

### Pattern 2: Append-only event documents

When history is unbounded, accessed independently, or needed by other devices without the parent, write each event as its **own document** with a UUID `_id`. Events are never updated, so there is nothing to merge, and the parent document stays small.

For events that arrive often, such as sensor readings, collect them for a short interval (for example, one second) and write them with one `INSERT` that has several documents (`INSERT INTO readings DOCUMENTS (:r1), (:r2), ...`). Each statement is one commit, and both the writing and the receiving device spend CPU on every commit: in our testing, one document per statement topped out at about 600 documents a second, while 50 documents per statement reached 5,000 a second at about a twelfth of the CPU per document, and the receiver saw every document, in the order written (see [One document per statement tops out at about 600 writes a second](../knowledge/observations/performance-measurements.md#one-document-per-statement-tops-out-at-about-600-writes-a-second)).

```dart
Future<void> recordOrderEvent(
  Ditto ditto, {
  required String eventId, // a new UUID
  required String orderId,
  required String storeId,
  required String type,
  required String userId,
}) async {
  await ditto.store.execute(
    'INSERT INTO orderEvents DOCUMENTS (:event)',
    arguments: {
      'event': {
        '_id': eventId,
        'orderId': orderId,
        'storeId': storeId,
        'type': type,
        'userId': userId,
        // utcTimestamp() is defined in the Timestamps section.
        'occurredAt': utcTimestamp(),
      },
    },
  );
}
```

`utcTimestamp()` (see [Timestamps](#timestamps)) gives every `occurredAt` value the same millisecond precision, so `ORDER BY occurredAt` sorts chronologically:

```sql
SELECT * FROM orderEvents
WHERE orderId = :orderId
ORDER BY occurredAt ASC, _id ASC
```

```dart
// ❌ BAD: Appending to an array. Arrays are registers: if two devices append
// concurrently, one of the appended events is lost after sync.
Future<void> appendEventToArray(
  Ditto ditto,
  String orderId,
  List<dynamic> currentHistory,
  Map<String, dynamic> event,
) async {
  await ditto.store.execute(
    'UPDATE orders SET history = :history WHERE _id = :id',
    arguments: {
      'id': orderId,
      'history': [...currentHistory, event],
    },
  );
}
```

Event collections grow forever; plan their cleanup from the start with eviction (see [EVICT](deletion-and-storage.md#evict)).

### Pattern 3: Current state plus history (two collections)

When you need both the latest value with low latency and a complete history, write each change to two collections:

1. **Current state** (`vehicles`): one document per entity, bounded in size. Real-time screens observe this collection.
2. **History** (`vehiclePositions`): one append-only document per change. Analysis queries read this collection.

Write both in one transaction so that local observers never see one without the other (see [Transactions](transactions.md)). The position is declared as a `REGISTER` because latitude and longitude from two different readings must never be mixed.

```dart
Future<void> recordPosition(
  Ditto ditto, {
  required String vehicleId,
  required String eventId, // a new UUID
  required double lat,
  required double lon,
}) async {
  // utcTimestamp() is defined in the Timestamps section.
  final recordedAt = utcTimestamp();
  await ditto.store.transaction(hint: 'recordPosition', (tx) async {
    await tx.execute(
      'INSERT INTO vehiclePositions DOCUMENTS (:event)',
      arguments: {
        'event': {
          '_id': eventId,
          'vehicleId': vehicleId,
          'position': {'lat': lat, 'lon': lon},
          'recordedAt': recordedAt,
        },
      },
    );
    await tx.execute(
      '''
      INSERT INTO COLLECTION vehicles (position REGISTER)
      DOCUMENTS (:vehicle)
      ON ID CONFLICT DO UPDATE_LOCAL_DIFF
      ''',
      arguments: {
        'vehicle': {
          '_id': vehicleId,
          'position': {'lat': lat, 'lon': lon},
          'lastSeenAt': recordedAt,
        },
      },
    );
  });
}
```

Devices can subscribe to what they need: a live map subscribes only to `vehicles`, and an analysis tool also subscribes to `vehiclePositions`. Keep in mind how transactions replicate: a peer that subscribes to only part of the documents a transaction changed receives only that part, and it can relay only that part to other peers (see [Transactions and Sync](transactions.md#transactions-and-sync)). Peers that need both halves together should subscribe to both collections.

| | Audit-log map | Event documents | Current state + history |
|---|---|---|---|
| Size | Grows the parent document | Parent unaffected | Current state bounded; history grows |
| Atomic with the parent | Yes (one document) | Only with a transaction | Only with a transaction |
| Readable without the parent | No | Yes | Yes |
| Best for | Status and workflow history of one record | Unbounded logs, analytics, compliance trails | Live dashboards plus history |

## Default Data with INITIAL Documents

`INSERT ... INITIAL DOCUMENTS` inserts default data that every peer can create independently, such as built-in categories or default settings. Ditto's [INSERT documentation](https://docs.ditto.live/dql/insert) describes initial documents as inserted "at the beginning of time" and viewed by all peers as the same insert, so several devices can initialize the same default data without overwriting later edits. Initial documents are regular documents: they sync like any other document that a subscription matches. See [INITIAL DOCUMENTS](dql.md#initial-documents) for the syntax.

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

```dart
// Default categories that every device creates at startup. Running this on
// every launch is safe: existing documents, including edited ones, are untouched.
Future<void> seedDefaultCategories(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO categories INITIAL DOCUMENTS (:categories)',
    arguments: {
      'categories': [
        {'_id': 'food', 'name': 'Food', 'sortOrder': 1},
        {'_id': 'drinks', 'name': 'Drinks', 'sortOrder': 2},
        {'_id': 'desserts', 'name': 'Desserts', 'sortOrder': 3},
      ],
    },
  );
}
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

Ditto is schemaless: documents in a collection can have different fields, and sync stores and replicates them without validation. In a mesh, however, devices run different app versions for weeks or months, so a schema change must work while old and new versions read and write the same data.

### Prefer additive changes

Adding a field needs no special pattern. Old app versions ignore fields they do not know; new versions must tolerate documents that do not have the field yet (`MISSING`).

```dart
// ✅ GOOD: A new field, read with a default for older documents.
class Car {
  Car({required this.id, required this.make, this.mileageKm});

  final String id;
  final String make;
  final int? mileageKm; // added in app version 2; absent in older documents

  factory Car.fromDocument(Map<String, dynamic> doc) => Car(
        id: doc['_id'] as String,
        make: doc['make'] as String,
        mileageKm: doc['mileageKm'] as int?,
      );
}
```

Instead of changing the meaning or unit of a field (`mileage` from miles to kilometers), **add a new field** (`mileageKm`) and let each version read the field it understands.

**❌ DON'T:**

- Change a field's type, remove it, or rename it without a versioning pattern. Old peers may crash or show wrong data. A change of CRDT type (for example, from a REGISTER to a MAP) leaves both values under the key, so app versions that declare the field differently read different values (see [Keep type declarations consistent](#keep-type-declarations-consistent)); according to Ditto's documentation, an index on such a field can also return wrong results (see [Strict mode and data types](indexing-and-performance.md#strict-mode-and-data-types)).

> **Note (SDK 5.1.0 and 5.2.0):** Renaming a field in place silently loses what old app versions write. In our testing, a new version renamed `qty` to `quantity` with `UPDATE orders SET quantity = qty UNSET qty` while an old version, offline, set `qty = 5`: depending on the order, the 5 was gone, or it came back in the old field that the new version did not read, and an old version that had already received the rename kept writing `qty` (see [Renaming a field in place hides older versions' edits](../knowledge/observations/merge-behavior.md#renaming-a-field-in-place-hides-older-versions-edits)). Reading both fields (`coalesce(quantity, qty)`) cannot recover the first case. Add the new field and let each version read the field it understands (see [Prefer additive changes](#prefer-additive-changes)), or version the documents ([Pattern 1](#pattern-1-schema-version-in-a-composite-_id)).

### Pattern 1: Schema version in a composite `_id`

Store the schema version as a subfield of `_id`. Because `_id` is immutable, an `UPDATE` cannot change a document's version by accident, and a new-version document is a new record that coexists with the old one. Each app version subscribes only to the versions it understands:

```dart
SyncSubscription subscribeToCarsV2(Ditto ditto) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM cars WHERE _id.schemaVersion = :version',
      arguments: {'version': 2},
    );

Future<void> insertCarV2(Ditto ditto, String carId) async {
  await ditto.store.execute(
    'INSERT INTO cars DOCUMENTS (:car)',
    arguments: {
      'car': {
        '_id': {'id': carId, 'schemaVersion': 2},
        'make': 'Hyundai',
        'fuelEconomyMpg': 32,
      },
    },
  );
}
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

### Changing CRDT types

Changing how a field is typed (an array or a REGISTER object to a MAP, or a number to a COUNTER) is a breaking change too: the old and new values coexist under the same key and statements see different values depending on their declarations (see [Keep type declarations consistent](#keep-type-declarations-consistent)). In our testing with SDK 5.0.3, 5.1.0, and 5.2.0, an old app version wrote `SET stock = 9` while a new version concurrently ran `APPLY stock INCREMENT BY -1` as a COUNTER: after sync, the field held both `9` and `-1` (the new counter started at 0), and an undeclared `SELECT` returned whichever had been written later (see [Changing a register to a counter leaves both values](../knowledge/observations/merge-behavior.md#changing-a-register-to-a-counter-leaves-both-values)). Introduce a new field with the new type instead (`stockCount` as a COUNTER next to the old `stock` register) and migrate readers as described above.

## Timestamps

Every device stamps documents with its own clock, and device clocks disagree. Store timestamps in a format that DQL date functions understand, and design so that clock differences cannot corrupt your data.

### Store UTC with a zone designator

Use one of two representations consistently within a field (in JavaScript, never pass a `Date` object: in our testing, it was stored as an empty object `{}` without an error; see [JavaScript values that are not plain JSON change when stored](../knowledge/observations/dql-behavior.md#javascript-values-that-are-not-plain-json-change-when-stored)):

| Format | Dart | Notes |
|---|---|---|
| ISO-8601 string in UTC with a zone designator (recommended) | `utcTimestamp()` below (fixed millisecond precision, for example `2026-10-08T10:30:00.123Z`) for values that are sorted or compared; otherwise `DateTime.now().toUtc().toIso8601String()`, whose precision differs by platform (see below) | Human-readable; compares as text when every value uses the same precision |
| Epoch milliseconds (integer) | `DateTime.now().millisecondsSinceEpoch` | Compact; DQL date functions accept epoch milliseconds, and `date_add`, `date_sub`, and `date_trunc` return them for numeric input |

> **Note:** In Dart, `DateTime.now().toIso8601String()` returns local time **without** a zone designator (for example, `2026-10-08T19:30:00.123456`). DQL date functions return `MISSING` for such strings (`date_part`, `date_diff`, `date_add`, `date_cast`, and the others), and no error is raised. Always call `toUtc()` first. <!-- lint-ignore -->

**Use one fixed-precision helper for timestamps that are sorted or compared.** On native platforms (iOS, Android, and desktop), Dart's `toIso8601String()` includes microseconds only when they are non-zero, so one device produces both `.123456Z` and `.123Z`; on the Web it includes only milliseconds (`.123Z`). ISO strings sort chronologically as text only when they share the same format: `'2026-10-08T10:30:45.123456Z'` sorts before `'2026-10-08T10:30:45.123Z'` although it is later, because `4` comes before `Z` in string order, and `'2026-10-08T10:30:45Z'` sorts after `'2026-10-08T10:30:45.123Z'` because `Z` comes after `.` (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)). When a field is used in `ORDER BY`, range filters, or comparisons, produce every value with one helper that fixes the precision, such as `utcTimestamp()` below. Other examples in this guide inline `DateTime.now().toUtc().toIso8601String()` for brevity; use the helper in their place wherever the field is sorted or compared.

```dart
/// Returns the current time as an ISO-8601 UTC string with exactly
/// millisecond precision, e.g. "2026-10-08T10:30:00.123Z".
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// ✅ GOOD: Consistent UTC timestamps from the one helper.
Future<void> markReady(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET readyAt = :readyAt WHERE _id = :id',
    arguments: {'id': orderId, 'readyAt': utcTimestamp()},
  );
}
```

```dart
// ❌ BAD: Local time without a zone. DQL date functions return MISSING for it,
// and values written in different time zones do not compare correctly.
await ditto.store.execute(
  'UPDATE orders SET readyAt = :readyAt WHERE _id = :id',
  arguments: {
    'id': 'order-1',
    'readyAt': DateTime.now().toIso8601String(), // lint-ignore
  },
);
```

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

> **Note (SDK 5.1.0 and 5.2.0):** Ditto's last-writer-wins follows device clocks too: its Hybrid Logical Clock starts from the device's clock and moves ahead to the clock of each running peer that the device syncs with (see [Receiving future timestamps does not advance Ditto's clock](../knowledge/observations/clocks-and-time.md#receiving-future-timestamps-does-not-advance-dittos-clock)). In our testing, a device whose clock was 5 seconds ahead won over a write of the same field made 2 seconds later (see [A device whose clock runs ahead wins concurrent edits](../knowledge/observations/clocks-and-time.md#a-device-whose-clock-runs-ahead-wins-concurrent-edits)), and a clock that ran ahead spread to every device that synced with that device, directly or through a hub, for every document and until the apps restarted (see [Clocks and Time](../knowledge/observations/clocks-and-time.md), [A clock running ahead spreads to devices that sync with it](../knowledge/observations/clocks-and-time.md#a-clock-running-ahead-spreads-to-devices-that-sync-with-it), and [Ditto's clock stays ahead until the app restarts](../knowledge/observations/clocks-and-time.md#dittos-clock-stays-ahead-until-the-app-restarts)). Fields that devices may write at the same time therefore need a shape whose merge does not depend on which write is later, as the list above describes.
