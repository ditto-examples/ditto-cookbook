// ============================================================================
// Transactions: Anti-Patterns (Non-Flutter Platforms)
// ============================================================================
//
// This example demonstrates common mistakes when using transactions in Ditto,
// which lead to deadlocks, performance issues, and incorrect behavior.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Nested transaction deadlock
// 2. ❌ Using ditto.store instead of tx
// 3. ❌ Long-running transaction
// 4. ❌ Missing hint parameter
// 5. ❌ Ignoring transaction errors
// 6. ❌ Transaction for single operation
// 7. ❌ Concurrent write conflicts
//
// WHY THESE ARE PROBLEMS:
// - Deadlocks freeze application
// - Performance degradation
// - Data inconsistency
// - Wasted resources
//
// SOLUTION: See transaction-good.js for correct patterns
//
// ============================================================================

const { Ditto } = require('@dittolive/ditto')

// ============================================================================
// ANTI-PATTERN 1: Nested Transaction Deadlock
// ============================================================================

/**
 * ❌ BAD: Nested transactions cause deadlock
 */
async function nestedTransactionDeadlock(ditto, orderId, paymentId) {
  console.log('❌ Attempting nested transaction (will deadlock)...')

  await ditto.store.transaction(async (outerTx) => {
    // Outer transaction starts
    console.log('  Outer transaction: Processing order')

    await outerTx.execute(
      `UPDATE orders SET status = :status WHERE _id = :orderId`,
      { orderId, status: 'processing' }
    )

    // ❌ BAD: Nested transaction inside outer transaction
    await ditto.store.transaction(async (innerTx) => {
      console.log('  Inner transaction: Processing payment')

      // 🚨 DEADLOCK!
      // Inner transaction tries to acquire locks
      // Outer transaction already holds locks
      // Both transactions wait for each other
      // Application freezes

      await innerTx.execute(
        `INSERT INTO payments (_id, orderId, status)
         VALUES (:paymentId, :orderId, :status)`,
        { paymentId, orderId, status: 'completed' }
      )
    })

    console.log('  This line never executes (deadlock)')
  })

  // 🚨 PROBLEMS:
  // - Application freezes indefinitely
  // - Must kill process to recover
  // - Data may be in inconsistent state
  // - User experience ruined
}

/**
 * ✅ GOOD: Flatten nested logic into single transaction
 */
async function flattenedTransaction(ditto, orderId, paymentId) {
  await ditto.store.transaction(async (tx) => {
    // All operations in single transaction
    await tx.execute(
      `UPDATE orders SET status = :status WHERE _id = :orderId`,
      { orderId, status: 'processing' }
    )

    await tx.execute(
      `INSERT INTO payments (_id, orderId, status)
       VALUES (:paymentId, :orderId, :status)`,
      { paymentId, orderId, status: 'completed' }
    )

    console.log('✅ All operations in single transaction (no deadlock)')
  })
}

// ============================================================================
// ANTI-PATTERN 2: Using ditto.store Instead of tx
// ============================================================================

/**
 * ❌ BAD: Using ditto.store.execute() inside transaction
 */
async function usingStoreInsteadOfTx(ditto, orderId) {
  console.log('❌ Using ditto.store inside transaction...')

  await ditto.store.transaction(async (tx) => {
    // ❌ BAD: Using ditto.store.execute() instead of tx.execute()
    await ditto.store.execute(
      `UPDATE orders SET status = :status WHERE _id = :orderId`,
      { orderId, status: 'completed' }
    )

    // 🚨 PROBLEMS:
    // - Query NOT part of transaction
    // - No atomicity guarantee
    // - No rollback on error
    // - Transaction essentially useless
    // - Subtle bug that's hard to detect

    console.log('  ❌ Update executed OUTSIDE transaction')
  })

  console.log('❌ Transaction did not include the update!')
}

// ============================================================================
// ANTI-PATTERN 3: Long-Running Transaction
// ============================================================================

/**
 * ❌ BAD: Transaction that takes too long
 */
async function longRunningTransaction(ditto, userId, postContent) {
  console.log('❌ Starting long-running transaction...')

  await ditto.store.transaction(async (tx) => {
    // ❌ BAD: Heavy computation inside transaction
    console.log('  Analyzing content...')
    await analyzeContent(postContent) // Takes 3 seconds!

    // ❌ BAD: External API call inside transaction
    console.log('  Calling external API...')
    await callExternalAPI(postContent) // Takes 2 seconds!

    // ❌ BAD: Complex data processing inside transaction
    console.log('  Processing data...')
    const processedData = await complexProcessing(postContent) // Takes 5 seconds!

    // Finally write to database
    await tx.execute(
      `INSERT INTO posts (_id, userId, content, processedData)
       VALUES (:postId, :userId, :content, :processedData)`,
      {
        postId: `post_${Date.now()}`,
        userId,
        content: postContent,
        processedData
      }
    )

    // 🚨 PROBLEMS:
    // - Transaction holds locks for 10+ seconds
    // - Other transactions blocked
    // - Database performance degraded
    // - User experience slow
    // - Timeout risk
  })

  console.log('❌ Transaction took 10+ seconds (too long!)')
}

