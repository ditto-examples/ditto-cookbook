---
name: transactions-attachments
description: "Ditto SDK transactions and attachments (Flutter, JavaScript, Kotlin, Swift): ditto.store.transaction with tx.execute only, no nesting, short scopes, rollback, close(); newAttachment, ATTACHMENT declarations, lazy fetchAttachment with a stall timeout, immutability, thumbnails, and blob availability. Use when writing or reviewing ditto.store.transaction, newAttachment, or fetchAttachment code, or when displaying photos or files stored in Ditto."
---

# Ditto Transactions and Attachments

Atomic multi-statement writes with `ditto.store.transaction`, and binary files stored, synced, and displayed as attachments. Targets Ditto SDK 5.2.0 in every SDK; API examples are per SDK.

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). These rules target SDK 5.2.0; for devices that still run 5.1.0, also apply `§ Known Issues in SDK 5.1.0`. **Note (SDK 5.1.0 and 5.2.0)** and **Note (SDK 5.1.0)** mark easy-to-miss behavior seen on those releases, with the safe pattern; **(SDK 5.1+)** / **(SDK 5.2+)** mark features introduced in that release.
- For API calls, Grep the outline of that SDK's page, `${CLAUDE_SKILL_DIR}/../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), with `^#{1,3} ` and read only the section you need, not the whole page; sections are named `<Topic> in <SDK>`. API examples: `examples/<sdk>/`, with the same base names in every SDK.
- `§ <Heading>` cites the full guide: Grep the heading as a fixed string in `best-practices/` and `knowledge/` under `${CLAUDE_SKILL_DIR}/../guide/reference/`, then read that section.
- Report each finding at the severity of its item in `§ Anti-Pattern Checklist` (the checklist decides; Grep a phrase of the item there). The labels below rank the rules, not each item in them.

## Key Facts

| Topic | Every SDK |
|---|---|
| Transaction API | `ditto.store.transaction` with a callback, `hint`, and `isReadOnly`; the callback gets a transaction object |
| Inside the callback | Only the transaction object's `execute`; never `ditto.store.execute` (Flutter throws; other SDKs can stop) |
| Commit / rollback | Throwing rolls back and rethrows; each SDK has an explicit rollback value (Flutter `TransactionCompletionAction.rollback`, JavaScript `'rollback'`, Swift `.rollback`, Kotlin `DittoTransaction.Result.Rollback`; Kotlin must return `Result.Commit(value)` to commit) |
| Concurrency | One read-write transaction at a time; read-only transactions run concurrently |
| Closing | Flutter's `close()` does not wait for in-flight transactions; JavaScript's waits |
| Create an attachment | `newAttachment` from a path or bytes, with string metadata |
| Store it | `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)` |
| Fetch it | `fetchAttachment(token, ...)` returns a fetcher that you `stop()` (Kotlin: a suspending call that returns the result) |
| Sync | Subscriptions sync the token only; blobs move only when a device fetches them |

Signatures and short examples for each SDK: [reference/sdk-apis.md](reference/sdk-apis.md).

## Prevents

