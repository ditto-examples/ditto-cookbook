# Performance Measurements

How long Ditto's statements, queries, and observers took, how many writes a device could make in a second, how much memory query results and observers kept, and how much CPU a hub spent as more devices connected. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The times come from one Mac and serve to compare approaches; Ditto's own benchmark on an Android device is quoted in [Counting documents](../../best-practices/indexing-and-performance.md#counting-documents). The rules that follow from these observations are in [Query Scope and Execution](../../best-practices/indexing-and-performance.md#query-scope-and-execution), [Index Usage Rules](../../best-practices/indexing-and-performance.md#index-usage-rules), [INSERT and Conflict Handling](../../best-practices/dql.md#insert-and-conflict-handling), [Large results](../../best-practices/dql.md#large-results), and [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

**In brief**

- Each `execute` call has a fixed cost of about 1.7 ms, so the number of statements matters more than the number of documents: 2,000 inserts took 3,930 to 4,659 ms one by one and 16 to 18 ms as one statement on SDK 5.1.0 and 5.2.0 ([The number of execute calls matters more than the number of documents](#the-number-of-execute-calls-matters-more-than-the-number-of-documents)).
- On SDK 5.1.0 and 5.2.0, awaited one at a time, statements that write one document each top out at about 600 documents a second and cost about 2 ms of CPU per document on the writing and the receiving device; 50 to 100 documents per statement reached 5,000 to 10,000 a second ([One document per statement tops out at about 600 writes a second](#one-document-per-statement-tops-out-at-about-600-writes-a-second)).
- `WHERE _id IN :ids` slows down as the list of IDs grows, and `USE IDS LIST :ids` much less: with 10,000 IDs, a count took 686 to 725 ms against 17 to 21 ms, and writes on 5.2.0 took 693 to 732 ms against 20 to 65 ms, while on 5.1.0, `EVICT` and `DELETE` with `USE IDS LIST` removed nothing ([Long ID lists are faster with USE IDS LIST than with WHERE _id IN](#long-id-lists-are-faster-with-use-ids-list-than-with-where-_id-in)).
- A full-collection `COUNT(*)` took 1.7 to 1.8 ms on 20,000 documents, indexes made filtered queries about 3 to 11 times faster, 11 conditions of the Index Usage Rules table produced the listed plans, and a query answered from the index alone took about two thirds of the time ([A full COUNT(*) is fast, and indexes made selective queries several times faster](#a-full-count-is-fast-and-indexes-made-selective-queries-several-times-faster), [Eleven conditions of the Index Usage Rules table produced the plans it lists](#eleven-conditions-of-the-index-usage-rules-table-produced-the-plans-it-lists), [A query answered from the index alone took about two thirds of the time](#a-query-answered-from-the-index-alone-took-about-two-thirds-of-the-time)); on 5.1.0 and 5.2.0, an index on a field with only two values made a query slower than no index, and a composite index was the fastest ([On SDK 5.1.0 and 5.2.0, an index on a field with two values made a query slower than no index](#on-sdk-510-and-520-an-index-on-a-field-with-two-values-made-a-query-slower-than-no-index)).
- Query strings built for each value were not slower than constant strings with parameters ([Constant query strings were not faster](#constant-query-strings-were-not-faster)).
- On 5.1.0 and 5.2.0, an observer of 5,000 documents was called about 5 to 6 times later after a write than an observer of 50, and evicting in chunks and opening a large store cost little ([On SDK 5.1.0 and 5.2.0, an observer of 5,000 documents was called about 5 to 6 times later than one of 50](#on-sdk-510-and-520-an-observer-of-5000-documents-was-called-about-5-to-6-times-later-than-one-of-50), [Evicting in chunks costs little more than one statement](#evicting-in-chunks-costs-little-more-than-one-statement), [Opening Ditto took the same time with 1,000 and 200,000 documents](#opening-ditto-took-the-same-time-with-1000-and-200000-documents)).
- Large query results raise the process's memory, which does not come back after the results are released; 5.2.0 used about 20 to 30% less than 5.1.0 while holding them, and about 35% less after reading them ([Large query results keep process memory after they are released](#large-query-results-keep-process-memory-after-they-are-released)).
- An observer that returned 200 documents while other devices kept updating them grew the process's memory by about 13 to 24 KiB on every callback; an observer of one row leveled off after about 5 minutes on 5.1.0 and 5.2.0 ([An observer of 200 documents grows memory on every callback](#an-observer-of-200-documents-grows-memory-on-every-callback)).
- The CPU that a hub spends on each change grows with the number of connected devices, and when every device writes, the hub's CPU grows faster than the number of devices ([Hub CPU per change grows with the number of connected devices](#hub-cpu-per-change-grows-with-the-number-of-connected-devices)).

## Statements and Write Rates

### The number of execute calls matters more than the number of documents

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, five runs each, and 5.0.3, four runs; each time is the median of three repetitions within a run. Every run gave the same order of the methods |
| Setup | (1) Inserting 2,000 new documents in different ways. (2) Reading 500 of 20,000 documents by ID, as 500 queries with `_id = :id` and as one query with `_id IN :ids` |

Inserting 2,000 documents:

| Method | 5.2.0 | 5.1.0 | 5.0.3 |
|---|---|---|---|
| 2,000 `INSERT` statements, each awaited | 3,930 to 4,645 ms | 3,957 to 4,659 ms | 5,199 to 5,567 ms |
| One statement with an array parameter | 17 to 18 ms | 16 to 18 ms | 108 to 112 ms |
| 10 statements of 200 documents each | 30 to 33 ms | 30 to 32 ms | 112 to 114 ms |
| 2,000 `tx.execute` calls in one transaction | 238 to 248 ms | 236 to 242 ms | 179 to 183 ms |
| 2,000 statements sent at once with `Promise.all` | 676 to 779 ms | 530 to 539 ms | 1,173 to 2,081 ms |

- One statement with an array parameter was 232 to 269 times faster than 2,000 awaited statements on 5.2.0, 240 to 279 times on 5.1.0, and 47 to 50 times on 5.0.3. Running the 2,000 statements in one transaction did not close the gap: on 5.1.0 and 5.2.0, it was still 13 to 15 times slower than the single statement (5.0.3: 1.6 to 1.7 times).
- Reading 500 of 20,000 documents took 812 to 876 ms as 500 queries with `_id = :id` and 11 to 15 ms as one query with `_id IN :ids` on 5.2.0, 55 to 78 times faster (5.1.0: 782 to 854 ms and 6 to 15 ms). On 5.0.3, the `IN` query took 52 to 53 ms, 16 to 17 times faster than the loop.
- Each `execute` call has a fixed cost of about 1.7 ms (5.0.3: about 6.5 ms; see [Constant query strings were not faster](#constant-query-strings-were-not-faster)), so the number of calls matters more than the number of documents.

**Used in:** [INSERT and Conflict Handling](../../best-practices/dql.md#insert-and-conflict-handling), [Query Scope and Execution](../../best-practices/indexing-and-performance.md#query-scope-and-execution).

### One document per statement tops out at about 600 writes a second

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each, on a 14-core Mac, with the other timing measurements stopped while this one ran |
| Setup | A writing and a receiving device in separate processes, connected directly over TCP. The writer wrote new documents `{ _id, seq, at, payload }`, each with a 100-byte random `payload`, at a target rate for 10 seconds, awaiting each statement before the next. The receiver subscribed to all documents, had an index on `seq`, and queried for new documents every 50 ms. The delay is the time from the write until the receiver's query saw the document, so it includes the 50 ms query interval. The eight cases ran one after another with the same two processes and stores |

Writes (5.2.0; values for 5.1.0 and 5.0.3 in parentheses where they were recorded; "same" means the same as on 5.2.0):

| Target per second × documents per statement | Documents written per second | Time per statement (median) | CPU, writer / receiver |
|---|---|---|---|
| 100 × 1 | 100 | 1.7 ms (5.1.0: same; 5.0.3: 2.1 ms) | 0.3 / 0.3 cores |
| 500 × 1 | 496 (5.1.0: same; 5.0.3: 224 to 485) | 1.7 ms (5.1.0: same; 5.0.3: 1.9 to 3.5 ms) | 1.2 / 1.1 cores |
| 1,000 to 5,000 × 1 | 591 to 600 (5.1.0: 584 to 597; 5.0.3: 150 to 529) | 1.7 ms (5.1.0: same; 5.0.3: 1.8 to 6.5 ms) | 1.4 / 1.3 cores (5.1.0: 1.3 / 1.2; 5.0.3: 0.2 to 1.1) |
| 2,000 × 50 | 1,997 | 2.0 ms (5.1.0: same; 5.0.3: 4.4 ms) | 0.4 / 0.5 cores |
| 5,000 × 50 | 4,992 (5.1.0: same; 5.0.3: 4,980) | 2.2 ms (5.1.0: same; 5.0.3: 6.3 ms) | 0.8 / 1.0 cores |
| 10,000 × 100 | 9,984 (5.1.0: 9,982; 5.0.3: 8,420 to 8,517) | 2.7 ms (5.1.0: same; 5.0.3: 11.1 ms) | 0.9 / 1.3 cores |

Delay on the receiver (median / 95th percentile / maximum):

| Target per second × documents per statement | 5.2.0 | 5.1.0 | 5.0.3 |
|---|---|---|---|
| 100 × 1 | 31 / 55 / 58 to 64 ms | Same as 5.2.0 | 33 / 58 / 65 to 72 ms |
| 500 × 1 | 32 / 56 / 60 to 62 ms | Same as 5.2.0 | Maximum 85 to 124 ms |
| 1,000 to 5,000 × 1 | 31 to 32 / 56 / 60 to 64 ms | Maximum 62 to 110 ms | Maximum 72 to 264 ms |
| 2,000 × 50 | 34 / 58 / 61 to 65 ms | Same as 5.2.0 | 39 to 41 / 64 to 368 / 153 to 864 ms |
| 5,000 × 50 | 39 / 65 / 71 to 83 ms | Same as 5.2.0 | 68 to 79 / 1,766 to 2,361 / 2,262 to 2,815 ms |
| 10,000 × 100 | 192 to 237 / 312 to 371 / 349 to 422 ms | 152 to 164 / 239 to 246 / 273 to 298 ms | 6.3 to 6.8 / 9.2 to 10.0 / 9.7 to 10.5 s |

- Up to 5,000 documents a second, the delays are almost entirely the query interval: if the real delay is a constant 10 ms or so, a query every 50 ms measures a median of about 30 ms and a maximum of about 60 ms. Only the 10,000-a-second row (0.15 to 0.42 s) and the rows where 5.0.3 fell behind show Ditto's own delay.
- With one document per statement, each statement takes about 1.7 ms, so awaiting one statement after another cannot write more than about 600 documents a second. A target of 5,000 a second did not change that. On 5.0.3, the time per statement varied, and the writer reached 150 to 529 documents a second.
- With one document per statement, the writer and the receiver each used about 2.2 to 2.3 ms of CPU per document (1.4 / 1.3 cores at 600 documents a second). With 50 documents per statement, they used about 0.16 / 0.19 ms per document, 12 to 15 times less on both sides. Because the receiver's CPU drops as well, the receiver probably has work to do for every commit. The receiver's CPU includes maintaining the `seq` index that its queries used; the writer, which had no index, also used about 2.3 ms per document, so the index is not the main part.
- On 5.1.0 and 5.2.0, the receiver kept up at every rate. After the writer finished, the receiver held every document within 0 to 3 ms up to 5,000 a second (the first check already found them all), and within 0.11 to 0.22 s at 10,000 a second. At 10,000 a second, the delay grew to about 0.3 to 0.4 s in the first few seconds and then stopped growing. Because the cases ran in the same stores, the receiver already held about 190,000 documents in this case (resident memory 370 to 425 MiB), so the effects of the rate and of the store size are not separated.
- On 5.0.3, 50 to 100 documents per statement made each statement 2 to 4 times slower (4.4 to 11 ms). At 5,000 a second, the receiver first fell more than 2 seconds behind and then caught up. At 10,000 a second, the writer wrote only about 8,500 a second, the receiver fell about 10 seconds behind, and it took 4.4 to 5.4 s after the writer finished until the receiver held every document.
- At every rate, the receiver received every document, and no document became visible in a different order from the order written (up to 100,000 documents; see [Changes written in separate statements arrived in the order written](subscriptions-and-replication.md#changes-written-in-separate-statements-arrived-in-the-order-written)).
- One statement is one commit, so the documents of one statement appear on the receiver together (see [Large transactions and statements arrived all at once](subscriptions-and-replication.md#large-transactions-and-statements-arrived-all-at-once)).

**Not tested:** the rate of writes issued in parallel with `Promise.all` ([Parallel writes are safe, but parallel read-modify-write loses updates](transaction-behavior.md#parallel-writes-are-safe-but-parallel-read-modify-write-loses-updates) checked only that they do not break anything); the effect of the store size apart from the rate.

**Used in:** [Pattern 2: Append-only event documents](../../best-practices/data-modeling.md#pattern-2-append-only-event-documents).

## Queries and Indexes

### Long ID lists are faster with USE IDS LIST than with WHERE _id IN

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; the lists of 100,000 and 500,000 IDs one run each |
| Setup | A collection of 20,000 documents, counted with `SELECT COUNT(*)` and each form of ID filter. For writes, `UPDATE`, `EVICT`, and `DELETE` with 10,000 IDs. For subscriptions, a second device received 10,000 of the 20,000 documents |

Time for `COUNT(*)` (nearly the same on both releases; no value was recorded for `USE IDS LIST` with 500,000 IDs):

| IDs in the list | `WHERE _id IN :ids` | `USE IDS LIST :ids` | `WHERE _id NOT IN :ids` |
|---|---|---|---|
| 1,000 | 12 to 13 ms | 3 to 4 ms | 175 to 189 ms |
| 10,000 | 686 to 725 ms | 17 to 21 ms | 1.28 to 1.37 s |
| 30,000 | 4.0 to 4.2 s | 37 to 46 ms | 4.0 to 4.2 s |
| 100,000 (one run) | 13.5 to 13.8 s | 78 to 85 ms | 13.7 to 13.9 s |
| 500,000 (one run) | 66 to 67 s | — | 67 to 69 s |

- In `EXPLAIN`, `IN :ids` is an `idScan` (a lookup by ID) followed by a `filter` that checks `_id IN [...]` again. Each document found is probably checked against the whole list again, which is why a longer list is slower. `USE IDS LIST` has no `filter`.
- Writes behaved the same (one run, 10,000 IDs, 20,000 documents). `UPDATE`, `EVICT`, and `DELETE` with `WHERE _id IN :ids` took 693 to 732 ms on 5.2.0, and with `USE IDS LIST :ids` 20 to 65 ms. On 5.1.0, `UPDATE` with `USE IDS LIST` worked (69 ms), but `EVICT` and `DELETE` removed nothing, as listed in [Known Issues in SDK 5.1.0](../upgrading.md#known-issues-in-sdk-510); 5.2.0 fixed this.
- A subscription by an ID list also makes the initial sync slower (5.1.0 and 5.2.0, two runs each). A subscription with `WHERE _id IN :ids` and 10,000 IDs took 3.32 to 3.38 s, and one with `WHERE grp = 'a'`, which selects the same documents, took 0.85 to 0.86 s (with 3,000 IDs: 1.2 s; with 1,000 IDs: 0.64 s and 0.38 s). After the initial sync, an update of one document arrived in about 31 ms with either subscription. For the initial sync, subscribing by a field that identifies the device or the store is therefore faster than subscribing by a list of document IDs.
- `USE IDS :ids` with an array treats the whole array as one ID. With a small array, it silently returns 0 documents; above 256 bytes, it fails with `SerializedFormOverLimit { limit: 256, ... }`.

**Used in:** [USE IDS](../../best-practices/dql.md#use-ids), [DELETE and Tombstones](../../best-practices/deletion-and-storage.md#delete-and-tombstones).

### A full COUNT(*) is fast, and indexes made selective queries several times faster

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, five runs each |
| Setup | One device without sync, 20,000 documents. Counts and filtered queries with and without an index on `(status, createdAt)` |

| Query | 5.2.0 | 5.1.0 |
|---|---|---|
| `COUNT(*)` of the whole collection | 1.7 to 1.8 ms | 1.7 to 1.8 ms |
| `SELECT _id` of every document | 54 to 59 ms | 63 to 66 ms |
| `COUNT(*)` with `status = 'paid'`, no index | 20 to 21 ms | 28 ms |
| The same, with an index on `(status, createdAt)` | 6.2 to 6.4 ms | 5.9 to 6.0 ms |
| A condition that matches 1% of the documents, no index | 19 to 20 ms | 26 to 29 ms |
| The same, with an index | 2.5 to 2.7 ms | 2.7 ms |
| `ORDER BY createdAt DESC LIMIT 50`, no index | 19 to 21 ms | 26 to 27 ms |
| The same, with an index | 7.1 to 7.2 ms | 6.3 to 6.4 ms |

- A full-collection `COUNT(*)` is cheap, as expected from a count scan that does not read documents: 1.7 to 1.8 ms against 54 to 66 ms for reading every `_id`. The index did not change it.
- The index made the filtered queries 2.7 to 10.8 times faster: the count with `status = 'paid'` 3.2 to 4.8 times, the condition that matches 1% 7.3 to 10.8 times, and `ORDER BY ... LIMIT 50` 2.7 to 4.3 times.

**Used in:** [Counting documents](../../best-practices/indexing-and-performance.md#counting-documents), [Index Usage Rules](../../best-practices/indexing-and-performance.md#index-usage-rules).

### Eleven conditions of the Index Usage Rules table produced the plans it lists

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each |
| Setup | One device without sync, 50,000 documents. `COUNT(*)` with each of 11 conditions of the table in [Index Usage Rules](../../best-practices/indexing-and-performance.md#index-usage-rules); `EXPLAIN` for the plan, and the median time on 5.2.0 |

The 11 conditions produced the plans that the table lists, on both releases. Among them:

| Condition | Plan | Time |
|---|---|---|
| `status = 'open'` (5,000 matches) | Index scan | 6 ms |
| `status IN ['open', 'paid']` | Index scan | 11 ms |
| The same condition written with `OR` | Index scan | 13 ms |
| `OR` of two fields | Union scan | 13 ms |
| `AND` of two fields | Intersect scan | 5 ms |
| `LIKE 'name-001%'`, and a range | Index scan over a range | 1.5 ms |
| `LIKE '%001%'`, and `lower(status) = 'open'` | Collection scan | 43 to 45 ms (5.1.0: 62 to 64 ms) |
| `status != 'open'` (45,000 matches) | Index scan | 41 ms |

- When a condition matches most documents, an index scan is no faster than a collection scan: `status != 'open'` took 41 ms through the index.

**Not tested:** the other conditions of the table, such as `IS MISSING`, `array_contains`, and composite indexes.

**Used in:** [Index Usage Rules](../../best-practices/indexing-and-performance.md#index-usage-rules).

### A query answered from the index alone took about two thirds of the time

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, four runs each (one earlier run with a separate script and three with the same setup); each time of the three later runs is the median of five queries |
| Setup | One device without sync, 50,000 documents of about 1 KB, 5,000 of them matching `status = 'open'`, and an index on `status`. Three projections of the same query |

| Projection | 5.2.0 | 5.1.0 |
|---|---|---|
| `SELECT _id, status` (`EXPLAIN`: `covering: true`, no fetch) | 15.8 to 16.6 ms | 15.5 to 16.6 ms |
| `SELECT _id, status, total` (one field outside the index) | 22.9 to 25.1 ms | 23 to 24 ms |
| `SELECT *` | 23.4 to 25 ms | 23.5 to 26 ms |

- The query answered from the index took about two thirds of the time of the others in every run.
- Once documents had to be fetched, projecting fewer fields hardly changed the time: of the two benefits of a narrow projection, the one that counts is skipping the fetch.
- On 5.2.0, the `indexScan` of `SELECT *` was also marked `covering: true` and was followed by a `fetch`; on 5.1.0, it had no `covering` mark. `SELECT _id, status, total` had none on either release. Whether a query is answered from the index alone shows in the missing `fetch` step.

**Used in:** [Covering scans](../../best-practices/indexing-and-performance.md#covering-scans).

### On SDK 5.1.0 and 5.2.0, an observer of 5,000 documents was called about 5 to 6 times later than one of 50

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, five runs each, and 5.0.3, four runs |
| Setup | One device without sync, 5,000 documents. Two observers: one of all documents, and one of `WHERE customerId = :c ORDER BY createdAt DESC LIMIT 50`. We measured the time from writing one document until each callback; each time is the median of the seven callbacks in a run |

| Observer | 5.2.0 | 5.1.0 | 5.0.3 |
|---|---|---|---|
| All 5,000 documents | 31 to 43 ms | 33 to 47 ms | 39 to 69 ms |
| 50 documents | 5.0 to 6.7 ms | 5.8 to 8.0 ms | 46 to 50 ms |

- In each run on 5.2.0, the larger observer was called 6.1 to 6.5 times later, and on 5.1.0 4.7 to 6.3 times later. On 5.0.3, the two observers were called at about the same time (0.8 to 1.5 times).

**Used in:** [Query Scope and Execution](../../best-practices/indexing-and-performance.md#query-scope-and-execution).

### Evicting in chunks costs little more than one statement

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, seven runs each |
| Setup | One device without sync, 10,000 documents to evict: with one `EVICT` statement, and in chunks of 1,000 |

- One statement took 29 to 30 ms (5.1.0: 36 ms).
- In chunks of 1,000, it took 11 statements, the longest 5.3 to 5.5 ms (5.1.0: 5.8 to 6.9 ms), 47 to 50 ms in total (5.1.0: 54 to 61 ms).
- The local cost is small either way; chunks keep each statement short.

**Used in:** [Batching evictions](../../best-practices/deletion-and-storage.md#batching-evictions).

### Opening Ditto took the same time with 1,000 and 200,000 documents

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each, with three opens of each store |
| Setup | Stores of 1,000 and of 200,000 documents of about 0.5 KB each, each opened and closed three times; then the first and the second query after opening |

- `Ditto.open()` took 11 to 15 ms and `close()` 25 to 32 ms, with 1,000 and with 200,000 documents: they hardly depend on the number of documents.
- The first query after opening was as fast as the second: a `COUNT(*) ... WHERE` without an index on 200,000 documents took 184 to 193 ms on 5.2.0 and 261 to 265 ms on 5.1.0.

**Used in:** none yet.

### On SDK 5.1.0 and 5.2.0, an index on a field with two values made a query slower than no index

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; each time is the median of five queries. How the time varied with one plan (12 queries): one run on 5.2.0 |
| Setup | 100,000 documents. `store` has 20 values, and `status` has 2 (two thirds of the documents are `'open'`). `WHERE store = 's1' AND status = 'open'` matches 3,300 documents. The query ran with different sets of indexes |

| Indexes | Time |
|---|---|
| None (the query reads every document) | 5.2.0: 90 to 91 ms; 5.1.0: 126 to 128 ms; 5.0.3: 232 ms |
| `status` only | 5.2.0: 140 to 143 ms; 5.1.0: 159 to 162 ms; 5.0.3: 231 to 237 ms |
| `store` only | 21 to 27 ms |
| `store` and `status`, as two separate indexes | 55 to 62 ms |
| Composite `(store, status)` (SDK 5.1+) | 17 to 18 ms |

- An index on `status` alone made the query slower than no index on 5.1.0 and 5.2.0 (1.3 to 1.6 times). The planner still used it (`indexScan` in `EXPLAIN` on 5.1 and later). On 5.0.3, the time was about the same as without an index.
- With separate indexes on `store` and `status`, the planner combined them (`intersectScan`), which was slower than the index on `store` alone.
- The composite index `(store, status)` was the fastest. With a condition that matches nothing (`total = 999` added), it took 6 ms, against 74 to 112 ms without an index on 5.1 and later.
- With `LIMIT 50`, the query took 2 to 4 ms even without an index: it reads from the start and stops after 50 documents. With the combined plan (with indexes on `store`, `status`, and `total`), the median was 6 to 7 ms, but individual queries with the same plan varied from 2 to 69 ms.
- `Ditto.open()` took 10 to 21 ms for an empty store and for 100,000 documents (about 70 MB): it does not depend on the size of the store. Without indexes, the first query after opening was as fast as the second (1 to 4 ms).

**Used in:** [Index Usage Rules](../../best-practices/indexing-and-performance.md#index-usage-rules), [Where indexes live](../../best-practices/indexing-and-performance.md#where-indexes-live).

### Constant query strings were not faster

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, five runs each, and 5.0.3, four runs; each time is the median of three repetitions within a run |
| Setup | 1,000 `SELECT ... WHERE _id = ...` queries, once with a constant string and a parameter, and once with a new string for each value, with the value written into it |

| Release | Constant string with a parameter | New string for each value |
|---|---|---|
| 5.2.0 | 1,592 to 1,710 ms | 1,657 to 1,696 ms |
| 5.1.0 | 1,677 to 1,710 ms | 1,498 to 1,701 ms |
| 5.0.3 | 6,528 to 6,562 ms | 6,503 to 6,551 ms |

- The constant string was not faster. In each run, the two times differed by at most 12%, in either direction; the constant string was the faster one in 2 of the 14 runs, both on 5.2.0.

**Not tested:** whether and when Ditto caches prepared statements.

**Used in:** [Query Scope and Execution](../../best-practices/indexing-and-performance.md#query-scope-and-execution).

## Memory Held by Query Results and Observers

### Large query results keep process memory after they are released

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each |
| Setup | 20,000 documents of about 1 KB. The test held 10 results of `SELECT *` (200,000 rows in total), then read every `item.value`, then dropped the results. At each point, it ran garbage collection and then measured the process's resident memory (RSS) and the JavaScript heap |
| Documentation | The 5.2.0 release notes say that query results stay compact until they are read |

RSS as the increase from the start; the JavaScript heap started at 7 MB. In MB:

| Point | RSS, 5.2.0 | RSS, 5.1.0 | JavaScript heap (both releases) |
|---|---|---|---|
| Holding the results | +441 to 515 | +634 to 635 | About 100 |
| After reading every value | +743 to 784 | +1,150 to 1,190 | About 325 to 334 |
| After dropping the results and garbage collection | +745 to 784 | +1,184 to 1,187 | About 91 to 101 |

- 5.2.0 used about 20 to 30% less memory than 5.1.0 while holding the results, and about 35% less after the values were read, in line with the release notes.
- After the results were dropped and garbage-collected, the process's RSS did not shrink. The JavaScript heap shrank, but not to its first 7 MB: 91 to 101 MB remained. Once a process has built a large result, expect its memory not to come back.
- Reading the values added about 1.1 KB per row to the JavaScript heap, about the size of a document.

**Not tested:** what remains in the JavaScript heap after the results are dropped.

**Used in:** [Large results](../../best-practices/dql.md#large-results).

### An observer of 200 documents grows memory on every callback

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each, with the three releases running at the same time; all nine runs showed the same trend. A second setup, below, three runs each |
| Setup | Nine devices in separate processes, connected through a TCP hub. Two devices without observers kept updating their own 100 documents (each with a 200-byte string), one document every 40 ms each (together about 42 to 46 updates a second). Every device except the hub subscribed to the whole collection and had one of the following: no observer; an observer of all 200 documents (`SELECT * FROM soak`); the same observer with garbage collection forced every 30 seconds; an observer of one row that changes on every write (`SELECT _id, round FROM soak ORDER BY round DESC LIMIT 1`); an observer of 200 documents cancelled after 4 minutes and followed at once by a forced garbage collection; an observer registered with `registerObserverWithSignalNext` that never called `signalNext()`. No callback read its result; each only counted its calls. The RSS and JavaScript heap of each process were measured every 30 seconds, and the growth rates leave out the first 2 minutes. The increase per call is the least-squares slope of RSS against the number of calls. The second setup: every device had an observer of 200 documents, two devices updated every 20 ms, one device registered its subscription again every 5 seconds, and one device lost its connection for 2 seconds every 15 seconds |

After 10 minutes (5.2.0; 5.1.0 / 5.0.3 in parentheses; RSS in MiB):

| Device | Calls per second | Increase per call | RSS at 10 minutes | Growth after the first 2 minutes (MiB per minute) |
|---|---|---|---|---|
| No observer | — | — | 142 to 147 (107 / 99 to 100) | 0.8 to 1.0 (0.1 to 0.2 / 0.1 to 0.2) |
| Observer of all 200 documents | 28 (25 to 26 / 32 to 33) | 13.4 to 13.8 KiB (16.3 to 24.4 / 13.3 to 18.1) | 522 to 558 (594 to 715 / 698 to 743) | 21.8 to 22.9 (25.8 to 36.7 / 24.5 to 35.4) |
| The same observer, garbage collection forced every 30 seconds | 28 (25 to 26 / 32 to 33) | 15.1 to 19.7 KiB (15.1 to 16.3 / 13.1 to 14.9) | 523 to 594 (523 to 595 / 647 to 669) | 25.1 to 32.9 (23.1 to 26.0 / 24.8 to 29.0) |
| Observer of one row that changes on every write | 22 to 24 (20 to 22 / 21 to 22) | 0.9 to 1.6 KiB (1.2 to 1.5 / 1.2 to 1.4) | 172 to 177 (140 to 143 / 141 to 144) | 1.2 to 2.2; in the last 5 minutes −0.2 to 0.3 (−1.2 to −0.3 / 0.9 to 1.4) |
| Observer that never calls `signalNext()` | Once in 10 minutes | — | 149 to 153 (108 to 109 / 100 to 101) | 1.1 to 1.8 (0 to 0.2 / 0 to 0.1) |

- **The number of rows in the result matters**: the observer of one row was called about 80% as often as the observer of 200 documents, but grew about 10 to 20 times less per call, and on 5.1.0 and 5.2.0 it stopped growing after about 5 minutes (on 5.0.3, it still grew 0.9 to 1.4 MiB per minute in the last 5 minutes). The observer of 200 documents grew by about 13 to 24 KiB per call (about 70 to 120 bytes per row), almost linearly for the 10 minutes. The callbacks did not read the result, so the growth does not come from values extracted in JavaScript. The JavaScript heap only moved up and down between 10 and 140 MiB; the growth is probably native memory.
- **Forcing garbage collection does not change it**: the device that forced garbage collection every 30 seconds grew in the same way.
- **The difference between releases is mainly the number of calls**: the increase per call was about the same on the three releases (5.2.0 varied less). 5.0.3 calls an observer more often for the same writes. In the second setup, with twice as many writes, an observer was called about 66 times a second on 5.0.3 and about 29 times on 5.1 and later (a separate run, once per release), and 5.0.3 grew about twice as fast: 43 to 62 MiB per minute against 19 to 30 MiB, and 870 to 1,109 MiB against 510 to 631 MiB at 10 minutes.
- **Registering a subscription again and reconnecting do not change the growth**: in the second setup, the device that registered its subscription again every 5 seconds and the device that lost its connection every 15 seconds grew about as much as the devices that kept updating, or slightly less. A hub without an observer hardly grew in the first setup, so the hub's growth in the second setup (22 to 25 MiB per minute on 5.1 and later, 55 to 59 MiB on 5.0.3) probably comes from its observer as well.
- **Cancelling stops the growth, and part of the memory returns 1.5 to 2 minutes later**: after the observer was cancelled at 4 minutes, the RSS stopped growing from the next measurement on. The forced garbage collection right after the cancellation shrank the JavaScript heap (5.2.0: from 50 to 56 MiB to 19 to 24 MiB) but the RSS by only 1 to 12 MiB. 90 to 120 seconds after the cancellation (between the same two measurements in all nine runs), the RSS dropped by 95 to 220 MiB at once and then stayed level. At 10 minutes, it was 271 to 276 MiB on 5.2.0, 276 to 300 MiB on 5.1.0, and 334 to 383 MiB on 5.0.3, still 125 to 285 MiB more than on the device without an observer. In a first version of the test without the forced garbage collection (one run per release), the RSS also dropped about 1.5 to 2 minutes after the cancellation. Registering the observer again started the growth again.
- **An observer that is not called does not grow**: the observer that never called `signalNext()` was called only once and stayed close to the device without an observer (5.2.0: 1 to 2 MiB per minute, against 0.8 to 1.0 MiB without an observer).
- **Writers without observers also grow slowly**: the two devices that kept updating their documents grew about 2.4 to 3.9 MiB per minute without any observer (5.2.0: 3.1 to 3.9; 5.1.0: 2.8 to 3.1; 5.0.3: 2.4 to 2.6), and the growth did not slow down in the second half: about 2 to 3 KiB per write. We did not look for the cause. The hub, which had no observer, grew 1.4 to 1.7 MiB per minute after the first 2 minutes on 5.2.0 and 0.2 to 0.3 MiB on 5.1.0 and 5.0.3.
- **5.2.0 grows more in the first 2 minutes**: even without an observer, a device on 5.2.0 grew about 35 to 40 MiB in the first 2 minutes (5.1.0: about 5 MiB; 5.0.3: about 3 MiB). The hub did the same (at 10 minutes, 182 to 189 MiB on 5.2.0 and 126 to 127 MiB on 5.1.0). After that, it hardly grew.
- This growth is a different mechanism from the results that queue up in a Flutter observer's unconsumed `changes` stream on SDK 5.1.0 (see [Store Observers in Flutter](../../best-practices/observers.md#store-observers-in-flutter)).

**Not tested:** lower write rates, closer to those of real apps (here, about 45 writes a second); whether an observer called less often, such as once a second, grows by the same amount per call (if it does, an observer of 200 documents called once a second grows by about 45 to 85 MiB an hour); callbacks that read the values; the relation to the size of the result in bytes rather than rows; Flutter observers (`onChange`, `changes`); mobile devices; CPU use (the three releases ran at the same time, so this test says little about CPU); runs longer than 10 minutes, and whether the growth levels off. Whether this is a leak cannot be said from a 10-minute observation, and what the retained memory holds was not examined.

**Used in:** [Query Scope and Execution](../../best-practices/indexing-and-performance.md#query-scope-and-execution).

## Load on a Hub

### Hub CPU per change grows with the number of connected devices

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each, on a 14-core Mac, with the other timing measurements stopped while this one ran |
| Setup | The hub and one watching device ran in separate processes; the writers were peers in the process that ran the test. Each writer subscribed only to its own document and wrote `UPDATE ... SET seq, at` at a fixed rate. The hub's TCP connection limit was 40. Each case was measured for 15 seconds. The hub's CPU is that of the hub process only, where 100% is one core. The watching device had an observer and also queried every 10 ms; the delay is the time until its observer saw a change |

5.2.0; 5.1.0 / 5.0.3 in parentheses:

| Connected writers | Writing devices × writes per second | Hub CPU | Delay, median / maximum |
|---|---|---|---|
| 1 | 1 × 5 | 3% (2 / 3) | 6 ms / 6 ms (5 to 6 / 15) |
| 5 | 5 × 5 | 13 to 14% (12 to 13 / 14) | 43 ms / 45 to 47 ms |
| 10 | 10 × 5 | 35% (33 / 38 to 39) | 47 ms / 49 to 94 ms |
| 20 | 20 × 5 | 113 to 117% (111 to 116 / 124 to 128) | 57 ms / 94 to 110 ms |
| 30 | 30 × 5 | 261 to 268% (269 to 271 / 260 to 262) | 112 ms / 290 to 321 ms (114 to 115 / 158 to 160) |
| 30 | 30 × 20 (the Mac's CPU almost fully used) | 421 to 442% (441 to 460 / 241 to 250) | 177 to 193 ms / 445 to 482 ms |
| 30 | 0 (connected only) | 17 to 20% (19 / 20) | — |
| 30 | 1 × 5 | 38 to 39% (37 to 38 / 39 to 40) | 12 ms / 56 to 65 ms |
| 30 | 5 × 5 | 89 to 91% (90 to 92 / 92 to 93) | 55 ms / 114 to 138 ms |

- When one device wrote 5 times a second, the hub's CPU was 3% with that device as its only client and 38 to 39% with 30 devices connected (about 20% after subtracting the 17 to 20% that the 30 connections used alone). The hub's CPU per change grew from about 6 ms with one device (an upper bound, because the idle CPU was not subtracted) to about 40 ms with 30 devices (after subtracting). With 30 devices connected, a change cost about 29 ms when 5 of them wrote and about 16 ms when all 30 wrote; probably the hub can handle more changes together. The other writers did not subscribe to the changed document.
- When every connected device wrote, the hub's CPU grew faster than the number of devices: about 14% with 5, 35% with 10, about 115% with 20, and about 265% with 30. From 5 to 30 devices, the number of devices grew 6 times and the CPU about 20 times, roughly the number of devices to the power of 1.7.
- The hub's memory (RSS) grew by about 4.5 MiB per connected device on 5.2.0 (from 105 MiB to 238 to 252 MiB), about 3 MiB on 5.1.0, and about 2 MiB on 5.0.3.
- On 5.1 and later, with 5 to 10 writers, the watching device's observer saw a change about 20 to 25 ms later than its queries every 10 ms did. This is probably the observer's batching (see [A device receives nearly every value of a fast-changing field](observer-behavior.md#a-device-receives-nearly-every-value-of-a-fast-changing-field)); the callbacks were not counted. With 20 to 30 writers, the difference shrank to 3 to 7 ms, while the time at which the queries saw the change also grew. On 5.0.3, the difference between the observer and the queries was small.
- When 30 devices wrote 20 times a second each (600 writes a second), the Mac's CPU was almost fully used (the hub 4.4 cores, the writers' process 5.6 cores). The watching device skipped intermediate values: of 9,000 changes, it saw 4,551 to 5,437 on 5.1 and later and 2,498 to 2,568 on 5.0.3. The final value of every writer reached the hub, and no writer's `seq` arrived out of order (see [Changes written in separate statements arrived in the order written](subscriptions-and-replication.md#changes-written-in-separate-statements-arrived-in-the-order-written)).
- The 30 writers ran in one process on the same Mac and used 55 to 68% CPU while only connected, and about 290% when 30 wrote 5 times a second. The delays may include the competition for CPU. The hub's CPU was measured for the hub process only.

**Not tested:** the number of observer callbacks on the watching device; delays without the writers competing with the hub for the same CPU.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).
