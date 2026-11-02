# Transactions and Observers

How transactions and store observers behave on one device: what other reads, writes, and incoming changes do while a read-write transaction or a large statement runs, how transactions fail in JavaScript, what `close()` waits for in JavaScript, when an observer is called and how changes are batched into callbacks, how observers differ between SDK releases, and how observers and query results behave in JavaScript. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Transactions](../best-practices/transactions.md), [Observing Changes](../best-practices/observers.md), [Resource Cleanup and Shutdown](../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), and [Platform Differences](platform-differences.md).

**In brief**

- While a read-write transaction is open, other reads see only committed data, other writes wait, and changes from other devices reach neither the store nor observers until it ends, also when it only reads. A large statement holds them up in the same way, on the writing and on the receiving device ([Reads outside a read-write transaction see only committed data](#reads-outside-a-read-write-transaction-see-only-committed-data), [Incoming changes wait while a read-write transaction is open](#incoming-changes-wait-while-a-read-write-transaction-is-open), [Large statements delay incoming changes and local writes](#large-statements-delay-incoming-changes-and-local-writes)).
- On one device, read-then-write sequences that run in parallel lose updates without an error, while the same sequences in transactions, or `UPDATE ... SET n = n + 1` statements, do not ([Parallel writes are safe, but parallel read-modify-write loses updates](#parallel-writes-are-safe-but-parallel-read-modify-write-loses-updates)).
- In JavaScript, a write through `store.execute` inside a transaction and a nested read-write transaction deadlock without an error and without ending the process, a `tx.execute` that is not awaited is not applied, and a Node.js script that does not start sync ends with a panic while it awaits a transaction ([In JavaScript, store.execute writes inside a transaction deadlock](#in-javascript-storeexecute-writes-inside-a-transaction-deadlock), [A deadlocked transaction does not end the process](#a-deadlocked-transaction-does-not-end-the-process), [A tx.execute that is not awaited is not applied](#a-txexecute-that-is-not-awaited-is-not-applied), [A Node.js script without sync ends with a panic while awaiting a transaction](#a-nodejs-script-without-sync-ends-with-a-panic-while-awaiting-a-transaction)).
- In JavaScript, `close()` waits for open transactions and pending writes, but not until changes have been sent to other devices ([In JavaScript, close() waits for open transactions](#in-javascript-close-waits-for-open-transactions), [In JavaScript, close() completes pending writes](#in-javascript-close-completes-pending-writes)).
- A `SELECT *` observer is called on every write to a document in its result, even of the same value; an observer that projects fields, only when a projected value changes; an aggregate observer, on every write to the collection ([When an observer fires depends on its query](#when-an-observer-fires-depends-on-its-query), [Writing the same value from an observer keeps it firing](#writing-the-same-value-from-an-observer-keeps-it-firing)).
- Since SDK 5.1, changes are coalesced into callbacks about 30 ms apart, so an observer skips intermediate values. Changes from another device arrive in a few callbacks, and a transaction in one ([Local writes are coalesced into callbacks about 30 ms apart](#local-writes-are-coalesced-into-callbacks-about-30-ms-apart), [A device receives nearly every value of a fast-changing field](#a-device-receives-nearly-every-value-of-a-fast-changing-field), [Remote changes arrive in a few callbacks, and a transaction in one](#remote-changes-arrive-in-a-few-callbacks-and-a-transaction-in-one)).
- On SDK 5.2.0, observer rows have no `_id` unless the query projects it; on SDK 5.1.0, 60 or more observers stop every callback ([On SDK 5.2.0, observer rows include _id only when it is projected](#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected), [On SDK 5.1.0, observers stall beyond about 60](#on-sdk-510-observers-stall-beyond-about-60)).
- In JavaScript, async observer callbacks are not awaited and can finish out of order, exceptions in callbacks are discarded, and garbage collection stops neither observers nor subscriptions ([In JavaScript, registerObserver does not await async callbacks](#in-javascript-registerobserver-does-not-await-async-callbacks), [In JavaScript, exceptions in observer callbacks are discarded](#in-javascript-exceptions-in-observer-callbacks-are-discarded), [In JavaScript, garbage-collected subscriptions and observers keep running](#in-javascript-garbage-collected-subscriptions-and-observers-keep-running)).

## Concurrency, waiting, and long transactions

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

- On the writing device, the updates waited as in [Incoming changes wait while a read-write transaction is open](#incoming-changes-wait-while-a-read-write-transaction-is-open). The maximum of 52 to 60 ms with split statements includes the observer's coalescing of about 34 ms (see [A device receives nearly every value of a fast-changing field](#a-device-receives-nearly-every-value-of-a-fast-changing-field)).
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

## When observers are called

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

## Observer differences between SDK releases

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

## Observers and results in JavaScript

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
