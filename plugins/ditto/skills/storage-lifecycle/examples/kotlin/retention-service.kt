// Retention services for Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// A long-lived service keeps only recent documents on the device. It moves the
// boundary of its subscription and evicts the complement in three steps:
// close the subscription, EVICT with the new cutoff, and subscribe again with
// the same cutoff, even if the eviction failed. Evicting documents that still
// match an active subscription is futile: peers send them back.
//
// Guide: § EVICT, § Time-based eviction, § Batching evictions,
//   § Soft delete, subscriptions, and cleanup, § Subscriptions in Kotlin

import com.ditto.kotlin.*
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.*

private val utcMillis: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

/** The same fixed-precision UTC format as the createdAt and deletedAt fields. */
fun utcTimestamp(time: Instant = Instant.now()): String = utcMillis.format(time)

/** ✅ GOOD: Keep the last 7 days of orders on this device. */
class OrderRetention(private val ditto: Ditto) {
    private val retention = Duration.ofDays(7)
    private var subscription: DittoSyncSubscription? = null

    private fun cutoff(): String = utcTimestamp(Instant.now().minus(retention))

    /** Call once at startup (before ditto.sync.start()). */
    fun start() {
        subscription = subscribeFrom(cutoff())
    }

    /** Call on a schedule, for example once a day. */
    suspend fun evictExpired(): Long {
        val cutoff = cutoff()
        subscription?.close() // 1. Stop asking peers for the documents about to be evicted.
        try {
            return evictInBatches(cutoff) // 2. Evict exactly the complement of the new subscription.
        } finally {
            subscription = subscribeFrom(cutoff) // 3. Subscribe again, even if the eviction failed.
        }
    }

    /** ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict. */
    private suspend fun evictInBatches(cutoff: String): Long {
        var total = 0L
        while (true) {
            val evicted = ditto.store.execute(
                "EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 RETURNING COUNT(*) AS evicted",
                mapOf("cutoff" to cutoff),
            ) { result -> result.items.first().value["evicted"].long }
            total += evicted
            if (evicted == 0L) return total
        }
    }

    private fun subscribeFrom(cutoff: String): DittoSyncSubscription =
        ditto.sync.registerSubscription("SELECT * FROM orders WHERE createdAt >= :cutoff", mapOf("cutoff" to cutoff))

    fun stop() {
        subscription?.close()
    }
}

/**
 * ✅ GOOD (Variant B): Keep active orders and orders deleted within the
 * retention window, and evict older deleted orders.
 */
class OrderSoftDeleteRetention(private val ditto: Ditto, private val storeId: String) {
    /** Longer than the longest time a device is expected to stay offline. */
    private val retention = Duration.ofDays(30)
    private var subscription: DittoSyncSubscription? = null

    private fun cutoff(): String = utcTimestamp(Instant.now().minus(retention))

    fun start() {
        subscription = subscribe(cutoff())
    }

    suspend fun evictExpired() {
        val cutoff = cutoff()
        subscription?.close()
        try {
            ditto.store.execute(
                "EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff",
                mapOf("storeId" to storeId, "cutoff" to cutoff),
            )
        } finally {
            subscription = subscribe(cutoff)
        }
    }

    private fun subscribe(cutoff: String): DittoSyncSubscription =
        ditto.sync.registerSubscription(
            "SELECT * FROM orders WHERE storeId = :storeId " +
                "AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)",
            mapOf("storeId" to storeId, "cutoff" to cutoff),
        )

    fun stop() {
        subscription?.close()
    }
}

/**
 * ✅ GOOD: Switching stores: close the old subscriptions first, evict the old
 * store's documents, then subscribe to the new store.
 */
suspend fun switchStore(
    ditto: Ditto,
    current: List<DittoSyncSubscription>,
    newStoreId: String,
): List<DittoSyncSubscription> {
    current.forEach { it.close() }
    ditto.store.execute("EVICT FROM orders WHERE storeId != :storeId", mapOf("storeId" to newStoreId))
    return listOf(
        ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to newStoreId)),
    )
}

/**
 * ✅ GOOD: Runs the eviction about once a day while the app runs, in a scope
 * that lives as long as the app. (WorkManager is an alternative that also runs
 * when the app is not open.)
 */
fun scheduleDailyEviction(scope: CoroutineScope, retention: OrderRetention): Job =
    scope.launch {
        while (isActive) {
            try {
                retention.evictExpired()
            } catch (error: CancellationException) {
                throw error
            } catch (error: DittoException) {
                android.util.Log.e("Retention", "Eviction failed; trying again tomorrow", error)
            }
            delay(Duration.ofDays(1).toMillis())
        }
    }

// ❌ Anti-pattern: evicting on every screen visit
/**
 * ❌ BAD: An eviction in a screen model's init runs on every screen visit, and
 * it evicts documents that the active subscription brings straight back.
 */
class OrdersScreenModelThatEvicts(ditto: Ditto, scope: CoroutineScope) {
    init {
        scope.launch {
            ditto.store.execute(
                "EVICT FROM orders WHERE createdAt < :cutoff",
                mapOf("cutoff" to utcTimestamp(Instant.now().minus(Duration.ofDays(7)))),
            )
        }
    }
}
