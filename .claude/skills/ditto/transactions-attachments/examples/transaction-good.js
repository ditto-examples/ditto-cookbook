// ============================================================================
// Transactions: Correct Usage (Non-Flutter Platforms)
// ============================================================================
//
// This example demonstrates proper transaction usage in Ditto SDK for
// non-Flutter platforms (JavaScript, Swift, Kotlin).
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Basic transaction usage
// 2. ✅ Read-only transactions
// 3. ✅ Transaction with hint parameter
// 4. ✅ Proper error handling
// 5. ✅ Atomic multi-step operations
// 6. ✅ Transaction best practices
//
// CRITICAL: Use `tx` parameter for all queries inside transaction!
//
// TRANSACTION RULES:
// - Always use tx.execute(), NOT ditto.store.execute()
// - Keep transactions short (< 1 second)
// - Avoid nested transactions (deadlock risk)
// - Use hint parameter for collections
// - Read-only when possible (better performance)
//
// PLATFORM SUPPORT:
// - JavaScript: ✅ Supported
// - Swift: ✅ Supported
// - Kotlin: ✅ Supported
// - Flutter: ❌ NOT supported (use sequential operations)
//
// ============================================================================

const { Ditto } = require('@dittolive/ditto')

// ============================================================================
// PATTERN 1: Basic Transaction Usage
// ============================================================================

/**
 * ✅ GOOD: Basic transaction for multi-step operation
 */
async function processOrderWithTransaction(ditto, orderId, customerId, productId, quantity) {
  console.log('📦 Processing order with transaction:', orderId)

  await ditto.store.transaction(async (tx) => {
    // Step 1: Check inventory (using tx, not ditto.store)
    const inventoryResult = await tx.execute(
      'SELECT stockQuantity FROM products WHERE _id = :productId',
      { productId }
    )

    if (inventoryResult.items.length === 0) {
      throw new Error('Product not found')
    }

    const currentStock = inventoryResult.items[0].value.stockQuantity

    if (currentStock < quantity) {
      throw new Error(`Insufficient stock: ${currentStock} < ${quantity}`)
    }

    // Step 2: Deduct inventory
    await tx.execute(
      `UPDATE products
       APPLY stockQuantity PN_INCREMENT BY :change
       WHERE _id = :productId`,
      { productId, change: -quantity }
    )
    console.log('  ✅ Inventory deducted')

    // Step 3: Create order
    await tx.execute(
      `INSERT INTO orders (
        _id, customerId, productId, quantity, status, createdAt
      )
      VALUES (:orderId, :customerId, :productId, :quantity, :status, :createdAt)`,
      {
        orderId,
        customerId,
        productId,
        quantity,
        status: 'pending',
        createdAt: new Date().toISOString()
      }
    )
    console.log('  ✅ Order created')

    // ✅ BENEFIT: All steps atomic
    // If any step fails, ALL changes rolled back automatically
  })

  console.log('✅ Order processed atomically')
}

// ============================================================================
// PATTERN 2: Read-Only Transactions
// ============================================================================

/**
 * ✅ GOOD: Read-only transaction for consistent multi-query reads
 */
async function getOrderDetailsWithTransaction(ditto, orderId) {
  console.log('📊 Fetching order details (read-only transaction):', orderId)

  const orderDetails = await ditto.store.transaction(async (tx) => {
    // Query 1: Get order
    const orderResult = await tx.execute(
      'SELECT * FROM orders WHERE _id = :orderId',
      { orderId }
    )

    if (orderResult.items.length === 0) {
      throw new Error('Order not found')
    }

    const order = orderResult.items[0].value

    // Query 2: Get customer
    const customerResult = await tx.execute(
      'SELECT * FROM customers WHERE _id = :customerId',
      { customerId: order.customerId }
    )

    const customer = customerResult.items[0]?.value

    // Query 3: Get product
    const productResult = await tx.execute(
      'SELECT * FROM products WHERE _id = :productId',
      { productId: order.productId }
    )

    const product = productResult.items[0]?.value

    // ✅ BENEFIT: All reads see consistent snapshot
    // No other transaction can modify data between queries
    return {
      order,
      customer,
      product
    }
  })

  console.log('✅ Order details fetched atomically')
  return orderDetails
}

// ============================================================================
// PATTERN 3: Transaction with Hint Parameter
// ============================================================================

/**
 * ✅ GOOD: Use hint parameter for better performance
 */
