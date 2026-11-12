// SDK Version: Ditto SDK 5.2.0 (com.ditto:ditto-kotlin 5.2.0)
// Platform: Kotlin (Android)
// Last Updated: 2026-11-06
//
// State Management Anti-Patterns with Ditto Observers
//
// Guide sections (../../../guide/reference/best-practices/ and knowledge/):
// - § Store Observers in Kotlin
// - § Observer lifecycle in Kotlin
// - § Keep observer callbacks fast
// - § Partial UI Updates
//
// Every class below compiles, but each one shows a mistake. The fix for each
// is in state-management-good.kt.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ One broad observer for the whole screen, with query result items in state
// 2. ❌ A registerObserver handle that is never closed
// 3. ❌ The same cold Flow collected by several collectors (one observer each)
// 4. ❌ Heavy synchronous work in the handler (the main thread by default)
// 5. ❌ One observer per list item
// 6. ❌ Writing to the observed collection from its own handler

import com.ditto.kotlin.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// ANTI-PATTERN 1: Broad observer, result items in state
/**
 * ❌ BAD: Observes the whole collection without ORDER BY or LIMIT and keeps the
 * items: they are closed when the handler returns, so the UI's later read of
 * an item throws IllegalStateException.
 */
class EverythingModel(ditto: Ditto) {
    val items = MutableStateFlow<List<DittoQueryResultItem>>(emptyList())

    init {
        ditto.store.registerObserver("SELECT * FROM todos") { result -> items.value = result.items }
    }
}

// ANTI-PATTERN 2: Never closed
/**
 * ❌ BAD: The handle is not kept, so nothing closes it. A new instance per
 * screen visit adds another observer; garbage collection does not stop them.
 */
class LeakyCountModel(ditto: Ditto) {
    val count = MutableStateFlow(0)

    init {
        ditto.store.registerObserver("SELECT COUNT(*) AS n FROM todos") { result ->
            count.value = result.items.first().value["n"].int
        }
    }
}

// ANTI-PATTERN 3: One cold Flow, several collectors
/**
 * ❌ BAD: The badge, the list, and the toolbar each collect the same cold Flow,
 * which registers three observers. Use stateIn or shareIn.
 */
class TripleCollector(ditto: Ditto, scope: CoroutineScope) {
    private val todos: Flow<Int> = ditto.store.observe("SELECT * FROM todos") { it.items.size }

    init {
        scope.launch { todos.collect { } }
        scope.launch { todos.collect { } }
        scope.launch { todos.collect { } }
    }
}

// ANTI-PATTERN 4: Heavy work in the handler
/** ❌ BAD: Sorting and serializing every row on every change, on the main thread. */
class SlowHandlerModel(ditto: Ditto) {
    val report = MutableStateFlow("")

    private val observer = ditto.store.registerObserver("SELECT * FROM todos") { result ->
        report.value = result.items.map { it.jsonString() }.sorted().joinToString("\n")
    }

    fun clear() = observer.close()
}

// ANTI-PATTERN 5: One observer per item
/** ❌ BAD: A list of 500 rows creates 500 observers. Observe the list once. */
class TodoRowModel(ditto: Ditto, scope: CoroutineScope, todoId: String) {
    val title: StateFlow<String?> = ditto.store
        .observe("SELECT title FROM todos WHERE _id = :id", mapOf("id" to todoId)) { result ->
            result.items.firstOrNull()?.value?.get("title")?.stringOrNull
        }
        .stateIn(scope, SharingStarted.Eagerly, null)
}

// ANTI-PATTERN 6: Writing to the observed collection
/**
 * ❌ BAD: Each write runs the observer again, which writes again.
 * Comparing with the stored time does not help: each device writes its own, so devices that
 * run this observer keep overwriting each other (guide: Writing from Observers).
 */
class SelfTriggeringModel(ditto: Ditto) {
    private val observer = ditto.store.registerObserver("SELECT * FROM todos") { _ ->
        ditto.store.execute("UPDATE todos SET viewedAt = :now", mapOf("now" to System.currentTimeMillis()))
    }

    fun clear() = observer.close()
}
