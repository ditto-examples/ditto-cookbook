# Documents and Limits

What happens at the edges of a document: a merge that pushes a document over the hard size limit, also between SDK releases, how heavy a document becomes when many devices have written it or one device has updated it many times, and how deep a document can nest. What many top-level fields or many collections cost is measured in [Many Fields and Many Collections](performance-measurements.md#many-fields-and-many-collections) on Performance Measurements. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Document Size Limits](../../best-practices/data-modeling.md#document-size-limits) and [Flat or nested](../../best-practices/data-modeling.md#flat-or-nested).

**In brief**

- When two devices together push a document over the hard size limit, SDK 5.1.0 stores the combined document and can no longer update it, while SDK 5.2.0 drops the change, so each device keeps its own version ([On SDK 5.2.0, an oversized merge leaves devices with different versions](#on-sdk-520-an-oversized-merge-leaves-devices-with-different-versions)).
- On 5.2.0, updates of such a document stop in both directions until one device evicts it, and that device loses its own changes to the document ([On SDK 5.2.0, an oversized document stops syncing until one side evicts it](#on-sdk-520-an-oversized-document-stops-syncing-until-one-side-evicts-it)).
- With releases mixed, an oversized merge ends differently on each device, and SDK 5.0.3 does not check the hard limit when a document is written ([An oversized merge ends differently on each release](#an-oversized-merge-ends-differently-on-each-release), [SDK 5.0.3 does not check the hard size limit when a document is written](#sdk-503-does-not-check-the-hard-size-limit-when-a-document-is-written)).
- A document grows with the number of devices that ever wrote it, also when they all wrote the same field and only one value remains: with 300 writers, the first sync was about 11 times and each later change 6 to 13 times as heavy. One device updating a document 10,000 times did not make it heavier ([A document grows with the number of devices that wrote it](#a-document-grows-with-the-number-of-devices-that-wrote-it), [Repeated updates do not grow a document](#repeated-updates-do-not-grow-a-document)).
- An argument can nest 125 levels and a literal 97 levels, while `UPDATE` paths can build much deeper documents ([Nesting depth is limited differently for arguments, literals, and paths](#nesting-depth-is-limited-differently-for-arguments-literals-and-paths)).
- Documents 800 or more levels deep ended a peer's process during sync on 5.1.0 and 5.2.0, and on 5.0.3, every query on a collection that holds a document 30 or more levels deep ends the process ([Very deep documents end a peer's process during sync](#very-deep-documents-end-a-peers-process-during-sync)).

## The Hard Size Limit across Devices

### On SDK 5.2.0, an oversized merge leaves devices with different versions

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each |
| Setup | Two devices, A and B, held the same document (`big` in the collection `blobs`), with the default hard limit of 5,242,880 bytes. While disconnected, A added a 3 MiB field `partA` and B a 3 MiB field `partB`. Then they reconnected, and we waited 20 seconds |
| Documentation | The SDK 5.2.0 release notes say that a device drops a replication diff that would push a document over the hard size limit, and lists the document in `system:sync_degradations` (see [Changes in SDK 5.2.0](../upgrading.md#changes-in-sdk-520)) |

| Release | What the devices held after sync | A later `UPDATE` of the document |
|---|---|---|
| 5.1.0 | Both held the 6 MiB document with `partA` and `partB` | Failed with `size is 6291872 bytes and exceeds limit of 5242880 bytes` |
| 5.2.0 | A held only `partA`, and B only `partB`; the two versions stayed different | Succeeded on A |

- On 5.2.0, `system:sync_degradations` on each device had one row: `{"collection": "blobs", "document_id": "big", "reason": "documentTooBig", "senderPeerKey": "<the other device's peer key>"}`. No API reported an error or a warning.
- On 5.1.0, the result is a document that no device can update; on 5.2.0, it is a document whose version differs from device to device. What happens to later updates, and to an eviction, is described in [On SDK 5.2.0, an oversized document stops syncing until one side evicts it](#on-sdk-520-an-oversized-document-stops-syncing-until-one-side-evicts-it).

**Used in:** [Document Size Limits](../../best-practices/data-modeling.md#document-size-limits), [What Concurrent Edits Produce](../crdt-types.md#what-concurrent-edits-produce), [System Virtual Collections](../system-reference.md#system-virtual-collections), [Upgrading from SDK 5.1](../upgrading.md).

### On SDK 5.2.0, an oversized document stops syncing until one side evicts it

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | Two devices A and B made the document diverge as in [On SDK 5.2.0, an oversized merge leaves devices with different versions](#on-sdk-520-an-oversized-merge-leaves-devices-with-different-versions). Then A wrote a small field `noteA` and B a small field `noteB` (`'b1'`) on that document, and another document was added. Finally, B evicted the document with `EVICT` and wrote `noteB` again (`'b2'`) |
| Documentation | According to the SDK 5.2.0 release notes, the document then receives no more updates on that device until it is evicted and synced again |

On 5.2.0:

- On the diverged document, even small updates reached neither device, in either direction: A had only `noteA`, and B only `noteB`. The other document synced normally.
- After B evicted the document, B received A's version (`partA` and `noteA`) within 15 seconds. B's `partB` and `noteB: 'b1'` remained nowhere: they were lost. `noteB: 'b2'`, which B wrote afterwards, reached A, and the two devices held the same document.
- A's `system:sync_degradations` kept its `documentTooBig` row; B's row disappeared with the eviction.
- Recovering with `EVICT` therefore loses the evicting device's changes to the document that had not synced, and keeps the version of the device that did not evict.

On 5.1.0:

- Both devices held the 6 MiB document, and `UPDATE` failed on A and on B. After B evicted the document, it received the 6 MiB document again, and `UPDATE` kept failing. On 5.1.0, recovering takes an `UNSET` that removes enough data.

**Used in:** [Document Size Limits](../../best-practices/data-modeling.md#document-size-limits).

### An oversized merge ends differently on each release

| | |
|---|---|
| Observed on | Three pairs of releases, one run each: 5.2.0 with 5.1.0, 5.1.0 with 5.2.0 (the same two releases in the other order), and 5.0.3 with 5.2.0 |
| Setup | Two peers on different releases, each in its own process. Each peer added 3 MiB to the same document, so that the merged document would be 6 MiB, over the hard size limit of 5 MiB |

- **5.1.0 and 5.2.0**: the 5.1.0 peer held the 6 MiB document that combined both 3 MiB parts, and a later `UPDATE` of it failed. The 5.2.0 peer kept only its own part and listed the document in `system:sync_degradations` with `documentTooBig`.
- **5.0.3 and 5.2.0**: the 5.0.3 peer held the 6 MiB document, and **a later `UPDATE` of it succeeded**. 5.0.3 does not check the hard limit when a document is written (see [SDK 5.0.3 does not check the hard size limit when a document is written](#sdk-503-does-not-check-the-hard-size-limit-when-a-document-is-written)).

**Used in:** [Document Size Limits](../../best-practices/data-modeling.md#document-size-limits), [Mixed Releases](../upgrading.md#mixed-releases).

### SDK 5.0.3 does not check the hard size limit when a document is written

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, four runs each, and 5.0.3, one run |
| Setup | One device without sync. A document with a 3 MiB field, then an `UPDATE` that adds a second 3 MiB field, and an `INSERT` of a new 6 MiB document; then the stored document was read |

- **5.1.0 and 5.2.0**: the `UPDATE` failed with `Update failed: <store> Document _id = "big" size is 6291697 bytes and exceeds limit of 5242880 bytes`, and the `INSERT` with the same message for the new document. The stored document kept only its first field.
- **5.0.3**: both writes succeeded, and the stored document held both 3 MiB fields. The parameter `DOCUMENT_SIZE_HARD_LIMIT_BYTES` exists on 5.0.3, but with every value we set, a 500 KB document could still be written (see [The documented parameter defaults match SHOW ALL](configuration-and-diagnostics.md#the-documented-parameter-defaults-match-show-all)).
- This is probably also why a peer on 5.0.3 could update a 6 MiB document in [An oversized merge ends differently on each release](#an-oversized-merge-ends-differently-on-each-release).

**Used in:** [Document Size Limits](../../best-practices/data-modeling.md#document-size-limits).

## Document Weight and the Number of Writers

### A document grows with the number of devices that wrote it

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; the results were the same on all three releases. The size of a counter that only the hub incremented was also measured separately, two runs on 5.2.0 |
| Setup | 300 new devices, one at a time, connected to a hub, received the document, wrote it, confirmed that the write had reached the hub, and closed. Then a new client, connected through a relay that counted the bytes, subscribed to one document at a time, and we counted the bytes that crossed the relay for the first sync and for one change made on the hub. The bytes are counted in both directions, after TLS and compression, and include the registration of the subscription |

Bytes for the first sync and for one change made on the hub:

| Document | First sync | One change on the hub |
|---|---|---|
| One field that only the hub wrote, 300 times | 607 to 616 | 301 to 633 (620 to 633 in 2 of 9 runs, about 301 in the others) |
| A document that the hub created after the writers had left, and wrote 300 times | 611 to 698 | 281 to 371 |
| One field `x`, written by 30 devices | 1,146 to 1,424 | 663 to 753 |
| One field `x`, written by 100 devices | 2,439 to 2,801 | 794 to 1,497 |
| One field `x`, written by 300 devices | 6,613 to 7,197 | 1,691 to 3,858 |
| A `COUNTER` that only the hub incremented, 30 or 1,000 times | 532 to 790 | 261 to 346 |
| A `COUNTER` that 30 devices incremented by 1 each | 1,119 to 1,450 | 502 to 904 |
| A `COUNTER` that 100 devices incremented by 1 each | 2,424 to 2,690 | 602 to 1,955 |
| A `COUNTER` that 300 devices incremented by 1 each | 8,068 to 9,790 | 2,590 to 5,209 |
| 100 fields, each written by a different device | 3,657 to 4,051 | 654 to 1,165 |
| 100 fields, all written by the hub | 2,766 to 3,195 | 263 to 368 |

- A document grows roughly in proportion to the number of devices that wrote it, both for the first sync and for each later change. With 300 writers of the same field, the first sync was about 11 times and one change 6 to 13 times as heavy as for a field that only the hub wrote as often.
- Only the last device's value remained in `x`, yet each device that had written it added about 20 bytes to the first sync and 5 to 12 bytes to each change. For a `COUNTER`, each device added about 25 to 30 bytes and 8 to 16 bytes. A `COUNTER` that only the hub incremented did not grow with the number of increments.
- A document that the hub created and wrote after the writers had left cost as little as the hub's other documents: the weight is in the document itself, not in the state of the hub.
- A document whose fields keep each writer's value also grows, but per writer about half as fast as a field that every device wrote.
- Overwriting the value does not bring the weight back down. After the hub had written every document once more (no writer's value remained), a second new client received the field written by 300 devices with 7,876 to 8,664 bytes, the `COUNTER` incremented by 300 devices with 6,274 to 7,426 bytes, and the hub-only documents with 539 to 1,017 bytes. Compared with the first client, the field became heavier (from 6,613 to 7,197) and the `COUNTER` lighter (from 8,068 to 9,790); we do not know why.
- Times did not differ. The first sync took 22 to 213 ms for every document (mostly about 25 ms), and a change 24 to 96 ms. 200 writes on the hub took 226 to 735 ms on a document that one device had written and 288 to 725 ms on one that 300 devices had written.
- One result is unexplained: a `COUNTER` that only the hub incremented 300 times, alternating with writes to two other documents, came to 1,025 to 1,458 bytes. The same steps run alone in a separate script gave 448 to 650 bytes, regardless of the order of the increments or of the measurements. We do not know why it was larger only within the full test.
- A device whose whole persistence directory was deleted comes back with a new peer key (see [Deleting only ditto_store keeps the peer key, and on SDK 5.1.0 and 5.2.0 leaves some writes unsynced](persistence-directory.md#deleting-only-ditto_store-keeps-the-peer-key-and-on-sdk-510-and-520-leaves-some-writes-unsynced)), so a reinstalled device writes as a new device and adds to the weight.
- If the growth stays proportional beyond 300 devices, a document that 3,000 devices wrote would cost about 60 KB on the first sync and about 30 KB per change. This is a calculation, not a measurement.

**Not tested:** what the added bytes contain (for example, a list of the devices that wrote the document); sizes on disk or in memory (the numbers are bytes on the wire after compression); more than 300 devices; whether the weight goes down after about 7 days, when Ditto removes the information about peers that have not connected (see [Eviction frequency](../../best-practices/deletion-and-storage.md#eviction-frequency)), since we measured only within minutes of the writes; the traffic of one document per device instead of one shared document.

**Used in:** [Document Size Limits](../../best-practices/data-modeling.md#document-size-limits), [When counters are appropriate](../../best-practices/data-modeling.md#when-counters-are-appropriate).

### Repeated updates do not grow a document

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; all nine runs showed the same tendency |
| Setup | One device updated a document holding 1 KB of random data 10,000 times with `UPDATE`, awaiting one statement at a time, and incremented a COUNTER 10,000 times. We compared these documents with a document of the same size written once: a new device subscribed to each document in turn through the relay that counts bytes |

- **Document size**: a new device received 1.4 KiB for the document written once, 1.3 KiB for the document updated 10,000 times, and 1.3 KiB for the document whose COUNTER was incremented 10,000 times, on all three releases. The history of updates does not stay in the document and does not add to what is sent.
- **Write time**: 10,000 `UPDATE` statements and 10,000 increments each took 14.3 to 15.2 seconds, 1.4 to 1.5 ms per write (5.0.3: 20.7 to 21.4 seconds, about 2.1 ms per write).

**Used in:** none yet.

## Nesting Depth

### Nesting depth is limited differently for arguments, literals, and paths

| | |
|---|---|
| Observed on | SDK 5.1.0 (two runs) and 5.2.0 (three runs); `UPDATE` paths and literals two runs each. The limits were found by a binary search in one run. Every run gave the same result, and the results were the same on both releases |
| Setup | A document of maps nested N levels below its root (`{n: {n: ... {leaf: 1}}}`, with N keys `n`) was passed as a query argument, written as a literal in a DQL statement, or built with an `UPDATE ... SET n.n.(…).leaf = 1` path. On SDK 5.0.3, deep documents were not read in this test, because reading them ends the process (see [Very deep documents end a peer's process during sync](#very-deep-documents-end-a-peers-process-during-sync)) |

| How the document is written | Deepest that worked | One level deeper |
|---|---|---|
| A document passed as an argument | 125 levels of maps below the root | 126 levels: `Invalid query arguments: recursion limit exceeded at offset ...` |
| An object or array literal in a DQL statement | 97 levels | 98 levels: `DQL parser error: Unexpected token {` |
| An `UPDATE ... SET n.n.(…).leaf = 1` path | Not limited in the same way: a path 5,000 levels deep was accepted, and a document 1,000 levels deep could be built (reading it took a few milliseconds) | An `UPDATE` that made the document 1,500 levels deep ended the process (`SIGILL`, no message) |

- The argument limit applies to the depth of the whole argument, also to arguments that are not documents (`SELECT :x`).
- The literal limit is of the same kind as the limit on nested parentheses (see [Conditions fail at 100 levels of nested parentheses](dql-behavior.md#conditions-fail-at-100-levels-of-nested-parentheses)).
- A document deeper than 125 levels cannot be written back as it was read with `INSERT ... ON ID CONFLICT DO UPDATE`, because of the argument limit.
- `SHOW ALL` lists no system parameter for the nesting depth.

**Used in:** [Flat or nested](../../best-practices/data-modeling.md#flat-or-nested), [Merge Semantics in Detail](../crdt-types.md#merge-semantics-in-detail).

### Very deep documents end a peer's process during sync

| | |
|---|---|
| Observed on | SDK 5.1.0 (four runs) and 5.2.0 (five runs); 400, 600, and 800 levels, and the depth at which SDK 5.0.3 fails to read, one run each |
| Setup | Two peers on the same release, each in its own process. After the writing peer had synced a shallow document, the document was made N levels deep with `UPDATE` paths and synced; only paths can build a document deeper than the argument limit (see [Nesting depth is limited differently for arguments, literals, and paths](#nesting-depth-is-limited-differently-for-arguments-literals-and-paths)). After 5 seconds, we checked whether both processes were still running, reopened the receiving peer, and read the depth that had arrived. When the receiving peer had ended, we opened it without sync, evicted the document, and synced again |

| Depth | 5.1.0 | 5.2.0 |
|---|---|---|
| 300 levels | Synced (four runs) | Synced (five runs) |
| 400 and 600 levels | Synced (one run each) | Synced (one run each) |
| 800 levels | The receiving peer's process ended (one run) | The receiving peer's process ended (one run) |
| 1,000 levels | The writing peer's process ended (all four runs); the receiving peer kept the shallow version | The receiving peer's process ended (all five runs) |

- Each process ended with `SIGILL` and no message.
- **5.2.0**: the receiving peer kept only the earlier, shallow version, and ended again every time it started sync. After it was opened without sync, evicted the document by its ID, and synced again, it received the whole 1,000-level document and did not end. We think that applying a change to the document fails, while receiving the whole document does not.
- **5.1.0**: without a peer, 5.1.0 can build and read a 1,000-level document (see [Nesting depth is limited differently for arguments, literals, and paths](#nesting-depth-is-limited-differently-for-arguments-literals-and-paths)), so it fails when it sends the change to the other peer. We think that the same defect as on the 5.2.0 receiving side appears in different places on the sending and the receiving side.
- **5.0.3**: a document 30 or more levels deep can be written, but every query on its collection ends the process with `Panic: able to deserialize document: ... recursion limit exceeded`, also a `SELECT` by the ID of another document and `COUNT(*)`. Documents up to 29 levels deep can be read. A 5.0.3 device that received a 40-level document written by a 5.1.0 or 5.2.0 device behaved the same: receiving the document did not end the process, but reading the collection did, also after reopening. `EVICT` by ID failed with `Failed to deserialize TLV into requested type`. `EVICT` without a condition on the collection succeeded, but the device received the document again when it synced, and ended again. Other collections could be read.

**Used in:** [Flat or nested](../../best-practices/data-modeling.md#flat-or-nested), [Upgrading from SDK 5.1](../upgrading.md).
