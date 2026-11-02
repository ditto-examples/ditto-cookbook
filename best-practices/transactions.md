# Transactions

A transaction runs several DQL statements against the local store **atomically**: either all of their changes are committed, or none are. Transactions are a local concept; they do not lock anything on other peers, and concurrent edits from other devices are still merged with CRDT rules (see [CRDT Types and Merge Behavior](../knowledge/crdt-types.md)).

**When to use a transaction:**
- Changes that span several documents and must never be visible half-done, such as closing an order and creating its invoice, or moving an item between two lists (dual writes)
- Read-check-write sequences on the local store, where the write depends on what you just read. Without a transaction, such sequences lose updates even on one device: in our testing with the JavaScript SDK, 500 concurrent read-then-write increments left the value at 2 or 3, while the same sequence in transactions ran one after another and reached exactly the expected count. Between devices, a transaction does not help; use a `COUNTER` (see [Counters](data-modeling.md#counters))
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
- Await all pending transactions before calling `ditto.close()`; closing does not wait for them.

**❌ DON'T:**
- Call `ditto.store.execute(...)` inside the callback. In Flutter it throws a `DittoException` ("Attempting to use `ditto.store.execute` while in a transaction scope. Use `transaction.execute` instead ..."). In JavaScript, Swift, and Kotlin the SDKs do not throw; a write through `store.execute` inside a transaction can deadlock, so the same rule applies.
- Start a read-write transaction inside another read-write transaction. Only one read-write transaction runs at a time, so the inner one waits for the outer one forever (deadlock). Flutter has no guard against this.
- Make network calls, show dialogs, wait for user input, or `await` timers inside a transaction. While it waits, this device also stops taking in changes from other devices (see [Concurrency and Duration](#concurrency-and-duration)).
- Store the `Transaction` object or use it after the callback returns; Flutter throws a `DittoException` when it is used outside its scope.
- Read `commitID` inside the transaction to track sync status; it is `null` until the transaction commits. Keep the `QueryResult` of the write (for example, return it from the callback) and read its `commitID` after `transaction()` completes.

```dart
// ❌ BAD: Mixing store.execute into a transaction, nesting, and doing network I/O.
Future<void> badCheckout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'checkout'},
    );
    // Network call inside the transaction: blocks every other read-write transaction.
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
- **Read-only transactions** can run concurrently with each other and with the active read-write transaction. A mutating statement inside a read-only transaction throws (`A mutating DQL query was attempted using a read-only transaction.`).
- **Arrival order (SDK 5.1+):** Small Peer write transactions are processed in arrival order, which prevents a write from being starved indefinitely by competing operations.
- **Long transactions are logged:** After a transaction has run for 10 seconds, Ditto logs a message about it (including the `hint`) every 5 seconds, starting at debug level and escalating to higher levels. The thresholds are configurable with the system parameters `TRANSACTION_DURATION_BEFORE_LOGGING_MS` and `TRANSACTION_TRACE_INTERVAL_MS`.
- **Incoming changes wait too:** **Note (SDK 5.1.0 and 5.2.0)**: in our testing, while a read-write transaction was open (even one that only read) or a large statement ran, changes from other devices did not reach the store or observers until it ended; they arrived right after. A transaction held open for 15 seconds delayed them by 15 seconds, without dropping the connection. With `isReadOnly: true`, changes kept arriving within about 20 ms. In the other direction, a device that received a 30,000-document transaction made its own small writes wait up to about 1.3 seconds. Split migrations and bulk rewrites into statements of about 1,000 documents with an indexed condition (updates then waited at most about 60 ms), and use one transaction only for changes that must appear at once.
- **Closing:** `ditto.close()` in Flutter does not wait for in-flight transactions. Track pending transactions yourself and await them before closing (see [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown)).

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

Atomicity is guaranteed on the device that commits the transaction. In our testing, receiving devices also applied a transaction all at once when their subscriptions (and those of every relay in between) covered all of its documents. That held on SDK 5.1.0 for transactions of up to 10,000 documents, both directly and through a relay, and on SDK 5.1.0 and 5.2.0 for 30,000 documents sent directly. One `INSERT` statement that wrote 30,000 documents also arrived at once, whereas 2,000 documents written one statement at a time arrived in 10 steps on 5.1.0 and in more than 30 steps on 5.2.0. Neither an observer nor a read on the receiving device ever saw part of a transaction. A device that had been offline received the backlog of several transactions as one step, so its observers saw the latest state, not each transaction. The [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) describes two replication limits, both of which our testing confirmed:

- A peer whose subscriptions cover only part of a transaction's documents receives only that part. If it later broadens its subscriptions, the remaining changes arrive only when replication catches up.
- A peer that relays changes can forward only what it has. A device connected only through a relay with narrower subscriptions may receive an incomplete transaction (see [Multi-hop relay](sync-and-subscriptions.md#multi-hop-relay)). For example, Peer 1 changes documents A and B in one transaction, Peer 2 subscribes only to A, and Peer 3 is connected only to Peer 2 but subscribes to both A and B. Peer 3 receives only the change to A, because Peer 2 never had the change to B.
- A device that is also connected to the writer can still show part of a transaction for a while when the relay with narrower subscriptions is its faster path. In our testing with SDK 5.1.0 and 5.2.0, a receiver connected to the writer over a slow link (20 KB/s) and to a fast relay that subscribed only to `orders` showed all 30 orders of a transaction without their `orderItems` for up to about 0.7 seconds in 6 of 12 runs. Writing the items before the orders, in separate statements, did not help (14 of 18 runs on SDK 5.0.3 to 5.2.0). With a relay that subscribed to both collections, with fast links only, or with the slow link alone, no order appeared without its items. A backlog received after a device had been offline (300 orders and 6,000 items, written with or without a transaction) always appeared at once.

Keep documents that are changed together in the same subscription scope (for example, both carry the same `storeId`), give every device that relays a collection the subscriptions for the documents written together with it, and ensure sufficient connectivity with peers that have broader subscription sets; connectivity alone does not prevent a temporary partial view. Make screens tolerate a parent whose children have not arrived yet, for example by storing the expected number of children in the parent and showing it as incomplete until they are all there.

## Transactions on Other Platforms

| Platform | API | Explicit rollback | Notes |
|---|---|---|---|
| Flutter | `ditto.store.transaction(hint:, isReadOnly:, (tx) async {...})` | Return `TransactionCompletionAction.rollback` | Any other return value commits; `store.execute` inside throws |
| JavaScript | `ditto.store.transaction(async (tx) => {...}, { isReadOnly, hint })` | Return `'rollback'` | `store.execute` writes or nested read-write transactions inside can deadlock |
| Swift | `try await ditto.store.transaction(hint:isReadOnly:) { tx in ... }` | Return `.rollback` | Return `.commit` (or a value) to commit |
| Kotlin | `ditto.store.transaction(hint, isReadOnly) { tx -> ... }` | Return `DittoTransaction.Result.Rollback` | The block must return `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback` |
