# Attachments

**Store binary data as attachments in fields declared as `ATTACHMENT`, fetch the bytes lazily with a stall timeout, and replace an attachment instead of editing it.** Use attachments for binary data such as photos, signatures, PDFs, and audio. Documents themselves are limited in size (see [Document Size Limits](data-modeling.md#document-size-limits)), and every change to a document is synced to every subscriber; large binary values do not belong in documents.

## Attachment Architecture

An attachment has two parts that sync differently:

| Part | Where it lives | How it syncs |
|---|---|---|
| **Token** (`{id, len, metadata}`) | In a document field (the `ATTACHMENT` type) | Like any other document data, through subscriptions |
| **Blob** (the bytes) | In a separate blob store on each device (object storage on Ditto Server) | Only when a device explicitly **fetches** it, with a separate, resumable transfer protocol |

Key properties:

- **Subscriptions never download blobs.** A device that receives a document gets only the token. It must call `fetchAttachment` to download the bytes (see [Attachments relay only through devices that fetched them](../knowledge/observations/attachment-behavior.md#attachments-relay-only-through-devices-that-fetched-them)).
- **Content-addressed:** The attachment `id` is a cryptographic hash of the contents. Identical blobs are stored once, and several documents can reference the same blob.
- **Resumable:** If a transfer is interrupted, progress is not lost; the transfer resumes when connectivity returns or when another peer that has the blob is available (see [An interrupted fetch resumes, and identical content is not downloaded again](../knowledge/observations/attachment-behavior.md#an-interrupted-fetch-resumes-and-identical-content-is-not-downloaded-again)).
- **Metadata** is a map of string values (file name, MIME type, dimensions) that syncs with the token, so you can show information about an attachment before fetching it.

## Creating and Inserting Attachments

Create the attachment with `ditto.store.newAttachment`, from a file path or from bytes, with optional metadata, then store the returned attachment object in a document field. Declare the field as `ATTACHMENT` in the statement:

```sql
-- ✅ GOOD: Insert the attachment object that newAttachment returned, with a
-- declared ATTACHMENT field. Pass the object itself as part of the parameter;
-- the SDK turns it into the token.
-- Arguments: {"photo": {"_id": "photo-1", "image": "<the attachment object>", "createdAt": "2026-01-15T10:30:00.000Z"}}
INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)
```

The file is copied into Ditto's blob store, so the original can be deleted once `newAttachment` has completed. Pass an absolute file path; web browsers accept only bytes. Metadata values must be strings. How each SDK creates attachments from files and bytes, and what the returned object offers: [Attachments in Flutter](platforms/flutter.md#attachments-in-flutter) · [JavaScript](platforms/javascript.md#attachments-in-javascript) · [Kotlin](platforms/kotlin.md#attachments-in-kotlin) · [Swift](platforms/swift.md#attachments-in-swift).

**✅ DO:**
- Declare attachment fields in the statement: `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)`; the `COLLECTION` keyword is required when you declare types.
- Pass the attachment object as part of a parameter; never build tokens by hand.
- Create the attachment **before** starting a transaction that stores it (see [Transactions](transactions.md)).

**❌ DON'T:**
- Store base64-encoded files in regular document fields; they count toward the document size limit and are re-sent with the document.
- Put non-string values into the metadata.

**Why declare the type:** With the default `DQL_STRICT_MODE = false`, an attachment inserted without the declaration is still stored as an attachment. With strict mode enabled, the declaration is required: fields written as `ATTACHMENT` are not visible to queries that do not declare them, and statements that do not declare the field, including `UNSET`, leave the attachment value unchanged without an error (see [Strict Mode](data-modeling.md#strict-mode)). Declaring the type works in both modes.

## Fetching Attachments

**Fetch when the component that shows the attachment appears, keep one fetcher per token, stop it when the user leaves, and give up after a stall timeout: Ditto has no fetch timeout.** Read the token from the document, then call `ditto.store.fetchAttachment` with it. In Flutter, JavaScript, and Swift, it returns a fetcher immediately and reports progress through events; in Kotlin, `fetchAttachment` is a suspending function that reports progress to a callback and returns the result when the fetch ends. The events are the same:

| Event | Delivered | Contents |
|---|---|---|
| Progress | Zero or more times; a fast fetch can report none (see [Fast fetches can complete without progress events](../knowledge/observations/attachment-behavior.md#fast-fetches-can-complete-without-progress-events)) | `downloadedBytes`, `totalBytes` |
| Completed | At most once | The attachment, whose bytes you can then read |
| Deleted | At most once (instead of Completed) | The attachment is not available to this device, for example because its token did not arrive in a document by sync (see the note below) |

> **Note (SDK 5.1.0 and 5.2.0):** According to the 5.2.0 release notes, a fetch of an attachment that no document references anymore ends with this event instead of retrying forever. In our testing, that happened only on 5.2.0, and only for a fetch that a device started after it had deleted the document and opened its store again. A fetch that was already waiting when the document was deleted, one started after a local deletion without opening the store again, and one whose only holder had collected the blob stayed pending without any event on both releases. A fetch with a token that the device had not received in a document by sync, such as a token that the app passed to it, ended at once on both releases (see [A fetch waits while no device holds the blob, and a device that deleted the document still serves it](../knowledge/observations/attachment-behavior.md#a-fetch-waits-while-no-device-holds-the-blob-and-a-device-that-deleted-the-document-still-serves-it) and [A fetch of a collected blob stays pending instead of ending with Deleted](../knowledge/observations/attachment-behavior.md#a-fetch-of-a-collected-blob-stays-pending-instead-of-ending-with-deleted)). Keep a stall timeout on both releases.

Stopping the fetcher cancels an in-flight fetch; it is not required after completion. Each SDK can list the fetchers that are still active (`ditto.store.attachmentFetchers`). Attachments that are already in the local blob store, for example ones the device created, complete right away, typically without progress events.

A component that loads an attachment does four things: it starts the fetch when it appears, restarts a stall timer on every progress event, stops the fetcher and offers a retry when the timer fires, and stops the fetcher when it goes away or shows another token. The code for each SDK: [Attachments in Flutter](platforms/flutter.md#attachments-in-flutter) · [JavaScript](platforms/javascript.md#attachments-in-javascript) · [Kotlin](platforms/kotlin.md#attachments-in-kotlin) · [Swift](platforms/swift.md#attachments-in-swift).

**✅ DO:**
- Fetch attachments **lazily**, when the component that shows them appears (for example, inside a row of a lazy list, which renders only visible rows).
- Keep the fetcher until the fetch completes, and stop it when the user navigates away first.
- Implement your own timeout: restart a timer on every progress event, and stop the fetcher and offer a retry when it fires.
- Show `len` and metadata from the token (size, file name) before the download starts.

**❌ DON'T:**
- Fetch every attachment of every document as soon as it syncs; this downloads data the user may never look at.
- Start a new fetch for the same token on every render or observer update; keep one fetcher per token.
- Treat a fetch that has not made progress as an error immediately; peers that have the blob may connect later.
- Start a fetch again because the connection dropped. The [attachment documentation](https://docs.ditto.live/sdk/latest/crud/working-with-attachments) describes transfers as resuming from the point of interruption, and in our testing, a 20 MB fetch interrupted halfway by `sync.stop()` stayed pending without an error and completed shortly after `sync.start()`, transferring only the rest (see [An interrupted fetch resumes, and identical content is not downloaded again](../knowledge/observations/attachment-behavior.md#an-interrupted-fetch-resumes-and-identical-content-is-not-downloaded-again)). Use the stall timeout for fetches that make no progress at all.

Because the attachment ID is a hash of the content, a device that already holds the same bytes does not download them again: in our testing, a later fetch of another device's attachment with the same bytes completed without any transfer (see [An interrupted fetch resumes, and identical content is not downloaded again](../knowledge/observations/attachment-behavior.md#an-interrupted-fetch-resumes-and-identical-content-is-not-downloaded-again)).

## Attachments Are Immutable

Once created, an attachment's contents never change. To "edit" a file, create a new attachment and replace the token in the document.

```sql
-- ✅ GOOD: Replace an attachment: create a new one with newAttachment, then
-- update the token field
-- Arguments: {"id": "photo-1", "image": "<the new attachment object>"}
UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id

-- ✅ GOOD: Remove the reference; the blob becomes eligible for garbage collection
-- Arguments: {"id": "photo-1"}
UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id
```

**Deleting and garbage collection:**
- Attachments cannot be deleted directly. Remove the token from the document (`UPDATE ... UNSET`, or set a new token), delete the document with `DELETE` (for every peer), or evict the whole document from this device with `EVICT`.
- According to the [attachment documentation](https://docs.ditto.live/sdk/latest/crud/working-with-attachments), a blob that no document references is garbage-collected on a 10-minute cadence, on each Small Peer that holds it (the device that replaced it and the devices that had fetched it). Garbage collection runs only on Small Peers, not on Ditto Server.
- An attachment object that the app still holds keeps its blob. In our testing with the JavaScript SDK, a blob was collected within about 10 minutes once the app had let go of the objects that `newAttachment` and `fetchAttachment` returned for it and JavaScript garbage collection had run, but not reliably when garbage collection was left to run by itself. Unreferenced blobs were collected at once when the store was opened again (see [Unreferenced blobs are collected after about 10 minutes](../knowledge/observations/attachment-behavior.md#unreferenced-blobs-are-collected-after-about-10-minutes) and [Blobs of replaced and deleted attachments were not collected at once while the store was open](../knowledge/observations/attachment-behavior.md#blobs-of-replaced-and-deleted-attachments-were-not-collected-at-once-while-the-store-was-open)). Do not keep attachment objects longer than you need them, and do not expect a blob to be gone a fixed time after its token was removed. Whether the objects of the other SDKs keep their blobs in the same way has not been tested.
- Deleting a document does not remove its blob from other devices at once. In our testing, a device that still had the token fetched the attachment completely from a peer that had deleted the document but had not yet collected the blob (see [A fetch waits while no device holds the blob, and a device that deleted the document still serves it](../knowledge/observations/attachment-behavior.md#a-fetch-waits-while-no-device-holds-the-blob-and-a-device-that-deleted-the-document-still-serves-it)). Do not rely on a deletion to make a sensitive file unavailable right away.

## Thumbnail Pattern

Lists of photos should not download full-size images. Store a small preview next to the full-size attachment and fetch the full-size file only when the user opens it.

| Preview option | Pros | Cons |
|---|---|---|
| Small **attachment** (for example, a downscaled JPEG) | Keeps documents small; only fetched where shown | Needs an explicit fetch, like any attachment |
| Small inline value in the document (for example, a tiny base64 preview) | Arrives with the document; no fetch needed | Counts toward the document size limit (256 KiB soft limit) and is re-sent with the document; keep it very small |

```sql
-- ✅ GOOD: Insert a thumbnail attachment and a full-size attachment together
-- Arguments: {"photo": {"_id": "photo-1", "thumbnail": "<a small attachment object>", "image": "<the full-size attachment object>", "createdAt": "2026-01-15T10:30:00.000Z"}}
INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)
```

List rows fetch only the thumbnail, and the full-size image is fetched when the user opens the photo, with a longer stall timeout for the larger file. The code for each SDK: [Attachments in Flutter](platforms/flutter.md#attachments-in-flutter) · [JavaScript](platforms/javascript.md#attachments-in-javascript) · [Kotlin](platforms/kotlin.md#attachments-in-kotlin) · [Swift](platforms/swift.md#attachments-in-swift).

**Why:** Every device that subscribes to `photos` receives both tokens, but downloads only the thumbnails that are actually displayed. Full-size blobs cross the network only for the photos users open, which matters most on slow peer-to-peer transports such as Bluetooth LE.

## Availability

An attachment can only be fetched while a peer that **holds the blob** is reachable. Documents and blobs travel separately, so a device can have a token for an attachment that no reachable peer can deliver at the moment.

- A blob exists on a device only if that device created it or fetched it. Ditto's [attachment documentation](https://docs.ditto.live/sdk/latest/crud/working-with-attachments) notes that Ditto Server can hold a document with an attachment token but not the blob, for example when Small Peers replicate the document among themselves without fetching the attachment.
- An interrupted transfer resumes from where it stopped, from the same peer or from another peer that has the blob (see [An interrupted fetch resumes, and identical content is not downloaded again](../knowledge/observations/attachment-behavior.md#an-interrupted-fetch-resumes-and-identical-content-is-not-downloaded-again)).
- The fetch API has no "not available" event for a token that the device received by sync: while no peer can deliver the blob, the fetch simply makes no progress. A token that the device did not receive by sync ends the fetch at once, so pass documents, not tokens, between devices (see [A fetch waits while no device holds the blob, and a device that deleted the document still serves it](../knowledge/observations/attachment-behavior.md#a-fetch-waits-while-no-device-holds-the-blob-and-a-device-that-deleted-the-document-still-serves-it)). Handle this with a timeout and a retry in the UI (see [Fetching Attachments](#fetching-attachments)).
- Do not design workflows that depend on a particular relay behavior for blobs across multiple hops; if a blob must be widely available (for example, a product image), make sure a well-connected device or Ditto Server fetches it. In our testing with three devices in a line (A–B–C), C could not fetch a blob that only A held until B had fetched the blob itself, even though B subscribed to the documents (see [Attachments relay only through devices that fetched them](../knowledge/observations/attachment-behavior.md#attachments-relay-only-through-devices-that-fetched-them)).

**✅ DO:**
- Show a placeholder with the attachment's metadata while the blob is unavailable.
- Let devices that act as hubs, or a backend connected to Ditto Server, fetch attachments that many devices will need.

**❌ DON'T:**
- Assume that receiving a document means its attachment can be downloaded right away.
- Delete the original file on the creating device before `newAttachment` has completed; after that, Ditto works from its own copy.

## Size Guidance

| Item | Guidance |
|---|---|
| Individual attachment | No fixed maximum in the SDK; practical limits are device storage and network bandwidth |
| Blob storage | Stored outside the document database; does not count toward the per-device key-value storage guidance (about 2 GB; see [Key Characteristics](../knowledge/understanding-ditto.md#key-characteristics)) |
| Uploads through the HTTP API | A separate 1 MB request body limit applies (can be raised on request) |
| Documents | 256 KiB soft limit (warning) and 5 MiB hard limit (writes that exceed it fail); see [Document Size Limits](data-modeling.md#document-size-limits) |
| Transfer progress | Reported only through fetch events; `system:data_sync_info` does not include attachments. A fast fetch can complete without any progress event, so make progress displays work without one (see [Fast fetches can complete without progress events](../knowledge/observations/attachment-behavior.md#fast-fetches-can-complete-without-progress-events)) |

**✅ DO:**
- Store images, documents, audio, and other binary files as attachments rather than inside documents.
- Compress and downscale media on the creating device before calling `newAttachment`.
- Consider the slowest transport your users rely on (Bluetooth LE is much slower than Wi-Fi) when deciding what to fetch automatically and what to fetch on demand.

**❌ DON'T:**
- Fetch large attachments automatically on devices that may only be connected over Bluetooth LE. A transfer shares the connection with document sync, and other changes wait behind the attachment data already queued: in our testing over TCP limited to 1 MB/s, a 5 MB attachment delayed small documents sent in the same direction by up to about 3 seconds, and those in the other direction by up to about 2 seconds. At 20 KB/s, documents in both directions waited until the end of a 500 KB transfer, up to 25 seconds. The wait was about the amount queued ahead of a document, 1 to 3 MB in that setup, divided by the link speed (see [A large attachment holds up documents on a slow link](../knowledge/observations/attachment-behavior.md#a-large-attachment-holds-up-documents-on-a-slow-link) and [Slow links keep the connection and the presence entry](../knowledge/observations/connections-and-presence.md#slow-links-keep-the-connection-and-the-presence-entry)). Fetch large files when the user opens them on devices that also need orders or notifications quickly.
- Keep many versions of large files alive by referencing old tokens from history documents unless you need them; every referenced blob stays on the device.
