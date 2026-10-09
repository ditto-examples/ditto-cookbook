// Ditto SDK 5.1 (Flutter, ditto_live 5.1.0): Transaction patterns
//
// Guide: .claude/guides/best-practices/ditto.md#transactions
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Atomic multi-document change that uses only tx.execute
// 2. ✅ Explicit rollback with TransactionCompletionAction
// 3. ✅ Read-only transaction for a consistent snapshot
// 4. ✅ I/O before the transaction, short transaction afterwards
// 5. ✅ Handling a failed statement deliberately
// 6. ✅ Tracking in-flight transactions so ditto.close() can wait for them

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

/// ISO-8601 UTC timestamp with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z". Fixed precision keeps values sortable as text
/// (native Dart omits zero microseconds, so even one device would otherwise
/// mix precisions).
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// ============================================================================
// PATTERN 1: Atomic multi-document change
// ============================================================================

/// ✅ GOOD: Close an order and create its invoice atomically.
///
/// Throwing inside the callback rolls back every change and rethrows the
/// error to the caller of `transaction()`.
Future<void> closeOrderWithInvoice(
  Ditto ditto,
  String orderId,
  String invoiceId,
) async {
  await ditto.store.transaction(
    hint: 'closeOrderWithInvoice', // Appears in logs; useful for debugging.
    (tx) async {
      final result = await tx.execute(
        'SELECT * FROM orders WHERE _id = :id',
        arguments: {'id': orderId},
      );
      if (result.items.isEmpty) {
        throw StateError('Order $orderId not found'); // Rolls back.
      }
      final order = result.items.first.value;

      await tx.execute(
        'INSERT INTO invoices DOCUMENTS (:invoice)',
        arguments: {
          'invoice': {
            '_id': invoiceId,
            'orderId': orderId,
            'total': order['total'],
            'createdAt': utcTimestamp(),
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

// ============================================================================
// PATTERN 2: Explicit rollback without throwing
// ============================================================================

/// ✅ GOOD: Returns true when the order was shipped.
///
/// Returning `TransactionCompletionAction.rollback` discards all changes made
/// in the callback. Returning `commit` (or any other value) commits.
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

// ============================================================================
// PATTERN 3: Read-only transaction for a consistent snapshot
// ============================================================================

/// ✅ GOOD: Both counts are read from the same snapshot.
///
/// Read-only transactions can run concurrently with each other and with the
/// active read-write transaction. A mutating statement inside one throws.
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

// ============================================================================
// PATTERN 4: I/O first, then one short transaction
// ============================================================================

/// ✅ GOOD: The payment call happens before the transaction starts, so no
/// other read-write transaction waits for the network.
Future<void> checkout(
  Ditto ditto,
  String orderId,
  Future<void> Function() chargeCard,
) async {
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

// ============================================================================
// PATTERN 5: Handling a failed statement deliberately
// ============================================================================

/// ✅ GOOD: A caught error does NOT roll back the transaction. Decide
/// explicitly what happens next.
///
/// Here the audit entry is optional (commit without it), but the stock
/// update is required (roll back if it fails).
Future<bool> reserveItem(Ditto ditto, String itemId, String auditId) async {
  final action = await ditto.store.transaction(
    hint: 'reserveItem',
    (tx) async {
      try {
        await tx.execute(
          'UPDATE items SET reserved = true WHERE _id = :id',
          arguments: {'id': itemId},
        );
      } on DittoException catch (error) {
        debugPrint('Reservation failed: $error');
        return TransactionCompletionAction.rollback; // Required step failed.
      }

      try {
        await tx.execute(
          'INSERT INTO auditLog DOCUMENTS (:entry)',
          arguments: {
            'entry': {'_id': auditId, 'itemId': itemId, 'action': 'reserve'},
          },
        );
      } on DittoException catch (error) {
        // Optional step: log it and keep the reservation.
        debugPrint('Audit entry skipped: $error');
      }
      return TransactionCompletionAction.commit;
    },
  );
  return action == TransactionCompletionAction.commit;
}

// ============================================================================
// PATTERN 6: Wait for in-flight transactions before closing
// ============================================================================

/// ✅ GOOD: `ditto.close()` does not wait for in-flight transactions, so
/// track them and await them before closing.
class TransactionTracker {
  final _pending = <Future<Object?>>{};

  Future<T> run<T>(
    Ditto ditto,
    String hint,
    Future<T> Function(Transaction tx) work,
  ) {
    final future = ditto.store.transaction(hint: hint, work);
    _pending.add(future);
    return future.whenComplete(() => _pending.remove(future));
  }

  Future<void> closeWhenIdle(Ditto ditto) async {
    // Errors are reported to the callers of run(); ignore them here.
    // then() with an onError callback works for any result type T, whereas a
    // catchError handler would have to return a value of type T.
    await Future.wait(
      _pending.map((f) => f.then<void>((_) {}, onError: (Object _) {})),
    );
    await ditto.close();
  }
}

/// Usage: route every transaction through the tracker, then shut down.
Future<void> trackerUsage(Ditto ditto, TransactionTracker tracker) async {
  await tracker.run(ditto, 'markOpen', (tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': 'order-1', 'status': 'open'},
    );
  });
  await tracker.closeWhenIdle(ditto);
}
