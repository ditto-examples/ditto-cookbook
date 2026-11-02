# Observing Changes

A **store observer** is a live local query. Ditto re-runs it whenever a local write or an incoming sync affects its query, and delivers the new result to your code. Observers never cause data to sync; pair them with a subscription (see [Sync and Subscriptions](sync-and-subscriptions.md)).

When an observer fires depends on its query. In our testing with SDK 5.1.0 and 5.2.0, a `SELECT *` observer fired on every write to a document in its result, even when the write did not change any value; an observer that projected fields (`SELECT _id, status ...`) fired only when a projected value changed; and an aggregate observer (`COUNT`, `GROUP BY`) fired on every write to the collection (see [When an observer fires depends on its query](../knowledge/transactions-and-observers.md#when-an-observer-fires-depends-on-its-query)). Project the fields a screen needs to avoid needless callbacks.

Since SDK 5.1, an observer is called at most about 30 times a second, so a quickly changing value skips intermediate states but the latest one arrives within tens of milliseconds, also for local writes (see [A device receives nearly every value of a fast-changing field](../knowledge/transactions-and-observers.md#a-device-receives-nearly-every-value-of-a-fast-changing-field) and [Local writes are coalesced into callbacks about 30 ms apart](../knowledge/transactions-and-observers.md#local-writes-are-coalesced-into-callbacks-about-30-ms-apart)). To process every value, write each one as its own document (see [Pattern 2: Append-only event documents](data-modeling.md#pattern-2-append-only-event-documents)). Changes that arrive through sync are delivered in batches, not one callback per remote write: in our testing, 20 documents written one by one on another device arrived in two or three callbacks, and a transaction, local or remote, arrived as one callback with all of its documents (see [Remote changes arrive in a few callbacks, and a transaction in one](../knowledge/transactions-and-observers.md#remote-changes-arrive-in-a-few-callbacks-and-a-transaction-in-one)). Do not use observer callbacks to count or log every local or remote change; intermediate states can be skipped.

Flutter offers three ways to register an observer:

| API | Status | Returns | Backpressure | Use for |
|---|---|---|---|---|
| `registerObserver` | Stable | `StoreObserver` | None (results are delivered as soon as they are ready) | UI updates and other fast, synchronous work (**default**) |
| `registerObserverV2` | **(Experimental)** (SDK 5.1+) | `StoreObserverV2` | Automatic: follows pause/resume of the `changes` stream | Slow or asynchronous per-update work with `await for` |
| `registerObserverWithSignalNext` | **(Experimental)** (SDK 5.1+) | `StoreObserverV2` | Manual: call `signalNext()` when ready | Explicit control over when the next update may arrive |

All three accept only `SELECT` queries and take parameters through `arguments:`.

## Store Observers in Flutter

The recommended pattern registers the observer **without** `onChange`, consumes the `changes` stream with a single `StreamSubscription`, and cancels both in `dispose()`:

```dart
// ✅ GOOD: The recommended observer pattern for widgets.
class OrdersList extends StatefulWidget {
  const OrdersList({super.key, required this.ditto});
  final Ditto ditto;
  @override
  State<OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<OrdersList> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      setState(() {
        _orders = result.items.map((item) => item.value).toList();
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          return ListTile(key: ValueKey(order['_id']), title: Text('${order['_id']}'));
        },
      );
}
```

**✅ DO:**
- Register observers in `initState()` (or in a service), never in `build()`.
- Copy plain values out of the result (`item.value`, or your own model objects) before storing them in state; do not keep `QueryResult` or `QueryResultItem` objects around (see [Working with Query Results](dql.md#working-with-query-results)).
- Add `ORDER BY` whenever the order of results matters; without it, the order of observer results is not guaranteed.
- Cancel the stream subscription **and** the observer in `dispose()`.

**❌ DON'T:**
- Pass `onChange` and leave the `changes` stream unconsumed (see the note below).
- Listen to `changes` twice; it is a single-subscription stream.
- Create an observer per list item; observe the list once and pass values down.

> **Note (SDK 5.1.0):** When an observer is registered with `onChange`, every result is **also** queued in its `changes` stream. If nothing listens to `changes`, those queued results stay in memory for the lifetime of the observer, so memory use grows with every update. The same applies to `registerObserverV2`, which starts observing as soon as it is registered, with or without `onChange`: listen to its `changes` stream right after registering it, never later. Use the pattern above (no `onChange`, consume `changes`). If you need `onChange`, also drain the stream, for example with `observer.changes.listen((_) {})`. The `ditto_live` 5.2.0 source registers observers the same way, so expect the same behavior there.

```dart
// ❌ BAD: onChange only; the unconsumed changes stream keeps every result in memory (SDK 5.1.0).
StoreObserver observeOrdersWithCallbackOnly(Ditto ditto, void Function(int) onCount) {
  return ditto.store.registerObserver(
    'SELECT * FROM orders ORDER BY createdAt DESC',
    onChange: (result) => onCount(result.items.length),
  );
}

// ✅ GOOD: The same work driven by the changes stream. Register the observer
// without onChange, and cancel both the returned subscription and the observer.
StreamSubscription<QueryResult> observeOrderCount(
  StoreObserver observer,
  void Function(int) onCount,
) {
  return observer.changes.listen((result) => onCount(result.items.length));
}
```

### Stable ordering

Observer results have no guaranteed order unless the query has an `ORDER BY` clause. Lists that re-order randomly on every update are a common symptom. Produce the timestamp you sort by with one fixed-precision helper (see [Timestamps](data-modeling.md#timestamps)).

```dart
// ❌ BAD: No ORDER BY; rows may change position between updates.
StoreObserver observeTasksUnordered(Ditto ditto) =>
    ditto.store.registerObserver('SELECT * FROM tasks WHERE done = false');

// ✅ GOOD: Deterministic order; _id breaks ties between equal timestamps.
StoreObserver observeTasksOrdered(Ditto ditto) => ditto.store.registerObserver(
      'SELECT * FROM tasks WHERE done = false ORDER BY createdAt DESC, _id',
    );
```

### Observer lifecycle and cleanup

| Behavior (`registerObserver`) | Consequence |
|---|---|
| Without `onChange`, the observer starts querying only when `changes` is first listened to | An observer that is registered but never listened to produces no events and does no query work, but still holds resources until cancelled |
| With `onChange`, the observer starts immediately | Results are delivered to `onChange` and also buffered in `changes` until something listens (see the note above); listen right after registering |
| `changes` is a single-subscription stream | A second `listen()` throws a `StateError` (`Bad state: Stream has already been listened to.`), including after the first subscription was cancelled |
| Cancelling the `StreamSubscription` does not cancel a `StoreObserver` | Always call `observer.cancel()` as well |
| `observer.cancel()` closes the `changes` stream | A pending `await for` loop over `changes` ends |
| `await ditto.close()` marks observers as cancelled (`isCancelled == true`) but does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2` | Do not rely on `close()` to end an `await for` loop over observer results; cancel observers explicitly before closing |

Because `changes` is single-subscription, a `StreamBuilder` works well when the observer is created once in `initState` and its stream is handed to exactly one `StreamBuilder`:

```dart
// ✅ GOOD: StreamBuilder variant. The query starts when StreamBuilder listens.
class OpenOrdersStream extends StatefulWidget {
  const OpenOrdersStream({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OpenOrdersStream> createState() => _OpenOrdersStreamState();
}

class _OpenOrdersStreamState extends State<OpenOrdersStream> {
  late final StoreObserver _observer;

  @override
  void initState() {
    super.initState();
    // Create the observer once; never in build().
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      arguments: {'status': 'open'},
    );
  }

  @override
  void dispose() {
    _observer.cancel(); // StreamBuilder's unsubscribe does not cancel the observer.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryResult>(
      stream: _observer.changes,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = result.items.map((item) => item.value).toList();
        return ListView(
          children: [
            for (final order in orders)
              ListTile(key: ValueKey(order['_id']), title: Text('${order['_id']}')),
          ],
        );
      },
    );
  }
}
```

**Why:** If the `StreamBuilder` is removed from the tree and later rebuilt with the same `changes` stream, the second listen throws. Keep the `StreamBuilder` mounted for the observer's lifetime, or move the observer into the same widget whose lifetime matches the `StreamBuilder`.

### Keep observer callbacks fast

`registerObserver` has no backpressure: Ditto never waits for your code before delivering the next result. Pausing the `changes` stream of a `StoreObserver` does not slow Ditto down; results queue up in the stream instead.

**✅ DO:**
- Keep the listener synchronous and short: copy values, map them to model objects, call `setState`.
- Move expensive decoding or computation off the UI isolate (for example, with Flutter's `compute()` on plain values copied out of the result).
- Use `registerObserverV2` or `registerObserverWithSignalNext` when each update triggers slow or asynchronous work (see [Backpressure (SDK 5.1+)](#backpressure-sdk-51)).
- Throttle UI updates for very busy collections if the user cannot perceive every intermediate state.

**❌ DON'T:**
- `await` network calls, file I/O, or database writes inside a `registerObserver` listener; the next results keep arriving while you wait. In our testing with the JavaScript SDK, async callbacks overlapped, and a slow callback for an older result finished last, so the screen kept showing the older state (see [In JavaScript, registerObserver does not await async callbacks](../knowledge/transactions-and-observers.md#in-javascript-registerobserver-does-not-await-async-callbacks)). Use `registerObserverWithSignalNext` (or `registerObserverV2` in Flutter) for asynchronous work.
- Write to the same collection from inside its observer without a guard; each write triggers the observer again. In our testing, a `SELECT *` observer that wrote the same value to its own document was called again about every 35 ms without end; comparing the value before writing, or `DO UPDATE_LOCAL_DIFF`, stopped it (see [Writing the same value from an observer keeps it firing](../knowledge/transactions-and-observers.md#writing-the-same-value-from-an-observer-keeps-it-firing)).

```dart
// ❌ BAD: Slow async work per update without backpressure; uploads overlap and queue up.
StreamSubscription<QueryResult> uploadOnEveryChange(
  StoreObserver observer,
  Future<void> Function(List<Map<String, dynamic>>) upload,
) {
  return observer.changes.listen((result) async {
    await upload(result.items.map((item) => item.value).toList());
  });
}
```

## Backpressure (SDK 5.1+)

Two experimental observer APIs (SDK 5.1+) let your code control when the next result is delivered. Both return a `StoreObserverV2`. While your code is busy, Ditto holds back further updates and then delivers the latest state, so intermediate results are merged instead of queued. The exact delivery rules for each API are listed below.

### registerObserverV2 (Experimental)

`registerObserverV2` signals readiness automatically after each result has been added to the `changes` stream, and it follows the stream's pause and resume. Because `await for` pauses its subscription while the loop body runs, slow `async` work in the loop body applies backpressure without extra code.

```dart
// ✅ GOOD: registerObserverV2 (Experimental) with await for: one update at a time.
class SensorAggregator {
  SensorAggregator(this._ditto);

  final Ditto _ditto;
  StoreObserverV2? _observer;

  Future<void> run(
    String deviceId,
    Future<void> Function(List<Map<String, dynamic>> readings) persistAggregates,
  ) async {
    stop(); // Cancel a previous run, if any.
    final observer = _ditto.store.registerObserverV2(
      'SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100',
      arguments: {'deviceId': deviceId},
    );
    _observer = observer;
    // While the body runs, the stream is paused and Ditto holds back the next update.
    await for (final result in observer.changes) {
      await persistAggregates(result.items.map((item) => item.value).toList());
    }
    // The loop ends when stop() cancels the observer.
  }

  void stop() => _observer?.cancel();
}
```

Behavior:

- While the stream is paused, Ditto stops delivering after the update that arrived right at the pause. On resume, that held update and the latest state are delivered; intermediate states are merged.
- Leaving the loop (`break`, `return`, or an exception) cancels the stream subscription, and cancelling the stream subscription of a `StoreObserverV2` also cancels the observer.
- `observer.cancel()` closes the stream and ends the loop; `ditto.close()` does not, so cancel the observer before closing.
- `signalNext()` has no effect on observers registered with `registerObserverV2`.

### registerObserverWithSignalNext (Experimental)

`registerObserverWithSignalNext` delivers one result and then waits until you call `signalNext()` (the callback parameter or `observer.signalNext()`). **If you never call it, the observer stops delivering updates.** Do not use pause and resume on the `changes` stream of such an observer; the SDK logs a warning if you do.

```dart
// ✅ GOOD: registerObserverWithSignalNext (Experimental): request the next update when done.
class OpenOrdersUploader {
  OpenOrdersUploader(this._ditto, this._upload);

  final Ditto _ditto;
  final Future<void> Function(List<Map<String, dynamic>> orders) _upload;
  StoreObserverV2? _observer;
  StreamSubscription<QueryResult>? _changes;

  void start() {
    stop(); // Cancel a previous start, if any.
    final observer = _ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
      arguments: {'status': 'open'},
    );
    _observer = observer;
    // Consume results through the changes stream (no onChange).
    _changes = observer.changes.listen((result) {
      final orders = result.items.map((item) => item.value).toList();
      unawaited(_handle(orders, observer.signalNext));
    });
  }

  Future<void> _handle(List<Map<String, dynamic>> orders, void Function() signalNext) async {
    try {
      await _upload(orders);
    } catch (error) {
      showError(error);
    } finally {
      signalNext(); // Always signal, even after an error; otherwise updates stop.
    }
  }

  void stop() {
    unawaited(_changes?.cancel()); // Cancelling the stream also cancels a StoreObserverV2.
    _observer?.cancel();
  }
}
```

```dart
// ❌ BAD: signalNext is skipped when the work throws; the observer silently stops updating.
StoreObserverV2 fragileObserver(
  Ditto ditto,
  Future<void> Function(List<Map<String, dynamic>> orders) upload,
) {
  final observer = ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM orders ORDER BY createdAt',
  );
  observer.changes.listen((result) async {
    await upload(result.items.map((item) => item.value).toList());
    observer.signalNext(); // Never reached if upload() throws.
  });
  return observer;
}
```

The `onChange` callback of `registerObserverWithSignalNext` receives the `signalNext` function as its second parameter, but results passed to `onChange` are also queued in `changes`, so the note in [Store Observers in Flutter](#store-observers-in-flutter) applies here too. Consuming `changes` and calling `observer.signalNext()`, as above, avoids the issue.

### Choosing an observer API

| Situation | Recommended API |
|---|---|
| Updating widgets from a query result | `registerObserver` + `changes` (stable) |
| Each update triggers slow or `async` work (upload, file export, heavy aggregation) and you can write it as a loop | `registerObserverV2` + `await for` **(Experimental)** |
| The work for an update finishes in a different place than where the update arrives (for example, after an animation or an external callback) | `registerObserverWithSignalNext` **(Experimental)** |
| Very frequent updates where only the latest state matters | `registerObserverV2` with a slow consumer (intermediate states are merged), or throttle a `registerObserver` listener |

The experimental APIs may change in a future release; the stable `registerObserver` remains the default choice for UI code.

### Backpressure on other platforms

Backpressure works differently on each platform. Do not port Flutter code one-to-one.

| Platform | Default observer | Backpressure |
|---|---|---|
| Flutter | `registerObserver(query, arguments:)` + `changes`; no backpressure | `registerObserverV2` (auto, follows pause/resume) or `registerObserverWithSignalNext` (manual); both experimental |
| JavaScript | `registerObserver(query, handler, args)` signals the next update automatically when the handler **returns**; an `async` handler is not awaited | `registerObserverWithSignalNext(query, (result, signalNext) => {...}, args)` for asynchronous work |
| Swift | `registerObserver(query:arguments:deliverOn:handler:)` signals automatically when the handler returns; delivered on the main queue by default | `handlerWithSignalNext:` for manual `signalNext()`; pass `deliverOn:` to move heavy work off the main queue |
| Kotlin | `registerObserver(query, args) { result -> }` with a suspending handler, or `observe(...)` returning a `Flow` (use `.conflate()` for slow collectors). Observers and subscriptions are released with `close()` | No `signalNext`; `collect(query, args) { result -> }` requests the next event only after the suspending handler returns |

## Diffing Results

An observer delivers the complete result every time. When you need to know **what** changed (for list animations, or to process only new items), use `Differ`. It compares successive results by `_id` and reports index sets:

| `Diff` field | Contents |
|---|---|
| `insertions` | Indexes in the **new** list of items that were added |
| `deletions` | Indexes in the **old** list of items that were removed |
| `updates` | Indexes in the **new** list of items whose value changed |
| `moves` | `DiffMove(from: oldIndex, to: newIndex)` for items that changed position |

Facts to keep in mind:

- `diff()` takes a `List<QueryResultItem>`; pass `result.items.toList()` (`items` is an `Iterable`).
- The first call reports every item as an insertion.
- Identity is `_id`, so include `_id` in the projection of a diffed query. **Note (SDK 5.2.0):** in our testing with the JavaScript SDK, observer rows of a query that did not project `_id` had no `_id` (on 5.1.0 they did), and `Differ` reported a reordering as updates instead of moves (see [On SDK 5.2.0, observer rows include _id only when it is projected](../knowledge/transactions-and-observers.md#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected)). Values are compared deeply. A value that changed and changed back between two results is not reported as an update; the observer may still deliver the unchanged result, which then produces an empty diff.
- `moves` can list every item whose position shifted, not just the one that was moved: in our testing, moving one item to the top of a three-item list reported three moves, plus an update for the moved item (see [Differ reports every shifted item as a move](../knowledge/transactions-and-observers.md#differ-reports-every-shifted-item-as-a-move)).
- `Differ` keeps the previous result in memory and diffing is computationally expensive. Debounce updates for large or busy result sets, and keep diffed queries bounded (for example, with `LIMIT`).
- `Differ` does not give you the old items. Keep the previous values (or at least their IDs) yourself.
- `Differ` only accepts items produced by Ditto; passing test doubles throws an `ArgumentError`.

```dart
// ✅ GOOD: Logging changes between results with Differ.
StreamSubscription<QueryResult> logOrderChanges(StoreObserver observer) {
  final differ = Differ();
  var previousIds = <Object?>[];

  return observer.changes.listen((result) {
    final items = result.items.toList(); // diff() takes a List.
    final Diff diff = differ.diff(items);
    final currentIds = items.map((item) => item.value['_id']).toList();

    for (final index in diff.deletions) {
      debugPrint('deleted ${previousIds[index]}'); // Index into the OLD list.
    }
    for (final index in diff.insertions) {
      debugPrint('inserted ${currentIds[index]}'); // Index into the NEW list.
    }
    for (final index in diff.updates) {
      debugPrint('updated ${currentIds[index]}'); // Index into the NEW list.
    }
    for (final DiffMove move in diff.moves) {
      debugPrint('moved ${move.from} -> ${move.to}');
    }
    previousIds = currentIds;
  });
}
```

### Animated lists

`Differ` is most useful with `AnimatedList`, which needs explicit `insertItem` and `removeItem` calls. A plain `ListView.builder` with `ValueKey`s does not need `Differ` at all.

```dart
// ✅ GOOD: Driving an AnimatedList from Differ results.
class AnimatedOrders extends StatefulWidget {
  const AnimatedOrders({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<AnimatedOrders> createState() => _AnimatedOrdersState();
}

class _AnimatedOrdersState extends State<AnimatedOrders> {
  final _listKey = GlobalKey<AnimatedListState>();
  final _differ = Differ();
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen(_apply);
  }

  void _apply(QueryResult result) {
    final items = result.items.toList();
    final diff = _differ.diff(items);
    final previous = _orders;
    final next = items.map((item) => item.value).toList();
    final list = _listKey.currentState;

    if (list != null) {
      // Remove from the end so earlier old indexes stay valid.
      final removed = {...diff.deletions, for (final m in diff.moves) m.from}.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final index in removed) {
        final order = previous[index];
        list.removeItem(index, (context, animation) => _row(order, animation));
      }
      // Insert in ascending order of new indexes.
      final inserted = {...diff.insertions, for (final m in diff.moves) m.to}.toList()
        ..sort();
      for (final index in inserted) {
        list.insertItem(index);
      }
    }
    // Updated rows are rebuilt with the new values.
    setState(() => _orders = next);
  }

  Widget _row(Map<String, dynamic> order, Animation<double> animation) =>
      SizeTransition(
        sizeFactor: animation,
        child: ListTile(title: Text('${order['_id']}'), subtitle: Text('${order['status']}')),
      );

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedList(
        key: _listKey,
        initialItemCount: _orders.length,
        itemBuilder: (context, index, animation) => _row(_orders[index], animation),
      );
}
```

**Why:** Applying removals in descending order and insertions in ascending order keeps `AnimatedList`'s internal indexes consistent with the new list. Treating a move as a removal plus an insertion is the simplest correct approach; use dedicated move animations only if your UI needs them.

## Partial UI Updates

An observer delivers a new result for **any** change that affects its query. If that result triggers `setState` at the top of a large screen, the whole screen rebuilds, which can cause dropped frames, lost scroll position, or lost input focus on busy collections.

**✅ DO:**
- Give each screen region its own small observer and its own widget, so a change rebuilds only that region.
- Use lazy list builders (`ListView.builder`) with a `ValueKey(_id)` per row; only visible rows are built, and keys preserve row state across updates.
- Use aggregate queries for summary widgets (a badge needs `COUNT(*)`, not the full list).
- With state management libraries (Riverpod, Bloc, Provider), let one provider or controller own each observer, cancel it in the provider's dispose hook, and remember that `changes` can only be listened to once.
- Map results to immutable model classes that implement `==` if you rely on equality checks to skip rebuilds; `item.value` creates a new `Map` for every result, so two maps with identical contents are never `==` to each other.

**❌ DON'T:**
- Observe a whole collection in the root widget and rebuild the entire screen on every change.
- Rebuild an app bar, filters, and list together when only one row changed.

```dart
// ✅ GOOD: The count badge and the list each observe what they need.
class OpenOrdersCount extends StatefulWidget {
  const OpenOrdersCount({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OpenOrdersCount> createState() => _OpenOrdersCountState();
}

class _OpenOrdersCountState extends State<OpenOrdersCount> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  final _count = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      final n = result.items.isEmpty ? 0 : result.items.first.value['n'];
      // ValueNotifier only notifies listeners when the value actually changes.
      _count.value = n is int ? n : 0;
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _count,
        builder: (context, count, _) => Text('Open orders: $count'),
      );
}

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, required this.ditto, required this.orderList});

  final Ditto ditto;

  /// A list widget with its own observer, such as OrdersByStatus from
  /// "Filter locally instead of re-registering" (Subscription Lifecycle).
  final Widget orderList;

  @override
  Widget build(BuildContext context) {
    // The screen itself observes nothing; each region rebuilds independently.
    return Scaffold(
      appBar: AppBar(title: OpenOrdersCount(ditto: ditto)),
      body: orderList,
    );
  }
}
```

**Why:** Several narrow observers (one per region) often cost less than rebuilding the entire screen for every change, and they make each widget self-contained. Each observer re-runs its query when its data changes, so keep the number of observers on busy collections reasonable. While any device runs SDK 5.1.0, also stay well below about 60 observers in total: more stalled every callback in our testing (see [On SDK 5.1.0, observers stall beyond about 60](../knowledge/transactions-and-observers.md#on-sdk-510-observers-stall-beyond-about-60)) (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)). Use Flutter DevTools to confirm which widgets rebuild before optimizing further.
