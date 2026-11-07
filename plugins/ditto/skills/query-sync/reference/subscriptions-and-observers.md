# Subscriptions and Observers Reference (SDK 5.2)

Detailed rules behind the subscription and observer patterns in [SKILL.md](../SKILL.md). Extracted from the guide sections `§ Sync and Subscriptions` and `§ Observing Changes`.

## Table of Contents

- [Subscription Rules](#subscription-rules)
- [Subscription Scope](#subscription-scope)
- [Subscription Lifecycle](#subscription-lifecycle)
- [When Data Does Not Sync](#when-data-does-not-sync)
- [Observer APIs](#observer-apis)
- [Observer Lifecycle](#observer-lifecycle)
- [Backpressure Behavior](#backpressure-behavior)
- [Differ](#differ)

---

## Subscription Rules

A subscription query selects whole documents from one collection: `SELECT * FROM <collection> [WHERE <condition>]`. The SDK validates it when `registerSubscription` is called and rejects the features below with an error, even before sync starts. Subscriptions on `system:` collections (such as `system:data_sync_info`) are accepted but have no effect.

| Query feature | Accepted? | Error message |
|---|---|---|
| `SELECT * FROM orders` | ✅ | — |
| `SELECT * FROM orders WHERE storeId = :storeId` | ✅ | — |
| Projection or aggregate | ❌ | `Unsupported feature: A projection other than wildcard (*)` |
| `DISTINCT` | ❌ | `Unsupported feature: DISTINCT` |
| `GROUP BY` | ❌ | `Unsupported feature: Grouping` |
| `JOIN` | ❌ | `Unsupported feature: Joining` |
| `USE IDS` | ❌ | `Unsupported feature: USE IDS` |
| `LIMIT`, `ORDER BY` | ❌ (while `DQL_RESTRICT_SUBSCRIPTIONS` has its default value `true`) | `Unsupported feature: Limit or Order by` |
| Non-`SELECT` statements | ❌ | `Unsupported feature: non-SELECT statement in sync subscription` |

Consequences:
- Subscriptions sync whole documents. To reduce what a device receives, split rarely needed data into another collection or move binary data into attachments.
- Subscriptions cannot join. If a child collection must be filtered by a key on its parent (for example `orderItems` by `storeId`), copy the key into the child documents.
- `WHERE` follows the rules of a local query: `!=` and `NOT IN` drop documents where the field is missing or `null`, so another device never receives them (in testing with SDK 5.1.0 and 5.2.0). Add `OR field IS MISSING` when older documents may lack the field.
- Do not use `clock()` in a subscription: each sending device evaluates it with its own clock, only when a document is written and when a new subscription arrives, so documents that enter the window as time passes are not sent (in testing with SDK 5.1.0 and 5.2.0, not after a reconnect or a restart either). Pass a boundary as a parameter (`§ Date and Time`).
- `DQL_RESTRICT_SUBSCRIPTIONS` (default `true`) controls `LIMIT`/`ORDER BY`. Setting it to `false` allows only those two and creates stateful subscriptions that force re-evaluation whenever documents cross the limit boundary. Keep the default; if you must use one, do not filter or sort on mutable fields together with `LIMIT`. On SDK 5.1.0 and 5.2.0, `LIMIT` bounds only the initial download. Afterwards, every new or changed document that matches the `WHERE` is synced, including documents that never ranked inside the window, and documents already received stay. The setting is checked only on the subscribing device.

## Subscription Scope

| | Too broad | Too narrow |
|---|---|---|
| Symptoms | High storage, long initial sync, battery and bandwidth drain | Missing or late data on devices not directly connected to the source |
| Typical cause | Unfiltered subscriptions on large collections | Filters on frequently changing fields; relays subscribing to less than the devices behind them |
| Fix | Filter by stable partition keys (tenant, store, region) | Subscribe to the full partition; filter further locally |

- Use the same subscriptions on peers in the same role so any of them can serve the others.
- An intermediate device relays only documents in its local store: give relay or hub devices at least the subscriptions of the devices behind them.
- A device that subscribes to nothing relays nothing; a second relay for redundancy needs the same subscriptions (updates kept flowing through the remaining relay when one stopped, in testing, although the first update after a relay stopped responding took up to about 4 s in some runs). Carriers work too: a device moving between sites that never connect carries the documents and deletions that match its own subscriptions, whatever the destination subscribes to.
- A device accepts a limited number of connections per transport; for TCP, 6 by default (`MESH_CHOOSER_MAX_WLAN_CONNECTIONS`). In testing with SDK 5.1.0 and 5.2.0, extra clients of a TCP hub got no data and no error, only a `WARN ... at capacity` log line (on 5.2.0, connections the device opened itself also count when it decides whether to accept one, so a hub that also dials out admits fewer clients; outgoing connections are not limited). On a hub with more clients, raise the limit so that it is in effect before `ditto.sync.start()`: in `DittoConfig.systemParameters` (SDK 5.2+), or on SDK 5.1 with `ALTER SYSTEM SET MESH_CHOOSER_MAX_WLAN_CONNECTIONS = <n>` after every `Ditto.open`. Raised before sync started, it admitted all eight test clients; raised after sync had started, it did not admit already rejected clients within 60 s. Guide: `§ Transport Configuration`.
- Keep predicates flat (`storeId = :storeId`); deeply nested `AND`/`OR` trees and deep paths add server-side processing, and overly complex subscription queries are a likely cause of `503 Service Unavailable` from Ditto Server.
- Do not filter subscriptions on fields that change often (`status`, `assignee`) and expect every device to follow each document through all of its states. Soft-delete flags are a special case (below). On SDK 5.1.0 and 5.2.0, a document that stops matching becomes a **frozen copy**. The device receives the change that made it stop matching, and then no further edits and not even its deletion. Local queries keep showing it, so filter it out locally and evict it when it is no longer needed. When it matches again, it arrives in its latest state.
- Soft delete: keep soft-deleted documents in the subscriptions of devices that relay data, and hide them locally with `coalesce(isDeleted, false) = false`. A device that subscribes only to active documents still receives the flag and a restore for documents it holds (SDK 5.1.0 and 5.2.0), but it cannot relay the flag for documents it did not already hold, and a `DELETE` of a flagged document never reaches it. Two designs meet this requirement:
  - **Variant A** (whole-collection or whole-partition subscription): simplest; devices cannot `EVICT` old soft-deleted documents because they still match the subscription, so cleanup is a `DELETE` after the retention period, run on the Ditto Server or by another authorized peer, that syncs to every device.
  - **Variant B** (retention-window subscription, `coalesce(isDeleted, false) = false OR deletedAt >= :cutoff`): devices evict documents deleted before the cutoff; the subscription is re-registered when the cutoff moves (at most about once a day). Choose a window longer than the longest expected offline period, so that other devices can still relay the flag.
  - See `§ Soft delete, subscriptions, and cleanup`.
- An unfiltered subscription is acceptable only for a small reference-data collection that every device needs.

## Subscription Lifecycle

- Avoid changing subscriptions more often than about every 15 minutes: each change makes peers re-evaluate which documents they must send to the device. The guideline is about that re-evaluation work, not data transfer: documents already held are not downloaded again, and an identical second registration transferred nothing in our testing, but data keeps syncing until **every** copy of it is cancelled. In testing with a Small Peer hub (Ditto Server was not tested), each registration made the hub read the whole collection again, in proportion to its size; indexes and `_id` filters did not shorten it, and each further subscription of the same device cost a little more (with 50,000 documents: about 0.1 s of hub CPU for the first, 0.2 s for the tenth). Register the long-lived set together, before `sync.start()` where possible (about a sixth of the cost); reconnecting cost almost nothing, and since SDK 5.1, so did cancelling.
- Register when data becomes relevant (app start, login, entering a workspace) in an app- or feature-level service; keep every subscription object.
- Re-register only when the set of data the device needs changes (switching store or tenant). Search, tabs, filters, and sort orders change observers.
- Subscriptions stay active until released (`cancel()`, `close()` in Kotlin) or until Ditto is closed. Always release them explicitly; do not rely on garbage collection to cancel them.
- Subscriptions are not persisted: register them again every time Ditto opens. Until then, the device sends its own changes but receives neither updates nor new documents from other peers, without an error (in testing with SDK 5.1.0 and 5.2.0; `§ Subscription Lifecycle`).
- In JavaScript, subscriptions and observers whose objects were garbage-collected kept syncing and calling back (in testing); cancel them through the entries of `ditto.sync.subscriptions` and `ditto.store.observers`, and keep your own references.
- While a device receives a large initial sync, its other sync waits: changes for existing subscriptions and its own writes to others (30,000 documents held them about 2 s in testing with SDK 5.1.0 and 5.2.0; other devices were unaffected). Splitting the subscription only helps when the parts are registered one after another; the whole download then takes about 2.5 times as long.
- The receiver shows an initial sync all at once, not document by document (in testing with SDK 5.1.0 and 5.2.0, 20,000 documents appeared together after about 2.4 s; local reads still returned within 2 ms). An initial sync interrupted with `sync.stop()` resumes where it stopped. Show that data is downloading, not a document count.
- The number of subscriptions did not change what was transferred: 300 subscriptions by `_id`, one by `_id IN :ids`, and one for the whole collection of the same documents cost the same time and bytes (in testing with SDK 5.1.0 and 5.2.0). Keep subscriptions few to keep them manageable, not to save bandwidth.
- Cancelling does not delete local data; documents stop receiving updates, new documents, and deletions from other peers. A device receives the union of its subscriptions, so documents that another active subscription matches keep syncing. To free storage, cancel every subscription that matches the documents (including overlapping ones), then `EVICT`; a document that another active subscription still matches is synced back. Data that was already being transferred can still arrive after cancelling; if the device must not keep it, run the eviction again later (for example, on the next app start or in a periodic cleanup).
- `sync.stop()` pauses all subscriptions; `start()` resumes them. Closing Ditto cancels them; releasing them afterwards is a no-op.
- `sync.subscriptions` is for debugging: read the query string and whether a subscription is cancelled only; what the SDKs return for its arguments differs.

> **Note (SDK 5.1.0 and 5.2.0):** In Flutter, do not read `queryArguments`, `queryArgumentsJsonString`, or `queryArgumentsCborBytes` from the elements of `ditto.sync.subscriptions`; for subscriptions registered without arguments this ended the app in testing, on macOS and iOS (the other SDKs report no arguments instead: `null` or `undefined` in JavaScript, `null` in Kotlin, and `nil` in Swift). Keep your own references when you need the arguments.

Switching stores: cancel the old store's subscriptions, evict its documents, then subscribe to the new store (`§ Cancelling subscriptions and local data`; services in `retention-service` and `subscription-lifecycle-good` in the Skills' `examples/<sdk>/`):

<!-- subscription -->
```sql
-- After cancelling the old subscriptions:
-- Arguments: {"storeId": "store-2"}
EVICT FROM orders WHERE storeId != :storeId

-- Then the new subscription:
-- Arguments: {"storeId": "store-2"}
SELECT * FROM orders WHERE storeId = :storeId
```

## When Data Does Not Sync

Documents that exist on one device but do not appear on another, stop updating, arrive late, or come back after eviction. Guide: `§ When Data Does Not Sync`; for statements that throw or return nothing on local data, `§ When a Statement Fails or Returns Nothing`.

| Symptom | Common cause | Guide |
|---|---|---|
| No peer appears | Transport off or missing permission; different Database IDs | `§ Diagnosing transport problems (SDK 5.1+)`, `§ DittoConfig` |
| `sync.start()` throws, or nothing syncs after logging in again | No expiration handler or license token; `logout()` stopped sync | `§ Starting and Stopping Sync`, `§ Authentication` |
| Some clients of a TCP hub get nothing, no error | Hub connection limit for the transport | `§ Transport Configuration` |
| Query or observer empty, another device holds the data | No subscription on this device matches | `§ Where Queries Run` |
| Documents with the field missing or `null` never arrive | Subscription filters with `!=` or `NOT IN` | `§ Subscription Rules` | <!-- lint-ignore -->
| Data arrives, the screen shows none of it | The local query filters it out (`ANY ... SATISFIES` over a parameter) | `§ When a Statement Fails or Returns Nothing` | <!-- lint-ignore -->
| Old data and no new documents after a restart | Subscriptions not registered again after opening Ditto | `§ Subscription Lifecycle` |
| A document stops updating; its deletion never arrives | It left the subscription (frozen copy), or the subscription was cancelled | `§ Multi-hop relay`, `§ Cancelling subscriptions and local data` |
| Documents entering a time window do not arrive | `clock()` in the subscription | `§ Date and Time` |
| Devices behind another device miss data | The relay subscribes to less, or may not write the documents | `§ Multi-hop relay`, `§ Write authority and peer-to-peer relaying` |
| Part of a transaction appears | Relay with narrower subscriptions | `§ Transactions and Sync` |
| A collection never reaches Ditto Server or other devices | Sync scope on the sending device | `§ Sync Scopes` |
| A matching document never reaches the device | Its read permissions exclude it | `§ Permissions` |
| Other changes stall right after login | A large initial sync on this device | `§ Subscription Lifecycle` |
| Evicted documents come back | An active subscription still matches them | `§ Cancelling subscriptions and local data` |
| A write right before `close()` or `sync.stop()` never arrived | Neither waits for unsent changes | `§ Resource Cleanup and Shutdown` |
| `"Connected"` after the peer left; a write stays unconfirmed | Status lags behind disconnections; an empty commit is confirmed only with the next exchange | `§ Monitoring Sync Status` |

## Observer APIs

Every SDK accepts only `SELECT` for observers and takes parameters as arguments. Observers never cause data to sync.

| SDK | Default observer | Backpressure for slow work (SDK 5.1+) | Release |
|---|---|---|---|
| Flutter | `registerObserver(query, arguments:)` + `changes`; no backpressure | `registerObserverV2` (automatic, follows pause/resume of `changes`: consume it with `await for`, since `listen(async ...)` does not pause it) or `registerObserverWithSignalNext` (manual), both (Experimental) | `cancel()` |
| JavaScript | `registerObserver(query, handler, args)` signals when a synchronous handler returns; `async` handlers are not awaited | `registerObserverWithSignalNext(query, (result, signalNext) => {...}, args)` | `cancel()` |
| Kotlin | `registerObserver(query, args) { result -> }` with a suspending handler, or `observe(...)` returning a `Flow` | The handler or the collector suspends; `collect(query, args) { }`; `.conflate()` for slow collectors; no `signalNext` | `close()` |
| Swift | `registerObserver(query:arguments:deliverOn:handler:)` signals when the handler returns; main queue by default | `handlerWithSignalNext:`; `deliverOn:` to move heavy work off the main queue | `cancel()` |

| Situation | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Updating UI state | `registerObserver` + `changes` | `registerObserver`, synchronous handler | `observe(...)` in the owner's scope | `registerObserver(... handler:)` |
| Slow or `async` work per update | `registerObserverV2` + `await for` | `registerObserverWithSignalNext` | Suspending handler, or `collect` | `handlerWithSignalNext:` |
| Work that completes elsewhere (animation, external callback) | `registerObserverWithSignalNext` | `registerObserverWithSignalNext` | Suspend until done | `handlerWithSignalNext:` |
| Only the latest state matters | `registerObserverV2` with a slow consumer, or throttle | Throttle | `observe(...).conflate()` | Throttle |

The experimental APIs may change in a future release. Each SDK page has the code: *Store Observers*, *Observer lifecycle*, and *Backpressure in <SDK>* (`§ Choosing an observer API`). Do not port one SDK's observer code to another one-to-one.

## Observer Lifecycle

Rules for every SDK (`§ Observer Lifecycle`):
- Give each observer one owner (screen, view model, service); register it when the owner starts, never in render code; release it when the owner goes away. Do not rely on garbage collection or `close()`: in JavaScript (in testing), garbage-collected observers kept running.
- Copy plain values out of results; do not keep result or row objects.
- Observe a list once and pass values down; on devices that still run SDK 5.1.0, stay well below about 60 observers in total.
- Each SDK can list the uncancelled observers (`ditto.store.observers`); a count that keeps growing while the user moves between screens points to an observer that is never released.

### Flutter observer lifecycle

| Behavior (`registerObserver`) | Consequence |
|---|---|
| Without `onChange`, querying starts when `changes` is first listened to | A registered but unlistened observer does no work but holds resources until cancelled |
| With `onChange`, the observer starts immediately | Results go to `onChange` and are also queued in `changes` |
| `changes` is single-subscription | A second `listen()` throws `StateError`, even after the first was cancelled; a `StreamBuilder` works if it stays mounted for the observer's lifetime |
| Cancelling the `StreamSubscription` does not cancel a `StoreObserver` | Always call `observer.cancel()` too |
| `observer.cancel()` closes `changes` | A pending `await for` ends |
| Cancelling the `StreamSubscription` of a `StoreObserverV2` (`registerObserverV2` or `registerObserverWithSignalNext`) also cancels the observer | Leaving an `await for` loop over `changes` does the same |
| `await ditto.close()` marks observers cancelled but does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2` | Cancel observers explicitly before closing |
| `ditto.store.observers` (SDK 5.2+) lists the uncancelled observers from `registerObserver` (not `registerObserverV2` or `registerObserverWithSignalNext`) | |

> **Note (SDK 5.1.0 and 5.2.0):** With `onChange` and an unconsumed `changes` stream, every delivered result stays in memory for the observer's lifetime, so memory use grows with every update. The same applies to `registerObserverV2`, which starts observing as soon as it is registered, with or without `onChange`: listen to its `changes` right after registering it. Register without `onChange` and consume `changes`; if `onChange` is required, also drain the stream.

The lifecycle in JavaScript, Kotlin, and Swift (what the release call does, what happens to a handle that is no longer referenced, what `close()` does): *Observer lifecycle in <SDK>* on each SDK page.

Callback rules for every SDK:
- Default observers without backpressure (Flutter `registerObserver`, JavaScript `registerObserver` with an `async` handler) never wait for your work: keep callbacks synchronous and short (copy values, map to models, update UI state); move heavy computation off the UI thread.
- Do not wait for network, file, or database work in a default observer callback; do not write to the observed collection without a guard.
- An observer does not re-run its query after writes to collections it does not observe: in testing with SDK 5.1.0 and 5.2.0, 50 writes to another collection ran no observer query (SDK 5.0.3 re-ran it after about every third write), although the 5.2.0 release notes list this as a fix. According to the same release notes, observers also hold less memory between updates in 5.2. Splitting observers by collection therefore costs little (`§ On SDK 5.1.0 and 5.2.0, an observer did not re-run its query after writes to another collection`).
- Changes that arrive through sync are delivered in batches: expect fewer callbacks than remote writes (a remote transaction arrives as one callback), and do not count or log changes through callbacks. Local writes are batched too: 50 awaited writes reached an observer on the same device in 4 or 5 callbacks (in testing with SDK 5.1.0 and 5.2.0), and a local transaction produced one callback after its commit.
- How often observers on `system:data_sync_info` fire varies: Ditto's sync status page describes a callback every 500 ms, while its virtual collections reference does not list the collection as timer-driven, and in testing with SDK 5.1.0 and 5.2.0 an observer with one idle peer was called 3 or 4 times in 40 seconds. Write code that works with either behavior: use one small observer and update the UI only when the derived value changes. See `§ Monitoring Sync Status`.
- With a state management library, let one store, provider, or view model own each observer and release it in its dispose hook. Each result creates new value objects, so map rows to immutable models that compare by content if you rely on equality to skip updates.

## Backpressure Behavior

Flutter `registerObserverV2` (Experimental):
- Readiness is signalled automatically after each result is added to `changes`; `await for` pauses the subscription while the loop body runs.
- While paused, delivery stops after the update that arrived at the pause; on resume, that update and the latest state are delivered and intermediate states are merged.
- Leaving the loop cancels the stream subscription, which also cancels the observer. `observer.cancel()` ends the loop; `ditto.close()` does not, so cancel the observer before closing.
- `signalNext()` has no effect.

`registerObserverWithSignalNext` (Flutter and JavaScript; Swift `handlerWithSignalNext:`):
- Delivers one result, then waits for `signalNext()`. Without it, updates stop.
- Call `signalNext()` in `finally` (or `defer`) so errors do not stop updates.
- Flutter: do not pause/resume its `changes` stream (the SDK logs a warning); its `onChange` receives `signalNext` as the second parameter, but results are also queued in `changes`, so consume `changes` and call `observer.signalNext()` instead.

Kotlin has no `signalNext`: the observer waits for the suspending handler, and `observe(...)` for the `Flow` collector.

## Differ

| Field | Contents |
|---|---|
| Insertions | Indexes in the new list of added items |
| Deletions | Indexes in the old list of removed items |
| Updates | Indexes in the new list of changed items |
| Moves | Pairs of an old and a new index |

`Differ` in Flutter and JavaScript, `DittoDiffer` in Swift; in Kotlin, the observer owns the differ and passes a `DittoDiff` to a two-parameter handler (apps do not create a `DittoDiffer`). An observer delivers the full result every time. A list keyed by `_id` does not need a differ; use it for an animated list or for processing only new items.

- The first diff reports every item as inserted.
- Identity is `_id`, so project `_id` in a diffed query: on SDK 5.2.0 (JavaScript, in testing), rows of a query without `_id` had none, and `Differ` reported a reordering as updates. Values are compared deeply, and only two successive results are compared: a value that changed and changed back is not an update, and moving one item to the top of a list reports a move for every item whose position shifted (JavaScript `Differ`, in testing).
- The differ keeps the previous result and is expensive: bound the query (`LIMIT`) and debounce large or busy results.
- It does not return old items; keep previous values or IDs yourself.
- Only items produced by Ditto are accepted: in testing with SDK 5.1.0 and 5.2.0, Flutter's test doubles threw `ArgumentError` and JavaScript's plain objects `TypeError`, and Swift's `DittoQueryResultItem` has no public initializer (`§ The differs accept only items from Ditto query results, and Kotlin apps do not create one`). Flutter's `diff()` takes `result.items.toList()`.
- For an animated list, apply removals in descending old-index order and insertions in ascending new-index order; treat moves as removal plus insertion. See `observer-differ` in `../examples/<sdk>/`.
