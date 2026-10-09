// Ditto SDK 5.1 (JavaScript, @dittolive/ditto 5.1.0): Transaction patterns
//
// Guide: .claude/guides/best-practices/ditto.md#transactions-on-other-platforms
//
// API (from the 5.1.0 type definitions):
//   ditto.store.transaction(async (tx) => { ... }, { isReadOnly, hint })
//   - tx.execute(query, args) inside the scope; never ditto.store.execute
//   - return 'commit' or 'rollback' to choose explicitly; any other value
//     (including undefined) commits and is returned by transaction()
//   - throwing rolls back and rethrows the error to the caller
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Atomic multi-document change that uses only tx.execute
// 2. ✅ Explicit rollback with 'rollback'
// 3. ✅ Read-only transaction returning a typed value
// 4. ✅ I/O before the transaction, short transaction afterwards
// 5. ✅ Handling a failed statement deliberately
// 6. ✅ Awaiting in-flight transactions before ditto.close()

import { DittoError } from '@dittolive/ditto'

/** @typedef {import('@dittolive/ditto').Ditto} Ditto */
/** @typedef {import('@dittolive/ditto').Transaction} Transaction */

// ============================================================================
// PATTERN 1: Atomic multi-document change
// ============================================================================

/**
 * ✅ GOOD: Close an order and create its invoice atomically.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 * @param {string} invoiceId
 */
export async function closeOrderWithInvoice(ditto, orderId, invoiceId) {
  await ditto.store.transaction(
    async (tx) => {
      const result = await tx.execute('SELECT * FROM orders WHERE _id = :id', {
        id: orderId,
      })
      if (result.items.length === 0) {
        throw new Error(`Order ${orderId} not found`) // Throwing rolls back.
      }
      const order = result.items[0].value

      await tx.execute('INSERT INTO invoices DOCUMENTS (:invoice)', {
        invoice: {
          _id: invoiceId,
          orderId,
          total: order.total,
          createdAt: new Date().toISOString(), // UTC with a Z suffix.
        },
      })
      await tx.execute(
        'UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id',
        { id: orderId, status: 'closed', invoiceId },
      )
    },
    { hint: 'closeOrderWithInvoice' },
  )
}

// ============================================================================
// PATTERN 2: Explicit rollback without throwing
// ============================================================================

/**
 * ✅ GOOD: Returns true when the order was shipped.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 * @returns {Promise<boolean>}
 */
export async function shipOrder(ditto, orderId) {
  const action = await ditto.store.transaction(
    async (tx) => {
      const result = await tx.execute(
        'SELECT * FROM orders WHERE _id = :id AND status = :status',
        { id: orderId, status: 'paid' },
      )
      if (result.items.length === 0) {
        return 'rollback' // Nothing to ship; no changes are applied.
      }
      await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
        id: orderId,
        status: 'shipped',
      })
      return 'commit'
    },
    { hint: 'shipOrder' },
  )
  return action === 'commit'
}

// ============================================================================
// PATTERN 3: Read-only transaction returning a value
// ============================================================================

/**
 * ✅ GOOD: Both counts come from one consistent snapshot. Read-only
 * transactions can run concurrently; a mutating statement inside one throws
 * a DittoError with code 'store/transaction-read-only'.
 *
 * @param {Ditto} ditto
 * @returns {Promise<{ open: number, closed: number }>}
 */
export function orderCounts(ditto) {
  return ditto.store.transaction(
    async (tx) => {
      const open = await tx.execute(
        'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
        { status: 'open' },
      )
      const closed = await tx.execute(
        'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
        { status: 'closed' },
      )
      return { open: open.items[0].value.n, closed: closed.items[0].value.n }
    },
    { isReadOnly: true, hint: 'orderCounts' },
  )
}

// ============================================================================
// PATTERN 4: I/O first, then one short transaction
// ============================================================================

/**
 * ✅ GOOD: Only one read-write transaction runs at a time, so the network
 * call happens before the transaction starts.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 * @param {() => Promise<void>} chargeCard
 */
export async function checkout(ditto, orderId, chargeCard) {
  await chargeCard() // Outside the transaction.

  await ditto.store.transaction(
    async (tx) => {
      await tx.execute(
        'UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id',
        { id: orderId, status: 'paid', paidAt: new Date().toISOString() },
      )
      await tx.execute('INSERT INTO payments DOCUMENTS (:payment)', {
        payment: { _id: `payment-${orderId}`, orderId },
      })
    },
    { hint: 'recordPayment' },
  )
}

// ============================================================================
// PATTERN 5: Handling a failed statement deliberately
// ============================================================================

/**
 * ✅ GOOD: A caught error does NOT roll back the transaction. Decide what
 * happens next: here the reservation is required, the audit entry optional.
 *
 * @param {Ditto} ditto
 * @param {string} itemId
 * @param {string} auditId
 * @returns {Promise<boolean>}
 */
export async function reserveItem(ditto, itemId, auditId) {
  const action = await ditto.store.transaction(
    async (tx) => {
      try {
        await tx.execute('UPDATE items SET reserved = true WHERE _id = :id', {
          id: itemId,
        })
      } catch (error) {
        console.warn('Reservation failed:', describe(error))
        return 'rollback' // Required step failed.
      }

      try {
        await tx.execute('INSERT INTO auditLog DOCUMENTS (:entry)', {
          entry: { _id: auditId, itemId, action: 'reserve' },
        })
      } catch (error) {
        console.warn('Audit entry skipped:', describe(error)) // Optional step.
      }
      return 'commit'
    },
    { hint: 'reserveItem' },
  )
  return action === 'commit'
}

/**
 * @param {unknown} error
 * @returns {string}
 */
function describe(error) {
  if (error instanceof DittoError) return `${error.code}: ${error.message}`
  return String(error)
}

// ============================================================================
// PATTERN 6: Await in-flight transactions before closing
// ============================================================================

/**
 * ✅ GOOD: Route transactions through a tracker so shutdown can wait for
 * them before calling ditto.close().
 */
export class TransactionTracker {
  /** @type {Set<Promise<unknown>>} */
  #pending = new Set()

  /**
   * @template T
   * @param {Ditto} ditto
   * @param {string} hint
   * @param {(tx: Transaction) => Promise<T>} work
   * @returns {Promise<T>}
   */
  run(ditto, hint, work) {
    const promise = ditto.store.transaction(work, { hint })
    this.#pending.add(promise)
    return promise.finally(() => this.#pending.delete(promise))
  }

  /** @param {Ditto} ditto */
  async closeWhenIdle(ditto) {
    // Errors are reported to the callers of run(); ignore them here.
    await Promise.allSettled([...this.#pending])
    await ditto.close()
  }
}
