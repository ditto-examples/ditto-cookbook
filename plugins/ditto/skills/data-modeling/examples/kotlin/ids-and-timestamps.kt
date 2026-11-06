// Document IDs and timestamps for Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// - Generate a random (version 4) UUID for every new document; a UUID cannot be
//   passed as an argument value, so pass its toString().
// - Keep human-readable numbers in a separate field.
// - Store UTC with a zone designator, and produce every timestamp that is
//   sorted or compared with one fixed-precision helper. Instant.toString()
//   writes as many fraction digits as needed (".100Z", ".123Z", or six digits
//   for Instant.now() on Android 16), so it does not sort as text.
// - Instant, java.util.Date, and UUID values cannot be passed as argument
//   values at all: the call throws IllegalArgumentException.
// - java.time is part of Android from API level 26; with minSdk 24, enable core
//   library desugaring, or use epoch milliseconds.
//
// Guide: § Document IDs, § Timestamps, § IDs and Timestamps in Kotlin

import com.ditto.kotlin.*
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

private val utcMillis: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

/** Returns the time as an ISO-8601 UTC string with exactly millisecond precision, e.g. "2026-10-08T10:30:00.123Z". */
fun utcTimestamp(time: Instant = Instant.now()): String = utcMillis.format(time)

/** Returns a random (version 4) UUID such as "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f". */
fun newId(): String = UUID.randomUUID().toString()

/** ✅ GOOD: UUID v4 as _id, UTC timestamp from the helper. */
suspend fun createOrder(ditto: Ditto, storeId: String): String {
    val orderId = newId()
    ditto.store.execute(
        "INSERT INTO orders DOCUMENTS (:order)",
        mapOf("order" to mapOf("_id" to orderId, "storeId" to storeId, "status" to "open", "createdAt" to utcTimestamp())),
    )
    return orderId
}

/** A display label, not an identifier: never use it as _id or as a lookup key. */
fun displayNumber(terminalCode: String, localSequence: Int): String =
    "$terminalCode-${localSequence.toString().padStart(4, '0')}"

/** ✅ GOOD: The UUID identifies the order; the label is for people. */
suspend fun createOrderWithLabel(ditto: Ditto, terminalCode: String, localSequence: Int): String {
    val orderId = newId()
    ditto.store.execute(
        "INSERT INTO orders DOCUMENTS (:order)",
        mapOf(
            "order" to mapOf(
                "_id" to orderId,
                "displayNumber" to displayNumber(terminalCode, localSequence),
                "createdAt" to utcTimestamp(),
            ),
        ),
    )
    return orderId
}

/** ✅ GOOD: Consistent UTC timestamps from the one helper. */
suspend fun markReady(ditto: Ditto, orderId: String) {
    ditto.store.execute(
        "UPDATE orders SET readyAt = :readyAt WHERE _id = :id",
        mapOf("id" to orderId, "readyAt" to utcTimestamp()),
    )
}

/** ❌ BAD: Collides when two offline devices create the 42nd order of the day. */
fun badSequentialId(dailyCount: Int) = "order-$dailyCount"

/** ❌ BAD: Collides when two devices write within the same millisecond. */
fun badTimestampId() = "order-${System.currentTimeMillis()}"

/**
 * ❌ BAD: Local time without a zone (for example "2026-11-06T22:43:35.879370").
 * DQL date functions return MISSING for it, and values written in different
 * time zones do not compare correctly.
 */
suspend fun markReadyLocalTime(ditto: Ditto, orderId: String) {
    ditto.store.execute(
        "UPDATE orders SET readyAt = :readyAt WHERE _id = :id",
        mapOf("id" to orderId, "readyAt" to LocalDateTime.now().toString()), // lint-ignore
    )
}

/** ❌ BAD: Variable precision ("...20Z", "...20.100Z", six digits for now()): the strings do not sort as text. */
fun variablePrecisionTimestamp(): String = Instant.now().toString()

/** ❌ BAD: An Instant cannot be converted: the call throws IllegalArgumentException. */
suspend fun markShippedWithInstant(ditto: Ditto, orderId: String) {
    ditto.store.execute(
        "UPDATE orders SET shippedAt = :shippedAt WHERE _id = :id",
        mapOf("id" to orderId, "shippedAt" to Instant.now()),
    )
}
