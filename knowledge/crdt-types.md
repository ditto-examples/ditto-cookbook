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

Because a MAP merges at every level, a single document can hold many independently editable sub-entities: maps merge the same way at every level of nesting. Nesting depth is limited, though, and very deep documents fail in other ways (see [Nesting depth is limited differently for arguments, literals, and paths](documents-and-limits.md#nesting-depth-is-limited-differently-for-arguments-literals-and-paths)).

## What concurrent edits produce

The table shows how two devices' edits to the same document merged in our testing with SDK 5.1.0 and 5.2.0 (see [The merge table held on SDK 5.1.0 and 5.2.0](merge-behavior.md#the-merge-table-held-on-sdk-510-and-520) for the setup and further cases). Both devices were offline when they wrote, and they synced afterwards. The results were the same on both releases and on both devices, and did not depend on which device wrote first, unless a row says otherwise. Use it to check a data model before you ship it: if a row's result is not what your users expect, change the model rather than the merge.

| Device A | Device B | Result after sync |
|---|---|---|
| `SET status = 'A'` | `SET status = 'B'` (later) | `'B'`: the later write wins on every device, even milliseconds apart |
| `SET obj.a = 2` | `SET obj.b = 3` | `{"a": 2, "b": 3}`: different keys of a map both survive |
| `SET obj = {'a': 10}` | `SET obj.b = 20` | `{"a": 10, "b": 20}`: assigning an object merges; it does not replace (see [Assigning an object merges it](../best-practices/dql.md#assigning-an-object-merges-it)) |
| `UNSET obj` | `SET obj.c = 5` | `{"c": 5}`: the removed keys stay removed, the new key survives |
| `SET obj.c = 5` | `UNSET obj` (later) | `{"c": null}`: the key added concurrently stays, with `null` |
| `SET address.zip = 'Z9'` | `UNSET address` and `SET address = {...}` in one transaction (later) | The new object plus `"zip": null`: a replacement keeps a key added concurrently, as `null` |
| `` UNSET items.`item-1` `` | `` SET items.`item-1`.quantity = 5 `` | The entry survives: `{"quantity": 5}` if the removal was first, `{"quantity": null}` if it was later (see [Arrays and Maps](../best-practices/data-modeling.md#arrays-and-maps)) |
| `SET tags = [1, 2, 3]` | `SET tags = [0, 1, 2]` (later) | `[0, 1, 2]`: the whole array is one value; A's change is lost |
| `APPLY n INCREMENT BY 5` | `APPLY n INCREMENT BY 7` | Both are added |
| `APPLY n RESTART WITH 100` | `APPLY n INCREMENT BY 5` (before or after) | `100`: the increment is discarded (see [RESTART](../best-practices/data-modeling.md#restart)) |
| `DELETE` | `UPDATE ... SET color = 'blue'` (later) | The document survives with `color = 'blue'`; other fields are missing (see [Husk documents](../best-practices/deletion-and-storage.md#husk-documents)) |
| `UPDATE ... SET color = 'blue'` | `DELETE` (later) | The document survives with `color = null`; other fields are missing |
| `UPDATE ... SET color = 'blue'` | `DELETE`, then `INSERT` with the same `_id` (later) | The new document plus `color = null` |
| `INSERT` of a new document | `INSERT` with the same `_id` (for example, a sequential ID) | One document with combined fields; a field both set keeps the later value (see [Document IDs](../best-practices/data-modeling.md#document-ids)) |
| Adds a 3 MiB field | Adds another 3 MiB field | On 5.1.0, a 6 MiB document on both devices, above the hard limit, which no `UPDATE` can change. On 5.2.0, each device keeps only its own field, and updates of the document stop (see [Document Size Limits](../best-practices/data-modeling.md#document-size-limits)) |
| `INSERT ... INITIAL DOCUMENTS` | Same `_id`, different content | Fields are combined; a field both set is decided by its value, not by time (see [Default Data with INITIAL Documents](../best-practices/data-modeling.md#default-data-with-initial-documents)) |

Further results of the same kind:

- **The later write wins by when it was written, not when it arrived.** An older offline write that reaches the other devices later does not overwrite a newer one (see [The later write wins by when it was written, not when it arrived](merge-behavior.md#the-later-write-wins-by-when-it-was-written-not-when-it-arrived)).
- **Values written together in a transaction still merge field by field** with other devices' edits, so an amount and its currency can end up from different devices. Keep values that must change together in one object declared as `REGISTER` (see [Fields written in one transaction still merge field by field](merge-behavior.md#fields-written-in-one-transaction-still-merge-field-by-field)).
- **A long text field keeps only one edit.** There is no character-level merge: two devices that edit different paragraphs of one string keep only the later edit, while paragraphs stored as map entries both survive (same entry).
- **The recommended shapes hold with more devices**: counters, maps keyed by ID, and audit logs kept every change from three offline devices, while an array kept one device's version (see [With three offline devices, counters and maps keep every change](merge-behavior.md#with-three-offline-devices-counters-and-maps-keep-every-change)).
- **Concurrent writes converge**: in a randomized test with four or five devices, also on mixed SDK releases, every device always ended with the same documents (see [A randomized merge test always converged](merge-behavior.md#a-randomized-merge-test-always-converged)).

## Writing a value that did not change

A write records a value with a new timestamp even when the value is the same as before, so it wins over an earlier concurrent edit of that field on another device. Writing a whole document with `ON ID CONFLICT DO UPDATE`, or setting a field to the value it already has, therefore overwrites what another device changed in the meantime. `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` and an `UPDATE` of only the changed fields keep the other device's edit, unless the values come from a copy read before that edit arrived (see [Rewriting an unchanged value overwrites concurrent edits](merge-behavior.md#rewriting-an-unchanged-value-overwrites-concurrent-edits)).

Write only the fields that the user changed, and never write back values from a copy that may be stale (see [Prefer field-level updates over whole-document rewrites](../best-practices/dql.md#prefer-field-level-updates-over-whole-document-rewrites)). Counters are the exception to "the latest write wins": a value written into a counter restarts it (see [Writing documents that contain counters](../best-practices/data-modeling.md#writing-documents-that-contain-counters)).

## What syncs after offline edits

Ditto syncs the current state of each document, not the history of writes: after many offline updates of one field, a device sent about as much as after one, so other devices never see the intermediate values (see [Only the current state syncs after offline edits](subscriptions-and-replication.md#only-the-current-state-syncs-after-offline-edits)). Write each event as its own entry when the history matters (see [Event History and Audit Logs](../best-practices/data-modeling.md#event-history-and-audit-logs)).

Changes sync as compressed field-level differences whichever way they were written, so the reason to write only what changed is the merge result in the previous section, not the transfer (see [Sync traffic is compressed and carries field-level changes](subscriptions-and-replication.md#sync-traffic-is-compressed-and-carries-field-level-changes)).

## Reordering on two devices

Entries of a map have no order, so an app that lets users reorder a list stores a `position` in each entry and sorts by it. Each `position` is a register, so which positions a reorder writes decides what survives a concurrent reorder on another device (see [Reordering on two offline devices keeps both moves only with gap positions](merge-behavior.md#reordering-on-two-offline-devices-keeps-both-moves-only-with-gap-positions)):

- **Renumbering every entry** overwrites the other device's reorder: only the order written later survives.
- **Writing only the moved entry**, with a value between its new neighbors (such as `0.5` to move an entry above the one at `1`), keeps both devices' moves.
- **Moving the same entry on two devices** leaves it where the later write put it, without a duplicate. Two entries inserted into the same gap with the same value both survive, in an order that depends on how the app sorts equal positions.
- **An order kept in an array** is one register: the later array replaces the other.
- **Values between neighbors run out** when entries keep being inserted into the same gap: halving a gap of 1 gave about 50 distinct values.

See [Arrays and Maps](../best-practices/data-modeling.md#arrays-and-maps) for the rules.

## Conditions and arithmetic across devices

Devices sync the effects of statements (changed documents), not the statements themselves, and each device evaluates conditions against the documents it has at that moment:

- **A conditional update is not a lock.** Two offline devices both ran `UPDATE tasks SET status = 'assigned', assignee = :me WHERE _id = 't1' AND status = 'open'`, and each statement changed one document, so each device concluded that it had claimed the task. After sync, only one assignee remained, and the other device's claim disappeared without notice. Claims written to a map keyed by device (`claims.A`, `claims.B`) both survived, so that every device can pick the winner by the same rule (the earliest time, then the smallest ID) (see [Conditional updates on two offline devices both succeed](merge-behavior.md#conditional-updates-on-two-offline-devices-both-succeed)).
- **A bulk update covers only the documents the device has.** One device ran `UPDATE orders SET status = 'closed' WHERE status = 'open' AND day <= 2` while another, offline, inserted a matching order. After sync, that order was still open. Run closing jobs and migrations where every change has arrived (for example on Ditto Server, afterwards), or evaluate the condition when reading (see [UPDATE changes only the documents that the writing device holds](merge-behavior.md#update-changes-only-the-documents-that-the-writing-device-holds)).
- **Arithmetic on a register loses concurrent changes, even online.** Six connected devices each ran `UPDATE c SET n = n + 1` 100 times: a register ended at 101 to 129 instead of 600, without an error, while a `COUNTER` reached 600 every time. Selling the last item from two offline devices left a register at 0, which hides the oversale, and a `COUNTER` at -1, which shows it (see [Read-modify-write increments lose most concurrent updates](merge-behavior.md#read-modify-write-increments-lose-most-concurrent-updates)).

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
- Read replaced or removed objects defensively: a key that another device added concurrently can remain with the value `null` (see the table above).
- When an object must be replaced as a whole, either declare it as a register (`COLLECTION orders (shippingAddress REGISTER)`) or run `UNSET` followed by `SET` in one transaction. Only the register guarantees that concurrent edits never mix two versions: with `UNSET` and `SET` the field is still a map, so a nested edit that another device made at the same time can merge into the new object. It can even bring back a key that the replacement removed: in our testing, replacing `{street, city, zip}` with `{street, city}` while another device set `zip` kept `zip`, with the value `null` (see [A key added concurrently survives a later removal as null](merge-behavior.md#a-key-added-concurrently-survives-a-later-removal-as-null)).

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
