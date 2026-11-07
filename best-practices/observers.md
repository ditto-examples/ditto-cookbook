# Observing Changes

A **store observer** is a live local query. Ditto re-runs it whenever a local write or an incoming sync affects its query, and delivers the new result to your code. Observers never cause data to sync; pair them with a subscription (see [Sync and Subscriptions](sync-and-subscriptions.md)).

Every SDK accepts only `SELECT` queries for observers and takes parameters as arguments. The SDKs differ in how an observer delivers results, whether it waits for your code before it delivers the next one, and how you release it:

| | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Default API | `registerObserver`, consumed through its `changes` stream | `registerObserver(query, handler, args)` | `registerObserver(query, args) { result -> }`, or `observe(...)`, which returns a `Flow` | `registerObserver(query:arguments:deliverOn:handler:)` |
| Waits for your code | No | Until a synchronous handler returns; an `async` handler is not awaited | Until the suspending handler returns | Until the handler returns |
| Backpressure for asynchronous work (SDK 5.1+) | `registerObserverV2` and `registerObserverWithSignalNext` (both Experimental) | `registerObserverWithSignalNext` | Suspend in the handler, or `collect` | `handlerWithSignalNext:` |
| Callbacks run on | The isolate that registered the observer | The event loop | The main thread, unless `DittoFactory.create` gets another scope | The main queue, unless `deliverOn:` names another |
| An exception in the callback | Reaches the zone; the observer keeps running, but a throwing `onChange` keeps its result out of `changes`, and a throw before `signalNext()` stops the observer | A synchronous throw is discarded; a rejected `async` callback is an unhandled rejection | Closes the observer, and is only logged | Not possible: the handler cannot throw |
| Release | `cancel()` | `cancel()` | `close()` | `cancel()` |
| Recommended pattern | [Store Observers in Flutter](platforms/flutter.md#store-observers-in-flutter) | [Store Observers in JavaScript](platforms/javascript.md#store-observers-in-javascript) | [Store Observers in Kotlin](platforms/kotlin.md#store-observers-in-kotlin) | [Store Observers in Swift](platforms/swift.md#store-observers-in-swift) |

## When Observers Fire

Which writes call an observer depends on its query. Project the fields a screen needs, including `_id`, so that writes to other fields do not call it (on SDK 5.2.0, rows of a query that does not project `_id` have no `_id`; see [Diffing Results](#diffing-results)). In our testing with SDK 5.1.0 and 5.2.0, observers were called as follows (see [When an observer fires depends on its query](../knowledge/observations/observer-behavior.md#when-an-observer-fires-depends-on-its-query)):

| Query | Called for |
|---|---|
| `SELECT *` | Every write to a document in its result, also a write that changes no value |
| A projection, such as `SELECT _id, status ...` | Only writes that change a projected value |
| `LIMIT` | Writes to documents in its result; not writes to documents outside it |
| An aggregate (`COUNT`, `GROUP BY`) | Every write to the collection, also to documents that its `WHERE` excludes, and also when the result stays the same |
| Any query, for writes to another collection | None: 50 writes to another collection ran no observer query (SDK 5.0.3 re-ran it after about every third write; see [On SDK 5.1.0 and 5.2.0, an observer did not re-run its query after writes to another collection](../knowledge/observations/observer-behavior.md#on-sdk-510-and-520-an-observer-did-not-re-run-its-query-after-writes-to-another-collection)) |

An observer does not see every intermediate state. Since SDK 5.1, it is called at most about 30 times a second, for local writes and for changes from sync alike: a quickly changing value skips intermediate states, but the latest one arrives within tens of milliseconds (see [Since SDK 5.1, local writes are coalesced into callbacks about 30 ms apart](../knowledge/observations/observer-behavior.md#since-sdk-51-local-writes-are-coalesced-into-callbacks-about-30-ms-apart) and [A device receives nearly every value of a fast-changing field](../knowledge/observations/observer-behavior.md#a-device-receives-nearly-every-value-of-a-fast-changing-field)). Changes from sync also arrive in batches: in our testing, 20 documents written one by one on another device arrived in two or three callbacks, and a transaction, local or remote, arrived as one callback with all of its documents (see [Remote changes arrive in a few callbacks, and a transaction in one](../knowledge/observations/observer-behavior.md#remote-changes-arrive-in-a-few-callbacks-and-a-transaction-in-one)).

**✅ DO:**
- Project only the fields that a screen shows, plus `_id`.
- Skip the UI update when an aggregate result equals the previous one (see [Partial UI Updates](#partial-ui-updates)).
- Write each value as its own document when every value must be processed (see [Pattern 2: Append-only event documents](data-modeling.md#pattern-2-append-only-event-documents)).

**❌ DON'T:**
- Count or log every local or remote change from observer callbacks; intermediate states can be skipped.

## Observer Lifecycle

An observer runs its query and holds memory until you release it. Give each observer one owner whose lifetime matches the results it shows, such as a screen, a view model, or an app-level service, and release the observer when that owner goes away.

**✅ DO:**
- Register an observer once when its owner starts, never in code that runs on every render or rebuild.
- Release every observer explicitly with the SDK's release call (`cancel()`, or `close()` in Kotlin). Do not rely on garbage collection or on closing Ditto: in our testing with all four SDKs on SDK 5.1.0 and 5.2.0, observers and subscriptions whose objects the app had dropped kept running, also after garbage collection (see [In Flutter, observers and subscriptions whose references were dropped keep running](../knowledge/observations/flutter-sdk.md#in-flutter-observers-and-subscriptions-whose-references-were-dropped-keep-running), [In JavaScript, garbage-collected subscriptions and observers keep running](../knowledge/observations/javascript-sdk.md#in-javascript-garbage-collected-subscriptions-and-observers-keep-running), [In Kotlin, garbage-collected subscriptions and observers keep running](../knowledge/observations/kotlin-sdk.md#in-kotlin-garbage-collected-subscriptions-and-observers-keep-running), and [In Swift, dropped observer and subscription objects keep running](../knowledge/observations/swift-sdk.md#in-swift-dropped-observer-and-subscription-objects-keep-running)), and in Flutter, `close()` does not end a loop over an observer's results (see [Observer lifecycle in Flutter](platforms/flutter.md#observer-lifecycle-in-flutter)).
- Copy plain values out of each result (the item's value, or your own model objects) before you keep them; do not keep result or item objects around (see [Working with Query Results](dql.md#working-with-query-results)).
- Observe a list once and pass the values down to its rows.

Catch errors inside every observer callback: depending on the SDK, an error that escapes stops the observer without a trace (Kotlin closes it and only logs the exception), ends the process (a rejected `async` callback in Node.js), or leaves an observer that waits for `signalNext()` forever (see [In Kotlin, an observer whose handler throws is closed, and the exception is only logged](../knowledge/observations/kotlin-sdk.md#in-kotlin-an-observer-whose-handler-throws-is-closed-and-the-exception-is-only-logged), [In JavaScript, an async observer callback that rejects causes an unhandled rejection](../knowledge/observations/javascript-sdk.md#in-javascript-an-async-observer-callback-that-rejects-causes-an-unhandled-rejection), and [In Flutter, an exception thrown in an observer callback reaches the zone, and the observer keeps running](../knowledge/observations/flutter-sdk.md#in-flutter-an-exception-thrown-in-an-observer-callback-reaches-the-zone-and-the-observer-keeps-running)).

**❌ DON'T:**
- Register an observer per list row.
- Keep an observer running for a screen that is no longer shown.

**How many observers**: On devices that still run SDK 5.1.0, stay well below about 60 observers in total, and do not register one observer per row of a list. In our testing on one Mac, 60 or more observers on 5.1.0 stopped every callback, without an exception, and cancelling most of them did not bring the others back; on 5.2.0, 1,000 observers worked, and with 500 observers of different documents, the observer of a written document was called after about 23 ms instead of about 4 ms with one (see [On SDK 5.1.0, observers stall beyond about 60](../knowledge/observations/observer-behavior.md#on-sdk-510-observers-stall-beyond-about-60) and [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)). The threshold may differ on other devices.

Each SDK page shows where to register and release observers in that SDK's UI code: [Flutter](platforms/flutter.md#observer-lifecycle-in-flutter) · [JavaScript](platforms/javascript.md#observer-lifecycle-in-javascript) · [Kotlin](platforms/kotlin.md#observer-lifecycle-in-kotlin) · [Swift](platforms/swift.md#observer-lifecycle-in-swift).

### Stable ordering

Observer results have no guaranteed order unless the query has an `ORDER BY` clause. Lists that re-order randomly on every update are a common symptom. Produce the timestamp you sort by with one fixed-precision helper (see [Timestamps](data-modeling.md#timestamps)).

```sql
-- ❌ BAD: No ORDER BY; rows may change position between updates
SELECT * FROM tasks WHERE done = false

-- ✅ GOOD: Deterministic order; _id breaks ties between equal timestamps
SELECT * FROM tasks WHERE done = false ORDER BY createdAt DESC, _id
```

### Keep observer callbacks fast

Unless you use a backpressure API (see [Backpressure (SDK 5.1+)](#backpressure-sdk-51)), Ditto does not wait for the work that a result starts before it delivers the next result. Slow work in a callback then either queues results up or runs several times at once, depending on the SDK.

**✅ DO:**
- Keep callbacks synchronous and short: copy values, map them to model objects, and hand them to your UI state.
- Move expensive decoding or computation off the UI thread, on plain values copied out of the result.
- Use the SDK's backpressure API when each update starts slow or asynchronous work.
- Throttle UI updates for very busy collections if the user cannot perceive every intermediate state.

**❌ DON'T:**
- Wait for network calls, file I/O, or database writes in a default observer callback. In our testing with the JavaScript SDK, `async` callbacks overlapped, and a slow callback for an older result finished last, so the screen kept showing the older state (see [In JavaScript, registerObserver does not await async callbacks](../knowledge/observations/javascript-sdk.md#in-javascript-registerobserver-does-not-await-async-callbacks)).
- Write to the same collection from inside its observer without a guard; each write triggers the observer again. In our testing, a `SELECT *` observer that wrote the same value to its own document was called again about every 35 ms without end; comparing the value before writing, or `DO UPDATE_LOCAL_DIFF`, stopped it (see [Writing the same value from an observer keeps it firing](../knowledge/observations/observer-behavior.md#writing-the-same-value-from-an-observer-keeps-it-firing)).

## Backpressure (SDK 5.1+)

With backpressure, your code decides when the next result may arrive. While your code is busy, Ditto holds back further updates and then delivers the latest state, so intermediate results are merged instead of queued or processed in parallel. The SDKs offer it in two forms:

- **Signal when done**: the observer delivers one result and waits until your code calls `signalNext()`. If your code never calls it, the observer stops delivering updates, so call it also after an error. JavaScript (`registerObserverWithSignalNext`), Swift (`handlerWithSignalNext:`), and Flutter (`registerObserverWithSignalNext`, Experimental) offer this form.
- **Wait for the handler**: the observer waits until your handler returns or, in Kotlin, until the suspending handler or the `Flow` collector resumes. Kotlin's observers and Swift's default `handler:` work this way, and so does Flutter's `registerObserverV2` (Experimental), which follows the pause and resume of its `changes` stream: consume it with `await for`, because `listen` with an `async` function does not pause the stream (in our testing, ten such callbacks ran at once; see [In Flutter, a slow async observer callback does not hold back the next result](../knowledge/observations/flutter-sdk.md#in-flutter-a-slow-async-observer-callback-does-not-hold-back-the-next-result)).

Flutter's default `registerObserver` has no backpressure: pausing its `changes` stream does not slow Ditto down, and results queue up in the stream instead.

### Choosing an observer API

| Situation | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Updating UI state from a query result | `registerObserver` + `changes` | `registerObserver` with a synchronous handler | `observe(...)` collected in the owner's scope, or `registerObserver` | `registerObserver(... handler:)` |
| Each update starts slow or asynchronous work (upload, file export, heavy aggregation) | `registerObserverV2` + `await for` (Experimental) | `registerObserverWithSignalNext` | A suspending handler, or `collect` | `handlerWithSignalNext:`, with `deliverOn:` a background queue |
| The work for an update finishes elsewhere (after an animation or an external callback) | `registerObserverWithSignalNext` (Experimental) | `registerObserverWithSignalNext` | Not available; suspend until the work is done | `handlerWithSignalNext:` |
| Very frequent updates where only the latest state matters | `registerObserverV2` with a slow consumer, or throttle the listener | Throttle the handler | `observe(...).conflate()` | Throttle the handler |

The experimental APIs may change in a future release. Code for each SDK: [Flutter](platforms/flutter.md#backpressure-in-flutter) · [JavaScript](platforms/javascript.md#backpressure-in-javascript) · [Kotlin](platforms/kotlin.md#backpressure-in-kotlin) · [Swift](platforms/swift.md#backpressure-in-swift).

## Diffing Results

An observer delivers the complete result every time. When you need to know **what** changed, for list animations or to process only new items, use the SDK's differ: `Differ` in Flutter and JavaScript and `DittoDiffer` in Swift, which you create and pass the items of each result; in Kotlin, the observer owns the differ and passes a `DittoDiff` to a handler with two parameters, and apps do not create a `DittoDiffer` (in our testing with SDK 5.1.0 and 5.2.0; see [The differs accept only items from Ditto query results, and Kotlin apps do not create one](../knowledge/observations/observer-behavior.md#the-differs-accept-only-items-from-ditto-query-results-and-kotlin-apps-do-not-create-one)). It compares successive results by `_id` and reports index sets:

| Field | Contents |
|---|---|
| Insertions | Indexes in the **new** list of items that were added |
| Deletions | Indexes in the **old** list of items that were removed |
| Updates | Indexes in the **new** list of items whose value changed |
| Moves | Pairs of an old and a new index for items that changed position |

Facts to keep in mind:

- The first diff reports every item as an insertion. A reorder reports a move for every item whose position shifted; an item that only shifts because another item was inserted or deleted is not a move. On SDK 5.1.0 and 5.2.0, every SDK's differ reported the same diffs in our testing (see [Every SDK's differ reports a reorder as a move of each shifted item and compares only two results](../knowledge/observations/observer-behavior.md#every-sdks-differ-reports-a-reorder-as-a-move-of-each-shifted-item-and-compares-only-two-results)).
- Identity is `_id`, so include `_id` in the projection of a diffed query. **Note (SDK 5.2.0):** in our testing with the JavaScript SDK, observer rows of a query that did not project `_id` had no `_id` (on 5.1.0 they did), and `Differ` reported a reordering as updates instead of moves (see [On SDK 5.2.0, observer rows include _id only when it is projected](../knowledge/observations/observer-behavior.md#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected)).
- Values are compared deeply, and only the two results are compared: in our testing with every SDK, a value that changed and changed back between two results was not reported as an update, and moving one item to the top of a three-item list reported three moves, one for every item whose position shifted, plus an update for the moved item (see [Every SDK's differ reports a reorder as a move of each shifted item and compares only two results](../knowledge/observations/observer-behavior.md#every-sdks-differ-reports-a-reorder-as-a-move-of-each-shifted-item-and-compares-only-two-results) and [The JavaScript Differ reports every shifted item as a move](../knowledge/observations/javascript-sdk.md#the-javascript-differ-reports-every-shifted-item-as-a-move)). An observer may also deliver a result that equals the previous one, which produces an empty diff.
- The differ keeps the previous result in memory, and diffing is computationally expensive. Debounce updates for large or busy result sets, and keep diffed queries bounded (for example, with `LIMIT`).
- The differ does not give you the old items. Keep the previous values, or at least their IDs, yourself.
- A list that identifies its rows by `_id` (a keyed list in Flutter, `ForEach` over identifiable values in SwiftUI, keys in Compose and React) does not need a differ; use one when the UI needs explicit insert, remove, and move calls, such as an animated list.

Code for each SDK: [Flutter](platforms/flutter.md#diffing-results-in-flutter) · [JavaScript](platforms/javascript.md#diffing-results-in-javascript) · [Kotlin](platforms/kotlin.md#diffing-results-in-kotlin) · [Swift](platforms/swift.md#diffing-results-in-swift).

## Partial UI Updates

An observer delivers a new result for **any** change that affects its query. If that result updates the state at the top of a large screen, the whole screen renders again, which can cause dropped frames, lost scroll position, or lost input focus on busy collections.

**✅ DO:**
- Give each screen region its own small observer, owned by the component that shows it, so a change updates only that region.
- Use lazy lists that render only the visible rows, and identify each row by `_id` so that rows keep their state across updates.
- Use aggregate queries for summary components (a badge needs `COUNT(*)`, not the full list), and skip the update when the value equals the previous one: an aggregate observer is called on every write to its collection (see [When Observers Fire](#when-observers-fire)).
- With a state management library, let one store, provider, or view model own each observer and release it when that owner is disposed.
- Map results to immutable model values that compare by content if you rely on equality checks to skip updates; each result creates new value objects, so two values with identical contents may not compare as equal.

**❌ DON'T:**
- Observe a whole collection at the root of the screen and render the entire screen on every change.
- Update an app bar, filters, and list together when only one row changed.

```sql
-- ✅ GOOD: A badge observes a count, not the list
-- Arguments: {"status": "open"}
SELECT COUNT(*) AS n FROM orders WHERE status = :status

-- ✅ GOOD: The list observes only the fields that its rows show
-- Arguments: {"status": "open"}
SELECT _id, customerName, total FROM orders WHERE status = :status ORDER BY createdAt DESC, _id
```

Several narrow observers, one per region, often cost less than rendering the entire screen for every change, and they make each component self-contained. Each observer re-runs its query when a write affects it (see [When Observers Fire](#when-observers-fire)), so keep the number of observers on busy collections reasonable, and confirm with your platform's profiler which components render before optimizing further.

Code for each SDK: [Flutter](platforms/flutter.md#partial-ui-updates-in-flutter) · [JavaScript](platforms/javascript.md#partial-ui-updates-in-javascript) · [Kotlin](platforms/kotlin.md#partial-ui-updates-in-kotlin) · [Swift](platforms/swift.md#partial-ui-updates-in-swift).
