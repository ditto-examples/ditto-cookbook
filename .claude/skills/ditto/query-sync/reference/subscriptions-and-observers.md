# Subscriptions and Observers Reference (SDK 5.1)

Detailed rules behind the subscription and observer patterns in [SKILL.md](../SKILL.md). Extracted from the guide sections [Sync and Subscriptions](../../../../guides/best-practices/ditto.md#sync-and-subscriptions) and [Observing Changes](../../../../guides/best-practices/ditto.md#observing-changes).

## Table of Contents

- [Subscription Rules](#subscription-rules)
- [Subscription Scope](#subscription-scope)
- [Subscription Lifecycle](#subscription-lifecycle)
- [Observer APIs](#observer-apis)
- [Observer Lifecycle](#observer-lifecycle)
- [Backpressure Behavior](#backpressure-behavior)
- [Other Platforms](#other-platforms)
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
- `DQL_RESTRICT_SUBSCRIPTIONS` (default `true`) controls `LIMIT`/`ORDER BY`. Setting it to `false` allows only those two and creates stateful subscriptions that force re-evaluation whenever documents cross the limit boundary. Keep the default; if you must use one, do not filter or sort on mutable fields together with `LIMIT`.

## Subscription Scope

| | Too broad | Too narrow |
|---|---|---|
| Symptoms | High storage, long initial sync, battery and bandwidth drain | Missing or late data on devices not directly connected to the source |
| Typical cause | Unfiltered subscriptions on large collections | Filters on frequently changing fields; relays subscribing to less than the devices behind them |
| Fix | Filter by stable partition keys (tenant, store, region) | Subscribe to the full partition; filter further locally |

- Use the same subscriptions on peers in the same role so any of them can serve the others.
- An intermediate device relays only documents in its local store: give relay or hub devices at least the subscriptions of the devices behind them.
- Keep predicates flat (`storeId = :storeId`); deeply nested `AND`/`OR` trees and deep paths add server-side processing, and overly complex subscription queries are a likely cause of `503 Service Unavailable` from Ditto Server.
- Do not filter subscriptions on fields that change often (`status`, `assignee`) and expect every device to follow each document through all of its states. Soft-delete flags are a special case (below).
- Soft delete: keep soft-deleted documents inside the subscription at least until every device has received the flag, and hide them locally with `coalesce(isDeleted, false) = false`. Two designs meet this requirement:
  - **Variant A** (whole-collection or whole-partition subscription): simplest; devices cannot `EVICT` old soft-deleted documents because they still match the subscription, so cleanup is a `DELETE` after the retention period, run on the Ditto Server or by another authorized peer, that syncs to every device.
  - **Variant B** (retention-window subscription, `coalesce(isDeleted, false) = false OR deletedAt >= :cutoff`): devices evict documents deleted before the cutoff; the subscription is re-registered when the cutoff moves (at most about once a day). Choose a window longer than the longest expected offline period.
  - See [Soft delete, subscriptions, and cleanup](../../../../guides/best-practices/ditto.md#soft-delete-subscriptions-and-cleanup).
- An unfiltered subscription is acceptable only for a small reference-data collection that every device needs.

## Subscription Lifecycle

- Avoid changing subscriptions more often than about every 15 minutes. Each change makes peers re-evaluate what they owe the device and can interrupt transfers.
- Register when data becomes relevant (app start, login, entering a workspace) in an app- or feature-level service; keep every `SyncSubscription` reference.
- Re-register only when the set of data the device needs changes (switching store or tenant). Search, tabs, filters, and sort orders change observers.
- Subscriptions stay active until `cancel()` or `ditto.close()`. Always release them explicitly; do not rely on garbage collection to cancel them.
- Cancelling does not delete local data; documents stop receiving updates. To free storage, cancel first, then `EVICT`. Data that was already being transferred can still arrive after cancelling; if the device must not keep it, run the eviction again later (for example, on the next app start or in a periodic cleanup).
- `ditto.sync.stop()` pauses all subscriptions; `start()` resumes them. `await ditto.close()` marks them cancelled; `cancel()` afterwards is a no-op.
- `ditto.sync.subscriptions` is for debugging: read `queryString` and `isCancelled` only.

> **Note (SDK 5.1.0):** Do not read `queryArguments` or `queryArgumentsJsonString` from the elements of `ditto.sync.subscriptions`; for subscriptions registered without arguments this can terminate the app. Keep your own references when you need the arguments.

```dart
// ✅ GOOD: Switching stores: cancel, evict the old store's data, subscribe again.
Future<List<SyncSubscription>> switchStore(
  Ditto ditto,
  List<SyncSubscription> current,
  String newStoreId,
) async {
  for (final subscription in current) {
    subscription.cancel();
  }
  await ditto.store.execute(
    'EVICT FROM orders WHERE storeId != :storeId',
    arguments: {'storeId': newStoreId},
  );
  return [
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': newStoreId},
    ),
  ];
}
```

## Observer APIs

| API | Status | Returns | Backpressure | Use for |
|---|---|---|---|---|
| `registerObserver` | Stable | `StoreObserver` | None | UI updates and fast synchronous work (default) |
| `registerObserverV2` | (Experimental) (SDK 5.1+) | `StoreObserverV2` | Automatic: follows pause/resume of `changes` | Slow or async work with `await for` |
| `registerObserverWithSignalNext` | (Experimental) (SDK 5.1+) | `StoreObserverV2` | Manual: `signalNext()` | Work that completes elsewhere |

All three accept only `SELECT` and take parameters through `arguments:`. Observers never cause data to sync.

| Situation | Recommended API |
|---|---|
| Updating widgets from a query result | `registerObserver` + `changes` |
| Slow or `async` work per update, expressible as a loop | `registerObserverV2` + `await for` |
| Work for an update finishes in another place (animation, external callback) | `registerObserverWithSignalNext` |
| Very frequent updates where only the latest state matters | `registerObserverV2` with a slow consumer, or a throttled `registerObserver` listener |

The experimental APIs may change in a future release; the stable `registerObserver` remains the default for UI code.

## Observer Lifecycle

| Behavior (`registerObserver`) | Consequence |
|---|---|
| Without `onChange`, querying starts when `changes` is first listened to | A registered but unlistened observer does no work but holds resources until cancelled |
| With `onChange`, the observer starts immediately | Results go to `onChange` and are also queued in `changes` |
| `changes` is single-subscription | A second `listen()` throws `StateError`, even after the first was cancelled |
| Cancelling the `StreamSubscription` does not cancel a `StoreObserver` | Always call `observer.cancel()` too |
| `observer.cancel()` closes `changes` | A pending `await for` ends |
| `await ditto.close()` marks observers cancelled but does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2` | Cancel observers explicitly before closing |
| With `onChange`, events emitted before the first listener attaches are buffered | Listen right after registering |

> **Note (SDK 5.1.0):** With `onChange` and an unconsumed `changes` stream, every delivered result stays in memory for the observer's lifetime, so memory use grows with every update. The same applies to `registerObserverV2`, which starts observing as soon as it is registered, with or without `onChange`: listen to its `changes` right after registering it. Register without `onChange` and consume `changes`; if `onChange` is required, also drain the stream.

Callback rules:
- `registerObserver` has no backpressure: it never waits for your code, and pausing its stream only queues results.
- Keep listeners synchronous: copy values, map to models, call `setState`. Move heavy computation off the UI isolate (for example `compute()` on copied values).
- Do not `await` network, file, or database work in a `registerObserver` listener; do not write to the observed collection without a guard.
- Observers on `system:data_sync_info` fire every 500 ms even without changes: use one small observer and rebuild only when the derived value changes. See [Monitoring Sync Status](../../../../guides/best-practices/ditto.md#monitoring-sync-status).
- With state management libraries, let one provider or controller own each observer and cancel it in the provider's dispose hook. `item.value` creates a new `Map` per result, so map rows to immutable models with `==` if you rely on equality to skip rebuilds.

## Backpressure Behavior

`registerObserverV2` (Experimental):
- Readiness is signalled automatically after each result is added to `changes`; `await for` pauses the subscription while the loop body runs.
- While paused, delivery stops after the update that arrived at the pause; on resume, that update and the latest state are delivered and intermediate states are merged.
- Leaving the loop cancels the stream subscription, which also cancels the observer. `observer.cancel()` ends the loop; `ditto.close()` does not, so cancel the observer before closing.
- `signalNext()` has no effect.

`registerObserverWithSignalNext` (Experimental):
- Delivers one result, then waits for `signalNext()` (callback parameter or `observer.signalNext()`). Without it, updates stop.
- Call `signalNext()` in `finally` so errors do not stop updates.
- Do not pause/resume its `changes` stream; the SDK logs a warning.
- Its `onChange` receives `signalNext` as the second parameter, but results are also queued in `changes`; consume `changes` and call `observer.signalNext()` instead.

## Other Platforms

| Platform | Default observer | Backpressure |
|---|---|---|
| Flutter | `registerObserver(query, arguments:)` + `changes` | `registerObserverV2` or `registerObserverWithSignalNext` (Experimental) |
| JavaScript | `registerObserver(query, handler, args)` signals when the handler returns; async handlers are not awaited | `registerObserverWithSignalNext(query, (result, signalNext) => {...}, args)` |
| Swift | `registerObserver(query:arguments:deliverOn:handler:)` signals when the handler returns; main queue by default | `handlerWithSignalNext:`; `deliverOn:` to move heavy work off the main queue |
| Kotlin | `registerObserver(query, args) { result -> }` with a suspending handler, or `observe(...)` returning a `Flow` (`.conflate()` for slow collectors) | No `signalNext`; `collect(query, args) { result -> }` requests the next event after the handler returns; release with `close()` |

Do not port Flutter observer code one-to-one.

## Differ

| `Diff` field | Contents |
|---|---|
| `insertions` | Indexes in the new list of added items |
| `deletions` | Indexes in the old list of removed items |
| `updates` | Indexes in the new list of changed items |
| `moves` | `DiffMove(from: oldIndex, to: newIndex)` |

- `diff()` takes a `List<QueryResultItem>` (`result.items.toList()`); the first call reports every item as inserted.
- Identity is `_id`; values are compared deeply. A value that changed and changed back between two results is not an update.
- `Differ` keeps the previous result and is expensive: bound the query (`LIMIT`) and debounce large or busy results.
- `Differ` does not return old items; keep previous values or IDs yourself.
- Only items produced by Ditto are accepted (test doubles throw `ArgumentError`).
- For `AnimatedList`, apply removals in descending old-index order and insertions in ascending new-index order; treat moves as removal plus insertion. See [observer-differ.dart](../examples/observer-differ.dart).
