// Recommended subscription patterns for Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Rules:
// - A subscription query is SELECT * FROM <collection> [WHERE <condition>].
//   Projections, DISTINCT, aggregates, JOIN, USE IDS, LIMIT and ORDER BY make
//   registerSubscription throw DittoException.StoreException at once.
// - Subscriptions are long-lived (app or feature scope) and scoped by stable
//   partition keys. Avoid changing subscriptions more often than about every
//   15 minutes.
// - Keep a reference to every DittoSyncSubscription and close() it when its
//   data is no longer relevant. Closing does not delete local data. Garbage
//   collection does not stop a subscription.
// - UI filters, search, tabs, and sorting change local observers, not
//   subscriptions.
//
// Guide: § Subscription Rules, § Subscription Lifecycle, § Filter locally instead of re-registering,
//   § Cancelling subscriptions and local data, § Subscriptions in Kotlin

import android.util.Log
import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * ✅ GOOD: A session-level service owns the long-lived subscriptions of one
 * workspace (store). Create it after login; call leaveStore() on logout.
 */
class OrderSync(private val ditto: Ditto) {
    private val subscriptions = mutableListOf<DittoSyncSubscription>()
    private var storeId: String? = null

    /** Call once after login or when the user enters a store. */
    fun enterStore(storeId: String) {
        if (storeId == this.storeId) return // Already subscribed; do not re-register.
        leaveStore()
        this.storeId = storeId
        // Scope by a stable partition key; screens filter further locally.
        subscriptions += ditto.sync.registerSubscription(
            "SELECT * FROM orders WHERE storeId = :storeId",
            mapOf("storeId" to storeId),
        )
        // orderItems carries a copied storeId because subscriptions cannot join.
        subscriptions += ditto.sync.registerSubscription(
            "SELECT * FROM orderItems WHERE storeId = :storeId",
            mapOf("storeId" to storeId),
        )
        // A small reference-data collection that every device needs may be
        // subscribed to without a filter.
        subscriptions += ditto.sync.registerSubscription("SELECT * FROM products")
    }

    /** Call on logout or when the user leaves the store. */
    fun leaveStore() {
        subscriptions.forEach { it.close() } // No-op if already closed.
        subscriptions.clear()
        storeId = null
    }
}

/**
 * ✅ GOOD: Switching stores: close first, evict the old store's data from this
 * device, then subscribe to the new store. Evicting documents that still match
 * an active subscription is futile: peers send them back.
 */
suspend fun switchStore(
    ditto: Ditto,
    currentSubscriptions: List<DittoSyncSubscription>,
    newStoreId: String,
): List<DittoSyncSubscription> {
    currentSubscriptions.forEach { it.close() }
    ditto.store.execute("EVICT FROM orders WHERE storeId != :storeId", mapOf("storeId" to newStoreId))
    ditto.store.execute("EVICT FROM orderItems WHERE storeId != :storeId", mapOf("storeId" to newStoreId))
    return listOf(
        ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to newStoreId)),
        ditto.sync.registerSubscription("SELECT * FROM orderItems WHERE storeId = :storeId", mapOf("storeId" to newStoreId)),
    )
}

/**
 * ✅ GOOD (soft delete, Variant A): soft-deleted documents stay in the
 * subscription, and local queries hide them with
 * coalesce(isDeleted, false) = false, so every device can relay the flag.
 */
fun subscribeToStoreOrders(ditto: Ditto, storeId: String): DittoSyncSubscription =
    ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to storeId))

/** ✅ GOOD: Subscriptions for a local JOIN: one per collection that the join reads. */
fun subscribeForOrderList(ditto: Ditto, storeId: String): List<DittoSyncSubscription> = listOf(
    ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to storeId)),
    ditto.sync.registerSubscription("SELECT * FROM customers WHERE storeId = :storeId", mapOf("storeId" to storeId)),
)

/**
 * ✅ GOOD: The subscription (owned by OrderSync) stays stable while the user
 * switches status filters; flatMapLatest replaces only the local observer.
 * In a ViewModel, pass viewModelScope as scope.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OrdersByStatusModel(ditto: Ditto, scope: CoroutineScope, storeId: String) {
    private val status = MutableStateFlow("open")

    val orderIds: StateFlow<List<String>> = status
        .flatMapLatest { current ->
            ditto.store.observe(
                "SELECT _id FROM orders WHERE storeId = :storeId AND status = :status ORDER BY createdAt DESC, _id",
                mapOf("storeId" to storeId, "status" to current),
            ) { result -> result.items.map { it.value["_id"].string } }
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun showStatus(newStatus: String) {
        status.value = newStatus
    }
}

/**
 * ✅ GOOD: Inspect active subscriptions for debugging. In Kotlin,
 * queryArguments is null for a subscription without arguments, and the listed
 * objects are not the ones that registerSubscription returned.
 */
fun logActiveSubscriptions(ditto: Ditto) {
    for (subscription in ditto.sync.subscriptions) {
        Log.d("Sync", "${subscription.queryString} ${subscription.queryArgumentsJsonString ?: "{}"}")
    }
}

/** ✅ GOOD: Pausing sync does not require closing subscriptions: stop() pauses them, start() resumes them. */
fun pauseSync(ditto: Ditto) = ditto.sync.stop()

fun resumeSync(ditto: Ditto) = ditto.sync.start()
