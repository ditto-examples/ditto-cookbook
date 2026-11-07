# Transaction Behavior

How transactions behave on one device: what other reads, writes, and incoming changes do while a read-write transaction or a large statement runs, which parallel read-then-write sequences lose updates, how long transactions are logged, and what a deadlocked transaction does. How each SDK's transaction API fails, and what its shutdown waits for, is on the page of that SDK: [Flutter](flutter-sdk.md), [JavaScript](javascript-sdk.md), [Kotlin](kotlin-sdk.md), or [Swift](swift-sdk.md). How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Transactions](../../best-practices/transactions.md), [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), and [Platform Differences](../platform-differences.md).

**In brief**

- While a read-write transaction is open, other reads see only committed data, other writes wait, and changes from other devices reach neither the store nor observers until it ends, also when it only reads. A large statement holds them up in the same way, on the writing and on the receiving device ([Reads outside a read-write transaction see only committed data](#reads-outside-a-read-write-transaction-see-only-committed-data), [Incoming changes wait while a read-write transaction is open](#incoming-changes-wait-while-a-read-write-transaction-is-open), [Large statements delay incoming changes and local writes](#large-statements-delay-incoming-changes-and-local-writes)).
- On one device, read-then-write sequences that run in parallel lose updates without an error, while the same sequences in transactions, or `UPDATE ... SET n = n + 1` statements, do not ([Parallel writes are safe, but parallel read-modify-write loses updates](#parallel-writes-are-safe-but-parallel-read-modify-write-loses-updates)).
- A long transaction is logged at rising levels: with the log level at Info, the first line appears after 20 seconds ([Long transactions are logged at rising levels](#long-transactions-are-logged-at-rising-levels)).
- A deadlocked transaction blocks the store but does not end the process ([A deadlocked transaction does not end the process](#a-deadlocked-transaction-does-not-end-the-process)).
- What each SDK does with `store.execute` inside a transaction, nested transactions, statements that are not awaited, and `close()` during a transaction is on the SDK pages: [Flutter SDK Behavior](flutter-sdk.md), [JavaScript SDK Behavior](javascript-sdk.md), [Kotlin SDK Behavior](kotlin-sdk.md), and [Swift SDK Behavior](swift-sdk.md).

## Concurrency, Waiting, and Long Transactions

### Reads outside a read-write transaction see only committed data

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; the results were the same on all three releases |
| Setup | One device. While a read-write transaction that had inserted a document was open, we started a read-only transaction, a `SELECT` and an `INSERT` through `store.execute`, a second read-write transaction, and, inside the open transaction, a nested read-only transaction. We also read `commitID` inside and after a transaction, ended transactions by returning `'rollback'` and by throwing, wrote in a read-only transaction, and used a stored `Transaction` after its callback had returned |

- While a read-write transaction is open, a read-only transaction and a `SELECT` through `store.execute` complete at once and return the state before the commit, without the document that the open transaction inserted. A read-only transaction nested inside the read-write transaction does not see the outer transaction's writes either.
- A second read-write transaction and an `INSERT` through `store.execute` wait until the first transaction has ended, and then succeed.
- The `commitID` of a `tx.execute` result is `null` inside the transaction. The same `QueryResult`, returned from the callback, has a `commitID` (for example, 5) after `transaction()` has completed.
- Returning `'rollback'` discards the writes, and `transaction()` returns `'rollback'`. A callback that throws also rolls back, and the exception reaches the caller unchanged.
- A write in a read-only transaction fails with `A mutating DQL query was attempted using a read-only transaction.`
- A `Transaction` object that is kept and used after its callback has finished fails with `No active write transaction found with id <uuid>. Active write transaction id: None`.

**Used in:** [Concurrency and Duration](../../best-practices/transactions.md#concurrency-and-duration), [Transaction Rules](../../best-practices/transactions.md#transaction-rules).

### Incoming changes wait while a read-write transaction is open

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0: four runs each with both peers in one process (in one of them, we also timed the sender's write; on 5.0.3, without the large `UPDATE`), and three runs each with each peer in its own process; the results were the same on all three releases. The local cases at the end: one run each on 5.1.0 and 5.2.0 |
| Setup | Two peers. While the receiving device held a read-write transaction open for 3 seconds (in another case, 15 seconds), the other peer updated a document, and we timed when the update appeared in the receiver's store and in its observer. Variants: a transaction that only ran `SELECT`, with and without `isReadOnly: true`, and one `UPDATE` statement on the receiver that rewrote 50,000 documents. Meanwhile, we also read the receiver's store. On one device, we also ran small writes and reads during a 50,000-document `UPDATE`, during a transaction, and during a `SELECT` that read 50,000 documents |

- An update written while the receiver held a read-write transaction open for 3 seconds appeared neither in its store nor in its observer until right after the transaction ended, about 2.8 seconds after it was sent. The sender's write had completed in 4 to 9 ms, so what waited was applying the change on the receiver. With each peer in its own process, the result was the same, so it is not a consequence of running both peers in one process.
- A transaction that ran only `SELECT` held the update back in the same way unless it was marked read-only. During an `isReadOnly: true` transaction, the update arrived in about 20 ms, as it does otherwise.
- A transaction held open for 15 seconds delayed the update to about 14.8 seconds, right after it ended. 14 seconds after the transaction began, each peer's presence still showed the other.
- While one `UPDATE` statement rewrote 50,000 documents on the receiver (about 0.3 seconds), the update waited as well and arrived right after the statement ended (5.1.0 and 5.2.0).
- In every case, reads of the receiver's store did not wait (2 to 7 ms each).
- On one device, the pattern was the same: during a 50,000-document `UPDATE` or a transaction, other small writes waited until it ended (186 to 352 ms), while reads returned in 1 to 2 ms. A heavy `SELECT` that read 50,000 documents (100 to 190 ms) did not make other reads or writes wait. In every case, the JavaScript event loop kept running (the largest delay was 6 to 7 ms).
- A bulk rewrite split into statements of 1,000 documents with an indexed condition delayed incoming changes by at most about 60 ms (see [Large statements delay incoming changes and local writes](#large-statements-delay-incoming-changes-and-local-writes)).

**Not tested:** whether the connection dropped and reconnected while the transaction was held open for 15 seconds.

**Used in:** [Concurrency and Duration](../../best-practices/transactions.md#concurrency-and-duration), [Transaction Rules](../../best-practices/transactions.md#transaction-rules).

### Large statements delay incoming changes and local writes

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each |
| Setup | Writing device (both peers in one process): one device rewrote 50,000 documents, either with one `UPDATE` or in 50 statements of 1,000 documents selected by an indexed condition, while the other peer sent an update every 50 ms, and we measured how late each update appeared on the writing device. Receiving device (both peers in one process, and again with each peer in its own process): the other peer inserted 30,000 documents in one transaction, or 1,000 at a time in 30 statements, with and without 50 ms between the statements, while the receiving device timed its own small writes. The delay on the writing device was measured only with both peers in one process; in the tests of [Incoming changes wait while a read-write transaction is open](#incoming-changes-wait-while-a-read-write-transaction-is-open), we confirmed that a device waiting for its turn to write does not make the writes of another device in the same process wait |

| Case | 5.1.0 and 5.2.0 | 5.0.3 |
|---|---|---|
| Writing device: one `UPDATE` of 50,000 documents | Took 0.54 to 0.65 s. The updates from the other peer were not applied meanwhile and were delayed by up to 0.51 to 0.60 s | Took about 1.7 s, and the updates were delayed by as much |
| Writing device: 50 statements of 1,000 documents with an indexed condition | 0.74 to 0.95 s in total, a little longer. The updates were delayed by at most 52 to 60 ms (median 9 to 12 ms) | About 7.6 s in total (about 150 ms per statement, even with the index). The updates were delayed by at most about 210 ms |
| Receiving device: the other peer inserts 30,000 documents in one transaction | The receiver's own small writes (normally 1.7 to 1.8 ms) waited up to 1.29 to 1.35 s while the documents were applied (about 2 s until all 30,000 were present). With each peer in its own process: up to 1.25 to 1.29 s | Up to about 0.66 s |
| Receiving device: 30 statements of 1,000 documents | Up to 0.64 to 0.70 s. With each peer in its own process: 0.62 to 0.66 s | Up to 0.24 s |
| Receiving device: 30 statements of 1,000 documents, 50 ms apart | Up to 0.23 to 0.31 s | Up to 0.04 s |

- On the writing device, the updates waited as in [Incoming changes wait while a read-write transaction is open](#incoming-changes-wait-while-a-read-write-transaction-is-open). The maximum of 52 to 60 ms with split statements includes the observer's coalescing of about 34 ms (see [A device receives nearly every value of a fast-changing field](observer-behavior.md#a-device-receives-nearly-every-value-of-a-fast-changing-field)).
- On the receiving device, the waits were the same with each peer in its own process, so they are not a consequence of running both peers in one process. Applying received changes probably takes its turn to write, like a local write.
- A change split into several statements no longer appears at once on receiving devices (see [Large transactions and statements arrived all at once](subscriptions-and-replication.md#large-transactions-and-statements-arrived-all-at-once)).
- A screen that awaits a write, for example to respond to a button, can therefore appear frozen while the device takes in a large sync.

**Not tested:** the delay on the writing device with each peer in its own process.

**Used in:** [Concurrency and Duration](../../best-practices/transactions.md#concurrency-and-duration).

### Parallel writes are safe, but parallel read-modify-write loses updates

| | |
|---|---|
| Observed on | JavaScript: SDK 5.0.3, 5.1.0, and 5.2.0, three runs each. Flutter on macOS, Kotlin on the Android 16 emulator, and Swift on macOS: SDK 5.1.0 and 5.2.0, three runs each (2026-11-07). The same pattern on every release and SDK |
| Setup | One device, in JavaScript. We started 500 operations at once with `Promise.all`, and compared them with awaiting one at a time: `INSERT` statements; `UPDATE c SET n = n + 1`; and a read-then-write sequence in the app (`SELECT`, add 1 to the value read, `UPDATE`). We also started the same sequence 100 times at once, each in its own `ditto.store.transaction`. In the other SDKs, the `UPDATE`, the read-then-write sequence, and the transactions were started at once in the same numbers: with `Future.wait` in Flutter, as coroutines on `Dispatchers.IO` in Kotlin (the transactions also on a dispatcher of 4 threads), and as tasks of a task group in Swift |

| Case | Result |
|---|---|
| 500 `INSERT` statements started at once with `Promise.all` | All succeeded, faster than awaiting one at a time: about 134 ms against about 900 ms on 5.1.0 and 5.2.0, and 308 to 583 ms against about 1,060 ms on 5.0.3 |
| 500 `UPDATE c SET n = n + 1` started at once (5.1.0 and 5.2.0) | `n` was exactly 500: each statement reads and writes as one unit |
| 500 read-then-write sequences started at once | `n` ended at 2 to 3: 497 to 498 updates were lost, and none of them raised an error |
| 100 read-then-write sequences started at once, each in a transaction | The transactions ran one after another, and `n` was exactly 100 (about 43 to 55 ms). Transactions that had to wait did not fail |

- **The other SDKs showed the same pattern**:

  | SDK | 500 `UPDATE c SET n = n + 1` | 500 read-then-write sequences | 100 sequences, each in a transaction |
  |---|---|---|---|
  | Flutter | `n` = 500 | `n` = 1 | `n` = 100, in 91 to 152 ms |
  | Kotlin | `n` = 500 | `n` = 8 to 9 | `n` = 100, in 613 to 779 ms on `Dispatchers.IO` and 308 to 399 ms on 4 threads |
  | Swift | `n` = 500 | `n` = 36 to 37 | `n` = 100, in 46 to 87 ms |

- In Kotlin and Swift, transactions that waited for each other did not stop the process, unlike `store.execute` writes that wait behind an open transaction ([In Kotlin, writes that wait behind a transaction each hold a thread](kotlin-sdk.md#in-kotlin-writes-that-wait-behind-a-transaction-each-hold-a-thread), [In Swift, 14 concurrent writes during an open transaction stop the process](swift-sdk.md#in-swift-14-concurrent-writes-during-an-open-transaction-stop-the-process)).
- Running statements in parallel is not an error.
- This applies within one device. When other devices write at the same time, both `n = n + 1` and a transaction are resolved by last-writer-wins (see [Conditional updates on two offline devices both succeed](merge-behavior.md#conditional-updates-on-two-offline-devices-both-succeed)). To add up numbers across devices, use a `COUNTER`.

**Not tested:** `n = n + 1` on 5.0.3, which does not accept a reference to a field in `SET`.

**Used in:** [Transactions](../../best-practices/transactions.md#transactions).

### Long transactions are logged at rising levels

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | A transaction with a `hint` was held open for 65 seconds, and a custom log callback (`Logger.setCustomLogCallback`) collected the lines that contained `has been running for` |

The callback received 11 lines, one every 5 seconds from 10.2 seconds:

| Time the transaction had run | Level |
|---|---|
| 10 and 15 s | Debug |
| 20, 25, and 30 s | Info |
| 35 to 55 s | Warning |
| From 60 s | Error |

- Every line contained the transaction's hint.
- With the minimum log level set to Info, the first line therefore appears after 20 seconds; with Warning, after 35 seconds.

**Used in:** [Concurrency and Duration](../../best-practices/transactions.md#concurrency-and-duration).

## Deadlocked Transactions

### A deadlocked transaction does not end the process

| | |
|---|---|
| Observed on | SDK 5.2.0, one run, stopped by hand after 306 seconds |
| Setup | A read-write transaction deadlocked by a write through `store.execute` inside it (as in [In JavaScript, store.execute writes inside a transaction deadlock](javascript-sdk.md#in-javascript-storeexecute-writes-inside-a-transaction-deadlock)), with the minimum log level set to Error |
| Documentation | The JavaScript SDK's type definitions describe a deadlock detection for Node.js only: it ends the process when an asynchronous callback that Ditto called does not finish within a set time |

- `Ditto.hasDeadlockDetection()` returned `true`. Even so, the deadlocked transaction had not ended the process after 306 seconds.
- From 60 seconds on, `ERROR ditto_small_peer_store: Transaction <uuid> (hint: n/a) has been running for 60s)` was logged every 5 seconds. This log line was the only sign of the stuck transaction; a transaction's `hint` appears in it (see [Long transactions are logged at rising levels](#long-transactions-are-logged-at-rising-levels)).

**Not tested:** which callbacks the deadlock detection applies to.

**Used in:** [Transaction Rules](../../best-practices/transactions.md#transaction-rules).
