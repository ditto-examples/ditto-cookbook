# Transaction Sync and Attachment Storage Details (SDK 5.2.0)

Details moved out of [SKILL.md](../SKILL.md) rules 8, 9, and 11. Guide (`../../guide/reference/best-practices/`): `§ Transactions and Sync`, `§ Attachments Are Immutable`, `§ Availability`, `§ Size Guidance`, `§ Document Size Limits`.

## Transactions on Receiving Peers

Atomicity is guaranteed on the device that commits. **Note (SDK 5.1.0 and 5.2.0)**: in our testing, receivers whose subscriptions covered every document of a transaction also applied it all at once (up to 30,000 documents; on 5.1.0 also through a relay with up to 10,000): no observer or read saw part of it, and a device returning from offline received the backlog as one step (observed on 5.1.0). One `INSERT` that wrote many documents also arrived at once. Ditto's [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) describes two limits for replication: a peer whose subscriptions cover only part of a transaction's documents receives only that part, and a relay can forward only what it has. Even a device also connected to the writer showed orders without their items for up to about 0.7 s when a relay that subscribed only to orders was its faster path (SDK 5.1.0 and 5.2.0, in testing); give relays the subscriptions for documents written together, and make screens tolerate a parent whose children have not arrived yet. Keep documents that change together in the same subscription scope (for example, both carry the same `storeId`), and give relay devices subscriptions that cover what the devices behind them need.

## Blob Garbage Collection

On Small Peers, blobs that are no longer referenced are garbage-collected automatically every 10 minutes; garbage collection runs only on Small Peers, not on Ditto Server. **Note (SDK 5.1.0 and 5.2.0)**: in our testing with the JavaScript SDK, an `Attachment` object the app still held also kept its blob alive, so do not cache `Attachment` objects longer than needed; without such objects, unreferenced blobs were collected within about 10 minutes, and at once when the store was opened again. Deleting a document does not remove its blob from other devices at once: a device with the token still fetched it from a peer that had deleted the document but not yet collected the blob. Every blob referenced by a token (including old tokens kept in history documents) stays on the device.

## Multi-Hop Blob Availability

Ditto's [attachment documentation](https://docs.ditto.live/sdk/latest/crud/working-with-attachments) describes that Ditto Server can hold a document with an attachment token but not the blob, for example when Small Peers replicate the document among themselves without fetching the attachment.

**Note (SDK 5.1.0 and 5.2.0)**: In our testing with devices in a line (A–B–C), C could not fetch a blob held only by A until B had fetched it itself, even though B subscribed to the documents; the fetch emitted no events in the meantime. Once B had the blob, C's fetch completed in milliseconds. Do not design workflows that depend on a particular relay behavior for blobs across multiple hops; if a blob must be widely available, make sure a well-connected device or Ditto Server fetches it.

## Attachment Size

There is no fixed maximum attachment size in the SDK; device storage and bandwidth are the practical limits. Blob storage does not count toward the per-device key-value storage guidance (about 2 GB); uploads through the HTTP API have a separate 1 MB request body limit. Documents have a 256 KiB soft limit (warning) and a 5 MiB hard limit (writes that exceed it fail).

Attachment transfers share the link with document sync, and other changes wait behind the data already sent. **Note (SDK 5.1.0 and 5.2.0)**: in testing over TCP limited to 1 MB/s, a 5 MB attachment delayed small documents by 1 to 3 s in both directions; at 20 KB/s, a 500 KB attachment held them for the whole 25 s transfer (`§ Size Guidance`). On devices that also need orders or notifications quickly, fetch large files when the user opens them.

Long writes hold up sync on the writing device. **Note (SDK 5.1.0 and 5.2.0)**: in testing, while a read-write transaction was open (even one that only read) or a large statement ran, changes from other devices reached neither the store nor observers until it ended; `isReadOnly: true` did not hold them up. A device receiving a 30,000-document transaction made its own small writes wait up to about 1.3 s. Split bulk rewrites into statements of about 1,000 documents with an indexed condition, and use one transaction only for changes that must appear at once (`§ Concurrency and Duration`). Read-then-write sequences need a transaction even on one device: 500 concurrent read-then-write increments in JavaScript kept 2 or 3 (`§ Transactions`).
