---
name: transactions-attachments
description: Ditto SDK transactions and attachments: ditto.store.transaction with tx.execute only, no nesting, short scopes, rollback, and close(); newAttachment, ATTACHMENT field declarations, lazy fetchAttachment with a stall timeout, immutability, thumbnails, and blob availability. Use when writing or reviewing ditto.store.transaction, tx.execute, newAttachment, fetchAttachment, or AttachmentFetcher code, or when displaying photos or files stored in Ditto.
---

# Ditto Transactions and Attachments

Atomic multi-statement writes with `ditto.store.transaction`, and binary files stored, synced, and displayed as attachments. Targets Ditto SDK 5.1.0; examples are Flutter (Dart).

## Before You Apply

- Check the project's Ditto SDK version (`ditto_live` in `pubspec.lock`, `@dittolive/ditto` in `package-lock.json`, `DittoSwift` in `Package.resolved`, `com.ditto` in Gradle files); these rules were verified with 5.1.0. **Note (SDK 5.1.0)** marks easy-to-miss 5.1.0 behavior (wrong results, lost data, crashes, hangs) and its safe pattern; on another version, confirm it (release notes, docs.ditto.live) first. **(SDK 5.1+)** marks features introduced in 5.1.
- Examples are Dart. For JavaScript, Swift, or Kotlin, translate with `§ Platform Differences` and do not port Flutter observer or transaction code one-to-one.
- `§ <Heading>` cites a section of the full guide: Grep the heading in `../guide/reference/ditto.md` and read it for the reasoning or a complete example.

## Key Facts

| Topic | Flutter 5.1.0 behavior |
|---|---|
| Transaction API | `ditto.store.transaction(hint: 'name', isReadOnly: false, (tx) async {...})` returns `Future<T>` |
| Inside the callback | Use only `tx.execute(...)`. `ditto.store.execute(...)` throws a `DittoException` |
| Commit / rollback | Throwing rolls back and rethrows; returning `TransactionCompletionAction.rollback` rolls back; anything else commits |
| Concurrency | One read-write transaction at a time; read-only transactions run concurrently |
| `ditto.close()` | Does not wait for in-flight transactions |
| Create an attachment | `await ditto.store.newAttachment(pathOrBytes, AttachmentMetadata({...}))` |
| Store it | `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)` |
| Fetch it | `ditto.store.fetchAttachment(token, (event) {...})` returns an `AttachmentFetcher`; cancel with `stop()` |
| Sync | Subscriptions sync the token only; blobs move only when a device fetches them |

## Prevents

- `ditto.store.execute` inside a transaction (throws in Flutter, can deadlock in JavaScript, Swift, and Kotlin)
- Nested read-write transactions (deadlock in Flutter and JavaScript, can deadlock in Swift and Kotlin; the SDK does not detect it)
- Network calls, dialogs, or timers inside a transaction, blocking all other writes
- Caught statement errors that silently commit the rest of a transaction
- `ditto.close()` while transactions are still running (`close()` does not wait)
- Assuming subscriptions download attachment blobs (only tokens sync)
- Eager or duplicate fetches, fetchers that are never stopped, and fetches without a timeout
- Trying to modify an attachment in place (attachments are immutable)
- Binary data stored inside documents instead of as attachments

## Rules

A transaction runs several DQL statements against the local store atomically. It does not lock anything on other peers. A single `INSERT`, `UPDATE`, or `DELETE` is already atomic, so do not wrap it in a transaction. `§ Using store.transaction`

### 1. Use only tx.execute inside a transaction, and never nest (CRITICAL)

Calling `ditto.store.execute` inside the callback throws a `DittoException` in Flutter. In JavaScript, Swift, and Kotlin the SDKs do not throw; a write through `store.execute` inside a transaction can deadlock, so the same rule applies. Starting a read-write transaction inside another one deadlocks in Flutter and JavaScript (and can deadlock in Swift and Kotlin), because only one read-write transaction runs at a time; the Flutter SDK does not detect it.

**✅ DO**: Run every read and write of the transaction through the `tx` passed to the callback.
**❌ DON'T**:
- Call `ditto.store.execute(...)` inside the callback
- Call `ditto.store.transaction(...)` (read-write) inside another read-write transaction, directly or through a helper method
- Store the `Transaction` object or use it after the callback returns (Flutter throws a `DittoException`)

`§ Transaction Rules`, `§ Platform Differences` · Full code: [reference/flutter-code.md](reference/flutter-code.md) · Examples: [transaction-good.dart](examples/transaction-good.dart), [transaction-bad.dart](examples/transaction-bad.dart), [transaction-good.js](examples/transaction-good.js), [transaction-bad.js](examples/transaction-bad.js)

