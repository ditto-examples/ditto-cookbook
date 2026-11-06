// Diffing observer results with DittoDiff in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Pass a lambda with two parameters to registerObserver, collect, or observe,
// and the SDK passes a DittoDiff against the previous result of the same
// observer:
// - insertions: indexes in the NEW list of rows that were added
// - deletions:  indexes in the OLD list of rows that were removed
// - updates:    indexes in the NEW list of rows whose value changed
// - moves:      DittoDiff.Move(from = oldIndex, to = newIndex)
//
// Facts:
// - The first result reports every row as an insertion.
// - Moving one row reports every row whose position shifted as a move.
// - DittoDiffer cannot be created by apps; the observer owns it.
// - The diff does not return old rows: keep previous values (or IDs) yourself.
// - Keep diffed queries bounded (WHERE and LIMIT). A ListAdapter with DiffUtil,
//   or a LazyColumn with keys, does not need DittoDiff.
//
// Guide: § Diffing Results, § Diffing results in Kotlin

import android.util.Log
import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/** ✅ GOOD: Logging changes between results. */
fun logOrderChanges(ditto: Ditto): DittoStoreObserver {
    var previousIds = emptyList<String>()
    return ditto.store.registerObserver("SELECT * FROM orders ORDER BY createdAt, _id LIMIT 200") { result, diff ->
        val currentIds = result.items.map { it.value["_id"].string }
        for (index in diff.deletions) Log.d("Orders", "deleted ${previousIds[index]}") // OLD list
        for (index in diff.insertions) Log.d("Orders", "inserted ${currentIds[index]}") // NEW list
        for (index in diff.updates) Log.d("Orders", "updated ${currentIds[index]}") // NEW list
        for (move in diff.moves) Log.d("Orders", "moved ${move.from} -> ${move.to}")
        previousIds = currentIds
    }
}

/** One update of an animated list: the new rows and the steps to apply to the old list. */
data class OrderListUpdate(
    val orderIds: List<String>,
    val removedIndexes: List<Int>, // old indexes, descending
    val insertedIndexes: List<Int>, // new indexes, ascending
    val updatedIndexes: Set<Int>, // new indexes
)

/**
 * ✅ GOOD: Turn each DittoDiff into the steps that an animating adapter applies
 * (notifyItemRemoved, then notifyItemInserted). A move is a removal plus an
 * insertion. In a ViewModel, pass viewModelScope.
 */
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

/**
 * ❌ BAD: Diffing an unbounded observer of a whole collection. Every change
 * compares the whole previous result. Add a WHERE filter and a LIMIT, or skip
 * the diff when keyed rows are enough.
 */
fun diffEverything(ditto: Ditto): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { _, diff ->
        Log.d("Orders", "${diff.insertions.size} inserted, ${diff.deletions.size} deleted")
    }
