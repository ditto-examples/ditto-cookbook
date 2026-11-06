// Recommended store observer patterns for Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// For screen state, use store.observe(...): it returns a cold Flow, and each
// collection is one observer that ends when the collecting coroutine is
// cancelled. Turn it into a StateFlow in the scope of the class that owns the
// screen's state; a ViewModel passes viewModelScope. Convert rows to plain
// values inside the transform: the result is closed when the transform returns.
//
// With the default scope of DittoFactory.create, Ditto calls handlers and
// transforms on the main thread (Note (SDK 5.1.0 and 5.2.0)).
//
// Observers read the local store only. Pair them with a long-lived
// subscription (see subscription-lifecycle-good.kt).
//
// Guide: § Store Observers in Kotlin, § Observer lifecycle in Kotlin, § Stable ordering, § Partial UI updates in Kotlin,
//   § Joins in observers, § Query results in Kotlin

import android.util.Log
import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/** Reads any number as a Double; a decimal that a 32-bit float holds exactly comes back as a FloatValue. */
fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

data class Order(val id: String, val status: String, val total: Double) {
    companion object {
        fun fromValue(value: DittoCborSerializable.Dictionary) = Order(
            id = value["_id"].string,
            status = value["status"].stringOrNull ?: "unknown",
            total = value["total"].numberOrNull() ?: 0.0,
        )
    }
}

/** ✅ GOOD: The recommended observer pattern for screen state. In a ViewModel, pass viewModelScope. */
class OpenOrdersModel(ditto: Ditto, scope: CoroutineScope) {
    val orders: StateFlow<List<Order>> = ditto.store
        .observe(
            "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
            mapOf("status" to "open"),
        ) { result ->
            // Convert inside the transform: the result is closed after it returns.
            result.items.map { Order.fromValue(it.value) }
        }
        // Observes only while the UI collects (plus 5 s for configuration changes).
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())
}

data class TaskRow(val id: String, val title: String)

/**
 * ✅ GOOD: Only the fields the list shows (plus _id), a deterministic order with
 * an _id tie-breaker, and a LIMIT that keeps the observer's result small.
 */
class TaskListModel(ditto: Ditto, scope: CoroutineScope, teamId: String) {
    val tasks: StateFlow<List<TaskRow>> = ditto.store
        .observe(
            "SELECT _id, title, createdAt FROM tasks " +
                "WHERE teamId = :teamId AND coalesce(isDeleted, false) = false " +
                "ORDER BY createdAt DESC, _id LIMIT 200",
            mapOf("teamId" to teamId),
        ) { result ->
            result.items.map { TaskRow(it.value["_id"].string, it.value["title"].stringOrNull ?: "") }
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())
}

/**
 * ✅ GOOD: Partial UI updates. The badge and the list each have their own
 * observer, and a StateFlow emits only when its value changes.
 */
class OrdersScreenModel(ditto: Ditto, scope: CoroutineScope) {
    val openCount: StateFlow<Int> = ditto.store
        .observe("SELECT COUNT(*) AS n FROM orders WHERE status = :status", mapOf("status" to "open")) { result ->
            result.items.firstOrNull()?.value?.get("n")?.intOrNull ?: 0
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), 0)

    val openOrders: StateFlow<List<Order>> = OpenOrdersModel(ditto, scope).orders
}

data class OrderWithCustomer(val orderId: String, val total: Double, val customerName: String?)

/**
 * ✅ GOOD: An observer owned by a non-UI controller that the owner closes. The
 * observed JOIN (SDK 5.1+) fires when either collection changes. Project the
 * keys of each row (o._id AS orderId): joined rows carry no _id of their own.
 * Subscribe to both collections separately.
 */
class OpenOrdersWithCustomers(ditto: Ditto) {
    private val _rows = MutableStateFlow<List<OrderWithCustomer>>(emptyList())
    val rows: StateFlow<List<OrderWithCustomer>> = _rows

    private val observer: DittoStoreObserver = ditto.store.registerObserver(
        "SELECT o._id AS orderId, o.total, c.name AS customerName " +
            "FROM orders o JOIN customers c ON c._id = o.customerId " +
            "WHERE o.status = :status ORDER BY o.createdAt DESC, o._id",
        mapOf("status" to "open"),
    ) { result ->
        try {
            _rows.value = result.items.map {
                OrderWithCustomer(
                    orderId = it.value["orderId"].string,
                    total = it.value["total"].numberOrNull() ?: 0.0,
                    customerName = it.value["customerName"].stringOrNull,
                )
            }
        } catch (error: Exception) {
            // An exception that leaves a registerObserver handler closes the
            // observer, and the SDK only logs it.
            Log.e("Orders", "Could not read the joined rows", error)
        }
    }

    /** A ViewModel calls this from onCleared(). */
    fun clear() {
        observer.close()
    }
}

/**
 * ✅ GOOD: Several collectors share one observer. Each collection of the cold
 * Flow from observe() would register an observer of its own.
 */
class SharedOrders(ditto: Ditto, scope: CoroutineScope) {
    val orders: SharedFlow<List<Order>> = ditto.store
        .observe("SELECT * FROM orders ORDER BY createdAt DESC, _id") { result ->
            result.items.map { Order.fromValue(it.value) }
        }
        .shareIn(scope, SharingStarted.WhileSubscribed(5_000), replay = 1)
}

/**
 * ✅ GOOD: Heavy work on the values runs off the main thread. The transform
 * stays short (it runs on the main thread with the default scope); the
 * collector moves the expensive part to Dispatchers.Default.
 */
fun observeOrderTotals(ditto: Ditto, scope: CoroutineScope, show: (Double) -> Unit): Job =
    scope.launch {
        ditto.store
            .observe("SELECT _id, total FROM orders WHERE status = :status", mapOf("status" to "open")) { result ->
                result.items.map { it.value["total"].numberOrNull() ?: 0.0 }
            }
            .collect { totals ->
                val sum = withContext(Dispatchers.Default) { totals.sum() } // imagine heavier work here
                show(sum)
            }
    }
