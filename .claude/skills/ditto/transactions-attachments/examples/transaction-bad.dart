// Ditto SDK 5.1 (Flutter, ditto_live 5.1.0): Transaction anti-patterns
//
// Guide: .claude/guides/best-practices/ditto.md#transaction-rules
//
// Every function below compiles. The problems appear at runtime.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ ditto.store.execute inside a transaction (throws DittoException)
// 2. ❌ Nested read-write transaction (deadlocks; the SDK does not detect it)
// 3. ❌ Network calls or timers inside a transaction (blocks all writes)
// 4. ❌ Storing the Transaction and using it later (throws DittoException)
// 5. ❌ Swallowing an error and committing a half-done change
// 6. ❌ Reading commitID inside the transaction
// 7. ❌ Closing Ditto while a transaction is still running
// 8. ❌ Wrapping a single statement in a transaction (adds nothing)
//
// See transaction-good.dart for the correct patterns.

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// ANTI-PATTERN 1: ditto.store.execute inside a transaction
// ============================================================================

/// ❌ BAD: Throws "Attempting to use `ditto.store.execute` while in a
/// transaction scope. Use `transaction.execute` instead ...".
/// In JavaScript, Swift, and Kotlin the same mistake can deadlock instead.
Future<void> storeExecuteInsideTransaction(Ditto ditto, String orderId) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'checkout'},
    );
    await ditto.store.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'paid'},
    );
  });
}

// ============================================================================
// ANTI-PATTERN 2: Nested read-write transaction
// ============================================================================

/// ❌ BAD: Only one read-write transaction runs at a time. The inner one waits
/// for the outer one, which waits for the inner one: a permanent deadlock.
Future<void> nestedTransaction(Ditto ditto, String orderId) async {
  await ditto.store.transaction((outer) async {
    await outer.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'paid'},
    );
    await _recordPaymentDate(ditto, orderId); // Hidden nesting via a helper.
  });
}

Future<void> _recordPaymentDate(Ditto ditto, String orderId) {
  return ditto.store.transaction((inner) async {
    await inner.execute(
      'UPDATE orders SET paidAt = :paidAt WHERE _id = :id',
      arguments: {
        'id': orderId,
        'paidAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  });
}

// ✅ Fix: pass the outer `tx` to helpers instead of starting a new
// transaction, or run the two transactions one after the other.

// ============================================================================
// ANTI-PATTERN 3: Network calls or timers inside a transaction
// ============================================================================

/// ❌ BAD: While this transaction waits for the network, every other
/// read-write transaction (and every plain store.execute write) waits.
/// After 10 seconds Ditto logs long-running transaction warnings.
Future<void> networkInsideTransaction(
  Ditto ditto,
  String orderId,
  Future<void> Function() chargeCard,
) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'checkout'},
    );
    await chargeCard(); // Network I/O inside the transaction.
    await Future<void>.delayed(const Duration(seconds: 2)); // Timer inside.
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'paid'},
    );
  });
}

// ✅ Fix: call chargeCard() first, then record the result in one short
// transaction with a hint.

// ============================================================================
// ANTI-PATTERN 4: Storing the Transaction and using it later
// ============================================================================

/// ❌ BAD: A Transaction is only valid inside its callback. Using it later
/// throws "Attempting to use transaction outside transaction scope ...".
class LeakyOrderService {
  LeakyOrderService(this.ditto);

  final Ditto ditto;
  Transaction? _lastTransaction;

  Future<void> start(String orderId) async {
    await ditto.store.transaction((tx) async {
      _lastTransaction = tx; // Stored outside the callback.
      await tx.execute(
        'UPDATE orders SET status = :status WHERE _id = :id',
        arguments: {'id': orderId, 'status': 'checkout'},
      );
    });
  }

  Future<void> finish(String orderId) async {
    await _lastTransaction?.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'paid'},
    );
  }
}

// ============================================================================
// ANTI-PATTERN 5: Swallowing an error and committing a half-done change
// ============================================================================

/// ❌ BAD: A caught error does not roll back. The invoice is committed even
/// though the order update failed, which is exactly what the transaction was
/// supposed to prevent.
Future<void> swallowedError(Ditto ditto, String orderId, String invoiceId) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'INSERT INTO invoices DOCUMENTS (:invoice)',
      arguments: {
        'invoice': {'_id': invoiceId, 'orderId': orderId},
      },
    );
    try {
      await tx.execute(
        'UPDATE orders SET invoiceId = :invoiceId WHERE _id = :id',
        arguments: {'id': orderId, 'invoiceId': invoiceId},
      );
    } catch (_) {
      // Ignored: the transaction continues and commits the invoice alone.
    }
  });
}

// ✅ Fix: rethrow, or return TransactionCompletionAction.rollback.

// ============================================================================
// ANTI-PATTERN 6: Reading commitID inside the transaction
// ============================================================================

/// ❌ BAD: commitID is null until the transaction commits, so this cannot be
/// used to track sync status. Return the QueryResult from the callback and read
/// its commitID after transaction() completes.
Future<void> commitIdInsideTransaction(Ditto ditto, String orderId) async {
  await ditto.store.transaction((tx) async {
    final result = await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'shipped'},
    );
    debugPrint('commitID: ${result.commitID}'); // null until the commit.
  });
}

// ============================================================================
// ANTI-PATTERN 7: Closing Ditto while a transaction is still running
// ============================================================================

/// ❌ BAD: ditto.close() does not wait for in-flight transactions. The
/// unawaited transaction can fail with DittoClosedException when the instance
/// closes.
Future<void> closeWithoutWaiting(Ditto ditto, String orderId) async {
  unawaited(
    ditto.store.transaction((tx) async {
      await tx.execute(
        'UPDATE orders SET status = :status WHERE _id = :id',
        arguments: {'id': orderId, 'status': 'archived'},
      );
    }),
  );
  await ditto.close();
}

// ✅ Fix: track pending transactions and await them before close()
// (TransactionTracker in transaction-good.dart).

// ============================================================================
// ANTI-PATTERN 8: A transaction around a single statement
// ============================================================================

/// ❌ BAD (unnecessary): A single UPDATE is already atomic. Wrapping it in a
/// transaction adds nothing.
Future<void> singleStatementTransaction(Ditto ditto, String orderId) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'open'},
    );
  });
}

// ✅ Fix: call ditto.store.execute(...) directly.
