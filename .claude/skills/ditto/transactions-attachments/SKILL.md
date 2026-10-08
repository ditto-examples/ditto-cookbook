---
name: transactions-attachments
description: |
  Validates Ditto SDK 5.1 transaction usage and attachment handling.

  CRITICAL ISSUES PREVENTED:
  - Calling ditto.store.execute inside a transaction (throws in Flutter, can deadlock in JavaScript, Swift, and Kotlin)
  - Nested read-write transactions (deadlock in Flutter and JavaScript, can deadlock in Swift and Kotlin; the SDK does not detect it)
  - Network calls, dialogs, or timers inside a transaction (block all other writes)
  - Closing Ditto while transactions are still running (close() does not wait)
  - Assuming subscriptions download attachment blobs (only tokens sync)
  - Eager or duplicate attachment fetches, fetchers that are never stopped, and fetches without a timeout
  - Trying to modify an attachment in place (attachments are immutable)
  - Binary data stored inside documents instead of as attachments

  TRIGGERS:
  - Using ditto.store.transaction(), Transaction, tx.execute, TransactionCompletionAction
  - Implementing atomic multi-document changes or read-check-write logic
  - Shutting down a Ditto instance that may have transactions in flight
  - Calling newAttachment(), fetchAttachment(), AttachmentFetcher, AttachmentMetadata
  - Declaring ATTACHMENT fields in INSERT or UPDATE statements
  - Displaying photos, PDFs, signatures, or other binary files from Ditto documents

  PLATFORMS: Flutter (primary), JavaScript, Swift, Kotlin
---

# Ditto Transactions and Attachments (SDK 5.1)

## Table of Contents

