# Merge Behavior

How concurrent writes from several devices merge: registers, maps, and removals on two devices, writes from three to six devices at once and from devices on different SDK releases, conditional updates and read-modify-write arithmetic, reordering and renaming, and counters. [CRDT Types and Merge Behavior](../crdt-types.md) is the reference summary of the CRDT types and of the merge results, including [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce); this page describes the observations behind it in full. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Arrays and Maps](../../best-practices/data-modeling.md#arrays-and-maps), [Counters](../../best-practices/data-modeling.md#counters), [Prefer field-level updates over whole-document rewrites](../../best-practices/dql.md#prefer-field-level-updates-over-whole-document-rewrites), [Event History and Audit Logs](../../best-practices/data-modeling.md#event-history-and-audit-logs), [Default Data with INITIAL Documents](../../best-practices/data-modeling.md#default-data-with-initial-documents), [Schema Evolution](../../best-practices/data-modeling.md#schema-evolution), [Husk documents](../../best-practices/deletion-and-storage.md#husk-documents), and [Transactions](../../best-practices/transactions.md).

**In brief**

- Of two concurrent writes to a register, the one written later by the device clocks wins, whichever reaches the other devices first. Writing a value that did not change is still a new write, and it overwrites an earlier concurrent edit from another device ([The later write wins by when it was written, not when it arrived](#the-later-write-wins-by-when-it-was-written-not-when-it-arrived), [Rewriting an unchanged value overwrites concurrent edits](#rewriting-an-unchanged-value-overwrites-concurrent-edits)).
- Removing or replacing an object, or deleting a document, does not remove a key that another device wrote concurrently: the key stays, with its value or as `null` ([The merge table held on SDK 5.1.0 and 5.2.0](#the-merge-table-held-on-sdk-510-and-520), [A key added concurrently survives a later removal as null](#a-key-added-concurrently-survives-a-later-removal-as-null)).
- Merges work field by field: values written together in a transaction mix with another device's later edit, and a long string keeps only one device's edit ([Fields written in one transaction still merge field by field](#fields-written-in-one-transaction-still-merge-field-by-field), [A text field keeps only one of two concurrent edits](#a-text-field-keeps-only-one-of-two-concurrent-edits)).
- A counter, a map keyed by ID, and an audit log keyed by timestamp kept every change from three offline devices, and a randomized test with four to six devices, also with SDK releases mixed, always converged, and in the documents that no deletion or upsert touched, no increment or latest write was lost. Peers on 5.0.3, 5.1.0, and 5.2.0 merged concurrent edits as on a single release ([With three offline devices, counters and maps keep every change](#with-three-offline-devices-counters-and-maps-keep-every-change), [A randomized merge test always converged](#a-randomized-merge-test-always-converged), [Peers on different releases merged to the same documents](#peers-on-different-releases-merged-to-the-same-documents)).
- Each device evaluates conditions and arithmetic on the documents it holds: a conditional update is not a lock, a bulk `UPDATE` misses documents that other devices added, and `reg = reg + 1` on six connected devices kept only 101 to 129 of 600 increments ([Conditional updates on two offline devices both succeed](#conditional-updates-on-two-offline-devices-both-succeed), [UPDATE changes only the documents that the writing device holds](#update-changes-only-the-documents-that-the-writing-device-holds), [Read-modify-write increments lose most concurrent updates](#read-modify-write-increments-lose-most-concurrent-updates)).
- A reorder survives a concurrent reorder only when it writes just the moved entry, with a value between its new neighbors; renaming a field in place hides what older app versions write ([Reordering on two offline devices keeps both moves only with gap positions](#reordering-on-two-offline-devices-keeps-both-moves-only-with-gap-positions), [Renaming a field in place hides older versions' edits](#renaming-a-field-in-place-hides-older-versions-edits)).
- A stored total keeps one device's partial result after the line items merge, and changing a register to a counter in a new app version leaves both values in the field, of which a read without a declaration returns the one written later ([A stored total keeps one device's partial result](#a-stored-total-keeps-one-devices-partial-result), [Changing a register to a counter leaves both values](#changing-a-register-to-a-counter-leaves-both-values)).
- A COUNTER accepts only integers. An upsert that declares the counter restarts it, and two devices that create the same counter document with a regular `INSERT` lose an increment, while `INITIAL DOCUMENTS` keeps both ([A COUNTER accepts only integers](#a-counter-accepts-only-integers), [An upsert that declares a counter restarts it](#an-upsert-that-declares-a-counter-restarts-it), [INITIAL DOCUMENTS keeps concurrent counter increments](#initial-documents-keeps-concurrent-counter-increments)).
- Counters inside map entries add up. An undeclared `SET` leaves a second value beside a counter, a deletion that meets a concurrent increment leaves a count of 0, and `INSERT ... SELECT` copies counters and attachments as plain values unless both sides declare them ([Counters inside map entries add up](#counters-inside-map-entries-add-up), [Resetting a counter with SET leaves two values](#resetting-a-counter-with-set-leaves-two-values), [Deleting a counter during a concurrent increment leaves a husk](#deleting-a-counter-during-a-concurrent-increment-leaves-a-husk), [INSERT ... SELECT copies counters and attachments as plain values](#insert--select-copies-counters-and-attachments-as-plain-values)).

## Last-Writer-Wins, Maps, and Removals

### The merge table held on SDK 5.1.0 and 5.2.0

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; the results were deterministic |
| Setup | Two devices, disconnected. For each of 26 cases, the devices made the case's two writes one after the other, without a pause between them (the second write started as soon as the first had returned), and then reconnected |

- On both releases, all 26 cases gave the expected result, and in every case the two devices ended with the same document.

The main cases:

| First write | Second write (later) | Result after sync |
|---|---|---|
| `SET` of a register | `SET` of the same register | The later value, also when the devices write in the other order. Arrays behave the same |
| `SET obj = {'a': 10}` | `SET obj.b = 20` | `{"seed": 0, "a": 10, "b": 20}` |
| `UNSET` of a map entry | An edit of the entry | `{"quantity": 5}` |
| An edit of the entry | `UNSET` of the entry | `{"quantity": null}` |
| `UNSET` of a map entry | The whole entry written again | The whole entry comes back |
| `APPLY n INCREMENT BY 5`, from 10 | `APPLY n INCREMENT BY 7` | 22 |
| `APPLY n RESTART WITH 100` | `APPLY n INCREMENT BY 5`, in either order | 100 |
| `RESTART` | A concurrent `RESTART` | The later value (200) |
| `RESTART WITH 100`, received by the other device | `INCREMENT BY 5` | 105: only an increment made after the restart has arrived is added |
| `DELETE` | `UPDATE ... SET color = 'blue'` | `{"color": "blue"}`. `make IS MISSING` is `true`, and `make IS NULL` is `false` |
| `UPDATE ... SET color = 'blue'` | `DELETE` | `{"color": null}`. `make IS MISSING` is `true`, and `make IS NULL` is `false` |
| `INSERT` | `INSERT` with the same `_id` | The fields are combined; a field that both wrote keeps the later value |
| `INSERT ... INITIAL DOCUMENTS` | `INSERT ... INITIAL DOCUMENTS` with the same `_id` and different content | `{"v": "B", "onlyA": 1, "onlyB": 1}`, in either order: the value decides, not the time |
| A regular `INSERT` | An `INITIAL DOCUMENTS` seed of the same `_id`, or the same two writes in the other order | The regular `INSERT` wins, whether it was written before or after the seed |
| An object declared as `REGISTER` | The same object written again | Replaced as a whole by the later value |
| A soft delete | A concurrent edit | Both remain |
| A soft delete | A restore | The restore wins |
| `DELETE`, then `INSERT` of `{fresh: 1}` with the same `_id` | A concurrent edit on another device, `SET color = 'blue'` | `{"fresh": 1, "color": "blue"}` |

**Used in:** [Merge Semantics in Detail](../crdt-types.md#merge-semantics-in-detail), [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce), [Local Write Semantics You Must Know](../crdt-types.md#local-write-semantics-you-must-know), [Arrays and Maps](../../best-practices/data-modeling.md#arrays-and-maps), [RESTART](../../best-practices/data-modeling.md#restart), [Default Data with INITIAL Documents](../../best-practices/data-modeling.md#default-data-with-initial-documents), [Never use sequential or timestamp-only IDs](../../best-practices/data-modeling.md#never-use-sequential-or-timestamp-only-ids), [DELETE and Tombstones](../../best-practices/deletion-and-storage.md#delete-and-tombstones), [Husk documents](../../best-practices/deletion-and-storage.md#husk-documents), [Soft Delete](../../best-practices/deletion-and-storage.md#soft-delete).

### A key added concurrently survives a later removal as null

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | Three more cases of the test in [The merge table held on SDK 5.1.0 and 5.2.0](#the-merge-table-held-on-sdk-510-and-520), for which we had no expected result. Device B wrote first, and device A wrote later |

| Device B (first) | Device A (later) | Result after sync |
|---|---|---|
| `SET obj.c = 5` | `UNSET obj` | `{"obj": {"c": null}}`: the original keys `a` and `b` are gone, and `c`, added concurrently, remains as `null` |
| `SET address.zip = 'Z9'` | `UNSET address` and `SET address = {street: 'S2', city: 'C2'}` in one transaction | `{"street": "S2", "city": "C2", "zip": null}`: the key `zip` remains as `null`, although the replacement was later |
| `SET color = 'blue'` | `DELETE`, then `INSERT` of `{fresh: 1}` with the same `_id` | `{"fresh": 1, "color": null}` |

Results were the same on both releases.

- A removal (`UNSET`, `DELETE`) cannot remove a key that another device wrote concurrently. The key remains: with its value when the edit was later than the removal (see [The merge table held on SDK 5.1.0 and 5.2.0](#the-merge-table-held-on-sdk-510-and-520)), and as `null` when the edit was earlier. Husk documents follow the same rule.

**Used in:** [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce), [Local Write Semantics You Must Know](../crdt-types.md#local-write-semantics-you-must-know), [DELETE and Tombstones](../../best-practices/deletion-and-storage.md#delete-and-tombstones), [Husk documents](../../best-practices/deletion-and-storage.md#husk-documents), [Adding, updating, and removing map entries](../../best-practices/data-modeling.md#adding-updating-and-removing-map-entries).

### The later write wins by when it was written, not when it arrived

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | A hub and two devices A and B. A and B disconnected; A wrote `status`, and 1 second later B wrote the same field. One of them reconnected first, and we waited until its change reached the hub; 2 seconds later, the other reconnected |

- When B, which wrote later, reconnected first, and A, which wrote earlier, reconnected afterwards, every device ended with B's value.
- When A reconnected first, every device also ended with B's value. The hub held A's value for a while, and B's value, which arrived later, replaced it.
- Results were the same on both releases. A device that reconnects after writing offline therefore does not overwrite newer writes with its older ones; its offline change loses to them instead.

**Not tested:** a device whose clock runs ahead (see [A device whose clock runs ahead wins concurrent edits made within the clock difference](clocks-and-time.md#a-device-whose-clock-runs-ahead-wins-concurrent-edits-made-within-the-clock-difference)).

**Used in:** [Merge Semantics in Detail](../crdt-types.md#merge-semantics-in-detail), [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce).

### Rewriting an unchanged value overwrites concurrent edits

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the result is deterministic |
| Setup | The document `{f1: 'old', f2: 'x'}` on two devices. Device B, offline, set `f1 = 'B-edit'`. Afterwards, device A changed `f2` from its own copy, in which `f1` was still `'old'`. The devices reconnected, and we read `f1` |

| How device A wrote | `f1` after sync |
|---|---|
| The whole document with `ON ID CONFLICT DO UPDATE` | `'old'`: B's edit was lost |
| `SET f1 = 'old', f2 = 'A-edit'` (`f1` equal to its current value) | `'old'`: B's edit was lost |
| The whole document with `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` | `'B-edit'`: B's edit remained |
| `SET f2 = 'A-edit'` only | `'B-edit'`: B's edit remained |
| A copy read before B's edit arrived, written with `DO UPDATE_LOCAL_DIFF` after it had arrived | `'old'`: B's edit was lost, because the stale value differed from the local `'B-edit'` and was therefore written |

Results were the same on both releases.

- A write records a new timestamp even when the value is the same as before, so by last-writer-wins it wins over an earlier concurrent edit of that field.
- The amount of data synced differs little between these ways of writing (see [Sync traffic is compressed and carries field-level changes](subscriptions-and-replication.md#sync-traffic-is-compressed-and-carries-field-level-changes)). The main reason to avoid `DO UPDATE` and whole-document rewrites is this overwrite, not the transfer.

**Used in:** [Writing a Value That Did Not Change](../crdt-types.md#writing-a-value-that-did-not-change), [ON ID CONFLICT](../../best-practices/dql.md#on-id-conflict), [Prefer field-level updates over whole-document rewrites](../../best-practices/dql.md#prefer-field-level-updates-over-whole-document-rewrites), [Prefer field-level updates](../../best-practices/data-modeling.md#prefer-field-level-updates).

### Fields written in one transaction still merge field by field

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | Devices A and B, disconnected. A wrote, and 1 second later B wrote. Then they reconnected |

- A wrote `amount = 15000` and `currency = 'JPY'` together in a transaction; B later wrote only `amount = 120`. After sync, both devices had `120 JPY`, on both releases.
- A transaction does not keep its values together with respect to other devices: another device's later edit of one field mixes with the transaction's other fields.

**Used in:** [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce), [Transactions](../../best-practices/transactions.md).

### A text field keeps only one of two concurrent edits

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | Devices A and B, disconnected. One string field held two paragraphs; A edited the first paragraph, and 1 second later B edited the second. Then they reconnected. The same edits were repeated with the paragraphs stored in a map (`paragraphs.p1`, `paragraphs.p2`) |

| Case | Result after sync |
|---|---|
| Both paragraphs in one string field | Only B's text, written later, remained; A's edit was lost |
| The paragraphs as entries of a map | Both edits remained |

- A string is one value, and there is no character-level merge: the later write replaces the whole text. Results were the same on both releases.

**Used in:** [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce).

## Several Devices Writing the Same Document

### With three offline devices, counters and maps keep every change

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each (the larger map: one run each as well) |
| Setup | Three devices, disconnected. Each device incremented a counter 50 times, added 10 entries to a map keyed by ID and 5 entries to an audit log keyed by timestamp, written with `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`, and replaced an array. Then the devices reconnected |

- All three devices ended with the counter at 150, 30 map entries, 15 audit log entries, and the array `["initial", "from-2"]`, the version of the device that wrote last. Results were the same on both releases.
- The same held at a larger scale. In one document with a map of 10,000 entries, three offline devices each updated a different 1,000 entries. Right after they reconnected, all 3,000 updates were there (the sum of the values matched on the three devices). Each update took 2 to 8 ms per statement and did not slow down with the size of the map.

**Used in:** [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce), [Arrays and Maps](../../best-practices/data-modeling.md#arrays-and-maps), [Adding, updating, and removing map entries](../../best-practices/data-modeling.md#adding-updating-and-removing-map-entries), [Counters](../../best-practices/data-modeling.md#counters), [Pattern 1: Audit-log map inside the document](../../best-practices/data-modeling.md#pattern-1-audit-log-map-inside-the-document).

### A randomized merge test always converged

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs of each test on each release; the random choices differed in every run, and every run converged |
| Setup | Two tests. In one process, a star of four devices and a chain of five devices, 16 rounds each. Across releases, four processes: a hub on the release under test and clients on 5.0.3, 5.1.0, and 5.2.0, 12 rounds. In each round, every device ran 6 statements, chosen at random from 14 kinds (listed below), on three documents. The rounds cycled through four modes: all devices offline; all connected; only the hub and one other device connected; and, while the devices wrote (every 20 ms), a random device other than the first one called `sync.stop()` or `sync.start()` every 20 to 170 ms (5 to 11 times a round). After the writes, we waited up to 30 seconds until `SELECT * FROM fuzz ORDER BY _id` returned the same on every device, and read again 3 seconds later to check that it stayed the same |

The statements, with deletions and upserts chosen a quarter as often as the others:

- `SET s` with a value whose type changed among string, number, map, array, `null`, and boolean; `SET` and `UNSET` of a map key; assignment of a whole map; replacement of an array
- `APPLY ... INCREMENT` of a COUNTER, `DELETE`, and upserts of the whole document (`DO UPDATE` and `DO NOTHING`)
- A nested `SET` (`nested.x.y`); replacing the nested object with a number, a string, or an array; creating a nested object under a map key that may hold a number (see [Statements without WHERE change every document](dql-behavior.md#statements-without-where-change-every-document)); `SET` of a flag

For each document that no deletion or upsert touched in a round, we checked that the COUNTER had added every increment of the round and that `s` held the value written last. The order of writing is the order of the clock, which on one Mac is the same as the order of the HLC timestamps (see [The later write wins by when it was written, not when it arrived](#the-later-write-wins-by-when-it-was-written-not-when-it-arrived)).

- In one process, 288 rounds (7,776 writes); across releases, 108 rounds (2,592 writes). In every round, every device ended with the same documents, and they were still the same 3 seconds later. No write failed.
- The counter and latest-write checks ran 608 times, with 0 failures. Results were the same in all three runs on each of the three releases.
- Time to converge, measured from the end of the writes. In the offline, partly connected, and reconnecting rounds, we measured from when the stopped devices had restarted sync and each had at least one connection; in the chain, the line may still have been broken at that moment. Most rounds converged within 10 ms, already when the measurement began. The connected rounds took about 265 ms because the wait checked every 250 ms; the actual sync delay was below 250 ms.
- Only the reconnecting rounds in the chain were slow. Of those 36 rounds, 23 took 4.9 to 5.7 seconds, 8 took 1.3 to 2.1 seconds, and 5 took 8 ms; in the star, they took 4 to 7 ms. Each device in the chain connects to the device before it. When that device stops and starts again, the connection probably stays broken until the next retry, after `connect.retryInterval` (5 seconds by default in JavaScript; see [A lost TCP connection is retried at the retry interval](connections-and-presence.md#a-lost-tcp-connection-is-retried-at-the-retry-interval)).

An extended version of both tests ran on SDK 5.0.3, 5.1.0, and 5.2.0, three runs each: in one process, a star of six devices and a chain of five; across releases, four processes as above. It added `EVICT`, `INSERT ... INITIAL DOCUMENTS`, an undeclared `SET c = n` on the COUNTER, `APPLY c RESTART WITH n`, an upsert that declares the COUNTER, and a transaction that writes `s` and increments the COUNTER.

- In all 18 runs, 396 rounds with 12,096 writes (each added statement ran 182 to 863 times), every device ended with the same documents, and they were still the same 3 seconds later. The checks of the COUNTER, read with its declaration, and of the latest write ran 345 times, with 0 failures.
- At first, the counter check used an undeclared read, and 4 runs (two each on 5.0.3 and 5.1.0) had 8 failures in total, while the devices held the same values. The undeclared `SET c` probably wrote a REGISTER beside the COUNTER, and an undeclared read returns the value written most recently (see [Resetting a counter with SET leaves two values](#resetting-a-counter-with-set-leaves-two-values)). That 5.2.0 had no failures was due to which statements were chosen: a reproduction in one store showed the same behavior on 5.2.0. We changed the check to read with `(c COUNTER)` and left those runs out of the results above.
- The only differences between devices that we have seen remain after a merge are at the limits: a merge that exceeds the size limit (see [On SDK 5.2.0, an oversized merge leaves devices with different versions](documents-and-limits.md#on-sdk-520-an-oversized-merge-leaves-devices-with-different-versions)) and documents nested too deeply (see [Very deep documents end a peer's process during sync](documents-and-limits.md#very-deep-documents-end-a-peers-process-during-sync)).

**Not tested:** attachments, devices with different strict mode settings, and devices with different clocks.

**Used in:** [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce).

### Peers on different releases merged to the same documents

| | |
|---|---|
| Observed on | Three pairs of releases, one run each: 5.2.0 with 5.1.0, 5.1.0 with 5.2.0 (the same two releases in the other order), and 5.0.3 with 5.2.0 |
| Setup | Two peers on different releases, each in its own process. They ran 22 of the 26 cases of [The merge table held on SDK 5.1.0 and 5.2.0](#the-merge-table-held-on-sdk-510-and-520), those whose two writes are single DQL statements, including counters, `RESTART`, husks, and `INITIAL DOCUMENTS`, and fetched a 200 KB attachment in both directions |
| Documentation | According to the release notes, SDK 5.1 and 5.2 sync with each other |

- In every pair, all 22 cases gave the same results as on a single release, and both peers held the same documents.
- The 200 KB attachment could be fetched in both directions, and its hash matched.

**Used in:** [Mixed Releases](../upgrading.md#mixed-releases).

## Conditional Updates and Arithmetic

### Conditional updates on two offline devices both succeed

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | A hub and devices A and B. A and B disconnected; A ran a statement, and 1 second later B ran the same statement. Then they reconnected |

| Case | Result after sync |
|---|---|
| Claiming a task: both ran `UPDATE tasks SET status = 'assigned', assignee = :me WHERE _id = 't1' AND status = 'open'` | Each statement changed one document, so each device could conclude that it had claimed the task. After sync, only `assignee: 'B'` remained, and A's claim disappeared without notice |
| Selling the last item: both read a stock of 1 and subtracted one, with a COUNTER | -1: both sales were counted, so the overselling shows |
| The same with a plain value (`SET qty = 0`) | 0: one sale disappeared from the record, and the overselling cannot be noticed |
| Claims written to a map keyed by device (`claims.A`, `claims.B`) | Both entries remained |

Results were the same on both releases.

- Each device evaluates the condition on its own copy, so a conditional update such as `WHERE status = 'open'` does not make a claim exclusive between offline devices.

**Used in:** [Conditions and Arithmetic across Devices](../crdt-types.md#conditions-and-arithmetic-across-devices), [When counters are appropriate](../../best-practices/data-modeling.md#when-counters-are-appropriate).

### UPDATE changes only the documents that the writing device holds

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | While device A was offline, it ran `UPDATE orders SET status = 'closed' WHERE status = 'open' AND day <= 2`, which closed o1 and o2, the documents it held. Meanwhile, device B inserted o3 (`status: 'open'`, `day: 1`), which matches the condition, and wrote a `note` on o1. Then the devices synced |

- After sync, o1 and o2 were closed, and o1 also kept B's `note`. o3 stayed `open`.
- Devices sync the result of a statement (the changed documents), not the statement itself. A bulk `UPDATE`, such as a closing job or a migration, affects only the documents that the device held when it ran.

**Used in:** [Conditions and Arithmetic across Devices](../crdt-types.md#conditions-and-arithmetic-across-devices).

### Read-modify-write increments lose most concurrent updates

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, six runs each (the map keys in the last three); the trend was the same on both releases |
| Setup | Six devices, a hub and five clients, all syncing. On the same document, each device ran `UPDATE tally SET reg = reg + 1` and `APPLY cnt INCREMENT BY 1` on a COUNTER, 100 times each and as fast as it could (about 0.55 seconds for all six devices). In the last three runs, each device also added 100 keys of its own (`` entries.`p0-0` `` and so on) to one map. We waited until all devices held the same values |

| Field | Value on every device after sync |
|---|---|
| COUNTER `cnt` | 600 (in three runs on each release) |
| Map `entries` | 600 keys (in the last three runs on each release) |
| REGISTER `reg` | 101 to 129 (123 to 129 in the runs with the map): about 79 to 83% of the 600 increments were lost |

- No statement failed. Each device adds 1 to the value that it holds and writes the result, so it overwrites the increments of other devices that have not reached it yet.
- From the end of the writes until all devices held the same values: 10 to 276 ms.
- [Conditional updates on two offline devices both succeed](#conditional-updates-on-two-offline-devices-both-succeed) showed the same loss between offline devices. Connected devices lose updates in the same way whenever they write at shorter intervals than the sync delay, which was tens of milliseconds in our setup.

**Used in:** [Conditions and Arithmetic across Devices](../crdt-types.md#conditions-and-arithmetic-across-devices), [When counters are appropriate](../../best-practices/data-modeling.md#when-counters-are-appropriate).

## Reordering and Renaming Fields

### A stored total keeps one device's partial result

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result |
| Setup | An order with one line item of 200 and a stored `subtotal` of 200, on two devices. While offline, device A added an item of 200 and stored the subtotal of the items it held (400); device B, later, added an item of 400 and stored its own subtotal (600). Then they synced |

- On both devices, the line items merged to a total of 800, while the stored `subtotal` was 600, B's partial total.
- A value computed from other fields is a separate register: each device writes the total of its partial view, and the later write wins, so the merged inputs and the stored total disagree.

**Used in:** [Do not store derived values that can diverge](../../best-practices/data-modeling.md#do-not-store-derived-values-that-can-diverge).

### Changing a register to a counter leaves both values

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result |
| Setup | A document with `stock: 10` as a plain number (a register), on two devices. While offline, one device wrote `SET stock = 9`, as an old app version would, and the other ran `APPLY stock INCREMENT BY -1`, as a new version that treats the field as a `COUNTER`, once with each write the later one. Then they synced, and both devices read `stock` without a declaration, declared as `REGISTER`, and declared as `COUNTER` |

| Written later | Undeclared `SELECT` | Declared `REGISTER` | Declared `COUNTER` |
|---|---|---|---|
| The counter increment | `-1` | `9` | `-1` |
| The register write | `9` | `9` | `-1` |

- Both values remained under the same key, the same on both devices: the register kept `9`, and the counter, which started at 0, held `-1`.
- A read without a declaration returned the value of the type written later. Which value an app shows therefore depends on which app version wrote last, and can change with the next write.
- [Resetting a counter with SET leaves two values](#resetting-a-counter-with-set-leaves-two-values) describes the opposite direction.

**Used in:** [Changing CRDT types](../../best-practices/data-modeling.md#changing-crdt-types), [Keep type declarations consistent](../../best-practices/data-modeling.md#keep-type-declarations-consistent).

### Reordering on two offline devices keeps both moves only with gap positions

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; all nine runs gave the same result |
| Setup | Two devices. A document held five map entries a, b, c, d, e in that order, each with a `position` (b, c, and d had the positions 2, 3, and 4, as the results show). Two offline devices reordered them with `UPDATE ... SET items.<key>.position = ...`; device A wrote first, and device B about 50 ms later. Map entries have no order, so the app sorts them by `position`; the orders below are sorted by `position`, and by key when positions are equal |

Unless a row says otherwise, A moved e to the top, and B moved a to the end.

| How the devices wrote | Order after sync (`position`) | Result |
|---|---|---|
| Both renumbered every entry (0 to 4) | b:0 c:1 d:2 e:3 a:4 | Only B's order, written later, remained; A's move was lost |
| A renumbered every entry; B added f after b and renumbered only the entries that shifted, c to e | a:1 b:2 f:2 c:3 d:4 e:5 | A's move was lost. a and b kept A's numbers and e kept B's; for c and d, both devices had written the same values. b and f both had 2, so their order depends on how the app sorts |
| Each wrote only the moved entry, with a value between its new neighbors (e: 0.5, a: 5.5) | e:0.5 b:2 c:3 d:4 a:5.5 | Both moves remained |
| Both moved the same entry c, to different places (0.5 and 5.5) | a b d e c:5.5 | The place written later; no duplicate |
| Both added an entry into the same gap between b and c, f and g, each with 2.5 | a b f:2.5 g:2.5 c d e | Both remained, with the same value. Their order depends on how the app sorts: unless it sorts in a fixed order, they can swap places each time the list is shown |
| The order kept in an array; A moved e to the top, and B appended f | a b c d e f | B's array, written later, remained; A's move was lost |

Results were the same on all three releases.

- The later write of each field wins (see [The merge table held on SDK 5.1.0 and 5.2.0](#the-merge-table-held-on-sdk-510-and-520) and [The later write wins by when it was written, not when it arrived](#the-later-write-wins-by-when-it-was-written-not-when-it-arrived)), so the more entries a reorder renumbers, the more of a concurrent reorder it overwrites. Renumbering every entry leaves nothing of the other device's move.
- Values between neighbors run out when entries keep being added into the same gap. Between b (2) and c (3), we wrote each new entry right after b, at half the distance to the entry after it: the first 51 entries had distinct values, and the 52nd had 2, the same value as b. Doubles have coarser steps at larger values, so the number of possible additions depends on the ratio of the gap to the neighbors' values: with a gap of 1,000 and values in the thousands, it hardly changes (in a JavaScript calculation, the first equal value moved only from the 52nd addition to the 54th). In Ditto, we checked only a gap of 1.
- All 60 values kept their exact double values through sync (compared with `Object.is`; see [JavaScript values that are not plain JSON change when stored](dql-behavior.md#javascript-values-that-are-not-plain-json-change-when-stored)).

**Not tested:** gaps other than 1 in Ditto (the gap of 1,000 was only calculated in JavaScript); positions stored as strings, a form that would not need renumbering.

**Used in:** [Reordering on Two Devices](../crdt-types.md#reordering-on-two-devices), [Arrays and Maps](../../best-practices/data-modeling.md#arrays-and-maps).

### Renaming a field in place hides older versions' edits

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | A new app version renamed a field with `UPDATE orders SET quantity = qty UNSET qty` (`qty: 1` became `quantity: 1`). An old version knew only `qty` and edited it with `UPDATE orders SET qty = 5`. With both offline, the old version edited 2 seconds before the rename in one case, and 2 seconds after it in another. In a third case, the old version was online, received the rename, and then wrote `qty = 6` |

| Case | Result after sync |
|---|---|
| The old version's edit first, the rename later | `{qty: null, quantity: 1}`. The 5 remains nowhere: the later `UNSET` removed the value, and the key remains as `null`, the same shape as in [A key added concurrently survives a later removal as null](#a-key-added-concurrently-survives-a-later-removal-as-null) |
| The rename first, the old version's edit later | `{qty: 5, quantity: 1}`. `qty` comes back with the old version's value, but `quantity`, which the new version reads, stays 1 |
| The old version writes after receiving the rename | `{qty: 6, quantity: 1}`. The old version keeps writing `qty`, and its writes never reach the new version |

- In every case, the new version sees 1, the value at the time of the rename, without an error or a warning. Reading both fields, as in `coalesce(quantity, qty)`, cannot recover the 5 in the first case.

**Used in:** [Prefer additive changes](../../best-practices/data-modeling.md#prefer-additive-changes).

## Counter Writes and Merges

### A COUNTER accepts only integers

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; the results are deterministic (the int64 limit: one run on 5.1.0 and 5.2.0) |
| Setup | Statements that write fractional and very large values into a COUNTER, and fractional values into the legacy `PN_COUNTER` |

Results were the same on all three releases:

- `APPLY cnt INCREMENT BY 0.1` fails with `Expected 0.1 to be an integer value`. It also fails with an argument (`BY :n` with 0.25), and with `BY 0.5` after an increment by an integer. An `INSERT` that declares `COUNTER` and writes 2.5 fails with `Expected an integer (not number) value for counter field`. Each error comes when the statement runs; no value is rounded silently.
- The legacy `PN_COUNTER` accepts `PN_INCREMENT BY 0.1`, and ten such increments gave `0.9999999999999999` (a floating-point error).
- A COUNTER wraps around at the int64 maximum: after `INCREMENT BY 9223372036854775807`, an increment by 1 gave `-9223372036854775808n`, without an error. A JavaScript `number` above 2^53 (`2 ** 53 + 2`) passed as an argument fails with `Expected :n to be an integer value`; integers beyond the safe range are passed as a `BigInt` (see [JavaScript values that are not plain JSON change when stored](dql-behavior.md#javascript-values-that-are-not-plain-json-change-when-stored)).

**Used in:** [Counters](../../best-practices/data-modeling.md#counters), [When counters are appropriate](../../best-practices/data-modeling.md#when-counters-are-appropriate).

### An upsert that declares a counter restarts it

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result (`DO UPDATE_LOCAL_DIFF`: one run on 5.1.0 and 5.2.0) |
| Setup | A counter incremented to 7. While offline, device A ran `INSERT INTO COLLECTION t (cnt COUNTER) DOCUMENTS ({..., 'cnt': 10}) ON ID CONFLICT DO UPDATE`, and device B ran `INCREMENT BY 5`, with A first and with B first. For comparison, A ran `RESTART WITH 10` instead. Finally, we ran the same upsert without the declaration on one device |

| Device A's write | Result after sync |
|---|---|
| The declared upsert of 10 with `DO UPDATE`, before or after B's increment | 10 on both devices: B's 5 was lost |
| `RESTART WITH 10` | 10 |
| The declared upsert with `DO UPDATE_LOCAL_DIFF`, writing the current value 7 | 7: B's 5, added afterwards, was lost |
| The declared upsert with `DO UPDATE_LOCAL_DIFF`, writing 10 | 10 |

- The number in the upsert counts as a restart, not as an increment, exactly like `RESTART WITH 10`. `DO UPDATE_LOCAL_DIFF`, which does not rewrite a register whose value is unchanged (see [Rewriting an unchanged value overwrites concurrent edits](#rewriting-an-unchanged-value-overwrites-concurrent-edits)), still restarts a COUNTER field, even with the value it already has. Re-importing a stock list from a server or a file with such an upsert would therefore discard the sales that offline devices have recorded.
- An undeclared upsert (`INSERT INTO t DOCUMENTS ({..., 'cnt': 10}) ON ID CONFLICT DO UPDATE`) leaves the counter unchanged and stores 10 as a separate value: a read that declares the COUNTER returned 7, and an undeclared read returned 10. After 1 was added to the COUNTER, both reads returned 8 (two values under one key; see [Mixed type declarations change what a query reads, not the index results](dql-behavior.md#mixed-type-declarations-change-what-a-query-reads-not-the-index-results) and [INSERT ... SELECT copies counters and attachments as plain values](#insert--select-copies-counters-and-attachments-as-plain-values)).

**Used in:** [Writing documents that contain counters](../../best-practices/data-modeling.md#writing-documents-that-contain-counters), [RESTART](../../best-practices/data-modeling.md#restart), [ON ID CONFLICT](../../best-practices/dql.md#on-id-conflict).

### INITIAL DOCUMENTS keeps concurrent counter increments

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result (`ON ID CONFLICT DO NOTHING`: two runs each on 5.1.0 and 5.2.0; inserts without sales, and `SET` on the counter: one run) |
| Setup | Two offline devices each created the same stock document with `cnt: 10` (COUNTER) and sold one item (`INCREMENT BY -1`). Device B created the document and sold first, and device A 1 second later. We compared a regular `INSERT ... DOCUMENTS` with `INSERT ... INITIAL DOCUMENTS` |

| How the devices created the document | Count on both devices after sync |
|---|---|
| A regular `INSERT` | 9: two items were sold, but only one was subtracted |
| `INSERT ... ON ID CONFLICT DO NOTHING` | 9, as with a regular `INSERT` |
| `INSERT ... INITIAL DOCUMENTS` | 8: both sales remained |
| Either form, when both devices only inserted 10 and sold nothing | 10, not 20 |

- With a regular `INSERT`, A's 10 probably counted as a restart and discarded B's earlier sale, by the same mechanism as in [An upsert that declares a counter restarts it](#an-upsert-that-declares-a-counter-restarts-it).
- `DO NOTHING` takes effect only when the document already exists on the device itself; it does not protect a document from another device that has not arrived yet.
- `SET cnt = 9` on the COUNTER field failed with `Unsupported DML operation on STCOUNTER ...`: a COUNTER changes only with `INCREMENT` and `RESTART`. (In [Resetting a counter with SET leaves two values](#resetting-a-counter-with-set-leaves-two-values), an undeclared `SET` was accepted.)

**Not tested:** which device's sale was lost with a regular `INSERT`.

**Used in:** [Writing documents that contain counters](../../best-practices/data-modeling.md#writing-documents-that-contain-counters), [INITIAL DOCUMENTS](../../best-practices/dql.md#initial-documents), [Default Data with INITIAL Documents](../../best-practices/data-modeling.md#default-data-with-initial-documents).

### Counters inside map entries add up

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | A document whose map `items` held a count `qty` in each entry. We tried to declare the nested path, and two offline devices changed the count of one entry from 10, by -1 and by -2, with `APPLY` and with `SET` |

- Declaring a nested path, as in `UPDATE COLLECTION inv (items.sku1.qty COUNTER) ...`, is a syntax error (`DQL parser error: Unexpected token .`).
- An undeclared `UPDATE inv APPLY items.sku1.qty INCREMENT BY n` is accepted and creates a counter inside the map entry. From 10, two offline devices added -1 and -2, and the count was 7 on both devices: both increments remained. An undeclared `SELECT items` also returned the count.
- The same change written as `SET items.sku2.qty = items.sku2.qty - n` gave 8: only the -2, written later, remained, and the -1 was lost. `sku2.qty` had also been set up as a counter, with `APPLY ... INCREMENT BY 10`, so the `SET` wrote a plain value on top of the counter (two values under one key; see [Mixed type declarations change what a query reads, not the index results](dql-behavior.md#mixed-type-declarations-change-what-a-query-reads-not-the-index-results)). That a field holding only a plain value loses concurrent writes is shown in [Read-modify-write increments lose most concurrent updates](#read-modify-write-increments-lose-most-concurrent-updates).

**Not tested:** SDK 5.0.3, which does not accept a field reference in a `SET` value.

**Used in:** [Writing documents that contain counters](../../best-practices/data-modeling.md#writing-documents-that-contain-counters).

### Deleting a counter during a concurrent increment leaves a husk

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, six runs each (the flag in the last three); every run gave the same result |
| Setup | A document with a COUNTER at 10, and a map entry whose `qty` counter was 10. While offline, device A deleted the document with `DELETE` or removed the entry with `UNSET`, and device B added -3 to the counter. We tried A first and B first |

| Case | Result after sync, in both orders |
|---|---|
| `DELETE` of the document | The husk `{_id, cnt: 0}`: the other fields, such as `name`, were gone, and the count was 0, neither 10 nor 7 |
| `UNSET` of the map entry | `{qty: 0}`: `name` was gone, and the entry itself remained |
| A flag, `isDeleted = true`, instead of `DELETE` | `{cnt: 7, isDeleted: true, name: 'tea'}`: the count was correct, and the flag remained |

Results were the same on all three releases.

- Neither the 10 from before the deletion nor the concurrent -3 remains in the count, which is not -3 either. The concurrent increment keeps the document or the entry from disappearing, but its count is 0.

**Used in:** [Husk documents](../../best-practices/deletion-and-storage.md#husk-documents), [Soft Delete](../../best-practices/deletion-and-storage.md#soft-delete), [Writing documents that contain counters](../../best-practices/data-modeling.md#writing-documents-that-contain-counters).

### Resetting a counter with SET leaves two values

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; the procedure is fixed, and the three releases gave exactly the same results |
| Setup | One store, and two devices in one process. A COUNTER `c` was changed with an undeclared `UPDATE t SET c = ...` and with `APPLY c INCREMENT BY 1`, and read both without a declaration and with `(c COUNTER)` declared |

- **One store**: after the counter had been incremented to 3, an undeclared `UPDATE t SET c = 5` made the undeclared read return 5, while the read that declares `(c COUNTER)` returned 3. After the next increment by 1, both reads returned 4, and the 5 was no longer visible. A reset with `SET c = 0` behaved the same way: the next increment gave 5. With `APPLY c RESTART WITH 10` instead, both reads returned 10, and the next increment gave 11.
- **Two devices**: the counter was incremented to 3 and synced. Offline, A ran `SET c = 0`, and B then added 1: after sync, both devices read 4, the earlier count plus 1. Next, B added 1 first, and A then ran `SET c = 0`: after sync, on both devices, the undeclared read returned 0 and the declared read returned 5. From that state, an increment on any device brought the value back to 6.
- In both cases, the two devices held the same values; they did not diverge. The value comes back because `SET` writes a REGISTER beside the COUNTER, and an undeclared read returns whichever of the two was written most recently.
- The failed checks with undeclared reads in the extended version of [A randomized merge test always converged](#a-randomized-merge-test-always-converged) probably had the same cause.

**Used in:** [Keep type declarations consistent](../../best-practices/data-modeling.md#keep-type-declarations-consistent).

### INSERT ... SELECT copies counters and attachments as plain values

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each; the results are deterministic |
| Setup | A document with a COUNTER incremented to 5 and an ATTACHMENT, copied to another collection with `INSERT ... SELECT`, with and without type declarations |

| How it was copied | Read as a COUNTER | Read without a declaration | After adding 1 on the copy | Attachment |
|---|---|---|---|---|
| `INSERT INTO plain SELECT * FROM src` | No value | 5 | 1 | Cannot be fetched (an ordinary map, not a token) |
| COUNTER declared on both sides | 5 | 5 | 6 | Cannot be fetched |
| COUNTER and ATTACHMENT declared on both sides | 5 | 5 | 6 | Fetched (3 bytes) |

Results were the same on both releases.

- Without the declaration, the counter is copied as the plain value 5 (a REGISTER). Adding 1 to the copy as a COUNTER starts from 0 and gives 1, and the undeclared read then returns 1 too: the original 5 is no longer visible (two values under one key, as in [Mixed type declarations change what a query reads, not the index results](dql-behavior.md#mixed-type-declarations-change-what-a-query-reads-not-the-index-results)).
- The attachment is copied as the map `{id, len, metadata}`; reading it with `ATTACHMENT` declared does not turn it into a token.

**Used in:** [INSERT ... SELECT (SDK 5.1+)](../../best-practices/dql.md#insert--select-sdk-51).