- `ditto.store.execute` inside a transaction (throws in Flutter, never completes in JavaScript)
- Statements not awaited before the callback returns (they are not applied)
- Nested read-write transactions (can deadlock; the SDK does not detect it)
- Network calls, dialogs, or timers inside a transaction, blocking all other writes
- Caught statement errors that silently commit the rest of a transaction
- Closing Ditto while transactions are still running (Flutter's `close()` does not wait)
- Assuming subscriptions download attachment blobs (only tokens sync)
- Eager or duplicate fetches, fetchers that are never stopped, and fetches without a timeout
- Trying to modify an attachment in place (attachments are immutable)
- Binary data stored inside documents instead of as attachments

## Rules

A transaction runs several DQL statements against the local store atomically. It does not lock anything on other peers: two devices can both pass the same read-check-write, so it is no lock, uniqueness check, or guard for a rule across devices (`§ Checks and Claims across Devices`), and fields written together still merge field by field with other devices' edits (keep such values in one `REGISTER` object). A single `INSERT`, `UPDATE`, or `DELETE` is already atomic, so do not wrap it in a transaction. `§ Using store.transaction`

### 1. Use only the transaction's execute inside a transaction, and never nest (CRITICAL)

Calling `ditto.store.execute` inside the callback throws a `DittoException` in Flutter; in JavaScript, Kotlin, and Swift, such a write never completed, without an error (in testing, 5.1.0 and 5.2.0). The rule is the same everywhere. Starting a read-write transaction inside another one deadlocks, because only one read-write transaction runs at a time; the SDKs do not detect it.

**✅ DO**: Run every read and write of the transaction through the transaction object passed to the callback, and await each statement before the callback returns.
**❌ DON'T**:
- Call `ditto.store.execute(...)` inside the callback
- Call `ditto.store.transaction(...)` (read-write) inside another read-write transaction, directly or through a helper method
- Start many writes in parallel while a transaction is open: in Kotlin and Swift each waiting write holds a thread, and once `Dispatchers.IO` (64 in testing) or Swift's cooperative pool (one thread per core) runs out, the app stops (`§ Transaction Rules`)
- Store the transaction object or use it after the callback returns

`§ Transaction Rules`, `§ Platform Differences` · Examples: `transaction-good`, `transaction-bad` in `examples/<sdk>/`

### 2. End a transaction deliberately (CRITICAL)

| Callback outcome | Result |
|---|---|
| Returns the SDK's commit value (or, except in Kotlin, any other value) | Committed; `transaction` returns that value |
| Returns the SDK's rollback value | Rolled back; no changes are applied |
| Throws | Rolled back; the error is rethrown to the caller |
| A statement fails but the callback catches the error | The transaction **continues**; the remaining changes are committed unless you roll back |

**❌ DON'T**: Catch an error from a statement and carry on without deciding. If the remaining work must not commit, rethrow or return the rollback value.

```sql
-- The statements of a shipOrder transaction: return the rollback value when
-- the first returns no row; otherwise update and commit. The check holds on
-- this device only (`§ Checks and Claims across Devices`)
-- Arguments: {"id": "order-1", "status": "paid"}
SELECT * FROM orders WHERE _id = :id AND status = :status

-- Arguments: {"id": "order-1", "status": "shipped"}
UPDATE orders SET status = :status WHERE _id = :id
```

`§ Transaction Rules`, `§ Using store.transaction` · Example: `transaction-good` in `examples/<sdk>/`; rollback values: [reference/sdk-apis.md](reference/sdk-apis.md#transactions-at-a-glance)

### 3. Await pending transactions before closing (HIGH; CRITICAL in Flutter)

In Flutter, `ditto.close()` does not wait for in-flight transactions, and closing while one is open, also a read-only one, stops the isolate (the UI stops responding). Track pending transactions (a set of their futures, removed when each completes) and await them, ignoring their errors, before closing. In JavaScript, `close()` waited for open transactions in testing, so a transaction that never ends keeps it from completing. Await your own pending work before closing in every SDK.

`§ Resource Cleanup and Shutdown`, `§ Closing Ditto in Flutter` · Example: `transaction-good` in `examples/<sdk>/` (Flutter: `TransactionTracker`)

### 4. Keep transactions short (HIGH)

While a read-write transaction runs, every other read-write transaction waits, and so does a plain `store.execute` write issued meanwhile. Network calls, dialogs, user input, or timers inside the callback block all writes.

**✅ DO**:
- Read, decide, write, return
- Prepare network responses, files, user input, and attachments (`newAttachment`) **before** the transaction
- Give every transaction a `hint`: Ditto logs it, at rising levels, while a transaction runs longer than 10 seconds (thresholds: `TRANSACTION_DURATION_BEFORE_LOGGING_MS`, `TRANSACTION_TRACE_INTERVAL_MS`)
- Use `isReadOnly` for transactions that only read; a mutating statement inside one fails

**❌ DON'T**:
- Wait for network calls, dialogs, or timers inside the callback
- Read the commit ID inside the transaction to track sync status; it is empty until the transaction commits. Keep the query result of the write (for example, return it from the callback) and read its commit ID after `transaction` completes

`§ Transaction Rules`, `§ Concurrency and Duration` · Example: `transaction-good` in `examples/<sdk>/`

### 5. Create attachments with newAttachment and declare ATTACHMENT fields (HIGH)

An attachment has two parts: the **token** (`{id, len, metadata}`), stored in a document field and synced like other data, and the **blob**, stored outside the document database and transferred only when a device calls `fetchAttachment`. The `id` is a hash of the contents, so identical blobs are stored once. `newAttachment` copies the file into Ditto's blob store.

**✅ DO**:
- Pass an absolute file path or bytes to `newAttachment`; in web browsers only bytes work (paths throw).
- Declare the field (`COLLECTION photos (image ATTACHMENT)`; `COLLECTION` is required when declaring types). Without strict mode (default `DQL_STRICT_MODE = false`) an undeclared attachment is still stored as one; strict mode requires the declaration, hides undeclared ATTACHMENT fields from queries, and statements that omit the declaration, including `UNSET`, leave the attachment unchanged without an error (`§ Strict Mode`). Declaring works in both modes.
- Pass the attachment object inside a parameter; never build tokens by hand
- Create the attachment **before** starting a transaction that stores it

**❌ DON'T**:
- Store base64-encoded files in regular fields; they count toward the document size limit and are re-sent with the document
- Put non-string values into the metadata
- Delete the original file before `newAttachment` completes (afterwards, the copy in Ditto's store is what matters)

```sql
-- Insert the object that newAttachment returned, with a declared field
-- Arguments: {"photo": {"_id": "photo-1", "image": "<the attachment object>", "createdAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)
```

`§ Attachment Architecture`, `§ Creating and Inserting Attachments` · API per SDK: [reference/sdk-apis.md](reference/sdk-apis.md#attachments-at-a-glance)

### 6. Fetch attachments explicitly, lazily, and cancellably (HIGH)

Subscriptions never download blobs; a token is not image data. Fetching every attachment as soon as a document syncs wastes bandwidth and storage.

| Event | Delivered | Contents |
|---|---|---|
| Progress | Zero or more times (none on a fast link in testing) | `downloadedBytes`, `totalBytes` |
| Completed | At most once | The attachment, whose bytes you then read |
| Deleted | At most once (instead of Completed) | The attachment was deleted while being fetched |

**Note (SDK 5.1.0 and 5.2.0)**: in our testing, a fetch that was waiting when its document was deleted stayed pending on 5.2.0 too, whose release notes say it now ends with Deleted; 5.2.0 ended only a fetch started after the document was deleted and the store opened again. A token that the device did not receive by sync (one the app passed to it) ends the fetch at once. Keep a stall timeout (rule 7).

The fetcher's `stop()` cancels an in-flight fetch (not needed after completion); `ditto.store.attachmentFetchers` lists active fetchers. Kotlin's `fetchAttachment` suspends and returns the result instead; cancel its coroutine. Attachments already in the local blob store complete right away, typically without progress events. Flutter: `fetcher.attachment` never completes after `stop()`, and `AttachmentFetchEvent` is not sealed (add a `default` branch).

**✅ DO**:
- Fetch when the component that shows the attachment appears (for example, a row of a lazy list)
- Keep the fetcher until the fetch completes; stop it when the user navigates away first
- Show `len` and metadata from the token before the download starts

**❌ DON'T**:
- Fetch every attachment of every document as soon as it syncs
- Start a new fetch for the same token on every render or observer update

`§ Fetching Attachments` · Examples: `attachment-lazy-loading-good`, `attachment-lazy-loading-bad` in `examples/<sdk>/`

### 7. Implement your own fetch timeout (HIGH)

Ditto has no fetch timeout and no "not available" event. While no reachable peer can deliver the blob, the fetch simply makes no progress.

**✅ DO**: Restart a timer on every progress event. When it fires, stop the fetcher and offer a retry. Use a longer stall timeout for larger files.
**❌ DON'T**: Treat a fetch that has not made progress as an error immediately; peers that have the blob may connect later. In Flutter, do not wrap `fetcher.attachment` in `Future.timeout` and then call `stop()`: the future never completes after `stop()`.

`§ Fetching Attachments`, `§ Availability` · Example: `attachment-fetch-timeout` in `examples/<sdk>/`

### 8. Replace attachments, never modify them (HIGH)

Attachment contents never change. To "edit" a file, create a new attachment and replace the token: `UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id`. Attachments cannot be deleted directly: remove the token (`UPDATE COLLECTION photos (image ATTACHMENT) UNSET image ...`, or set a new token), delete the document with `DELETE` (for every peer), or evict it from this device with `EVICT`. Unreferenced blobs are garbage-collected on Small Peers only ([details](reference/sync-and-storage.md#blob-garbage-collection)); do not cache attachment objects longer than needed.

**❌ DON'T**: Overwrite the source file and expect the attachment to change (the file was copied into Ditto's store), or keep many old tokens in history documents unless you need them (every referenced blob stays on the device).

`§ Attachments Are Immutable` · Example: `attachment-immutability` in `examples/<sdk>/`

### 9. Keep transacted documents in one subscription scope (HIGH)

Atomicity is guaranteed on the device that commits. A peer whose subscriptions cover only part of a transaction's documents receives only that part, and a relay can forward only what it has ([transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions)). Receiver-side test results: [reference/sync-and-storage.md](reference/sync-and-storage.md#transactions-on-receiving-peers).

**✅ DO**: Keep documents that change together in the same subscription scope (for example, both carry the same `storeId`), and give relay devices subscriptions that cover what the devices behind them need.

`§ Transactions and Sync`

### 10. Plan for attachment availability and size (HIGH)

An attachment can be fetched only while a peer that **holds the blob** is reachable. A blob exists on a device only if that device created or fetched it; Ditto Server can hold a token without the blob ([details](reference/sync-and-storage.md#multi-hop-blob-availability)). An interrupted transfer resumes from where it stopped. If a blob must be widely available, make sure a well-connected device or Ditto Server fetches it.

**Note (SDK 5.1.0 and 5.2.0)**: In testing, a blob did not pass through a relay device until the relay had fetched it itself, even though the relay subscribed to the documents; the waiting fetch emitted no events. Do not depend on a particular relay behavior for blobs across hops ([multi-hop test](reference/sync-and-storage.md#multi-hop-blob-availability)).

**✅ DO**:
- Show a placeholder with metadata while the blob is unavailable
- Let hub devices, or a backend connected to Ditto Server, fetch attachments that many devices need
- Compress and downscale media before `newAttachment`
- Consider the slowest transport (Bluetooth LE is much slower than Wi-Fi) when deciding what to fetch automatically

**❌ DON'T**:
- Assume that receiving a document means its attachment can be downloaded right away
- Fetch large attachments automatically on devices that may be connected only over Bluetooth LE
- Look for attachment progress in `system:data_sync_info`; it is reported only through fetch events

No fixed maximum attachment size; documents have a 256 KiB soft limit and a 5 MiB hard limit ([size details](reference/sync-and-storage.md#attachment-size)).

`§ Availability`, `§ Size Guidance`, `§ Document Size Limits`

### 11. Show thumbnails in lists (MEDIUM)

Store a small preview next to the full-size attachment (`INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)`). List rows fetch only thumbnails; the full-size blob is fetched when the user opens the item.

| Preview option | Pros | Cons |
|---|---|---|
| Small attachment (downscaled JPEG) | Keeps documents small; fetched only where shown | Needs an explicit fetch |
| Tiny inline value (for example, base64) | Arrives with the document | Counts toward the 256 KiB soft limit and is re-sent with the document |

`§ Thumbnail Pattern` · Example: `thumbnail-pattern` in `examples/<sdk>/`

## Checklist

Transactions:
- [ ] Used only for multi-statement work that must be atomic (not for a single statement)
- [ ] Only the transaction object's `execute` inside the callback; no `ditto.store.execute`; every statement awaited
- [ ] No read-write transaction started inside another one
- [ ] No network calls, dialogs, user input, or timers inside the callback
- [ ] Every transaction has a `hint`; read-only work uses `isReadOnly`
- [ ] Rollback is explicit: throw or return the SDK's rollback value; caught errors do not roll back
- [ ] The transaction object is never stored or used after the callback returns
- [ ] Pending transactions are awaited before closing Ditto
- [ ] Documents changed together share a subscription scope

Attachments:
- [ ] Binary data is stored as attachments, not inside documents
- [ ] `newAttachment` from a path or bytes, with string metadata values only
- [ ] Attachment fields are declared: `INSERT INTO COLLECTION c (field ATTACHMENT) ...`
- [ ] Attachments are created before the transaction that stores them
- [ ] `fetchAttachment` is called explicitly and lazily, once per token
- [ ] Fetchers are stopped when the UI goes away (Flutter: `fetcher.attachment` never awaited after `stop()`)
- [ ] A stall timer (reset on progress) and a retry action handle unavailable blobs
- [ ] Updates create a new attachment and replace the token; removal uses `UNSET` with the `ATTACHMENT` declaration
- [ ] Lists fetch thumbnails; full-size files are fetched on demand

## More

- Reference: [reference/sdk-apis.md](reference/sdk-apis.md) - transaction and attachment signatures and short examples for Flutter, JavaScript, Kotlin, and Swift
- Examples: `examples/<sdk>/` - transactions (good/bad), lazy loading (good/bad), fetch timeout, immutability, thumbnails, with the same base names in every SDK
- Related skills: `query-sync` (subscriptions and store observers), `storage-lifecycle` (EVICT and storage management), `data-modeling` (CRDT types, strict mode, document size)
