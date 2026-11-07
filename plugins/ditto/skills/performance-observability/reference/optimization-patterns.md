# Performance and Observability Reference (SDK 5.2.0)

Detailed rules behind the [performance-observability skill](../SKILL.md). Everything here is extracted from the Ditto best practices guide; `§ <Heading>` cites a section of the guide in [../../guide/reference/best-practices/](../../guide/reference/best-practices/README.md) or [../../guide/reference/knowledge/](../../guide/reference/knowledge/README.md) (find it with Grep for the heading text in both directories) for full explanations and example output.

## Table of Contents

- [Observer Behavior](#observer-behavior)
- [Observer Lifecycle](#observer-lifecycle)
- [Backpressure Example: registerObserverV2](#backpressure-example-registerobserverv2)
- [Differ](#differ)
- [Index Usage Rules](#index-usage-rules)
- [Composite Indexes and Covering Scans](#composite-indexes-and-covering-scans)
- [ADVISE](#advise)
- [EXPLAIN and PROFILE](#explain-and-profile)
- [Query Scope](#query-scope)
- [Long-Running Requests and Execution Model](#long-running-requests-and-execution-model)
- [Avoiding Unnecessary Writes](#avoiding-unnecessary-writes)
- [Logging Details](#logging-details)
- [System Virtual Collections](#system-virtual-collections)
- [System Parameters for Diagnostics](#system-parameters-for-diagnostics)
- [Support Bundles](#support-bundles)

---

## Observer Behavior

**Guide**: `§ Observing Changes`, `§ When Observers Fire`, `§ Observer Lifecycle`, `§ Choosing an observer API`, `§ Diffing Results`; each SDK page's *Store Observers*, *Observer lifecycle*, and *Backpressure in <SDK>* sections

| SDK | Default observer | Backpressure (SDK 5.1+) | Release |
|---|---|---|---|
| Flutter | `registerObserver` (returns `StoreObserver`; results in `changes`); none | `registerObserverV2` (automatic, follows pause/resume of `changes`: consume it with `await for`, since `listen(async ...)` does not pause it) and `registerObserverWithSignalNext` (manual), both **(Experimental)**, return `StoreObserverV2` | `cancel()` |
| JavaScript | `registerObserver(query, handler, args)` signals when the handler **returns**; an `async` handler is not awaited | `registerObserverWithSignalNext(query, (result, signalNext) => {...}, args)` | `cancel()` |
| Kotlin | `registerObserver(query, args) { result -> }` (suspending) or `observe(...)` returning a `Flow` | Suspending handlers, `collect(...)`, or `.conflate()`; no `signalNext` | `close()` |
| Swift | `registerObserver(query:arguments:deliverOn:handler:)`, main queue by default | `handlerWithSignalNext:`; pass `deliverOn:` to move heavy work off the main queue | `cancel()` |

Every SDK accepts only `SELECT` queries for observers and takes parameters as arguments. Observers never cause data to sync; pair them with a subscription.

Behavior:
- When an observer fires depends on its query (in testing with SDK 5.1.0 and 5.2.0): `SELECT *` fires on every write to a document in its result, even one that changes no value; a projection fires only when a projected value changes; an aggregate (`COUNT`, `GROUP BY`) fires on every write to the collection; writes to another collection call no observer. Project the fields a screen needs, plus `_id` (on 5.2.0, rows of a query that does not project `_id` have none).
- A `SELECT *` observer that writes the same value to its own document is called again about every 35 ms without end; compare before writing, or use `DO UPDATE_LOCAL_DIFF`.
- Since SDK 5.1, an observer is called at most about 30 times a second (about every 34 ms in testing), so quickly changing values skip intermediate states, also for local writes (50 awaited writes reached an observer on the same device in 4 or 5 callbacks on 5.1.0 and 5.2.0); write each value as its own document if every one matters.
- In JavaScript, `async` callbacks of `registerObserver` overlap, and a slow callback for an older result can finish last and leave the screen stale; use `registerObserverWithSignalNext`.
- Large result sets cost memory on every callback: an observer of 200 documents under constant updates grew the JavaScript process by about 13 to 24 KiB per callback for 10 minutes, one of a single row leveled off after about 5 minutes on 5.1.0 and 5.2.0, and cancelling stopped the growth (`§ Query Scope and Execution`).
- Flutter `registerObserver` has no backpressure: it never waits for your code.
- Flutter: with `onChange`, events emitted before the first listener attaches are buffered; listen right after registering. `registerObserverV2` starts observing as soon as it is registered, with or without `onChange`, so listen to its `changes` right away.
- Flutter `registerObserverV2`: while the stream is paused, Ditto stops delivering after the update that arrived at the pause; on resume, that update and the latest state are delivered. Leaving an `await for` loop cancels the subscription and the observer; `ditto.close()` does not end the loop, so cancel the observer before closing.
- `registerObserverWithSignalNext` (and Swift `handlerWithSignalNext:`): one result, then nothing until `signalNext()`. In Flutter, do not pause or resume its stream (the SDK logs a warning).
- An observer does not re-run its query after writes to collections it does not observe: in testing with SDK 5.1.0 and 5.2.0, 50 writes to another collection ran no observer query (SDK 5.0.3 re-ran it after about every third write), although the 5.2.0 release notes list this as a fix. According to the same release notes, observers also hold less memory between updates in 5.2. Splitting observers by collection therefore costs little (`§ On SDK 5.1.0 and 5.2.0, an observer did not re-run its query after writes to another collection`, `§ Query Scope and Execution`).
- `ditto.store.observers` lists the uncancelled observers (in Flutter, SDK 5.2+, only those from `registerObserver`), and `ditto.store.attachmentFetchers` the active fetchers. A count that keeps growing while the user moves between screens points to an observer that is never cancelled (`§ Resource Cleanup and Shutdown`).
- The differ keeps the previous result in memory, and diffing is computationally expensive; debounce updates for large or busy result sets and keep diffed queries bounded (for example, with `LIMIT`). It only accepts items produced by Ditto (in Flutter, test doubles throw an `ArgumentError`).

---|---|---|
| JavaScript | `registerObserver(query, handler, args)` signals when the handler **returns**; an `async` handler is not awaited | `registerObserverWithSignalNext(query, (result, signalNext) => {...}, args)` |
| Swift | `registerObserver(query:arguments:deliverOn:handler:)`, main queue by default | `handlerWithSignalNext:`; pass `deliverOn:` to move heavy work off the main queue |
| Kotlin | `registerObserver(query, args) { result -> }` (suspending) or `observe(...)` returning a `Flow` | No `signalNext`; suspending handlers, `collect(...)`, or `.conflate()`; release with `close()` |

---

## Observer Lifecycle

**Guide**: `§ Observer Lifecycle`, `§ Resource Cleanup and Shutdown`; each SDK page's *Observer lifecycle in <SDK>* section

In every SDK:
- Register observers in the owner's start hook (Flutter `initState()`, a view model, a service or controller), never in render code; let observers follow screen scope and keep subscriptions at app or feature scope.
- Release every observer when its owner goes away (`cancel()`, `close()` in Kotlin); do not rely on garbage collection or on closing Ditto.
- Add `ORDER BY` whenever result order matters (use `_id` as a tie-breaker); without it the order of observer results is not guaranteed (`§ Stable ordering`).
- Copy values out of the result (plain values or your own model objects) instead of keeping result or row objects in state or caches (`§ Working with Query Results`).
- Do not create an observer per list item; observe the list once and pass values down.

Flutter (`registerObserver`; `§ Observer lifecycle in Flutter`):

| Behavior | What to do |
|---|---|
| Without `onChange`, the query starts when `changes` is first listened to | Listen right after registering |
| `changes` is single-subscription; a second `listen()` throws a `StateError` (`Bad state: Stream has already been listened to.`), even after the first subscription was cancelled | Hand the stream to exactly one listener or `StreamBuilder`, and keep that `StreamBuilder` mounted |
| Cancelling the `StreamSubscription` does not cancel a `StoreObserver` | Always call `observer.cancel()` as well, in `dispose()` |
| `observer.cancel()` closes `changes` | A pending `await for` loop ends |
| `await ditto.close()` does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2`, and `cancel()` does nothing once Ditto is closed | Cancel stream subscriptions and observers before closing |
| Cancelling the stream subscription of a `StoreObserverV2` also cancels the observer | Still call `cancel()` in your cleanup path for clarity |

The full widget for each SDK is in `observer-performance` in `../examples/<sdk>/` (Flutter: Pattern 1 of [../examples/flutter/observer-performance.dart](../examples/flutter/observer-performance.dart), with the onChange-only anti-pattern in the same file).

---

## Backpressure Example: registerObserverV2

**Guide**: `§ Backpressure (SDK 5.1+)`, `§ Backpressure in Flutter`, `§ Choosing an observer API`. This example is Flutter-only; the other SDKs' backpressure code is in `observer-backpressure` in `../examples/<sdk>/` and on each SDK page.

```dart
// ✅ GOOD: registerObserverV2 (Experimental) with await for: one update at a time.
Future<void> exportOpenOrders(
  Ditto ditto,
  Future<void> Function(List<Map<String, dynamic>> orders) export,
) async {
  final observer = ditto.store.registerObserverV2(
    'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
    arguments: {'status': 'open'},
  );
  // await for pauses the stream while the body runs; Ditto holds back the next update.
  await for (final result in observer.changes) {
    await export(result.items.map((item) => item.value).toList());
  }
  // The loop ends when observer.cancel() is called elsewhere.
}
```

- `signalNext()` has no effect on observers registered with `registerObserverV2`.
- Results passed to `onChange` of either experimental API are also queued in `changes`; consume the stream.
- The experimental APIs may change in a future release; `registerObserver` remains the default for Flutter UI code.

---

## Differ

**Guide**: `§ Diffing Results`, `§ Partial UI Updates`; each SDK page's *Diffing results in <SDK>* section

- `Differ` in Flutter and JavaScript, `DittoDiffer` in Swift; in Kotlin, the observer passes a `DittoDiff` to a two-parameter handler, and apps do not create a `DittoDiffer`. Flutter's `diff()` takes a `List<QueryResultItem>` (pass `result.items.toList()`).
- The first call reports every item as an insertion.
- Deletions index the **old** list; insertions and updates index the **new** list.
- It does not give you the old items; keep previous values yourself.
- The differ keeps the previous result in memory and diffing is expensive; use it only where you need to know what changed (for example an animated list), and keep diffed queries bounded with `LIMIT`. A list keyed by `_id` does not need it.
- Each result creates new value objects, so two rows with identical contents may not compare as equal (in Flutter, two `item.value` maps are never `==`); map results to immutable models that compare by content if you rely on equality to skip updates.

---

## Index Usage Rules

**Guide**: `§ Index Usage Rules`

The planner chooses indexes by rules, not by statistics. `EXPLAIN` shows these plans:

| Predicate | Plan | Notes |
|---|---|---|
| `status = :status` | Index scan | |
| `status IN :statuses` (array parameter) | Index scan, one span per value | Write `IN :statuses`; `IN (:statuses)` matches nothing |
| `total > 100`, `total >= :min AND total < :max` | Index range scan | |
| `name LIKE 'abc%'` | Index range scan | Case-sensitive prefix without a leading wildcard; works with a literal or a parameter |
| `starts_with(name, 'abc')` | Collection scan | Use `LIKE 'abc%'` |
| `lower(name) = 'abc'`, any function on the field | Collection scan | Functions on the value side are fine |
| `status != 'open'`, `NOT (status = 'open')` | Index scan over two ranges | |
| `flag IS MISSING` | Index scan | SDK indexes include documents without the field |
| `coalesce(isDeleted, false) = false` | Collection scan | Combine with an indexed predicate, or use `isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false` |
| `_id = :id`, `_id IN :ids`, `USE IDS` | ID scan | No index needed |
| `a = 1 OR b = 2` (both indexed) | Union scan | |
| `a = 1 OR b = 2` (`b` not indexed) | **Collection scan** | Every `OR` branch must be indexable |
| `a = 1 AND b = 2` (separate indexes) | Intersect scan | A composite index on `(a, b)` is generally better; in testing, the intersect scan was slower than the more selective index alone |
| `address.city = 'Tokyo'` (index on `address.city`) | Index scan | Index the full path you filter on |
| `tags = ['x', 'y']` (index on `tags`) | Index scan | Whole-value match only |
| `array_contains(tags, 'x')`, `:tag IN tags` | Collection scan | Element lookups cannot use an index |
| `SELECT COUNT(*) FROM orders` (no `WHERE`) | Count scan | Does not read documents |

Do not index a field with only a few distinct values (a boolean, a two-value status) on its own: the planner uses it, and on 100,000 documents it was slower than no index (140 against 90 ms), while an index on the selective field took 21 to 27 ms and a composite `(store, status)` 17 ms (SDK 5.1.0 and 5.2.0, in testing; `§ Creating Indexes`). Measure the time after adding an index, not only the plan.

Constraints (`§ Creating Indexes`, `§ Strict mode and data types`):
- Expression, partial, and functional indexes are not supported.
- `IF NOT EXISTS` checks only the index **name**; to change a definition, create it under a new name or drop and recreate it.
- `DROP INDEX` requires `ON <collection>`.
- With `DQL_STRICT_MODE` set to `true`, the planner of SDK 5.1.0 and 5.2.0 uses no secondary indexes; queries that would use an index scan fall back to a collection scan. ID lookups and full-collection `COUNT(*)` are not affected, and `ADVISE` returns no suggestions.
- According to Ditto's documentation, only the most recently written CRDT type of a field is indexed. If the same field is written with different type declarations (for example `REGISTER` and `MAP`), an index on it can return incorrect or mis-ordered results. In our testing with SDK 5.1.0 and 5.2.0, results did not change, because queries that declared a type did not use the index; reads with different declarations did return different values. Keep type declarations consistent, and do not index fields written with more than one type.

```sql
CREATE INDEX IF NOT EXISTS idx_orders_city ON orders (address.city)

DROP INDEX IF EXISTS idx_orders_city ON orders

SELECT * FROM system:indexes WHERE collection = :collection
```

---

## Composite Indexes and Covering Scans

**Guide**: `§ Composite indexes and key order (SDK 5.1+)`, `§ Covering scans`

- Put **equality** fields first, then the **range** or **sort** field.
- Match the **sort direction**: with an index on `(status, total DESC)`, `WHERE status = 'open' ORDER BY total DESC` uses the index without a separate sort, while `ORDER BY total ASC` needs an extra sort step.
- On SDK 5.1.0, do not mix `ASC` and `DESC` keys in one index: such an index skips the sort but returns the results in the wrong order, and with `LIMIT` the wrong documents. Use `(status, total)` there and accept the extra sort step. Also on 5.1.0, an indexed query that projects fields and sorts by one of them can return the rows in the wrong order (use `SELECT *` or sort in your code), and a comparison with the constant on the left (`1 < a`) can return wrong results through an index (write `a > 1`). See `§ Known Issues in SDK 5.1.0`.
- Queries that do not constrain the leading field benefit less.
- When a query projects only indexed fields (plus `_id`), `EXPLAIN` shows `"covering": true` and no `fetch` step.

```sql
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)

-- Answered from idx_orders_status alone (covering scan)
SELECT _id, status FROM orders WHERE status = :status
```

---

## ADVISE

**Guide**: `§ ADVISE (SDK 5.1+)`

- `ADVISE <statement>` plans but does not execute; available on Small Peers for `SELECT`, `UPDATE`, `DELETE`, `EVICT`, and `INSERT ... SELECT`.
- The result row has `advice.suggestedIndexes` (each with `collection`, `reason`, `statement`), `advice.existingIndexes` when related indexes exist, and `advice.outcome` when there is nothing to suggest (for example `optimal indexes already exist`, `no advice available for statement`, or `no keys to advise on` when every condition applies a function to the field).
- `ADVISE AND PROVISION` also creates the suggested indexes (`createdIndexes`, `failedIndexes`). Keep it out of production code paths.
- For the statement below, SDK 5.1.0 and 5.2.0 suggest the same index, `(isDeleted ASC, status ASC, createdAt DESC)`, which mixes `ASC` and `DESC` keys. On 5.1.0, do not create such a suggestion as given: indexes that mix directions return the results in the wrong order there (`§ Known Issues in SDK 5.1.0`).

```sql
ADVISE SELECT * FROM orders WHERE status = :status AND isDeleted = false ORDER BY createdAt DESC
```

A development-only helper that prints each suggestion's `statement` (and `outcome` when there are none) is in *Executing DQL in <SDK>* on each SDK page.

The `ADVISE` statement above filters with `isDeleted = false`, which is correct only when every document has the field; otherwise keep the `coalesce` form (see `§ Indexing soft-delete filters`).

---

## EXPLAIN and PROFILE

**Guide**: `§ EXPLAIN and PROFILE`, `§ Reading an EXPLAIN plan`

| | `EXPLAIN` | `PROFILE` |
|---|---|---|
| Executes the statement | No (parse and plan only) | Yes |
| Returns | The query plan | The normal results plus one `~request_profile` row (for mutations without `RETURNING`, the profile row is the only row) |
| Use it to | Check access paths and indexes | Measure time and document counts per step |
| Statements | `SELECT`, mutations, `CREATE INDEX` / `DROP INDEX`, and `ADVISE` (not `SHOW` or `ALTER SYSTEM`) | `SELECT` and mutations (`INSERT`, `UPDATE`, `DELETE`, `EVICT`); mutations are executed |

| Operator | Meaning |
|---|---|
| `scan` | Collection scan; a warning sign on large collections |
| `indexScan` | Reads an index (`desc.index`, `spans`; `covering: true` means the filter can be evaluated from the index) |
| `idScan` | Direct lookup by `_id` |
| `unionScan` / `intersectScan` | Combines index scans for `OR` / `AND` |
| `countScan` | `COUNT(*)` without reading documents |
| `fetch` | Loads documents found by a scan |
| `filter` | Applies the full `WHERE` condition |
| `sort` / `limit` / `projection` | Ordering, row limit, `SELECT` list |
| `nlJoin` | Nested-loop JOIN (SDK 5.1+) |

In a `PROFILE` row, each operator has `#stats` (`documentsIn`, `documentsOut`, `phaseTimes`), and `times` holds `elapsed`, `parse`, and `plan`. Look for:
- A `filter` whose `documentsIn` is much larger than its `documentsOut` (an index usually helps)
- A `scan` or `fetch` with a high document count on a large collection
- `sort` or grouping steps on large inputs (they collect all input first, which costs memory)

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'open'

PROFILE SELECT * FROM orders WHERE total = 5
```

Directives (`§ Directives`) override the planner for one statement; use them only after `EXPLAIN` and `PROFILE` show the planner's choice is wrong. `USE INDEX 'name'` is silently ignored if the index does not exist or cannot serve the query, and `USE INDEX ''` requests a collection scan. Do not put directives in subscription queries; indexes and directives only affect local query execution.

```sql
SELECT * FROM orders USE INDEX 'idx_orders_status' WHERE status = :status
```

---

## Query Scope

**Guide**: `§ Query Scope and Execution`, `§ Large results`

**✅ DO:**
- Filter in `WHERE`, not in app code
- Project only the fields you need (subscriptions still sync whole documents and accept only `SELECT *`)
- Use `ORDER BY ... LIMIT` for local queries and observers that need the first rows
- Keep query strings constant and pass values as parameters, for safety (a string built per value was not measurably slower in testing with SDK 5.0.3 to 5.2.0)
- Prefer keyset pagination with an `_id` tie-breaker (`WHERE createdAt < :after OR (createdAt = :after AND _id < :afterId) ORDER BY createdAt DESC, _id DESC LIMIT :pageSize`) over large `OFFSET` values, which re-read and skip earlier rows
- Use `DISTINCT` only on a few low-cardinality fields; it keeps every distinct row in memory
- Count with `COUNT(*)` and check existence with `LIMIT 1`

**❌ DON'T:**
- Observe an entire large collection and filter or paginate in app code
- Run one query per ID when `WHERE _id IN :ids` returns the same data (each `execute` call costs about 1.7 ms in testing with SDK 5.1.0 and 5.2.0: 500 lookups took 0.8 to 0.9 s, one `IN` query 6 to 15 ms); likewise, insert many documents with one array parameter, not one statement each (2,000 documents: about 4 s against 17 ms)
- Use `DISTINCT` with `_id` or `*`

```sql
SELECT _id, title, createdAt FROM tasks
WHERE createdAt < :after OR (createdAt = :after AND _id < :afterId)
ORDER BY createdAt DESC, _id DESC LIMIT :pageSize

SELECT DISTINCT status FROM orders ORDER BY status

SELECT * FROM orders WHERE _id IN :ids
```

**Counting** (`§ Counting documents`): a full-collection `COUNT(*)` is answered by a count scan (SDK 5.1+) without reading documents. Ditto's 5.1 benchmark reported about 167x faster full-collection counts and about 4.4x faster filtered counts, comparing median runtimes of SDK 5.0.3 and 5.1.0 on a single Android device (Orion O6) with one retail dataset of about 93,000 documents; results depend on device, data shape, indexes, and query mix. A filtered count still evaluates the filter, so index the filtered fields.

---

## Long-Running Requests and Execution Model

**Guide**: `§ Long-running requests (SDK 5.1+)`, `§ Query execution and the UI thread`

| Parameter | Default | Effect |
|---|---|---|
| `DQL_SLOW_REQUEST_WARN_SECONDS` (SDK 5.1+) | `60` | Logs a warning with request details once a request runs this long, repeated at the same interval; `0` disables |
| `DQL_REQUEST_TIMEOUT_SECONDS` (SDK 5.1+) | `0` (disabled) | Cancels longer requests with a timeout error (cooperative cancellation) |

```sql
ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 10

ALTER SYSTEM SET DQL_REQUEST_TIMEOUT_SECONDS = 30
```

`ALTER SYSTEM` changes these values while the app runs, for example when support asks for slow-request warnings on a device in the field. System parameters are not persisted: for settings the app always needs, pass them in the system parameters of `DittoConfig` on every open (SDK 5.2+; on SDK 5.1, `ALTER SYSTEM` after every open, before sync starts). Before enabling a timeout in production, handle the resulting error for every query.

`execute` is asynchronous in every SDK; decode large results and do heavy work on the values off the UI thread. In Flutter on native platforms, `ditto.store.execute` runs on a long-lived worker isolate per `Ditto` instance, so a slow query does not block the UI isolate. `Store.experimentalSkipExecuteIsolateOffload` **(Experimental)** runs `execute` inline on the calling isolate; any slow query then blocks that isolate (usually the UI). Use it only after measuring a real throughput problem with many very small queries.

---

## Avoiding Unnecessary Writes

Write frequent events in batches: one document per `INSERT` topped out at about 600 documents a second and cost about 2 ms of CPU per document on both the writer and the receiver, while 50 documents per `INSERT` reached 5,000 a second at about a twelfth of the CPU per document (SDK 5.1.0 and 5.2.0, 14-core Mac; `§ Pattern 2: Append-only event documents`).

**Guide**: `§ ON ID CONFLICT`, `§ UPDATE`, `§ Prefer field-level updates over whole-document rewrites`, `§ Assigning an object merges it`, `§ Prefer field-level updates`

| Policy | When the `_id` already exists locally |
|---|---|
| `FAIL` (default) | The statement fails |
| `DO NOTHING` | Existing document unchanged; no error |
| `DO UPDATE` | Supplied fields are written (merged; fields not supplied remain). Identical values are still written, the document is reported as mutated, and observers can fire again |
| `DO UPDATE_LOCAL_DIFF` | Same merge, but only differing fields are written; nothing is written when nothing changed (for upserts and re-imports; it does not protect a stale in-memory copy) |

With the default strict mode (`DQL_STRICT_MODE = false`), object fields are CRDT maps:

| Starting `address` | Statement | Result |
|---|---|---|
| `{"city": "Oslo", "zip": "0150"}` | `SET address = :a` with `{"country": "NO"}` | `{"city": "Oslo", "zip": "0150", "country": "NO"}` |
| `{"city": "Oslo", "zip": "0150"}` | `SET address = {}` | Unchanged (the document is still reported as mutated) |
| `{"city": "Oslo", "zip": "0150"}` | `UNSET address.zip` | `{"city": "Oslo"}` |
| `{"city": "Oslo", "zip": "0150"}` | `UNSET address`, then `SET address = :a` with `{"city": "Bergen"}` (inside one transaction) | `{"city": "Bergen"}` |

```sql
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

UPDATE orders SET status = :status WHERE _id = :id AND coalesce(status, :none) != :status

UPDATE orders UNSET discountCode, pricing.discount WHERE _id = :id
```

An `UPDATE` that sets a field to its current value is still recorded as a mutation, appears in the result's mutated document IDs, and can wake observers. Skip such writes with a `WHERE` condition (with `coalesce` so missing or `null` values stay eligible) or use `DO UPDATE_LOCAL_DIFF`.

- Update nested fields individually (`SET address.city = :city`) instead of assigning the whole object.
- Do not read a document, modify it in app code, and write the whole document back with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF`: a stale value that differs from the stored one is written back.
- Do not expect `DO UPDATE` or `SET obj = {...}` to replace an object; with the default strict mode they merge, and fields not supplied remain (remove keys with `UNSET`).
- Why: Ditto syncs changes at field level. Rewriting a whole document makes the change larger, and an unchanged field written by this device can win a merge against a real concurrent change made on another device.

---

## Logging Details

**Guide**: `§ Logging`, `§ Configuring logging`, `§ Log levels`, `§ Forwarding logs to your own pipeline`, `§ On-disk logs and exporting them`; each SDK page's *Logging in <SDK>* section

| Level | Typical use |
|---|---|
| `error` | Failures that need attention |
| `warning` | Unexpected situations Ditto handled (recommended for production) |
| `info` | High-level lifecycle events (default) |
| `debug` | Detailed diagnostics (recommended while debugging) |
| `verbose` | Very detailed tracing; can slow down replication |

- Configure the logger before Ditto opens (Flutter: `DittoLogger` members throw until the SDK is initialized, so call `await Ditto.init()` first, then `Ditto.open`).
- `isEnabled` and `minimumLogLevel` control the logs Ditto emits at runtime, not the on-disk logs. On-disk logs always include debug-level entries, so a `warning` console level in production does not reduce what support can retrieve.
- Set the level explicitly: `warning` in production, `debug` while debugging; use `verbose` only for short, targeted investigations.
- Forward log events with the SDK's callback or stream (Flutter `customLogCallback`, JavaScript `setCustomLogCallback`, Kotlin `observeLogEvents()`, Swift `setCustomLogCallback(_:)`); keep the receiving code fast. In Flutter, `ditto.close()` resets `customLogCallback` to `null` for the whole process, so set it again before every `Ditto.open()` (after `Ditto.init()`).
- Flutter: `DittoLogger.isDevtoolsLoggingEnabled = true` also sends Ditto logs to Flutter DevTools.
- On-disk logs (debug level and above) are kept in the persistence directory of the most recently created `Ditto` instance, about 15 MB of compressed logs or 15 days of logs by default (older entries are discarded once one of these limits is reached). They rotate in files of up to 1 MB or 24 hours each, and at most 15 files are kept (`ROTATING_LOG_FILE_MAX_SIZE_MB`, `ROTATING_LOG_FILE_MAX_AGE_H`, `ROTATING_LOG_FILE_MAX_FILES_ON_DISK`); leave them at their defaults unless Ditto support advises otherwise.
- Each write added about 1.5 KB of debug log on SDK 5.1.0 and 5.2.0 (in testing); the active file grew to 15 to 18 MB before rotating, each rotated file was about 0.6 MB compressed, and the 15 files held about 200,000 writes (about 5 hours at 10 writes a second).
- Retrieve on-disk logs from the Ditto Portal device dashboard or with the logger's export (Flutter `exportLogs(path)`, JavaScript and Kotlin `exportToFile(path)`, Swift `export(to:)`; gzip-compressed JSON Lines; the file must not exist and its directory must exist; returns the byte count). Use a fresh, timestamped `.jsonl.gz` path.
- On-disk logs contain the text and argument values of this device's subscriptions and of those of directly connected devices, at every console level; document values, `execute` statements and arguments, and peer metadata did not appear (in testing with SDK 5.1.0 and 5.2.0). Do not filter subscriptions by personal data, because the logs leave the device when exported or requested.
- Data bundles requested through the Ditto Portal include (SDK 5.1+) a `config_snapshot.json` file with the device's effective configuration.

---

## System Virtual Collections

**Guide**: `§ System Virtual Collections`, `§ Request diagnostics`

Local only, read only, and snapshot-based. Query them with `execute`; do not register long-lived observers on `system:system_info` (they fire often even when nothing changed: every 500 ms in SDK 5.1.0, and in testing with 5.2.0 about twice per second, mostly with identical results), or observers on `system:data_sync_info` in many places (with SDK 5.1.0 an idle observer fired only when the rows changed; older Ditto documentation described a 500 ms interval, so do not rely on either behavior). For live sync status, use a single observer with a trivial callback, as shown in `§ Monitoring Sync Status`.

| Collection | Purpose |
|---|---|
| `system:system_info` | Key/value rows: SDK version, database ID, storage usage, subscriptions, log settings, non-default parameters |
| `system:indexes` | Indexes on this device |
| `system:data_sync_info` | One row per sync connection. `sync_session_status` stays `"Connected"` for about 73 s after a disconnect (SDK 5.1.0 and 5.2.0); use presence for live connectivity |
| `system:active_requests` | DQL requests executing now |
| `system:request_history` | Recently completed requests matching the history qualifiers (in memory). **Note (SDK 5.2.0):** with the default qualifiers, only queries of about 10 seconds or more were recorded in testing (5.1.0 recorded queries of 3 seconds); set `DQL_REQUEST_HISTORY_QUALIFIERS` to `{'threshold': 1000}` to record faster ones. **Note (SDK 5.1.0 and 5.2.0):** setting the qualifiers merges into the current ones, and `RESET` and `SET ... TO DEFAULT` leave them in effect until Ditto is opened again, so name each qualifier you change back (`§ Request diagnostics`) |
| `system:shared_statements` | Prepared-statement cache with execution statistics |
| `system:metrics` | SDK metrics; disabled by default, and enabled only at startup (see the parameter below). SDK 5.2 adds query metrics (`ditto.query.requests`, `ditto.query.failed`, `ditto.query.execution_time`), `ditto.store.observer.retained_bytes`, `ditto.store.database.sync_degraded_document_count`, SQLite WAL values, and transport counters |
| `system:sync_degradations` (SDK 5.2+) | Documents whose sync is degraded on this device, with the reason (currently `documentTooBig`, see `§ Document Size Limits`). Include it in diagnostics so that a document that stopped syncing is found before a user reports it |
| `system:support_bundles` (SDK 5.2+) | Support bundles stored on this device (see [Support Bundles](#support-bundles)) |

```sql
SELECT key, value FROM system:system_info WHERE namespace = 'logs'

SELECT key, value FROM system:system_info WHERE key LIKE 'non_default_system_parameter%'

SELECT _id, text, state, times FROM system:active_requests

SELECT * FROM system:sync_degradations

-- SQLite write-ahead log (SDK 5.2+): wal_current_size_bytes, wal_peak_size_bytes, ...
SELECT key, value FROM system:system_info WHERE namespace = 'backend_sqlite3'
```

The last query reads the WAL values. Since SDK 5.2, Small Peers keep the WAL in check and reclaim free disk space automatically, and Ditto logs a warning when the WAL grows past `BACKEND_SQLITE3_WAL_SIZE_THRESHOLD_BYTES` (1 GiB by default); the usual cause is a read transaction that stays open for a long time (`§ Monitoring Storage`).

---

## System Parameters for Diagnostics

**Guide**: `§ System Parameters Reference`

| Parameter | Default | Purpose |
|---|---|---|
| `DQL_STRICT_MODE` | `false` | When `true`, the planner (5.1.0 and 5.2.0) uses no secondary index scans |
| `DQL_SLOW_REQUEST_WARN_SECONDS` (SDK 5.1+) | `60` | Slow-request warning threshold; `0` disables |
| `DQL_REQUEST_TIMEOUT_SECONDS` (SDK 5.1+) | `0` | Request timeout; `0` disables |
| `DQL_REQUEST_HISTORY_SIZE` | `128` (`4096` in 5.1) | Entries kept in `system:request_history`; set it explicitly if your diagnostics read more of the history |
| `DQL_DEFAULT_DIRECTIVES` | `{}` | Default directives for every statement |
| `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED` | `false` | Enables `system:metrics`; read only at startup, so `ALTER SYSTEM` after `Ditto.open` has no effect. Pass it in `DittoConfig.systemParameters` (SDK 5.2+) or set the environment variable `DITTO_METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED=true` before the process starts (both verified with the JavaScript SDK on Node.js). Once enabled, it stays enabled for every `Ditto` instance in the process |
| `BACKEND_SQLITE3_WAL_SIZE_THRESHOLD_BYTES` (SDK 5.2+) | `1073741824` (1 GiB) | WAL size above which Ditto logs a warning |
| `SUPPORT_BUNDLE_REQUEST_RATE` / `SUPPORT_BUNDLE_REQUEST_TIMEOUT` / `SUPPORT_BUNDLE_RETENTION_LIMIT` (SDK 5.2+) | `3` / `30` / `10` | Support bundle requests per rolling 10 minutes (`0` turns bundles off), seconds per bundle, and bundles kept |

```sql
SHOW ALL LIKE 'dql_slow%'

ALTER SYSTEM RESET DQL_SLOW_REQUEST_WARN_SECONDS
```

Settings are not persisted. Pass the ones your app always needs in the system parameters of `DittoConfig` on every open (SDK 5.2+), and use `ALTER SYSTEM` for changes while the app runs; on SDK 5.1, run `ALTER SYSTEM` after every open, before sync starts (`§ Applying System Parameters`, `§ Applying parameters at startup`). Example: `logging-configuration-good` in `../examples/<sdk>/` (Flutter: `appSystemParameters` and `logNonDefaultParameters`).

---

## Support Bundles

**Guide**: `§ Support bundles (SDK 5.2+)`

A support bundle packages the device's on-disk logs, its effective configuration, and runtime telemetry into one `tar` archive for Ditto support. Since SDK 5.2, the app can create one on the device with DQL, without a connection to Ditto Server (native platforms only, not the Web), for example from an admin screen or a "Send diagnostics" button:

```sql
EXECUTE FUNCTION system_request_support_bundle({'metadata': {'requested_by': 'support'}})

SELECT * FROM system:support_bundles ORDER BY _id.created_at DESC
```

The function returns one document with `_id` (the peer key and the capture time), `reason` (`USER_INITIATED`), and `file`, an attachment token for the archive; fetch it with `fetchAttachment()` (the code for each SDK: `logging-configuration-good` in `../examples/<sdk>/` and *Logging in <SDK>* on the SDK page). A request over `SUPPORT_BUNDLE_REQUEST_RATE` fails with `support bundle request rate exceeded`, and the count survives restarts. The log export contains the full peer keys of other devices and absolute file paths on the device: review a bundle before you share it beyond Ditto support. Bundles stay on the device until the app fetches and shares them.
