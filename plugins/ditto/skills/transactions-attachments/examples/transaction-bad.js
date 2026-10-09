// Ditto SDK 5.1 (JavaScript, @dittolive/ditto 5.1.0): Transaction anti-patterns
//
// Guide: § Transaction Rules
//
// Every function below is valid JavaScript. The problems appear at runtime.
// Unlike Flutter, the JavaScript SDK does not throw for the first two
// mistakes: both can deadlock, so never make them.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ ditto.store.execute write inside a transaction (can deadlock)
// 2. ❌ Nested read-write transaction (deadlock)
// 3. ❌ Network calls or timers inside a transaction (blocks all writes)
// 4. ❌ Swallowing an error and committing a half-done change
// 5. ❌ Returning a value other than 'rollback' to signal failure (commits)
// 6. ❌ Mutating inside a read-only transaction (throws)
// 7. ❌ Wrapping a single statement in a transaction (adds nothing)
//
// See transaction-good.js for the correct patterns.

/** @typedef {import('@dittolive/ditto').Ditto} Ditto */

// ============================================================================
// ANTI-PATTERN 1: ditto.store.execute inside a transaction
// ============================================================================

/**
 * ❌ BAD: The type definitions warn that calling ditto.store.execute inside
 * a transaction may lead to a deadlock. The SDK does not throw an error.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 */
export async function storeExecuteInsideTransaction(ditto, orderId) {
  await ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'checkout',
    })
    await ditto.store.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      { id: orderId, status: 'paid' },
    )
  })
}

// ✅ Fix: use tx.execute for every statement inside the scope.

// ============================================================================
// ANTI-PATTERN 2: Nested read-write transaction
// ============================================================================

/**
 * ❌ BAD: Only one read-write transaction runs at a time. The inner one
 * waits for the outer one forever.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 */
export async function nestedTransaction(ditto, orderId) {
  await ditto.store.transaction(async (outer) => {
    await outer.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'paid',
    })
    await recordPaymentDate(ditto, orderId) // Hidden nesting via a helper.
  })
}

/**
 * @param {Ditto} ditto
 * @param {string} orderId
 */
function recordPaymentDate(ditto, orderId) {
  return ditto.store.transaction(async (inner) => {
    await inner.execute('UPDATE orders SET paidAt = :paidAt WHERE _id = :id', {
      id: orderId,
      paidAt: new Date().toISOString(),
    })
  })
}

// ✅ Fix: pass the outer transaction to helpers, or run the transactions one
// after the other.

// ============================================================================
// ANTI-PATTERN 3: Network calls or timers inside a transaction
// ============================================================================

/**
 * ❌ BAD: Every other read-write transaction waits while this one waits for
 * the network. After 10 seconds Ditto logs messages about the long-running
 * transaction.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 * @param {() => Promise<void>} chargeCard
 */
export async function networkInsideTransaction(ditto, orderId, chargeCard) {
  await ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'checkout',
    })
    await chargeCard() // Network I/O inside the transaction.
    await new Promise((resolve) => setTimeout(resolve, 2000)) // Timer inside.
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'paid',
    })
  })
}

// ✅ Fix: call chargeCard() first, then record the result in one short
// transaction with a hint.

// ============================================================================
// ANTI-PATTERN 4: Swallowing an error
// ============================================================================

/**
 * ❌ BAD: A caught error does not roll back. The invoice is committed even
 * though the order update failed.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 * @param {string} invoiceId
 */
export async function swallowedError(ditto, orderId, invoiceId) {
  await ditto.store.transaction(async (tx) => {
    await tx.execute('INSERT INTO invoices DOCUMENTS (:invoice)', {
      invoice: { _id: invoiceId, orderId },
    })
    try {
      await tx.execute(
        'UPDATE orders SET invoiceId = :invoiceId WHERE _id = :id',
        { id: orderId, invoiceId },
      )
    } catch {
      // Ignored: the transaction continues and commits the invoice alone.
    }
  })
}

// ✅ Fix: rethrow, or return 'rollback'.

// ============================================================================
// ANTI-PATTERN 5: Returning false to "cancel"
// ============================================================================

/**
 * ❌ BAD: Only the string 'rollback' rolls back. Any other return value,
 * including false or null, commits the changes made so far.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 * @returns {Promise<boolean>}
 */
export async function falseStillCommits(ditto, orderId) {
  return ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'shipping',
    })
    const result = await tx.execute(
      'SELECT * FROM orders WHERE _id = :id AND status = :status',
      { id: orderId, status: 'shipping' },
    )
    if (result.items.length === 0) {
      return false // Commits! Use: return 'rollback'
    }
    return true
  })
}

// ============================================================================
// ANTI-PATTERN 6: Mutating inside a read-only transaction
// ============================================================================

/**
 * ❌ BAD: Throws DittoError 'store/transaction-read-only'
 * ("A mutating DQL query was attempted using a read-only transaction.").
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 */
export async function mutateInReadOnly(ditto, orderId) {
  await ditto.store.transaction(
    async (tx) => {
      await tx.execute('UPDATE orders SET viewedAt = :now WHERE _id = :id', {
        id: orderId,
        now: new Date().toISOString(),
      })
    },
    { isReadOnly: true },
  )
}

// ============================================================================
// ANTI-PATTERN 7: A transaction around a single statement
// ============================================================================

/**
 * ❌ BAD (unnecessary): A single UPDATE is already atomic. Wrapping it in a
 * transaction adds nothing.
 *
 * @param {Ditto} ditto
 * @param {string} orderId
 */
export async function singleStatementTransaction(ditto, orderId) {
  await ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'open',
    })
  })
}

// ✅ Fix: call ditto.store.execute(query, args) directly.
