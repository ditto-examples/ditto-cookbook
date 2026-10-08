# Transactions and Attachments on JavaScript, Swift, and Kotlin (SDK 5.1)

The patterns in [SKILL.md](../SKILL.md) apply to every platform; the API shapes differ. Signatures below were checked against the 5.1.0 SDK artifacts: the JavaScript type definitions (`@dittolive/ditto` 5.1.0), the Swift interface (`DittoSwift` 5.1.0), and the Kotlin sources (`com.ditto:ditto-kotlin` 5.1.0). Guide: [Transactions on Other Platforms](../../../../guides/best-practices/ditto.md#transactions-on-other-platforms) and [Platform Differences](../../../../guides/best-practices/ditto.md#platform-differences).

## Table of Contents

- [Transactions at a Glance](#transactions-at-a-glance)
- [JavaScript](#javascript)
- [Swift](#swift)
- [Kotlin](#kotlin)
- [Attachments at a Glance](#attachments-at-a-glance)

---

## Transactions at a Glance

| Platform | API | Explicit rollback | Inside the scope |
|---|---|---|---|
| Flutter | `ditto.store.transaction((tx) async {...}, isReadOnly:, hint:)` | Return `TransactionCompletionAction.rollback` | `store.execute` throws a `DittoException`; a nested read-write transaction can deadlock (the SDK does not detect it) |
| JavaScript | `ditto.store.transaction(async (tx) => {...}, { isReadOnly, hint })` | Return `'rollback'` | `store.execute` writes or nested read-write transactions can deadlock (no error is thrown); never do it |
| Swift | `try await ditto.store.transaction(hint:isReadOnly:) { tx in ... }` | Return `.rollback` | `store.execute` or nesting can deadlock; never do it |
| Kotlin | `ditto.store.transaction(hint, isReadOnly) { tx -> ... }` | Return `DittoTransaction.Result.Rollback` | `store.execute` or nesting can deadlock; never do it |

Rules shared by all platforms:
- Use only the transaction object passed to the scope for queries.
- Only one read-write transaction runs at a time; keep the scope short and do I/O before it.
- Throwing inside the scope rolls back and propagates the error to the caller.
- A caught error inside the scope does **not** roll back; the transaction continues.
- A mutating statement inside a read-only transaction throws.

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
- Calling `ditto.store.execute()` or starting a nested read-write transaction inside a transaction can deadlock; the SDK does not throw. Use only the `tx` passed to the scope.

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

Full examples: [../examples/transaction-good.js](../examples/transaction-good.js), [../examples/transaction-bad.js](../examples/transaction-bad.js).

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
// From the 5.1.0 Swift interface.
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
- Calling `ditto.store.execute` or starting a nested read-write transaction inside the scope can deadlock; never do it.

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
// From the 5.1.0 Swift interface.
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
// From the 5.1.0 Kotlin sources (package com.ditto.kotlin).
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
- Calling `ditto.store.execute` or starting a nested transaction inside the block can deadlock; never do it.

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
// From the 5.1.0 Kotlin sources.
fun newAttachment(path: String, metadata: Map<String, Any?>): DittoAttachment                     // not suspend
suspend fun newAttachment(inputStream: InputStream, metadata: Map<String, Any?>): DittoAttachment
suspend fun fetchAttachment(
    tokenMap: Map<String, Any>,
    onFetchProgress: suspend (downloadedBytes: ULong, totalBytes: ULong) -> Unit = { _, _ -> },
): DittoAttachmentFetchResult
// DittoAttachmentFetchResult: Completed (attachment) | Deleted; asCompleted(), asDeleted()
// DittoAttachment (AutoCloseable): id, len: ULong, metadata, getData(), getInputStream(), copyToPath(path), close()
```

- `newAttachment(path, ...)` is not a `suspend` function; the `InputStream` overload is.
- The metadata parameter is typed `Map<String, Any?>`, but use string values only, as on every other platform.
- `fetchAttachment` is a `suspend` function that returns a result instead of delivering completion events. Progress arrives through `onFetchProgress`. Launch it in a coroutine scope tied to the screen that shows the attachment.
- `DittoAttachment` is `AutoCloseable`; read it inside `use { }`.

```kotlin
// ✅ GOOD: Declare the ATTACHMENT field; close the attachment after reading.
val attachment = ditto.store.newAttachment(path, mapOf("name" to "receipt.jpg"))
ditto.store.execute(
    "INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)",
    mapOf("photo" to mapOf("_id" to photoId, "image" to attachment)),
)

val result = ditto.store.fetchAttachment(tokenMap) { downloaded, total ->
    showProgress(downloaded, total)
}
result.asCompleted()?.attachment?.use { fetched -> showImage(fetched.getData()) }
    ?: showUnavailable()
```

---

## Attachments at a Glance

| Platform | Create | Fetch | Cancel |
|---|---|---|---|
| Flutter | `await newAttachment(pathOrBytes, AttachmentMetadata({...}))` | `fetchAttachment(token, (event) {...})` returns `AttachmentFetcher` | `fetcher.stop()` |
| JavaScript | `await newAttachment(pathOrBytes, { key: 'value' })` (bytes only in browsers) | `fetchAttachment(token, (event) => {...})` returns `AttachmentFetcher` (awaitable) | `fetcher.stop()` |
| Swift | `try await newAttachment(path:metadata:)` / `newAttachment(data:metadata:)` | `try fetchAttachment(token:deliverOn:onFetchEvent:)` returns `DittoAttachmentFetcher` | `fetcher.stop()` |
| Kotlin | `newAttachment(path, map)` / `newAttachment(inputStream, map)` (suspend) | `fetchAttachment(tokenMap) { downloaded, total -> }` (suspend) returns `DittoAttachmentFetchResult` | Not covered here |

On every platform: declare the field as `ATTACHMENT` in the statement, fetch lazily, implement your own stall timeout (there is no fetch timeout or "not available" event), and replace rather than modify attachments. See [SKILL.md](../SKILL.md) patterns 6 to 11.
