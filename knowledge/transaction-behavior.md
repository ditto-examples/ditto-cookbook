# Transaction Behavior

How transactions behave on one device: what other reads, writes, and incoming changes do while a read-write transaction or a large statement runs, which parallel read-then-write sequences lose updates, how long transactions are logged, how transactions fail in JavaScript, and what `close()` waits for in JavaScript. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Transactions](../best-practices/transactions.md), [Resource Cleanup and Shutdown](../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), and [Platform Differences](platform-differences.md).

**In brief**

- While a read-write transaction is open, other reads see only committed data, other writes wait, and changes from other devices reach neither the store nor observers until it ends, also when it only reads. A large statement holds them up in the same way, on the writing and on the receiving device ([Reads outside a read-write transaction see only committed data](#reads-outside-a-read-write-transaction-see-only-committed-data), [Incoming changes wait while a read-write transaction is open](#incoming-changes-wait-while-a-read-write-transaction-is-open), [Large statements delay incoming changes and local writes](#large-statements-delay-incoming-changes-and-local-writes)).
- On one device, read-then-write sequences that run in parallel lose updates without an error, while the same sequences in transactions, or `UPDATE ... SET n = n + 1` statements, do not ([Parallel writes are safe, but parallel read-modify-write loses updates](#parallel-writes-are-safe-but-parallel-read-modify-write-loses-updates)).
- A long transaction is logged at rising levels: with the log level at Info, the first line appears after 20 seconds ([Long transactions are logged at rising levels](#long-transactions-are-logged-at-rising-levels)).
- In JavaScript, a write through `store.execute` inside a transaction and a nested read-write transaction deadlock without an error and without ending the process, a `tx.execute` that is not awaited is not applied, and a Node.js script that does not start sync ends with a panic while it awaits a transaction ([In JavaScript, store.execute writes inside a transaction deadlock](#in-javascript-storeexecute-writes-inside-a-transaction-deadlock), [A deadlocked transaction does not end the process](#a-deadlocked-transaction-does-not-end-the-process), [A tx.execute that is not awaited is not applied](#a-txexecute-that-is-not-awaited-is-not-applied), [A Node.js script without sync ends with a panic while awaiting a transaction](#a-nodejs-script-without-sync-ends-with-a-panic-while-awaiting-a-transaction)).
- In JavaScript, `close()` waits for open transactions and pending writes, but not until changes have been sent to other devices ([In JavaScript, close() waits for open transactions](#in-javascript-close-waits-for-open-transactions), [In JavaScript, close() completes pending writes](#in-javascript-close-completes-pending-writes)).

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

**Used in:** [Concurrency and Duration](../best-practices/transactions.md#concurrency-and-duration), [Transaction Rules](../best-practices/transactions.md#transaction-rules).

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

**Used in:** [Concurrency and Duration](../best-practices/transactions.md#concurrency-and-duration), [Transaction Rules](../best-practices/transactions.md#transaction-rules).

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

**Used in:** [Concurrency and Duration](../best-practices/transactions.md#concurrency-and-duration).

### Parallel writes are safe, but parallel read-modify-write loses updates

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; the same pattern on all three releases |
| Setup | One device, in JavaScript. We started 500 operations at once with `Promise.all`, and compared them with awaiting one at a time: `INSERT` statements; `UPDATE c SET n = n + 1`; and a read-then-write sequence in the app (`SELECT`, add 1 to the value read, `UPDATE`). We also started the same sequence 100 times at once, each in its own `ditto.store.transaction` |

| Case | Result |
|---|---|
| 500 `INSERT` statements started at once with `Promise.all` | All succeeded, faster than awaiting one at a time: about 134 ms against about 900 ms on 5.1.0 and 5.2.0, and 308 to 583 ms against about 1,060 ms on 5.0.3 |
| 500 `UPDATE c SET n = n + 1` started at once (5.1.0 and 5.2.0) | `n` was exactly 500: each statement reads and writes as one unit |
| 500 read-then-write sequences started at once | `n` ended at 2 to 3: 497 to 498 updates were lost, and none of them raised an error |
| 100 read-then-write sequences started at once, each in a transaction | The transactions ran one after another, and `n` was exactly 100 (about 43 to 55 ms). Transactions that had to wait did not fail |

- Running statements in parallel is not an error.
- This applies within one device. When other devices write at the same time, both `n = n + 1` and a transaction are resolved by last-writer-wins (see [Conditional updates on two offline devices both succeed](merge-behavior.md#conditional-updates-on-two-offline-devices-both-succeed)). To add up numbers across devices, use a `COUNTER`.

**Not tested:** `n = n + 1` on 5.0.3, which does not accept a reference to a field in `SET`.

**Used in:** [Transactions](../best-practices/transactions.md).

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

**Used in:** [Concurrency and Duration](../best-practices/transactions.md#concurrency-and-duration).

## Transactions in JavaScript

### In JavaScript, store.execute writes inside a transaction deadlock

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; the results were the same on all three releases |
| Setup | Inside a read-write transaction, we ran an `INSERT` and a `SELECT` through `ditto.store.execute`, and started a read-write transaction and a read-only transaction. A call that had not completed after 4 seconds counted as deadlocked (in [A deadlocked transaction does not end the process](#a-deadlocked-transaction-does-not-end-the-process), one had still not completed after 306 seconds) |
| Documentation | The description of `Store.transaction()` in the JavaScript SDK's type definitions (the same text in 5.0.3 and 5.2.0) warns: "**Warning:** Calling `ditto.store.execute()` or creating a nested transaction within a transaction may lead to a deadlock." |

- An `INSERT` through `ditto.store.execute` inside a read-write transaction never completes, and raises no exception. A `SELECT` completes, but, like any read outside the transaction, it does not see the transaction's writes (see [Reads outside a read-write transaction see only committed data](#reads-outside-a-read-write-transaction-see-only-committed-data)).
- A read-write transaction started inside a read-write transaction never completes. A read-only transaction started inside completes.

**Used in:** [Transaction Rules](../best-practices/transactions.md#transaction-rules), [Transactions on Other Platforms](../best-practices/transactions.md#transactions-on-other-platforms), [Platform Differences](platform-differences.md).

### A deadlocked transaction does not end the process

| | |
|---|---|
| Observed on | SDK 5.2.0, one run, stopped by hand after 306 seconds |
| Setup | A read-write transaction deadlocked by a write through `store.execute` inside it (as in [In JavaScript, store.execute writes inside a transaction deadlock](#in-javascript-storeexecute-writes-inside-a-transaction-deadlock)), with the minimum log level set to Error |
| Documentation | The JavaScript SDK's type definitions describe a deadlock detection for Node.js only: it ends the process when an asynchronous callback that Ditto called does not finish within a set time |

- `Ditto.hasDeadlockDetection()` returned `true`. Even so, the deadlocked transaction had not ended the process after 306 seconds.
- From 60 seconds on, `ERROR ditto_small_peer_store: Transaction <uuid> (hint: n/a) has been running for 60s)` was logged every 5 seconds. This log line was the only sign of the stuck transaction; a transaction's `hint` appears in it (see [Long transactions are logged at rising levels](#long-transactions-are-logged-at-rising-levels)).

**Not tested:** which callbacks the deadlock detection applies to.

**Used in:** [Transaction Rules](../best-practices/transactions.md#transaction-rules).

### A tx.execute that is not awaited is not applied

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; without a handler for the statement's failure, five runs each; the `forEach` case, three runs each. The results were the same on all three releases |
| Setup | The callback of a read-write transaction called `tx.execute(...)` to change `v`, which was 1, without `await`, and returned. Variants: with and without a handler for the statement's failure; three `INSERT` statements in `[1, 2, 3].forEach(async (i) => { await tx.execute(INSERT ...) })`; and, for comparison, `await Promise.all(items.map((item) => tx.execute(...)))` |

- When the callback returns without awaiting `tx.execute(...)`, the transaction ends without an error. The statement fails afterwards with a `store/backend` error, `No active write transaction found with id ... Active write transaction id: None`, and the value does not change (`v` stays 1).
- When nothing handles that failure, it becomes an unhandled promise rejection, and Node.js ends the process with exit code 1. This happened in 4 of 5 runs on 5.2.0 and in 1 of 5 runs on 5.1.0, depending on when the rejection occurred.
- The `forEach` form behaves the same: the transaction ends without an error, none of the three documents is inserted, and all three statements become unhandled rejections. Each is caused by `No active write transaction found`; on 5.1.0 and 5.2.0, the message has the prefix `Query failed: ... Insert failed: <store> No active write transaction found ...`. Later transactions and `close()` worked normally.
- `await Promise.all(items.map((item) => tx.execute(...)))` worked correctly on all three releases, with 10 `INSERT` statements, and with 10 `SELECT` statements in a read-only transaction. Running the statements in parallel is not the problem; not awaiting them is.
- A `tx` taken out of the transaction and used after the transaction has ended fails with the same error.
- The callback's return value becomes the result of `transaction()`, and a callback that throws rolls back its writes.

**Not tested:** Dart. A `tx.execute` left `unawaited` there probably behaves the same.

**Used in:** [Transaction Rules](../best-practices/transactions.md#transaction-rules).

### A Node.js script without sync ends with a panic while awaiting a transaction

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, five runs each for each kind of callback, for `store.execute`, and for the script that kept a timer; deterministic. The CommonJS script, and the script that started sync: three runs each on 5.1.0 and 5.2.0. The results were the same on all three releases |
| Setup | A Node.js script with nothing else that kept the event loop alive (no timer, no server) awaited `ditto.store.transaction(...)` with a read-write callback, a read-only callback, or a callback that did nothing. For comparison, the same script ran `store.execute` without a transaction, and kept a `setInterval` timer. Variants: a CommonJS script without top-level `await`, which called `async function main()`, and a script that started sync with `sync.start()` before the same transaction |

- Without anything that keeps the event loop alive, `await ditto.store.transaction(...)` makes Node.js print `Warning: Detected unsettled top-level await` and begin to exit. An SDK callback that arrives afterwards ends the process with `Panic: Error { status: PendingException, reason: "" }` (exit code 134). This happened with all three kinds of callback, in all five runs.
- A CommonJS script without top-level `await` fails the same way. No warning appears: Node.js begins to exit normally (`process.on('exit')` is called with exit code 0), and then the same panic ends the process (exit code 134). In both forms, the code after the transaction does not run.
- `store.execute` without a transaction completed in all five runs, and so did 500 `store.execute` calls run in parallel with `Promise.all` (see [Parallel writes are safe, but parallel read-modify-write loses updates](#parallel-writes-are-safe-but-parallel-read-modify-write-loses-updates)).
- With a `setInterval` timer kept running, the failure did not occur in any of the five runs. It did not occur inside a `node --test` test either, because the test runner keeps the event loop alive. Apps whose event loop always runs, such as servers or Electron apps, are not affected.
- A script that started sync (`sync.start()`, then the same transaction) completed in every run. Run again without sync on the same day, the script ended abnormally in every run (exit code 134 or 139, with `PendingException` or `InvalidArg` in the panic message). Only scripts that do not start sync, such as seed, migration, and command-line scripts, are affected.
- The same kind of abnormal exit also occurs occasionally with `fetchAttachment()`; with a transaction, it occurred every time. The other tests behind these pages always kept a timer running, so this failure did not affect them.

**Used in:** [Transactions on Other Platforms](../best-practices/transactions.md#transactions-on-other-platforms), [Platform Differences](platform-differences.md).

## Closing Ditto in JavaScript

### In JavaScript, close() waits for open transactions

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | While a read-write transaction was paused at an `await` inside its callback, we called `ditto.close()`, and then let the transaction continue |
| Documentation | The description of `Store.transaction()` in the JavaScript SDK's type definitions says: "When a Ditto instance goes out of scope, it will drive all pending transactions to completion before being shut down." |

- `close()` had not completed after 3 seconds. When the transaction continued, its next `tx.execute` succeeded, the transaction ended, and then `close()` completed.
- The SDK's code matches: in the JavaScript SDK 5.2.0, `Ditto.close()` sets `isClosed`, stops sync, and then waits with `Promise.allSettled` until all pending operations have finished.
- A transaction that never ends, such as a deadlocked one, therefore probably keeps `close()` from completing as well.

**Not tested:** Flutter.

**Used in:** [Concurrency and Duration](../best-practices/transactions.md#concurrency-and-duration), [Transactions on Other Platforms](../best-practices/transactions.md#transactions-on-other-platforms), [Resource Cleanup and Shutdown](../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Platform Differences](platform-differences.md).

### In JavaScript, close() completes pending writes

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, two runs each (cancelling an observer: one run each). Calls after `close()`: one run each on 5.1.0 and 5.2.0. Sending to another device: 54 runs |
| Setup | We started 200 `INSERT` statements without awaiting them and then awaited `ditto.close()` at once; we also started an `INSERT` right after calling `close()`, before awaiting it. Then we reopened the directory and counted the documents. Separately, we cancelled a store observer while writes continued, called each API after `close()`, and closed Ditto right after a write that was not awaited while another device was connected |

- `close()` completed in 81 to 172 ms, and all 200 inserts had succeeded; after reopening, all 200 documents were there.
- An `INSERT` started right after `close()` was called, before it was awaited, also succeeded and was there after reopening.
- `execute` after `close()` had completed failed with `Can't perform operation using a Ditto instance that has been closed.`
- After a store observer was cancelled with `cancel()` while writes continued, it received 0 callbacks.
- The JavaScript SDK wraps `execute` in `deferCloseAsync`, the same mechanism as for transactions (see [In JavaScript, close() waits for open transactions](#in-javascript-close-waits-for-open-transactions)), so `close()` waits for operations in progress.
- After `close()`, `store.execute`, `store.transaction`, `registerObserver`, `registerSubscription`, `sync.start()`, `sync.isActive`, `presence.graph`, and `updateTransportConfig` all throw `Error: Can't perform operation using a Ditto instance that has been closed.` This is a plain `Error`, not a `DittoError`. `cancel()` on subscriptions and observers registered before closing, and a second `close()`, raise no error, so cleanup code can cancel after closing and can call `close()` twice.
- `close()` waits only for local writes, not until they have been sent. When `close()` followed right after a write that was not awaited, the write was stored but reached the other device in 0 of 54 runs; it arrives at the next sync (see [A write made right before close or stop may not leave the device](subscriptions-and-replication.md#a-write-made-right-before-close-or-stop-may-not-leave-the-device)).

**Not tested:** Flutter, including whether its `close()` waits for pending work on 5.2.0.

**Used in:** [Resource Cleanup and Shutdown](../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Platform Differences](platform-differences.md).
