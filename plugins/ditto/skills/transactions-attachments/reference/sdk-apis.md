# Transactions and Attachments in Each SDK (SDK 5.2)

The patterns in [SKILL.md](../SKILL.md) apply to every SDK; the API shapes differ. The JavaScript signatures below were checked against the 5.1.0 type definitions, the Swift and Kotlin signatures against DittoSwift and `ditto-kotlin` 5.2.0, with which the Swift and Kotlin examples build, and the Flutter signatures follow `ditto_live` 5.2.0. The complete, current code for each SDK is on its page, `../../guide/reference/best-practices/platforms/<sdk>.md` (*Transactions in <SDK>* and *Attachments in <SDK>*), and in `../examples/<sdk>/` (`transaction-good`, `transaction-bad`, `attachment-lazy-loading-good`, `attachment-fetch-timeout`, `attachment-immutability`, `thumbnail-pattern`). Guide: `§ Using store.transaction`, `§ Transaction Rules`, `§ Fetching Attachments`, `§ Platform Differences`.

## Table of Contents

- [Transactions at a Glance](#transactions-at-a-glance)
- [Flutter](#flutter)
- [JavaScript](#javascript)
- [Swift](#swift)
- [Kotlin](#kotlin)
- [Attachments at a Glance](#attachments-at-a-glance)

---

## Transactions at a Glance

| SDK | API | Explicit rollback | Inside the scope |
|---|---|---|---|
| Flutter | `ditto.store.transaction(hint:, isReadOnly:, (tx) async {...})` | Return `TransactionCompletionAction.rollback` | `store.execute` throws a `DittoException`; a nested read-write transaction deadlocks (the SDK does not detect it) |
| JavaScript | `ditto.store.transaction(async (tx) => {...}, { isReadOnly, hint })` | Return `'rollback'` | `store.execute` writes and nested read-write transactions deadlocked without an error in testing (5.0.3 to 5.2.0); never do it. `close()` waits for open transactions |
| Swift | `try await ditto.store.transaction(hint:isReadOnly:) { tx in ... }` | Return `.rollback` | `store.execute` writes and nested read-write transactions never returned in testing (5.1.0 and 5.2.0); never do it. Writes waiting behind it hold threads of the cooperative pool |
| Kotlin | `ditto.store.transaction(hint, isReadOnly) { tx -> ... }` | Return `DittoTransaction.Result.Rollback` | `store.execute` writes and nested read-write transactions never returned in testing (5.1.0 and 5.2.0); never do it. Writes waiting behind it hold threads of `Dispatchers.IO` |

What happens when `store.execute` or a nested read-write transaction is used inside the scope is listed per SDK on the SDK pages (*Transactions in <SDK>* and *Behavior Specific to the <SDK> SDK*); never do either on any SDK.

Rules shared by all SDKs:
- Use only the transaction object passed to the scope for queries.
- Only one read-write transaction runs at a time; keep the scope short and do I/O before it.
- Throwing inside the scope rolls back and propagates the error to the caller.
- A caught error inside the scope does **not** roll back; the transaction continues.
- A mutating statement inside a read-only transaction throws.

---

## Flutter

### Transactions

```dart
// ditto_live 5.2.0.
Future<T> transaction<T>(
  Future<T> Function(Transaction tx) callback, {
  bool isReadOnly = false,
  String? hint,
});
enum TransactionCompletionAction { commit, rollback }
// Transaction: execute(query, arguments: {...}) -> Future<QueryResult>
```

- Returning `TransactionCompletionAction.rollback` rolls back; returning `commit` or any other value (including nothing) commits, and `transaction()` returns that value.
- `ditto.store.execute` inside the callback throws a `DittoException` ("... while in a transaction scope ..."); a nested read-write transaction deadlocks, and the SDK does not detect it.
- Using the `Transaction` after the callback returns throws a `DittoException`. The `unawaited_futures` lint reports a `tx.execute` without `await`.
- `ditto.close()` does not wait for in-flight transactions; track them and await them before closing (`TransactionTracker` in `../examples/flutter/transaction-good.dart`).

```dart
// ✅ GOOD: Explicit rollback, typed result.
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
```

### Attachments

```dart
// ditto_live 5.2.0.
Future<Attachment> newAttachment(Object pathOrBytes, [AttachmentMetadata? metadata]);
AttachmentFetcher fetchAttachment(
  Map<String, dynamic> token,
  void Function(AttachmentFetchEvent event) onFetchEvent,
);
// AttachmentFetchEventProgress (downloadedBytes, totalBytes) | AttachmentFetchEventCompleted (attachment) | AttachmentFetchEventDeleted
// AttachmentFetcher: stop(), isStopped, attachment (Future<Attachment?>)
// Attachment: id, len, metadata, data (Future<Uint8List>), copyToPath(path) (native only)
// ditto.store.attachmentFetchers: active fetchers
```

- The first argument of `newAttachment` is a file path (`String`) or bytes (`Uint8List`); paths throw on the Web. Metadata is `AttachmentMetadata(Map<String, String>)`.
- `AttachmentFetchEvent` is not sealed: give every `switch` on it a `default` branch.
- `fetcher.attachment` never completes after `stop()`, so never await it once you have stopped the fetcher (and do not wrap it in `Future.timeout` and then call `stop()`).

```dart
// ✅ GOOD: Declare the ATTACHMENT field; keep the fetcher so it can be stopped.
final attachment = await ditto.store.newAttachment(
  filePath,
  AttachmentMetadata({'name': 'receipt.jpg', 'mimeType': 'image/jpeg'}),
);
await ditto.store.execute(
  'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
  arguments: {'photo': {'_id': photoId, 'image': attachment}},
);

_fetcher?.stop(); // One fetcher per token, owned by the code that displays it.
_fetcher = ditto.store.fetchAttachment(token, (event) async {
  switch (event) {
    case AttachmentFetchEventCompleted(:final attachment):
      onLoaded(await attachment.data);
    case AttachmentFetchEventDeleted():
      onUnavailable();
    default:
      break;
  }
});
// When the widget is disposed before completion: _fetcher?.stop();
```

---

## JavaScript

### Transactions

```ts
// From the 5.1.0 type definitions.
type TransactionOptions = { isReadOnly?: boolean; hint?: string }
type TransactionCompletionAction = 'commit' | 'rollback'
transaction<T = TransactionCompletionAction>(
  scope: (transaction: Transaction) => Promise<T>,
  options?: TransactionOptions,
): Promise<T>
// Transaction: info (TransactionInfo: id, hint, isReadOnly), execute(query, args)
```

- Options are the **second** argument.
- Returning `'commit'` or `'rollback'` applies that action. Any other value, including `undefined`, `null`, or `false`, commits and is returned by `transaction()`.
- A mutating statement in a read-only transaction throws a `DittoError` with code `'store/transaction-read-only'`.
- Calling `ditto.store.execute()` or starting a nested read-write transaction inside a transaction deadlocked in testing with SDK 5.0.3 to 5.2.0: the write never completed, the SDK did not throw, and the process kept running with only a `has been running for` log line every 5 seconds. A read through `store.execute` completes but does not see the transaction's writes. Use only the `tx` passed to the scope.
- `ditto.close()` waits for open transactions and other running operations, so a stuck transaction also keeps `close()` from completing.
- Await every `tx.execute` before the callback returns. A statement that was not awaited (a missing `await`, `forEach(async ...)`) was not applied in testing with SDK 5.0.3 to 5.2.0: the transaction committed, the statement failed afterwards with `No active write transaction found`, and an unhandled failure could end the Node.js process. `await Promise.all(...)` over the statements worked.
- In a Node.js script that does not start sync (seed, migration, CLI), keep the event loop alive with a timer while awaiting `ditto.store.transaction()`; otherwise the process ended with a panic before the transaction finished.
- An exception thrown in an observer callback is discarded without any report (`uncaughtException` and `unhandledRejection` stay silent), and the observer keeps running; catch and log errors inside the callback.

```js
// ✅ GOOD: Explicit rollback, options as the second argument.
const action = await ditto.store.transaction(
  async (tx) => {
    const result = await tx.execute(
      'SELECT * FROM orders WHERE _id = :id AND status = :status',
      { id: orderId, status: 'paid' },
    )
    if (result.items.length === 0) return 'rollback'
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'shipped',
    })
    return 'commit'
  },
  { hint: 'shipOrder' },
)
```

Full examples: [../examples/javascript/transaction-good.js](../examples/javascript/transaction-good.js), [../examples/javascript/transaction-bad.js](../examples/javascript/transaction-bad.js).

### Attachments

```ts
// From the 5.1.0 type definitions.
newAttachment(pathOrData: string | Uint8Array, metadata?: { [key: string]: string }): Promise<Attachment>
fetchAttachment(
  token: { id: string; len: number | bigint; metadata: { [key: string]: string } },
  eventHandler?: (event: AttachmentFetchEvent) => void,
): AttachmentFetcher // PromiseLike<Attachment | null>
type AttachmentFetchEvent =
  | { type: 'Completed'; attachment: Attachment }
  | { type: 'Progress'; totalBytes: number | bigint; downloadedBytes: number | bigint }
  | { type: 'Deleted' }
// AttachmentFetcher: attachment (Promise<Attachment>), stop()
// Attachment: id, len, metadata, data(): Promise<Uint8Array>, copyToPath(path): Promise<void>
// ditto.store.attachmentFetchers: active fetchers
```

- Creating an attachment from a file path throws in web browsers; pass a `Uint8Array` there. In Node.js, relative paths resolve from the current working directory.
- `copyToPath` throws in web browsers.
- `AttachmentFetcher` is `PromiseLike`, so `await ditto.store.fetchAttachment(token)` waits for the download. Keep the fetcher instead when you may need to call `stop()`.
- Events are distinguished by `event.type`; byte counts may be `bigint`.
- `data()` is a method in JavaScript (in Flutter, `data` is a getter).

```js
// ✅ GOOD: Declare the ATTACHMENT field; keep the fetcher so it can be stopped.
const attachment = await ditto.store.newAttachment(bytes, { name: 'receipt.jpg' })
await ditto.store.execute(
  'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
  { photo: { _id: photoId, image: attachment } },
)

const fetcher = ditto.store.fetchAttachment(token, (event) => {
  if (event.type === 'Progress') {
    showProgress(Number(event.downloadedBytes), Number(event.totalBytes))
  } else if (event.type === 'Completed') {
    event.attachment.data().then(showImage)
  } else if (event.type === 'Deleted') {
    showUnavailable()
  }
})
// Later, if the user leaves before the download finishes:
fetcher.stop()
```

---

## Swift

### Transactions

```swift
// DittoSwift 5.2.0.
@discardableResult
func transaction(hint: String? = nil, isReadOnly: Bool = false,
                 with scope: @Sendable (_ transaction: DittoTransaction) async throws  // lint-ignore: Swift type name
                     -> DittoTransactionCompletionAction) async throws -> DittoTransactionCompletionAction
func transaction<T: Sendable>(hint: String? = nil, isReadOnly: Bool = false,
                              with scope: @Sendable (_ transaction: DittoTransaction) async throws -> T)  // lint-ignore: Swift type name
    async throws -> T
enum DittoTransactionCompletionAction { case commit, rollback }
// Transaction object: execute(query:arguments:) async throws -> DittoQueryResult
```

- Return `.commit` or `.rollback` to choose explicitly, or return another value to commit and receive it from `transaction`.
- A write through `ditto.store.execute` or a nested read-write transaction inside the scope never returns; never do it. While a transaction is open, do not start as many concurrent writes as the device has CPU cores: each waiting write holds a thread of Swift's cooperative pool, and once all of them wait, every task of the process stops (`§ Transactions in Swift`).

```swift
// ✅ GOOD: Explicit rollback.
let action = try await ditto.store.transaction(hint: "shipOrder") { tx in
  let result = try await tx.execute(
    query: "SELECT * FROM orders WHERE _id = :id AND status = :status",
    arguments: ["id": orderId, "status": "paid"])
  if result.items.isEmpty { return .rollback }
  try await tx.execute(
    query: "UPDATE orders SET status = :status WHERE _id = :id",
    arguments: ["id": orderId, "status": "shipped"])
  return .commit
}
```

### Attachments

```swift
// DittoSwift 5.2.0.
func newAttachment(path: String, metadata: [String: String] = [:]) async throws -> DittoAttachment
func newAttachment(data: Data, metadata: [String: String] = [:]) async throws -> DittoAttachment
@discardableResult
func fetchAttachment(token: [String: Any], deliverOn queue: DispatchQueue = .main,
                     onFetchEvent: @escaping @Sendable (DittoAttachmentFetchEvent) -> Void) throws -> DittoAttachmentFetcher
enum DittoAttachmentFetchEvent { case completed(DittoAttachment); case progress(downloadedBytes: UInt64, totalBytes: UInt64); case deleted }
func fetchAttachmentPublisher(attachmentToken: [String: Any]) -> FetchAttachmentPublisher // Combine
// DittoAttachment: id, len: UInt64, metadata, data() throws -> Data, copy(toPath:) throws
// DittoAttachmentFetcher: stop()
```

- Fetch events are delivered on `deliverOn` (default: the main queue). Pass another queue for heavy work.
- `fetchAttachment` itself `throws`; `@discardableResult` makes it easy to drop the fetcher by accident. Keep it so you can call `stop()`.

```swift
// ✅ GOOD: Declare the ATTACHMENT field; keep the fetcher.
let attachment = try await ditto.store.newAttachment(data: bytes, metadata: ["name": "receipt.jpg"])
try await ditto.store.execute(
  query: "INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)",
  arguments: ["photo": ["_id": photoId, "image": attachment]])

self.fetcher = try ditto.store.fetchAttachment(token: token) { event in
  switch event {
  case .progress(let downloaded, let total): showProgress(downloaded, total)
  case .completed(let attachment): showImage(try? attachment.data())
  case .deleted: showUnavailable()
  @unknown default: break
  }
}
// In deinit or when the view disappears before completion:
self.fetcher?.stop()
```

---

## Kotlin

### Transactions

```kotlin
// ditto-kotlin 5.2.0 (package com.ditto.kotlin).
suspend fun <T> transaction(
    hint: String? = null,
    isReadOnly: Boolean = false,
    transactionBlock: suspend (DittoTransaction) -> DittoTransaction.Result<T>,  // lint-ignore: Kotlin type name
): DittoTransaction.Result<T>  // lint-ignore: Kotlin type name
// Result.Commit(value), Result.Commit() == Result.Commit(Unit), Result.Rollback
// Transaction object: execute(query, args) returns Unit; execute(query, args) { result -> ... } returns the handler's value
```

- The block **must** return `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback`; there is no "return any value to commit" form.
- `tx.execute(query, args)` returns `Unit`. To read inside a transaction, use the overload with a result handler; the result is closed after the handler returns, so copy out what you need.
- A mutating statement in a read-only transaction throws `DittoException.StoreException`.
- A write through `ditto.store.execute` or a nested read-write transaction inside the block never returns, and `close()` then never returns either; never do it. While a transaction is open, do not launch many writes in parallel: each waiting write holds a thread of `Dispatchers.IO`, and with 64 of them the transaction could not resume (`§ Transactions in Kotlin`).

```kotlin
// ✅ GOOD: Explicit rollback.
val outcome = ditto.store.transaction(hint = "shipOrder") { tx ->
    val isPaid = tx.execute(
        "SELECT * FROM orders WHERE _id = :id AND status = :status",
        mapOf("id" to orderId, "status" to "paid"),
    ) { result -> result.items.isNotEmpty() }
    if (!isPaid) {
        DittoTransaction.Result.Rollback  // lint-ignore: Kotlin type name
    } else {
        tx.execute(
            "UPDATE orders SET status = :status WHERE _id = :id",
            mapOf("id" to orderId, "status" to "shipped"),
        )
        DittoTransaction.Result.Commit()  // lint-ignore: Kotlin type name
    }
}
```

### Attachments

```kotlin
// ditto-kotlin 5.2.0.
fun newAttachment(path: String, metadata: Map<String, String>): DittoAttachment                   // not suspend
suspend fun newAttachment(inputStream: InputStream, metadata: Map<String, String>): DittoAttachment
suspend fun fetchAttachment(
    token: DittoAttachmentToken,          // from item.value["image"].attachmentTokenOrNull
    onFetchProgress: suspend (downloadedBytes: ULong, totalBytes: ULong) -> Unit = { _, _ -> },
): DittoAttachmentFetchResult
suspend fun fetchAttachment(tokenMap: Map<String, Any>, onFetchProgress: ...): DittoAttachmentFetchResult
// DittoAttachmentFetchResult: Completed (attachment) | Deleted; asCompleted(), asDeleted()
// DittoAttachment (AutoCloseable): id, len: ULong, metadata, getData(), getInputStream(), copyToPath(path), close()
```

- `newAttachment(path, ...)` is not a `suspend` function; the `InputStream` overload is.
- Metadata is a `Map<String, String>`. In SDK 5.2, the older overloads that take `Map<String, Any?>` metadata are deprecated and throw `IllegalArgumentException` for values that are not strings (`§ Changes in SDK 5.2.0`).
- `fetchAttachment` is a `suspend` function that returns a result instead of delivering completion events, and cancelling the coroutine that awaits it cancels the fetch. Launch it in a coroutine scope tied to the screen that shows the attachment. Progress arrives through `onFetchProgress`, but do not depend on it: in our testing, a 200 kB attachment arrived without any progress event, and a fetch that no peer could serve reported none either (`§ Attachments in Kotlin`).
- `DittoAttachment` is `AutoCloseable`; read it inside `use { }`.

```kotlin
// ✅ GOOD: Declare the ATTACHMENT field; close the attachment after reading.
val attachment = ditto.store.newAttachment(path, mapOf("name" to "receipt.jpg"))
ditto.store.execute(
    "INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)",
    mapOf("photo" to mapOf("_id" to photoId, "image" to attachment)),
)

val result = ditto.store.fetchAttachment(token) { downloaded, total ->
    showProgress(downloaded, total)
}
result.asCompleted()?.attachment?.use { fetched -> showImage(fetched.getData()) }
    ?: showUnavailable()
```

---

## Attachments at a Glance

| SDK | Create | Fetch | Cancel |
|---|---|---|---|
| Flutter | `await newAttachment(pathOrBytes, AttachmentMetadata({...}))` | `fetchAttachment(token, (event) {...})` returns `AttachmentFetcher` | `fetcher.stop()` |
| JavaScript | `await newAttachment(pathOrBytes, { key: 'value' })` (bytes only in browsers) | `fetchAttachment(token, (event) => {...})` returns `AttachmentFetcher` (awaitable) | `fetcher.stop()` |
| Swift | `try await newAttachment(path:metadata:)` / `newAttachment(data:metadata:)` | `try fetchAttachment(token:deliverOn:onFetchEvent:)` returns `DittoAttachmentFetcher` | `fetcher.stop()` |
| Kotlin | `newAttachment(path, map)` / `newAttachment(inputStream, map)` (suspend) | `fetchAttachment(token) { downloaded, total -> }` (suspend) returns `DittoAttachmentFetchResult` | Cancel the coroutine that awaits it |

In every SDK: declare the field as `ATTACHMENT` in the statement, fetch lazily, implement your own stall timeout (there is no fetch timeout or "not available" event), and replace rather than modify attachments. See [SKILL.md](../SKILL.md) rules 3, 4, 7, 8, 10, and 11.