async function transferFundsWithHint(ditto, fromAccountId, toAccountId, amount) {
  console.log('💰 Transferring funds:', { fromAccountId, toAccountId, amount })

  // ✅ Hint tells Ditto which collections will be accessed
  await ditto.store.transaction(
    async (tx) => {
      // Debit source account
      await tx.execute(
        `UPDATE accounts
         APPLY balance PN_INCREMENT BY :change
         WHERE _id = :accountId`,
        { accountId: fromAccountId, change: -amount }
      )

      // Credit destination account
      await tx.execute(
        `UPDATE accounts
         APPLY balance PN_INCREMENT BY :change
         WHERE _id = :accountId`,
        { accountId: toAccountId, change: amount }
      )

      console.log('  ✅ Funds transferred atomically')
    },
    ['accounts'] // ✅ Hint: Only 'accounts' collection accessed
  )

  console.log('✅ Transfer completed')
}

// ============================================================================
// PATTERN 4: Proper Error Handling
// ============================================================================

/**
 * ✅ GOOD: Transaction with comprehensive error handling
 */
async function processPaymentWithErrorHandling(ditto, paymentId, accountId, amount) {
  console.log('💳 Processing payment:', paymentId)

  try {
    await ditto.store.transaction(async (tx) => {
      // Check account balance
      const accountResult = await tx.execute(
        'SELECT balance FROM accounts WHERE _id = :accountId',
        { accountId }
      )

      if (accountResult.items.length === 0) {
        throw new Error('Account not found')
      }

      const balance = accountResult.items[0].value.balance

      if (balance < amount) {
        throw new Error(`Insufficient funds: ${balance} < ${amount}`)
      }

      // Deduct payment
      await tx.execute(
        `UPDATE accounts
         APPLY balance PN_INCREMENT BY :change
         WHERE _id = :accountId`,
        { accountId, change: -amount }
      )

      // Create payment record
      await tx.execute(
        `INSERT INTO payments (
          _id, accountId, amount, status, createdAt
        )
        VALUES (:paymentId, :accountId, :amount, :status, :createdAt)`,
        {
          paymentId,
          accountId,
          amount,
          status: 'completed',
          createdAt: new Date().toISOString()
        }
      )

      console.log('  ✅ Payment processed')
    }, ['accounts', 'payments'])

    console.log('✅ Payment transaction completed')
    return { success: true, paymentId }

  } catch (error) {
    console.error('❌ Payment transaction failed:', error.message)

    // ✅ BENEFIT: Automatic rollback on error
    // Account balance not deducted
    // Payment record not created
    // Database remains consistent

    return { success: false, error: error.message }
  }
}

// ============================================================================
// PATTERN 5: Atomic Counter Update
// ============================================================================

/**
 * ✅ GOOD: Atomic counter increment with transaction
 */
async function incrementViewCount(ditto, postId) {
  await ditto.store.transaction(
    async (tx) => {
      // Read current count
      const result = await tx.execute(
        'SELECT viewCount FROM posts WHERE _id = :postId',
        { postId }
      )

      const currentCount = result.items[0]?.value.viewCount || 0

      // Increment
      await tx.execute(
        `UPDATE posts
         SET viewCount = :newCount
         WHERE _id = :postId`,
        { postId, newCount: currentCount + 1 }
      )

      console.log(`  ✅ View count: ${currentCount} → ${currentCount + 1}`)
    },
    ['posts']
  )
}

// ============================================================================
// PATTERN 6: Multiple Collection Updates
// ============================================================================

/**
 * ✅ GOOD: Transaction across multiple collections
 */
async function completeOrderWithMultipleUpdates(ditto, orderId) {
  console.log('📦 Completing order:', orderId)

  await ditto.store.transaction(
    async (tx) => {
      // Update order status
      await tx.execute(
        `UPDATE orders
         SET status = :status, completedAt = :timestamp
         WHERE _id = :orderId`,
        {
          orderId,
          status: 'completed',
          timestamp: new Date().toISOString()
        }
      )

      // Create notification
      await tx.execute(
        `INSERT INTO notifications (
          _id, userId, type, orderId, createdAt
        )
        VALUES (:notificationId, :userId, :type, :orderId, :createdAt)`,
        {
          notificationId: `notif_${Date.now()}`,
          userId: 'user_123', // From order
          type: 'order_completed',
          orderId,
          createdAt: new Date().toISOString()
        }
      )

      // Log event
      await tx.execute(
        `INSERT INTO events (
          _id, eventType, orderId, timestamp
        )
        VALUES (:eventId, :eventType, :orderId, :timestamp)`,
        {
          eventId: `event_${Date.now()}`,
          eventType: 'order_completed',
          orderId,
          timestamp: new Date().toISOString()
        }
      )

      console.log('  ✅ All updates completed atomically')
    },
    ['orders', 'notifications', 'events']
  )

  console.log('✅ Order completion transaction finished')
}

