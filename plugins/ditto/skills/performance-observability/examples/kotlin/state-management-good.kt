// SDK Version: Ditto SDK 5.2.0 (com.ditto:ditto-kotlin 5.2.0)
// Platform: Kotlin (Android)
// Last Updated: 2026-11-06
//
// State Management with Ditto Observers (Correct Patterns)
//
// Guide sections (../../../guide/reference/best-practices/ and knowledge/):
// - § Store Observers in Kotlin
// - § Observer lifecycle in Kotlin
// - § Partial UI updates in Kotlin
// - § Working with Query Results
//
// The classes below receive a CoroutineScope so that they build without
// androidx: in an Android ViewModel, pass viewModelScope, and the observers end
// when the ViewModel is cleared. The UI collects the StateFlows with the
// lifecycle-aware collectors of androidx.lifecycle.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ A model that owns its observers through its scope and exposes StateFlows
// 2. ✅ Immutable data classes instead of query results
// 3. ✅ Separate observers for separate screen regions (badge vs list)
// 4. ✅ A registerObserver handle closed when the owner is cleared
// 5. ✅ Subscription at feature scope, observers at screen scope

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

// Model
/** Immutable: equal rows compare equal, so a StateFlow does not emit an unchanged list. */
data class Todo(val id: String, val title: String, val done: Boolean)

data class TodosUiState(val todos: List<Todo> = emptyList(), val loading: Boolean = true)

// PATTERN 1 + 2: A model that owns its observers
/** ✅ GOOD: In a ViewModel, pass viewModelScope; the observer ends with it. */
class TodosModel(ditto: Ditto, scope: CoroutineScope, listId: String) {
    val state: StateFlow<TodosUiState> = ditto.store
        .observe(
            "SELECT _id, title, done FROM todos WHERE listId = :listId " +
                "AND coalesce(isDeleted, false) = false ORDER BY createdAt, _id",
            mapOf("listId" to listId),
        ) { result ->
            TodosUiState(
                todos = result.items.map {
                    Todo(it.value["_id"].string, it.value["title"].stringOrNull ?: "", it.value["done"].booleanOrNull ?: false)
                },
                loading = false,
            )
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), TodosUiState())

    /** ✅ GOOD: A separate, tiny observer for a summary value: COUNT(*) instead of the whole list. */
    val openCount: StateFlow<Int> = ditto.store
        .observe(
            "SELECT COUNT(*) AS n FROM todos WHERE listId = :listId AND done = false " +
                "AND coalesce(isDeleted, false) = false",
            mapOf("listId" to listId),
        ) { result -> result.items.firstOrNull()?.value?.get("n")?.intOrNull ?: 0 }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), 0)
}

// PATTERN 4: A registerObserver handle
/** ✅ GOOD: The owner closes the handle when it is cleared (a ViewModel from onCleared()). */
class CartTotalModel(ditto: Ditto, cartId: String) {
    private val _total = MutableStateFlow(0.0)
    val total: StateFlow<Double> = _total

    private val observer = ditto.store.registerObserver(
        "SELECT price, quantity FROM cartItems WHERE cartId = :cartId",
        mapOf("cartId" to cartId),
    ) { result ->
        _total.value = result.items.sumOf {
            (it.value["price"].numberOrNull() ?: 0.0) * (it.value["quantity"].longOrNull ?: 0L)
        }
    }

    fun clear() {
        observer.close()
    }
}

// PATTERN 5: Subscription at feature scope
/** ✅ GOOD: The feature service owns the subscription; screens only observe locally. */
class TodosFeature(private val ditto: Ditto) {
    private var subscription: DittoSyncSubscription? = null

    fun start(teamId: String) {
        subscription?.close()
        subscription = ditto.sync.registerSubscription(
            "SELECT * FROM todos WHERE teamId = :teamId",
            mapOf("teamId" to teamId),
        )
    }

    fun stop() {
        subscription?.close()
        subscription = null
    }

    /** A screen's model, created per screen with the screen's scope. */
    fun screenModel(scope: CoroutineScope, listId: String) = TodosModel(ditto, scope, listId)
}
