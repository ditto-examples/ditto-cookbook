# Flutter SDK Behavior

How the Flutter SDK, `ditto_live`, behaves where its API works differently from the other SDKs: how its observers deliver results to slow callbacks and to streams that nobody consumes, how it reports exceptions, invalid DQL, and calls after `close()`, how it converts Dart values, how transactions use Dart zones, and what `close()` does to pending work. Every entry ran with `ditto_live` 5.2.0 and 5.1.0 on macOS 26.7.2 (Apple silicon), with Flutter 3.47.8 and Dart 3.13.7, as integration tests of a macOS desktop app that runs without the App Sandbox; entries that say so also ran on an iOS 26.5 simulator. Each store used a new persistence directory with the peer-to-peer transports disabled, and stores that synced connected over TCP on `127.0.0.1` with an offline license token. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Ditto on Flutter](../../best-practices/platforms/flutter.md).

**In brief**

- A `registerObserver` callback that does slow `async` work does not hold back the next result: callbacks overlap, and `await for` over `changes` handles every queued result in turn. `registerObserverV2` with `await for`, and `registerObserverWithSignalNext`, merge intermediate results ([In Flutter, a slow async observer callback does not hold back the next result](#in-flutter-a-slow-async-observer-callback-does-not-hold-back-the-next-result)).
- An exception in an observer callback reaches the zone and the observer keeps running, but a throwing `onChange` keeps its result out of `changes`, and a throw before `signalNext()` stops the observer ([In Flutter, an exception thrown in an observer callback reaches the zone, and the observer keeps running](#in-flutter-an-exception-thrown-in-an-observer-callback-reaches-the-zone-and-the-observer-keeps-running)).
- The observer lifecycle rules of the guide held on both releases, and an observer registered with `onChange` keeps every result in its `changes` stream until something consumes it, about 100 to 130 MB for 300 results of 200 documents ([In Flutter, the observer lifecycle rules held on SDK 5.1.0 and 5.2.0](#in-flutter-the-observer-lifecycle-rules-held-on-sdk-510-and-520), [In Flutter, an observer whose changes stream nobody consumes keeps every result in memory](#in-flutter-an-observer-whose-changes-stream-nobody-consumes-keeps-every-result-in-memory)).
- Observers and subscriptions whose references the app drops keep running; a garbage-collected `SyncSubscription` keeps syncing ([In Flutter, observers and subscriptions whose references were dropped keep running](#in-flutter-observers-and-subscriptions-whose-references-were-dropped-keep-running)).
- Each read of `result.items` creates new items with new `value` maps, and results stay readable after `close()`. Some Dart values change type when stored: a `BigInt` above 2^63 comes back as a `double` or as bytes, bytes come back as a list, and a `DateTime` becomes a string ([In Flutter, each read of result.items creates new items, and results stay readable after close](#in-flutter-each-read-of-resultitems-creates-new-items-and-results-stay-readable-after-close), [In Flutter, Dart values change type between writing and reading](#in-flutter-dart-values-change-type-between-writing-and-reading)).
- Invalid DQL fails the `Future` of `execute`, but throws synchronously from `registerObserver` and `registerSubscription` ([In Flutter, invalid DQL fails the Future of execute and throws when an observer or subscription is registered](#in-flutter-invalid-dql-fails-the-future-of-execute-and-throws-when-an-observer-or-subscription-is-registered)).
- A subscription registered without arguments reports `{}` as its arguments, but reading the arguments of its element in `ditto.sync.subscriptions` ends the app, on 5.2.0 as on 5.1.0 ([In Flutter, the subscriptions and observers that registration returns report their arguments](#in-flutter-the-subscriptions-and-observers-that-registration-returns-report-their-arguments), [In Flutter, reading the arguments of a listed subscription without arguments ends the app](#in-flutter-reading-the-arguments-of-a-listed-subscription-without-arguments-ends-the-app)).
- On a device connected to a peer in another process, every read of `system:data_sync_info` completed on both releases ([In Flutter, reads of system:data_sync_info kept responding with a peer in another process](#in-flutter-reads-of-systemdata_sync_info-kept-responding-with-a-peer-in-another-process)).
- `ditto.store.execute` inside a transaction callback throws, and so does code that the callback started, such as a timer or an observer listener, after the commit. A read-write transaction started inside another waits for it ([In Flutter, store.execute inside a transaction callback throws, and outside it only writes wait](#in-flutter-storeexecute-inside-a-transaction-callback-throws-and-outside-it-only-writes-wait), [In Flutter, code started inside a transaction callback cannot call store.execute after the commit](#in-flutter-code-started-inside-a-transaction-callback-cannot-call-storeexecute-after-the-commit), [In Flutter, a read-write transaction started inside another waits for the outer one](#in-flutter-a-read-write-transaction-started-inside-another-waits-for-the-outer-one)).
- On 5.2.0, opening a directory that is already open fails after about a second; on 5.1.0, `Ditto.open` never completes ([In Flutter, opening an open directory again fails within a second on SDK 5.2.0 and never completes on 5.1.0](#in-flutter-opening-an-open-directory-again-fails-within-a-second-on-sdk-520-and-never-completes-on-510)).
- On 5.2.0, `SyncSubscription` and `Transaction` objects that are garbage-collected after their instance was closed can stop the next `Ditto.open` or `close()` in the same process ([In Flutter 5.2.0, dropped subscription and transaction objects of a closed instance stop the next open or close](#in-flutter-520-dropped-subscription-and-transaction-objects-of-a-closed-instance-stop-the-next-open-or-close)).
- `close()` while a transaction is open stops the isolate; `close()` with pending writes fails their `Future`s although it stores them; afterwards, calls throw `DittoClosedException`, and `DittoLogger.customLogCallback` is cleared ([In Flutter, close() while a transaction is open stops the app's isolate](#in-flutter-close-while-a-transaction-is-open-stops-the-apps-isolate), [In Flutter, close() fails pending execute calls, also writes that it stores](#in-flutter-close-fails-pending-execute-calls-also-writes-that-it-stores), [In Flutter, calls after close() throw DittoClosedException](#in-flutter-calls-after-close-throw-dittoclosedexception), [In Flutter, close() clears DittoLogger.customLogCallback](#in-flutter-close-clears-dittologgercustomlogcallback)).
- `Ditto.version` returns a string such as `iOSF5.2.0_f6bdf023fa`, also on macOS, and `0.0.0_<hash>` until the first instance is opened ([In Flutter, Ditto.version includes a platform prefix and a build hash](#in-flutter-dittoversion-includes-a-platform-prefix-and-a-build-hash)).

## Flutter Observer Behavior

### In Flutter, a slow async observer callback does not hold back the next result

| | |
|---|---|
| Observed on | SDK 5.2.0, four runs, and 5.1.0, three runs; every run gave the same result, and the results were the same on both releases |
| Setup | One document; ten `UPDATE`s of its field `n` (1 to 10), 50 ms apart, each awaited. Every observer callback awaited a 500 ms delay. Each API ran on its own store |
| Documentation | The `ditto_live` 5.2.0 API reference: `registerObserverV2` signals readiness after an update has been added to `changes` and `onChange` has returned, and follows `pause` and `resume` of the stream; `registerObserverWithSignalNext` waits for `signalNext`, and then delivers at most one event with the latest result |

| How the result was consumed | Callbacks | Most callbacks running at once | Values received | Until the latest value was handled |
|---|---|---|---|---|
| `registerObserver`, `changes.listen` with an `async` function | 11 | 10 | All, 0 to 10 | about 1.0 s |
| `registerObserver`, an `async` function as `onChange` | 11 | 10 | All | about 1.0 s |
| `registerObserver`, `await for` over `changes` | 11 | 1 | All, one after another | 5.2 to 5.3 s |
| `registerObserverV2` (Experimental), `await for` over `changes` | 3 | 1 | 0, 1, 10 | 1.2 to 1.3 s |
| `registerObserverV2`, `changes.listen` with an `async` function | 11 | 10 | All | about 1.0 s |
| `registerObserverWithSignalNext` (Experimental), `signalNext()` after the work | 3 | 1 | 0, 4, 10 | about 1.2 s |

- `listen` and `onChange` do not await the `Future` that an `async` callback returns: ten callbacks ran at the same time. Because every callback here took the same time, the last one to finish was also the newest; with callbacks of different lengths, an older result can finish last, as in [In JavaScript, registerObserver does not await async callbacks](javascript-sdk.md#in-javascript-registerobserver-does-not-await-async-callbacks).
- `await for` over the `changes` of a `registerObserver` observer handled one result at a time, but the stream kept every result: the latest value was handled after all ten older ones, about 5 seconds after the writes ended.
- With `registerObserverV2` and `await for`, and with `registerObserverWithSignalNext`, the intermediate values were merged: three callbacks, the last with the latest value.
- `registerObserverV2` with `listen` behaved like `registerObserver`: `listen` does not pause the stream, so the observer kept signaling.

**Not tested:** callbacks of different lengths, results from sync instead of local writes, iOS and Android.

**Used in:** [Backpressure in Flutter](../../best-practices/platforms/flutter.md#backpressure-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Backpressure (SDK 5.1+)](../../best-practices/observers.md#backpressure-sdk-51), [Keep observer callbacks fast](../../best-practices/observers.md#keep-observer-callbacks-fast).

### In Flutter, an exception thrown in an observer callback reaches the zone, and the observer keeps running

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases |
| Setup | For each variant, the observer was registered and its stream listened to inside `runZonedGuarded`, whose error handler counted the errors. The callback threw a `StateError` on every call. Three `UPDATE`s followed, 300 ms apart |

| Variant | Calls (registration plus 3 writes) | Errors that reached the zone | Results on `changes` |
|---|---|---|---|
| `registerObserver` with an `onChange` that throws; `changes` also listened to | 4 | 4 | **0** |
| `registerObserver`, `changes.listen` that throws | 4 | 4 | |
| `registerObserver`, `changes.listen` with an `async` function that throws after an `await` | 4 | 4 | |
| `registerObserverV2`, `changes.listen` that throws | 4 | 4 | |
| `registerObserverWithSignalNext`, `changes.listen` that throws before calling `signalNext()` | **1** | 1 | |
| `registerObserverWithSignalNext`, an `onChange` that calls `signalNext` and then throws; `changes` also listened to | 4 | 4 | **0** |

- Each exception was reported to the error handler of the zone in which the observer was registered or the stream was listened to. The observer stayed registered and was called for the next write, and the store kept working.
- When `onChange` throws, the result is not added to `changes`: a listener of `changes` received none of the four results. The SDK adds the result to the stream after `onChange` returns (`ditto_live` 5.2.0 source, `StoreObserver._make` and `StoreObserverV2._make`).
- An exception before `signalNext()` stops the observer for good: it was not called again for the three writes, without any other sign.

**Not tested:** an exception without `runZonedGuarded` in a running app, where it reaches the app's own error zone or `PlatformDispatcher.onError`, iOS and Android.

**Used in:** [Observer lifecycle in Flutter](../../best-practices/platforms/flutter.md#observer-lifecycle-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Observer Lifecycle](../../best-practices/observers.md#observer-lifecycle).

### In Flutter, the observer lifecycle rules held on SDK 5.1.0 and 5.2.0

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases, apart from `store.observers`, which 5.1.0 does not have |
| Setup | One document whose field `n` was updated; each rule was tested on its own store |

- Without `onChange`, `registerObserver` ran no query before the first `listen`: after three writes, a late `listen` received one result with the latest value. With `onChange`, the observer started at registration, and the late `listen` received all four results that `onChange` had received.
- A second `listen` on `changes` threw `StateError: Bad state: Stream has already been listened to.`, also after the first subscription had been cancelled. Cancelling the `StreamSubscription` did not cancel the observer (`isCancelled` stayed `false`, and on 5.2.0 `store.observers` still listed it); `observer.cancel()` did.
- `observer.cancel()` ended an `await for` loop over `changes`, for `registerObserver` and `registerObserverV2`. `ditto.close()` did not end it, although `isCancelled` became `true`.
- For `registerObserverV2`, cancelling the stream subscription, or `break` out of `await for`, cancelled the observer.
- `registerObserverV2` paused during five writes delivered, after `resume`, the result that arrived at the pause and the latest one (`[0, 1, 5]`). A paused `registerObserver` stream kept all five and delivered them on `resume` (`[0, 1, 2, 3, 4, 5]`).
- `registerObserverWithSignalNext` without `signalNext()` delivered only the first result during three writes; one `signalNext()` then delivered the latest value only.

**Not tested:** iOS and Android, `StreamBuilder` and other widgets.

**Used in:** [Observer lifecycle in Flutter](../../best-practices/platforms/flutter.md#observer-lifecycle-in-flutter), [Backpressure in Flutter](../../best-practices/platforms/flutter.md#backpressure-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, an observer whose changes stream nobody consumes keeps every result in memory

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run of each variant on each release, plus one run of all variants in one process on 5.2.0 |
| Setup | 200 documents of about 1 KB in the observed result. One field was updated 300 times, 40 ms apart. Each variant ran in its own process; we counted the callbacks, read the process's resident memory (`ProcessInfo.currentRss`) before and after the updates, and then listened to `changes` and counted the results it delivered within 2 seconds |

| Variant | Results waiting in `changes` | Memory growth on 5.2.0 | on 5.1.0 |
|---|---|---|---|
| `registerObserver` with `onChange`, `changes` never listened to | 301 | 129 MB | 100 MB |
| `registerObserver` with `onChange`, `changes` consumed | 0 | 39 MB | 31 MB |
| `registerObserver` without `onChange`, never listened to | none (no query ran; a late `listen` received 1 result) | 1 MB | 3 MB |
| `registerObserverV2` with `onChange`, never listened to | 301 | 129 MB | 107 MB |
| `registerObserverWithSignalNext` with an `onChange` that signals, never listened to | 301 | 129 MB | 113 MB |

- Every result that `onChange` received also waited in `changes`, about 0.3 to 0.4 MB each for this result size, until something listened. The same held for `registerObserverV2` and `registerObserverWithSignalNext` with `onChange`.
- In one process, the variants that ran after the first grew by only 2 to 4 MB: the process reused the memory that the first variant had taken. Compare memory only between separate processes.

**Not tested:** iOS and Android, how the memory behaves after the observer is cancelled, smaller results.

**Used in:** [Store Observers in Flutter](../../best-practices/platforms/flutter.md#store-observers-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, observers and subscriptions whose references were dropped keep running

| | |
|---|---|
| Observed on | SDK 5.2.0, two runs (the second with the `WeakReference`s), and 5.1.0, one run with them; the results were the same in every run |
| Setup | Store B, connected to store A over TCP, registered a subscription and four observers (`registerObserver` with `onChange`, `registerObserver` with `changes.listen`, `registerObserverV2` with `changes.listen`, `registerObserverWithSignalNext` with `onChange`) in a function that kept no reference, apart from `WeakReference`s. After a first document from A arrived, the test allocated and dropped about 2 GB in 1 MB chunks to make the VM collect garbage, and A wrote a second document |
| Documentation | The `ditto_live` API reference: an observer or a subscription remains active until it is cancelled or its `Ditto` is closed |

- The `SyncSubscription` object was collected (its `WeakReference` was empty), but the subscription stayed in `ditto.sync.subscriptions` (1), and A's second document still arrived on B. A collected `SyncSubscription` can be cancelled only through its element of `ditto.sync.subscriptions`.
- None of the four observers was collected: the SDK keeps them, and their callbacks, reachable. Each was called for A's second document and for a local write on B. On 5.2.0, `store.observers` listed both `registerObserver` observers before and after the collection.

**Not tested:** iOS and Android, longer runs, whether the native handle of a collected subscription is freed.

**Used in:** [Subscriptions in Flutter](../../best-practices/platforms/flutter.md#subscriptions-in-flutter), [Observer lifecycle in Flutter](../../best-practices/platforms/flutter.md#observer-lifecycle-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Observer Lifecycle](../../best-practices/observers.md#observer-lifecycle), [Subscription Lifecycle](../../best-practices/sync-and-subscriptions.md#subscription-lifecycle).

## Flutter Statement and Value Behavior

### In Flutter, each read of result.items creates new items, and results stay readable after close

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases |
| Setup | Two documents; we read `items`, `items.first`, and `item.value` several times, changed `item.value`, wrote with `UPDATE ... WHERE _id IN :ids`, cancelled an observer after its first result, and read the results after `ditto.close()` |
| Documentation | The `ditto_live` API reference: the first time `value` is accessed, it is loaded and then cached until the `QueryResultItem` is garbage-collected. In the 5.2.0 source, `items` creates a new `QueryResultItem` for every element on every iteration, and `value` is `jsonDecode` of the item's JSON |

- Within one item, `item.value` returned the same `Map` every time. `result.items` returned a new `Iterable` every time, `result.items.first` a new item, and so a new `Map`.
- The `Map` is modifiable (`_Map<String, dynamic>`, also the nested maps). After `item.value['status'] = ...`, that item's `value` kept the change; a new item from the same result, and the store, did not.
- `mutatedDocumentIDs()` returned `['o1', 'o2']`, a new `List` on every call. `commitID` was an `int`. The write returned no items.
- After `ditto.close()`, `items.length`, the `value` of an item read before the close and of one not read yet, `jsonString`, `cborBytes`, `mutatedDocumentIDs()`, and `commitID` could all still be read. So could the result of an observer that had been cancelled.

**Not tested:** memory held by results that are kept, results of large queries, iOS and Android.

**Used in:** [Query results in Flutter](../../best-practices/platforms/flutter.md#query-results-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, Dart values change type between writing and reading

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases |
| Setup | Each value was written in its own document as `{'_id': ..., 'v': value}` through `arguments`, and read back with `SELECT v, type(v) AS storedAs, char_length(v) AS chars` |
| Documentation | In the `ditto_live` 5.2.0 source, arguments are encoded with `cbor.encode` of `package:cbor` 6.5.1, which writes a `DateTime` as a date-time string and calls `toCbor()` on other objects; `QueryResultItem.value` is `jsonDecode` of the item's JSON |

| Dart value | Written | `type(v)` | Read back from `item.value` |
|---|---|---|---|
| `DateTime.utc(2026, 11, 6, 10, 30, 45, 123, 456)` | yes | `string` | `'2026-11-06T10:30:45.123456Z'` |
| A local `DateTime` (UTC+9) | yes | `string` | `'2026-11-06T01:30:45+09:00'` |
| `Uint8List` `[0, 1, 2, 255]` | yes | `binary` | a `List<dynamic>` `[0, 1, 2, 255]`, not a `Uint8List` |
| `List<int>` `[0, 1, 2, 255]` | yes | `array` | a `List<dynamic>` |
| `9223372036854775807`, `-9223372036854775808`, `9007199254740993` | yes | `integer` | the same `int` |
| `BigInt` 2^63 and 2^64 − 1 | yes | `integer` | a `double` (`9223372036854776000.0`, `18446744073709552000.0`): digits are lost |
| `BigInt` 2^64 | yes | `binary` | a `List<dynamic>` `[1, 0, 0, 0, 0, 0, 0, 0, 0]` |
| `-5` in a map, and `-5` as a parameter | yes | `object` / `integer` | `-5` |
| `1.0` | yes | `float` | `1.0` (`double`) |
| `double.nan`, `double.infinity` | no: `DittoException(<dql> Invalid query arguments: Non finite float value)` | | |
| A map with `int` keys | no: `DittoException(<dql> Invalid query arguments: expected {String,Bytes,} found byte 0x1 at offset 18)` | | |
| A `Set` | yes | `array` | a `List<dynamic>` |
| A `Uri` | yes | `string` | the URL as a `String` |
| `Duration`, a class of the app, `Object()` | no: `NoSuchMethodError: Class '...' has no instance method 'toCbor'` | | |
| A class with a `toCbor()` method | yes, as the value that `toCbor()` returns | `object` | a `Map` |
| `'a\uD800b'` (an unpaired surrogate) | yes, without an error | `string` | `'a�b'`: the surrogate became U+FFFD |
| `null`, `true`, `{}`, `{'a': [1, {'b': 2}]}` | yes | `null`, `boolean`, `object`, `object` | unchanged |

- A `DateTime` passed as a query parameter matched a stored string of the same instant in the same format (`WHERE at = :at` found 1 document).
- `DateTime.toIso8601String()` on macOS: `'...00.123456Z'` with microseconds, `'...00.123Z'` with milliseconds only, `'...00.000Z'` for a whole second.

**Not tested:** iOS, Android, and the Web (where `int` is a JavaScript number), reading the same values with `cborBytes`, values written by other SDKs.

**Used in:** [Arguments and value types in Flutter](../../best-practices/platforms/flutter.md#arguments-and-value-types-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, invalid DQL fails the Future of execute and throws when an observer or subscription is registered

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases |
| Setup | A misspelled `SELEC`, an unknown function, a missing parameter, an argument that cannot be encoded, and an `UPDATE` passed to `execute`, `transaction.execute`, `registerObserver` (with and without `onChange`), `registerObserverV2`, and `registerSubscription` |

- `execute` and `tx.execute` returned a failed `Future`: `DittoException(<dql> Invalid query: DQL parser error: Unexpected token SELEC at line 1 column 1 ...)`, `Function "nosuchfn" not found`, and `Parameter color was not provided`. An `Object()` argument failed with `NoSuchMethodError` (`has no instance method 'toCbor'`).
- `registerObserver` (with or without `onChange`), `registerObserverV2`, and `registerSubscription` threw the `DittoException` synchronously, at registration, also for a missing parameter. An `UPDATE` threw `Unsupported feature: non-SELECT statement in store observer` (`... in sync subscription`). Nothing reached the stream or the zone afterwards.
- The store kept working.

**Not tested:** iOS and Android, errors that occur only while the query runs.

**Used in:** [Executing DQL in Flutter](../../best-practices/platforms/flutter.md#executing-dql-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

## Flutter Subscription Behavior

### In Flutter, the subscriptions and observers that registration returns report their arguments

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases |
| Setup | Subscriptions and observers with and without `arguments`; we read their query properties, compared them with `ditto.sync.subscriptions`, registered the same subscription twice, and cancelled one |

- A subscription registered without `arguments` reported `queryArguments` `{}`, `queryArgumentsJsonString` `'{}'`, and 1 byte of `queryArgumentsCborBytes`: `registerSubscription` passes an empty map by default. With `{'color': 'blue'}`, it reported that map. (The JavaScript SDK returns `null`; see [In JavaScript, a subscription without arguments has no queryArguments](javascript-sdk.md#in-javascript-a-subscription-without-arguments-has-no-queryarguments).)
- `ditto.sync.subscriptions` listed both. Its elements equal (`==`) the returned objects but are other objects, and their order differed between the releases.
- Registering the same query twice created a second subscription (3 in the list); cancelling it left the first one active.
- An observer from `registerObserver` without arguments reported the constant default `{}` as `queryArguments` (`_ConstMap`, which cannot be changed); one from `registerObserverV2` a new `{}`.

**Not tested:** iOS and Android.

**Used in:** [Subscriptions in Flutter](../../best-practices/platforms/flutter.md#subscriptions-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, reading the arguments of a listed subscription without arguments ends the app

| | |
|---|---|
| Observed on | SDK 5.2.0, one run of each property on macOS and one on iOS (`queryArgumentsJsonString`); SDK 5.1.0, two runs on macOS; every run that read an affected property ended the app |
| Setup | One subscription registered without `arguments`. The test read one property of its element of `ditto.sync.subscriptions` per run, and marked before and after the read. Controls read `queryString` and `isCancelled` of the element, all three properties of the object that `registerSubscription` returned, and all three properties of the element of a subscription registered with arguments |

- Reading `queryArgumentsJsonString`, `queryArgumentsCborBytes`, or `queryArguments` of that element ended the app with `EXC_BAD_ACCESS (SIGSEGV)` at address 0 (macOS crash report), before the read returned. This happened on 5.2.0 as on 5.1.0, and on the iOS simulator.
- `queryString` and `isCancelled` of the element could be read. The returned object, and the element of a subscription registered with arguments, returned all three properties.

**Not tested:** Android, subscriptions registered with an explicit empty map as `arguments`.

**Used in:** [Subscriptions in Flutter](../../best-practices/platforms/flutter.md#subscriptions-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Sync stop, close, and inspection](../../best-practices/sync-and-subscriptions.md#sync-stop-close-and-inspection).

### In Flutter, reads of system:data_sync_info kept responding with a peer in another process

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, ten runs each; no read stopped in any run |
| Setup | A Flutter store on macOS and a Node.js peer of the same release in a separate process, each subscribed to `orders`, connected over TCP on `127.0.0.1` (the Node.js peer listened). After the Flutter store saw the peer in presence, it inserted a document and read `SELECT * FROM system:data_sync_info` 20 times, 50 ms apart, then closed. A read that had not completed after 3 seconds would have counted as stuck |

- On both releases, all 20 reads completed in every run. The slowest read of a run took 0.003 to 0.018 seconds on 5.2.0 and 0.001 to 0.058 seconds on 5.1.0, and `close()` then completed in 0.537 to 0.582 seconds (5.2.0) and 0.535 to 0.555 seconds (5.1.0).
- The JavaScript SDK behaved differently with the same steps: a read stopped responding in 4 of 10 runs on 5.2.0 (see [In JavaScript, a read of system:data_sync_info can stop responding](javascript-sdk.md#in-javascript-a-read-of-systemdata_sync_info-can-stop-responding)).

**Not tested:** a Flutter app as the other peer, both peers in one process, an observer of `system:data_sync_info`, reads after the first 20, iOS and Android, Ditto Server.

**Used in:** [Subscriptions in Flutter](../../best-practices/platforms/flutter.md#subscriptions-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Monitoring Sync Status](../../best-practices/sync-and-subscriptions.md#monitoring-sync-status).

## Flutter Transaction Behavior

### In Flutter, store.execute inside a transaction callback throws, and outside it only writes wait

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases |
| Setup | (A) Inside a read-write transaction callback, after a `tx.execute` write, `ditto.store.execute` was called for a read and for a write, each in a `try`. (B) While a read-write transaction that had written a document stayed open for 2 seconds, code outside the callback ran a read and then a write with `ditto.store.execute`. (C) A callback returned `TransactionCompletionAction.rollback`, another threw, and a read-only transaction wrote |
| Documentation | The `ditto_live` 5.2.0 source detects the transaction scope with a `Zone` value and throws from `Store.execute` inside it |

- (A) Both calls threw `DittoException(Attempting to use ditto.store.execute while in a transaction scope. Use transaction.execute instead (where transaction is the first parameter of the callback function that is passed to ditto.store.transaction). ...)`. Because the callback caught them, the transaction committed its own write (`tx.execute` saw it inside, and it was stored); the write through `store.execute` was not stored.
- (B) The read outside the transaction returned at once and did not see the transaction's uncommitted document. The write waited until the transaction ended: 2.0 seconds.
- (C) Returning `TransactionCompletionAction.rollback` rolled back and made `transaction()` return that value. A throwing callback rolled back and rethrew its error (`StateError`). A write in an `isReadOnly: true` transaction failed with `DittoException(<store> A mutating DQL query was attempted using a read-only transaction.)`. Using a `Transaction` object after its callback ended threw `DittoException(Attempting to use transaction outside transaction scope. ...)`.

**Not tested:** iOS and Android.

**Used in:** [Transactions in Flutter](../../best-practices/platforms/flutter.md#transactions-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, code started inside a transaction callback cannot call store.execute after the commit

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases |
| Setup | (1) A transaction callback started a 500 ms timer that was not awaited, and returned; the timer called `ditto.store.execute` after the commit. (2) A transaction callback registered an observer and listened to its `changes`; after the commit, a write triggered the listener, which called `ditto.store.execute` |
| Documentation | Dart runs timers and stream listeners in the zone in which they were created. The SDK stores the transactions in scope as a value of that zone (`ditto_live` 5.2.0 source, `privateTransactionImpl`) |

- Both calls threw `DittoException(Transaction is no longer valid. Do not store the transaction object outside the transaction callback)`, although the transaction had committed and the code did not use the `Transaction` object. The error is raised while `Store.execute` builds its message about the transactions in scope.
- The listener keeps the zone for as long as it exists, so every later call of `store.execute` from it fails the same way.

**Not tested:** `Future.microtask` and other ways of scheduling work, iOS and Android.

**Used in:** [Transactions in Flutter](../../best-practices/platforms/flutter.md#transactions-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, a read-write transaction started inside another waits for the outer one

| | |
|---|---|
| Observed on | SDK 5.2.0, one run of each combination; SDK 5.1.0, one run of a read-write transaction inside a read-write transaction |
| Setup | Inside an outer transaction callback, after one read, the code started an inner transaction and waited for it for up to 10 seconds, then returned. Each combination of `isReadOnly` for the outer and the inner transaction ran in its own test |

| Outer | Inner | Inner transaction while the outer was open |
|---|---|---|
| read-write | read-write | Did not start within 10 seconds; it completed right after the outer transaction ended |
| read-write | read-only | Completed within 0.01 seconds |
| read-only | read-write | Completed within 0.01 seconds |
| read-only | read-only | Completed within 0.01 seconds |

- An outer read-write transaction that awaits an inner read-write transaction therefore never ends, and the SDK reports nothing. Here the 10-second limit let the outer transaction return.
- The store worked afterwards, and `close()` completed.

**Not tested:** writes in the inner transaction, iOS and Android.

**Used in:** [Transactions in Flutter](../../best-practices/platforms/flutter.md#transactions-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Transaction Rules](../../best-practices/transactions.md#transaction-rules).

## Flutter Open and Close Behavior

### In Flutter, opening an open directory again fails within a second on SDK 5.2.0 and never completes on 5.1.0

| | |
|---|---|
| Observed on | SDK 5.2.0, three runs on macOS and one on iOS; SDK 5.1.0, three runs on macOS; every run gave the same result. `Ditto.openSync`: one run on each release |
| Setup | With a `Ditto` open on a directory, the same process called `Ditto.open` with a `DittoConfig` for the same directory and waited 20 seconds. Then the first instance ran a query and was closed, and the directory was opened again. In a separate test, `Ditto.openSync` was called on the open directory |
| Documentation | The `ditto_live` 5.2.0 API reference: `Ditto.open` throws a `DittoException` if the chosen persistence directory is already locked |

- On 5.2.0, `Ditto.open` failed after 1.02 to 1.03 seconds with `DittoException(File already locked, working dir = ..., retried 5 times. Multiple Ditto instances cannot run at the same time within the same working directory. Either use unique working directories for each instance, or consider managing your Ditto instance as a singleton instead.)`, on macOS and on iOS.
- On 5.1.0, `Ditto.open` did not complete within 20 seconds in any run, and raised no error.
- `Ditto.openSync` threw the same `DittoException` after about 1.0 second on both releases.
- On both releases, the first instance kept working, and after it was closed, the directory opened again (in about 0.55 seconds, including the close).

**Not tested:** another process holding the directory, Android, how long the 5.1.0 call would have waited.

**Used in:** [One shared instance in Flutter](../../best-practices/platforms/flutter.md#one-shared-instance-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory).

### In Flutter 5.2.0, dropped subscription and transaction objects of a closed instance stop the next open or close

| | |
|---|---|
| Observed on | SDK 5.2.0: eight runs in which the subscription or transaction objects were not kept, three in which they were kept, three without subscriptions and transactions, and one that closed every store at the end; SDK 5.1.0: four runs in which the objects were not kept; every run gave the result of its group |
| Setup | One integration-test process ran 40 tests one after another. Each opened a store in a new directory (the same database ID in every test), ran a query, and closed the store. Variants added, before the close: an insert; an observer that was listened to and cancelled; a subscription that was registered and cancelled; a read-write transaction that wrote; the subscription or `Transaction` object either not referenced after the test or kept in a top-level list. Two more variants paused 1 second after each close, and closed no store in its test but all of them after the last test. Each step was marked, and a run that had not finished after 75 to 150 seconds was stopped |
| Documentation | In the `ditto_live` 5.2.0 source, a `NativeFinalizer` frees the native handle of a `SyncSubscription` and of a `Transaction` when the Dart object is garbage-collected (`bridge/native/sync.dart`, `bridge/native/store.dart`) |

| Variant | 5.2.0 | 5.1.0 |
|---|---|---|
| A subscription registered and cancelled, its object not kept (alone, or with an insert and an observer, also with a 1-second pause after each close) | 7 of 7 runs stopped, in the second or third test: at `Ditto.open` of the next store (6 runs) or at its `close()` (1 run) | 3 of 3 runs completed 40 tests |
| A read-write transaction, its `Transaction` object not kept | 1 of 1 run stopped, at `Ditto.open` of the second store | 1 of 1 run completed 40 tests |
| The same, with every subscription or `Transaction` object kept in a top-level list | 3 of 3 runs completed 40 tests | not run |
| A subscription and a transaction, objects not kept, every store closed only after the last test | 1 of 1 run completed 40 tests and closed the 40 stores | not run |
| No subscription and no transaction: only a query, with an insert, or with an observer | 3 of 3 runs completed 40 tests | not run |

- The call that stopped raised no error, and the stores had nothing else in common: each test used its own directory.
- The guide's local-store tests, which use a transaction and register subscriptions, behaved the same way in one process with a helper that closed each test's store in its tear-down: a `Ditto.open` did not complete in 4 of 6 runs on 5.2.0, after the multi-peer test or, in a run without it, in the middle of the local tests. Both runs that dropped every object stopped, and 2 of the 4 runs that kept only the subscription objects. With the helpers of [A local-store test helper in Flutter](../../best-practices/platforms/flutter.md#a-local-store-test-helper-in-flutter), which close the stores only after the last test, and each test file in its own process, every one of the guide's five Flutter test files (two on that page, three in the plugin) completed in 2 of 2 runs.
- The pattern matches a finalizer that frees an object of an instance that is already closed while the process opens or closes another one, but we did not determine the cause. Objects that a transaction creates inside the SDK cannot be kept by the app, so any code that uses `store.transaction` is exposed.

**Not tested:** iOS and Android, an app that closes and opens Ditto again (sign-out and sign-in), observers registered with `registerObserverV2`, other objects with finalizers (query results, attachments), how long the stopped call would have waited, and whether forcing garbage collection right after `close()` triggers it.

**Used in:** [Subscriptions in Flutter](../../best-practices/platforms/flutter.md#subscriptions-in-flutter), [A local-store test helper in Flutter](../../best-practices/platforms/flutter.md#a-local-store-test-helper-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Testing Strategies](../../best-practices/testing.md#testing-strategies), [Changes in SDK 5.2.0](../upgrading.md#changes-in-sdk-520), [Switching users on a shared device](../../best-practices/setup-and-lifecycle.md#switching-users-on-a-shared-device).

### In Flutter, close() while a transaction is open stops the app's isolate

| | |
|---|---|
| Observed on | SDK 5.2.0: two runs with a read-write transaction and one with a read-only transaction on macOS, and one with a read-write transaction on iOS; SDK 5.1.0: one run with a read-write transaction on macOS; every run gave the same result |
| Setup | A read-write transaction wrote a document, awaited a 1-second delay, and then wrote another. 200 ms after it started, the test called `ditto.close()` and waited for it for up to 20 seconds. A timer marked every second. One test used a read-only transaction that read instead of writing |
| Documentation | The `ditto_live` 5.2.0 source: closing "does not await in-flight API calls to complete as in the JS SDK" |

- After `close()` was called, nothing else ran in the isolate: the transaction did not continue after its delay, the 1-second timer never fired, and the 20-second limit on `close()` never fired either. The test was stopped by the lab's time limit of 90 to 240 seconds.
- The same happened with a read-only transaction.
- In an app, this is the UI isolate: the app stops responding.

**Not tested:** Android, a transaction that awaits only `tx.execute` calls, how long the isolate would stay stopped, what is on disk afterwards.

**Used in:** [Closing Ditto in Flutter](../../best-practices/platforms/flutter.md#closing-ditto-in-flutter), [Transactions in Flutter](../../best-practices/platforms/flutter.md#transactions-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown).

### In Flutter, close() fails pending execute calls, also writes that it stores

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, three runs each with a running worker and one run each without; every run gave the same result |
| Setup | The test started 200 `INSERT`s with `ditto.store.execute` without awaiting them, called `ditto.close()` right away, started 50 more `INSERT`s, and then awaited everything. In one variant an awaited `INSERT` ran first, so that the worker isolate on which `execute` runs was already running. Then the directory was opened again and the documents counted |
| Documentation | The `ditto_live` 5.2.0 source: closing does not await in-flight API calls |

| | Worker already running | First `execute` right before `close()` |
|---|---|---|
| `close()` | completed in 0.59 to 0.63 s | completed in 0.55 s |
| The 200 pending writes | all failed with `StateError: Bad state: Ditto closed before execute() completed` | 199 failed with the same error, 1 with `Ditto closed during execute worker spawn` |
| Stored after reopening | **all 200** | none |
| The 50 writes started after `close()` was called | failed with `DittoClosedException`, none stored | the same |

- With the worker running, every pending write was stored although its `Future` reported a failure. Code that retries writes whose `Future` failed during `close()` writes them twice. In JavaScript, `close()` waits for pending writes and they succeed (see [In JavaScript, close() completes pending writes](javascript-sdk.md#in-javascript-close-completes-pending-writes)).

**Not tested:** iOS and Android, fewer pending writes.

**Used in:** [Closing Ditto in Flutter](../../best-practices/platforms/flutter.md#closing-ditto-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown).

### In Flutter, calls after close() throw DittoClosedException

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases, apart from `store.observers`, which 5.1.0 does not have |
| Setup | With an observer (listened to), a `registerObserverV2` observer consumed with `await for`, a subscription, and a presence observer active, the test awaited `ditto.close()` and then called the APIs below |

- `store.execute` and `store.transaction` returned a `Future` that failed with `DittoClosedException` (`This ditto instance is closed, so all operations are invalid`). `registerObserver`, `registerObserverV2`, `sync.registerSubscription`, `sync.subscriptions`, `sync.start()`, `sync.stop()`, `sync.isActive`, `presence.graph`, `auth.status`, `transportConfig`, and `absolutePersistenceDirectory` threw it synchronously.
- `store.observers` (5.2.0) and `store.attachmentFetchers` returned empty sets. A second `close()` completed. `isClosed` was `true`.
- The observers and the subscription reported `isCancelled == true`; `cancel()` and the presence observer's `stop()` returned without an error.
- The `await for` loop over the `registerObserverV2` observer did not end after `close()`, nor after a later `cancel()`, which does nothing once Ditto is closed.

**Not tested:** iOS and Android, attachment fetchers that were running.

**Used in:** [Closing Ditto in Flutter](../../best-practices/platforms/flutter.md#closing-ditto-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, close() clears DittoLogger.customLogCallback

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run each; the results were the same on both releases |
| Setup | `DittoLogger` was read before `Ditto.init()`, then after it; a `customLogCallback` counted lines while two instances were open; one instance was closed and a third opened; the logs were exported twice to the same file |

- Before `Ditto.init()`, reading or setting `DittoLogger` threw `DittoError(Ditto not initialized. Call Ditto.init() and await the Future before using any Ditto functionality)`.
- The defaults were `isEnabled` `true`, `minimumLogLevel` `LogLevel.info`, and `customLogCallback` `null`.
- With two instances open, closing one set `customLogCallback` back to `null`. Neither the remaining instance nor a newly opened one sent any line to the callback afterwards (0 lines, against 53 before). `minimumLogLevel` kept its value.
- `DittoLogger.exportLogs(path)` returned the number of bytes it wrote (2,660 in this run), and a second export to the same path failed with `DittoError(FfiError(code: 20, description: File exists (os error 17)))`.

**Not tested:** iOS and Android, log lines emitted during `Ditto.open`.

**Used in:** [Logging in Flutter](../../best-practices/platforms/flutter.md#logging-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).

### In Flutter, Ditto.version includes a platform prefix and a build hash

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0 on macOS, and 5.2.0 on iOS, in every run |
| Setup | Every test recorded `Ditto.version`; ten runs on each release also recorded it before `Ditto.init()` and after it, before the first `Ditto.open` |
| Documentation | The `ditto_live` API reference describes `Ditto.version` as the semantic version of the SDK, with the example `4.4.3` |

- `Ditto.version` returned `iOSF5.2.0_f6bdf023fa` on 5.2.0 and `iOSF5.1.0_363452e05c` on 5.1.0, on macOS as on iOS. Code that compares or reports the version should extract the `x.y.z` part.
- Before the first instance of the process was opened, `Ditto.version` returned `0.0.0_f6bdf023fa` (5.2.0) and `0.0.0_363452e05c` (5.1.0), also after `await Ditto.init()` (ten runs on each release).

**Not tested:** Android and the Web.

**Used in:** [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk).