async function analyzeContent(content) {
  await new Promise(resolve => setTimeout(resolve, 3000))
  return { sentiment: 'positive' }
}

async function callExternalAPI(content) {
  await new Promise(resolve => setTimeout(resolve, 2000))
  return { spam: false }
}

async function complexProcessing(content) {
  await new Promise(resolve => setTimeout(resolve, 5000))
  return { processed: content.toUpperCase() }
}

/**
 * ✅ GOOD: Do heavy work BEFORE transaction
 */
async function shortTransaction(ditto, userId, postContent) {
  // ✅ GOOD: Heavy work BEFORE transaction
  const analysis = await analyzeContent(postContent)
  const apiResult = await callExternalAPI(postContent)
  const processedData = await complexProcessing(postContent)

  // ✅ Transaction is quick (< 1 second)
  await ditto.store.transaction(async (tx) => {
    await tx.execute(
      `INSERT INTO posts (_id, userId, content, processedData)
       VALUES (:postId, :userId, :content, :processedData)`,
      {
        postId: `post_${Date.now()}`,
        userId,
        content: postContent,
        processedData
      }
    )
  })

  console.log('✅ Transaction completed quickly')
}

// ============================================================================
// ANTI-PATTERN 4: Missing Hint Parameter
// ============================================================================

/**
 * ❌ BAD: Transaction without hint parameter
 */
async function transactionWithoutHint(ditto, userId) {
  console.log('❌ Transaction without hint parameter...')

  // ❌ BAD: No hint parameter
  await ditto.store.transaction(async (tx) => {
    await tx.execute(
      `UPDATE users SET lastActiveAt = :timestamp WHERE _id = :userId`,
      { userId, timestamp: new Date().toISOString() }
    )

    await tx.execute(
      `INSERT INTO activityLog (_id, userId, timestamp)
       VALUES (:logId, :userId, :timestamp)`,
      {
        logId: `log_${Date.now()}`,
        userId,
        timestamp: new Date().toISOString()
      }
    )

    // 🚨 PROBLEM:
    // - Ditto doesn't know which collections are accessed
    // - May acquire unnecessary locks
    // - Performance not optimized
  })

  console.log('  ❌ Transaction without optimization hints')
}

/**
 * ✅ GOOD: Transaction with hint parameter
 */
async function transactionWithHint(ditto, userId) {
  // ✅ Hint parameter tells Ditto which collections accessed
  await ditto.store.transaction(
    async (tx) => {
      await tx.execute(
        `UPDATE users SET lastActiveAt = :timestamp WHERE _id = :userId`,
        { userId, timestamp: new Date().toISOString() }
      )

      await tx.execute(
        `INSERT INTO activityLog (_id, userId, timestamp)
         VALUES (:logId, :userId, :timestamp)`,
        {
          logId: `log_${Date.now()}`,
          userId,
          timestamp: new Date().toISOString()
        }
      )
    },
    ['users', 'activityLog'] // ✅ Hint: Collections accessed
  )

  console.log('✅ Transaction with optimization hints')
}

// ============================================================================
// ANTI-PATTERN 5: Ignoring Transaction Errors
// ============================================================================

/**
 * ❌ BAD: No error handling
 */
async function transactionWithoutErrorHandling(ditto, accountId, amount) {
  console.log('❌ Transaction without error handling...')

  // ❌ BAD: No try-catch
  await ditto.store.transaction(async (tx) => {
    const result = await tx.execute(
      'SELECT balance FROM accounts WHERE _id = :accountId',
      { accountId }
    )

    const balance = result.items[0].value.balance // ❌ Could be undefined!

    if (balance < amount) {
      throw new Error('Insufficient funds')
    }

    await tx.execute(
      `UPDATE accounts APPLY balance PN_INCREMENT BY :change WHERE _id = :accountId`,
      { accountId, change: -amount }
    )

    // 🚨 PROBLEM:
    // - Error thrown but not caught
    // - No feedback to user
    // - Application may crash
    // - No recovery possible
  })

  console.log('  ❌ Error silently propagated')
}

/**
 * ✅ GOOD: Proper error handling
 */
async function transactionWithErrorHandling(ditto, accountId, amount) {
  try {
    await ditto.store.transaction(async (tx) => {
      const result = await tx.execute(
        'SELECT balance FROM accounts WHERE _id = :accountId',
        { accountId }
      )

      if (result.items.length === 0) {
        throw new Error('Account not found')
      }

      const balance = result.items[0].value.balance

      if (balance < amount) {
        throw new Error(`Insufficient funds: ${balance} < ${amount}`)
      }

      await tx.execute(
        `UPDATE accounts APPLY balance PN_INCREMENT BY :change WHERE _id = :accountId`,
        { accountId, change: -amount }
      )
    })

    console.log('✅ Transaction completed')
    return { success: true }

  } catch (error) {
    console.error('❌ Transaction failed:', error.message)
    // ✅ Error caught and handled
    // User gets feedback
    // Application remains stable
    return { success: false, error: error.message }
  }
}

