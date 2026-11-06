// Observer backpressure in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Every Kotlin observer waits for your code: registerObserver and collect
// deliver the next result only after the suspending handler has returned, and
// the changes in between are merged into the latest state. The Flow of
// observe() runs one result ahead of a slow collector; add conflate() when only
// the latest state matters. There is no signalNext(): to wait for work that
// finishes elsewhere, suspend in the handler until it is done.
//
// | Situation                                     | API                                         |
// |-----------------------------------------------|---------------------------------------------|
// | Updating screen state                         | observe(...) + stateIn in the owner's scope |
// | Slow or async work for each update            | collect(...) with a suspending handler      |
// | Only the latest state matters                 | observe(...).conflate()                     |
// | Work finishes elsewhere (callback, animation) | suspend until it reports completion         |
//
// Guide: § Backpressure (SDK 5.1+), § Backpressure in Kotlin, § Choosing an observer API

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

/** ✅ GOOD: collect with a suspending handler: one update at a time, then the latest state. */
class SensorAggregator(private val ditto: Ditto, private val scope: CoroutineScope) {
    private var job: Job? = null

    fun run(deviceId: String, persistAggregates: suspend (List<Double>) -> Unit) {
        stop() // Cancel a previous run, if any.
        job = scope.launch {
            ditto.store.collect(
                "SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100",
                mapOf("deviceId" to deviceId),
            ) { result ->
                // Copy plain values first; Ditto holds back the next update until this returns.
                persistAggregates(result.items.mapNotNull { it.value["value"].numberOrNull() })
            }
        }
    }

    fun stop() {
        job?.cancel() // Cancelling the coroutine removes the observer.
    }
}

/** ✅ GOOD: Only the latest state matters: a slow consumer never builds a queue. */
fun exportLatestOrderCount(ditto: Ditto, scope: CoroutineScope, writeFile: suspend (Int) -> Unit): Job =
    scope.launch {
        ditto.store.observe("SELECT * FROM orders") { it.items.size }
            .conflate()
            .collect { count ->
                try {
                    writeFile(count)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    android.util.Log.e("Orders", "Export failed; waiting for the next state", error)
                }
            }
    }

/** ✅ GOOD: The work finishes elsewhere: the handler suspends until it reports completion. */
fun observeWithExternalCompletion(
    ditto: Ditto,
    startWork: (rows: Int, done: () -> Unit) -> Unit,
): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { result ->
        val finished = CompletableDeferred<Unit>()
        startWork(result.items.size) { finished.complete(Unit) }
        finished.await() // the next update waits until the work is done
    }

/**
 * ❌ BAD: The handler launches the work and returns at once. Ditto delivers the
 * next result immediately, so the uploads overlap and queue up.
 */
fun uploadWithoutWaiting(ditto: Ditto, scope: CoroutineScope, upload: suspend (Int) -> Unit): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { result ->
        val count = result.items.size
        scope.launch { upload(count) }
    }
