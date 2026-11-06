// Attachment fetch with a stall timeout in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// fetchAttachment suspends until the attachment is available and has no
// timeout of its own: while no peer delivers the blob, it waits without
// progress events. A token whose blob no connected peer has ever had fails at
// once with DittoException.StoreException ("Attachment not found.").
// Cancelling the coroutine that awaits the fetch cancels it.
//
// Guides: § Fetching Attachments
//         § Availability
//         § Attachments in Kotlin
//
// 1. ✅ Stall timeout: a watchdog that measures the time since the last progress
// 2. ✅ Cancel the fetch when the timer fires and report a retryable outcome
// 3. ✅ Longer stall timeouts for larger files (the token's len is known first)
// 4. ✅ Retry on user request instead of failing permanently
// 5. ❌ A total timeout that also gives up on a slow but progressing download

import com.ditto.kotlin.*
import java.util.concurrent.atomic.AtomicReference
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.*

sealed interface FetchOutcome {
    class Loaded(val bytes: ByteArray) : FetchOutcome
    data object Stalled : FetchOutcome // retryable: keep the token and offer a retry
    data object Deleted : FetchOutcome
}

/**
 * ✅ GOOD: Fetches one attachment, gives up after [stallTimeout] without
 * progress, and cancels the fetch when it does.
 */
suspend fun fetchWithStallTimeout(
    ditto: Ditto,
    token: DittoAttachmentToken,
    stallTimeout: Duration,
    onProgress: (Double) -> Unit = {},
): FetchOutcome = coroutineScope {
    val lastProgress = AtomicReference(TimeSource.Monotonic.markNow())
    val fetching = async {
        ditto.store.fetchAttachment(token) { downloaded, total ->
            lastProgress.set(TimeSource.Monotonic.markNow()) // Progress resets the stall timer.
            if (total > 0u) onProgress(downloaded.toDouble() / total.toDouble())
        }
    }
    var result: DittoAttachmentFetchResult? = null
    while (result == null) {
        // Wait for the result, but look at the stall timer at least once a second.
        result = withTimeoutOrNull(minOf(stallTimeout, 1.seconds)) { fetching.await() }
        if (result == null && lastProgress.get().elapsedNow() > stallTimeout) {
            fetching.cancel() // Cancelling the coroutine cancels the fetch.
            return@coroutineScope FetchOutcome.Stalled
        }
    }
    when (result) {
        is DittoAttachmentFetchResult.Completed ->
            FetchOutcome.Loaded(withContext(Dispatchers.IO) { result.attachment.getData() })
        is DittoAttachmentFetchResult.Deleted -> FetchOutcome.Deleted
    }
}

/** ✅ GOOD: The token's len is known before the download starts, so larger files get more time. */
fun stallTimeoutFor(token: DittoAttachmentToken): Duration =
    if (token.len > 5_000_000uL) 2.minutes else 30.seconds

/**
 * ✅ GOOD: A stalled fetch is not an error. Keep the token, show the outcome,
 * and fetch again when the user asks (or when a peer that has the blob appears).
 */
class RetryableAttachment(private val ditto: Ditto, private val token: DittoAttachmentToken) {
    suspend fun load(onProgress: (Double) -> Unit = {}): FetchOutcome =
        fetchWithStallTimeout(ditto, token, stallTimeoutFor(token), onProgress)

    suspend fun retry(): FetchOutcome = load()
}

/**
 * ❌ BAD: A total timeout. A large file over a slow link keeps making progress
 * but is cancelled after 30 seconds every time, so it never finishes.
 */
suspend fun fetchWithTotalTimeout(ditto: Ditto, token: DittoAttachmentToken): ByteArray? =
    withTimeoutOrNull(30.seconds) {
        (ditto.store.fetchAttachment(token) as? DittoAttachmentFetchResult.Completed)?.attachment?.getData()
    }