// ============================================================================
// ANTI-PATTERN 6: Transaction for Single Operation
// ============================================================================

/**
 * ❌ BAD: Unnecessary transaction for single query
 */
async function unnecessaryTransaction(ditto, userId, newEmail) {
  console.log('❌ Unnecessary transaction for single operation...')

  // ❌ BAD: Transaction not needed for single UPDATE
  await ditto.store.transaction(async (tx) => {
    await tx.execute(
      `UPDATE users SET email = :email WHERE _id = :userId`,
      { userId, email: newEmail }
    )

    // 🚨 PROBLEM:
    // - Transaction overhead unnecessary
    // - Single operation already atomic
    // - Wastes resources
  })

  console.log('  ❌ Transaction overhead for no benefit')
}

/**
 * ✅ GOOD: Direct query without transaction
 */
async function directQuery(ditto, userId, newEmail) {
  // ✅ Single operation doesn't need transaction
  await ditto.store.execute(
    `UPDATE users SET email = :email WHERE _id = :userId`,
    { userId, email: newEmail }
  )

  console.log('✅ Direct query (no transaction overhead)')
}

// ============================================================================
// ANTI-PATTERN 7: Not Handling Concurrent Write Conflicts
// ============================================================================

/**
 * ❌ BAD: Read-modify-write without handling conflicts
 */
async function readModifyWriteRaceCondition(ditto, postId) {
  console.log('❌ Read-modify-write without conflict handling...')

  await ditto.store.transaction(async (tx) => {
    // Read current like count
    const result = await tx.execute(
      'SELECT likeCount FROM posts WHERE _id = :postId',
      { postId }
    )

    const currentCount = result.items[0].value.likeCount

    // Increment
    const newCount = currentCount + 1

    // Write back
    await tx.execute(
      `UPDATE posts SET likeCount = :newCount WHERE _id = :postId`,
      { postId, newCount }
    )

    // ❌ PROBLEM:
    // - If another transaction runs concurrently
    // - Both read same value (e.g., 10)
    // - Both increment to 11
    // - One increment lost!
    // - Should use PN_INCREMENT instead
  })

  console.log('  ❌ Potential lost update')
}

/**
 * ✅ GOOD: Use PN_INCREMENT for concurrent-safe counter
 */
async function concurrentSafeCounter(ditto, postId) {
  // ✅ PN_INCREMENT is concurrent-safe
  await ditto.store.transaction(async (tx) => {
    await tx.execute(
      `UPDATE posts APPLY likeCount PN_INCREMENT BY 1.0 WHERE _id = :postId`,
      { postId }
    )

    // ✅ BENEFIT:
    // - Multiple concurrent increments merge correctly
    // - No lost updates
    // - CRDT guarantees correctness
  })

  console.log('✅ Concurrent-safe counter increment')
}

// ============================================================================
// ANTI-PATTERN 8: Transaction Timeout Not Handled
// ============================================================================

/**
 * ❌ BAD: Long transaction that may timeout
 */
async function transactionMayTimeout(ditto, batchData) {
  console.log('❌ Transaction that may timeout...')

  await ditto.store.transaction(async (tx) => {
    // ❌ Processing 10,000 items in single transaction
    for (const item of batchData) { // Assume 10,000 items
      await tx.execute(
        `INSERT INTO items (_id, data) VALUES (:id, :data)`,
        { id: item.id, data: item.data }
      )
    }

    // 🚨 PROBLEMS:
    // - Transaction may timeout
    // - Database locks held too long
    // - Other transactions blocked
    // - All work lost if timeout occurs
  })

  console.log('  ❌ Transaction likely to timeout')
}

/**
 * ✅ GOOD: Batch operations in smaller transactions
 */
async function batchInSmallTransactions(ditto, batchData) {
  const BATCH_SIZE = 100

  for (let i = 0; i < batchData.length; i += BATCH_SIZE) {
    const batch = batchData.slice(i, i + BATCH_SIZE)

    // ✅ Small transaction (100 items)
    await ditto.store.transaction(async (tx) => {
      for (const item of batch) {
        await tx.execute(
          `INSERT INTO items (_id, data) VALUES (:id, :data)`,
          { id: item.id, data: item.data }
        )
      }
    })

    console.log(`✅ Processed batch ${i / BATCH_SIZE + 1}`)
  }

  console.log('✅ All batches processed')
}

// ============================================================================
// Export functions
// ============================================================================

module.exports = {
  nestedTransactionDeadlock,
  flattenedTransaction,
  usingStoreInsteadOfTx,
  longRunningTransaction,
  shortTransaction,
  transactionWithoutHint,
  transactionWithHint,
  transactionWithoutErrorHandling,
  transactionWithErrorHandling,
  unnecessaryTransaction,
  directQuery,
  readModifyWriteRaceCondition,
  concurrentSafeCounter,
  transactionMayTimeout,
  batchInSmallTransactions
}
