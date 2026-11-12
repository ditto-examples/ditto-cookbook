// Store observer anti-patterns for Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Every example compiles, but leaks observers, reads closed results, stops
// updating without an error, or does far more work than needed. The corrected
// versions are in observer-patterns-good.kt and observer-backpressure.kt.
//
// Guide: § Store Observers in Kotlin, § Observer lifecycle in Kotlin, § Query results in Kotlin, § Stable ordering,
//   § Keep observer callbacks fast, § Backpressure in Kotlin

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * ❌ BAD: Registered from code that runs on every render or bind, and never
 * closed. Each call adds another observer; garbage collection does not stop
 * them (they stay in ditto.store.observers).
 */
fun renderOrderCount(ditto: Ditto, show: (Int) -> Unit) {
    ditto.store.registerObserver("SELECT * FROM orders") { result -> show(result.items.size) }
}

/**
 * ❌ BAD: The transform returns the items. They are closed when the transform
 * returns, so reading them in the collector throws IllegalStateException
 * ("Query result item has already been closed.").
 */
fun observeOrderItems(ditto: Ditto): Flow<List<DittoQueryResultItem>> =
    ditto.store.observe("SELECT * FROM orders ORDER BY createdAt DESC") { result -> result.items }

/**
 * ❌ BAD: Keeping a raw result in state. It holds native memory until it is
 * closed, and ditto.close() closes it under you.
 */
class RetainsResult(private val ditto: Ditto) {
    var latest: DittoQueryResult? = null

    suspend fun refresh() {
        latest = ditto.store.executeRaw("SELECT * FROM orders") // never closed
    }
}

/** ❌ BAD: No ORDER BY. Rows may change position between updates. */
fun observeTasksUnordered(ditto: Ditto): Flow<List<String>> =
    ditto.store.observe("SELECT * FROM tasks WHERE done = false") { result ->
        result.items.map { it.value["_id"].string }
    }

/**
 * ❌ BAD: The handler starts an upload and returns at once, so uploads overlap,
 * and Ditto does not wait for them. Suspend in the handler, or use collect().
 */
fun uploadOnEveryChange(ditto: Ditto, scope: CoroutineScope, upload: suspend (Int) -> Unit): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { result ->
        val count = result.items.size
        scope.launch { upload(count) }
    }

/**
 * ❌ BAD: Writing to the observed collection from its own handler without a
 * guard. Each write runs the observer again.
 * Comparing with the stored time does not help: each device writes its own, so devices that
 * run this observer keep overwriting each other (guide: Writing from Observers).
 */
fun touchOnEveryChange(ditto: Ditto): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { _ ->
        ditto.store.execute("UPDATE orders SET seenAt = :now", mapOf("now" to System.currentTimeMillis()))
    }

/**
 * ❌ BAD: The handler throws for a row without a price. The observer is closed,
 * the SDK only logs the exception, and the screen silently stops updating.
 */
fun observeTotalsFragile(ditto: Ditto, show: (Long) -> Unit): DittoStoreObserver =
    ditto.store.registerObserver("SELECT priceCents FROM orders") { result ->
        show(result.items.sumOf { it.value["priceCents"].long }) // throws on a missing price
    }

/**
 * ❌ BAD: Blocking work in a handler. With the default scope of
 * DittoFactory.create, handlers run on the main thread, so this freezes the UI.
 */
fun exportOnEveryChange(ditto: Ditto, writeFileBlocking: (Int) -> Unit): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { result ->
        writeFileBlocking(result.items.size)
    }

/**
 * ❌ BAD: One observer per list row. Observe the list once and pass the values
 * down to the rows.
 */
class OrderRowModel(ditto: Ditto, scope: CoroutineScope, orderId: String) {
    val status: StateFlow<String?> = ditto.store
        .observe("SELECT status FROM orders WHERE _id = :id", mapOf("id" to orderId)) { result ->
            result.items.firstOrNull()?.value?.get("status")?.stringOrNull
        }
        .stateIn(scope, SharingStarted.Eagerly, null)
}

/**
 * ❌ BAD: The same cold Flow collected in three places registers three
 * observers. Share it with stateIn or shareIn.
 */
fun collectThreeTimes(ditto: Ditto, scope: CoroutineScope) {
    val orders = ditto.store.observe("SELECT * FROM orders") { it.items.size }
    scope.launch { orders.collect { } } // badge
    scope.launch { orders.collect { } } // list
    scope.launch { orders.collect { } } // toolbar
}
