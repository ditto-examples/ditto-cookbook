// Transactions in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// ditto.store.transaction(hint, isReadOnly) { tx -> ... } runs the block and
// returns what the block returns: DittoTransaction.Result.Commit(value) commits
// and DittoTransaction.Result.Rollback rolls back. A block that throws rolls
// back, and the exception reaches the caller. A statement that fails inside
// the block does not end the transaction when the block catches the error.
// Inside the block, run every statement through tx.execute.
//
// 1. ✅ Atomic multi-document change that uses only tx.execute
// 2. ✅ Explicit rollback with a typed result
// 3. ✅ Read-only transaction for a consistent snapshot
// 4. ✅ I/O before the transaction, short transaction afterwards
// 5. ✅ Handling a failed statement deliberately
// 6. ✅ Many documents in one statement instead of many concurrent writes
// 7. ✅ Closing Ditto: close() waits for an open transaction
//
// Guide: § Transactions, § Transaction Rules, § Concurrency and Duration, § Transactions in Kotlin

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.*

private val utcMillis: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

fun utcTimestamp(time: Instant = Instant.now()): String = utcMillis.format(time)

fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

/** ✅ GOOD: Close an order and create its invoice atomically. */
suspend fun closeOrderWithInvoice(ditto: Ditto, orderId: String, invoiceId: String) {
    ditto.store.transaction(hint = "closeOrderWithInvoice") { tx -> // The hint appears in logs.
        val total = tx.execute("SELECT * FROM orders WHERE _id = :id", mapOf("id" to orderId)) { result ->
            result.items.firstOrNull()?.value?.get("total")?.numberOrNull()
        } ?: throw IllegalStateException("Order $orderId not found") // Throwing rolls back.
        tx.execute(
            "INSERT INTO invoices DOCUMENTS (:invoice)",
            mapOf("invoice" to mapOf("_id" to invoiceId, "orderId" to orderId, "total" to total, "createdAt" to utcTimestamp())),
        )
        tx.execute(
            "UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id",
            mapOf("id" to orderId, "status" to "closed", "invoiceId" to invoiceId),
        )
        DittoTransaction.Result.Commit(Unit)
    }
}

/** ✅ GOOD: Returns true when the order was shipped; rolls back without throwing otherwise. */
suspend fun shipOrder(ditto: Ditto, orderId: String): Boolean {
    val result = ditto.store.transaction(hint = "shipOrder") { tx ->
        val paid = tx.execute(
            "SELECT * FROM orders WHERE _id = :id AND status = :status",
            mapOf("id" to orderId, "status" to "paid"),
        ) { it.items.isNotEmpty() }
        if (!paid) return@transaction DittoTransaction.Result.Rollback // Nothing to ship.
        tx.execute("UPDATE orders SET status = :status WHERE _id = :id", mapOf("id" to orderId, "status" to "shipped"))
        DittoTransaction.Result.Commit(true)
    }
    return result is DittoTransaction.Result.Commit
}

/** ✅ GOOD: Both counts are read from the same snapshot. */
suspend fun orderCounts(ditto: Ditto): Pair<Long, Long> {
    val result = ditto.store.transaction(hint = "orderCounts", isReadOnly = true) { tx ->
        suspend fun count(status: String) = tx.execute(
            "SELECT COUNT(*) AS n FROM orders WHERE status = :status",
            mapOf("status" to status),
        ) { it.items.first().value["n"].long }
        DittoTransaction.Result.Commit(count("open") to count("closed"))
    }
    return (result as DittoTransaction.Result.Commit).value
}

/**
 * ✅ GOOD: The payment call happens before the transaction starts, so no other
 * write waits for the network.
 */
suspend fun checkout(ditto: Ditto, orderId: String, chargeCard: suspend () -> Unit) {
    chargeCard() // Outside the transaction.
    ditto.store.transaction(hint = "recordPayment") { tx ->
        tx.execute(
            "UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id",
            mapOf("id" to orderId, "status" to "paid", "paidAt" to utcTimestamp()),
        )
        tx.execute("INSERT INTO payments DOCUMENTS (:payment)", mapOf("payment" to mapOf("_id" to "payment-$orderId", "orderId" to orderId)))
        DittoTransaction.Result.Commit(Unit)
    }
}

/**
 * ✅ GOOD: A caught error does NOT roll back the transaction. Decide
 * explicitly: here, a failed audit entry rolls everything back.
 */
suspend fun archiveOrder(ditto: Ditto, orderId: String): Boolean {
    val result = ditto.store.transaction(hint = "archiveOrder") { tx ->
        tx.execute("UPDATE orders SET archived = true WHERE _id = :id", mapOf("id" to orderId))
        try {
            tx.execute("INSERT INTO audit DOCUMENTS (:entry)", mapOf("entry" to mapOf("_id" to "archive-$orderId", "at" to utcTimestamp())))
        } catch (error: DittoException) {
            return@transaction DittoTransaction.Result.Rollback // the archive flag is not kept either
        }
        DittoTransaction.Result.Commit(Unit)
    }
    return result is DittoTransaction.Result.Commit
}

/**
 * ✅ GOOD: One statement writes many documents. Many concurrent execute calls
 * behind a long transaction each hold a thread while they wait, and can take
 * every thread of Dispatchers.IO.
 */
suspend fun importOrders(ditto: Ditto, orders: List<Map<String, Any?>>) {
    withContext(Dispatchers.IO) {
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:orders) ON ID CONFLICT DO UPDATE",
            mapOf("orders" to orders),
        )
    }
}

/**
 * ✅ GOOD: ditto.close() waits for an open transaction, so it needs no tracking.
 * Make sure no transaction can deadlock: then close() would never return.
 */
fun shutdown(ditto: Ditto) {
    ditto.close()
}
