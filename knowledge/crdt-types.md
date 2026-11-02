# CRDT Types and Merge Behavior

Each field value in a document is stored as one of the following CRDT types:

| Type | What it holds | Merge rule for concurrent writes |
|---|---|---|
| `REGISTER` | Any single value: string, number, boolean, null, array, or an object kept as one value | Last-writer-wins (LWW), decided by a Hybrid Logical Clock (HLC) timestamp |
| `MAP` | An object whose keys merge independently | Add-wins: concurrent additions of different keys are all kept; each nested value merges by its own type |
| `COUNTER` | An integer | Increments and decrements from all peers are combined; `RESTART` operations are last-writer-wins, and a `RESTART` discards concurrent increments (see [RESTART](../best-practices/data-modeling.md#restart)) |
| `ATTACHMENT` | A token that references binary data stored outside the document | Last-writer-wins |

`PN_COUNTER` also exists as a legacy counter type. Use `COUNTER` for all new fields (see [Counters](../best-practices/data-modeling.md#counters)).

## How values are typed with the default settings

With the default `DQL_STRICT_MODE = false` (see [Strict Mode](../best-practices/data-modeling.md#strict-mode)), Ditto infers the type from the value and the operation:

| You write | Stored as | Consequence |
|---|---|---|
| A scalar (string, number, boolean, null) | `REGISTER` | Concurrent writes: one value wins |
| An array | `REGISTER` | The **whole array** is one value. Concurrent edits keep one version of the array |
| An object | `MAP` | Each key merges independently; nested objects are nested maps |
| `APPLY f INCREMENT BY n` / `RESTART` | `COUNTER` | Concurrent increments are added together |
| An attachment token | `ATTACHMENT` | Inferred from the attachment value |
| An object in a statement that declares `(f REGISTER)` | `REGISTER` | The object is replaced as a whole |

## Merge semantics in detail

Ditto's [CRDT documentation](https://docs.ditto.live/key-concepts/syncing-data#crdts) and [conflict resolution patterns](https://docs.ditto.live/best-practices/conflict-resolution-patterns) describe how concurrent writes from different devices merge:

- **REGISTER (last-writer-wins).** When two devices write the same register concurrently, the write with the later HLC timestamp wins on every device. The losing write is discarded silently: there is no error and no notification.
- **MAP (add-wins).** When two devices add different keys to the same map, both keys survive. Each scalar inside a map entry is its own register, so two devices that edit *different fields* of the same entry both keep their changes. Two devices that edit the *same* field fall back to last-writer-wins for that field.
- **Arrays.** An array is a register. If one device appends an element and another device removes a different element at the same time, the merged document contains one of the two arrays, not a combination.
- **COUNTER.** Increments and decrements from every device are combined. Concurrent `RESTART` operations resolve by last-writer-wins. A `RESTART` also discards every increment that the restarting device had not yet received, even increments made later by the clock (see [RESTART](../best-practices/data-modeling.md#restart)).
- **Consistency guarantee.** Ditto guarantees causal consistency across documents and collections within the same database.

Because a MAP merges at every level, a single document can hold many independently editable sub-entities. Nesting carries no special performance penalty; CRDT maps work the same way at every level.

## What concurrent edits produce

The table shows how two devices' edits to the same document merged in our testing with SDK 5.1.0 and 5.2.0 (the results were identical on both releases). Both devices were offline when they wrote, and they synced afterwards. Every result was the same on both devices and did not depend on which device wrote first unless the table says so. Use it to check a data model before you ship it: if a row's result is not what your users expect, change the model rather than the merge.

| Device A | Device B | Result after sync |
|---|---|---|
| `SET status = 'A'` | `SET status = 'B'` (later) | `'B'`: the later write wins on every device, even milliseconds apart |
| `SET obj.a = 2` | `SET obj.b = 3` | `{"a": 2, "b": 3}`: different keys of a map both survive |
| `SET obj = {'a': 10}` | `SET obj.b = 20` | `{"a": 10, "b": 20}`: assigning an object merges; it does not replace (see [Assigning an object merges it](../best-practices/dql.md#assigning-an-object-merges-it)) |
| `UNSET obj` | `SET obj.c = 5` | `{"c": 5}`: the removed keys stay removed, the new key survives |
| `` UNSET items.`item-1` `` | `` SET items.`item-1`.quantity = 5 `` | The entry survives: `{"quantity": 5}` if the removal was first, `{"quantity": null}` if it was later (see [Arrays and Maps](../best-practices/data-modeling.md#arrays-and-maps)) |
| `SET tags = [1, 2, 3]` | `SET tags = [0, 1, 2]` (later) | `[0, 1, 2]`: the whole array is one value; A's change is lost |
| `APPLY n INCREMENT BY 5` | `APPLY n INCREMENT BY 7` | Both are added |
| `APPLY n RESTART WITH 100` | `APPLY n INCREMENT BY 5` (before or after) | `100`: the increment is discarded (see [RESTART](../best-practices/data-modeling.md#restart)) |
| `DELETE` | `UPDATE ... SET color = 'blue'` (later) | The document survives with `color = 'blue'`; other fields are missing (see [Husk documents](../best-practices/deletion-and-storage.md#husk-documents)) |
| `UPDATE ... SET color = 'blue'` | `DELETE` (later) | The document survives with `color = null`; other fields are missing |
| `INSERT` of a new document | `INSERT` with the same `_id` (for example, a sequential ID) | One document with combined fields; a field both set keeps the later value (see [Document IDs](../best-practices/data-modeling.md#document-ids)) |
| Adds a 3 MiB field | Adds another 3 MiB field | A 6 MiB document on both devices, above the hard limit; every later `UPDATE` of it fails (see [Document Size Limits](../best-practices/data-modeling.md#document-size-limits)) |
| `INSERT ... INITIAL DOCUMENTS` | Same `_id`, different content | Fields are combined; a field both set is decided by its value, not by time (see [Default Data with INITIAL Documents](../best-practices/data-modeling.md#default-data-with-initial-documents)) |

## Writing a value that did not change

A write records a value with a new timestamp even when the value is the same as before, so it wins over an earlier concurrent edit of that field on another device. In our testing with SDK 5.1.0 and 5.2.0, the document `{f1: 'old', f2: 'x'}` was on two devices. Device B, offline, set `f1 = 'B-edit'`. Afterwards device A, which still held `f1: 'old'`, changed `f2`. After sync, `f1` was:

| How device A wrote | `f1` after sync |
|---|---|
| The whole document with `ON ID CONFLICT DO UPDATE` | `'old'`: B's edit was lost |
| `UPDATE ... SET f1 = 'old', f2 = :value` (`f1` unchanged) | `'old'`: B's edit was lost |
| The whole document with `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` | `'B-edit'` |
| `UPDATE ... SET f2 = :value` | `'B-edit'` |
| A copy read before B's edit arrived, written with `DO UPDATE_LOCAL_DIFF` after it arrived | `'old'`: B's edit was lost, because the stale value differed from the local one |

Write only the fields that the user changed, and never write back values from a copy that may be stale (see [Prefer field-level updates over whole-document rewrites](../best-practices/dql.md#prefer-field-level-updates-over-whole-document-rewrites)). Counters are the exception to "the latest write wins": a value written into a counter restarts it (see [Writing documents that contain counters](../best-practices/data-modeling.md#writing-documents-that-contain-counters)).

## Local write semantics you must know

Several MAP behaviors differ from what developers expect from a JSON document store. With the default settings:

| Statement on an existing object `{"a": 1, "b": 2}` | Result | Why |
|---|---|---|
| `UPDATE ... SET obj.a = 10` | `{"a": 10, "b": 2}` | Field-level update |
| `UPDATE ... SET obj = {'c': 3}` | `{"a": 1, "b": 2, "c": 3}` | Assigning an object to a MAP **merges**; it does not replace |
| `UPDATE ... SET obj = {}` | `{"a": 1, "b": 2}` | An empty object adds nothing (the document is still reported as mutated) |
| `UPDATE ... UNSET obj.b` | `{"a": 1}` | `UNSET` is the only way to remove a key |
| `SET obj = 5`, then later `SET obj = {'w': 1}` | `{"a": 1, "b": 2, "w": 1}` | The old map keys come back: overwriting with a scalar does not clear the map |
| `UNSET obj`, then `SET obj = {'w': 1}`, in one transaction | `{"w": 1}` | Clearing first, then writing, replaces the object |
| `INSERT ... ON ID CONFLICT DO UPDATE` with `{"obj": {"c": 3}}` | `{"a": 1, "b": 2, "c": 3}` | Upserts merge too; omitted keys and fields remain |

**✅ DO:**
- Update individual fields with `UPDATE ... SET obj.field = :value`.
- Remove keys explicitly with `UNSET`.
- When an object must be replaced as a whole, either declare it as a register (`COLLECTION orders (shippingAddress REGISTER)`) or run `UNSET` followed by `SET` in one transaction. Only the register guarantees that concurrent edits never mix two versions: with `UNSET` and `SET` the field is still a map, so a nested edit that another device made at the same time can merge into the new object. It can even bring back a key that the replacement removed: in our testing, replacing `{street, city, zip}` with `{street, city}` while another device set `zip` kept `zip`.

**❌ DON'T:**
- Assume `SET obj = {...}` or `ON ID CONFLICT DO UPDATE` removes keys that you left out.
- Clear a map with `SET obj = {}` or by assigning a scalar.

```dart
// ✅ GOOD: Update one field of a nested object. Concurrent edits to other
// fields of shippingAddress merge cleanly.
await ditto.store.execute(
  'UPDATE orders SET shippingAddress.city = :city WHERE _id = :id',
  arguments: {'city': 'Lisbon', 'id': 'order-1'},
);

// ✅ GOOD: Remove one key from a map.
await ditto.store.execute(
  'UPDATE orders UNSET shippingAddress.line2 WHERE _id = :id',
  arguments: {'id': 'order-1'},
);
```

To replace a whole MAP value, clear it and then write the new object in one transaction, so that no reader sees the intermediate state (see `replaceAddress()` in [Assigning an object merges it](../best-practices/dql.md#assigning-an-object-merges-it)).

```dart
// ❌ BAD: Expecting this to replace the address. Under the default settings the
// object is merged into the existing map: keys missing from newAddress remain.
Future<void> replaceShippingAddressIncorrectly(
  Ditto ditto,
  String orderId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.execute(
    'UPDATE orders SET shippingAddress = :address WHERE _id = :id',
    arguments: {'id': orderId, 'address': newAddress},
  );
}
```

**Why:** The add-wins MAP is what lets offline edits from many devices merge without data loss. The price is that removal must be explicit: Ditto needs to distinguish "this key was not part of my write" from "this key was intentionally removed".

> **Note:** `UNSET` creates removal metadata. Unsetting a very large number of dynamically generated keys over time can degrade performance; unsetting the parent field (or deleting the document) mitigates the accumulation.

## Choosing a type or shape

| What you want | Use | Example |
|---|---|---|
| A single value where the latest write should win | Scalar field (REGISTER) | `status`, `displayName`, `updatedAt` |
| A group of fields that different devices edit independently | Object (MAP, the default) | `shippingAddress.city`, `settings.theme` |
| An object that must always be replaced as one consistent unit | Object declared as `REGISTER` in every statement | GPS `position: {lat, lon}` |
| A collection of items that several devices add, edit, or remove | Map keyed by item ID | `items: {"<itemId>": {...}}` |
| An ordered list written by a single device, or a list replaced wholesale | Array (REGISTER) | `tags`, a route's `waypoints` |
| A status history or multi-writer ordered list | Timestamp-keyed map (audit log) | `statusLog: {"2026-10-08T10:00:00.000Z": "created"}` |
| A tally that many devices change concurrently | `COUNTER` | `likeCount`, `viewCount` |
| Binary content (images, PDFs) | `ATTACHMENT` | `photo` |
| Unbounded, independently accessed records | A separate collection | `orderEvents`, `orderItems` |
