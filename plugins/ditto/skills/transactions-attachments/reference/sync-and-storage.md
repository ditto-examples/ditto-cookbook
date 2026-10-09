# Transaction Sync and Attachment Storage Details (SDK 5.1.0)

Details moved out of [SKILL.md](../SKILL.md) rules 8, 9, and 11. Guide (`../guide/reference/ditto.md`): `§ Transactions and Sync`, `§ Attachments Are Immutable`, `§ Availability`, `§ Size Guidance`, `§ Document Size Limits`.

## Transactions on Receiving Peers

Atomicity is guaranteed on the device that commits. **Note (SDK 5.1.0)**: in our testing, receivers whose subscriptions covered every document of a transaction also applied it all at once: no observer or read saw part of it, and a device returning from offline received the backlog as one step. Ditto's [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) describes two limits for replication: a peer whose subscriptions cover only part of a transaction's documents receives only that part, and a relay can forward only what it has. Keep documents that change together in the same subscription scope (for example, both carry the same `storeId`), and give relay devices subscriptions that cover what the devices behind them need.

## Blob Garbage Collection

On Small Peers, blobs that are no longer referenced are garbage-collected automatically every 10 minutes; garbage collection runs only on Small Peers, not on Ditto Server. **Note (SDK 5.1.0)**: in our testing with the JavaScript SDK, an `Attachment` object the app still held also kept its blob alive, so do not cache `Attachment` objects longer than needed. Every blob referenced by a token (including old tokens kept in history documents) stays on the device.

## Multi-Hop Blob Availability

Ditto's [attachment documentation](https://docs.ditto.live/sdk/latest/crud/working-with-attachments) describes that Ditto Server can hold a document with an attachment token but not the blob, for example when Small Peers replicate the document among themselves without fetching the attachment.

**Note (SDK 5.1.0)**: In our testing with SDK 5.1.0 and devices in a line (A–B–C), C could not fetch a blob held only by A until B had fetched it itself, even though B subscribed to the documents; the fetch emitted no events in the meantime. Once B had the blob, C's fetch completed in milliseconds. Do not design workflows that depend on a particular relay behavior for blobs across multiple hops; if a blob must be widely available, make sure a well-connected device or Ditto Server fetches it.

## Attachment Size

There is no fixed maximum attachment size in the SDK; device storage and bandwidth are the practical limits. Blob storage does not count toward the per-device key-value storage guidance (about 2 GB); uploads through the HTTP API have a separate 1 MB request body limit. Documents have a 256 KiB soft limit (warning) and a 5 MiB hard limit (writes that exceed it fail).
