# Swift SDK Behavior

What we observed when we ran the Swift SDK (DittoSwift) where its API or behavior is specific to it: opening and shutting down without a `close()` method, calls after shutdown, observer handlers and handles, how Swift values are stored, transactions and Swift's cooperative thread pool, authentication, and logging. Every entry ran as a command-line program on macOS 26 (arm64) and, where the entry says so, as an app in an iOS 26.5 simulator on the same Mac, which has 14 CPU cores. The programs were built with the Swift 6.2.3 toolchain in the Swift 5 language mode against the SwiftPM package `https://github.com/getditto/DittoSwiftPackage` at the exact release, and each run used new persistence directories with every peer-to-peer transport off; where two stores synced, they connected over TCP on `127.0.0.1` with an offline license token. Real devices were not tested. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Ditto on Swift](../../best-practices/platforms/swift.md).

**In brief**

- DittoSwift 5.2.0 has no `close()` method, although the 5.2.0 release notes announce one. An instance shuts down as soon as its last strong reference is released, also while `store`, `sync`, or `presence` are still referenced, and the release waits for open transactions ([In Swift 5.2.0, Ditto has no close() method](#in-swift-520-ditto-has-no-close-method), [In Swift, releasing the last reference shuts Ditto down at once](#in-swift-releasing-the-last-reference-shuts-ditto-down-at-once)).
- After the release, some calls throw `useAfterCloseError` and others end the process with a `Fatal error`, and on 5.2.0 most writes that were still in flight fail ([In Swift, calls after the instance is released throw or end the process](#in-swift-calls-after-the-instance-is-released-throw-or-end-the-process), [In Swift 5.2.0, writes in flight fail when the instance is released](#in-swift-520-writes-in-flight-fail-when-the-instance-is-released)).
- Opening a directory that the same process has open throws `persistenceDirectoryLocked` after about a second ([In Swift, opening an open directory again fails after about a second](#in-swift-opening-an-open-directory-again-fails-after-about-a-second)).
- A `Date` argument is stored as an object, `Decimal` and `URL` as objects of their fields, and `NaN` and infinity are rejected; a float that fits in 32 bits reads back as `Float`, so `as? Double` is `nil` for it ([In Swift, item.value returns a Float for values that fit in 32 bits](#in-swift-itemvalue-returns-a-float-for-values-that-fit-in-32-bits)); result values are dictionary copies that stay readable after shutdown; invalid statements throw from the call itself; a subscription without arguments has `nil` `queryArguments` ([In Swift, a Date argument is stored as an object](#in-swift-a-date-argument-is-stored-as-an-object), [In Swift, query result values are copies that outlive the instance](#in-swift-query-result-values-are-copies-that-outlive-the-instance), [In Swift, invalid DQL throws from the registration call](#in-swift-invalid-dql-throws-from-the-registration-call), [In Swift, a subscription without arguments has nil queryArguments](#in-swift-a-subscription-without-arguments-has-nil-queryarguments)).
- A store observer's `handler:` waits for the previous call to return, and dropped observer and subscription objects keep running; an `AsyncStream` around an observer cancels it when the iterating task is cancelled ([In Swift, a store observer's handler waits for the previous one](#in-swift-a-store-observers-handler-waits-for-the-previous-one), [In Swift, dropped observer and subscription objects keep running](#in-swift-dropped-observer-and-subscription-objects-keep-running), [In Swift, an AsyncStream around an observer cancels it when its task ends](#in-swift-an-asyncstream-around-an-observer-cancels-it-when-its-task-ends)).
- Inside a read-write transaction, a write through `ditto.store.execute` and a nested read-write transaction never return; 14 concurrent writes while a transaction is open stop every task of the process on a 14-core Mac; a statement error caught inside a transaction does not roll it back ([In Swift, store.execute writes and nested read-write transactions inside a transaction do not return](#in-swift-storeexecute-writes-and-nested-read-write-transactions-inside-a-transaction-do-not-return), [In Swift, 14 concurrent writes during an open transaction stop the process](#in-swift-14-concurrent-writes-during-an-open-transaction-stop-the-process), [In Swift, a statement error caught inside a transaction does not roll it back](#in-swift-a-statement-error-caught-inside-a-transaction-does-not-roll-it-back)).
- On a device connected to a peer in another process, a read of `system:data_sync_info` sometimes stops responding, and later reads of it do as well ([In Swift, a read of system:data_sync_info can stop responding](#in-swift-a-read-of-systemdata_sync_info-can-stop-responding)).
- `login` reports failure to its completion handler, and the custom log callback stays installed for the whole process ([In Swift, login reports failure to its completion handler](#in-swift-login-reports-failure-to-its-completion-handler), [In Swift, the custom log callback stays installed after an instance shuts down](#in-swift-the-custom-log-callback-stays-installed-after-an-instance-shuts-down)).

## Swift Opening and Shutting Down

### In Swift 5.2.0, Ditto has no close() method

| | |
|---|---|
| Observed on | SDK 5.2.0 (DittoSwiftPackage 5.2.0, revision `18455b3`) and 5.1.0, one build each |
| Setup | A program that calls `ditto.close()` and `Ditto.close(ditto)`, compiled against the package; the public and private module interfaces of every slice of the 5.2.0 XCFramework |
| Documentation | The 5.2.0 release notes say "Swift adds `Ditto.close()` and `Ditto.deleteStore(databaseID:persistenceDirectory:)`", and list "`Ditto.close()` and `Ditto.deleteStore(databaseID:persistenceDirectory:)` for closing and deleting a local store (#SDKS-4662)" under the Swift changes |

- On both releases the build fails with `value of type 'Ditto' has no member 'close'` and `type 'Ditto' has no member 'close'`. The public module interface of every 5.2.0 slice (macOS, iOS, iOS simulator, Mac Catalyst) has no `close()` on `Ditto`; the only `close()` methods are on stream types behind `@_spi(PreviewDataStreams)` in the private interface.
- `Ditto.deleteStore(databaseID:persistenceDirectory:)`, `DittoConfig.encryptionKey`, and `DittoConfig.systemParameters` are in 5.2.0 and not in 5.1.0.

**Not tested:** CocoaPods and other distributions than the SwiftPM package; releases after 5.2.0.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Closing Ditto in Swift](../../best-practices/platforms/swift.md#closing-ditto-in-swift), [Changes in SDK 5.2.0](../upgrading.md#changes-in-sdk-520).

### In Swift, releasing the last reference shuts Ditto down at once

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS: a reopen after the release, three runs each; a release while a transaction with about 1 second left was open, three runs each; reading results after the release and calls after it, one run each. SDK 5.2.0, macOS: a release while a transaction with 15 seconds left was open, one run with `Ditto.shouldWaitForCleanupOnClose` at `false` and one at `true`. SDK 5.2.0, iOS simulator: a reopen after the release, two runs. Every run gave the same result |
| Setup | A `Ditto` opened by the program, a `weak` reference to it, and strong references to `ditto.store`, `ditto.sync`, and `ditto.presence`. The program set its only strong reference to `nil`, checked the weak reference, and reopened the directory. In the runs with a transaction, the transaction's scope slept and then inserted a document, and the release ran on a detached task, timed |

- The weak reference was `nil` at the first check (0 ms) in every run, also while the program held `store`, `sync`, and `presence`: these objects reference `Ditto` weakly and do not keep it alive.
- The log showed `shutting down Ditto` right after the release. The directory opened again with its data 44 to 60 ms (macOS) and 68 to 73 ms (iOS) after the release.
- With a transaction open, the release itself (setting the reference to `nil`, which runs `deinit`) blocked its thread until the transaction had finished, and the transaction committed: 904 to 973 ms for a transaction with about 1 second left (both releases), and 15,535 ms and 15,435 ms for one with 15 seconds left, longer than `Ditto.deinitTimeoutSeconds` (`10`). The log showed `Ditto shutdown complete` after the transaction. Setting `Ditto.shouldWaitForCleanupOnClose` to `true` made no difference.
- `Ditto.shouldWaitForCleanupOnClose` is `false` and `Ditto.deinitTimeoutSeconds` is `10` by default (both releases).

**Not tested:** What `deinitTimeoutSeconds` and `shouldWaitForCleanupOnClose` change; a release on the main thread while observers deliver on it; real devices.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Closing Ditto in Swift](../../best-practices/platforms/swift.md#closing-ditto-in-swift), [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown).

### In Swift, calls after the instance is released throw or end the process

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, one run of each call on each release |
| Setup | The program kept `store`, `sync`, and `presence`, released the `Ditto` instance (deallocated at once), then made one call per run |

| Call after release | 5.2.0 | 5.1.0 |
|---|---|---|
| `store.execute(query:)` | Throws `DittoError.useAfterCloseError(message: "Can't get `DittoStore`'s associated FFI object, the corresponding `Ditto` instance has been shut down.")` | Ends the process: `DittoStore.swift:732: Fatal error: Can't execute query, the corresponding `Ditto` instance has been shut down.` |
| `store.transaction { ... }` | Throws the same `useAfterCloseError` | Throws the same `useAfterCloseError` |
| `store.registerObserver(query:handler:)` | Ends the process: `DittoStore.swift:236: Fatal error: Can't register store observer, the corresponding `Ditto` is `nil`, which means it's out of scope.` | Not reached (`store.execute` ended the process first) |
| `sync.registerSubscription(query:)` | Ends the process: `DittoSync.swift:132: Fatal error: Can't register sync subscription, the corresponding `Ditto` is `nil`, which means it's out of scope.` | Ends the process (`DittoSync.swift:121`, the same message) |
| `sync.start()` | Ends the process: `DittoSync.swift:56: Fatal error: Internal inconsistency, can't start sync, the owning `Ditto` instance is `nil` but must be alive while using these APIs.` | The same |
| `presence.graph` | Ends the process: `DittoPresence.swift:57: Fatal error: Can't get presence graph, the corresponding `Ditto` instance has been deallocated.` | The same |

**Not tested:** `auth`, attachments, and `diskUsage` after the release.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Closing Ditto in Swift](../../best-practices/platforms/swift.md#closing-ditto-in-swift), [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown).

### In Swift 5.2.0, writes in flight fail when the instance is released

| | |
|---|---|
| Observed on | SDK 5.2.0, macOS: 4 runs; iOS simulator: 1 run. SDK 5.1.0, macOS: 2 runs, which did not finish |
| Setup | A read-write transaction whose scope slept 1 s and then inserted a document, and 200 `store.execute` inserts started as tasks that nobody awaited, then, at once, the release of the only strong reference to `Ditto`. For comparison: the same with 200 writes started 100 ms before the release and no transaction, three runs on each release |

- 5.2.0: the transaction committed in every run. Of the 200 writes, 1 to 4 were stored on macOS (4, 2, 1, and 3) and 8 in the iOS simulator; the others threw `useAfterCloseError` ("... the corresponding `Ditto` instance has been shut down."). Reopening found the transaction's document and those writes.
- 5.1.0: neither run finished before the time limit (180 s and 120 s). The log showed `shutting down Ditto`, then `Transaction ... has been running for 170s` and `Waiting for write transaction (elapsed: 170s) ... blocked_by=User [txn_id: 5] ... queue_depth=13`. The writes waited for the transaction's lock instead of failing, as in [In Swift, 14 concurrent writes during an open transaction stop the process](#in-swift-14-concurrent-writes-during-an-open-transaction-stop-the-process).
- Without a transaction, all 200 writes started 100 ms before the release were stored, and the release took 31 to 48 ms (both releases).

**Not tested:** Writes started after the release.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Closing Ditto in Swift](../../best-practices/platforms/swift.md#closing-ditto-in-swift), [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown).

### In Swift, opening an open directory again fails after about a second

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, three runs each; SDK 5.2.0, iOS simulator, one run |
| Setup | While the process had a directory open, `Ditto.open(config:)` and `Ditto.openSync(config:)` with the same `DittoConfig`; `Ditto.deleteStore(databaseID:persistenceDirectory:)` on an open directory (SDK 5.2.0, macOS, one run) |

- Both threw `DittoError.storeError(reason: .persistenceDirectoryLocked(message: "File already locked, working dir = <dir>, retried 5 times.\nMultiple Ditto instances cannot run at the same time within the same working directory. Either use unique working directories for each instance, or consider managing your Ditto instance as a singleton instead."))`, after 1,011 to 1,032 ms (macOS, both releases) and 1,028 ms (iOS).
- `Ditto.deleteStore` on an open directory threw the same error at once ("retried 0 times"). On a store whose instance had been released, it succeeded and left only `__ditto_lock_file` in the directory.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory), [One shared instance in Swift](../../best-practices/platforms/swift.md#one-shared-instance-in-swift).

## Swift Queries and Values

### In Swift, a Date argument is stored as an object

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, one run each; the results were the same apart from `NSNumber(value: true)` |
| Setup | Each value written as field `v` of its own document through `arguments`, then read back with `SELECT v, type(v) AS t` |
| Documentation | The 5.2.0 release notes say that boolean arguments created with `JSONSerialization` are stored as booleans instead of `0` or `1` since 5.2.0 |

| Swift value | `type(v)` | `item.value["v"]` |
|---|---|---|
| `String`, `Bool`, `Int`, `Int8`, `UInt8`, `Int64.min`, `Int64.max`, `9_007_199_254_740_993` | string, boolean, integer | `String`, `Bool`, `Int`, exact |
| `UInt64.max` | integer | `UInt`, exact |
| `Double` `0.1`, `Float` `0.1` | float | `Double` `0.1`; `Float` `0.1` (JSON `0.10000000149011612`) |
| `nil`, `NSNull()` | null | `nil` |
| `Date(timeIntervalSince1970: 1700000000.123)` | object | `{"__type": "date_epoch_timestamp", "__value": 1700000000.123}` |
| `Data([0, 1, 2, 255])` | binary | `[UInt8]` `[0, 1, 2, 255]` |
| `UUID` | string | the uppercase `uuidString` |
| `Decimal(string: "1.10")` | object | `{"exponent": -1, "isCompact": true, "isNegative": false, "length": 1, "mantissa": [11, 0, 0, 0, 0, 0, 0, 0]}` |
| `URL(string: "https://example.com/a")` | object | `{"relative": "https://example.com/a"}` |
| A nested dictionary with `-5`, an array with `nil` | object, array | the same values |
| `NSNumber(value: true)` | 5.2.0: boolean; 5.1.0: integer | 5.2.0: `Bool` `true`; 5.1.0: `Int` `1` |
| `NSNumber(value: 3)` | integer | `Int` |
| `Double.nan`, `Double.infinity`, `Character`, `Substring` | — | The write throws `DittoError.storeError(reason: .queryArgumentsInvalid)` ("The provided query arguments were invalid.") |

- A `Date` is not stored as a time: DQL sees an object, so date functions and ordering by the field do not work as they do for an ISO 8601 string. `Decimal` and `URL` become objects of their internal fields.

**Not tested:** `Float.nan`; strings with unpaired surrogates (a Swift `String` cannot hold them).

**Used in:** [Arguments and value types in Swift](../../best-practices/platforms/swift.md#arguments-and-value-types-in-swift), [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [IDs and Timestamps in Swift](../../best-practices/platforms/swift.md#ids-and-timestamps-in-swift).

### In Swift, item.value returns a Float for values that fit in 32 bits

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, one run each; the results were the same |
| Setup | Swift `Double` values written as field `v` of their own documents through `arguments`, a DQL literal (`12.5`), a `Float(12.5)`, and `SUM` of two of the values; each read back with `SELECT`, and `item.value["v"]` cast with `as? Double` and `as? NSNumber`, and `item.jsonData()` decoded with `JSONDecoder` into a `Double` field |

| Written | `item.value["v"]` | `as? Double` |
|---|---|---|
| `0.5`, `1.0`, `2.0`, `12.5`, `3.25`, `1e10`, `-0.0` | `Float` | `nil` |
| `0.1`, `1.0 / 3.0`, `16777217.0`, `3.4e38`, `1e300` | `Double` | the value |
| The DQL literal `12.5`, `Float(12.5)`, `SUM` of `12.5` and `3.25` (`15.75`) | `Float` | `nil` |

- A value that a 32-bit float represents exactly came back as a Swift `Float`, others as `Double`; `type(v)` was `float` for all of them, and the JSON of the row had the full value (`12.5`, `0.1`).
- `as? NSNumber` gave the value in every case (`doubleValue`), and so did `JSONDecoder` into a `Double` field.

**Not tested:** Values inside nested objects and arrays; integers stored as floats by other SDKs.

**Used in:** [Arguments and value types in Swift](../../best-practices/platforms/swift.md#arguments-and-value-types-in-swift), [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Query results in Swift](../../best-practices/platforms/swift.md#query-results-in-swift).

### In Swift, query result values are copies that outlive the instance

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, one run each; the results were the same |
| Setup | A `SELECT` of one document; the program read `item.value`, changed its copy, read again, dematerialized the item, then released the `Ditto` instance and read the items of two results (one read before, one never read) |

- `isMaterialized` was `false` before the first read of `value` and `true` after it; `dematerialize()` set it back to `false`, and `value` returned the same contents again.
- `value` is a Swift dictionary, a value type: changing the copy changed neither the item (`status` still `open`) nor the store.
- After the instance had been deallocated, both results could still be read, including `jsonData()` of the item that had never been read.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Query results in Swift](../../best-practices/platforms/swift.md#query-results-in-swift).

### In Swift, invalid DQL throws from the registration call

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, one run each; the messages were the same |
| Setup | Invalid statements passed to `execute`, `registerObserver`, `registerSubscription`, and `tx.execute` |

- Every call threw `DittoError` at once; none returned an object that reported the error later:
  - a syntax error: `.storeError(reason: .queryInvalid(message: "<dql> Invalid query: `DQL parser error: Unexpected token SELEC at line 1 column 1 near \"SELEC * FROM cars\"; expected a DQL statement`. For more information on Ditto's query language see: https://ditto.com/link/dql-guide"))`, from all four calls;
  - an unknown function: `.queryInvalid` with "`Function \"nosuch\" not found`"; a missing argument: `.queryInvalid` with "`Parameter id was not provided`";
  - an `UPDATE` in an observer: `.queryNotSupported(message: "<dql> Unsupported feature: non-SELECT statement in store observer")`;
  - a subscription with `ORDER BY` and `LIMIT`: `.queryNotSupported` with "Limit or Order by"; with a `JOIN`: "Joining".
- `error.localizedDescription` is the message without the enum path.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Executing DQL in Swift](../../best-practices/platforms/swift.md#executing-dql-in-swift).

### In Swift, a subscription without arguments has nil queryArguments

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, one run each; the results were the same |
| Setup | Subscriptions to the same collection without arguments, with `[:]`, with a dictionary, and with an `Encodable` struct; observers without and with arguments |

- Without arguments, `queryArguments` is `nil` and `queryArgumentsJSONData` is empty; with `[:]`, they are `[:]` and `{}`. The dictionary and the `Encodable` struct gave the same `queryArguments` (`["status": "open"]`) and JSON (`{"status":"open"}`). Observers behaved the same.
- `sync.subscriptions` listed all 4 subscriptions; two with the same query and arguments were not `==`.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Subscriptions in Swift](../../best-practices/platforms/swift.md#subscriptions-in-swift).

## Swift Observers and Handles

### In Swift, a store observer's handler waits for the previous one

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, three runs each; every run gave the same result |
| Setup | A document updated 10 times, 50 ms apart (535 to 552 ms for all 10), observed by four observers of the same query, each on its own serial queue: (a) a `handler:` that starts a `Task` with 500 ms of async work and returns; (b) a `handler:` that blocks its queue for 500 ms; (c) a `handlerWithSignalNext:` that calls `signalNext()` after 500 ms of async work; (d) a `handler:` on the default queue |
| Documentation | The Swift v4 to v5 migration guide says that `registerObserver` signals readiness for the next callback after the handler returns, and that `handlerWithSignalNext` lets the app decide when the next callback arrives. The 5.1.0 release notes say that callbacks are delivered on the `deliverOn` queue since 5.1 |

- (a) received all 11 states (0 to 10); up to 10 of its tasks ran at the same time, and all 11 finished.
- (b) received 3 states (0, 4, and 10), one at a time: the SDK held back the next result until the handler returned, and the last state arrived.
- (c) received the same 3 states, one at a time.
- (d) ran on the main thread for all 11 calls (the default `deliverOn` is `.main`).
- The handler type is not `throws`: a `throw` inside it does not compile ("invalid conversion from throwing function ... to non-throwing function type"), on both releases.

**Not tested:** Handlers on a concurrent queue; observers of remote changes.

**Used in:** [Backpressure in Swift](../../best-practices/platforms/swift.md#backpressure-in-swift), [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Keep observer callbacks fast](../../best-practices/observers.md#keep-observer-callbacks-fast).

### In Swift, dropped observer and subscription objects keep running

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS, three runs each; SDK 5.2.0, iOS simulator, one run; every run gave the same result |
| Setup | Store b registered an observer and a subscription inside a `do` block without keeping the returned objects (both methods are `@discardableResult`); weak references showed when the objects were deallocated. Store a then wrote a document. For comparison, a kept observer and subscription were cancelled with `cancel()`. Finally the program cancelled what `store.observers` and `sync.subscriptions` listed |

- Both objects were deallocated when the block ended. Ditto kept both registrations: `store.observers` and `sync.subscriptions` each listed 1 entry, the document from store a arrived, and the observer was called again (2 calls).
- `cancel()` on kept objects stopped them: `isCancelled` was `true`, the document did not arrive, and the observer was not called.
- The objects in `store.observers` are other objects than the one that `registerObserver` returned (`===` is `false`) but equal to it (`==` is `true`). `cancel()` on the listed objects stopped the dropped registrations.
- The results match the JavaScript SDK ([In JavaScript, garbage-collected subscriptions and observers keep running](javascript-sdk.md#in-javascript-garbage-collected-subscriptions-and-observers-keep-running)).

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Closing Ditto in Swift](../../best-practices/platforms/swift.md#closing-ditto-in-swift), [Observer Lifecycle](../../best-practices/observers.md#observer-lifecycle), [Store Observers in Swift](../../best-practices/platforms/swift.md#store-observers-in-swift), [Subscription Lifecycle](../../best-practices/sync-and-subscriptions.md#subscription-lifecycle).

### In Swift, an AsyncStream around an observer cancels it when its task ends

| | |
|---|---|
| Observed on | SDK 5.2.0: macOS, one run of the probe and two runs of the page's examples; iOS simulator, one run of the page's examples |
| Setup | An `AsyncStream` whose builder registers an observer and sets `continuation.onTermination` to cancel it, iterated by a task. The probe inserted a document, then cancelled the task. The page's test returned from the loop once the new row had arrived; in its first version the stream was created outside the task and stayed referenced, in the final version inside the task |

- The rows arrived (2 rows, then 3 after the insert). Cancelling the iterating task cancelled the observer: `isCancelled` was `true`, and `store.observers` went from 1 to 0.
- Returning from the loop while the stream was still referenced outside the task left the observer registered (`store.observers` was not empty). With the stream created inside the task, it was cancelled once the task had ended, in every run.

**Not tested:** A stream released without being iterated; an observer whose registration throws inside the builder.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Observer lifecycle in Swift](../../best-practices/platforms/swift.md#observer-lifecycle-in-swift).

## Swift Transactions

### In Swift, store.execute writes and nested read-write transactions inside a transaction do not return

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS: reads through `store.execute`, nested transactions, and a write in a read-only transaction, three runs each on 5.2.0 and two on 5.1.0; a write through `store.execute`, two runs on 5.2.0 and one on 5.1.0; every run gave the same result |
| Setup | Inside a read-write `store.transaction`: a `SELECT` and, in another run, an `INSERT` through `ditto.store.execute`; a read-write and a read-only transaction started inside a read-write transaction, and a read-only one inside a read-only one; an `INSERT` in a read-only transaction. A call that did not end within 10 s counted as not returning. After a write had not returned, the program tried a plain `INSERT` (5 s limit) and watched for 50 s more |
| Documentation | The JavaScript SDK's type definitions warn that `ditto.store.execute()` or a nested transaction inside a transaction may lead to a deadlock; we found no such text for Swift |

- A `SELECT` through `ditto.store.execute` returned at once (2 to 4 ms) and, like any read outside the transaction, did not see the transaction's own insert (0 rows, while `tx.execute` saw 1).
- An `INSERT` through `ditto.store.execute` did not return within 10 s. After that, a plain `SELECT` still answered at once and found nothing, a plain `INSERT` did not return within 5 s, and no write became visible in the next 50 s.
- `tx.store` is the same object as `ditto.store` (`===` is `true`), so `tx.store.execute` is a call outside the transaction.
- A read-write transaction inside a read-write transaction did not return within 10 s. A read-only transaction inside a read-write one returned within 2 ms and saw only committed data, and so did a read-only one inside a read-only one.
- An `INSERT` in a read-only transaction threw `DittoError.storeError(reason: .transactionReadOnly(message: "<store> A mutating DQL query was attempted using a read-only transaction."))`.
- The results match the JavaScript SDK ([In JavaScript, store.execute writes inside a transaction deadlock](javascript-sdk.md#in-javascript-storeexecute-writes-inside-a-transaction-deadlock)).

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Transaction Rules](../../best-practices/transactions.md#transaction-rules), [Transactions in Swift](../../best-practices/platforms/swift.md#transactions-in-swift).

### In Swift, 14 concurrent writes during an open transaction stop the process

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, macOS: 13 writes and 14 writes, three runs each; SDK 5.2.0, macOS: 4, 8, and 16 writes, one run each, and 13 writes, one more run; iOS simulator: 14 writes, one run. A transaction of `tx.execute` statements with 64 writes, one run on each release. 200 writes without a transaction, two runs on each release and one more on 5.2.0 |
| Setup | A read-write transaction on a detached task; its scope slept 1 s (`Task.sleep`), then inserted a document. 100 ms after it began, N `store.execute` inserts started at once on detached tasks. The program waited at most 15 s for the transaction (`Lab.settle`) and printed progress lines. In another case, a transaction ran 20 `tx.execute` inserts in sequence, with no other `await`, and 64 concurrent writes started with it. In a third, 200 concurrent writes ran with no transaction open. `ProcessInfo.activeProcessorCount` was 14 on macOS and in the simulator |

- With 4, 8, or 13 writes, the transaction committed after 0.92 to 0.97 s, and every write finished, on both releases.
- With 14 or 16 writes, the transaction never resumed after `Task.sleep`, and no write finished. On macOS, even the program's 15 s limit never fired: every task of the process stopped until the lab ended it after 40 or 60 s (6 of 6 runs with 14 writes, on both releases). In the iOS simulator, the 15 s limit fired after 16 s with 0 writes finished, and the app did not exit afterwards.
- 14 is the width of Swift's cooperative thread pool on this Mac. A `store.execute` write that waits for the write lock appears to hold a pool thread while it waits, so once 14 writes wait, nothing can resume the transaction that holds the lock.
- With 64 concurrent writes, a transaction of plain `tx.execute` statements did not complete even its first statement (both releases).
- Without an open transaction, 200 concurrent writes all finished in 52 to 213 ms (both releases).

**Not tested:** Real devices, whose pools are narrower; concurrent reads instead of writes; writes from `DispatchQueue` threads instead of tasks; a transaction started after the writes.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Executing DQL in Swift](../../best-practices/platforms/swift.md#executing-dql-in-swift), [Transaction Rules](../../best-practices/transactions.md#transaction-rules), [Transactions in Swift](../../best-practices/platforms/swift.md#transactions-in-swift).

### In Swift, a statement error caught inside a transaction does not roll it back

| | |
|---|---|
| Observed on | SDK 5.2.0, macOS, one run |
| Setup | A read-write transaction that inserted a document, caught the error of an invalid statement (`SELEC broken`) inside its scope, inserted a second document, and returned `.commit`. In a second transaction, an `INSERT` of an `_id` that already existed, without `ON ID CONFLICT` |

- Both inserts of the first transaction were committed: the caught error did not end or roll back the transaction.
- The duplicate `_id` threw `DittoError.unknownError(message: "<dql> Query failed: `DQL Internal execution error: Insert failed: <store> Document CRDT error for document \"before\": DQL evaluation failed with DQL evaluation error: Identifier conflict on document \"before\": using FAIL conflict policy`. ...")`: an `unknownError`, not a `storeError`.

**Not tested:** 5.1.0; returning `.rollback` after a caught error.

**Used in:** [Transactions in Swift](../../best-practices/platforms/swift.md#transactions-in-swift).

## Swift Sync Status

### In Swift, a read of system:data_sync_info can stop responding

| | |
|---|---|
| Observed on | SDK 5.2.0, 25 runs (10 of the first setup and 15 that also waited after a stuck read); SDK 5.1.0, 10 runs; macOS |
| Setup | Two devices, each subscribed to `orders`: this device listened on TCP on `127.0.0.1`, and the other ran in a second process (the same program started again) and connected to it. After this device saw the other in presence (356 to 424 ms after the start), it inserted a document, which reached the other device, and then read `SELECT * FROM system:data_sync_info` up to 20 times, 50 ms apart. A read that had not completed after 3 seconds counted as stuck. After a stuck read, this device read `orders`, waited 20 seconds more for the stuck read, called `sync.stop()`, and read `system:data_sync_info` again (the 15 runs) |

| | 5.2.0 | 5.1.0 |
|---|---|---|
| Runs with a stuck read | 4 of 25 (2 of 10, then 2 of 15) | 1 of 10 |
| Which read got stuck | Always the second | The second |
| Reads that completed | In 0 to 30 ms | In 0 to 10 ms |

- A stuck read had still not completed 20 seconds later (23 seconds after it started). A second read of `system:data_sync_info` on the same device also got stuck, while a read of `orders` completed at once, and the other device was still in presence.
- `sync.stop()` returned at once, but a read of `system:data_sync_info` after it got stuck as well.
- The result matches the JavaScript SDK ([In JavaScript, a read of system:data_sync_info can stop responding](javascript-sdk.md#in-javascript-a-read-of-systemdata_sync_info-can-stop-responding)).

**Not tested:** An observer of `system:data_sync_info`; both devices in one process; the iOS simulator; whether the device recovers after more than 23 seconds or after the instance is released; devices connected to Ditto Server.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Closing Ditto in Swift](../../best-practices/platforms/swift.md#closing-ditto-in-swift), [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Monitoring Sync Status](../../best-practices/sync-and-subscriptions.md#monitoring-sync-status).

## Swift Authentication and Logging

### In Swift, login reports failure to its completion handler

| | |
|---|---|
| Observed on | SDK 5.2.0, macOS: one run of the probe and two runs of the page's examples; iOS simulator, one run of the page's examples |
| Setup | A store opened with `.server(url: URL(string: "http://127.0.0.1:9")!)`, a port where nothing listens. The program started sync without and with an expiration handler, called `login(token:provider:completion:)` with an invalid token, read `auth.status`, called `logout(cleanup:)`, and ran a query afterwards. On a small-peers-only store it read `ditto.auth` |

- `ditto.auth` is `nil` for a small-peers-only store and non-`nil` for a server connection.
- Without an expiration handler, `sync.start()` threw `DittoError.authenticationError(reason: .expirationHandlerMissing(message: "<authentication> The operation failed because an authentication expiration handler has not yet been set."))`. With a handler, sync started, and Ditto called the handler once at once, with `timeUntilExpiration` `0.0`.
- `login` did not throw: its completion handler received `clientInfo` `nil` and `DittoError.authenticationError(reason: .failedToAuthenticate)` 2 ms later; `auth.status.isAuthenticated` stayed `false`.
- `logout(cleanup:)` ran the cleanup closure before it returned, and sync was no longer active afterwards; a query after `logout` succeeded.

**Not tested:** A reachable server, a valid token, and an expiring token.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk).

### In Swift, the custom log callback stays installed after an instance shuts down

| | |
|---|---|
| Observed on | SDK 5.2.0, macOS, one run |
| Setup | `DittoLogger.setCustomLogCallback` counted the lines it received while an instance was open, after that instance had been released, and while a second instance was open; `DittoLogger.minimumLogLevel` was set before any instance existed |

- The callback received 26 lines while the first instance was open, 30 after its release, and 56 once a second instance had run a query: it stayed installed for the whole process.
- `DittoLogger.minimumLogLevel` could be set before any instance was opened. Its default is `.info`, and `DittoLogger.isEnabled` is `true` by default.
- `DittoLogger.export(to:)` wrote the on-disk logs and returned the number of bytes; to an existing file it threw `DittoError.ioError(reason: .alreadyExists(message: "File exists (os error 17)"))`.

**Not tested:** 5.1.0; which lines the callback receives at each level.

**Used in:** [Behavior Specific to the Swift SDK](../../best-practices/platforms/swift.md#behavior-specific-to-the-swift-sdk), [Logging in Swift](../../best-practices/platforms/swift.md#logging-in-swift).
