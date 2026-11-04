# Transactions

A transaction runs several DQL statements against the local store **atomically**: either all of their changes are committed, or none are. Transactions are a local concept: they do not lock anything on other peers, and concurrent edits from other devices still merge with the transaction's writes field by field, by the CRDT rules (see [CRDT Types and Merge Behavior](../knowledge/crdt-types.md)). Values written together can therefore end up mixed with another device's edit: in our testing, `amount = 15000` and `currency = 'JPY'` written in one transaction, and a later `amount = 120` from another device, gave `120 JPY` on both devices (see [Fields written in one transaction still merge field by field](../knowledge/observations/merge-behavior.md#fields-written-in-one-transaction-still-merge-field-by-field)). Keep values that must change together, such as an amount and its currency, in one object declared as `REGISTER` (see [When to choose strict mode](data-modeling.md#when-to-choose-strict-mode)).

**When to use a transaction:**
- Changes that span several documents and must never be visible half-done, such as closing an order and creating its invoice, or moving an item between two lists (dual writes)
- Read-check-write sequences on the local store, where the write depends on what you just read and one statement cannot express it. Without a transaction, such sequences lose updates even on one device, without an error: in our testing with the JavaScript SDK, 500 read-then-write increments started at once left the value at 2 or 3, while the same sequence in transactions, and `UPDATE ... SET n = n + 1` statements (SDK 5.1+), which read and write as one unit, kept every update (see [Parallel writes are safe, but parallel read-modify-write loses updates](../knowledge/observations/transaction-behavior.md#parallel-writes-are-safe-but-parallel-read-modify-write-loses-updates)). Between devices, neither helps, because concurrent writes to one field are resolved by last-writer-wins; use a `COUNTER` (see [Counters](data-modeling.md#counters))
- Several reads that must see one consistent snapshot (read-only transaction)

**When not to use one:** A single `INSERT`, `UPDATE`, or `DELETE` statement is already atomic. Wrapping it in a transaction adds nothing.

## Using store.transaction

```dart
// ✅ GOOD: Close an order and create its invoice atomically.
Future<void> closeOrderWithInvoice(Ditto ditto, String orderId, String invoiceId) async {
  await ditto.store.transaction(
    hint: 'closeOrderWithInvoice', // Appears in logs; useful for debugging.
    (tx) async {
      final result = await tx.execute(
        'SELECT * FROM orders WHERE _id = :id',
        arguments: {'id': orderId},
      );
      if (result.items.isEmpty) {
        throw StateError('Order $orderId not found'); // Throwing rolls back.
      }
      final order = result.items.first.value;

      await tx.execute(
        'INSERT INTO invoices DOCUMENTS (:invoice)',
        arguments: {
          'invoice': {
            '_id': invoiceId,
            'orderId': orderId,
            'total': order['total'],
            'createdAt': utcTimestamp(), // Defined in the Timestamps section.
          },
        },
      );
      await tx.execute(
        'UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id',
        arguments: {'id': orderId, 'status': 'closed', 'invoiceId': invoiceId},
      );
    },
  );
}
```

`Store.transaction` signature (Flutter):

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `callback` (positional) | `Future<T> Function(Transaction)` | required | The work to do. Use only the `Transaction` passed in. |
| `isReadOnly` | `bool` | `false` | Read-only transactions reject mutating statements and can run concurrently |
| `hint` | `String?` | `null` | A label written to the logs (for example, in messages about long-running transactions) |

How a transaction ends:

| Callback outcome | Result |
|---|---|
| Returns `TransactionCompletionAction.commit` | Committed; `transaction()` returns `TransactionCompletionAction.commit` |
| Returns `TransactionCompletionAction.rollback` | Rolled back; no changes are applied; `transaction()` returns `TransactionCompletionAction.rollback` |
| Returns any other value (including nothing) | Committed; `transaction()` returns that value |
| Throws | Rolled back; the error is rethrown to the caller of `transaction()` |
| A statement fails, but the callback catches the error | The transaction **continues**; the remaining changes are committed unless you roll back |

```dart
// ✅ GOOD: Explicit rollback without throwing, and a typed return value.
Future<bool> shipOrder(Ditto ditto, String orderId) async {
  final action = await ditto.store.transaction(
    hint: 'shipOrder',
    (tx) async {
      final result = await tx.execute(
        'SELECT * FROM orders WHERE _id = :id AND status = :status',
        arguments: {'id': orderId, 'status': 'paid'},
      );
      if (result.items.isEmpty) {
        return TransactionCompletionAction.rollback; // Nothing to ship.
      }
      await tx.execute(
        'UPDATE orders SET status = :status WHERE _id = :id',
        arguments: {'id': orderId, 'status': 'shipped'},
      );
      return TransactionCompletionAction.commit;
    },
  );
  return action == TransactionCompletionAction.commit;
}

// ✅ GOOD: A read-only transaction for a consistent multi-query snapshot.
Future<(int open, int closed)> orderCounts(Ditto ditto) {
  return ditto.store.transaction(
    hint: 'orderCounts',
    isReadOnly: true,
    (tx) async {
      final open = await tx.execute(
        'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
        arguments: {'status': 'open'},
      );
      final closed = await tx.execute(
        'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
        arguments: {'status': 'closed'},
      );
      return (
        open.items.first.value['n'] as int,
        closed.items.first.value['n'] as int,
      );
    },
  );
}
```

## Transaction Rules

**✅ DO:**
- Use **only** `tx.execute(...)` inside the callback.
- Keep transactions short: read, decide, write, return.
- Prepare everything that needs I/O (network responses, files, user input, attachments created with `newAttachment`) **before** starting the transaction.
- Give every transaction a `hint`.
- Use `isReadOnly: true` for transactions that only read.
- Await all pending transactions before calling `ditto.close()`; in Flutter, closing does not wait for them.

**❌ DON'T:**
- Call `ditto.store.execute(...)` inside the callback. In Flutter it throws a `DittoException` ("Attempting to use `ditto.store.execute` while in a transaction scope. Use `transaction.execute` instead ..."). In JavaScript, Swift, and Kotlin the SDKs do not throw, so the same rule applies: in our testing with the JavaScript SDK, an `INSERT` through `store.execute` inside a read-write transaction never completed, without an error and without ending the process; the only sign was a log line, `Transaction <id> (hint: ...) has been running for ...`, every 5 seconds (see [In JavaScript, store.execute writes inside a transaction deadlock](../knowledge/observations/transaction-behavior.md#in-javascript-storeexecute-writes-inside-a-transaction-deadlock) and [A deadlocked transaction does not end the process](../knowledge/observations/transaction-behavior.md#a-deadlocked-transaction-does-not-end-the-process)).
- Start a read-write transaction inside another read-write transaction. Only one read-write transaction runs at a time, so the inner one waits for the outer one forever (deadlock). Flutter has no guard against this.
- Make network calls, show dialogs, wait for user input, or `await` timers inside a transaction. While it waits, this device also stops taking in changes from other devices (see [Concurrency and Duration](#concurrency-and-duration) and [Incoming changes wait while a read-write transaction is open](../knowledge/observations/transaction-behavior.md#incoming-changes-wait-while-a-read-write-transaction-is-open)).
- Return from the callback before every `tx.execute` has completed, for example by leaving out an `await` or by calling `tx.execute` in `forEach` with an `async` function. In our testing with the JavaScript SDK, such a statement was not applied: the transaction committed without an error, the statement failed afterwards, and, when nothing handled that failure, the unhandled rejection could end the Node.js process (see [A tx.execute that is not awaited is not applied](../knowledge/observations/transaction-behavior.md#a-txexecute-that-is-not-awaited-is-not-applied)). Await each statement, for example in a `for` loop; in JavaScript, `await Promise.all(...)` over the statements also worked. In Dart, the `unawaited_futures` lint reports a missing `await`.
- Store the `Transaction` object or use it after the callback returns; Flutter throws a `DittoException` when it is used outside its scope (JavaScript: `No active write transaction found with id ...`).
- Read `commitID` inside the transaction to track sync status; it is `null` until the transaction commits. Keep the `QueryResult` of the write (for example, return it from the callback) and read its `commitID` after `transaction()` completes (see [Reads outside a read-write transaction see only committed data](../knowledge/observations/transaction-behavior.md#reads-outside-a-read-write-transaction-see-only-committed-data)).

```dart
// ❌ BAD: Mixing store.execute into a transaction, nesting, and doing network I/O.
Future<void> badCheckout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'checkout'},
    );
    // Network call inside the transaction: every other write, and every change
    // from other devices, waits until the transaction ends.
    await chargeCard();
    // Throws in Flutter (can deadlock on other platforms): use tx.execute instead.
    await ditto.store.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'paid'},
    );
    // Deadlock: the inner read-write transaction waits for the outer one.
    await ditto.store.transaction((inner) async {
      await inner.execute(
        'UPDATE orders SET paidAt = :paidAt WHERE _id = :id',
        arguments: {'id': orderId, 'paidAt': DateTime.now().toUtc().toIso8601String()},
      );
    });
  });
}

// ✅ GOOD: Do the I/O first, then record the outcome in one short transaction.
Future<void> checkout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await chargeCard(); // Outside the transaction.
  await ditto.store.transaction(hint: 'recordPayment', (tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id',
      arguments: {
        'id': orderId,
        'status': 'paid',
        'paidAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await tx.execute(
      'INSERT INTO payments DOCUMENTS (:payment)',
      arguments: {
        'payment': {'_id': 'payment-$orderId', 'orderId': orderId},
      },
    );
  });
}
```

## Concurrency and Duration

- **One read-write transaction at a time:** Any other read-write transaction started meanwhile waits until the current one commits or rolls back. A plain `store.execute` write issued meanwhile also waits.
- **Read-only transactions** can run concurrently with each other and with the active read-write transaction. A mutating statement inside a read-only transaction throws (`A mutating DQL query was attempted using a read-only transaction.`). They see only committed data: in our testing, a read-only transaction and a `store.execute` read returned the state from before the open read-write transaction, without its writes (see [Reads outside a read-write transaction see only committed data](../knowledge/observations/transaction-behavior.md#reads-outside-a-read-write-transaction-see-only-committed-data)).
- **Arrival order (SDK 5.1+):** Small Peer write transactions are processed in arrival order, which prevents a write from being starved indefinitely by competing operations.
- **Long transactions are logged:** The [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) says that after a transaction has run for 10 seconds, Ditto logs a message about it, with its `hint`, every 5 seconds, at levels that rise from debug; the system parameters `TRANSACTION_DURATION_BEFORE_LOGGING_MS` and `TRANSACTION_TRACE_INTERVAL_MS` change the two times. In our testing, the level rose to info at 20 seconds, warning at 35 seconds, and error at 60 seconds, so with the default minimum level, info, the first line appears after 20 seconds, and with warning, after 35 seconds (see [Long transactions are logged at rising levels](../knowledge/observations/transaction-behavior.md#long-transactions-are-logged-at-rising-levels)).
- **Incoming changes wait too:** **Note (SDK 5.1.0 and 5.2.0)**: in our testing, while a read-write transaction was open, even one that only read, changes from other devices reached neither the store nor observers until it ended: a transaction held open for 15 seconds held them back for those 15 seconds, while during an `isReadOnly: true` transaction they kept arriving (see [Incoming changes wait while a read-write transaction is open](../knowledge/observations/transaction-behavior.md#incoming-changes-wait-while-a-read-write-transaction-is-open)). Keep read-write transactions short, and mark transactions that only read with `isReadOnly: true`.
- **Large writes hold up both sides:** In our testing with SDK 5.1.0 and 5.2.0, one `UPDATE` of 50,000 documents held back the changes arriving from other devices for up to about 0.6 seconds, and 30,000 documents inserted in one transaction on another device made the receiving device's own writes wait up to about 1.3 seconds while it applied them, so a screen that awaits a write can seem frozen during a large sync. Rewriting the same documents in statements of 1,000 selected by an indexed condition kept the delay of incoming changes to about 60 ms, and documents sent in statements of 1,000 held up the receiving device's writes about half as long (see [Large statements delay incoming changes and local writes](../knowledge/observations/transaction-behavior.md#large-statements-delay-incoming-changes-and-local-writes)). Split migrations and bulk rewrites this way, and use one transaction only for changes that must appear at once.
- **Closing:** According to the [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions), `close()` waits for pending transactions to complete, except in Flutter, which does not support waiting for them. In JavaScript, `close()` completed only after an open transaction had finished, so a transaction that never ends, such as a deadlocked one, probably keeps `close()` from completing as well (see [In JavaScript, close() waits for open transactions](../knowledge/observations/transaction-behavior.md#in-javascript-close-waits-for-open-transactions)). In Flutter, track pending transactions yourself and await them before closing (see [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown)).

```dart
// ✅ GOOD: Track in-flight transactions so shutdown can wait for them.
class TransactionTracker {
  final _pending = <Future<Object?>>{};

  Future<T> run<T>(Ditto ditto, String hint, Future<T> Function(Transaction tx) work) {
    final future = ditto.store.transaction(hint: hint, work);
    _pending.add(future);
    return future.whenComplete(() => _pending.remove(future));
  }

  Future<void> closeWhenIdle(Ditto ditto) async {
    // Errors are reported to the callers of run(); ignore them here.
    // then() with an onError callback works for any result type T, whereas a
    // catchError handler would have to return a value of type T.
    await Future.wait(_pending.map((f) => f.then<void>((_) {}, onError: (Object _) {})));
    await ditto.close();
  }
}
```

## Transactions and Sync

Atomicity is guaranteed on the device that commits the transaction. On the other devices, the [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) says that replication keeps the transaction atomic when their subscriptions cover it. In our testing with SDK 5.1.0 and 5.2.0, receiving devices applied a transaction of 30,000 documents in one step, and so did one statement that wrote as many, when their subscriptions and those of every relay in between covered all of its documents; documents written one statement at a time arrived in steps (see [Large transactions and statements arrived all at once](../knowledge/observations/subscriptions-and-replication.md#large-transactions-and-statements-arrived-all-at-once)). Such documents arrived in the order written, and a device that had been offline received them in one or two steps, without a gap, but that order is not documented, and a relay with narrower subscriptions breaks it (see [Changes written in separate statements arrived in the order written](../knowledge/observations/subscriptions-and-replication.md#changes-written-in-separate-statements-arrived-in-the-order-written)). Write documents that must appear together in one transaction.

The documentation describes two replication limits, both of which our testing confirmed:

- A peer whose subscriptions cover only part of a transaction's documents receives only that part. If it later broadens its subscriptions, the remaining changes arrive only when replication catches up.
- A peer that relays changes can forward only what it has. A device connected only through a relay with narrower subscriptions may receive an incomplete transaction (see [Multi-hop relay](sync-and-subscriptions.md#multi-hop-relay) and [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)). For example, Peer 1 changes documents A and B in one transaction, Peer 2 subscribes only to A, and Peer 3 is connected only to Peer 2 but subscribes to both A and B. Peer 3 receives only the change to A, because Peer 2 never had the change to B.

A device that is also connected to the writer can still show part of a transaction for a while when such a relay is its faster path. In our testing with SDK 5.1.0 and 5.2.0, a receiving device connected to the writer over a slow link, and to a fast relay that subscribed only to `orders`, showed all 30 orders of a transaction without their `orderItems` for up to about 0.7 seconds in 6 of 12 runs, and writing the items first did not help (see [A fast relay with narrower subscriptions can show part of a transaction](../knowledge/observations/subscriptions-and-replication.md#a-fast-relay-with-narrower-subscriptions-can-show-part-of-a-transaction)).

Keep documents that are changed together in the same subscription scope (for example, both carry the same `storeId`), give every device that relays a collection the subscriptions for the documents written together with it, and ensure sufficient connectivity with peers that have broader subscription sets; connectivity alone does not prevent a temporary partial view. Make screens tolerate a parent whose children have not arrived yet, for example by storing the expected number of children in the parent and showing it as incomplete until they are all there.

## Transactions on Other Platforms

| Platform | API | Explicit rollback | Notes |
|---|---|---|---|
| Flutter | `ditto.store.transaction(hint:, isReadOnly:, (tx) async {...})` | Return `TransactionCompletionAction.rollback` | Any other return value commits; `store.execute` inside throws |
| JavaScript | `ditto.store.transaction(async (tx) => {...}, { isReadOnly, hint })` | Return `'rollback'` | Any other return value commits; `store.execute` writes inside deadlock (see below) |
| Swift | `try await ditto.store.transaction(hint:isReadOnly:) { tx in ... }` | Return `.rollback` | Return `.commit` (or a value) to commit |
| Kotlin | `ditto.store.transaction(hint, isReadOnly) { tx -> ... }` | Return `DittoTransaction.Result.Rollback` | The block must return `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback` |

In JavaScript, three behaviors that we observed on SDK 5.0.3, 5.1.0, and 5.2.0 need care (see [Platform Differences](../knowledge/platform-differences.md)):

- A write through `store.execute` inside a read-write transaction, and a read-write transaction started inside one, deadlocked without an error (see [In JavaScript, store.execute writes inside a transaction deadlock](../knowledge/observations/transaction-behavior.md#in-javascript-storeexecute-writes-inside-a-transaction-deadlock)).
- `close()` waits for open transactions, so a transaction that never ends probably keeps it from completing (see [Concurrency and Duration](#concurrency-and-duration) and [In JavaScript, close() waits for open transactions](../knowledge/observations/transaction-behavior.md#in-javascript-close-waits-for-open-transactions)).
- A Node.js script that keeps neither sync nor a timer running, such as a seed or migration script, ended with a panic while it awaited a transaction. Keep the event loop alive while it runs, for example with a timer that you clear afterwards (see [A Node.js script that keeps neither sync nor a timer running ends with a panic while awaiting a transaction](../knowledge/observations/transaction-behavior.md#a-nodejs-script-that-keeps-neither-sync-nor-a-timer-running-ends-with-a-panic-while-awaiting-a-transaction)).
