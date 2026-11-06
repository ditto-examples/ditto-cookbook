// Ditto SDK 5.2 (JavaScript, @dittolive/ditto 5.2.0): Transaction patterns
//
// ditto.store.transaction(async (tx) => { ... }, { hint, isReadOnly })
// - Run every statement with tx.execute(query, args); never ditto.store.execute.
// - Return 'commit' or 'rollback' to choose explicitly; any other value
//   (including undefined) commits and is what transaction() resolves to.
// - Throwing rolls back and rejects transaction() with the same error. An
//   error that the callback catches does NOT roll back.
// - Await every tx.execute; a statement that is not awaited is not applied.
// - close() waits for open transactions in JavaScript, so no tracking is
//   needed for shutdown. A Node.js script that keeps neither sync nor a timer
//   running must keep the event loop alive while it awaits a transaction.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Atomic multi-document change that uses only tx.execute
// 2. ✅ Explicit rollback with 'rollback', and a typed return value
// 3. ✅ Read-only transaction for a consistent snapshot
// 4. ✅ I/O before the transaction, short transaction afterwards
// 5. ✅ Handling a failed statement deliberately
// 6. ✅ Keeping the event loop alive in a Node.js script
// 7. ✅ Reading the commit ID after the transaction has committed
//
// Guide: § Transactions in JavaScript, § Using store.transaction, § Transaction Rules

import { DittoError } from '@dittolive/ditto';

// ISO-8601 UTC timestamp with exactly millisecond precision.
export const utcTimestamp = (time = new Date()) => time.toISOString();

// PATTERN 1: Atomic multi-document change.

// ✅ GOOD: Close an order and create its invoice atomically. Throwing inside
// the callback rolls back every change and rejects transaction().
export async function closeOrderWithInvoice(ditto, orderId, invoiceId) {
  await ditto.store.transaction(
    async (tx) => {
      const result = await tx.execute('SELECT * FROM orders WHERE _id = :id', { id: orderId });
      if (result.items.length === 0) throw new Error(`Order ${orderId} not found`); // Throwing rolls back.
      const order = result.items[0].value;
      await tx.execute('INSERT INTO invoices DOCUMENTS (:invoice)', {
        invoice: { _id: invoiceId, orderId, total: order.total, createdAt: utcTimestamp() },
      });
      await tx.execute('UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id', {
        id: orderId,
        status: 'closed',
        invoiceId,
      });
    },
    { hint: 'closeOrderWithInvoice' }, // Appears in logs; useful for debugging.
  );
}

// PATTERN 2: Explicit rollback without throwing.

// ✅ GOOD: Resolves to true when the order was shipped. Returning 'rollback'
// discards all changes made in the callback.
export async function shipOrder(ditto, orderId) {
  const action = await ditto.store.transaction(
    async (tx) => {
      const result = await tx.execute('SELECT * FROM orders WHERE _id = :id AND status = :status', {
        id: orderId,
        status: 'paid',
      });
      if (result.items.length === 0) return 'rollback'; // Nothing to ship.
      await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id: orderId, status: 'shipped' });
      return 'commit';
    },
    { hint: 'shipOrder' },
  );
  return action === 'commit';
}

// PATTERN 3: Read-only transaction for a consistent snapshot.

// ✅ GOOD: Both counts are read from the same snapshot. Read-only transactions
// run concurrently; a mutating statement in one fails with store/transaction-read-only.
export function orderCounts(ditto) {
  return ditto.store.transaction(
    async (tx) => {
      const open = await tx.execute('SELECT COUNT(*) AS n FROM orders WHERE status = :status', { status: 'open' });
      const closed = await tx.execute('SELECT COUNT(*) AS n FROM orders WHERE status = :status', { status: 'closed' });
      return { open: open.items[0].value.n, closed: closed.items[0].value.n };
    },
    { hint: 'orderCounts', isReadOnly: true },
  );
}

// PATTERN 4: I/O first, then one short transaction.

// ✅ GOOD: The payment call happens before the transaction starts, so no other
// read-write transaction waits for the network.
export async function checkout(ditto, orderId, chargeCard) {
  await chargeCard(); // Outside the transaction.
  await ditto.store.transaction(
    async (tx) => {
      await tx.execute('UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id', {
        id: orderId,
        status: 'paid',
        paidAt: utcTimestamp(),
      });
      await tx.execute('INSERT INTO payments DOCUMENTS (:payment)', { payment: { _id: `payment-${orderId}`, orderId } });
    },
    { hint: 'recordPayment' },
  );
}

// PATTERN 5: Handling a failed statement deliberately.

// ✅ GOOD: A caught error does NOT roll back the transaction, so decide what
// happens next. The audit entry is optional (commit without it); the stock
// update is required (roll back if it fails).
export async function reserveItem(ditto, itemId, auditId) {
  const action = await ditto.store.transaction(
    async (tx) => {
      try {
        await tx.execute('UPDATE items SET reserved = true WHERE _id = :id', { id: itemId });
      } catch (error) {
        if (!(error instanceof DittoError)) throw error;
        return 'rollback'; // Required step failed: discard everything.
      }
      try {
        await tx.execute('INSERT INTO audit DOCUMENTS (:entry)', {
          entry: { _id: auditId, itemId, action: 'reserve', at: utcTimestamp() },
        });
      } catch (error) {
        console.warn(`audit entry skipped: ${error.message}`); // Optional step: keep the reservation.
      }
      return 'commit';
    },
    { hint: 'reserveItem' },
  );
  return action === 'commit';
}

// PATTERN 6: Node.js scripts.

// ✅ GOOD: A seed or migration script that starts no sync keeps the event loop
// alive while it awaits the transaction; otherwise Node.js ends the process
// with a panic before the transaction completes.
export async function runMigration(ditto, migrate) {
  const keepAlive = setInterval(() => {}, 1000);
  try {
    return await ditto.store.transaction((tx) => migrate(tx), { hint: 'migration' });
  } finally {
    clearInterval(keepAlive);
  }
}

// PATTERN 7: The commit ID.

// ✅ GOOD: Inside the transaction, results have no commit ID. Return the
// result and read commitID (a bigint) after transaction() has resolved.
export async function renameProduct(ditto, productId, name) {
  const result = await ditto.store.transaction(
    (tx) => tx.execute('UPDATE products SET name = :name WHERE _id = :id', { id: productId, name }),
    { hint: 'renameProduct' },
  );
  return result.commitID;
}