### 2. Keep transactions short (CRITICAL)

While a read-write transaction runs, every other read-write transaction waits, and so does a plain `store.execute` write issued meanwhile. Network calls, dialogs, user input, or timers inside the callback block all writes.

**✅ DO**:
- Read, decide, write, return
- Prepare network responses, files, user input, and attachments (`newAttachment`) **before** the transaction
- Give every transaction a `hint`: after 10 seconds Ditto logs a message that includes it every 5 seconds, starting at debug level and escalating to higher levels (thresholds: system parameters `TRANSACTION_DURATION_BEFORE_LOGGING_MS` and `TRANSACTION_TRACE_INTERVAL_MS`)
- Use `isReadOnly: true` for transactions that only read; a mutating statement inside one throws

**❌ DON'T**:
- `await` network calls, dialogs, or timers inside the callback
- Read `commitID` inside the transaction to track sync status; it is `null` until the transaction commits. Keep the `QueryResult` of the write (for example, return it from the callback) and read its `commitID` after `transaction()` completes

`§ Transaction Rules`, `§ Concurrency and Duration` · Full code: [reference/flutter-code.md](reference/flutter-code.md#io-before-the-transaction-rule-2)

### 3. Create attachments with newAttachment and declare ATTACHMENT fields (CRITICAL)

An attachment has two parts: the **token** (`{id, len, metadata}`), stored in a document field and synced like other data, and the **blob**, stored outside the document database and transferred only when a device calls `fetchAttachment`. The `id` is a hash of the contents, so identical blobs are stored once. `newAttachment` copies the file into Ditto's blob store.

**✅ DO**:
- Pass a file path (`String`) or bytes (`Uint8List`) to `newAttachment`; on the web only bytes work (paths throw). Pass an absolute file path (for example, one built from `path_provider`).
- Declare the field (`COLLECTION photos (image ATTACHMENT)`; `COLLECTION` is required when declaring types). Without strict mode (default `DQL_STRICT_MODE = false`) an undeclared attachment is still stored as one; strict mode requires the declaration, hides undeclared ATTACHMENT fields from queries, and statements that omit the declaration, including `UNSET`, leave the attachment unchanged without an error (`§ Strict Mode`). Declaring works in both modes.
- Pass the `Attachment` object inside a parameter; never build tokens by hand
- Create the attachment **before** starting a transaction that stores it

**❌ DON'T**:
- Store base64-encoded files in regular fields; they count toward the document size limit and are re-sent with the document
- Put non-string values into `AttachmentMetadata`
- Delete the original file before `newAttachment` completes (afterwards, the copy in Ditto's store is what matters)

```dart
final attachment = await ditto.store.newAttachment(
  filePath,
  AttachmentMetadata({'name': 'receipt.jpg', 'mimeType': 'image/jpeg'}), // String values only.
);
await ditto.store.execute(
  'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
  arguments: {'photo': {'_id': photoId, 'image': attachment, 'createdAt': utcTimestamp()}},
);
```

`§ Attachment Architecture`, `§ Creating and Inserting Attachments` · Full code: [reference/flutter-code.md](reference/flutter-code.md#create-and-insert-an-attachment-rule-3)

### 4. Fetch attachments explicitly, lazily, and cancellably (CRITICAL)

Subscriptions never download blobs; a token is not image data. Fetching every attachment as soon as a document syncs wastes bandwidth and storage.

| Event | Delivered | Contents |
|---|---|---|
| `AttachmentFetchEventProgress` | Zero or more times | `downloadedBytes`, `totalBytes` |
| `AttachmentFetchEventCompleted` | At most once | `attachment` (read bytes with `await attachment.data`) |
| `AttachmentFetchEventDeleted` | At most once (instead of Completed) | The attachment was deleted while being fetched |

**Note (SDK 5.1.0)**: `AttachmentFetchEventDeleted` was not observed in our testing: when the document was deleted while no peer could deliver the blob, the fetch stayed pending; keep a stall timeout.

`AttachmentFetcher`: `stop()` cancels an in-flight fetch (not needed after completion); `isStopped`; `attachment` is a `Future<Attachment?>` that never completes after `stop()`, so do not await it once you have stopped the fetcher. `ditto.store.attachmentFetchers` lists active fetchers. Attachments already in the local blob store complete right away, typically without progress events.

**✅ DO**:
- Fetch when the widget that shows the attachment is built (for example, a row of `ListView.builder`)
- Keep the `AttachmentFetcher` until the fetch completes; call `stop()` when the user navigates away first
- Show `len` and metadata from the token before the download starts
- Add a `default` branch to `switch` statements on `AttachmentFetchEvent` (it is not sealed; progress events land there)

**❌ DON'T**:
- Fetch every attachment of every document as soon as it syncs
- Start a new fetch for the same token on every rebuild or observer update

```dart
_fetcher?.stop(); // One fetcher per token, owned by the code that displays it.
_fetcher = ditto.store.fetchAttachment(token, (event) async {
  switch (event) {
    case AttachmentFetchEventCompleted(:final attachment):
      onLoaded(await attachment.data);
    case AttachmentFetchEventDeleted():
      debugPrint('Attachment was deleted during the fetch');
    default:
      break;
  }
});
// In dispose(): _fetcher?.stop();
```

`§ Fetching Attachments` · Full code: [reference/flutter-code.md](reference/flutter-code.md#photoloader-one-fetcher-per-token-rule-4) · Examples: [attachment-lazy-loading-good.dart](examples/attachment-lazy-loading-good.dart), [attachment-lazy-loading-bad.dart](examples/attachment-lazy-loading-bad.dart)

### 5. End a transaction deliberately (HIGH)

| Callback outcome | Result |
|---|---|
| Returns `TransactionCompletionAction.commit` | Committed; `transaction()` returns `TransactionCompletionAction.commit` |
| Returns `TransactionCompletionAction.rollback` | Rolled back; no changes are applied |
| Returns any other value (including nothing) | Committed; `transaction()` returns that value |
| Throws | Rolled back; the error is rethrown to the caller |
| A statement fails but the callback catches the error | The transaction **continues**; the remaining changes are committed unless you roll back |

**❌ DON'T**: Catch an error from `tx.execute` and carry on without deciding. If the remaining work must not commit, rethrow or return `TransactionCompletionAction.rollback`.

```dart
final action = await ditto.store.transaction(hint: 'shipOrder', (tx) async {
  final result = await tx.execute(
    'SELECT * FROM orders WHERE _id = :id AND status = :status',
    arguments: {'id': orderId, 'status': 'paid'},
  );
  if (result.items.isEmpty) return TransactionCompletionAction.rollback;
  await tx.execute('UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'shipped'});
  return TransactionCompletionAction.commit;
});
return action == TransactionCompletionAction.commit;
```

`§ Transaction Rules` · Example: [transaction-good.dart](examples/transaction-good.dart)

### 6. Await pending transactions before close() (HIGH)

`ditto.close()` in Flutter does not wait for in-flight transactions; calls that are still running can fail with `DittoClosedException`. Track pending transactions (a set of their futures, removed in `whenComplete`) and await them, ignoring their errors, before closing.

`§ Resource Cleanup and Shutdown` · Full code (`TransactionTracker`): [reference/flutter-code.md](reference/flutter-code.md#transactiontracker-await-before-close-rule-6) · Example: [transaction-good.dart](examples/transaction-good.dart)

### 7. Implement your own fetch timeout (HIGH)

Ditto has no fetch timeout and no "not available" event. While no reachable peer can deliver the blob, the fetch simply makes no progress.

**✅ DO**: Restart a timer on every progress event. When it fires, stop the fetcher and offer a retry. Use a longer stall timeout for larger files.
**❌ DON'T**: Treat a fetch that has not made progress as an error immediately; peers that have the blob may connect later. Do not wrap `fetcher.attachment` in `Future.timeout` and then call `stop()`: the future never completes after `stop()`.

`§ Fetching Attachments`, `§ Availability` · Example: [attachment-fetch-timeout.dart](examples/attachment-fetch-timeout.dart)

### 8. Replace attachments, never modify them (HIGH)

Attachment contents never change. To "edit" a file, create a new attachment and replace the token: `UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id`. Attachments cannot be deleted directly: remove the token (`UPDATE COLLECTION photos (image ATTACHMENT) UNSET image ...`, or set a new token), delete the document with `DELETE` (for every peer), or evict it from this device with `EVICT`. Unreferenced blobs are garbage-collected on Small Peers only ([details](reference/sync-and-storage.md#blob-garbage-collection)); do not cache `Attachment` objects longer than needed.

**❌ DON'T**: Overwrite the source file and expect the attachment to change (the file was copied into Ditto's store), or keep many old tokens in history documents unless you need them (every referenced blob stays on the device).

`§ Attachments Are Immutable` · Full code: [reference/flutter-code.md](reference/flutter-code.md#replace-an-attachment-rule-8) · Example: [attachment-immutability.dart](examples/attachment-immutability.dart)

### 9. Keep transacted documents in one subscription scope (MEDIUM)

Atomicity is guaranteed on the device that commits. A peer whose subscriptions cover only part of a transaction's documents receives only that part, and a relay can forward only what it has ([transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions)). Receiver-side test results: [reference/sync-and-storage.md](reference/sync-and-storage.md#transactions-on-receiving-peers).

**✅ DO**: Keep documents that change together in the same subscription scope (for example, both carry the same `storeId`), and give relay devices subscriptions that cover what the devices behind them need.

`§ Transactions and Sync`

### 10. Show thumbnails in lists (MEDIUM)

Store a small preview next to the full-size attachment (`INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)`). List rows fetch only thumbnails; the full-size blob is fetched when the user opens the item.

| Preview option | Pros | Cons |
|---|---|---|
| Small attachment (downscaled JPEG) | Keeps documents small; fetched only where shown | Needs an explicit fetch |
| Tiny inline value (for example, base64) | Arrives with the document | Counts toward the 256 KiB soft limit and is re-sent with the document |

`§ Thumbnail Pattern` · Full code: [reference/flutter-code.md](reference/flutter-code.md#insert-a-thumbnail-and-a-full-size-attachment-rule-10) · Example: [thumbnail-pattern.dart](examples/thumbnail-pattern.dart)

### 11. Plan for attachment availability and size (MEDIUM)

An attachment can be fetched only while a peer that **holds the blob** is reachable. A blob exists on a device only if that device created or fetched it; Ditto Server can hold a token without the blob ([details](reference/sync-and-storage.md#multi-hop-blob-availability)). An interrupted transfer resumes from where it stopped. If a blob must be widely available, make sure a well-connected device or Ditto Server fetches it.

**Note (SDK 5.1.0)**: In testing, a blob did not pass through a relay device until the relay had fetched it itself, even though the relay subscribed to the documents; the waiting fetch emitted no events. Do not depend on a particular relay behavior for blobs across hops ([multi-hop test](reference/sync-and-storage.md#multi-hop-blob-availability)).

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

## Checklist

Transactions:
- [ ] Used only for multi-statement work that must be atomic (not for a single statement)
- [ ] Only `tx.execute` inside the callback; no `ditto.store.execute`
- [ ] No read-write transaction started inside another one
- [ ] No network calls, dialogs, user input, or timers inside the callback
- [ ] Every transaction has a `hint`; read-only work uses `isReadOnly: true`
- [ ] Rollback is explicit: throw or return `TransactionCompletionAction.rollback`; caught errors do not roll back
- [ ] The `Transaction` object is never stored or used after the callback returns
- [ ] Pending transactions are awaited before `ditto.close()`
- [ ] Documents changed together share a subscription scope

Attachments:
- [ ] Binary data is stored as attachments, not inside documents
- [ ] `newAttachment(pathOrBytes, AttachmentMetadata({...}))` with string metadata values only
- [ ] Attachment fields are declared: `INSERT INTO COLLECTION c (field ATTACHMENT) ...`
- [ ] Attachments are created before the transaction that stores them
- [ ] `fetchAttachment` is called explicitly and lazily, once per token
- [ ] Fetchers are stopped when the UI goes away; `fetcher.attachment` is never awaited after `stop()`
- [ ] A stall timer (reset on progress) and a retry action handle unavailable blobs
- [ ] `switch` on `AttachmentFetchEvent` has a `default` branch
- [ ] Updates create a new attachment and replace the token; removal uses `UNSET` with the `ATTACHMENT` declaration
- [ ] Lists fetch thumbnails; full-size files are fetched on demand

## More

- Reference: [reference/flutter-code.md](reference/flutter-code.md) - complete Flutter code for the shortened snippets
- Reference: [reference/platform-specific.md](reference/platform-specific.md) - JavaScript, Swift, and Kotlin 5.1 transaction and attachment APIs
- Examples: [examples/](examples/) - Dart and JavaScript transactions (good/bad), lazy loading (good/bad), fetch timeout, immutability, thumbnails
- Guide sections: `§ Transactions`, `§ Transactions on Other Platforms`, `§ Attachments`, `§ Resource Cleanup and Shutdown`, `§ Platform Differences`
- Related skills: `query-sync` (subscriptions and store observers), `storage-lifecycle` (EVICT and storage management), `data-modeling` (CRDT types, strict mode, document size)
