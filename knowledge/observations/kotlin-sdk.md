# Kotlin SDK Behavior

What the Kotlin SDK's API does when an app uses it: on which thread Ditto calls an app's code, how observers wait for it and what happens when it throws, how query results and values behave, what opening, closing, and transactions do, and how authentication, transports, attachments, and logging report what they do. The observations of how Ditto itself syncs, merges, and stores data are on the other observation pages; this page covers only what the Kotlin API adds. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The patterns that follow from these observations are in [Ditto on Kotlin](../../best-practices/platforms/kotlin.md).

Unless an entry says otherwise, every entry used `com.ditto:ditto-kotlin` 5.2.0 and 5.1.0 in an Android instrumented test on the Android 16 emulator (API 36, arm64-v8a), with one `Ditto` instance per new persistence directory, `DittoConfig.Connect.SmallPeersOnly()`, every transport off (`ditto.transportConfig = DittoTransportConfig()`), and `DittoFactory.create(config)` with its default coroutine scope. Entries with two devices ran two instances in the same app, licensed with an offline license token and connected over TCP on the emulator's `127.0.0.1`, some through a relay that can stall the link. Entries that needed a server connection used `DittoConfig.Connect.Server("http://127.0.0.1:9")`, a closed port inside the emulator, so that nothing left the emulator.

**In brief**

