# Attachment Behavior

How attachments behaved: which devices can deliver a blob, what a fetch reports and how it continues after an interruption, how a transfer affects document sync on a slow link, and when Ditto collects blobs that no document references. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The two parts of an attachment, the token and the blob, are described in [Attachment Architecture](../../best-practices/attachments.md#attachment-architecture). The rules that follow from these observations are in [Fetching Attachments](../../best-practices/attachments.md#fetching-attachments), [Attachments Are Immutable](../../best-practices/attachments.md#attachments-are-immutable), [Availability](../../best-practices/attachments.md#availability), and [Size Guidance](../../best-practices/attachments.md#size-guidance).

**In brief**

- A blob travels only from a device that holds it: with three devices in a line, the device at the end could fetch a blob only after the device in the middle had fetched it ([Attachments relay only through devices that fetched them](#attachments-relay-only-through-devices-that-fetched-them)).
- A fetch interrupted by `sync.stop()` stays pending and continues where it stopped after `sync.start()`; a device that already holds the same bytes downloads nothing, because identical content gets the same attachment ID ([An interrupted fetch resumes, and identical content is not downloaded again](#an-interrupted-fetch-resumes-and-identical-content-is-not-downloaded-again)).
- A fast fetch can complete with a single `Completed` event and no `Progress` event, and `system:data_sync_info` does not show it; 60 fetches started at once all completed ([Fast fetches can complete without progress events](#fast-fetches-can-complete-without-progress-events)).
- On a slow link, documents sent in the same direction as a large attachment wait behind the attachment data already queued: at 1 MB/s, 1.2 to 1.9 seconds at the median and up to 3.3 seconds, and documents in the other direction waited as well ([A large attachment holds up documents on a slow link](#a-large-attachment-holds-up-documents-on-a-slow-link)).
- While the store stayed open, the blobs of replaced and deleted attachments were not collected at once: in three runs of 12 minutes in which a JavaScript app let go of their attachment objects but did not call the garbage collector, they stayed in the first and were collected after 10 minutes in the other two (Flutter was not tested); attachments with the same bytes share one blob ([Blobs of replaced and deleted attachments were not collected at once while the store was open](#blobs-of-replaced-and-deleted-attachments-were-not-collected-at-once-while-the-store-was-open)).
- Unreferenced blobs are collected about 10 minutes later while Ditto stays open, but only after a JavaScript app has let go of its attachment objects for them (the values that `newAttachment` and `fetchAttachment` return), and at once when the store is opened again ([Unreferenced blobs are collected after about 10 minutes](#unreferenced-blobs-are-collected-after-about-10-minutes)).
- A fetch ends at once on a device that never received the referencing document by sync, also while the holder is connected, and on SDK 5.2.0 on a device that deleted the document and opened its store again. On a device that received the document, a fetch that no connected peer can serve stays pending without an event, also after the document was deleted there, and a device that deleted the document but has not collected the blob still serves it. The terminal `Deleted` status that the 5.2.0 release notes describe appeared only in that one 5.2.0 case ([A fetch waits while no device holds the blob, and a device that deleted the document still serves it](#a-fetch-waits-while-no-device-holds-the-blob-and-a-device-that-deleted-the-document-still-serves-it), [A fetch of a collected blob stays pending instead of ending with Deleted](#a-fetch-of-a-collected-blob-stays-pending-instead-of-ending-with-deleted)).

## Relaying and Fetching Attachments

### Attachments relay only through devices that fetched them

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | Three devices in a line, A–B–C, each subscribed to the documents; only A held the blob, and C fetched it |

- **Relay**: while only A held the blob, C's fetch made no progress for 15 seconds. Once B had fetched the blob (8 to 19 ms), C's fetch also completed at once.

**Used in:** [Attachment Architecture](../../best-practices/attachments.md#attachment-architecture), [Availability](../../best-practices/attachments.md#availability).

### A fetch waits while no device holds the blob, and a device that deleted the document still serves it

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0: procedures (1) and (2), one run each, and (1) once more on each release; procedure (3), two runs each. The results were the same on both releases, except one case of (3) (below) |
| Setup | (1) Two devices; the second received two documents with attachments by sync, and the only device that held the blobs was disconnected. The second device started a fetch and then deleted that document locally while the fetch waited; it deleted the other document first and then fetched with the token it had read from it. Each fetch was watched for 20 seconds. (2) The device that held the blob deleted the document; then another device, which still had the token, started a fetch and reconnected. (3) The JavaScript SDK, one holder and two fetching devices: tokens of documents that the fetching device had received by sync, with the document still there, deleted or evicted locally, or deleted and the store closed and opened again; and tokens of documents in a collection that the fetching device did not subscribe to, which the app passed to it inside the process. Each with the holder connected or after it had stopped sync, watched for 10 seconds |
| Documentation | The 5.2.0 release notes (DS-842): "Requesting an attachment that no document references anymore now delivers a terminal `Deleted` status" |

- **No peer can deliver the blob** (procedure 1): while the only peer that held the blob was disconnected, the fetch stayed pending for 20 seconds without an event, both when the fetching device deleted the document during the fetch and when it started the fetch after it had deleted the document. In both cases, the token had arrived with the document by sync.
- **Whether a fetch waits or ends at once** (procedure 3) depended on whether the fetching device had received the document that references the attachment, not on the connection to the holder:

| Fetching device | Holder connected | Holder stopped sync |
|---|---|---|
| Received the document by sync, and it is still there | Completed within 11 ms | Pending for 10 seconds, no event |
| Received the document, then deleted or evicted it locally | Not tested | Pending for 10 seconds, no event |
| Received the document, deleted it, and opened its store again | Not tested | SDK 5.2.0: ended at once. SDK 5.1.0: pending for 10 seconds, no event |
| Never received the document; the app passed the token to it | Ended at once (within 2 ms) | Ended at once |

How the JavaScript SDK reports a fetch that ends at once (a `Deleted` event, then `store/attachment-not-found`) is in [In JavaScript, fetchAttachment fails at once for a token that the store did not receive by sync](javascript-sdk.md#in-javascript-fetchattachment-fails-at-once-for-a-token-that-the-store-did-not-receive-by-sync). The Kotlin SDK failed at once with `Attachment not found` for a token from another store that it had never connected to (see [In Kotlin, fetchAttachment waits without progress while no peer delivers the blob](kotlin-sdk.md#in-kotlin-fetchattachment-waits-without-progress-while-no-peer-delivers-the-blob)).
- **The holder deleted the document**: after the peer that held the blob had deleted the document, another device started a fetch and reconnected, and the fetch **completed** (2.1 seconds) instead of ending with `Deleted`. Deleting the document does not remove the blob from the device that holds it at once.
- **DS-842 only in part**: procedures (1) and (2) did not reproduce the behavior that the release notes describe, nor did [A fetch of a collected blob stays pending instead of ending with Deleted](#a-fetch-of-a-collected-blob-stays-pending-instead-of-ending-with-deleted), in which the holder had collected the blob. Only in procedure (3), on 5.2.0, a fetch that the device started after it had deleted the document and opened its store again ended at once; on 5.1.0, the same fetch waited. A fetch that was already pending when the document was deleted, and one started before the store was opened again, kept waiting on both releases.

**Not tested:** in procedure (3), a deletion that the fetching device received by sync before it opened its store again, and an evicted document followed by opening the store again; procedure (3) with the other SDKs.

**Used in:** [Fetching Attachments](../../best-practices/attachments.md#fetching-attachments), [Availability](../../best-practices/attachments.md#availability), [Attachments Are Immutable](../../best-practices/attachments.md#attachments-are-immutable), [Known Issues in SDK 5.1.0](../upgrading.md#known-issues-in-sdk-510).

### An interrupted fetch resumes, and identical content is not downloaded again

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each (when sync stopped, 10.5 to 11.8 MiB had been transferred; after it resumed, 7.6 to 8.8 MiB) |
| Setup | Two devices with the relay between them, counting the bytes. Attachments of 20 MB and 5 MB with random content. (1) The receiving device called `sync.stop()` in the middle of fetching the 20 MB attachment, and later `sync.start()`. (2) The receiving device created an attachment with `newAttachment` from the same bytes as the other device's 5 MB attachment, then fetched the other device's attachment |

Results on 5.2.0 (5.1.0 in parentheses):

- When the receiving device called `sync.stop()` after 11.1 MiB (10.5 MiB) had passed the relay, the fetch did not fail and stayed pending (one progress event arrived while sync was stopped). It completed 72 ms (78 ms) after `sync.start()`, and only 8.3 MiB (8.8 MiB) flowed after sync resumed: the data that had arrived was kept.
- The attachment that the receiving device created from the same bytes got the same ID as the other device's attachment. The fetch of the other device's attachment then completed with 0 MiB transferred.

**Used in:** [Fetching Attachments](../../best-practices/attachments.md#fetching-attachments), [Availability](../../best-practices/attachments.md#availability), [Attachment Architecture](../../best-practices/attachments.md#attachment-architecture).

### Fast fetches can complete without progress events

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0. The 20 MB fetch: one run each. 60 fetches at once: three runs each. 40 fetches of 2 MB and 10 fetches of 20 MB at once: one run. The results were the same on both releases |
| Setup | Fetches between two devices. During a 20 MB fetch, we watched the rows of `system:data_sync_info` and the fetch events. Then several fetches started at once: 60 attachments of 200 KB (compared with fetching them one after another), 40 of 2 MB, and 10 of 20 MB |

- The 20 MB fetch completed in less than 1 second. During it, the rows of `system:data_sync_info` did not change once. The fetch delivered a single event, `Completed`, and no `Progress` event.
- 60 fetches of 200 KB started at once all completed, in about 0.41 to 0.48 seconds: about 8 ms per attachment, the same as when each fetch was awaited before the next.
- 40 fetches of 2 MB and 10 fetches of 20 MB started at once also all completed (in 0.5 seconds and 0.8 seconds), again without any `Progress` event.
- The checks of starting and stopping sync that ran together with these are described in [Starting and stopping sync behaved as documented](subscriptions-and-replication.md#starting-and-stopping-sync-behaved-as-documented).

**Used in:** [Fetching Attachments](../../best-practices/attachments.md#fetching-attachments), [Size Guidance](../../best-practices/attachments.md#size-guidance).

## Attachments on Slow Links

### A large attachment holds up documents on a slow link

| | |
|---|---|
| Observed on | SDK 5.0.3 and 5.1.0, four runs each, and 5.2.0, five runs. The amount of data queued ahead of the documents: counted in one run per release. The number of TCP connections: one run each on 5.0.3 and 5.2.0 |
| Setup | A hub and a client with the relay between them, limiting the bandwidth in each direction; the relay added no latency. Apart from the relay's own buffer, about 1 MB more queued in the operating system's socket buffers between the sender and the relay (see [Slow links keep the connection and the presence entry](connections-and-presence.md#slow-links-keep-the-connection-and-the-presence-entry)). The hub and the client each wrote one small document every 250 ms, and we compared the time until it reached the other side before, during, and after a fetch |

Time until a small document reached the other side (median / maximum; the same trend on the three releases):

| Case | Same direction as the transfer | Opposite direction |
|---|---|---|
| Before and after the transfer | 16 to 44 ms / 29 to 106 ms | 16 to 44 ms / 29 to 106 ms |
| The client fetches a 50 MB attachment from the hub at 10 MB/s (about 5.05 s) | 0.14 to 0.25 s / 0.16 to 0.27 s | 22 to 36 ms, as before the transfer |
| The client fetches a 5 MB attachment from the hub at 1 MB/s (about 5.02 s) | 1.2 to 1.9 s / 1.9 to 3.3 s | 0.37 to 0.65 s / 0.97 to 2.0 s |
| The hub fetches a 5 MB attachment from the client at 1 MB/s (a photo being sent) | 1.3 to 1.9 s / 1.9 to 3.2 s | 0.39 to 0.62 s / 0.95 to 2.0 s |
| For comparison: an initial sync of 10,000 documents (about 5.3 MB) at 1 MB/s (about 5.9 s) | 3.22 to 3.34 s / 6.02 to 6.15 s | 0.46 to 0.75 s / 1.0 to 2.2 s |

- During a transfer, documents still arrived before it ended: the longest delay was shorter than the transfer. The median delay was roughly inversely proportional to the bandwidth: about 0.14 to 0.25 seconds at 10 MB/s and about 1.2 to 1.9 seconds at 1 MB/s. Documents in the opposite direction were delayed as well at 1 MB/s. The direction of the fetch did not change the pattern.
- Counted from the fetch's progress (`downloadedBytes` of `Progress`), at 1 MB/s, 1.3 to 1.8 MB (median) and 2.1 to 3.2 MB (maximum) of the attachment were queued ahead of a document in the same direction (one run per release), and the document waited behind them. Most of this was probably in the operating system's socket buffers. At 10 MB/s, `Progress` arrived only about every 2.6 MB, so the amount could not be counted.
- An initial sync of documents held up documents in the same direction until it had finished, longer than the attachment did (see [A large initial sync holds up the device's other sync](subscriptions-and-replication.md#a-large-initial-sync-holds-up-the-devices-other-sync)).
- The hub and the client had one TCP connection between them, before and during the fetch: attachments and documents travel over the same connection.

**Not tested:** Bluetooth LE, which is slower still, and real Wi-Fi with its latency and buffers; the relay ran over TCP on `127.0.0.1` and limited only the bandwidth.

**Used in:** [Size Guidance](../../best-practices/attachments.md#size-guidance).

## Garbage Collection of Blobs

### Blobs of replaced and deleted attachments were not collected at once while the store was open

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each. Waiting 12 minutes: three runs, first one on 5.2.0 and later one each on 5.1.0 and 5.2.0. A collection interval of 15 seconds: one run each on 5.1.0 and 5.2.0 |
| Setup | A device replaced a 2 MB attachment with another 2 MB attachment and deleted a document with a 1 MB attachment, and we watched `fs_usage_attachment` in `system:system_info` and the blob files on disk. Separately, attachments with the same bytes in two documents |

- **Replacing an attachment**: after a 2 MB attachment was replaced with another 2 MB attachment, `fs_usage_attachment` stayed at about 4.26 MB for 60 seconds: the old blob was not collected. This value is updated about every 10 seconds.
- **Waiting longer**: after a 2 MB attachment was replaced and a document with a 1 MB attachment was deleted, we watched for 12 minutes with the store open. The app kept no attachment objects for the replaced and the deleted attachment and did not call the JavaScript garbage collector. In the first run (5.2.0), no blob was collected: `fs_usage_attachment` kept growing by about 16 KB every 30 seconds; this was the SQLite write-ahead log of the attachment metadata (`ditto_attachments/db.sql-wal`), not blobs. In the two later runs (5.1.0 and 5.2.0), `fs_usage_attachment` fell from about 5.67 MB to about 2.70 MB after 10 minutes: the two unreferenced blobs, 3 MB together, were collected.
- **Collection intervals**: `SHOW ALL` on 5.2.0 lists `ATTACHMENTS_GC_INTERVAL_SECS` (600) and `ATTACHMENTS_RETAINED_CLAIM_IDLE_SECS` (600; not present on 5.1.0), among others. With the collection interval set to 15 seconds (accepted with `ALTER SYSTEM` on 5.1.0, and with `systemParameters` and with `ALTER SYSTEM` on 5.2.0), the number of blob files stayed at 5 for 3 minutes.
- Later checks found what decides this: a blob stays while the app holds its JavaScript attachment object and, after the app lets go of it, until JavaScript garbage collection has run (see [Unreferenced blobs are collected after about 10 minutes](#unreferenced-blobs-are-collected-after-about-10-minutes)). The difference between the 12-minute runs probably came from whether JavaScript garbage collection ran by itself in time; we did not record when it ran.
- **Identical content**: attachments with the same bytes get the same ID, and only one copy is stored on disk. Attaching a file with the same content to another document does not add a blob.

**Used in:** [Attachments Are Immutable](../../best-practices/attachments.md#attachments-are-immutable).

### Unreferenced blobs are collected after about 10 minutes

| | |
|---|---|
| Observed on | First round: SDK 5.0.3, 5.1.0, and 5.2.0, one run each with the default settings; shorter collection intervals, one run on 5.2.0; blobs received from another device, one run each on 5.1.0 and 5.2.0. Second round: 12 minutes with the store open, one run each on 5.1.0 and 5.2.0, and single runs of 60 minutes once and 15 minutes twice on 5.2.0 and 15 minutes once on 5.1.0. The releases gave the same results |
| Setup | A device replaced two attachments and deleted one document that had an attachment, which left five blob files, two of them referenced. We counted the blob files while Ditto stayed open, after `close()`, and after opening the same directory again. In the second round, the app either kept the objects that `newAttachment` and `fetchAttachment` returned, or dropped them and called the JavaScript garbage collector (`gc()`) every minute |

- **Collection after about 10 minutes**: when the app had dropped the returned objects and JavaScript garbage collection ran, unreferenced blobs were collected between 9 and 10 minutes while Ditto stayed open (three runs on 5.2.0, two on 5.1.0). In the run that we watched for 60 minutes, they were collected between 5 and 10 minutes, and after that only the blob that a document still referenced remained, until the 60th minute. This matches `attachments_gc_interval_secs` (600) in `SHOW ALL`.
- **Held objects keep their blobs**: when the app kept the object that `newAttachment` returned, the unreferenced blob was not collected in 12 to 15 minutes (5.1.0 and 5.2.0).
- **Attachments never put in a document**: an attachment that `newAttachment` created but that was never written to a document was collected in the 10th minute once its object was dropped and garbage collection ran (one run each on 5.1.0 and 5.2.0). If the app fails before it writes the attachment to a document, the blob does not stay on disk for good.
- **Blobs received from another device**: the same applies (one run on 5.2.0). While the receiving device kept the object that `fetchAttachment` returned, the blob stayed for 12 minutes after the sending device had deleted the document; after the object was dropped and garbage collection ran, the blob was collected in the 10th minute.
- **First round, with the objects still held**: after 20 seconds with Ditto open, the five blob files were still there, and still five right after `close()`. Opening the same directory again left two within 5 seconds (the same on the three releases). On 5.2.0, setting the four intervals related to collection (`ATTACHMENTS_GC_INTERVAL_SECS`, `ATTACHMENTS_QUEUE_CLEANUP_INTERVAL_SECS`, `ATTACHMENTS_CLAIM_REAP_INTERVAL_SECS`, and `ATTACHMENTS_RETAINED_CLAIM_IDLE_SECS`) to 5 to 10 seconds collected nothing in 120 seconds with Ditto open; opening it again collected the blobs at once. Blobs received from another device behaved the same: after the other device had replaced one attachment and deleted one document, the receiving device kept three blob files while open and one (the attachment that was still referenced) after opening again.
- Together with the first 12-minute run in [Blobs of replaced and deleted attachments were not collected at once while the store was open](#blobs-of-replaced-and-deleted-attachments-were-not-collected-at-once-while-the-store-was-open), the first round looked as if blobs were collected only at startup. The second round showed otherwise: in the first round, the JavaScript `DittoAttachment` objects were still held in variables, or JavaScript garbage collection had not run. Blobs are collected right after the store is opened again because the new process has no attachment objects left.

**Not tested:** the Flutter SDK, and whether Dart attachment objects keep their blobs in the same way.

**Used in:** [Attachments Are Immutable](../../best-practices/attachments.md#attachments-are-immutable).

### A fetch of a collected blob stays pending instead of ending with Deleted

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | Device A was the only device that held the blob, and device B had received only the token. B disconnected; A deleted the document, then closed and opened again, which removed A's blob file (from one file to none; see [Unreferenced blobs are collected after about 10 minutes](#unreferenced-blobs-are-collected-after-about-10-minutes)). B started a fetch and then reconnected |
| Documentation | The 5.2.0 release notes (DS-842): "Requesting an attachment that no document references anymore now delivers a terminal `Deleted` status" |

- B received the deletion, and its copy of the document was gone, but the fetch stayed pending for 30 seconds, and no event arrived.
- B had not opened its store again. With the procedures in [A fetch waits while no device holds the blob, and a device that deleted the document still serves it](#a-fetch-waits-while-no-device-holds-the-blob-and-a-device-that-deleted-the-document-still-serves-it), a fetch ended at once in the way that DS-842 describes only when the fetching device had deleted the document and opened its store again, and only on 5.2.0.

**Used in:** [Fetching Attachments](../../best-practices/attachments.md#fetching-attachments), [Known Issues in SDK 5.1.0](../upgrading.md#known-issues-in-sdk-510).
