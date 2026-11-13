package com.example.fieldservice.data

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

data class WorkOrder(
    val id: String,
    val siteId: String,
    val title: String,
    val status: String,
    val technicianNote: String,
    val partCount: Int,
)

/** Converts a row of the workOrders collection. */
fun workOrderFromValue(value: DittoCborSerializable.Dictionary): WorkOrder = WorkOrder(
    id = value["_id"].string,
    siteId = value["siteId"].string,
    title = value["title"].stringOrNull ?: "",
    status = value["status"].stringOrNull ?: "open",
    technicianNote = value["technicianNote"].string,
    partCount = value["parts"].listOrNull?.size ?: 0,
)

/** Returns a random (version 4) UUID. */
fun newId(): String = UUID.randomUUID().toString()

private val utcMillis: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

/** Returns the time as an ISO-8601 UTC string with exactly millisecond precision. */
fun utcTimestamp(time: Instant = Instant.now()): String = utcMillis.format(time)
