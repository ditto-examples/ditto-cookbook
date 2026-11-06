// Ditto SDK 5.2 (JavaScript, @dittolive/ditto 5.2.0): Transaction anti-patterns
//
// Every function below is valid JavaScript. The problems appear at runtime,
// and unlike Flutter, the JavaScript SDK does not throw for the first two:
// they wait forever, and because close() waits for open transactions, a stuck
// transaction also keeps close() from completing.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ ditto.store.execute write inside a transaction (never completes)
// 2. ❌ Nested read-write transaction (waits for the outer one forever)
// 3. ❌ Network calls or timers inside a transaction (blocks all writes)
// 4. ❌ Using the transaction after the callback has returned
// 5. ❌ A tx.execute that is not awaited (not applied)
// 6. ❌ Swallowing an error and committing a half-done change
// 7. ❌ Returning a value other than 'rollback' to signal failure (commits)
// 8. ❌ Mutating inside a read-only transaction (rejects)
// 9. ❌ Wrapping a single statement in a transaction (adds nothing)
// See transaction-good.js for the correct patterns.
//
// Guide: § Transactions in JavaScript, § Transaction Rules, § Behavior Specific to the JavaScript SDK

// ❌ BAD: A write through ditto.store.execute inside a read-write transaction
// never completes and raises no exception. A read through it completes but
// does not see the transaction's writes.
export async function storeExecuteInsideTransaction(ditto, orderId) {
  await ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'paid' });
    await ditto.store.execute('UPDATE orders SET paidAt = :paidAt WHERE _id = :id', {
      id: orderId,
      paidAt: new Date().toISOString(),
    });
  });
}
// ✅ Fix: use tx.execute for every statement inside the callback.

// ❌ BAD: A read-write transaction started inside another one waits until the
// outer one ends. Awaiting it inside the outer callback never ends.
export async function nestedTransaction(ditto, orderId) {
  await ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'paid' });
    await recordPaymentDate(ditto, orderId); // Starts its own transaction.
  });
}

function recordPaymentDate(ditto, orderId) {
  return ditto.store.transaction((tx) =>
    tx.execute('UPDATE orders SET paidAt = :paidAt WHERE _id = :id', { id: orderId, paidAt: new Date().toISOString() }),
  );
}
// ✅ Fix: pass the outer tx to helpers instead of starting a new transaction.

// ❌ BAD: While this transaction waits for the network, every other read-write
// transaction (and every plain write) waits, and changes from other devices are
// held back. After 20 seconds Ditto logs messages about the long transaction.
export async function networkInsideTransaction(ditto, orderId, chargeCard) {
  await ditto.store.transaction(async (tx) => {
    await chargeCard();
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'paid' });
  });
}
// ✅ Fix: call chargeCard() first, then record the result in one short transaction.

// ❌ BAD: A transaction is only valid inside its callback. Using it later fails
// with "No active write transaction found".
export async function useTransactionLater(ditto, orderId) {
  let saved;
  await ditto.store.transaction(async (tx) => {
    saved = tx; // Stored outside the callback.
  });
  await saved.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'paid' });
}

// ❌ BAD: forEach(async ...) does not await the statements, so the callback
// returns before they run. The changes are not applied: each statement fails
// as an unhandled rejection, and the commit itself can fail with "The active
// write transaction is currently in use". Await each statement, or await
// Promise.all(ids.map(...)).
export async function notAwaited(ditto, ids) {
  await ditto.store.transaction(async (tx) => {
    ids.forEach(async (id) => {
      await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id, status: 'closed' });
    });
  });
}

// ❌ BAD: The failed insert is caught and ignored. The transaction continues
// and commits the status change without the invoice.
export async function swallowedError(ditto, orderId, invoice) {
  await ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'closed' });
    try {
      await tx.execute('INSERT INTO invoices DOCUMENTS (:invoice)', { invoice });
    } catch {
      // Ignored: the transaction commits the status change alone.
    }
  });
}
// ✅ Fix: rethrow, or return 'rollback'.

// ❌ BAD: Returning false does not cancel anything; any value other than
// 'rollback' commits.
export async function falseStillCommits(ditto, orderId) {
  return ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'shipped' });
    const check = await tx.execute('SELECT * FROM payments WHERE orderId = :id', { id: orderId });
    if (check.items.length === 0) return false; // Still commits the update above.
    return true;
  });
}

// ❌ BAD: A write in a read-only transaction rejects with a DittoError
// (store/transaction-read-only).
export async function mutateInReadOnly(ditto, orderId) {
  await ditto.store.transaction(
    (tx) => tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'open' }),
    { isReadOnly: true },
  );
}

// ❌ BAD: A transaction around a single statement adds nothing: a single
// statement is already atomic.
export async function singleStatementTransaction(ditto, orderId) {
  await ditto.store.transaction((tx) =>
    tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'open' }),
  );
}
// ✅ Fix: call ditto.store.execute(query, args) directly.
