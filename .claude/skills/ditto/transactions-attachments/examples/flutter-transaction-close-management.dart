// SDK Version: All
// Platform: Flutter
// Last Updated: 2025-12-19
//
// ============================================================================
// Flutter: Transaction Close Management
// ============================================================================
//
// This example demonstrates how to properly manage transactions in Flutter SDK.
//
// CRITICAL: Flutter SDK SUPPORTS transactions but does NOT wait for pending
// transactions to complete when closing the Ditto instance.
//
// YOU MUST manually track and await all transactions before calling ditto.close()
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Tracking pending transactions
// 2. ✅ Safe Ditto close() with transaction await
// 3. ✅ DittoManager pattern
// 4. ✅ Proper transaction usage in Flutter
// 5. ❌ BAD: Closing without awaiting transactions
// 6. ❌ BAD: Untracked transactions
// 7. ❌ BAD: Race conditions on close
//
// WHY THIS MATTERS:
// - Flutter SDK has transaction API (available in v4.11+)
// - But does NOT wait for pending transactions when closing
// - Closing without awaiting → incomplete transactions, data loss
// - MUST track pending transactions manually
//
// OFFICIAL DOCS:
// "The Flutter SDK does not support waiting for pending transactions to
// complete. Make sure to await all transactions' completion before closing
// the Ditto instance."
// Source: https://docs.ditto.live/sdk/latest/crud/transactions
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: DittoManager with Transaction Tracking (RECOMMENDED)
// ============================================================================

/// ✅ GOOD: Proper transaction tracking and safe close
class DittoManager {
  final Ditto ditto;
  final Set<Future<void>> _pendingTransactions = {};

  DittoManager(this.ditto);

  /// Execute a transaction with tracking
  Future<void> executeTransaction(
    Future<void> Function(DittoTransaction) block, {
    String? hint,
    bool isReadOnly = false,
  }) async {
    print('🔄 Starting transaction${hint != null ? ': $hint' : ''}');

    // Create transaction future
    final transactionFuture = ditto.store.transaction(
      hint: hint,
      isReadOnly: isReadOnly,
      block,
    );

    // Track pending transaction
    _pendingTransactions.add(transactionFuture);

    try {
      // Await completion
      await transactionFuture;
      print('  ✅ Transaction completed${hint != null ? ': $hint' : ''}');
    } catch (e) {
      print('  ❌ Transaction failed${hint != null ? ': $hint' : ''}: $e');
      rethrow;
    } finally {
      // Remove from pending set
      _pendingTransactions.remove(transactionFuture);
    }
  }

  /// Execute a transaction that returns a value
  Future<T> executeTransactionReturning<T>(
    Future<T> Function(DittoTransaction) block, {
    String? hint,
    bool isReadOnly = false,
  }) async {
    T result;

    final transactionFuture = ditto.store.transaction<T>(
      hint: hint,
      isReadOnly: isReadOnly,
      (tx) async {
        return await block(tx);
      },
    );

    _pendingTransactions.add(transactionFuture as Future<void>);

    try {
      result = await transactionFuture;
      return result;
    } finally {
      _pendingTransactions.remove(transactionFuture as Future<void>);
    }
  }

  /// Get number of pending transactions
  int get pendingTransactionCount => _pendingTransactions.length;

  /// Check if any transactions are pending
  bool get hasPendingTransactions => _pendingTransactions.isNotEmpty;

  /// ✅ CRITICAL: Safe close - awaits all pending transactions
  Future<void> close() async {
    if (_pendingTransactions.isNotEmpty) {
      print('⏳ Waiting for ${_pendingTransactions.length} pending transactions...');

      // Wait for all transactions to complete
      await Future.wait(_pendingTransactions);

      print('  ✅ All transactions completed');
    }

    // Now safe to close Ditto
    await ditto.close();
    print('🔒 Ditto closed safely');
  }
}

// ============================================================================
// PATTERN 2: Using DittoManager for Multi-Step Operations
// ============================================================================

