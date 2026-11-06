# Transactions

**Use a transaction only when several statements must commit together or read one snapshot; keep it short, use only the transaction's own `execute` inside it, and never start a read-write transaction inside another.** A transaction runs several DQL statements against the local store **atomically**: either all of their changes are committed, or none are. Transactions are a local concept: they do not lock anything on other peers, and concurrent edits from other devices still merge with the transaction's writes field by field, by the CRDT rules (see [CRDT Types and Merge Behavior](../knowledge/crdt-types.md)). Values written together can therefore end up mixed with another device's edit: in our testing, `amount = 15000` and `currency = 'JPY'` written in one transaction, and a later `amount = 120` from another device, gave `120 JPY` on both devices (see [Fields written in one transaction still merge field by field](../knowledge/observations/merge-behavior.md#fields-written-in-one-transaction-still-merge-field-by-field)). Keep values that must change together, such as an amount and its currency, in one object declared as `REGISTER` (see [When to choose strict mode](data-modeling.md#when-to-choose-strict-mode)).

**When to use a transaction:**
- Changes that span several documents and must never be visible half-done, such as closing an order and creating its invoice, or moving an item between two lists (dual writes)
- Read-check-write sequences on the local store, where the write depends on what you just read and one statement cannot express it. Without a transaction, such sequences lose updates even on one device, without an error: in our testing with the JavaScript SDK, 500 read-then-write increments started at once left the value at 2 or 3, while the same sequence in transactions, and `UPDATE ... SET n = n + 1` statements (SDK 5.1+), which read and write as one unit, kept every update (see [Parallel writes are safe, but parallel read-modify-write loses updates](../knowledge/observations/transaction-behavior.md#parallel-writes-are-safe-but-parallel-read-modify-write-loses-updates)). Between devices, neither helps, because concurrent writes to one field are resolved by last-writer-wins; use a `COUNTER` (see [Counters](data-modeling.md#counters))
- Several reads that must see one consistent snapshot (read-only transaction)

**When not to use one:** A single `INSERT`, `UPDATE`, or `DELETE` statement is already atomic. Wrapping it in a transaction adds nothing.

## Using store.transaction

`ditto.store.transaction` takes the work as a callback, which receives a transaction object, and two options: `isReadOnly` (default `false`; read-only transactions reject mutating statements and can run concurrently) and `hint` (a label written to the logs, for example in messages about long-running transactions). Inside the callback, run every statement through the transaction object's `execute`.

| SDK | Call | Commit | Roll back |
|---|---|---|---|
| Flutter | `ditto.store.transaction(hint:, isReadOnly:, (tx) async {...})` | Return any value, or `TransactionCompletionAction.commit` | Return `TransactionCompletionAction.rollback`, or throw |
| JavaScript | `ditto.store.transaction(async (tx) => {...}, { isReadOnly, hint })` | Return any value | Return `'rollback'`, or throw |
| Kotlin | `ditto.store.transaction(hint, isReadOnly) { tx -> ... }` | Return `DittoTransaction.Result.Commit(value)` | Return `DittoTransaction.Result.Rollback`, or throw |
| Swift | `try await ditto.store.transaction(hint:isReadOnly:) { tx in ... }` | Return a value, or `.commit` | Return `.rollback`, or throw |

In every SDK, a callback that throws rolls the transaction back, and the error reaches the caller of `transaction`. A statement that fails inside the callback does **not** end the transaction when the callback catches the error: the remaining changes are committed unless you roll back.

```sql
-- ✅ GOOD: Close an order and create its invoice atomically: the three
-- statements of one read-write transaction. Roll back if the first one
-- returns no order.
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id

-- Arguments: {"invoice": {"_id": "invoice-1", "orderId": "order-1", "total": 42, "createdAt": "2026-01-15T10:30:00.000Z"}}
INSERT INTO invoices DOCUMENTS (:invoice)

-- Arguments: {"id": "order-1", "status": "closed", "invoiceId": "invoice-1"}
UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id
```

The code for a transaction with a rollback, a typed return value, and a read-only snapshot: [Transactions in Flutter](platforms/flutter.md#transactions-in-flutter) · [JavaScript](platforms/javascript.md#transactions-in-javascript) · [Kotlin](platforms/kotlin.md#transactions-in-kotlin) · [Swift](platforms/swift.md#transactions-in-swift).

## Transaction Rules

**✅ DO:**
- Use **only** the transaction object's `execute` inside the callback.
- Keep transactions short: read, decide, write, return.
- Prepare everything that needs I/O (network responses, files, user input, attachments created with `newAttachment`) **before** starting the transaction.
- Give every transaction a `hint`.
- Use `isReadOnly` for transactions that only read.
- Await all pending transactions before closing Ditto; in Flutter, closing does not wait for them.

**❌ DON'T:**
- Call `ditto.store.execute` inside the callback. None of the SDKs makes it work. Flutter throws a `DittoException` ("Attempting to use `ditto.store.execute` while in a transaction scope. Use `transaction.execute` instead ..."). In JavaScript, Kotlin, and Swift, a write through `store.execute` never completed, without an error, in our testing with SDK 5.1.0 and 5.2.0, and a read completed without seeing the transaction's own writes; the only sign was a log line, `Transaction <id> (hint: ...) has been running for ...`, every 5 seconds (see [In JavaScript, store.execute writes inside a transaction deadlock](../knowledge/observations/javascript-sdk.md#in-javascript-storeexecute-writes-inside-a-transaction-deadlock), [In Kotlin, store.execute writes inside a transaction deadlock](../knowledge/observations/kotlin-sdk.md#in-kotlin-storeexecute-writes-inside-a-transaction-deadlock), [In Swift, store.execute writes and nested read-write transactions inside a transaction do not return](../knowledge/observations/swift-sdk.md#in-swift-storeexecute-writes-and-nested-read-write-transactions-inside-a-transaction-do-not-return), and [A deadlocked transaction does not end the process](../knowledge/observations/transaction-behavior.md#a-deadlocked-transaction-does-not-end-the-process)).
- Start a read-write transaction inside another read-write transaction. Only one read-write transaction runs at a time, so the inner one waits for the outer one forever (deadlock). In our testing, this held in all four SDKs on SDK 5.1.0 and 5.2.0, while a read-only transaction inside a read-write one completed (see [In Flutter, a read-write transaction started inside another waits for the outer one](../knowledge/observations/flutter-sdk.md#in-flutter-a-read-write-transaction-started-inside-another-waits-for-the-outer-one), [In JavaScript, a read-write transaction started inside another one waits until the outer one ends](../knowledge/observations/javascript-sdk.md#in-javascript-a-read-write-transaction-started-inside-another-one-waits-until-the-outer-one-ends), [In Kotlin, a read-write transaction inside a read-write transaction deadlocks](../knowledge/observations/kotlin-sdk.md#in-kotlin-a-read-write-transaction-inside-a-read-write-transaction-deadlocks), and [In Swift, store.execute writes and nested read-write transactions inside a transaction do not return](../knowledge/observations/swift-sdk.md#in-swift-storeexecute-writes-and-nested-read-write-transactions-inside-a-transaction-do-not-return)).
- Start many writes in parallel while a read-write transaction is open. Each write that waits for the transaction can hold a thread, and when the threads run out, the transaction cannot resume and the app stops. In our testing, this happened in Kotlin with 64 writes on `Dispatchers.IO`, and in Swift with 14 writes, the number of cores of the test machine, which a phone reaches sooner (see [In Kotlin, writes that wait behind a transaction each hold a thread](../knowledge/observations/kotlin-sdk.md#in-kotlin-writes-that-wait-behind-a-transaction-each-hold-a-thread) and [In Swift, 14 concurrent writes during an open transaction stop the process](../knowledge/observations/swift-sdk.md#in-swift-14-concurrent-writes-during-an-open-transaction-stop-the-process)). Run such writes one after another, or after the transaction.
- Make network calls, show dialogs, wait for user input, or wait for timers inside a transaction. While it waits, this device also stops taking in changes from other devices (see [Concurrency and Duration](#concurrency-and-duration) and [Incoming changes wait while a read-write transaction is open](../knowledge/observations/transaction-behavior.md#incoming-changes-wait-while-a-read-write-transaction-is-open)).
- Return from the callback before every statement has completed, for example by leaving out an `await` or by starting the statements in a loop that does not wait for them. In our testing with the JavaScript SDK, such a statement was not applied: the transaction committed without an error, the statement failed afterwards, and, when nothing handled that failure, the unhandled rejection could end the Node.js process (see [A tx.execute that is not awaited is not applied](../knowledge/observations/javascript-sdk.md#a-txexecute-that-is-not-awaited-is-not-applied)). Await each statement, for example in a `for` loop.
- Store the transaction object or use it after the callback returns; the SDKs reject it outside its scope (Flutter throws a `DittoException`; JavaScript fails with `No active write transaction found with id ...`).
- Read the commit ID inside the transaction to track sync status; it is empty until the transaction commits. Keep the query result of the write (for example, return it from the callback) and read its commit ID after `transaction` completes (see [Reads outside a read-write transaction see only committed data](../knowledge/observations/transaction-behavior.md#reads-outside-a-read-write-transaction-see-only-committed-data)).

```sql
-- ✅ GOOD: Do the I/O (charging the card) first, then record the outcome in
-- one short transaction with these two statements
-- Arguments: {"id": "order-1", "status": "paid", "paidAt": "2026-01-15T10:30:00.000Z"}
UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id

-- Arguments: {"payment": {"_id": "payment-order-1", "orderId": "order-1"}}
INSERT INTO payments DOCUMENTS (:payment)
```

The code for a checkout that does its I/O first, and for the mistakes above: [Transactions in Flutter](platforms/flutter.md#transactions-in-flutter) · [JavaScript](platforms/javascript.md#transactions-in-javascript) · [Kotlin](platforms/kotlin.md#transactions-in-kotlin) · [Swift](platforms/swift.md#transactions-in-swift).

## Concurrency and Duration

- **One read-write transaction at a time:** Any other read-write transaction started meanwhile waits until the current one commits or rolls back. A plain `store.execute` write issued meanwhile also waits.
- **Read-only transactions** can run concurrently with each other and with the active read-write transaction. A mutating statement inside a read-only transaction throws (`A mutating DQL query was attempted using a read-only transaction.`). They see only committed data: in our testing, a read-only transaction and a `store.execute` read returned the state from before the open read-write transaction, without its writes (see [Reads outside a read-write transaction see only committed data](../knowledge/observations/transaction-behavior.md#reads-outside-a-read-write-transaction-see-only-committed-data)).
- **Arrival order (SDK 5.1+):** Small Peer write transactions are processed in arrival order, which prevents a write from being starved indefinitely by competing operations.
- **Long transactions are logged:** The [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) says that after a transaction has run for 10 seconds, Ditto logs a message about it, with its `hint`, every 5 seconds, at levels that rise from debug; the system parameters `TRANSACTION_DURATION_BEFORE_LOGGING_MS` and `TRANSACTION_TRACE_INTERVAL_MS` change the two times. In our testing, the level rose to info at 20 seconds, warning at 35 seconds, and error at 60 seconds, so with the default minimum level, info, the first line appears after 20 seconds, and with warning, after 35 seconds (see [Long transactions are logged at rising levels](../knowledge/observations/transaction-behavior.md#long-transactions-are-logged-at-rising-levels)).
- **Incoming changes wait too:** **Note (SDK 5.1.0 and 5.2.0)**: in our testing, while a read-write transaction was open, even one that only read, changes from other devices reached neither the store nor observers until it ended: a transaction held open for 15 seconds held them back for those 15 seconds, while during an `isReadOnly: true` transaction they kept arriving (see [Incoming changes wait while a read-write transaction is open](../knowledge/observations/transaction-behavior.md#incoming-changes-wait-while-a-read-write-transaction-is-open)). Keep read-write transactions short, and mark transactions that only read with `isReadOnly: true`.
- **Large writes hold up both sides:** In our testing with SDK 5.1.0 and 5.2.0, one `UPDATE` of 50,000 documents held back the changes arriving from other devices for up to about 0.6 seconds, and 30,000 documents inserted in one transaction on another device made the receiving device's own writes wait up to about 1.3 seconds while it applied them, so a screen that awaits a write can seem frozen during a large sync. Rewriting the same documents in statements of 1,000 selected by an indexed condition kept the delay of incoming changes to about 60 ms, and documents sent in statements of 1,000 held up the receiving device's writes about half as long (see [Large statements delay incoming changes and local writes](../knowledge/observations/transaction-behavior.md#large-statements-delay-incoming-changes-and-local-writes)). Split migrations and bulk rewrites this way, and use one transaction only for changes that must appear at once.
- **Closing:** According to the [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions), closing Ditto waits for pending transactions to complete, except in Flutter, which does not support waiting for them; in our testing with the JavaScript SDK, `close()` completed only after an open transaction had finished (see [In JavaScript, close() waits for open transactions](../knowledge/observations/javascript-sdk.md#in-javascript-close-waits-for-open-transactions)), so a transaction that never ends, such as a deadlocked one, probably keeps it from completing. In Flutter, track pending transactions yourself and await them before closing (see [Transactions in Flutter](platforms/flutter.md#transactions-in-flutter) and [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown)).

## Transactions and Sync

**Write documents that must appear together in one transaction, and give every device that receives or relays them subscriptions that cover all of them.**

**✅ DO:**
- Keep documents that are changed together in the same subscription scope (for example, both carry the same `storeId`).
- Give every device that relays a collection the subscriptions for the documents written together with it, and ensure sufficient connectivity with peers that have broader subscription sets.
- Make screens tolerate a parent whose children have not arrived yet, for example by storing the expected number of children in the parent and showing it as incomplete until they are all there; connectivity alone does not prevent a temporary partial view.

Atomicity is guaranteed on the device that commits the transaction. On the other devices, the [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) says that replication keeps the transaction atomic when their subscriptions cover it. In our testing with SDK 5.1.0 and 5.2.0, receiving devices applied a transaction of 30,000 documents in one step, and so did one statement that wrote as many, when their subscriptions and those of every relay in between covered all of its documents; documents written one statement at a time arrived in steps (see [Large transactions and statements arrived all at once](../knowledge/observations/subscriptions-and-replication.md#large-transactions-and-statements-arrived-all-at-once)). Such documents arrived in the order written, and a device that had been offline received them in one or two steps, without a gap, but that order is not documented, and a relay with narrower subscriptions breaks it (see [Changes written in separate statements arrived in the order written](../knowledge/observations/subscriptions-and-replication.md#changes-written-in-separate-statements-arrived-in-the-order-written)).

The documentation describes two replication limits, both of which our testing confirmed:

- A peer whose subscriptions cover only part of a transaction's documents receives only that part. If it later broadens its subscriptions, the remaining changes arrive only when replication catches up.
- A peer that relays changes can forward only what it has. A device connected only through a relay with narrower subscriptions may receive an incomplete transaction (see [Multi-hop relay](sync-and-subscriptions.md#multi-hop-relay) and [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)). For example, Peer 1 changes documents A and B in one transaction, Peer 2 subscribes only to A, and Peer 3 is connected only to Peer 2 but subscribes to both A and B. Peer 3 receives only the change to A, because Peer 2 never had the change to B.

A device that is also connected to the writer can still show part of a transaction for a while when such a relay is its faster path. In our testing with SDK 5.1.0 and 5.2.0, a receiving device connected to the writer over a slow link, and to a fast relay that subscribed only to `orders`, showed all 30 orders of a transaction without their `orderItems` for up to about 0.7 seconds in 6 of 12 runs, and writing the items first did not help (see [A fast relay with narrower subscriptions can show part of a transaction](../knowledge/observations/subscriptions-and-replication.md#a-fast-relay-with-narrower-subscriptions-can-show-part-of-a-transaction)).
