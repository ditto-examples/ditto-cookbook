// SDK Version: Ditto SDK 5.2.0 (com.ditto:ditto-kotlin 5.2.0)
// Platform: Kotlin (Android)
// Last Updated: 2026-11-06
//
// Partial UI Updates and Diffing (Kotlin)
//
// Guide sections (../../../guide/reference/best-practices/ and knowledge/):
// - § Partial UI Updates
// - § Partial UI updates in Kotlin
// - § Diffing Results
// - § Diffing results in Kotlin
//
// An observer delivers a new result for any change that affects its query.
// Keep each observer narrow and give each region of a screen its own
// StateFlow. A StateFlow emits only when the new value differs from the
// current one, so map rows to data classes (which compare by value).
//
// PATTERNS DEMONSTRATED:
// 1. ✅ One small observer per screen region (badge, list)
// 2. ✅ Keyed rows: a list that diffs by _id does not need DittoDiff
// 3. ✅ DittoDiff to log what changed between results
// 4. ✅ DittoDiff turned into the steps of an animated list
// 5. ❌ One broad observer for the whole screen
//
// DittoDiff facts: the first result reports every row as an insertion; moving
// one row reports every row whose position shifted as a move; deletions are
// indexes into the OLD list, insertions and updates into the NEW list.

import android.util.Log
import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

data class OrderRow(val id: String, val status: String, val total: Double)

// PATTERN 1 + 2: One observer per region; keyed rows
/** ✅ GOOD: The badge and the list each observe what they need. In a ViewModel, pass viewModelScope. */
class OrdersScreenModel(ditto: Ditto, scope: CoroutineScope) {
    /** Changes only when the count changes. */
    val openCount: StateFlow<Int> = ditto.store
        .observe("SELECT COUNT(*) AS n FROM orders WHERE status = :status", mapOf("status" to "open")) { result ->
            result.items.firstOrNull()?.value?.get("n")?.intOrNull ?: 0
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), 0)

    /** Changes only when a displayed field changes. A list keyed by OrderRow.id updates only changed rows. */
    val openOrders: StateFlow<List<OrderRow>> = ditto.store
        .observe(
            "SELECT _id, status, total FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
            mapOf("status" to "open"),
        ) { result ->
            result.items.map {
                OrderRow(it.value["_id"].string, it.value["status"].string, it.value["total"].numberOrNull() ?: 0.0)
            }
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())
}

// PATTERN 3: Logging changes
/** ✅ GOOD: Report inserted, deleted, updated, and moved documents. */
fun logOrderChanges(ditto: Ditto): DittoStoreObserver {
    var previousIds = emptyList<String>()
    return ditto.store.registerObserver("SELECT * FROM orders ORDER BY createdAt, _id LIMIT 200") { result, diff ->
        val currentIds = result.items.map { it.value["_id"].string }
        for (index in diff.deletions) Log.d("Orders", "deleted ${previousIds[index]}")
        for (index in diff.insertions) Log.d("Orders", "inserted ${currentIds[index]}")
        for (index in diff.updates) Log.d("Orders", "updated ${currentIds[index]}")
        for (move in diff.moves) Log.d("Orders", "moved ${move.from} -> ${move.to}")
        previousIds = currentIds
    }
}

// PATTERN 4: An animated list
data class OrderListUpdate(
    val orderIds: List<String>,
    val removedIndexes: List<Int>, // old indexes, descending
    val insertedIndexes: List<Int>, // new indexes, ascending
    val updatedIndexes: Set<Int>,
)

/** ✅ GOOD: Removals from the end of the old list, then insertions in ascending order; a move is both. */
class AnimatedOrdersModel(ditto: Ditto, scope: CoroutineScope) {
    val updates: SharedFlow<OrderListUpdate> = ditto.store
        .observe(
            "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200",
            mapOf("status" to "open"),
        ) { result, diff ->
            OrderListUpdate(
                orderIds = result.items.map { it.value["_id"].string },
                removedIndexes = (diff.deletions + diff.moves.map { it.from }).sortedDescending(),
                insertedIndexes = (diff.insertions + diff.moves.map { it.to }).sorted(),
                updatedIndexes = diff.updates,
            )
        }
        .shareIn(scope, SharingStarted.WhileSubscribed(5_000))
}

// PATTERN 5: One broad observer
data class WholeScreenState(val title: String, val filters: List<String>, val orders: List<String>)

/**
 * ❌ BAD: The whole collection without a filter, ORDER BY, or LIMIT, and one
 * state object for the whole screen: every write to any order rebuilds the
 * title, the filters, and the list.
 */
class WholeScreenModel(ditto: Ditto, scope: CoroutineScope) {
    val state: StateFlow<WholeScreenState?> = ditto.store
        .observe("SELECT * FROM orders") { result ->
            val ids = result.items.map { it.value["_id"].string }
            WholeScreenState("Orders (${ids.size})", ids.map { "filter-$it" }, ids)
        }
        .stateIn(scope, SharingStarted.Eagerly, null)
}