/// ✅ GOOD: Process order with proper transaction tracking
Future<void> processOrderExample(DittoManager dittoManager) async {
  print('📦 Processing order with transaction tracking...\n');

  await dittoManager.executeTransaction(
    (tx) async {
      // Step 1: Fetch order
      final orderResult = await tx.execute(
        'SELECT * FROM orders WHERE _id = :orderId',
        arguments: {'orderId': 'order_123'},
      );

      if (orderResult.items.isEmpty) {
        throw Exception('Order not found');
      }

      final order = orderResult.items.first.value;
      print('  📋 Order found: ${order['_id']}');

      // Step 2: Update order status
      await tx.execute(
        'UPDATE orders SET status = :status, processedAt = :timestamp WHERE _id = :orderId',
        arguments: {
          'orderId': 'order_123',
          'status': 'shipped',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      print('  📝 Order status updated to: shipped');

      // Step 3: Decrement inventory
      await tx.execute(
        'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = :itemId',
        arguments: {'itemId': order['itemId']},
      );
      print('  📦 Inventory decremented');
    },
    hint: 'process-order',
  );

  print('✅ Order processing completed\n');
}

// ============================================================================
// PATTERN 3: Read-Only Transaction
// ============================================================================

/// ✅ GOOD: Read-only transaction for consistent snapshot
Future<void> readOnlyTransactionExample(DittoManager dittoManager) async {
  print('📖 Running read-only transaction...\n');

  await dittoManager.executeTransaction(
    (tx) async {
      // All queries see the same data snapshot
      final ordersResult = await tx.execute('SELECT * FROM orders');
      final itemsResult = await tx.execute('SELECT * FROM order_items');

      print('  📊 Orders: ${ordersResult.items.length}');
      print('  📦 Items: ${itemsResult.items.length}');
    },
    hint: 'read-order-summary',
    isReadOnly: true,
  );

  print('✅ Read-only transaction completed\n');
}

// ============================================================================
// PATTERN 4: Multiple Concurrent Transactions
// ============================================================================

/// ✅ GOOD: Multiple concurrent transactions tracked properly
Future<void> multipleConcurrentTransactions(DittoManager dittoManager) async {
  print('🔀 Running multiple concurrent transactions...\n');

  // Start multiple transactions concurrently
  await Future.wait([
    dittoManager.executeTransaction(
      (tx) async {
        await tx.execute('UPDATE products SET views = views + 1 WHERE category = :cat',
          arguments: {'cat': 'electronics'});
        print('  ✅ Transaction 1 completed');
      },
      hint: 'update-electronics-views',
    ),
    dittoManager.executeTransaction(
      (tx) async {
        await tx.execute('UPDATE products SET views = views + 1 WHERE category = :cat',
          arguments: {'cat': 'books'});
        print('  ✅ Transaction 2 completed');
      },
      hint: 'update-books-views',
    ),
    dittoManager.executeTransaction(
      (tx) async {
        await tx.execute('UPDATE products SET views = views + 1 WHERE category = :cat',
          arguments: {'cat': 'clothing'});
        print('  ✅ Transaction 3 completed');
      },
      hint: 'update-clothing-views',
    ),
  ]);

  print('✅ All concurrent transactions completed\n');
}

// ============================================================================
// ❌ ANTI-PATTERN 1: Closing Without Awaiting Transactions
// ============================================================================

/// ❌ BAD: Close Ditto without waiting for pending transactions
Future<void> badCloseWithoutAwaitingExample(Ditto ditto) async {
  print('❌ BAD EXAMPLE: Closing without awaiting transactions...\n');

  // Start transaction WITHOUT tracking
  unawaited(ditto.store.transaction((tx) async {
    print('  🔄 Transaction started...');
    await Future.delayed(Duration(seconds: 2)); // Simulate work
    await tx.execute('UPDATE orders SET status = :status',
      arguments: {'status': 'completed'});
    print('  ⚠️ This may not complete!');
  }));

  // Close immediately - WRONG!
  print('  🔒 Closing Ditto immediately...');
  await ditto.close();
  print('  ❌ Transaction may be incomplete!\n');

  // PROBLEM: Transaction started but Ditto closed before completion
  // Result: Incomplete transaction, potential data loss
}

// ============================================================================
// ❌ ANTI-PATTERN 2: Untracked Transactions
// ============================================================================

/// ❌ BAD: Run transactions without tracking
Future<void> badUntrackedTransactionsExample(Ditto ditto) async {
  print('❌ BAD EXAMPLE: Untracked transactions...\n');

  // Multiple transactions without tracking
  ditto.store.transaction((tx) async {
    await tx.execute('UPDATE products SET stock = stock - 1');
    print('  ⚠️ Transaction 1 - untracked');
  });

  ditto.store.transaction((tx) async {
    await tx.execute('UPDATE orders SET status = :status',
      arguments: {'status': 'shipped'});
    print('  ⚠️ Transaction 2 - untracked');
  });

  // If app closes now, both transactions may be incomplete
  print('  ❌ No way to know if transactions completed before close\n');
}

// ============================================================================
// ❌ ANTI-PATTERN 3: Race Condition on Close
// ============================================================================

/// ❌ BAD: Race condition between transaction and close
Future<void> badRaceConditionExample(Ditto ditto) async {
  print('❌ BAD EXAMPLE: Race condition on close...\n');

  // Start long-running transaction
  final transactionFuture = ditto.store.transaction((tx) async {
    print('  🔄 Starting long transaction...');
    await Future.delayed(Duration(seconds: 3));
    await tx.execute('UPDATE large_table SET processed = true');
    print('  ⚠️ Long transaction - may not complete');
  });

  // Don't await transaction
  print('  🔒 Closing Ditto without waiting...');
  await ditto.close();
  print('  ❌ Race condition - transaction lost!\n');

  // transactionFuture is orphaned, may never complete
}

// ============================================================================
// ❌ ANTI-PATTERN 4: No Error Handling on Close
// ============================================================================

/// ❌ BAD: Close without checking for errors
Future<void> badNoErrorHandlingExample(DittoManager dittoManager) async {
  print('❌ BAD EXAMPLE: No error handling on close...\n');

  // Start transaction that may fail
  dittoManager.executeTransaction((tx) async {
    await tx.execute('INVALID SQL QUERY'); // Will throw error
  });

  // Try to close without handling errors
  try {
    await dittoManager.close();
  } catch (e) {
    print('  ❌ Error during close: $e');
    print('  ⚠️ Should have handled transaction errors before closing\n');
  }
}

// ============================================================================
// PATTERN 5: Proper Application Lifecycle Management
// ============================================================================

/// ✅ GOOD: Proper lifecycle management
class MyApp {
  late final DittoManager dittoManager;

  Future<void> initialize() async {
    print('🚀 Initializing app...\n');

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: '/tmp/ditto',
    );

    dittoManager = DittoManager(ditto);
    print('  ✅ DittoManager initialized\n');
  }

  Future<void> performOperations() async {
    print('📝 Performing operations...\n');

    // Run multiple operations
    await processOrderExample(dittoManager);
    await readOnlyTransactionExample(dittoManager);
    await multipleConcurrentTransactions(dittoManager);
  }

  /// ✅ CRITICAL: Proper cleanup on app shutdown
  Future<void> cleanup() async {
    print('🧹 Cleaning up...\n');

    // Check for pending transactions
    if (dittoManager.hasPendingTransactions) {
      print('  ⏳ ${dittoManager.pendingTransactionCount} transactions pending');
    }

    // Safe close - awaits all transactions
    await dittoManager.close();

    print('✅ Cleanup completed\n');
  }
}

// ============================================================================
// Main Example
// ============================================================================

void main() async {
  print('═══════════════════════════════════════════════════════════════════\n');
  print('Flutter Transaction Close Management - Best Practices\n');
  print('═══════════════════════════════════════════════════════════════════\n\n');

  // ✅ GOOD PATTERN: Proper lifecycle management
  final app = MyApp();

  try {
    await app.initialize();
    await app.performOperations();
  } finally {
    await app.cleanup();
  }

  print('\n═══════════════════════════════════════════════════════════════════');
  print('KEY TAKEAWAYS:');
  print('═══════════════════════════════════════════════════════════════════');
  print('1. ✅ Flutter SDK SUPPORTS transactions (v4.11+)');
  print('2. ⚠️  Flutter does NOT wait for pending transactions on close');
  print('3. ✅ Use DittoManager to track pending transactions');
  print('4. ✅ Always await all transactions before calling ditto.close()');
  print('5. ❌ Never close Ditto with pending transactions');
  print('6. ❌ Never use unawaited() with transactions before close');
  print('═══════════════════════════════════════════════════════════════════\n');
}

// Helper function
void unawaited(Future<void> future) {
  // Intentionally not awaiting - for demonstration only
  // DO NOT DO THIS in production code with transactions
}
