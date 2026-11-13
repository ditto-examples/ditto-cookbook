package com.example.fieldservice.data

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class WorkOrderRepository(private val ditto: Ditto) {

    suspend fun createWorkOrder(siteId: String, title: String): String = withContext(Dispatchers.IO) {
        require(siteId.isNotEmpty() && title.isNotBlank()) { "Invalid work order" }
        val id = newId()
        ditto.store.execute(
            "INSERT INTO workOrders DOCUMENTS (:order)",
            mapOf(
                "order" to mapOf(
                    "_id" to id,
                    "siteId" to siteId,
                    "title" to title,
                    "status" to "open",
                    "parts" to emptyList<Map<String, Any>>(),
                    "createdAt" to utcTimestamp(),
                ),
            ),
        )
        id
    }

    /** The note is optional: only technicians who write one set it. */
    suspend fun addNote(orderId: String, note: String) = withContext(Dispatchers.IO) {
        ditto.store.execute(
            "UPDATE workOrders SET technicianNote = :note WHERE _id = :id",
            mapOf("id" to orderId, "note" to note),
        )
    }

    suspend fun reschedule(orderId: String, scheduledFor: String) = withContext(Dispatchers.IO) {
        require(orderId.isNotEmpty()) { "Invalid work order ID" }
        ditto.store.execute(
            "UPDATE workOrders SET scheduledFor = :scheduledFor WHERE _id = :id",
            mapOf("id" to orderId, "scheduledFor" to scheduledFor),
        )
    }

    /** Any technician at the site can add the parts they used. */
    suspend fun addPart(orderId: String, partNumber: String, quantity: Int) = withContext(Dispatchers.IO) {
        val parts = ditto.store.execute(
            "SELECT parts FROM workOrders WHERE _id = :id",
            mapOf("id" to orderId),
        ) { result ->
            result.items.firstOrNull()?.value?.get("parts")?.listOrNull
                ?.mapNotNull { part ->
                    val number = part["partNumber"].stringOrNull ?: return@mapNotNull null
                    mapOf("partNumber" to number, "quantity" to (part["quantity"].longOrNull ?: 0L))
                }
                .orEmpty()
        }
        val updated = parts + mapOf("partNumber" to partNumber, "quantity" to quantity.toLong())
        ditto.store.execute(
            "UPDATE workOrders SET parts = :parts WHERE _id = :id",
            mapOf("id" to orderId, "parts" to updated),
        )
    }

    suspend fun forSite(siteId: String): List<WorkOrder> = withContext(Dispatchers.IO) {
        ditto.store.execute(
            "SELECT * FROM workOrders WHERE siteId = '$siteId' ORDER BY createdAt DESC, _id",
        ) { result -> result.items.map { workOrderFromValue(it.value) } }
    }

    suspend fun loadByIds(ids: List<String>): List<WorkOrder> = withContext(Dispatchers.IO) {
        ditto.store.execute(
            "SELECT * FROM workOrders WHERE _id IN :ids ORDER BY createdAt DESC, _id",
            mapOf("ids" to ids),
        ) { result -> result.items.map { workOrderFromValue(it.value) } }
    }

    suspend fun openRows(siteId: String): List<DittoQueryResultItem> = withContext(Dispatchers.IO) {
        ditto.store.execute(
            "SELECT * FROM workOrders WHERE siteId = :siteId AND status = :status ORDER BY createdAt DESC, _id",
            mapOf("siteId" to siteId, "status" to "open"),
        ) { result -> result.items }
    }

    suspend fun openTitles(siteId: String): List<String> =
        openRows(siteId).map { it.value["title"].stringOrNull ?: "" }

    /** Shows the number of open work orders in the app bar badge. */
    fun watchOpenCount(siteId: String, onCount: (Long) -> Unit) {
        ditto.store.registerObserver(
            "SELECT COUNT(*) AS n FROM workOrders WHERE siteId = :siteId AND status = :status",
            mapOf("siteId" to siteId, "status" to "open"),
        ) { result ->
            onCount(result.items.firstOrNull()?.value?.get("n")?.longOrNull ?: 0L)
        }
    }
}
