// SDK Version: Ditto SDK 5.2.0 (com.ditto:ditto-kotlin 5.2.0)
// Platform: Kotlin (Android)
// Last Updated: 2026-11-06
//
// Observer Backpressure in Kotlin
//
// Guide sections (../../../guide/reference/best-practices/ and knowledge/):
// - § Backpressure (SDK 5.1+)
// - § Backpressure in Kotlin
// - § Choosing an observer API
//
// Every Kotlin observer waits for your code: registerObserver and collect
// deliver the next result only after the suspending handler has returned, and
// the changes in between are merged into the latest state. In testing with SDK
// 5.1.0 and 5.2.0, a handler that suspended for 500 ms during 10 writes 50 ms
// apart was called 3 times, one call at a time, and received the final value.
// The Flow of observe() is one result ahead of a slow collector. There is no
// signalNext().
//
// PATTERNS DEMONSTRATED:
// 1. ✅ collect with a suspending handler (one update at a time)
// 2. ✅ observe + conflate (latest state only)
// 3. ✅ observe + buffer(Channel.RENDEZVOUS) (the producer waits for the collector)
// 4. ✅ Suspending until work that finishes elsewhere reports completion
// 5. ❌ Launching the work from the handler (no backpressure)
// 6. ❌ Blocking the handler's thread (the main thread by default)

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*

fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

// PATTERN 1: collect
/** ✅ GOOD: One update at a time; Ditto holds back the next one until the handler returns. */
class SensorAggregator(private val ditto: Ditto, private val scope: CoroutineScope) {
    private var job: Job? = null

    fun run(deviceId: String, persistAggregates: suspend (List<Double>) -> Unit) {
        stop()
        job = scope.launch {
            ditto.store.collect(
                "SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100",
                mapOf("deviceId" to deviceId),
            ) { result ->
                persistAggregates(result.items.mapNotNull { it.value["value"].numberOrNull() })
            }
        }
    }

    fun stop() {
        job?.cancel() // Cancelling the coroutine removes the observer.
    }
}

// PATTERN 2: observe + conflate
/** ✅ GOOD: A slow consumer gets the latest state, never a queue. */
fun uploadLatestOpenOrders(ditto: Ditto, scope: CoroutineScope, upload: suspend (List<String>) -> Unit): Job =
    scope.launch {
        ditto.store
            .observe("SELECT _id FROM orders WHERE status = :status ORDER BY _id", mapOf("status" to "open")) { result ->
                result.items.map { it.value["_id"].string }
            }
            .conflate()
            .collect { ids ->
                try {
                    upload(ids)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    android.util.Log.e("Orders", "Upload failed; waiting for the next state", error)
                }
            }
    }

// PATTERN 3: observe + buffer(RENDEZVOUS)
/** ✅ GOOD: Every value is handed over before the next one is produced (ordered processing). */
fun processInOrder(ditto: Ditto, scope: CoroutineScope, process: suspend (Int) -> Unit): Job =
    scope.launch {
        ditto.store.observe("SELECT * FROM orders") { it.items.size }
            .buffer(Channel.RENDEZVOUS)
            .collect { count -> process(count) }
    }

// PATTERN 4: Work that finishes elsewhere
/** ✅ GOOD: The handler suspends until an external callback reports that the work is done. */
fun observeWithExternalCompletion(
    ditto: Ditto,
    startWork: (rows: Int, done: () -> Unit) -> Unit,
): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { result ->
        val finished = CompletableDeferred<Unit>()
        startWork(result.items.size) { finished.complete(Unit) }
        finished.await()
    }

// PATTERN 5: No backpressure
/** ❌ BAD: The handler returns at once, so the uploads overlap and queue up. */
fun uploadOnEveryChange(ditto: Ditto, scope: CoroutineScope, upload: suspend (Int) -> Unit): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { result ->
        val count = result.items.size
        scope.launch { upload(count) }
    }

// PATTERN 6: Blocking the handler's thread
/**
 * ❌ BAD: Thread.sleep (or any blocking call) in a handler blocks the thread it
 * runs on, which is the main thread with the default scope of
 * DittoFactory.create. Suspend instead, or switch with withContext.
 */
fun blockingHandler(ditto: Ditto): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { _ ->
        Thread.sleep(500)
    }
