// SDK Version: Ditto SDK 5.2.0 (com.ditto:ditto-kotlin 5.2.0)
// Platform: Kotlin (Android)
// Last Updated: 2026-11-06
//
// Store Observer Performance in Kotlin
//
// Guide sections (../../../guide/reference/best-practices/ and knowledge/):
// - § Store Observers in Kotlin
// - § Stable ordering
// - § Observer lifecycle in Kotlin
// - § Keep observer callbacks fast
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Recommended pattern: observe + stateIn in the owner's scope
// 2. ✅ A registerObserver handle owned and closed by its owner
// 3. ✅ Short transforms; heavy work off the main thread
// 4. ✅ Throttling updates for very busy collections
// 5. ✅ One shared observer for several collectors
// 6. ❌ No ORDER BY, an observer created on every bind
// 7. ❌ Blocking work in a handler that runs on the main thread
// 8. ❌ A handler that throws (the observer closes silently)
//
// With the default scope of DittoFactory.create, Ditto calls transforms and
// handlers on the main thread. For slow or async per-update work, see
// observer-backpressure.kt.

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

data class OrderRow(val id: String, val status: String, val total: Double)

private fun rowOf(value: DittoCborSerializable.Dictionary) =
    OrderRow(value["_id"].string, value["status"].stringOrNull ?: "unknown", value["total"].numberOrNull() ?: 0.0)

// PATTERN 1: The recommended observer pattern
/** ✅ GOOD: Only the fields the screen shows, a stable order, plain values out of the transform. */
class OpenOrdersModel(ditto: Ditto, scope: CoroutineScope) {
    val orders: StateFlow<List<OrderRow>> = ditto.store
        .observe(
            "SELECT _id, status, total FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
            mapOf("status" to "open"),
        ) { result -> result.items.map { rowOf(it.value) } }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())
}

// PATTERN 2: A registerObserver handle
/** ✅ GOOD: The owner keeps the handle and closes it (a ViewModel from onCleared()). */
class OpenOrdersCounter(ditto: Ditto) {
    private val _count = MutableStateFlow(0)
    val count: StateFlow<Int> = _count

    private val observer = ditto.store.registerObserver(
        "SELECT COUNT(*) AS n FROM orders WHERE status = :status",
        mapOf("status" to "open"),
    ) { result -> _count.value = result.items.firstOrNull()?.value?.get("n")?.intOrNull ?: 0 }

    fun clear() {
        observer.close()
    }
}

// PATTERN 3: Short transforms, heavy work elsewhere
/** ✅ GOOD: The transform only copies values; the collector computes on Dispatchers.Default. */
fun revenueByStatus(ditto: Ditto, scope: CoroutineScope, show: (Map<String, Double>) -> Unit): Job =
    scope.launch {
        ditto.store.observe("SELECT _id, status, total FROM orders") { result -> result.items.map { rowOf(it.value) } }
            .collect { rows ->
                val revenue = withContext(Dispatchers.Default) {
                    rows.groupBy { it.status }.mapValues { (_, list) -> list.sumOf { it.total } }
                }
                show(revenue)
            }
    }

// PATTERN 4: Throttling
/** ✅ GOOD: conflate() keeps only the latest result, and the delay limits updates to about four a second. */
fun throttledOrderCount(ditto: Ditto, scope: CoroutineScope, show: (Int) -> Unit): Job =
    scope.launch {
        ditto.store.observe("SELECT COUNT(*) AS n FROM orders") { it.items.first().value["n"].int }
            .conflate()
            .collect { count ->
                show(count)
                delay(250)
            }
    }

// PATTERN 5: One shared observer
/** ✅ GOOD: Every collector of `orders` shares one observer. */
class SharedOrders(ditto: Ditto, scope: CoroutineScope) {
    val orders: SharedFlow<List<OrderRow>> = ditto.store
        .observe("SELECT _id, status, total FROM orders ORDER BY createdAt DESC, _id") { result ->
            result.items.map { rowOf(it.value) }
        }
        .shareIn(scope, SharingStarted.WhileSubscribed(5_000), replay = 1)
}

// PATTERN 6: No ORDER BY, observer per bind
/** ❌ BAD: Rows change position between updates, and every bind adds an observer that is never closed. */
fun bindTaskCount(ditto: Ditto, show: (Int) -> Unit) {
    ditto.store.registerObserver("SELECT * FROM tasks WHERE done = false") { result -> show(result.items.size) }
}

// PATTERN 7: Blocking work on the main thread
/** ❌ BAD: Sorting and formatting thousands of rows in the transform, which runs on the main thread by default. */
fun formattedReport(ditto: Ditto): Flow<String> =
    ditto.store.observe("SELECT * FROM orders") { result ->
        result.items.map { it.jsonString() }.sorted().joinToString("\n")
    }

// PATTERN 8: A handler that throws
/** ❌ BAD: A missing total throws, the observer closes, and the SDK only logs it. */
fun observeTotalsFragile(ditto: Ditto, show: (Double) -> Unit): DittoStoreObserver =
    ditto.store.registerObserver("SELECT total FROM orders") { result ->
        show(result.items.sumOf { it.value["total"].numberOrNull()!! })
    }
