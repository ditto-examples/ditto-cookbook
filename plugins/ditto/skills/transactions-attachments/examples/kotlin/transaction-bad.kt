// Transaction anti-patterns in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Every example compiles. Several of them deadlock: in the Kotlin SDK, a write
// through ditto.store.execute inside a transaction, and a read-write
// transaction inside another one, never return and raise no exception, and a
// later ditto.close() does not return either (in testing with SDK 5.1.0 and
// 5.2.0). The corrected versions are in transaction-good.kt.
//
// 1. ❌ ditto.store.execute inside a transaction (writes deadlock; reads miss the transaction's writes)
// 2. ❌ Nested read-write transaction (deadlocks)
// 3. ❌ Network calls inside a transaction (blocks all writes)
// 4. ❌ Keeping the DittoTransaction and using it later (throws IllegalStateException)
// 5. ❌ Swallowing an error and committing a half-done change
// 6. ❌ Many concurrent writes behind a transaction (thread starvation)
// 7. ❌ Wrapping a single statement in a transaction (adds nothing)
//
// Guide: § Transaction Rules, § Concurrency and Duration, § Transactions in Kotlin

import com.ditto.kotlin.*
import kotlinx.coroutines.*

/** ❌ BAD: The write through ditto.store.execute waits for this transaction, which waits for it: a deadlock. */
suspend fun markPaidInsideTransaction(ditto: Ditto, orderId: String) {
    ditto.store.transaction { tx ->
        tx.execute("UPDATE orders SET status = 'checkout' WHERE _id = :id", mapOf("id" to orderId))
        ditto.store.execute("UPDATE orders SET status = 'paid' WHERE _id = :id", mapOf("id" to orderId))
        DittoTransaction.Result.Commit(Unit)
    }
}

/**
 * ❌ BAD: Only one read-write transaction runs at a time. The inner one waits
 * for the outer one, which waits for the inner one.
 */
suspend fun nestedTransactions(ditto: Ditto, orderId: String) {
    ditto.store.transaction(hint = "outer") { _ ->
        ditto.store.transaction(hint = "inner") { inner ->
            inner.execute("UPDATE orders SET status = 'paid' WHERE _id = :id", mapOf("id" to orderId))
            DittoTransaction.Result.Commit(Unit)
        }
        DittoTransaction.Result.Commit(Unit)
    }
}
// ✅ Fix: pass the outer `tx` to helpers instead of starting a new transaction.

/**
 * ❌ BAD: While this transaction waits for the network, every other write, and
 * every change from other devices, waits too.
 */
suspend fun chargeInsideTransaction(ditto: Ditto, orderId: String, chargeCard: suspend () -> Unit) {
    ditto.store.transaction { tx ->
        chargeCard()
        tx.execute("UPDATE orders SET status = 'paid' WHERE _id = :id", mapOf("id" to orderId))
        DittoTransaction.Result.Commit(Unit)
    }
}
// ✅ Fix: call chargeCard() first, then record the result in one short transaction.

/**
 * ❌ BAD: A DittoTransaction is only valid inside its block. Using it later
 * throws IllegalStateException ("dittoffi_transaction was already closed.").
 */
suspend fun keepTransaction(ditto: Ditto): DittoTransaction {
    var kept: DittoTransaction? = null
    ditto.store.transaction { tx ->
        kept = tx
        DittoTransaction.Result.Commit(Unit)
    }
    return kept!! // calling execute on it throws
}

/**
 * ❌ BAD: A caught error does not roll back. The order is closed although its
 * invoice was never written.
 */
suspend fun closeOrderIgnoringErrors(ditto: Ditto, orderId: String, invoice: Map<String, Any?>) {
    ditto.store.transaction { tx ->
        tx.execute("UPDATE orders SET status = 'closed' WHERE _id = :id", mapOf("id" to orderId))
        try {
            tx.execute("INSERT INTO invoices DOCUMENTS (:invoice)", mapOf("invoice" to invoice))
        } catch (error: DittoException) {
            // swallowed
        }
        DittoTransaction.Result.Commit(Unit)
    }
}
// ✅ Fix: rethrow, or return DittoTransaction.Result.Rollback.

/**
 * ❌ BAD: One coroutine per document on Dispatchers.IO while a transaction is
 * open. Each waiting write holds an IO thread; with enough of them, the
 * transaction cannot resume, and neither it, the writes, nor close() return.
 */
fun importOrdersConcurrently(ditto: Ditto, scope: CoroutineScope, orders: List<Map<String, Any?>>) {
    for (order in orders) {
        scope.launch(Dispatchers.IO) {
            ditto.store.execute("INSERT INTO orders DOCUMENTS (:order)", mapOf("order" to order))
        }
    }
}

/** ❌ BAD: A single statement is already atomic; the transaction adds nothing. */
suspend fun singleStatementTransaction(ditto: Ditto, orderId: String) {
    ditto.store.transaction { tx ->
        tx.execute("UPDATE orders SET status = 'open' WHERE _id = :id", mapOf("id" to orderId))
        DittoTransaction.Result.Commit(Unit)
    }
}
