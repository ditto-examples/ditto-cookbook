# Performance and Observability Reference (SDK 5.1.0)

Detailed rules behind the [performance-observability skill](../SKILL.md). Everything here is extracted from the Ditto best practices guide; `§ <Heading>` cites a section of [../../guide/reference/ditto.md](../../guide/reference/ditto.md) (find it with Grep for the heading text) for full explanations and example output.

## Table of Contents

- [Observer Behavior](#observer-behavior)
- [Observer Lifecycle in Flutter](#observer-lifecycle-in-flutter)
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

---

## Observer Behavior

**Guide**: `§ Observing Changes`, `§ Store Observers in Flutter`, `§ Observer lifecycle and cleanup`, `§ Diffing Results`

| API (Flutter) | Status | Returns | Backpressure |
|---|---|---|---|
| `registerObserver` | Stable | `StoreObserver` | None |
| `registerObserverV2` | **(Experimental)** (SDK 5.1+) | `StoreObserverV2` | Automatic: follows pause/resume of `changes` |
| `registerObserverWithSignalNext` | **(Experimental)** (SDK 5.1+) | `StoreObserverV2` | Manual: call `signalNext()` |

All three accept only `SELECT` queries and take parameters through `arguments:`. Observers never cause data to sync; pair them with a subscription.

Behavior:
- `registerObserver` has no backpressure: it never waits for your code.
- With `onChange`, events emitted before the first listener attaches are buffered; listen right after registering. `registerObserverV2` starts observing as soon as it is registered, with or without `onChange`, so listen to its `changes` right away.
- `registerObserverV2`: while the stream is paused, Ditto stops delivering after the update that arrived at the pause; on resume, that update and the latest state are delivered. Leaving an `await for` loop cancels the subscription and the observer; `ditto.close()` does not end the loop, so cancel the observer before closing.
- `registerObserverWithSignalNext`: one result, then nothing until `signalNext()`. Do not pause or resume its stream (the SDK logs a warning).
- `Differ` keeps the previous result in memory, and diffing is computationally expensive; debounce updates for large or busy result sets and keep diffed queries bounded (for example, with `LIMIT`). `Differ` only accepts items produced by Ditto (test doubles throw an `ArgumentError`).

Other platforms (`§ Backpressure on other platforms`):

| Platform | Default observer | Backpressure |
|---|---|---|
| JavaScript | `registerObserver(query, handler, args)` signals when the handler **returns**; an `async` handler is not awaited | `registerObserverWithSignalNext(query, (result, signalNext) => {...}, args)` |
| Swift | `registerObserver(query:arguments:deliverOn:handler:)`, main queue by default | `handlerWithSignalNext:`; pass `deliverOn:` to move heavy work off the main queue |
| Kotlin | `registerObserver(query, args) { result -> }` (suspending) or `observe(...)` returning a `Flow` | No `signalNext`; suspending handlers, `collect(...)`, or `.conflate()`; release with `close()` |

---

## Observer Lifecycle in Flutter

**Guide**: `§ Observer lifecycle and cleanup`, `§ Resource Cleanup and Shutdown`

| Behavior (`registerObserver`) | What to do |
|---|---|
| Without `onChange`, the query starts when `changes` is first listened to | Listen right after registering |
| `changes` is single-subscription; a second `listen()` throws a `StateError` (`Bad state: Stream has already been listened to.`), even after the first subscription was cancelled | Hand the stream to exactly one listener or `StreamBuilder`, and keep that `StreamBuilder` mounted |
| Cancelling the `StreamSubscription` does not cancel a `StoreObserver` | Always call `observer.cancel()` as well |
| `observer.cancel()` closes `changes` | A pending `await for` loop ends |
| `await ditto.close()` does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2`, and `cancel()` does nothing once Ditto is closed | Cancel stream subscriptions and observers before closing |
| Cancelling the stream subscription of a `StoreObserverV2` also cancels the observer | Still call `cancel()` in your cleanup path for clarity |

**✅ DO:**
- Register observers in `initState()` or in a service or controller, never in `build()`
- Cancel the stream subscription **and** the observer in `dispose()`
- Let observers follow screen scope; keep subscriptions at app or feature scope
- Add `ORDER BY` whenever result order matters (use `_id` as a tie-breaker); without it the order of observer results is not guaranteed (`§ Stable ordering`)
- Copy values out of the result (`item.value` or your own model objects) instead of keeping `QueryResult` or `QueryResultItem` objects in state or caches (`§ Working with Query Results`)

**❌ DON'T:**
- Create an observer per list item; observe the list once and pass values down
- Rely on `ditto.close()` to end an `await for` loop over `registerObserver` results
- Listen to `changes` twice; it is a single-subscription stream

The full widget (`OrdersList`: `registerObserver` without `onChange` in `initState()`, one `StreamSubscription` that copies `item.value` into state inside `setState`, `ListView.builder` with `ValueKey(order['_id'])`, both cancelled in `dispose()`) is Pattern 1 of [../examples/flutter-observer-performance.dart](../examples/flutter-observer-performance.dart); the onChange-only anti-pattern is in the same file.

---

## Backpressure Example: registerObserverV2

**Guide**: `§ Backpressure (SDK 5.1+)`, `§ registerObserverV2 (Experimental)`, `§ Choosing an observer API`

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
- The experimental APIs may change in a future release; `registerObserver` remains the default for UI code.

---

## Differ

**Guide**: `§ Diffing Results`, `§ Animated lists`, `§ Partial UI Updates`

- `diff()` takes a `List<QueryResultItem>` (pass `result.items.toList()`).
- The first call reports every item as an insertion.
- `deletions` index the **old** list; `insertions` and `updates` index the **new** list.
- It does not give you the old items; keep previous values yourself.
- `Differ` keeps the previous result in memory and diffing is expensive; use it only where you need to know what changed (for example `AnimatedList`), and keep diffed queries bounded with `LIMIT`. A `ListView.builder` with keys does not need it.
- `item.value` creates a new `Map` for every result, and two maps with identical contents are never `==`; map results to immutable model classes that implement `==` if you rely on equality to skip rebuilds.

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
| `a = 1 AND b = 2` (separate indexes) | Intersect scan | A composite index on `(a, b)` is generally better |
| `address.city = 'Tokyo'` (index on `address.city`) | Index scan | Index the full path you filter on |
| `tags = ['x', 'y']` (index on `tags`) | Index scan | Whole-value match only |
| `array_contains(tags, 'x')`, `:tag IN tags` | Collection scan | Element lookups cannot use an index |
| `SELECT COUNT(*) FROM orders` (no `WHERE`) | Count scan | Does not read documents |

Constraints (`§ Creating Indexes`, `§ Strict mode and data types`):
- Expression, partial, and functional indexes are not supported.
- `IF NOT EXISTS` checks only the index **name**; to change a definition, create it under a new name or drop and recreate it.
- `DROP INDEX` requires `ON <collection>`.
- With `DQL_STRICT_MODE` set to `true`, the SDK 5.1.0 planner uses no secondary indexes; queries that would use an index scan fall back to a collection scan. ID lookups and full-collection `COUNT(*)` are not affected, and `ADVISE` returns no suggestions.
- Only the most recently written CRDT type of a field is indexed. If the same field is written with different type declarations (for example `REGISTER` and `MAP`), an index on it can return incorrect or mis-ordered results; keep type declarations consistent, and do not index fields written with more than one type.

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

```sql
ADVISE SELECT * FROM orders WHERE status = :status AND isDeleted = false ORDER BY createdAt DESC
```

Development-only Dart helper that prints suggestions:

```dart
// ✅ GOOD: Development-only helper that prints index suggestions (SDK 5.1+).
Future<void> printOrderIndexAdvice(Ditto ditto) async {
  final result = await ditto.store.execute(
    'ADVISE SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  final advice = result.items.first.value['advice'] as Map<String, dynamic>;
  final suggested = (advice['suggestedIndexes'] as List<dynamic>?) ?? const [];
  if (suggested.isEmpty) debugPrint('No suggestions: ${advice['outcome']}');
  for (final index in suggested) {
    debugPrint('${(index as Map<String, dynamic>)['statement']}');
  }
}
```

The `ADVISE` SQL statement above (not the Dart helper) filters with `isDeleted = false`, which is correct only when every document has the field; otherwise keep the `coalesce` form (see `§ Indexing soft-delete filters`).

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
- Filter in `WHERE`, not in Dart
- Project only the fields you need (subscriptions still sync whole documents and accept only `SELECT *`)
- Use `ORDER BY ... LIMIT` for local queries and observers that need the first rows
- Keep query strings constant and pass values as parameters (prepared statements are cached)
- Prefer keyset pagination with an `_id` tie-breaker (`WHERE createdAt < :after OR (createdAt = :after AND _id < :afterId) ORDER BY createdAt DESC, _id DESC LIMIT :pageSize`) over large `OFFSET` values, which re-read and skip earlier rows
- Use `DISTINCT` only on a few low-cardinality fields; it keeps every distinct row in memory
- Count with `COUNT(*)` and check existence with `LIMIT 1`

**❌ DON'T:**
- Observe an entire large collection and filter or paginate in Dart
- Run one query per ID when `WHERE _id IN :ids` returns the same data
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

**Guide**: `§ Long-running requests (SDK 5.1+)`, `§ Flutter execution model`

| Parameter | Default | Effect |
|---|---|---|
| `DQL_SLOW_REQUEST_WARN_SECONDS` (SDK 5.1+) | `60` | Logs a warning with request details once a request runs this long, repeated at the same interval; `0` disables |
| `DQL_REQUEST_TIMEOUT_SECONDS` (SDK 5.1+) | `0` (disabled) | Cancels longer requests with a timeout error (cooperative cancellation) |

```sql
ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 10

ALTER SYSTEM SET DQL_REQUEST_TIMEOUT_SECONDS = 30
```

System parameters are not persisted: apply them after every `Ditto.open`, before `ditto.sync.start()`. Before enabling a timeout in production, handle the resulting error for every query.

On native platforms, `ditto.store.execute` runs on a long-lived worker isolate per `Ditto` instance, so a slow query does not block the UI isolate. `Store.experimentalSkipExecuteIsolateOffload` **(Experimental)** runs `execute` inline on the calling isolate; any slow query then blocks that isolate (usually the UI). Use it only after measuring a real throughput problem with many very small queries.

---

## Avoiding Unnecessary Writes

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

An `UPDATE` that sets a field to its current value is still recorded as a mutation, appears in `mutatedDocumentIDs()`, and can wake observers. Skip such writes with a `WHERE` condition (with `coalesce` so missing or `null` values stay eligible) or use `DO UPDATE_LOCAL_DIFF`.

- Update nested fields individually (`SET address.city = :city`) instead of assigning the whole object.
- Do not read a document, modify it in Dart, and write the whole map back with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF`: a stale value that differs from the stored one is written back.
- Do not expect `DO UPDATE` or `SET obj = {...}` to replace an object; with the default strict mode they merge, and fields not supplied remain (remove keys with `UNSET`).
- Why: Ditto syncs changes at field level. Rewriting a whole document makes the change larger, and an unchanged field written by this device can win a merge against a real concurrent change made on another device.

---

## Logging Details

**Guide**: `§ Logging`, `§ Configuring logging in Flutter`, `§ Forwarding logs to your own pipeline`, `§ On-disk logs and exporting them`

| `LogLevel` | Typical use |
|---|---|
| `error` | Failures that need attention |
| `warning` | Unexpected situations Ditto handled (recommended for production) |
| `info` | High-level lifecycle events (default) |
| `debug` | Detailed diagnostics (recommended while debugging) |
| `verbose` | Very detailed tracing; can slow down replication |

- `DittoLogger` members throw until the SDK is initialized; call `await Ditto.init()` before configuring logging, then `Ditto.open`.
- `isEnabled` and `minimumLogLevel` control the logs Ditto emits at runtime, not the on-disk logs. On-disk logs always include debug-level entries, so a `warning` console level in production does not reduce what support can retrieve.
- Set the level explicitly: `warning` in production, `debug` while debugging; use `verbose` only for short, targeted investigations.
- `customLogCallback` receives the log events that Ditto emits; keep it fast. `ditto.close()` resets it to `null` for the whole process, so set it again before every `Ditto.open()` (after `Ditto.init()`).
- `DittoLogger.isDevtoolsLoggingEnabled = true` also sends Ditto logs to Flutter DevTools.
- On-disk logs (debug level and above) are kept in the persistence directory of the most recently created `Ditto` instance, about 15 MB of compressed logs or 15 days of logs by default (older entries are discarded once one of these limits is reached). They rotate in files of up to 1 MB or 24 hours each, and at most 15 files are kept (`ROTATING_LOG_FILE_MAX_SIZE_MB`, `ROTATING_LOG_FILE_MAX_AGE_H`, `ROTATING_LOG_FILE_MAX_FILES_ON_DISK`); leave them at their defaults unless Ditto support advises otherwise.
- Retrieve on-disk logs from the Ditto Portal device dashboard or with `DittoLogger.exportLogs(path)` (gzip-compressed JSON Lines; the file must not exist and its directory must exist; returns the byte count). Use a fresh, timestamped `.jsonl.gz` path.
- Data bundles requested through the Ditto Portal include (SDK 5.1+) a `config_snapshot.json` file with the device's effective configuration.

---

## System Virtual Collections

**Guide**: `§ System Virtual Collections`, `§ Request diagnostics`

Local only, read only, and snapshot-based. Query them with `execute`; do not register long-lived observers on `system:system_info` (they fire every 500 ms regardless of whether anything changed), or observers on `system:data_sync_info` in many places (documented as firing every 500 ms; with SDK 5.1.0 an idle observer fired only when the rows changed, so do not rely on either behavior). For live sync status, use a single observer with a trivial callback, as shown in `§ Monitoring Sync Status`.

| Collection | Purpose |
|---|---|
| `system:system_info` | Key/value rows: SDK version, database ID, storage usage, subscriptions, log settings, non-default parameters |
| `system:indexes` | Indexes on this device |
| `system:data_sync_info` | One row per sync connection. `sync_session_status` stays `"Connected"` for about 73 s after a disconnect (SDK 5.1.0); use presence for live connectivity |
| `system:active_requests` | DQL requests executing now |
| `system:request_history` | Recently completed requests matching the history qualifiers (in memory) |
| `system:shared_statements` | Prepared-statement cache with execution statistics |
| `system:metrics` | SDK metrics; disabled by default, and can be enabled only at process start (see the parameter below) |

```sql
SELECT key, value FROM system:system_info WHERE namespace = 'logs'

SELECT key, value FROM system:system_info WHERE key LIKE 'non_default_system_parameter%'

SELECT _id, text, state, times FROM system:active_requests
```

---

## System Parameters for Diagnostics

**Guide**: `§ System Parameters Reference`

| Parameter | Default | Purpose |
|---|---|---|
| `DQL_STRICT_MODE` | `false` | When `true`, the 5.1.0 planner uses no secondary index scans |
| `DQL_SLOW_REQUEST_WARN_SECONDS` (SDK 5.1+) | `60` | Slow-request warning threshold; `0` disables |
| `DQL_REQUEST_TIMEOUT_SECONDS` (SDK 5.1+) | `0` | Request timeout; `0` disables |
| `DQL_REQUEST_HISTORY_SIZE` | `4096` | Entries kept in `system:request_history` |
| `DQL_DEFAULT_DIRECTIVES` | `{}` | Default directives for every statement |
| `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED` | `false` | Enables `system:metrics`, only at process start: `ALTER SYSTEM` after `Ditto.open` has no effect; the environment variable `DITTO_METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED=true` works (verified on Node.js) |

```sql
SHOW ALL LIKE 'dql_slow%'

ALTER SYSTEM RESET DQL_SLOW_REQUEST_WARN_SECONDS
```

Settings are not persisted; apply them after every `Ditto.open`, before `ditto.sync.start()` (`§ Applying System Parameters`).
