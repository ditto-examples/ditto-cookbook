# Observer Behavior

How store observers behave: when an observer is called, how changes are batched into callbacks, what happens when observers on several devices write in reaction to each other's changes, how often observers of `system:` collections fire, and how observers differ between SDK releases. How each SDK's observer API calls your code is on the page of that SDK: [Flutter](flutter-sdk.md), [JavaScript](javascript-sdk.md), [Kotlin](kotlin-sdk.md), or [Swift](swift-sdk.md). How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Observing Changes](../../best-practices/observers.md), [Monitoring Storage](../../best-practices/deletion-and-storage.md#monitoring-storage), and [Platform Differences](../platform-differences.md).

**In brief**

- A `SELECT *` observer is called on every write to a document in its result, even of the same value; an observer that projects fields, only when a projected value changes; and on 5.1.0 and 5.2.0, an aggregate observer, on every write to the collection ([When an observer fires depends on its query](#when-an-observer-fires-depends-on-its-query), [Writing the same value from an observer keeps it firing](#writing-the-same-value-from-an-observer-keeps-it-firing)).
- Since SDK 5.1, changes are coalesced into callbacks about 30 ms apart, so an observer skips intermediate values. Changes from another device arrive in a few callbacks, and a transaction in one ([Since SDK 5.1, local writes are coalesced into callbacks about 30 ms apart](#since-sdk-51-local-writes-are-coalesced-into-callbacks-about-30-ms-apart), [A device receives nearly every value of a fast-changing field](#a-device-receives-nearly-every-value-of-a-fast-changing-field), [Remote changes arrive in a few callbacks, and a transaction in one](#remote-changes-arrive-in-a-few-callbacks-and-a-transaction-in-one)).
- Observers on two devices that write in reaction to a change kept writing to each other when each device wanted its own value, also when each compared before writing and also with `DO UPDATE_LOCAL_DIFF`; they stopped after one or two writes each when both wanted the same value, or one derived from synced data only. A loop on one device calls the `SELECT *` observers of the devices that sync the document as often as its own ([Observers on two devices that each write their own value keep writing](#observers-on-two-devices-that-each-write-their-own-value-keep-writing), [Observers on two devices that write the same value, or one derived from synced data, stop after one or two writes](#observers-on-two-devices-that-write-the-same-value-or-one-derived-from-synced-data-stop-after-one-or-two-writes), [A loop on one device calls the observers of the devices that sync the document](#a-loop-on-one-device-calls-the-observers-of-the-devices-that-sync-the-document)).
- An observer of `system:system_info` keeps firing while nothing changes: every 500 ms on 5.1.0, with new `_id` or `timestamp` values in 16 rows, and twice about every second on 5.2.0, mostly with identical results ([Observers of system:system_info keep firing while nothing changes](#observers-of-systemsystem_info-keep-firing-while-nothing-changes)).
- An observer of `system:data_sync_info` with an idle peer was not called every 500 ms, but 3 or 4 times in 40 seconds ([An observer of system:data_sync_info was called 3 or 4 times in 40 seconds with an idle peer](#an-observer-of-systemdata_sync_info-was-called-3-or-4-times-in-40-seconds-with-an-idle-peer)).
- Every SDK's differ, and Kotlin's `DittoDiff`, reported the same diffs on 5.1.0 and 5.2.0: the first result as insertions, a reorder as a move for every shifted item plus an update for the moved one, no move for items that only shifted because of a deletion or an insertion, and nothing for a value that changed and changed back between two results ([Every SDK's differ reports a reorder as a move of each shifted item and compares only two results](#every-sdks-differ-reports-a-reorder-as-a-move-of-each-shifted-item-and-compares-only-two-results)).
- The differs of Flutter, JavaScript, and Swift accept only the items of Ditto query results: test doubles and plain objects make `diff()` throw in Flutter and JavaScript, and Swift's item type cannot be created outside the SDK. Kotlin apps do not create a differ; the observer passes a `DittoDiff` to its handler ([The differs accept only items from Ditto query results, and Kotlin apps do not create one](#the-differs-accept-only-items-from-ditto-query-results-and-kotlin-apps-do-not-create-one)).
- On SDK 5.2.0, observer rows have no `_id` unless the query projects it, on every SDK except with Flutter's `registerObserver`; on SDK 5.1.0, 60 or more observers stopped every callback in our tests, a threshold that may differ by device ([On SDK 5.2.0, observer rows include _id only when it is projected, except with Flutter's registerObserver](#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected-except-with-flutters-registerobserver), [On SDK 5.1.0, observers stall beyond about 60](#on-sdk-510-observers-stall-beyond-about-60)).
- On SDK 5.0.3, an observer ran its query again after writes to other collections, which cost CPU time; on 5.1.0 and 5.2.0, it did not, although the 5.2.0 release notes list this as a fix ([On SDK 5.1.0 and 5.2.0, an observer did not re-run its query after writes to another collection](#on-sdk-510-and-520-an-observer-did-not-re-run-its-query-after-writes-to-another-collection)).
- What each SDK's observer API does with slow or failing callbacks, result objects, dropped references, and its differ is on the SDK pages: [Flutter SDK Behavior](flutter-sdk.md), [JavaScript SDK Behavior](javascript-sdk.md), [Kotlin SDK Behavior](kotlin-sdk.md), and [Swift SDK Behavior](swift-sdk.md).

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

**Used in:** [When Observers Fire](../../best-practices/observers.md#when-observers-fire), [Prefer field-level updates over whole-document rewrites](../../best-practices/dql.md#prefer-field-level-updates-over-whole-document-rewrites).

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

**Used in:** [When Observers Fire](../../best-practices/observers.md#when-observers-fire), [Recording presence in documents](../../best-practices/setup-and-lifecycle.md#recording-presence-in-documents).

### Since SDK 5.1, local writes are coalesced into callbacks about 30 ms apart

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

**Used in:** [When Observers Fire](../../best-practices/observers.md#when-observers-fire), [Backpressure in Flutter](../../best-practices/platforms/flutter.md#backpressure-in-flutter).

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

**Used in:** [When Observers Fire](../../best-practices/observers.md#when-observers-fire).

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

**Used in:** [Keep observer callbacks fast](../../best-practices/observers.md#keep-observer-callbacks-fast).

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

- The observers of `system:data_sync_info` and `system:indexes` were called once, for the first result, on every release. With a connected peer, the observer of `system:data_sync_info` was called a few more times ([An observer of system:data_sync_info was called 3 or 4 times in 40 seconds with an idle peer](#an-observer-of-systemdata_sync_info-was-called-3-or-4-times-in-40-seconds-with-an-idle-peer)).

**Not tested:** other `system:` collections; the observers of `system:system_info` and `system:indexes` while sync runs.

**Used in:** [Monitoring Storage](../../best-practices/deletion-and-storage.md#monitoring-storage), [System Virtual Collections](../system-reference.md#system-virtual-collections), [Changes in SDK 5.2.0](../upgrading.md#changes-in-sdk-520).

### An observer of system:data_sync_info was called 3 or 4 times in 40 seconds with an idle peer

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, four runs each; every run on a release showed the same pattern |
| Setup | Two connected devices that subscribed to the same, empty collection. 3 seconds after they connected, one of them registered an observer of `SELECT * FROM system:data_sync_info` and recorded the time of each callback for 40 seconds, while neither device wrote anything |
| Documentation | Ditto's page on monitoring sync status says that observers of `system:data_sync_info` are called every 500 ms, whether or not the data changed. The virtual collections reference does not list `system:data_sync_info` among the collections whose observers run on a timer, and says that a timer-driven observer is not called when its result has not changed |

| Release | Callbacks in 40 seconds | When |
|---|---|---|
| 5.1.0 | 3 in every run | At registration, 2.0 to 5.0 seconds later, and 27.6 to 27.7 seconds later |
| 5.2.0 | 3 or 4 | At registration, in two runs 0.85 or 2.8 seconds later, and 27.3 seconds later followed by a second callback about 30 ms after it |

- The observer was not called every 500 ms on either release. We think the callback at about 27 seconds is a periodic update between the two devices, the same one that confirms an empty commit ([An empty commit is confirmed only with the next sync exchange](subscriptions-and-replication.md#an-empty-commit-is-confirmed-only-with-the-next-sync-exchange)).

**Not tested:** what the rows contained in each callback; more than one peer; devices that sync changes while the observer runs; longer than 40 seconds.

**Used in:** [Monitoring Sync Status](../../best-practices/sync-and-subscriptions.md#monitoring-sync-status).

## Observers That Write on Several Devices

### Observers on two devices that each write their own value keep writing

| | |
|---|---|
| Observed on | SDK 5.1.0 (six runs) and 5.2.0 (seven runs); the per-device key: three runs each |
| Setup | Two peers in one process, A and B, both subscribed to the collection. A inserted a document with `owner: 'none'`. On each device, an observer of that document wrote the device's own name to `owner` with `UPDATE`, only when the stored value was not already that name. We counted each device's writes in 6 seconds, and those in the last 2 seconds, with three kinds of observer: `SELECT _id, owner`, `SELECT *`, and `SELECT *` whose callback wrote with `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` on every call. A control run had only A's observer. As a fix, each device's `SELECT *` observer wrote `{seenBy: {<its name>: true}}` with `DO UPDATE_LOCAL_DIFF` on every call |
| Documentation | In the JavaScript SDK's type definitions, the `QueryResult` that an observer receives holds the items, the mutated document IDs (described as always empty for an observer), and the commit ID; none of them names the device that made the change |

| Observer | Writes per device in 6 seconds | In the last 2 seconds |
|---|---|---|
| `SELECT _id, owner`, compared before writing | 85 to 87 in 10 of 13 runs; in the other 3 runs (two on 5.2.0, one on 5.1.0), 41 within 2.8 seconds, 9 to 10 within 0.6 seconds, and 4 to 5 within 0.25 seconds, then none | 28 to 29 in 10 of 13 runs; 0 in the other 3 |
| `SELECT *`, compared before writing | 85 to 87 in every run | 28 to 29 |
| `SELECT *`, `DO UPDATE_LOCAL_DIFF` on every call | 169 to 173 statements in every run | 56 to 58 |
| Control: only A's observer | 1 in every run | 0 |
| Fix: `SELECT *`, each device writes its own key of `seenBy` with `DO UPDATE_LOCAL_DIFF` | 2 statements in every run, the last within 43 ms; both keys remained | 0 |

- Each write changed the value that the other device wanted, so it called the other device's observer, whose write called the first one's again. Comparing before writing and `DO UPDATE_LOCAL_DIFF` skip only a write of the value already stored, which was never the case here. Except in the three runs below, the writes stopped only when the observers were cancelled, after which both devices held the same document.
- In the three runs that stopped, one device's name remained, and that device's observer was not called again, so the other device's rule stayed unmet without an error. We think that a write arrived while the device's own write was being coalesced, so that the projected value looked unchanged to its observer (see [Since SDK 5.1, local writes are coalesced into callbacks about 30 ms apart](#since-sdk-51-local-writes-are-coalesced-into-callbacks-about-30-ms-apart)); we did not confirm this.
- About 14 writes a second per device is the round trip of this setup: two peers over loopback TCP, with callbacks about 30 ms apart. Over real networks, each round trip takes longer, so we expect fewer writes a second; we did not test that.
- The commit ID of the result in every observer callback was `null`, so the callback could not tell its own device's writes from the other device's.
- The results were the same on both releases.

**Not tested:** three or more devices; a loop through two collections; devices in separate processes, on real networks, or with different clocks; observers of the Flutter, Kotlin, and Swift SDKs, whose callbacks wait differently (see [Keep observer callbacks fast](../../best-practices/observers.md#keep-observer-callbacks-fast)).

**Used in:** [Checks and Claims across Devices](../../best-practices/data-modeling.md#checks-and-claims-across-devices), [Writing from Observers](../../best-practices/observers.md#writing-from-observers).

### Observers on two devices that write the same value, or one derived from synced data, stop after one or two writes

| | |
|---|---|
| Observed on | SDK 5.1.0 (six runs) and 5.2.0 (seven runs) |
| Setup | The two peers of [Observers on two devices that each write their own value keep writing](#observers-on-two-devices-that-each-write-their-own-value-keep-writing), with a `SELECT *` observer of one document on each device. Same value: A inserted `status: 'new'`, and each observer wrote `status = 'done'`, either only when the stored value differed, or with `DO UPDATE_LOCAL_DIFF` on every call. Derived value: A inserted `items: {a: 2, b: 3}` and `total: 0`; each observer wrote the sum of `items` to `total` when it differed, and after 2 seconds B added `items.c = 4`. We counted each device's writes in 6 seconds |

| Reaction on both devices | Writes per device | Last write |
|---|---|---|
| The same value, compared before writing | 1 | Within 9 ms of the insert |
| The same value, `DO UPDATE_LOCAL_DIFF` on every call | 1 to 2 statements | Within 43 ms |
| A total derived from `items`, compared before writing | 1 to 2: one after the insert, one after B's change | Within 12 ms of each change; both devices held `total: 9` |

- Once a device held the value that its rule produces, its next call wrote nothing, so the other device's observer was not called again. Both devices wrote the same value concurrently, which merged without a conflict.
- The results were the same on both releases.

**Not tested:** a derived value that depends on documents that only some devices hold; the same with concurrent edits of the inputs while the devices are offline.

**Used in:** [Writing from Observers](../../best-practices/observers.md#writing-from-observers).

### A loop on one device calls the observers of the devices that sync the document

| | |
|---|---|
| Observed on | SDK 5.1.0 (six runs) and 5.2.0 (seven runs) |
| Setup | The two peers above. On B, a `SELECT *` observer of one document wrote the value that the document already had on every call, the loop of [Writing the same value from an observer keeps it firing](#writing-the-same-value-from-an-observer-keeps-it-firing). A had a `SELECT *` observer of the same document that did not write. We counted the calls in 6 seconds |

- B wrote 168 to 172 times in 6 seconds, and A's observer was called 169 to 174 times, about 28 times a second, until B's observer was cancelled. Every write synced, although no value changed.
- The results were the same on both releases.

**Not tested:** an observer on A that projects fields (it would not be called for these writes; see [When an observer fires depends on its query](#when-an-observer-fires-depends-on-its-query)); the traffic and battery cost of the loop.

**Used in:** [Writing from Observers](../../best-practices/observers.md#writing-from-observers).

## Differs

### The differs accept only items from Ditto query results, and Kotlin apps do not create one

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each with JavaScript, Flutter, and Kotlin; every run gave the same result. Swift: the module interface of DittoSwift 5.1.0 and 5.2.0 |
| Setup | JavaScript on Node.js 24 and Flutter (`ditto_live`) on macOS, each in a store with two documents: we passed to a new differ the items of a query, then items that Ditto did not produce, a list that mixed a real item with one of those, and an empty list. In JavaScript, the other items were plain objects with a `value` property, plain documents, and an object created with the prototype of a real item; in Flutter, a test double that `implements QueryResultItem`. Kotlin on the Android 16 emulator: we read with reflection the constructors of `DittoDiffer` and `DittoQueryResultItem`, and the public methods of `Ditto`, `DittoStore`, and the file class of `DittoDiffer` that return a `DittoDiffer`. Swift: we read the declarations of `DittoDiffer` and `DittoQueryResultItem` in DittoSwift's module interface (`.swiftinterface`) |
| Documentation | [Reacting to Data Changes](https://docs.ditto.live/sdk/latest/crud/observing-data-changes) (Diffing Results): in Swift, JavaScript, and Flutter, the app creates the differ and passes it the query result items; for Kotlin, "In v5, the differ is owned by the observer — you do not construct one yourself". The page says nothing about other items or test doubles |

| SDK | Items that Ditto did not produce |
|---|---|
| Flutter | `diff()` threw `ArgumentError: Invalid argument(s): List must not contain subtypes of QueryResultItem` for the test double, also when the list held a real item as well |
| JavaScript | `diff()` threw `TypeError: item.deref is not a function` for the plain objects and the plain documents, also when the list held a real item as well, and `Error: Bridging error: QueryResultItem object is not currently registered in this bridge.` for the object with the prototype of a real item |
| Kotlin | No differ to pass them to. `DittoDiffer` and `DittoQueryResultItem` are final classes whose only constructors take types of the SDK's `com.ditto.internal` package, and the only function that returns a `DittoDiffer`, `toFacade`, takes such a type as well. A diff reaches the app as the `DittoDiff` that the observer passes to a handler with two parameters (see [In Kotlin, DittoDiff reports every shifted row as a move](kotlin-sdk.md#in-kotlin-dittodiff-reports-every-shifted-row-as-a-move)) |
| Swift | `DittoQueryResultItem` is a `final` class without a public initializer (`@_hasMissingDesignatedInitializers`), and `DittoDiffer.diff(_:)` takes `[DittoQueryResultItem]`, so other values cannot be passed; the compiler rejects them |

- The items of a query gave the expected diff: the first call reported both documents as insertions. An empty list gave an empty diff.

**Not tested:** compiling a test double in Kotlin or Swift; JavaScript in browsers and React Native; Flutter on iOS and Android.

**Used in:** [Diffing Results](../../best-practices/observers.md#diffing-results), [Testing Observer Lifecycle](../../best-practices/testing.md#testing-observer-lifecycle), [Diffing results in Flutter](../../best-practices/platforms/flutter.md#diffing-results-in-flutter), [Testing in Flutter](../../best-practices/platforms/flutter.md#testing-in-flutter), [Testing in JavaScript](../../best-practices/platforms/javascript.md#testing-in-javascript), [Diffing results in Kotlin](../../best-practices/platforms/kotlin.md#diffing-results-in-kotlin), [Diffing results in Swift](../../best-practices/platforms/swift.md#diffing-results-in-swift), [Testing in Swift](../../best-practices/platforms/swift.md#testing-in-swift).

### Every SDK's differ reports a reorder as a move of each shifted item and compares only two results

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each with Flutter, JavaScript, and Kotlin, and with Swift on macOS and in the iOS simulator; every run gave the same result, on every SDK |
| Setup | Three documents `a`, `b`, and `c` with `rank` 1 to 3, read with `SELECT * FROM items ORDER BY rank`. In Flutter (macOS), JavaScript (Node.js 24 on macOS), and Swift, one differ received the items of the query after each step; in Kotlin (Android 16 emulator), which has no differ that apps create, we recorded the `DittoDiff` that an observer of the same query passed to its handler after each step. The steps: the first result; the same result again (not in Kotlin); `c` moved to the top (`rank = 0`); a field of `a` changed and changed back before the next diff (two statements, in Kotlin one transaction); a field of `b` changed; `a` deleted; and a document `d` inserted at the top |

| Step | Result order | Diff on every SDK |
|---|---|---|
| First result | `a b c` | insertions 0, 1, 2 |
| Same result again | `a b c` | empty |
| `c` moved to the top | `c a b` | updates 0; moves 2→0, 0→1, 1→2 |
| A value changed and changed back | `c a b` | empty |
| A value of `b` changed | `c a b` | updates 2 |
| `a` deleted | `c b` | deletions 1, no moves |
| `d` inserted at the top | `d c b` | insertions 0, no moves |

- A reorder reported a move for every item whose position shifted, not only the item that moved, and an update for the moved item, whose `rank` changed.
- An item that only shifted because another item was deleted or inserted was not reported as a move.
- A value that changed and changed back before the next diff was not reported. In Kotlin, the transaction that did so still produced one callback, with an empty diff.

**Not tested:** larger lists and several reorders at once; Flutter on iOS and Android; JavaScript in browsers.

**Used in:** [Diffing Results](../../best-practices/observers.md#diffing-results).

## Observer Differences between SDK Releases

### On SDK 5.1.0 and 5.2.0, an observer did not re-run its query after writes to another collection

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result. The `system:metrics` counter: SDK 5.2.0, two runs |
| Setup | One device without sync. (1) An observer of `SELECT * FROM products` over one document, with every request recorded in `system:request_history` (`DQL_REQUEST_HISTORY_QUALIFIERS = {'threshold': 0}`): 50 single-document `INSERT` statements into `orders`, awaited one at a time, then 50 into `products`; we counted the observer's query in the history and the callbacks. (2) The same observer over 20,000 documents: the process CPU time of 50 such `INSERT` statements into another collection with and without the observer, and of 50 into the observed collection |
| Documentation | The 5.2.0 release notes say: "Store observers no longer re-run their queries after writes to collections they don't observe" (QE-1116) |

| Measurement | 5.0.3 | 5.1.0 | 5.2.0 |
|---|---|---|---|
| Observer runs after 50 writes to another collection | 14 to 15, without a callback | 0 | 0 |
| Observer runs after 50 writes to the observed collection | 15 to 16, with 13 to 15 callbacks | 4, with 4 callbacks | 4, with 4 callbacks |
| CPU time of 50 writes to another collection, with the observer of 20,000 documents | 265 to 308 ms | 73 to 105 ms | 106 to 129 ms |
| The same, without an observer | 50 to 121 ms | 66 to 103 ms | 79 to 132 ms |
| CPU time of 50 writes to the observed collection | 1,068 to 1,175 ms, 13 to 14 callbacks | 600 to 614 ms, 5 callbacks | 562 to 592 ms, 5 callbacks |

- On 5.0.3, the observer ran its query again after writes to another collection, without calling back, and the writes used about three times as much CPU time. On 5.1.0 and 5.2.0, it did not run: the issue that the 5.2.0 release notes list as fixed did not occur on 5.1.0 in this test.
- Writes to the observed collection ran the query about every third write on 5.0.3, and 4 or 5 times for all 50 writes on 5.1.0 and 5.2.0, which coalesce changes (see [Since SDK 5.1, local writes are coalesced into callbacks about 30 ms apart](#since-sdk-51-local-writes-are-coalesced-into-callbacks-about-30-ms-apart)).
- On 5.2.0, `system:metrics` agreed: `ditto.query.requests` did not grow with the 50 writes to another collection, and grew by 4 with the 50 writes to the observed collection. 5.1.0 has no query metrics.

**Not tested:** observers of joins or of several collections; changes that arrive through sync; writes in transactions; whether other conditions make 5.1.0 run an observer after writes to another collection.

**Used in:** [When Observers Fire](../../best-practices/observers.md#when-observers-fire).

### On SDK 5.2.0, observer rows include _id only when it is projected, except with Flutter's registerObserver

| | |
|---|---|
| Observed on | JavaScript: SDK 5.0.3, 5.1.0, and 5.2.0, three runs each (the join: 5.1.0 and 5.2.0). Flutter, Kotlin, and Swift, and JavaScript's `registerObserverWithSignalNext`: SDK 5.1.0 and 5.2.0, three runs each. Every run gave the same result |
| Setup | An observer of `SELECT name FROM items ORDER BY rank`, and an observer of a join, `SELECT o._id AS orderId, o.total, c.name AS customerName FROM orders o JOIN customers c ...`. We compared their rows with the result of `execute()`, and passed the rows to `Differ` after two documents had changed places. We then ran both queries, with the join `ON c._id = o.customerId`, with every observer API of Flutter on macOS (`registerObserver` with `onChange` and with `changes`, `registerObserverV2`, and `registerObserverWithSignalNext`), with `registerObserver` of Kotlin on the Android 16 emulator and of Swift on macOS, and with JavaScript's `registerObserverWithSignalNext`, and read the keys of the first row |
| Documentation | The SDK 5.2.0 release notes say that observers with a projection no longer retain the previous result (#QE-1093), and also that "Observer behavior and query results are unchanged". They do not mention the change below |

| Rows of | 5.0.3 | 5.1.0 | 5.2.0 |
|---|---|---|---|
| The observer of `SELECT name FROM items ORDER BY rank` | `{"_id": "a", "name": "A"}` | `{"_id": "a", "name": "A"}` | `{"name": "A"}` |
| `execute()` of the same query | No `_id` | No `_id` | No `_id` |
| The join observer | — | Composite `_id` (`{"c": "c1", "o": "o1"}`) | No `_id` |

| Observer API on 5.2.0 | `SELECT name ...` | The join |
|---|---|---|
| JavaScript `registerObserver` and `registerObserverWithSignalNext` | No `_id` | No `_id` |
| Kotlin `registerObserver` | No `_id` | No `_id` |
| Swift `registerObserver` | No `_id` | No `_id` |
| Flutter `registerObserverV2` and `registerObserverWithSignalNext` | No `_id` | No `_id` |
| Flutter `registerObserver`, with `onChange` and with `changes` | `_id` | Composite `_id` (`{c: c1, o: o1}`) |

- On 5.1.0, every observer API that we ran delivered the `_id`, composite in the join. `execute()` returned no `_id` for either query on every SDK and release.
- As a result, on 5.2.0, the JavaScript `Differ` reported the reordering of two rows as `updates: [0, 1]` and `moves: []`, while 5.0.3 and 5.1.0 reported two moves. Without `_id`, `Differ` cannot tell the rows apart, so animations and other processing of the differences go wrong.
- In a join, `SELECT _id ...` returns the composite ID (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)).

**Not tested:** the differs of Flutter, Kotlin, and Swift with rows without `_id`; the other observer APIs of Kotlin (`observe`) and Swift; Flutter on iOS and Android.

**Used in:** [Diffing Results](../../best-practices/observers.md#diffing-results), [Joins in observers](../../best-practices/dql.md#joins-in-observers), [Diffing results in Flutter](../../best-practices/platforms/flutter.md#diffing-results-in-flutter), [Behavior Specific to the Flutter SDK](../../best-practices/platforms/flutter.md#behavior-specific-to-the-flutter-sdk), [Diffing results in Kotlin](../../best-practices/platforms/kotlin.md#diffing-results-in-kotlin), [Diffing results in Swift](../../best-practices/platforms/swift.md#diffing-results-in-swift), [Changes in SDK 5.2.0](../upgrading.md#changes-in-sdk-520).

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

**Used in:** [Known Issues in SDK 5.1.0](../upgrading.md#known-issues-in-sdk-510), [Observer Lifecycle](../../best-practices/observers.md#observer-lifecycle).
