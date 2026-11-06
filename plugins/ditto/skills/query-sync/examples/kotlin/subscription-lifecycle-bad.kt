// Subscription anti-patterns for Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Every example compiles and runs, but wastes bandwidth and storage, churns
// the mesh, or leaks subscriptions. The corrected versions are in
// subscription-lifecycle-good.kt.
//
// Subscription queries that registerSubscription rejects at once with
// DittoException.StoreException (described here instead of executed):
// - Projection, aggregate:  SELECT _id, status FROM orders / SELECT COUNT(*) AS n FROM orders
// - DISTINCT, GROUP BY, JOIN, USE IDS
// - LIMIT / ORDER BY:       SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50
//   -> "<dql> Unsupported feature: Limit or Order by" (while DQL_RESTRICT_SUBSCRIPTIONS
//      has its default value true; keep the default)
// - A non-SELECT statement -> "<dql> Unsupported feature: non-SELECT statement in sync subscription"
// Subscribe with SELECT * FROM c WHERE ... and sort, limit, project, or join in
// local queries instead.
//
// Guide: § Subscription Rules, § Subscription Lifecycle, § Scope subscriptions to what the device needs,
//   § Filter locally instead of re-registering, § Soft delete, subscriptions, and cleanup, § Subscriptions in Kotlin

import com.ditto.kotlin.*
import kotlinx.coroutines.*

/**
 * ❌ BAD: A new subscription every time a list row is bound, never closed.
 * Each one keeps replicating until the Ditto instance is closed.
 */
fun bindOrderBadge(ditto: Ditto, storeId: String, showStore: (String) -> Unit) {
    ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to storeId))
    showStore(storeId)
}

/**
 * ❌ BAD: A subscription owned by a screen's model. Every visit registers and
 * closes it, making peers across the mesh re-evaluate what they owe the device
 * and interrupting transfers. Own it in an app or feature service.
 */
class OrdersScreenSubscription(ditto: Ditto, storeId: String) {
    private val subscription = ditto.sync.registerSubscription(
        "SELECT * FROM orders WHERE storeId = :storeId",
        mapOf("storeId" to storeId),
    )

    fun clear() {
        subscription.close()
    }
}

/**
 * ❌ BAD: Re-registering the subscription whenever the user changes a filter or
 * a search term. Change the local observer instead.
 */
class OrderSearchSync(private val ditto: Ditto) {
    private var subscription: DittoSyncSubscription? = null

    fun onSearchChanged(storeId: String, status: String, customerName: String) {
        subscription?.close()
        subscription = ditto.sync.registerSubscription(
            "SELECT * FROM orders WHERE storeId = :storeId AND status = :status AND customerName = :name",
            mapOf("storeId" to storeId, "status" to status, "name" to customerName),
        )
    }
}

/**
 * ❌ BAD: The reference is dropped without closing. Garbage collection does not
 * stop the subscription; only ditto.sync.subscriptions can still reach it.
 */
fun subscribeAndForget(ditto: Ditto, storeId: String) {
    ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to storeId))
}

/**
 * ❌ BAD: Every device receives and stores every order of every tenant. Filter
 * by stable partition keys (tenant, store, region, team).
 */
fun subscribeToEverything(ditto: Ditto): DittoSyncSubscription =
    ditto.sync.registerSubscription("SELECT * FROM orders")

/**
 * ❌ BAD: Filtering the subscription on a field that changes often, or
 * excluding soft-deleted documents. Documents leave the subscription when they
 * change state, so devices stop following them and cannot relay the change.
 */
fun subscribeToOpenOrdersOnly(ditto: Ditto, storeId: String): DittoSyncSubscription =
    ditto.sync.registerSubscription(
        "SELECT * FROM orders WHERE storeId = :storeId AND status = 'open' AND coalesce(isDeleted, false) = false",
        mapOf("storeId" to storeId),
    )

/** ❌ BAD: Values interpolated into the subscription string. Use parameters. */
fun subscribeWithInterpolation(ditto: Ditto, storeId: String): DittoSyncSubscription =
    ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = '$storeId'")

/**
 * ❌ BAD: Evicting while the matching subscription is still active. Connected
 * peers notice the missing documents and send them back. Close first.
 */
suspend fun evictWhileSubscribed(ditto: Ditto, oldStoreId: String) {
    ditto.store.execute("EVICT FROM orders WHERE storeId = :storeId", mapOf("storeId" to oldStoreId))
}

/**
 * ❌ BAD: Expecting execute() to fetch data from peers. Without a matching
 * subscription it only sees what is already stored locally, and an empty
 * result does not mean that no data exists.
 */
suspend fun orderExistsAnywhere(ditto: Ditto, orderId: String): Boolean =
    ditto.store.execute("SELECT * FROM orders WHERE _id = :id", mapOf("id" to orderId)) { it.items.isNotEmpty() }