// ============================================================================
// PATTERN 7: Transaction with Conditional Logic
// ============================================================================

/**
 * ✅ GOOD: Complex business logic in transaction
 */
async function applyDiscountIfEligible(ditto, orderId, discountCode) {
  console.log('🎫 Applying discount:', { orderId, discountCode })

  const result = await ditto.store.transaction(async (tx) => {
    // Get order
    const orderResult = await tx.execute(
      'SELECT * FROM orders WHERE _id = :orderId',
      { orderId }
    )

    if (orderResult.items.length === 0) {
      throw new Error('Order not found')
    }

    const order = orderResult.items[0].value

    // Get discount code
    const discountResult = await tx.execute(
      'SELECT * FROM discountCodes WHERE code = :code',
      { code: discountCode }
    )

    if (discountResult.items.length === 0) {
      throw new Error('Invalid discount code')
    }

    const discount = discountResult.items[0].value

    // Check if code is active
    if (!discount.isActive) {
      throw new Error('Discount code expired')
    }

    // Check usage limit
    if (discount.usageCount >= discount.maxUsage) {
      throw new Error('Discount code usage limit reached')
    }

    // Apply discount
    const discountAmount = order.total * discount.percentage
    const newTotal = order.total - discountAmount

    await tx.execute(
      `UPDATE orders
       SET total = :newTotal,
           discountCode = :code,
           discountAmount = :discountAmount
       WHERE _id = :orderId`,
      { orderId, newTotal, code: discountCode, discountAmount }
    )

    // Increment usage count
    await tx.execute(
      `UPDATE discountCodes
       APPLY usageCount PN_INCREMENT BY 1.0
       WHERE code = :code`,
      { code: discountCode }
    )

    console.log(`  ✅ Discount applied: $${discountAmount.toFixed(2)}`)
    return { success: true, discountAmount, newTotal }
  }, ['orders', 'discountCodes'])

  return result
}

// ============================================================================
// PATTERN 8: Short Transaction Duration
// ============================================================================

/**
 * ✅ GOOD: Keep transaction short
 */
async function updateUserPreferencesShort(ditto, userId, preferences) {
  // ✅ Transaction completes quickly (< 1 second)
  await ditto.store.transaction(
    async (tx) => {
      await tx.execute(
        `UPDATE users
         SET preferences = :preferences,
             updatedAt = :timestamp
         WHERE _id = :userId`,
        {
          userId,
          preferences,
          timestamp: new Date().toISOString()
        }
      )
    },
    ['users']
  )
}

/**
 * ❌ BAD: Long transaction (avoid this)
 */
async function updateUserPreferencesLongBad(ditto, userId, preferences) {
  await ditto.store.transaction(async (tx) => {
    // ❌ BAD: Heavy computation inside transaction
    const computedPreferences = await heavyComputation(preferences) // Takes 5 seconds!

    await tx.execute(
      `UPDATE users
       SET preferences = :preferences
       WHERE _id = :userId`,
      { userId, preferences: computedPreferences }
    )
  })

  // 🚨 PROBLEM: Transaction holds locks for 5+ seconds
  // Other transactions blocked
  // Performance degradation
}

async function heavyComputation(data) {
  // Simulated heavy work
  await new Promise(resolve => setTimeout(resolve, 5000))
  return data
}

// ============================================================================
// Best Practices Summary
// ============================================================================

function printTransactionBestPractices() {
  console.log('✅ Transaction Best Practices:')
  console.log('')
  console.log('DO:')
  console.log('  ✓ Use tx.execute() inside transaction (not ditto.store.execute())')
  console.log('  ✓ Keep transactions short (< 1 second)')
  console.log('  ✓ Use hint parameter for collections')
  console.log('  ✓ Use read-only transactions when possible')
  console.log('  ✓ Handle errors with try-catch')
  console.log('  ✓ Return values from transaction function')
  console.log('')
  console.log('DON\'T:')
  console.log('  ✗ Nest transactions (deadlock risk)')
  console.log('  ✗ Use ditto.store.execute() inside transaction')
  console.log('  ✗ Run long operations inside transaction')
  console.log('  ✗ Forget hint parameter for multi-collection access')
  console.log('  ✗ Ignore transaction errors')
}

// ============================================================================
// Export functions
// ============================================================================

module.exports = {
  processOrderWithTransaction,
  getOrderDetailsWithTransaction,
  transferFundsWithHint,
  processPaymentWithErrorHandling,
  incrementViewCount,
  completeOrderWithMultipleUpdates,
  applyDiscountIfEligible,
  updateUserPreferencesShort,
  printTransactionBestPractices
}
