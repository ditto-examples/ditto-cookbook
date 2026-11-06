// Handling DittoQueryResult and DittoQueryResultItem in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Rules:
// - store.execute(query, args) without a handler returns Unit. To read the
//   result, pass a handler; the result is closed when the handler returns, so
//   convert rows to plain Kotlin data inside it and never return the result or
//   its items.
// - executeRaw returns a result that you close; it is AutoCloseable (use { }).
// - item.value is a read-only DittoCborSerializable.Dictionary; each read
//   returns a new, equal object.
// - Read fields with .string, .long, .boolean, ... or the ...OrNull forms. A
//   missing key reads as NullValue (like null); a typed accessor on it throws.
// - A decimal that a 32-bit float holds exactly (7.5) comes back as a
//   FloatValue, for which doubleOrNull returns null: use numberOrNull() below.
// - commitId is null for reads. A write that changed nothing still gets a
//   commitId; track it only when mutatedDocumentIds() is not empty.
// - ditto.close() closes results that the app has not closed.
//
// Guide: § Working with Query Results, § Query results in Kotlin, § Arguments and value types in Kotlin

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*

/** Reads any number as a Double; a decimal that a 32-bit float holds exactly comes back as a FloatValue. */
fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

/** A plain, immutable model built from a result row (data classes compare by value). */
data class Order(val id: String, val status: String, val total: Double) {
    companion object {
        fun fromValue(value: DittoCborSerializable.Dictionary) = Order(
            id = value["_id"].string,
            status = value["status"].stringOrNull ?: "unknown",
            total = value["total"].numberOrNull() ?: 0.0,
        )
    }
}

/** ✅ GOOD: Project only the needed fields, convert inside the handler, return models. */
suspend fun loadOpenOrders(ditto: Ditto): List<Order> =
    ditto.store.execute(
        "SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id",
        mapOf("status" to "open"),
    ) { result -> result.items.map { Order.fromValue(it.value) } }

/** ✅ GOOD: Read a single row and keep the model, not the item. */
suspend fun loadOrder(ditto: Ditto, id: String): Order? =
    ditto.store.execute("SELECT * FROM orders WHERE _id = :id", mapOf("id" to id)) { result ->
        result.items.firstOrNull()?.let { Order.fromValue(it.value) }
    }

data class ChangedOrders(val ids: List<String>, val commitId: ULong?)

/** ✅ GOOD: Inspect which documents changed; track the commit only when something changed. */
suspend fun closeOrders(ditto: Ditto, ids: List<String>): ChangedOrders =
    ditto.store.execute(
        "UPDATE orders SET status = :status WHERE _id IN :ids",
        mapOf("status" to "closed", "ids" to ids),
    ) { result ->
        val changed = result.mutatedDocumentIds().map { it.string } // composite IDs: read .dictionary
        // Nothing to track when no document changed (for example, unknown IDs).
        ChangedOrders(changed, if (changed.isEmpty()) null else result.commitId)
    }

/** ✅ GOOD: Alternative encoding, for example to hand rows to a JSON decoder. */
suspend fun openOrdersAsJson(ditto: Ditto): List<String> =
    ditto.store.execute("SELECT * FROM orders WHERE status = :status", mapOf("status" to "open")) { result ->
        result.items.map { it.jsonString() }
    }

/** ✅ GOOD: A raw result for several steps, closed when the block ends. */
suspend fun openOrdersSummary(ditto: Ditto): String =
    ditto.store.executeRaw("SELECT * FROM orders WHERE status = :status", mapOf("status" to "open")).use { result ->
        "${result.items.size} open orders, first: ${result.items.firstOrNull()?.value?.get("_id")?.stringOrNull}"
    }

/** ✅ GOOD: A missing field and a null field read the same; containsKey tells them apart. */
fun phoneOf(customer: DittoCborSerializable.Dictionary): String? =
    customer["phone"].stringOrNull // .string would throw for a missing or null phone

/** ✅ GOOD: A cache holds plain models, never query results. */
class OrderCache(private val ditto: Ditto) {
    private var orders: Map<String, Order> = emptyMap()

    suspend fun refresh() {
        orders = ditto.store.execute("SELECT * FROM orders") { result ->
            result.items.associate { item -> Order.fromValue(item.value).let { it.id to it } }
        }
    }

    operator fun get(id: String): Order? = orders[id]
}

/**
 * ❌ BAD: Keeping items out of the handler. They are closed when the handler
 * returns: reading one later throws IllegalStateException
 * ("Query result item has already been closed.").
 */
class RetainingCache(private val ditto: Ditto) {
    private var items: List<DittoQueryResultItem> = emptyList()

    suspend fun refresh() {
        items = ditto.store.execute("SELECT * FROM orders") { result -> result.items }
    }

    fun firstStatus(): String? = items.firstOrNull()?.value?.get("status")?.stringOrNull // throws
}

/** ❌ BAD: Reading a decimal with doubleOrNull: a total of 7.5 reads as null. */
fun totalOrNullBadly(order: DittoCborSerializable.Dictionary): Double? = order["total"].doubleOrNull