- Ditto calls observer handlers, the expiration handler, and connection request handlers in the scope that `DittoFactory.create` received, which on Android is `MainScope()` by default, so they run on the main thread ([In Kotlin, observer handlers run on the main thread unless DittoFactory.create gets another scope](#in-kotlin-observer-handlers-run-on-the-main-thread-unless-dittofactorycreate-gets-another-scope)).
- Every observer API waits for the app's code and skips intermediate results; the `Flow` of `observe` runs one result ahead of a slow collector, and each collection of it is an observer of its own ([In Kotlin, observer handlers run one at a time, and intermediate results are skipped](#in-kotlin-observer-handlers-run-one-at-a-time-and-intermediate-results-are-skipped), [In Kotlin, each collection of an observe() Flow is its own observer](#in-kotlin-each-collection-of-an-observe-flow-is-its-own-observer)).
- A `registerObserver` handler that throws closes its observer without telling the app; observers and subscriptions keep running when their handles are garbage-collected; `DittoDiff` reports every shifted row as a move ([In Kotlin, an observer whose handler throws is closed, and the exception is only logged](#in-kotlin-an-observer-whose-handler-throws-is-closed-and-the-exception-is-only-logged), [In Kotlin, garbage-collected subscriptions and observers keep running](#in-kotlin-garbage-collected-subscriptions-and-observers-keep-running), [In Kotlin, DittoDiff reports every shifted row as a move](#in-kotlin-dittodiff-reports-every-shifted-row-as-a-move)).
- A query result is closed when its `execute` handler returns and when Ditto closes; `item.value` is a new, read-only `Dictionary` on each read; a missing key reads as `NullValue`; and a decimal that a 32-bit float holds exactly comes back as a `FloatValue`, which `doubleOrNull` does not read ([In Kotlin, query results are closed when the execute handler returns, and by close()](#in-kotlin-query-results-are-closed-when-the-execute-handler-returns-and-by-close), [In Kotlin, item.value returns a new read-only Dictionary on each read](#in-kotlin-itemvalue-returns-a-new-read-only-dictionary-on-each-read), [In Kotlin, a missing key reads as NullValue, and a typed accessor on it throws](#in-kotlin-a-missing-key-reads-as-nullvalue-and-a-typed-accessor-on-it-throws), [In Kotlin, a decimal that a 32-bit float holds exactly comes back as a FloatValue](#in-kotlin-a-decimal-that-a-32-bit-float-holds-exactly-comes-back-as-a-floatvalue)).
- `Date`, `Instant`, `UUID`, `BigDecimal`, and `BigInteger` cannot be passed as arguments, NaN and infinity fail the write, and on 5.1.0 negative integers in map arguments were stored as one less ([Kotlin values that are not plain JSON fail or change when stored](#kotlin-values-that-are-not-plain-json-fail-or-change-when-stored), [On Kotlin SDK 5.1.0, negative integers in map arguments were stored as one less](#on-kotlin-sdk-510-negative-integers-in-map-arguments-were-stored-as-one-less)).
- Invalid DQL, an oversized document, and an invalid configuration or encryption key are reported by the call that receives them, as typed `DittoException`s ([In Kotlin, invalid DQL is reported by the call that receives it](#in-kotlin-invalid-dql-is-reported-by-the-call-that-receives-it), [In Kotlin, an oversized document fails with an UnknownException](#in-kotlin-an-oversized-document-fails-with-an-unknownexception), [In Kotlin, an invalid configuration or a wrong encryption key makes create() throw](#in-kotlin-an-invalid-configuration-or-a-wrong-encryption-key-makes-create-throw)); a subscription without arguments has `null` `queryArguments` ([In Kotlin, a subscription without arguments has null queryArguments](#in-kotlin-a-subscription-without-arguments-has-null-queryarguments)).
- On 5.1.0, on a device connected to a peer in another process, a read of `system:data_sync_info` sometimes stopped responding, and so did later reads of it and `close()`; `withTimeoutOrNull` around the read did not return, while a helper that awaits the read from a scope of its own returned at its deadline; on 5.2.0, no read got stuck ([On Kotlin SDK 5.1.0, a read of system:data_sync_info could stop responding](#on-kotlin-sdk-510-a-read-of-systemdata_sync_info-could-stop-responding)).
- `store.execute` blocks the thread of the coroutine that calls it, also while it waits for a write transaction, so many writes behind a transaction can take every thread of `Dispatchers.IO` ([In Kotlin, store.execute blocks the thread of its caller](#in-kotlin-storeexecute-blocks-the-thread-of-its-caller), [In Kotlin, writes that wait behind a transaction each hold a thread](#in-kotlin-writes-that-wait-behind-a-transaction-each-hold-a-thread)).
- Opening an open directory fails after about a second; `deleteStore` fails while the store is open; `close()` waits for an open transaction, writes in flight are stored even when their call throws, and later calls throw, except `sync.start()` ([In Kotlin, opening an open directory again fails after about a second](#in-kotlin-opening-an-open-directory-again-fails-after-about-a-second), [In Kotlin, deleteStore fails while the store is open](#in-kotlin-deletestore-fails-while-the-store-is-open), [In Kotlin, close() waits for an open transaction](#in-kotlin-close-waits-for-an-open-transaction), [In Kotlin, writes in flight when close() runs are stored even when the call throws](#in-kotlin-writes-in-flight-when-close-runs-are-stored-even-when-the-call-throws), [In Kotlin, calls after close() throw, except sync.start()](#in-kotlin-calls-after-close-throw-except-syncstart)).
- A write through `store.execute` inside a transaction, and a read-write transaction inside another, deadlock; otherwise transactions commit, roll back, and rethrow as documented ([In Kotlin, store.execute writes inside a transaction deadlock](#in-kotlin-storeexecute-writes-inside-a-transaction-deadlock), [In Kotlin, a read-write transaction inside a read-write transaction deadlocks](#in-kotlin-a-read-write-transaction-inside-a-read-write-transaction-deadlocks), [In Kotlin, transactions commit, roll back, and rethrow as documented](#in-kotlin-transactions-commit-roll-back-and-rethrow-as-documented)).
- `login()` throws when it fails, and an expiration handler that throws is only logged ([In Kotlin, login() throws, and a throwing expiration handler is only logged](#in-kotlin-login-throws-and-a-throwing-expiration-handler-is-only-logged)).
- An empty `DittoTransportConfig` turns every transport off; a connection request handler that denies keeps the peer out; `fetchAttachment` waits without progress while no peer delivers the blob ([In Kotlin, an empty DittoTransportConfig turns every transport off](#in-kotlin-an-empty-dittotransportconfig-turns-every-transport-off), [In Kotlin, a connection request handler that denies keeps the peer out](#in-kotlin-a-connection-request-handler-that-denies-keeps-the-peer-out), [In Kotlin, fetchAttachment waits without progress while no peer delivers the blob](#in-kotlin-fetchattachment-waits-without-progress-while-no-peer-delivers-the-blob)).
- `DittoLogger` works before the first instance and writes to logcat; `Instant.toString()` varies its precision ([In Kotlin, DittoLogger works before the first create, and logs go to logcat](#in-kotlin-dittologger-works-before-the-first-create-and-logs-go-to-logcat), [In Kotlin, Instant.toString() varies its precision](#in-kotlin-instanttostring-varies-its-precision)).

## Kotlin Observer Behavior

### In Kotlin, observer handlers run one at a time, and intermediate results are skipped

| | |
|---|---|
| Observed on | SDK 5.2.0, three runs; SDK 5.1.0, one run; every run gave the same result, and the results were the same on both releases |
| Setup | A document `{_id: 'c', n: 0}`. For each of the observer APIs, an observer of `SELECT n FROM counters WHERE _id = 'c'` whose handler recorded `n` and then suspended for 500 ms (`delay(500)`); 300 ms after registration, 10 `UPDATE` statements set `n` to 1 to 10, 50 ms apart. The APIs: `registerObserver` with a suspend handler, `registerObserver` with a handler that also takes a `DittoDiff`, `store.collect` (launched on `Dispatchers.Default` and cancelled afterwards), and `store.observe` (a `Flow` whose transform returned `n`, collected by a collector that suspended for 500 ms) |
| Documentation | The Kotlin V4→V5 migration guide says that `registerObserver()` and `collect()` deliver the next event only after the suspend handler returns, and that changes in the meantime are coalesced. It says that `observe()` has no natural backpressure: the `Flow` asks for the next event as soon as `emit` succeeds, and a slow collector should add `.conflate()` or `.buffer(Channel.RENDEZVOUS)` |

- With `registerObserver` (both forms) and `store.collect`, the handler was called 3 times: for the initial result (`n` = 0), once while the writes were running (`n` = 3 or 4), and for the final value 10. No two calls overlapped. The last call ended 1.22 to 1.30 seconds after the first write.
- With `store.observe` and a slow collector, the collector received 4 values (0, 1, 4, 10), one at a time, and the transform ran 4 times; the last value arrived 1.72 to 1.77 seconds after the first write. The flow ran one result ahead of the collector, as the guide describes.
- With every API, the final value 10 arrived; no intermediate value after the first one was guaranteed.
- After `observer.close()`, or after the coroutine that ran `collect` or collected the `Flow` was cancelled, `ditto.store.observers` was empty.

**Not tested:** `observe` with `.conflate()` or `.buffer(...)`; handlers that throw `CancellationException`.

**Used in:** [Backpressure in Kotlin](../../best-practices/platforms/kotlin.md#backpressure-in-kotlin).

### In Kotlin, observer handlers run on the main thread unless DittoFactory.create gets another scope

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | As in [In Kotlin, observer handlers run one at a time, and intermediate results are skipped](#in-kotlin-observer-handlers-run-one-at-a-time-and-intermediate-results-are-skipped), with `registerObserver` only, on an instance created with `DittoFactory.create(config)` and on one created with `DittoFactory.create(config, CoroutineScope(Dispatchers.IO + SupervisorJob()))`. Each handler either suspended (`delay(500)`) or blocked its thread (`Thread.sleep(500)`), and recorded the name of its thread. The test itself ran on the instrumentation thread, not on the main thread. We also read the SDK's bytecode for the default scope, and recorded the thread of the expiration handler (see [In Kotlin, login() throws, and a throwing expiration handler is only logged](#in-kotlin-login-throws-and-a-throwing-expiration-handler-is-only-logged)) |

- With the default scope, every handler ran on the thread named `main`, also when it was registered from another thread and when it blocked that thread for 500 ms. In the SDK 5.2.0 bytecode, the default scope of `DittoFactory.create` on Android is `MainScope()` with a coroutine name added. The expiration handler also ran on `main`.
- With the `Dispatchers.IO` scope, the handlers ran on a `DefaultDispatcher-worker` thread. With a `Dispatchers.Default` scope (one run on 5.2.0), the handler ran on a `DefaultDispatcher-worker` thread too.
- With both scopes and both kinds of handler, there were 3 calls, never two at a time, and the final value arrived.
- A handler that blocks, or does heavy work without switching dispatchers, therefore runs on the UI thread of an app that uses the default scope.

**Not tested:** what the handler of `store.collect` runs on when its caller uses another dispatcher (in the previous entry, `collect` launched on `Dispatchers.Default` still called its handler on `main`); a scope with `Dispatchers.Main.immediate`.

**Used in:** [Opening Ditto in Kotlin](../../best-practices/platforms/kotlin.md#opening-ditto-in-kotlin), [Store Observers in Kotlin](../../best-practices/platforms/kotlin.md#store-observers-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, each collection of an observe() Flow is its own observer

| | |
|---|---|
| Observed on | SDK 5.2.0, one run; the shared variant, one run on 5.2.0 |
| Setup | One `Flow` from `ditto.store.observe(...)`, collected by two coroutines at the same time; then a `Flow` shared with `shareIn(scope, SharingStarted.WhileSubscribed(5_000), replay = 1)` and collected by two coroutines. We read `ditto.store.observers` 500 ms after the collections started |

- Two collections of the same cold `Flow` registered two observers: `ditto.store.observers` listed 2.
- Two collectors of the shared `Flow` used one observer: `ditto.store.observers` listed 1.
- Cancelling a collection removed its observer (see also [In Kotlin, observer handlers run one at a time, and intermediate results are skipped](#in-kotlin-observer-handlers-run-one-at-a-time-and-intermediate-results-are-skipped)).

**Used in:** [Observer lifecycle in Kotlin](../../best-practices/platforms/kotlin.md#observer-lifecycle-in-kotlin).

### In Kotlin, an observer whose handler throws is closed, and the exception is only logged

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | An observer whose `registerObserver` handler threw `IllegalStateException` on every call, followed by three writes 300 ms apart. One run installed a default uncaught-exception handler that recorded what reached it; another run left the default handler in place. We also threw in the transform of `store.observe` (collected with `first()`) and in the handler of `store.collect` |

- The handler was called once, for the initial result. After the exception, the observer was closed (`isClosed` was `true`), it was no longer listed in `ditto.store.observers`, and the three writes did not call it again.
- The exception did not reach the default uncaught-exception handler, and the process did not end. The SDK logged it at the error level: `DittoStore: Unhandled exception in observer event handler. Error: java.lang.IllegalStateException: ...`.
- An exception in the transform of `store.observe`, or in the handler of `store.collect`, was rethrown to the code that collected the flow or called `collect`, and the observer was gone from `ditto.store.observers` afterwards.

**Not tested:** `CancellationException` thrown by a handler; exceptions from a handler that switched dispatchers with `withContext`.

**Used in:** [Observer Lifecycle](../../best-practices/observers.md#observer-lifecycle), [Observer lifecycle in Kotlin](../../best-practices/platforms/kotlin.md#observer-lifecycle-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, garbage-collected subscriptions and observers keep running

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | Two devices, A and B. B registered a subscription to `SELECT * FROM cars` and a `registerObserver` observer of the same query in a function that kept only `WeakReference`s to them. After a document from A arrived, B called `System.gc()` and `System.runFinalization()` five times, 200 ms apart, and A wrote another document. Then we closed every object listed in B's `ditto.store.observers` and `ditto.sync.subscriptions`, and A wrote a third document |

- Both `WeakReference`s were empty after the garbage collection, but `ditto.store.observers` and `ditto.sync.subscriptions` each still listed one entry. The document written after the collection arrived at B, and the observer was called for it (3 calls in all).
- Closing the listed objects stopped both: the lists were empty, the observer was not called again, and the third document did not arrive within 10 seconds.
- The listed objects are not the objects that the registration returned (see [In Kotlin, a subscription without arguments has null queryArguments](#in-kotlin-a-subscription-without-arguments-has-null-queryarguments)), but closing them stops the subscription or observer.

**Not tested:** longer periods than about 2 seconds after the collection; release builds with R8.

**Used in:** [Observer Lifecycle](../../best-practices/observers.md#observer-lifecycle), [Closing Ditto in Kotlin](../../best-practices/platforms/kotlin.md#closing-ditto-in-kotlin), [Observer lifecycle in Kotlin](../../best-practices/platforms/kotlin.md#observer-lifecycle-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, DittoDiff reports every shifted row as a move

| | |
|---|---|
| Observed on | SDK 5.2.0, two runs (one with `registerObserver`, one with `observe` in a model class) |
| Setup | Three documents ordered by a field, observed with a handler that takes a `DittoDiff`. We moved the last row to the top by changing its field, then deleted one row |

- The first result reported every row as an insertion (`insertions = [0, 1, 2]`).
- Moving the last row to the top reported `updates = [0]` and three moves, `2→0`, `0→1`, and `1→2`: every row whose position shifted is a move, not only the one that was moved. In the second run, moving the first row to the bottom likewise reported a move for each of the three rows, and an update at the moved row's new index.
- Deleting the second row reported `deletions = [1]` and no moves.

**Used in:** [Diffing results in Kotlin](../../best-practices/platforms/kotlin.md#diffing-results-in-kotlin).

## Kotlin Query Results and Values

### In Kotlin, query results are closed when the execute handler returns, and by close()

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | Three documents. We returned the `DittoQueryResult` itself from the handler of `store.execute(query) { result -> result }` and read it afterwards. With `executeRaw`, we read an item's value, then called `result.close()` and read an item that had not been read; then we ran `executeRaw` again, read one value, called `ditto.close()`, and read the other items. We also returned `result.items` from the transform of `store.observe` and read them in the collector (5.2.0, one run) |
| Documentation | The Kotlin V4→V5 migration guide warns that a `DittoQueryResult` and its items are native resources that close when the handler or transform returns, and that a handler must return plain Kotlin data. `store.execute` without a handler returns `Unit`; `executeRaw` returns a result that the caller closes |

- A result returned out of the `execute` handler still reported 3 items, but reading an item's value threw `IllegalStateException: Query result item has already been closed.` Items returned from the transform of `store.observe` threw the same exception in the collector.
- After `result.close()` of an `executeRaw` result, the same exception came from the value and from `jsonString()` of an item that had not been read.
- `ditto.close()` closed results that the app had not closed: reading the value or `jsonString()` of their items afterwards threw the same exception. A `DittoCborSerializable.Dictionary` that had been read before `close()` could still be read.

**Not tested:** `materialize()` before `close()`.

**Used in:** [Query results in Kotlin](../../best-practices/platforms/kotlin.md#query-results-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, item.value returns a new read-only Dictionary on each read

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | One item of an `executeRaw` result, read twice through `item.value`, then cast to `MutableMap` to change a field, then dematerialized with `item.dematerialize()` and read again |

- `item.value` returned a `DittoCborSerializable.Dictionary`. Two reads returned equal objects that were not the same object (`==` was `true`, `===` was `false`).
- `item.isMaterialized` was `false` before the first read and `true` after it. After `dematerialize()`, it was `false`, and the next read returned the same values.
- The `Dictionary` is a read-only `Map`: the cast to `MutableMap` failed with `ClassCastException`, and the item, its `jsonString()`, and the stored document kept their values.

**Used in:** [Query results in Kotlin](../../best-practices/platforms/kotlin.md#query-results-in-kotlin).

### In Kotlin, a missing key reads as NullValue, and a typed accessor on it throws

| | |
|---|---|
| Observed on | SDK 5.2.0, one run |
| Setup | A document `{_id: 'r1', n: null}`, read with `SELECT *`; we read `value["absent"]` and `value["n"]` with the base accessor, `stringOrNull`, and `string`, and called `containsKey` with both keys |

- `value["absent"]` returned a `NullValue` whose `isNull` was `true`, the same as `value["n"]`. `stringOrNull` returned `null`.
- `containsKey("absent".toDittoCbor())` was `false`, and `containsKey("n".toDittoCbor())` was `true`: only `containsKey` tells a missing key from a `null` value.
- `value["absent"].string` threw `DittoException.FatalException: Fatal error: Could not deserialize String from NullValue`, a `FatalException` rather than a type error.

**Used in:** [Query results in Kotlin](../../best-practices/platforms/kotlin.md#query-results-in-kotlin).

### In Kotlin, a decimal that a 32-bit float holds exactly comes back as a FloatValue

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each of the ten values, and one more run on 5.2.0 of eight values including DQL literals; the results were the same on both releases |
| Setup | Kotlin `Double` values written through a `Map` argument (`0.1`, `7.5`, `7.0`, `100.25`, `1.23456789012345`, `1e300`, `3.4e38`, `16777217.0`, `-0.5`, `1.0 / 3`), a `Float` `2.0f`, `Int` and `Long` `7`, and the DQL literals `7.0`, `1.5`, and `7`; read back with `doubleOrNull`, `double`, `floatOrNull`, `longOrNull`, and with a helper that tries `doubleOrNull`, then `floatOrNull`, then `longOrNull` |

- The DQL type of every decimal was `float`. Values that a 32-bit float holds exactly (`7.5`, `7.0`, `100.25`, `-0.5`, `2.0f`, and the literals `7.0` and `1.5`) came back as a `FloatValue`; the others (`0.1`, `1.23456789012345`, `1e300`, `3.4e38`, `16777217.0`, `1.0 / 3`) as a `DoubleValue`.
- For a `FloatValue`, `doubleOrNull` returned `null`, and `double` threw `DittoException.FatalException: Fatal error: Could not deserialize Double from FloatValue(value=7.5)`. `floatOrNull` returned the value. For a `DoubleValue`, `floatOrNull` returned `null`.
- Integers came back as `UnsignedInteger`, for which `doubleOrNull` returned `null` and `longOrNull` the value.
- The helper read all ten `Double` values back exactly. `jsonString()` showed every value as written.

**Not tested:** values that synced from another SDK.

**Used in:** [Query results in Kotlin](../../best-practices/platforms/kotlin.md#query-results-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### Kotlin values that are not plain JSON fail or change when stored

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; apart from the negative integers (see [On Kotlin SDK 5.1.0, negative integers in map arguments were stored as one less](#on-kotlin-sdk-510-negative-integers-in-map-arguments-were-stored-as-one-less)), the results were the same on both releases |
| Setup | Each value was written as field `v` of its own document through a `Map` argument (`INSERT INTO types DOCUMENTS (:doc)`), and read back with `SELECT type(v) AS t, v, char_length(v) AS chars`: the DQL type, the `DittoCborSerializable` class that Kotlin returned, and `jsonString()`. A field set to `null` in the map was also matched with `IS MISSING` (5.2.0, one run) |
| Documentation | The Kotlin V4→V5 migration guide lists `Map<String, Any?>`, `@Serializable` types, and `DittoCborSerializable.Dictionary` as arguments |

| Kotlin value | Result |
|---|---|
| `Int`, `Long`, `Short`, `Byte` | `integer`; `Long.MAX_VALUE` and `9007199254740993` (above 2^53) round-trip exactly. Non-negative values come back as `UnsignedInteger`, negative ones as `NegativeInteger` |
| `Double`, `Float` | `float` (see [In Kotlin, a decimal that a 32-bit float holds exactly comes back as a FloatValue](#in-kotlin-a-decimal-that-a-32-bit-float-holds-exactly-comes-back-as-a-floatvalue)) |
| `Double.NaN`, `Double.POSITIVE_INFINITY` | The write fails: `StoreException: The provided query arguments were invalid.` |
| `null` | `null` (`NullValue`); the field exists, so `IS MISSING` does not match it |
| `true` | `boolean` |
| `ByteArray` | `binary` (`ByteString`) |
| `Map`, empty `Map`, `List`, `Set` | `object` and `array`; a `Set` becomes an array |
| `Char`, `enum` constant | `string`: `'x'` as `"x"`, `Color.RED` as `"RED"` |
| `java.util.Date`, `java.time.Instant`, `java.util.UUID`, `BigDecimal`, `BigInteger` | The write fails before it reaches the store: `IllegalArgumentException: Cannot convert ... of type java.util.Date to cbor` (and the same for the others) |
| A string with a lone surrogate (`"a\uD800b"`) | Stored as `"a?b"` (`U+003F` in place of the surrogate), `char_length` 3 |

**Not tested:** `@Serializable` arguments (the test project has no serialization plugin); `ULong` and `UInt`; `Float.NaN`.

**Used in:** [Arguments and value types in Kotlin](../../best-practices/platforms/kotlin.md#arguments-and-value-types-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### On Kotlin SDK 5.1.0, negative integers in map arguments were stored as one less

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each |
| Setup | As in [Kotlin values that are not plain JSON fail or change when stored](#kotlin-values-that-are-not-plain-json-fail-or-change-when-stored), with `-5` as `Int`, as `Long`, inside a nested map, as `(-5).toDittoCbor()` inside the `Map` argument, `listOf(-5, -1, 0, 1)`, `Int.MIN_VALUE`, and `Long.MIN_VALUE`, and then `SELECT _id FROM types WHERE v = -5` |
| Documentation | The Kotlin 5.2.0 release notes: before 5.2, a negative integer passed as a DQL query argument through the map-based overloads was stored and compared as one less than the value passed (`-5` as `-6`), the Kotlin SDK's value accessors had the matching error, and values such as `Int.MIN_VALUE` failed to serialize. Upgrading does not correct stored data |

- On 5.1.0, `-5` was stored as `-6` in every form, also inside a nested map and as a `DittoCborSerializable` value inside the map, and the list was stored as `[-6, -2, 0, 1]`. `jsonString()` showed `-6`, but `item.value["v"]` returned `-5`: the Kotlin SDK's own reads compensated. `WHERE v = -5` matched no document. `Int.MIN_VALUE` and `Long.MIN_VALUE` failed with `StoreException: The provided query arguments were invalid.`
- On 5.2.0, every value was stored as passed, `WHERE v = -5` matched the three documents with `-5`, and `Int.MIN_VALUE` and `Long.MIN_VALUE` round-tripped.

**Not tested:** data written on 5.1.0 and read on 5.2.0; negative arguments in `WHERE` clauses on 5.1.0.

**Used in:** [Arguments and value types in Kotlin](../../best-practices/platforms/kotlin.md#arguments-and-value-types-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, a subscription without arguments has null queryArguments

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | Subscriptions to `SELECT * FROM cars` (twice) and to `SELECT * FROM cars WHERE color = :color` with `color` = `blue`, and two observers likewise; we read their `queryArguments` and `queryArgumentsJsonString`, and `ditto.sync.subscriptions` and `ditto.store.observers`, before and after closing them |

- Without arguments, `queryArguments` and `queryArgumentsJsonString` were `null`, for subscriptions and observers. With arguments, `queryArgumentsJsonString` was `{"color":"blue"}`.
- The same query registered twice gave two subscriptions, which were not equal; `ditto.sync.subscriptions` listed 3.
- The objects in `ditto.sync.subscriptions` and `ditto.store.observers` were not the objects that the registrations returned (no listed object was `===` to them).
- After `close()`, `isClosed` was `true` and the list had one fewer; a second `close()` did nothing.

**Used in:** [Subscriptions in Kotlin](../../best-practices/platforms/kotlin.md#subscriptions-in-kotlin).

### In Kotlin, invalid DQL is reported by the call that receives it

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | `SELEC * FROM cars` passed to `store.execute`, `store.registerObserver`, `store.observe` (collected with `first()`), and `sync.registerSubscription`; a missing parameter; an argument of type `Any()`; an `INSERT` passed to an observer and a subscription; and a subscription with `ORDER BY` and `LIMIT` |

- Every invalid statement threw `DittoException.StoreException` from the call itself: `registerObserver` and `registerSubscription` at registration, and `store.observe` when the flow was collected. The parser error reads ``<dql> Invalid query: `DQL parser error: Unexpected token SELEC at line 1 column 1 near "SELEC * FROM cars"; expected a DQL statement`. For more information on Ditto's query language see: ...``.
- A missing parameter: ``<dql> Invalid query: `Parameter color was not provided`.``
- An argument that Kotlin cannot convert: `IllegalArgumentException: Cannot convert java.lang.Object@... of type kotlin.Any to cbor`.
- An `INSERT`: `<dql> Unsupported feature: non-SELECT statement in store observer` and `... in sync subscription`. `ORDER BY` and `LIMIT` in a subscription: `<dql> Unsupported feature: Limit or Order by`.
- In one `INSERT ... DOCUMENTS (:docs)` statement, two documents with the same `_id` failed with ``<dql> Invalid query: `Expected unique document identifiers. Document id "i1" is a duplicate` `` (5.2.0, one run).

**Used in:** [Executing DQL in Kotlin](../../best-practices/platforms/kotlin.md#executing-dql-in-kotlin).

### In Kotlin, an oversized document fails with an UnknownException

| | |
|---|---|
| Observed on | SDK 5.2.0, two runs (an `INSERT` and an `UPDATE`) |
| Setup | A document with a string field of 6 MiB, written with `INSERT` in one run and with `UPDATE ... SET notes = :notes` in another |

- The `INSERT` threw `DittoException.UnknownException`, not a `StoreException`: ``<dql> Query failed: `DQL Internal execution error: Insert failed: <store> Document `_id = "v1"` size is 6291633 bytes and exceeds limit of 5242880 bytes`. ...``
- The `UPDATE` threw a `DittoException` whose message also contained `exceeds limit of`; we did not record its class.

**Used in:** [Executing DQL in Kotlin](../../best-practices/platforms/kotlin.md#executing-dql-in-kotlin).

### On Kotlin SDK 5.1.0, a read of system:data_sync_info could stop responding

| | |
|---|---|
| Observed on | SDK 5.1.0, 55 runs (45 with the other peer in another process, 10 with both peers in one process); SDK 5.2.0, 41 runs (31 with the other peer in another process, 10 with both peers in one process) |
| Setup | This device, in the Android test, subscribed to `orders` and connected over TCP to one other device that also subscribed to `orders`. In one process, the other device was a second instance in the same test, of the same release, connected over the emulator's `127.0.0.1`. In another process, the other device was a JavaScript SDK peer (`@dittolive/ditto` 5.2.0 or 5.1.0 in Node.js) on the Mac that ran the emulator: it listened on the Mac's `127.0.0.1`, which the emulator reaches at `10.0.2.2`, used the same Database ID, stayed up for all the runs of a series (11 to 26 minutes), and read `system:data_sync_info` every 5 seconds. After this device saw the other in presence, it inserted a document and read `SELECT * FROM system:data_sync_info` up to 20 times, 50 ms apart. A read that had not completed after 3 seconds counted as stuck. After a stuck read, this device read `system:data_sync_info` again and read `orders`, each with a limit of 5 seconds, and then called `close()` with a limit of 5 seconds. In 35 of the runs with the JavaScript 5.2.0 peer, this device also called `waitUntilServerHas` from [Closing Ditto in Kotlin](../../best-practices/platforms/kotlin.md#closing-ditto-in-kotlin) with `timeoutMillis = 3000`, which reads every 200 ms in a scope of its own: either right after the insert, before the 20 reads (10 runs on each release), or after them (15 runs on 5.1.0). The peer is not Ditto Server, so the helper could only return `false`. After a stuck read in these runs, this device ran `withTimeoutOrNull(3000) { ditto.store.execute(...) }` with a limit of 10 seconds, and `close()` with a limit of 20 seconds |
| Documentation | The Kotlin release notes for 5.0.3 list "Corrected a hang when accessing `system:data_sync_info`" (QE-1095). The release notes for 5.1.0 and 5.2.0 do not mention `system:data_sync_info` |

The runs in which a read on this device got stuck:

| Other device, and the first reads after the insert | This device on 5.2.0 | This device on 5.1.0 |
|---|---|---|
| In the same process, same release; 20 reads | 0 of 10 | 0 of 10 |
| JavaScript 5.2.0, in another process; 20 reads | 0 of 11 | 10 of 25 |
| JavaScript 5.1.0, in another process; 20 reads | 0 of 10 | 3 of 10 |
| JavaScript 5.2.0, in another process; `waitUntilServerHas` | 0 of 10 | 1 of 10 |

- When the 20 reads came first, a stuck read was always the second; the first one completed. In the 9 runs on 5.1.0 in which the reads of `waitUntilServerHas` did not get stuck, the 20 reads after it did not either. In the 61 runs that timed each read, every read that completed took 40 ms or less.
- After a stuck read, the next read of `system:data_sync_info` on this device returned nothing within 5 seconds, while a read of `orders` completed within 10 ms, and `close()` did not return within 5 seconds (all 6 such runs). In the 8 stuck runs with the longer limits, `close()` did not return within 20 seconds.
- `waitUntilServerHas` returned `false` after 3.00 to 3.01 seconds in all 35 runs, also in the 8 runs with a stuck read. 0.5 seconds after it returned, each stuck read still held a thread inside `store.execute` (one thread when the helper's own read got stuck, two after a stuck read of the 20 reads).
- `withTimeoutOrNull(3000)` around `ditto.store.execute` did not return within 10 seconds in all 8 stuck runs: `store.execute` blocks its thread, so the timeout cannot cancel it ([In Kotlin, store.execute blocks the thread of its caller](#in-kotlin-storeexecute-blocks-the-thread-of-its-caller)).
- In the runs without a stuck read, `close()` returned in 0.04 to 0.12 seconds.
- The release of the other device made no clear difference: with this device on 5.1.0, 10 of 25 runs got stuck with the JavaScript 5.2.0 peer and 3 of 10 with 5.1.0; with this device on 5.2.0, no run did.
- The JavaScript peers completed all of their reads of `system:data_sync_info` (132 and 312 on 5.2.0, 156 on 5.1.0), including those during and after the runs in which this device got stuck.
- On 5.2.0, unlike the JavaScript and Swift SDKs on the same release, no read got stuck ([In JavaScript, a read of system:data_sync_info can stop responding](javascript-sdk.md#in-javascript-a-read-of-systemdata_sync_info-can-stop-responding), [In Swift, a read of system:data_sync_info can stop responding](swift-sdk.md#in-swift-a-read-of-systemdata_sync_info-can-stop-responding)).

**Not tested:** An observer of `system:data_sync_info`; two Android processes or two emulators; runs without the insert; whether a stuck read completes after more than 10 seconds, whether `close()` returns after more than 20 seconds, or whether the device recovers; `waitUntilServerHas` with Ditto Server, where it can return `true`; other transports, physical devices, and a device connected to Ditto Server.

**Used in:** [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Monitoring Sync Status](../../best-practices/sync-and-subscriptions.md#monitoring-sync-status), [Closing Ditto in Kotlin](../../best-practices/platforms/kotlin.md#closing-ditto-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

## Kotlin Opening, Closing, and Threads

### In Kotlin, opening an open directory again fails after about a second

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each, and one more run on 5.2.0; every run gave the same result |
| Setup | One instance opened a directory and wrote a document. In the same app, `DittoFactory.create` with the same `DittoConfig` was called again (bounded at 20 seconds). Then the first instance was closed and the directory was opened again |

- The second `DittoFactory.create` threw `DittoException.StoreException` after 1.01 to 1.04 seconds: `File already locked, working dir = ..., retried 5 times. Multiple Ditto instances cannot run at the same time within the same working directory. Either use unique working directories for each instance, or consider managing your Ditto instance as a singleton instead.`
- `close()` of the first instance took 0.04 to 0.06 seconds, and opening the directory again right after it took 0.06 to 0.09 seconds and found the document.

**Not tested:** two processes; a directory held by an instance that was not closed but is no longer referenced.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory), [One shared instance in Kotlin](../../best-practices/platforms/kotlin.md#one-shared-instance-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, an invalid configuration or a wrong encryption key makes create() throw

| | |
|---|---|
| Observed on | SDK 5.2.0, one run |
| Setup | `DittoFactory.create` with an unknown system parameter, with `DQL_STRICT_MODE` set to a string, and with `DQL_STRICT_MODE` set to `true` (then `SHOW DQL_STRICT_MODE`). A store created with a 32-byte `DittoEncryptionKey.raw(...)` was closed and opened without a key, with another key, and with its key; an unencrypted store was opened with a key; and `DittoEncryptionKey.raw` was called with 16 bytes |
| Documentation | The Kotlin 5.2.0 release notes list `DittoConfig.systemParameters`, `DittoConfig.encryptionKey` with a raw 32-byte key, and the encryption reasons `KeyRequired`, `KeyUnexpected`, `KeyInvalid`, `UnsupportedScheme`, and `MetadataCorrupt` |

- An unknown name threw `DittoException.ValidationException: The provided DittoConfig is invalid: Invalid DittoConfig: unknown parameter 'not_a_parameter'`, and a wrong type `... type error: value String("yes") doesn't match system parameter dql_strict_mode type of bool`. With `true`, `SHOW DQL_STRICT_MODE` returned `{"dql_strict_mode":true}`.
- The encrypted store opened without a key threw `DittoException.EncryptionException: no encryption key was provided while required.`, with another key `wrong encryption key provided`, and with its key it opened and returned its document. The unencrypted store opened with a key threw `an encryption key was provided while not required.`
- `DittoEncryptionKey.raw` with 16 bytes threw `IllegalArgumentException: encryption key must be exactly 32 bytes`.
- `systemParameters` takes a `Map<String, Any>`: a `Map<String, Any?>` does not match the constructor, and the Kotlin compiler then picks no overload with that name.

**Not tested:** `UnsupportedScheme` and `MetadataCorrupt`; a corrupted store.

**Used in:** [DittoConfig in Kotlin](../../best-practices/platforms/kotlin.md#dittoconfig-in-kotlin).

### In Kotlin, deleteStore fails while the store is open

| | |
|---|---|
| Observed on | SDK 5.2.0: while open, one run; after `close()`, two runs |
| Setup | A store with one document. `DittoFactory.deleteStore(databaseId, persistenceDirectory)` was called while the store was open, then after `close()`; then the directory was opened again |

- While the store was open, `deleteStore` threw `DittoException.StoreException: File already locked, ... retried 0 times.`
- After `close()`, it returned, and the directory opened again as an empty store (0 documents). The directory itself still existed.

**Used in:** [Closing Ditto in Kotlin](../../best-practices/platforms/kotlin.md#closing-ditto-in-kotlin).

### In Kotlin, store.execute blocks the thread of its caller

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each, and one run on 5.2.0 with a smaller query; every run gave the same result |
| Setup | 20,000 documents. A coroutine on a single-thread dispatcher ticked every 10 ms while `SELECT * FROM big ORDER BY text DESC` ran: once called from a coroutine on the same single thread, and once from `Dispatchers.Default`. We counted the ticks during the query |

- Called on the single thread, the query took 156 to 208 ms, and the ticker ran once during it (the longest gap between ticks was 166 to 216 ms): the thread was blocked for the whole query. In the run with a query of 43 ms, the ticker also ran once.
- Called from `Dispatchers.Default`, the query took 122 to 184 ms, and the ticker ran 12 to 18 times during it.
- `execute` is a suspending function, but it does not move the query to a thread of its own. Called from the main thread, it would block the UI for as long as the query runs.

**Not tested:** `executeRaw`, `tx.execute`, and observer queries; a call from `Dispatchers.Main`.

**Used in:** [Query execution and the UI thread](../../best-practices/indexing-and-performance.md#query-execution-and-the-ui-thread), [Executing DQL in Kotlin](../../best-practices/platforms/kotlin.md#executing-dql-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, writes that wait behind a transaction each hold a thread

| | |
|---|---|
| Observed on | SDK 5.1.0, two runs, and SDK 5.2.0, three runs, with everything on `Dispatchers.IO`; SDK 5.1.0 and 5.2.0, three runs each, with the transaction on a thread of its own; every run gave the same result |
| Setup | As in [In Kotlin, close() waits for an open transaction](#in-kotlin-close-waits-for-an-open-transaction), with 200 `store.execute` writes launched on `Dispatchers.IO` while the transaction was suspended, then `ditto.close()` on a thread of `Dispatchers.IO` (bounded at 20 seconds). In the second variant, the transaction ran on a single-thread dispatcher of its own, and we counted the launched writes that had started 300 ms after they were launched |

- With everything on `Dispatchers.IO`, `close()` had not returned after 20 seconds, the transaction had not ended after another 10 seconds, and the writes had not ended (in one 5.1.0 run, 51 had completed).
- With the transaction on its own thread, `close()` returned after 1.14 to 1.28 seconds, the transaction committed, and all 200 writes were stored (137 calls returned, 63 threw as in [In Kotlin, writes in flight when close() runs are stored even when the call throws](#in-kotlin-writes-in-flight-when-close-runs-are-stored-even-when-the-call-throws)).
- In that variant, exactly 64 of the 200 launched writes had started before `close()`, the number of threads of `Dispatchers.IO`. Each `store.execute` that waited for the write transaction kept its thread (see [In Kotlin, store.execute blocks the thread of its caller](#in-kotlin-storeexecute-blocks-the-thread-of-its-caller)), so the other coroutines could not start. With everything on `Dispatchers.IO`, the waiting writes and `close()` held every thread, and the transaction could not resume after its `delay`.

**Not tested:** fewer launched writes; `Dispatchers.Default`.

**Used in:** [Transaction Rules](../../best-practices/transactions.md#transaction-rules), [Transactions in Kotlin](../../best-practices/platforms/kotlin.md#transactions-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, close() waits for an open transaction

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | A read-write transaction, launched on `Dispatchers.IO`, inserted a document and suspended for 1 second before it returned `Commit`. 100 ms after it started, `ditto.close()` was called on another thread. Then the directory was opened again |

- `close()` returned after 1.12 to 1.15 seconds, when the transaction had finished. The transaction committed, and its document was in the store when the directory was opened again.

**Not tested:** a transaction that suspends for longer than a few seconds.

**Used in:** [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Closing Ditto in Kotlin](../../best-practices/platforms/kotlin.md#closing-ditto-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, writes in flight when close() runs are stored even when the call throws

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | 200 coroutines launched on `Dispatchers.IO`, each running one `store.execute` with an `INSERT`, not awaited; then `ditto.close()` at once. Then the directory was opened again |

- `close()` returned after 0.35 to 0.39 seconds.
- 137 of the 200 calls returned normally, and 63 threw `DittoException.FatalException: Fatal error: Couldn't create child of a closed resource ...`, in every run.
- All 200 documents were in the store when the directory was opened again, including those whose call had thrown. An exception from a write during `close()` does not mean that the write was not applied.

**Used in:** [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Closing Ditto in Kotlin](../../best-practices/platforms/kotlin.md#closing-ditto-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, calls after close() throw, except sync.start()

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | An instance with an observer and a subscription was closed with `ditto.close()`; then each call was made, bounded at 5 seconds |

- The observer and the subscription were closed (`isClosed` was `true`).
- `store.execute` (read or write) and `store.transaction` threw `DittoException.FatalException: Fatal error: Resource ... is not active, cannot proceed! Current state is Closed`.
- `store.registerObserver`, `sync.registerSubscription`, and reading `sync.subscriptions` threw `IllegalStateException: CDitto was already closed.` Reading `store.observers` returned an empty set.
- `sync.start()` and `sync.stop()` returned without an error, and a second `close()` did nothing. Every call returned at once.

**Used in:** [Sync and the App Lifecycle in Kotlin](../../best-practices/platforms/kotlin.md#sync-and-the-app-lifecycle-in-kotlin), [Closing Ditto in Kotlin](../../best-practices/platforms/kotlin.md#closing-ditto-in-kotlin).

## Kotlin Transaction Behavior

### In Kotlin, store.execute writes inside a transaction deadlock

| | |
|---|---|
| Observed on | The write: SDK 5.2.0, three runs, and SDK 5.1.0, one run. The read: SDK 5.1.0 and 5.2.0, one run each. Every run gave the same result |
| Setup | Inside a read-write `ditto.store.transaction`, after `tx.execute` had inserted a document, we called `ditto.store.execute` with a `SELECT` (one case) or with an `INSERT` (another case). A transaction that had not returned after 10 seconds counted as deadlocked. The test then queried the store and ended, which closes the instance |

- A `SELECT` through `ditto.store.execute` returned at once (0.19 to 0.25 seconds for the whole transaction), but it did not see the transaction's own insert, and the transaction committed.
- An `INSERT` through `ditto.store.execute` never returned, and neither did the transaction: after 10 seconds, nothing had been thrown. A `SELECT` from outside afterwards returned no documents: the transaction's insert was not committed.
- `ditto.close()` afterwards did not return either; the lab ended the test at its time limit (30, 45, or 180 seconds). In the 5.2.0 run that lasted 180 seconds, the SDK logged `Transaction <id> (hint: n/a) has been running for 20s` at the info level, from 35 seconds at the warning level and from 60 seconds at the error level, every 5 seconds, together with `Waiting for write transaction ... blocked_by=User`.

**Used in:** [Transaction Rules](../../best-practices/transactions.md#transaction-rules), [Transactions in Kotlin](../../best-practices/platforms/kotlin.md#transactions-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, a read-write transaction inside a read-write transaction deadlocks

| | |
|---|---|
| Observed on | The read-write transaction inside a read-write one: SDK 5.2.0, three runs, and SDK 5.1.0, one run. The other cases: SDK 5.1.0 and 5.2.0, one run each. Every run gave the same result, and the results were the same on both releases |
| Setup | Inside a read-write transaction that had inserted a document, we started another read-write transaction (one case), or a read-only transaction (another case). We also started a read-write transaction inside a read-only one, and wrote through `tx.execute` in a read-only transaction. Each was bounded at 10 seconds |

- A read-write transaction inside a read-write transaction never started: after 10 seconds, neither transaction had returned, the outer insert was not committed, and the later `close()` did not return.
- A read-only transaction inside a read-write one returned in 0.01 seconds and did not see the outer transaction's insert. A read-write transaction inside a read-only one also returned in 0.01 seconds and committed.
- `tx.execute` with an `INSERT` in a read-only transaction threw `DittoException.StoreException: <store> A mutating DQL query was attempted using a read-only transaction.`

**Used in:** [Transaction Rules](../../best-practices/transactions.md#transaction-rules), [Transactions in Kotlin](../../best-practices/platforms/kotlin.md#transactions-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, transactions commit, roll back, and rethrow as documented

| | |
|---|---|
| Observed on | SDK 5.2.0, one run; the page's transaction examples, one more run on 5.2.0 |
| Setup | A document `{_id: 'a', n: 0}`. Transactions that set `n` and then threw, that set `n` and caught the failure of an invalid statement before returning `Commit`, and that set `n` and returned `Rollback`; a `DittoTransaction` kept and used after its block had returned; and `tx.info` of a transaction without a hint |
| Documentation | The Kotlin V4→V5 migration guide: the block returns `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback` |

- A block that threw rolled back (`n` stayed 0), and `transaction` rethrew the exception.
- A block that caught a failed statement and returned `Commit` committed its other changes (`n` became 2).
- `Rollback` rolled back (`n` stayed 2), and `transaction` returned `Rollback`. `Commit(value)` returned a `Commit` whose `value` was the block's value.
- Using the kept `DittoTransaction` threw `IllegalStateException: dittoffi_transaction was already closed.`
- Without a hint, `tx.info.hint` was an empty string and `tx.info.hintOrNull` was `null`.

**Used in:** [Transactions in Kotlin](../../best-practices/platforms/kotlin.md#transactions-in-kotlin).

## Kotlin Authentication, Transports, Attachments, and Logging

### In Kotlin, login() throws, and a throwing expiration handler is only logged

| | |
|---|---|
| Observed on | SDK 5.2.0, one run; the page's authentication examples, one more run on 5.2.0 |
| Setup | Instances with `DittoConfig.Connect.Server("http://127.0.0.1:9")`, a closed port inside the emulator. We called `sync.start()` without an expiration handler; set a handler that called `login` with a custom provider name and recorded the result; called `login` with `DittoAuthenticationProvider.development()`; called `logout` with a cleanup function; and set a handler that threw `IllegalStateException` |
| Documentation | The Kotlin install guide: `ditto.auth` is `null` with `Connect.SmallPeersOnly`, and the handler is a suspending lambda. The 5.2.0 release notes: `login()` failures expose `AuthenticationException.failureCode` |

- `ditto.auth` was not `null` in server mode; its status had `isAuthenticated = false` and `userId = null`.
- `sync.start()` without a handler threw `DittoException.AuthenticationException: <authentication> The operation failed because an authentication expiration handler has not yet been set.`
- With a handler, `sync.start()` returned, and the handler was called once, with `timeUntilExpiration` 0.0, on the thread named `main`. `login` threw `DittoException.AuthenticationException: Could not connect to authentication server` with `failureCode` `RetryableOrUnknown` after 5 ms; with the development provider, it threw the same.
- `logout` called the cleanup function, and `sync.isActive` was `false` afterwards; an `EVICT` statement still worked.
- A handler that threw was called once; the SDK logged `InternalDittoAuthenticator: Error in expirationHandler: thrown by the expiration handler. Error: java.lang.IllegalStateException: ...` at the error level, sync stayed active, the process did not end, and nothing reached the app's code.

**Not tested:** a reachable server that rejects the token; the `failureCode` of a rejection; when the handler is called again after a failed login.

**Used in:** [Authentication in Kotlin](../../best-practices/platforms/kotlin.md#authentication-in-kotlin), [Behavior Specific to the Kotlin SDK](../../best-practices/platforms/kotlin.md#behavior-specific-to-the-kotlin-sdk).

### In Kotlin, an empty DittoTransportConfig turns every transport off

| | |
|---|---|
| Observed on | SDK 5.2.0, two runs; the transports of a new instance and of `DittoTransportConfig()`, and the update that disabled Bluetooth LE, again on SDK 5.1.0 and 5.2.0, three runs each, with the same result (see [A new instance enables the platform's peer-to-peer transports, and an empty configuration enables none](connections-and-presence.md#a-new-instance-enables-the-platforms-peer-to-peer-transports-and-an-empty-configuration-enables-none)) |
| Setup | We read `ditto.transportConfig` of a new instance and of `DittoTransportConfig()`, and changed a configuration with `updateTransportConfig` |

- A new instance had Bluetooth LE, LAN, and Wi-Fi Aware enabled, no TCP listener, and no TCP servers.
- `DittoTransportConfig()` had every transport disabled, also Bluetooth LE, LAN, and Wi-Fi Aware.
- `updateTransportConfig` started from the current configuration: after setting only `peerToPeer.bluetoothLe.enabled = false`, LAN and Wi-Fi Aware stayed enabled.

**Used in:** [Transports and Presence in Kotlin](../../best-practices/platforms/kotlin.md#transports-and-presence-in-kotlin).

### In Kotlin, a connection request handler that denies keeps the peer out

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | Two small peers over TCP. The listening peer set a connection request handler that recorded each request and returned `Deny`; the other peer set its peer metadata to `{"role": "cashier"}` and subscribed to a collection in which the listening peer had a document. After 6 seconds, the handler was replaced by one that returned `Allow` |

- The handler was called twice in 6 seconds, with `connectionType` `AccessPoint`, `identityServiceMetadataJsonString` `{}`, and `peerMetadataJsonString` `{"role":"cashier"}`. The document did not arrive, and the listening peer's `presence.graph.remotePeers` was empty.
- After the handler allowed the connection, the document arrived. The remote peer had `deviceName` `sdk_gphone64_arm64` (the default name on the emulator), `os` `Android`, `dittoSdkVersion` `5.2.0` (or `5.1.0`), `isConnectedToDittoServer` `false`, the peer metadata, and one direct `AccessPoint` connection.

**Used in:** [Transports and Presence in Kotlin](../../best-practices/platforms/kotlin.md#transports-and-presence-in-kotlin).

### In Kotlin, fetchAttachment waits without progress while no peer delivers the blob

| | |
|---|---|
| Observed on | SDK 5.2.0, one run; the stalled fetch with the page's loader, one more run on 5.2.0 |
| Setup | (1) A token from another store in the same app that was not connected, fetched with `fetchAttachment`. (2) Two peers connected through a relay; a document with a 200 kB attachment synced, then the relay stalled the link, and the receiving peer fetched the attachment (bounded at 4 seconds); after the relay was restored, it fetched it again. (3) Local attachments created from a file and from bytes, fetched on the same device |

- The token of the other store failed at once with `DittoException.StoreException: Attachment not found.`
- Over the stalled link, `fetchAttachment` did not return within 4 seconds and reported no progress. After the relay was restored, a new fetch completed with all 200,000 bytes, also without progress events.
- Local attachments completed at once, without progress events.

**Not tested:** progress events for larger attachments; how long a fetch waits before it gives up, if it ever does.

**Used in:** [Attachments in Kotlin](../../best-practices/platforms/kotlin.md#attachments-in-kotlin).

### In Kotlin, DittoLogger works before the first create, and logs go to logcat

| | |
|---|---|
| Observed on | SDK 5.2.0, one run; the logcat lines, every Kotlin run of this page on 5.1.0 and 5.2.0 |
| Setup | Before any `Ditto` instance existed in the process, we set `DittoLogger.minimumLogLevel` and read `DittoLogger.isEnabled`. Later, we exported the logs twice to the same file with `DittoLogger.exportToFile(path)`, created a support bundle with `EXECUTE FUNCTION system_request_support_bundle()` and fetched it, and read the app's logcat |

- Setting and reading `DittoLogger` before the first instance worked (`Debug`, `true`).
- The first `exportToFile` returned the number of bytes written; the second, to the same path, threw `DittoException.IoException: File exists (os error 17)`.
- The support bundle was created and fetched like an attachment and copied to a file (28 to 32 kB).
- The SDK wrote its log to logcat with the tag `Ditto`, at the levels `I`, `W`, and `E`.

**Used in:** [Logging in Kotlin](../../best-practices/platforms/kotlin.md#logging-in-kotlin).

### In Kotlin, Instant.toString() varies its precision

| | |
|---|---|
| Observed on | On the Android 16 emulator, one run |
| Setup | `Instant.ofEpochMilli(...)` for a whole second, for `.100` and `.123` seconds, and `Instant.now()`, each turned into a string with `toString()`; and the same instants formatted with `DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)` |
| Documentation | Java's `DateTimeFormatter.ISO_INSTANT`, which `Instant.toString()` uses, writes the fraction in as many groups of three digits as needed |

- `toString()` returned `2025-10-09T08:53:20Z`, `2025-10-09T08:53:20.100Z`, and `2025-10-09T08:53:20.123Z`, and `Instant.now()` had six fraction digits (`2026-11-06T13:26:14.419349Z`). Strings of different lengths do not sort chronologically as text.
- The formatter returned `2025-10-09T08:53:20.000Z`, `...20.100Z`, and `...20.123Z`.
- A `LocalDateTime.now().toString()` value (`2026-11-06T22:43:35.879370`, without a zone) was stored, and `date_cast()` of it returned no value.

**Used in:** [IDs and Timestamps in Kotlin](../../best-practices/platforms/kotlin.md#ids-and-timestamps-in-kotlin).
