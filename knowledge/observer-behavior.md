# Observer Behavior

How store observers behave on one device: when an observer is called, how changes are batched into callbacks, how often observers of `system:` collections fire, how observers differ between SDK releases, and how observers and query results behave in JavaScript. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Observing Changes](../best-practices/observers.md), [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage), and [Platform Differences](platform-differences.md).

**In brief**

- A `SELECT *` observer is called on every write to a document in its result, even of the same value; an observer that projects fields, only when a projected value changes; an aggregate observer, on every write to the collection ([When an observer fires depends on its query](#when-an-observer-fires-depends-on-its-query), [Writing the same value from an observer keeps it firing](#writing-the-same-value-from-an-observer-keeps-it-firing)).
- Since SDK 5.1, changes are coalesced into callbacks about 30 ms apart, so an observer skips intermediate values. Changes from another device arrive in a few callbacks, and a transaction in one ([Local writes are coalesced into callbacks about 30 ms apart](#local-writes-are-coalesced-into-callbacks-about-30-ms-apart), [A device receives nearly every value of a fast-changing field](#a-device-receives-nearly-every-value-of-a-fast-changing-field), [Remote changes arrive in a few callbacks, and a transaction in one](#remote-changes-arrive-in-a-few-callbacks-and-a-transaction-in-one)).
- An observer of `system:system_info` keeps firing while nothing changes: every 500 ms on 5.1.0 and twice about every second on 5.2.0, mostly with identical results ([Observers of system:system_info keep firing while nothing changes](#observers-of-systemsystem_info-keep-firing-while-nothing-changes)).
- `Differ` reports every item whose position shifted as a move, not only the item that was moved ([Differ reports every shifted item as a move](#differ-reports-every-shifted-item-as-a-move)).
- On SDK 5.2.0, observer rows have no `_id` unless the query projects it; on SDK 5.1.0, 60 or more observers stop every callback ([On SDK 5.2.0, observer rows include _id only when it is projected](#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected), [On SDK 5.1.0, observers stall beyond about 60](#on-sdk-510-observers-stall-beyond-about-60)).
- In JavaScript, async observer callbacks are not awaited and can finish out of order, exceptions in callbacks are discarded, and garbage collection stops neither observers nor subscriptions ([In JavaScript, registerObserver does not await async callbacks](#in-javascript-registerobserver-does-not-await-async-callbacks), [In JavaScript, exceptions in observer callbacks are discarded](#in-javascript-exceptions-in-observer-callbacks-are-discarded), [In JavaScript, garbage-collected subscriptions and observers keep running](#in-javascript-garbage-collected-subscriptions-and-observers-keep-running)).
- In JavaScript, query results return the same objects on every read, so changes to them stay in the object but never reach the store, and `store.observers` lists other objects than the ones that the registration returned ([In JavaScript, query results return the same objects](#in-javascript-query-results-return-the-same-objects), [In JavaScript, store.observers exists since 5.0 and lists other objects](#in-javascript-storeobservers-exists-since-50-and-lists-other-objects)).

## When Observers Are Called

### When an observer fires depends on its query

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; on 5.1.0 and 5.2.0, every run gave the same counts (three earlier runs each, without the writes of the current value, gave the same results for the other writes). Changes through sync: one run each on 5.1.0 and 5.2.0. The top-10 observer: one run each on 5.0.3, 5.1.0, and 5.2.0 |
| Setup | One device with 100 documents, 10 whose `status` was `open` and 90 `closed`, and the eight observers in the table below. Three kinds of write were made 20 times each, 100 ms apart, and we counted the calls of each observer: an update of `v` in a document that is in no observer's result, an update of `v` in an `open` document outside the `LIMIT 5`, and a write of the current value to an `open` document inside the `LIMIT` |

Calls per 20 writes (on 5.1.0 and 5.2.0):

| Observer | Document in no result | `v` of an `open` document outside the `LIMIT` | Current value written again |
|---|---|---|---|
| `SELECT * ... WHERE status = 'open'` | 0 | 20 | 20 |
| `SELECT * ... ORDER BY _id LIMIT 5` | 0 | 0 | 20 |
| `SELECT * ... WHERE _id = 'd01'` | 0 | 0 | 20 |
| `SELECT _id ...` (`v` not projected) | 0 | 0 | 0 |
| `SELECT _id, v ...` | 0 | 20 | 0 |
| `SELECT COUNT(*) ... WHERE status = 'open'` | 20 | 20 | 20 |
| `SELECT COUNT(*) FROM t` | 20 | 20 | 20 |
| `SELECT status, COUNT(*) ... GROUP BY status` | 20 | 20 | 20 |

- A `SELECT *` observer is called on every write to a document in its result, also when no value changes (as in [Writing the same value from an observer keeps it firing](#writing-the-same-value-from-an-observer-keeps-it-firing)).
- An observer that projects fields is called only when a projected value changes. A change to a field that it does not project, or a write of the same value, does not call it.
- Changes through sync behave the same (one run on 5.1.0 and 5.2.0). Of 10 writes on another device to a field that was not projected, `SELECT *` was called 10 times, `SELECT _id, v` 0 times, and `COUNT` 10 times. When the other device wrote the same value 10 times, `SELECT *` and `COUNT` were still called 10 times.
- On 5.1.0 and 5.2.0, an aggregate observer (`COUNT`, `GROUP BY`) is called on every write to the collection, whatever its result, so on a collection that is written often, it is recomputed on every write. On 5.0.3, `COUNT` was not called when its value did not change, and `GROUP BY` was called 4 to 14 times out of 20.
- An observer of `ORDER BY score DESC LIMIT 10`, which returns the top 10 of 1,000 documents, was not called for writes to documents outside its result: updates of other fields, updates to values that do not reach the top 10, `INSERT`, and `DELETE`. It was called once for each update of a document in its result and for each update to a value that enters the top 10, like an observer of `WHERE score >= 990`. With only `_id` and `score` projected, it was not called for updates of other fields of the documents in its result either.
- A projecting observer does not fall into the loop of [Writing the same value from an observer keeps it firing](#writing-the-same-value-from-an-observer-keeps-it-firing) (one run on 5.1.0 and 5.2.0). When the callback wrote the same value again with `DO UPDATE`, in 2 seconds, `SELECT *` was called 58 to 59 times, and `SELECT _id, v` only once, for its first result.

**Used in:** [Observing Changes](../best-practices/observers.md), [Prefer field-level updates over whole-document rewrites](../best-practices/dql.md#prefer-field-level-updates-over-whole-document-rewrites).

### Remote changes arrive in a few callbacks, and a transaction in one

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; nearly the same results on both releases. Local transactions: one run each on 5.0.3, 5.1.0, and 5.2.0 |
| Setup | Another device wrote 20 documents one at a time, awaiting each write; updated one document 20 times; and wrote 200 documents in one transaction. We counted the callbacks of an observer on the receiving device, and of an observer on the writing device. On one device, a transaction wrote 10 documents 50 ms apart and then committed or rolled back; for comparison, 10 writes were made 50 ms apart without a transaction |

| Change on the other device | Callbacks on the receiving device | Result in each callback |
|---|---|---|
| 20 documents inserted one at a time, each awaited | 2 to 3 | 1, 15 to 18, and 20 documents; or 1 and 20 |
| One document updated 20 times | 2 to 3 | Values 1, 10 to 16, and 20; or 1 and 20. The last is the latest value |
| 200 documents in one transaction | 1, in all 6 runs | 200 documents; no intermediate state |

- The writing device's own observer was called only 3 times for its 20 writes: local writes are coalesced too.
- A local transaction that wrote 10 documents 50 ms apart called the observer once, after the commit (10 documents), and not at all when it was rolled back. Without a transaction, 10 writes 50 ms apart called it 10 times.

**Used in:** [Observing Changes](../best-practices/observers.md).

### Local writes are coalesced into callbacks about 30 ms apart

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | One device wrote 50 documents, awaiting each write, and then 50 writes 50 ms apart, while a store observer counted its callbacks. In a second case, an observer registered with `registerObserverWithSignalNext` did not call `signalNext()` during 5 writes, and then called it |
| Documentation | The SDK 5.2.0 release notes mention observer updates being coalesced over 33 ms |

| Writes | 5.2.0 | 5.1.0 | 5.0.3 |
|---|---|---|---|
| 50 writes, each awaited | 5 callbacks | 4 callbacks | 16 callbacks |
| 50 writes, 50 ms apart | 50 callbacks | 50 callbacks | 50 callbacks |

- Since 5.1, the changes within about 30 ms are combined into one callback.
- With `registerObserverWithSignalNext`, no callback arrived during the 5 writes until `signalNext()` was called; then one callback delivered the latest result (5 documents). This was the same on all three releases.

**Used in:** [Observing Changes](../best-practices/observers.md), [registerObserverWithSignalNext (Experimental)](../best-practices/observers.md#registerobserverwithsignalnext-experimental).

### A device receives nearly every value of a fast-changing field

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each |
| Setup | Two peers in one process. One device updated one document 50 times a second, 200 times a second, and as fast as it could (about 620 times a second on 5.1 and later, about 520 on 5.0.3), for 8 seconds each. On the receiving device, we read the store every 2 ms and counted the distinct values seen, and we counted the calls of an observer and how old each delivered value was |

- **Store reads on the receiver**: at 50 and 200 updates a second, nearly every value written was seen: 401 values for 400 writes (including the initial value), and 1,561 to 1,586 for 1,600 writes. We did not determine whether the values missing at 200 a second were missed by the reader or skipped by sync. While the devices are connected and the receiver keeps up, intermediate states arrive, not only the last state (after offline edits, only the current state is sent; see [Only the current state syncs after offline edits](subscriptions-and-replication.md#only-the-current-state-syncs-after-offline-edits)). At the fastest rate, the reader could not keep up (2,000 to 2,300 values), so we could not measure whether sync delivered every state at that rate.
- **Observers**: on 5.1.0 and 5.2.0, the observer was called only 29 to 30 times a second (about every 34 ms), whatever the write rate. On 5.0.3, it had no limit of 30 a second:

| Write rate | Observer on 5.1.0 and 5.2.0 | Age of the value at the callback, 5.1.0 and 5.2.0 | Observer on 5.0.3 |
|---|---|---|---|
| 50 a second | 29 to 30 calls a second; about 230 of the 400 values arrived | Median 17 to 18 ms, at most 42 ms | 50 calls a second: all 400 values arrived (median age 9 ms) |
| 200 a second | 29 to 30 calls a second | Median 7 ms | About 105 to 110 calls a second |
| As fast as possible | 29 to 30 calls a second | Median 4 ms | About 105 to 110 calls a second |

- The more writes, the fresher the delivered value. 5.0.3 also has a limit, but a much higher one; upgrading from 5.0.x therefore reduces the number of observer calls.
- After the writes stopped, the last value arrived within 1 to 8 ms. On no release did the delay build up.
- For comparison, changes of peer metadata reach other peers only about once a second (see [Peer metadata changes reach other peers about once per second](connections-and-presence.md#peer-metadata-changes-reach-other-peers-about-once-per-second)).
- Over real wireless links, the delays are probably much larger.

**Not tested:** whether the values missing at 200 updates a second were missed by the reader or skipped by sync; whether sync delivered every state at the fastest rate; writing each value as its own document, so that an observer can process every value (we think no value is lost that way, because every document stays in the result).

**Used in:** [Observing Changes](../best-practices/observers.md).

### Writing the same value from an observer keeps it firing

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | An observer's callback wrote to the document that it observed: the value the document already had, with `UPDATE`; a different timestamp on each call; the value only when it differed from the stored one; or the value with `DO UPDATE_LOCAL_DIFF`. We counted the calls in 3 seconds |

| What the callback wrote | Calls in 3 seconds |
|---|---|
| The same value, with `UPDATE` | 86 on 5.1.0 and 5.2.0 (about every 35 ms), 296 on 5.0.3, without stopping |
| A different timestamp on each call | The same numbers |
| The value, only when it differed | 2 (the first result, and one after the write) |
| The value, with `DO UPDATE_LOCAL_DIFF` | 2 |

- A write of the same value is a change that calls the observer again, so the callback keeps writing and the observer keeps firing. An observer that projects fields does not loop this way (see [When an observer fires depends on its query](#when-an-observer-fires-depends-on-its-query)).

**Used in:** [Keep observer callbacks fast](../best-practices/observers.md#keep-observer-callbacks-fast).

### Observers of system:system_info keep firing while nothing changes

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each, and 5.0.3, one run |
| Setup | One device without sync and without other activity. Observers of `SELECT * FROM system:system_info`, `SELECT * FROM system:data_sync_info`, and `SELECT * FROM system:indexes`, each watched for 5 seconds; every result was compared with the previous one |
| Documentation | The 5.2.0 release notes say: "Most virtual-collection observers now fire only when data changes. Previously they fired periodically whether or not anything changed" (QE-1139) |

| Release | Callbacks of the `system:system_info` observer in 5 seconds | What changed between results |
|---|---|---|
| 5.0.3 | 5, about once a second | The storage keys changed once, at about 1.5 seconds; the other results were identical |
| 5.1.0 | 10, every 500 ms | In most results, only the `_id` or `timestamp` of 16 rows; the storage keys changed once, at about 1.5 seconds |
| 5.2.0 | 11 and 12, two about every second (for example at 1.007 and 1.040 seconds) | Most results were identical; the storage and transport keys changed in the first second |

- The observers of `system:data_sync_info` and `system:indexes` were called once, for the first result, on every release.

**Not tested:** other `system:` collections; observers while sync runs.

**Used in:** [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage), [System Virtual Collections](system-reference.md#system-virtual-collections), [Changes in SDK 5.2.0](upgrading.md#changes-in-sdk-520).

## Observer Differences between SDK Releases

### On SDK 5.2.0, observer rows include _id only when it is projected

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; deterministic |
| Setup | An observer of `SELECT name FROM items ORDER BY rank`, and an observer of a join, `SELECT o._id AS orderId, o.total, c.name AS customerName FROM orders o JOIN customers c ...`. We compared their rows with the result of `execute()`, and passed the rows to `Differ` after two documents had changed places |
| Documentation | The SDK 5.2.0 release notes say that observers with a projection no longer retain the previous result (#QE-1093), and also that "Observer behavior and query results are unchanged". They do not mention the change below |

| Rows of | 5.0.3 | 5.1.0 | 5.2.0 |
|---|---|---|---|
| The observer of `SELECT name FROM items ORDER BY rank` | `{"_id": "a", "name": "A"}` | `{"_id": "a", "name": "A"}` | `{"name": "A"}` |
| `execute()` of the same query | No `_id` | No `_id` | No `_id` |
| The join observer | — | Composite `_id` (`{"c": "c1", "o": "o1"}`) | No `_id` |

- As a result, on 5.2.0, `Differ` reported the reordering of two rows as `updates: [0, 1]` and `moves: []`, while 5.0.3 and 5.1.0 reported two moves. Without `_id`, `Differ` cannot tell the rows apart, so animations and other processing of the differences go wrong.
- In a join, `SELECT _id ...` returns the composite ID (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.2.0](dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-520)).

**Not tested:** Flutter's `Differ` and observers.

**Used in:** [Diffing Results](../best-practices/observers.md#diffing-results), [Joins in observers](../best-practices/dql.md#joins-in-observers).

### On SDK 5.1.0, observers stall beyond about 60

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0: two runs each with all observers registered at once (on 5.0.3, both runs crashed with `SIGTRAP` under our test runner and gave results when run alone), one run each with observers registered gradually; the costs on 5.1.0 and 5.2.0, one run each (medians of 7 measurements); and runs by hand to find the threshold (14 numbers between 20 and 300 on 5.1.0, 9 numbers between 20 and 100 on 5.0.3). Deterministic; the thresholds are the values on one Mac with 14 cores |
| Setup | N store observers, each of a different document, and then an update of one document. Variants: all N registered at once, or one every 20 ms; an update of all documents; and cancelling 90 of them. On 5.2.0, we also measured the time from a write until the observer was called, for different numbers of observers |
| Documentation | The SDK 5.2.0 release notes list a stall of observers when many are active at the same time (#SPO-1114) among the fixed issues, and say that up to 5.1.0, every write triggered every observer |

| Release | Normal | Stalled |
|---|---|---|
| 5.1.0 | 55 observers or fewer | 60 or more: in every attempt, the callback for the update did not arrive within 5 seconds (8 seconds in the runs by hand) |
| 5.0.3 | 30 or fewer | 35 or more |
| 5.2.0 | 1,000 observers: the update arrived in 54 ms | |

- On 5.1.0, when all observers were registered at once, even the first results arrived for only some of them (1 to 15 of 100). After about 5 seconds, `ERROR dittoffi: Failed to start store observer error=StoreError(DatabaseError(BeginTransactionTimeout))` was logged for each observer. The API raised no exception, and the observers did not appear to be cancelled.
- On 5.1.0, with one observer registered every 20 ms, all 100 observers received their first results, but after all documents had been updated, none of them received a callback (the same with 300; this time, no ERROR line appeared). With 50 observers registered this way, 5.1.0 delivered every callback, and 5.0.3 none.
- Cancelling 90 observers did not bring the others back. `execute` kept working.
- Because every write triggers every observer up to 5.1.0, many observers re-running at the same time appear to be the trigger.
- The costs on 5.2.0 (medians of 7 measurements): with 1, 10, 100, and 500 observers of different documents, one write took 3.8 to 6.3 ms, and the observer of the written document was called after the times below. With 500 observers of the same document, all 500 callbacks arrived within 25 ms. Registering the observers increased memory by a few MiB to about 20 MiB, varying from one measurement to the next.

| Observers of different documents | 1 | 10 | 100 | 500 |
|---|---|---|---|---|
| Time until the written document's observer was called | 4.3 ms | 5.6 ms | 9.6 ms | 22.8 ms |

**Not tested:** Flutter and mobile devices. The threshold may differ from device to device, for example with the number of threads.

**Used in:** [Known Issues in SDK 5.1.0](upgrading.md#known-issues-in-sdk-510), [Partial UI Updates](../best-practices/observers.md#partial-ui-updates).

## Observers and Results in JavaScript

### In JavaScript, registerObserver does not await async callbacks

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; deterministic; the results were the same on all three releases |
| Setup | Five documents were inserted 60 ms apart. The observer's callback took 600 ms on its second call and 10 ms on the others, and when it finished, it wrote the number of documents in its result to the app's state |

- With an async function passed to `registerObserver`, the callback was called 6 times, and two calls ran at the same time. The slow second call (1 document) finished last, so the final state was 1 document, while the store held 5. If no newer result arrives after that, the screen keeps showing the old state.
- With `registerObserverWithSignalNext`, calling `signalNext()` after the work, the callback was called only 3 times (the intermediate results were skipped), one call at a time, and the final state was 5 documents.

**Used in:** [Keep observer callbacks fast](../best-practices/observers.md#keep-observer-callbacks-fast), [Backpressure on other platforms](../best-practices/observers.md#backpressure-on-other-platforms), [Platform Differences](platform-differences.md).

### In JavaScript, exceptions in observer callbacks are discarded

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; the results were the same on all three releases |
| Setup | An observer whose callback threw on every call, while the process listened for `uncaughtException` and `unhandledRejection`. We also passed an `UPDATE` statement to `registerObserver`, timed the first callback, and closed Ditto with an observer active |

- A callback that threw on every call kept being called (4 times out of 4), and `isCancelled` stayed `false`. Nothing reached `uncaughtException` or `unhandledRejection`: the exceptions are silently discarded.
- `registerObserver` with an `UPDATE` statement throws at once: `Unsupported feature: non-SELECT statement in store observer`.
- The first callback arrives asynchronously, about 1 ms after the registration; it is not called inside the registration call.
- After `ditto.close()`, the observer's `isCancelled` is `true`, and the callbacks stop.

**Used in:** [Platform Differences](platform-differences.md).

### In JavaScript, query results return the same objects

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; deterministic; the results were the same on all three releases |
| Setup | We read `items`, `items[0]`, and `item.value` of one `QueryResult` several times, changed `item.value`, and read results after `ditto.close()` |

- `result.items` returns the same array every time, `result.items[0]` the same object, and `item.value` the same object: a value is kept once it has been created.
- After `item.value.n = 99`, later reads of `item.value.n` also return 99. The value in the store does not change (it stays 1).
- After `ditto.close()`, the `value` and `jsonString()` of results that had not been read yet could still be read.

**Used in:** [Materialize values, then let the result go](../best-practices/dql.md#materialize-values-then-let-the-result-go), [Platform Differences](platform-differences.md).

### In JavaScript, store.observers exists since 5.0 and lists other objects

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; deterministic; the results were the same on all three releases |
| Setup | We registered two observers with `registerObserver` and one with `registerObserverWithSignalNext`, cancelled one, and closed Ditto, and read `ditto.store.observers` after each step |
| Documentation | The JavaScript SDK's type definitions list `store.observers`, next to `store.attachmentFetchers`, on 5.0.3 as well |

- `store.observers` also works on 5.0.3.
- With two observers from `registerObserver`, it returned 2; with one from `registerObserverWithSignalNext` added, 3. However, `observers.includes(withSignal)` was `false`: the list holds other objects than the ones that the registration returned.
- After `cancel()` on one observer, the list had one fewer. `close()` set `isCancelled` to `true` on the remaining observers, and reading `store.observers` after `close()` threw `Can't perform operation using a Ditto instance that has been closed.`

**Used in:** [Platform Differences](platform-differences.md).

### Differ reports every shifted item as a move

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each, with the JavaScript `Differ` |
| Setup | An observer of three items whose results we passed to one `Differ`. We moved one item to the top of the list, changed a value and changed it back, and looked at the first `diff()` |

- Moving the third item to the top reported three moves (`2→0`, `0→1`, `1→2`) and one update for the moved item: every item whose position shifted is a move, not just the one that was moved.
- A value that changed and changed back between two results was not reported as an update.
- The first `diff()` reported every item as an insertion.
- On 5.2.0, rows of a query that did not project `_id` have no `_id`, so `Differ` cannot tell the items apart (see [On SDK 5.2.0, observer rows include _id only when it is projected](#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected)).

**Used in:** [Diffing Results](../best-practices/observers.md#diffing-results).

### In JavaScript, garbage-collected subscriptions and observers keep running

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result |
| Setup | A device registered a subscription and a store observer without keeping a reference to either. After their JavaScript objects had been garbage-collected (checked with a `WeakRef` to each), we checked whether new documents still arrived and whether the observer was still called, then cancelled both through `ditto.sync.subscriptions` and `ditto.store.observers` |

- The JavaScript objects of the subscription and the observer were garbage-collected (each `WeakRef` was empty). Ditto kept both running: `ditto.sync.subscriptions` and `ditto.store.observers` each returned one entry, new documents arrived, and the observer was called.
- `cancel()` on the objects from these lists stopped both: the lists were empty, no new documents arrived, and the observer was not called. The lists return other objects than the ones that the registration returned (see [In JavaScript, store.observers exists since 5.0 and lists other objects](#in-javascript-storeobservers-exists-since-50-and-lists-other-objects)), but they can be used to cancel.
- Garbage collection stops neither subscriptions nor observers. Once the reference is gone, the only ways to stop them are these lists and `close()`.

**Not tested:** Dart.

**Used in:** [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle).