- [Purpose](#purpose)
- [When This Skill Applies](#when-this-skill-applies)
- [Key Facts](#key-facts)
- [Transaction Patterns](#transaction-patterns)
  - [1. Use tx.execute Only, and Never Nest](#1-use-txexecute-only-and-never-nest-priority-critical)
  - [2. Keep Transactions Short](#2-keep-transactions-short-priority-critical)
  - [3. End a Transaction Deliberately](#3-end-a-transaction-deliberately-priority-high)
  - [4. Await Pending Transactions Before close()](#4-await-pending-transactions-before-close-priority-high)
  - [5. Keep Transacted Documents in One Subscription Scope](#5-keep-transacted-documents-in-one-subscription-scope-priority-medium)
- [Attachment Patterns](#attachment-patterns)
  - [6. Create Attachments and Declare ATTACHMENT Fields](#6-create-attachments-and-declare-attachment-fields-priority-critical)
  - [7. Fetch Explicitly, Lazily, and Cancellably](#7-fetch-explicitly-lazily-and-cancellably-priority-critical)
  - [8. Implement Your Own Timeout](#8-implement-your-own-timeout-priority-high)
  - [9. Replace, Never Modify](#9-replace-never-modify-priority-high)
  - [10. Thumbnail Pattern](#10-thumbnail-pattern-priority-medium)
  - [11. Plan for Availability and Size](#11-plan-for-availability-and-size-priority-medium)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

## Purpose

This Skill applies the [Transactions](../../../guides/best-practices/ditto.md#transactions) and [Attachments](../../../guides/best-practices/ditto.md#attachments) sections of the Ditto best-practices guide. The guide is the source of truth; this Skill extracts the actionable patterns. Examples are Flutter (`ditto_live` 5.1.0) unless stated otherwise. For JavaScript, Swift, and Kotlin signatures, see [reference/platform-specific.md](reference/platform-specific.md).

## When This Skill Applies

- Code calls `ditto.store.transaction(...)` or uses a `Transaction` object
- Several documents must change together, or a write depends on a read
- App shutdown code calls `ditto.close()`
- Code calls `newAttachment` or `fetchAttachment`, or declares `ATTACHMENT` fields
- UI shows images or files that are stored in Ditto

## Key Facts

| Topic | Flutter 5.1.0 behavior |
|---|---|
| Transaction API | `ditto.store.transaction((tx) async {...}, isReadOnly: false, hint: 'name')` returns `Future<T>` |
| Inside the callback | Use only `tx.execute(...)`. `ditto.store.execute(...)` throws a `DittoException` |
| Commit / rollback | Throwing rolls back and rethrows; returning `TransactionCompletionAction.rollback` rolls back; anything else commits |
| Concurrency | One read-write transaction at a time; read-only transactions run concurrently |
| `ditto.close()` | Does not wait for in-flight transactions |
| Create an attachment | `await ditto.store.newAttachment(pathOrBytes, AttachmentMetadata({...}))` |
| Store it | `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)` |
| Fetch it | `ditto.store.fetchAttachment(token, (event) {...})` returns an `AttachmentFetcher`; cancel with `stop()` |
| Sync | Subscriptions sync the token only; blobs move only when a device fetches them |

---

## Transaction Patterns

A transaction runs several DQL statements against the local store atomically. It does not lock anything on other peers. A single `INSERT`, `UPDATE`, or `DELETE` is already atomic, so do not wrap it in a transaction. Guide: [Using store.transaction](../../../guides/best-practices/ditto.md#using-storetransaction).

### 1. Use tx.execute Only, and Never Nest (Priority: CRITICAL)

**Problem**: Calling `ditto.store.execute` inside the callback throws a `DittoException` in Flutter. In JavaScript, Swift, and Kotlin the SDKs do not throw; a write through `store.execute` inside a transaction can deadlock, so the same rule applies. Starting a read-write transaction inside another one deadlocks in Flutter and JavaScript (and can deadlock in Swift and Kotlin), because only one read-write transaction runs at a time; the Flutter SDK does not detect it. Guide: [Transaction Rules](../../../guides/best-practices/ditto.md#transaction-rules), [Platform Differences](../../../guides/best-practices/ditto.md#platform-differences).

```dart
// ✅ GOOD: Close an order and create its invoice atomically, using only tx.
Future<void> closeOrderWithInvoice(Ditto ditto, String orderId, String invoiceId) async {
  await ditto.store.transaction(hint: 'closeOrderWithInvoice', (tx) async {
    final result = await tx.execute(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': orderId},
    );
    if (result.items.isEmpty) {
      throw StateError('Order $orderId not found'); // Throwing rolls back.
    }
    final order = result.items.first.value;
    await tx.execute(
      'INSERT INTO invoices DOCUMENTS (:invoice)',
      arguments: {
        'invoice': {
          '_id': invoiceId,
          'orderId': orderId,
          'total': order['total'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      },
    );
    await tx.execute(
      'UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'closed', 'invoiceId': invoiceId},
    );
  });
}
```

**❌ DON'T**:
- Call `ditto.store.execute(...)` inside the callback
- Call `ditto.store.transaction(...)` (read-write) inside another read-write transaction, directly or through a helper method
- Store the `Transaction` object or use it after the callback returns (Flutter throws a `DittoException`)

**See**: [examples/transaction-good.dart](examples/transaction-good.dart), [examples/transaction-bad.dart](examples/transaction-bad.dart), [examples/transaction-good.js](examples/transaction-good.js), [examples/transaction-bad.js](examples/transaction-bad.js)

---

### 2. Keep Transactions Short (Priority: CRITICAL)

**Problem**: While a read-write transaction runs, every other read-write transaction waits, and so does a plain `store.execute` write issued meanwhile. Network calls, dialogs, user input, or timers inside the callback block all writes. Guide: [Transaction Rules](../../../guides/best-practices/ditto.md#transaction-rules), [Concurrency and Duration](../../../guides/best-practices/ditto.md#concurrency-and-duration).

```dart
// ✅ GOOD: Do the I/O first, then record the outcome in one short transaction.
Future<void> checkout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await chargeCard(); // Outside the transaction.
  await ditto.store.transaction(hint: 'recordPayment', (tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id',
      arguments: {
        'id': orderId,
        'status': 'paid',
        'paidAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await tx.execute(
      'INSERT INTO payments DOCUMENTS (:payment)',
      arguments: {
        'payment': {'_id': 'payment-$orderId', 'orderId': orderId},
      },
    );
  });
}
```

**✅ DO**:
- Read, decide, write, return
- Prepare network responses, files, user input, and attachments (`newAttachment`) **before** the transaction
- Give every transaction a `hint`: after 10 seconds Ditto logs warnings that include it, every 5 seconds (thresholds: system parameters `TRANSACTION_DURATION_BEFORE_LOGGING_MS` and `TRANSACTION_TRACE_INTERVAL_MS`)
- Use `isReadOnly: true` for transactions that only read; a mutating statement inside one throws

**❌ DON'T**:
- `await` network calls, dialogs, or timers inside the callback
- Read `commitID` inside the transaction to track sync status; it is `null` until the transaction commits. Keep the `QueryResult` of the write (for example, return it from the callback) and read its `commitID` after `transaction()` completes

---

### 3. End a Transaction Deliberately (Priority: HIGH)

| Callback outcome | Result |
|---|---|
| Returns `TransactionCompletionAction.commit` | Committed; `transaction()` returns `TransactionCompletionAction.commit` |
| Returns `TransactionCompletionAction.rollback` | Rolled back; no changes are applied |
| Returns any other value (including nothing) | Committed; `transaction()` returns that value |
| Throws | Rolled back; the error is rethrown to the caller |
| A statement fails but the callback catches the error | The transaction **continues**; the remaining changes are committed unless you roll back |

```dart
// ✅ GOOD: Explicit rollback without throwing.
Future<bool> shipOrder(Ditto ditto, String orderId) async {
  final action = await ditto.store.transaction(hint: 'shipOrder', (tx) async {
    final result = await tx.execute(
      'SELECT * FROM orders WHERE _id = :id AND status = :status',
      arguments: {'id': orderId, 'status': 'paid'},
    );
    if (result.items.isEmpty) return TransactionCompletionAction.rollback;
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'shipped'},
    );
    return TransactionCompletionAction.commit;
  });
  return action == TransactionCompletionAction.commit;
}
```

**❌ DON'T**: Catch an error from `tx.execute` and carry on without deciding. If the remaining work must not commit, rethrow or return `TransactionCompletionAction.rollback`.

---

### 4. Await Pending Transactions Before close() (Priority: HIGH)

**Problem**: `ditto.close()` in Flutter does not wait for in-flight transactions; calls that are still running can fail with `DittoClosedException`. Track pending transactions and await them before closing. Guide: [Resource Cleanup and Shutdown](../../../guides/best-practices/ditto.md#resource-cleanup-and-shutdown).

```dart
// ✅ GOOD: Track in-flight transactions so shutdown can wait for them.
class TransactionTracker {
  final _pending = <Future<Object?>>{};

  Future<T> run<T>(Ditto ditto, String hint, Future<T> Function(Transaction tx) work) {
    final future = ditto.store.transaction(hint: hint, work);
    _pending.add(future);
    return future.whenComplete(() => _pending.remove(future));
  }

  Future<void> closeWhenIdle(Ditto ditto) async {
    // Errors are reported to the callers of run(); ignore them here.
    // then() with an onError callback works for any result type T, whereas a
    // catchError handler would have to return a value of type T.
    await Future.wait(_pending.map((f) => f.then<void>((_) {}, onError: (Object _) {})));
    await ditto.close();
  }
}
```

---

### 5. Keep Transacted Documents in One Subscription Scope (Priority: MEDIUM)

Atomicity is guaranteed on the device that commits. Ditto's [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) describes two limits for replication: a peer whose subscriptions cover only part of a transaction's documents receives only that part, and a relay can forward only what it has. Keep documents that change together in the same subscription scope (for example, both carry the same `storeId`), and give relay devices subscriptions that cover what the devices behind them need. Guide: [Transactions and Sync](../../../guides/best-practices/ditto.md#transactions-and-sync).

---

## Attachment Patterns

An attachment has two parts: the **token** (`{id, len, metadata}`), stored in a document field and synced like other data, and the **blob**, stored outside the document database and transferred only when a device calls `fetchAttachment`. The `id` is a hash of the contents, so identical blobs are stored once. Guide: [Attachment Architecture](../../../guides/best-practices/ditto.md#attachment-architecture).

### 6. Create Attachments and Declare ATTACHMENT Fields (Priority: CRITICAL)

```dart
// ✅ GOOD: Create the attachment, then insert it with a declared ATTACHMENT field.
Future<void> savePhoto(Ditto ditto, String photoId, String filePath) async {
  // The file is copied into Ditto's blob store.
  final attachment = await ditto.store.newAttachment(
    filePath,
    AttachmentMetadata({'name': 'receipt.jpg', 'mimeType': 'image/jpeg'}), // String values only.
  );
  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'image': attachment,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    },
  );
}
```

**✅ DO**:
- Pass a file path (`String`) or bytes (`Uint8List`) to `newAttachment`; on the web only bytes work (paths throw). Pass an absolute file path (for example, one built from `path_provider`).
- Declare the field (`COLLECTION photos (image ATTACHMENT)`); the `COLLECTION` keyword is required when you declare types. With the default `DQL_STRICT_MODE = false`, an attachment inserted without the declaration is still stored as an attachment, but strict mode requires the declaration and hides undeclared ATTACHMENT fields from queries ([Strict Mode](../../../guides/best-practices/ditto.md#strict-mode)). With strict mode enabled, statements that do not declare the field, including `UNSET`, leave the attachment value unchanged without an error. Declaring works in both modes.
- Pass the `Attachment` object inside a parameter; never build tokens by hand
- Create the attachment **before** starting a transaction that stores it

**❌ DON'T**:
- Store base64-encoded files in regular fields; they count toward the document size limit and are re-sent with the document
- Put non-string values into `AttachmentMetadata`
- Delete the original file before `newAttachment` completes (afterwards, the copy in Ditto's store is what matters)

Guide: [Creating and Inserting Attachments](../../../guides/best-practices/ditto.md#creating-and-inserting-attachments).

---

### 7. Fetch Explicitly, Lazily, and Cancellably (Priority: CRITICAL)

**Problem**: Subscriptions never download blobs; a token is not image data. Fetching every attachment as soon as a document syncs wastes bandwidth and storage. Guide: [Fetching Attachments](../../../guides/best-practices/ditto.md#fetching-attachments).

| Event | Delivered | Contents |
|---|---|---|
| `AttachmentFetchEventProgress` | Zero or more times | `downloadedBytes`, `totalBytes` |
| `AttachmentFetchEventCompleted` | At most once | `attachment` (read bytes with `await attachment.data`) |
| `AttachmentFetchEventDeleted` | At most once (instead of Completed) | The attachment was deleted while being fetched |

`AttachmentFetcher`: `stop()` cancels an in-flight fetch (not needed after completion); `isStopped`; `attachment` is a `Future<Attachment?>` that never completes after `stop()`, so do not await it once you have stopped the fetcher. `ditto.store.attachmentFetchers` lists active fetchers. Attachments already in the local blob store complete right away, typically without progress events.

```dart
// ✅ GOOD: One fetcher per token, owned by the code that displays it.
class PhotoLoader {
  PhotoLoader(this.ditto);

  final Ditto ditto;
  AttachmentFetcher? _fetcher;

  void load(Map<String, dynamic> token, void Function(List<int> bytes) onLoaded) {
    _fetcher?.stop();
    _fetcher = ditto.store.fetchAttachment(token, (event) async {
      switch (event) {
        case AttachmentFetchEventCompleted(:final attachment):
          onLoaded(await attachment.data);
        case AttachmentFetchEventDeleted():
          debugPrint('Attachment was deleted during the fetch');
        default: // AttachmentFetchEvent is not sealed; progress events land here.
          break;
      }
    });
  }

  void dispose() => _fetcher?.stop(); // Cancel if the screen goes away first.
}
```

**✅ DO**:
- Fetch when the widget that shows the attachment is built (for example, a row of `ListView.builder`)
- Keep the `AttachmentFetcher` until the fetch completes; call `stop()` when the user navigates away first
- Show `len` and metadata from the token before the download starts
- Add a `default` branch to `switch` statements on `AttachmentFetchEvent`

**❌ DON'T**:
- Fetch every attachment of every document as soon as it syncs
- Start a new fetch for the same token on every rebuild or observer update

**See**: [examples/attachment-lazy-loading-good.dart](examples/attachment-lazy-loading-good.dart), [examples/attachment-lazy-loading-bad.dart](examples/attachment-lazy-loading-bad.dart)

---

### 8. Implement Your Own Timeout (Priority: HIGH)

**Problem**: Ditto has no fetch timeout and no "not available" event. While no reachable peer can deliver the blob, the fetch simply makes no progress.

**✅ DO**: Restart a timer on every progress event. When it fires, stop the fetcher and offer a retry. Use a longer stall timeout for larger files.

**❌ DON'T**: Treat a fetch that has not made progress as an error immediately; peers that have the blob may connect later. Do not wrap `fetcher.attachment` in `Future.timeout` and then call `stop()`: the future never completes after `stop()`.

**See**: [examples/attachment-fetch-timeout.dart](examples/attachment-fetch-timeout.dart)

---

### 9. Replace, Never Modify (Priority: HIGH)

Attachment contents never change. To "edit" a file, create a new attachment and replace the token. Attachments cannot be deleted directly: remove the token (`UPDATE COLLECTION photos (image ATTACHMENT) UNSET image ...`, or set a new token), delete the document with `DELETE` (for every peer), or evict it from this device with `EVICT`. On Small Peers, blobs that are no longer referenced are garbage-collected automatically every 10 minutes; garbage collection runs only on Small Peers, not on Ditto Server. Guide: [Attachments Are Immutable](../../../guides/best-practices/ditto.md#attachments-are-immutable).

```dart
// ✅ GOOD: Replace the attachment by updating the token field.
Future<void> replacePhoto(Ditto ditto, String photoId, String newFilePath) async {
  final attachment = await ditto.store.newAttachment(
    newFilePath,
    AttachmentMetadata({'name': 'receipt-v2.jpg', 'mimeType': 'image/jpeg'}),
  );
  await ditto.store.execute(
    'UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id',
    arguments: {'id': photoId, 'image': attachment},
  );
}
```

**❌ DON'T**: Overwrite the source file and expect the attachment to change (the file was copied into Ditto's store), or keep many old tokens in history documents unless you need them (every referenced blob stays on the device).

**See**: [examples/attachment-immutability.dart](examples/attachment-immutability.dart)

---

### 10. Thumbnail Pattern (Priority: MEDIUM)

Store a small preview next to the full-size attachment. List rows fetch only thumbnails; the full-size blob is fetched when the user opens the item. Guide: [Thumbnail Pattern](../../../guides/best-practices/ditto.md#thumbnail-pattern).

| Preview option | Pros | Cons |
|---|---|---|
| Small attachment (downscaled JPEG) | Keeps documents small; fetched only where shown | Needs an explicit fetch |
| Tiny inline value (for example, base64) | Arrives with the document | Counts toward the 256 KiB soft limit and is re-sent with the document |

```dart
import 'dart:typed_data';

// ✅ GOOD: Insert a thumbnail and a full-size attachment together.
Future<void> savePhotoWithThumbnail(
  Ditto ditto, {
  required String photoId,
  required Uint8List thumbnailBytes, // Downscaled by your app beforehand.
  required String fullSizePath,
}) async {
  final thumbnail = await ditto.store.newAttachment(
    thumbnailBytes,
    AttachmentMetadata({'kind': 'thumbnail', 'mimeType': 'image/jpeg'}),
  );
  final fullSize = await ditto.store.newAttachment(
    fullSizePath,
    AttachmentMetadata({'kind': 'full', 'mimeType': 'image/jpeg'}),
  );
  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'thumbnail': thumbnail,
        'image': fullSize,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    },
  );
}
```

**See**: [examples/thumbnail-pattern.dart](examples/thumbnail-pattern.dart)

---

### 11. Plan for Availability and Size (Priority: MEDIUM)

An attachment can be fetched only while a peer that **holds the blob** is reachable. A blob exists on a device only if that device created or fetched it. Ditto's [attachment documentation](https://docs.ditto.live/sdk/latest/crud/working-with-attachments) describes that Ditto Server can hold a document with an attachment token but not the blob, for example when Small Peers replicate the document among themselves without fetching the attachment. An interrupted transfer resumes from where it stopped. Do not design workflows that depend on a particular relay behavior for blobs across multiple hops; if a blob must be widely available, make sure a well-connected device or Ditto Server fetches it. Guide: [Availability](../../../guides/best-practices/ditto.md#availability), [Size Guidance](../../../guides/best-practices/ditto.md#size-guidance).

**✅ DO**:
- Show a placeholder with metadata while the blob is unavailable
- Let hub devices, or a backend connected to Ditto Server, fetch attachments that many devices need
- Compress and downscale media before `newAttachment`
- Consider the slowest transport (Bluetooth LE is much slower than Wi-Fi) when deciding what to fetch automatically

**❌ DON'T**:
- Assume that receiving a document means its attachment can be downloaded right away
- Fetch large attachments automatically on devices that may be connected only over Bluetooth LE
- Look for attachment progress in `system:data_sync_info`; it is reported only through fetch events

There is no fixed maximum attachment size in the SDK; device storage and bandwidth are the practical limits. Blob storage does not count toward the per-device key-value storage guidance (about 2 GB); uploads through the HTTP API have a separate 1 MB request body limit. Documents have a 256 KiB soft limit (warning) and a 5 MiB hard limit (writes that exceed it fail) ([Document Size Limits](../../../guides/best-practices/ditto.md#document-size-limits)).

---

## Quick Reference Checklist

### Transactions
- [ ] Used only for multi-statement work that must be atomic (not for a single statement)
- [ ] Only `tx.execute` inside the callback; no `ditto.store.execute`
- [ ] No read-write transaction started inside another one
- [ ] No network calls, dialogs, user input, or timers inside the callback
- [ ] Every transaction has a `hint`; read-only work uses `isReadOnly: true`
- [ ] Rollback is explicit: throw or return `TransactionCompletionAction.rollback`; caught errors do not roll back
- [ ] The `Transaction` object is never stored or used after the callback returns
- [ ] Pending transactions are awaited before `ditto.close()`
- [ ] Documents changed together share a subscription scope

### Attachments
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

---

## See Also

### Main Guide
- [Transactions](../../../guides/best-practices/ditto.md#transactions)
- [Transactions on Other Platforms](../../../guides/best-practices/ditto.md#transactions-on-other-platforms)
- [Attachments](../../../guides/best-practices/ditto.md#attachments)
- [Resource Cleanup and Shutdown](../../../guides/best-practices/ditto.md#resource-cleanup-and-shutdown)
- [Platform Differences](../../../guides/best-practices/ditto.md#platform-differences)

### Examples
- [examples/transaction-good.dart](examples/transaction-good.dart) - Atomic changes, rollback, read-only snapshots, shutdown tracking
- [examples/transaction-bad.dart](examples/transaction-bad.dart) - `store.execute` inside, nesting, I/O inside, leaked `Transaction`
- [examples/transaction-good.js](examples/transaction-good.js) - JavaScript 5.1 transaction patterns
- [examples/transaction-bad.js](examples/transaction-bad.js) - JavaScript anti-patterns (can deadlock instead of throwing)
- [examples/attachment-lazy-loading-good.dart](examples/attachment-lazy-loading-good.dart) - Lazy, cancellable image widget in a list
- [examples/attachment-lazy-loading-bad.dart](examples/attachment-lazy-loading-bad.dart) - Eager, duplicate, and leaked fetches
- [examples/attachment-fetch-timeout.dart](examples/attachment-fetch-timeout.dart) - Stall timeout and retry
- [examples/attachment-immutability.dart](examples/attachment-immutability.dart) - Replacing and removing attachments
- [examples/thumbnail-pattern.dart](examples/thumbnail-pattern.dart) - Thumbnail plus full-size attachment

### Reference
- [reference/platform-specific.md](reference/platform-specific.md) - JavaScript, Swift, and Kotlin 5.1 APIs

### Other Skills
- [query-sync](../query-sync/SKILL.md) - Subscriptions and store observers
- [storage-lifecycle](../storage-lifecycle/SKILL.md) - EVICT and storage management
- [data-modeling](../data-modeling/SKILL.md) - CRDT types, strict mode, document size
