// Lazy attachment loading in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Subscriptions sync documents with attachment tokens; the blobs are fetched
// only when your code calls fetchAttachment. Fetch when the image is shown,
// keep one fetch per token, cancel it when the image goes away, and give up
// after a stall timeout (Ditto has no fetch timeout).
//
// Guide: § Fetching Attachments, § Attachments in Kotlin
//
// 1. ✅ Subscriptions sync tokens only; blobs are fetched explicitly
// 2. ✅ Fetch lazily: a row's loader starts when the row is shown
// 3. ✅ One fetch per loader, cancelled when the row goes away
// 4. ✅ Progress, completion, and deletion as UI state
// 5. ✅ Stall timeout with a retry (Ditto has no fetch timeout)
// 6. ✅ Token metadata (name, size) shown before the download starts

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import java.util.concurrent.atomic.AtomicReference
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

sealed interface AttachmentState {
    data class Loading(val progress: Double?) : AttachmentState
    class Loaded(val bytes: ByteArray) : AttachmentState
    data object Failed : AttachmentState // offer a retry
}

/** ✅ GOOD: Loads one attachment when asked, with a stall timeout. In a ViewModel, pass viewModelScope. */
class AttachmentLoader(private val ditto: Ditto, private val scope: CoroutineScope) {
    private val _state = MutableStateFlow<AttachmentState>(AttachmentState.Loading(null))
    val state: StateFlow<AttachmentState> = _state
    private var fetch: Job? = null

    /** Starts (or restarts) fetching [token]. Call when the image is shown. */
    fun load(token: DittoAttachmentToken, stallTimeout: Duration = 30.seconds) {
        fetch?.cancel() // A new token or a retry replaces the previous fetch.
        _state.value = AttachmentState.Loading(null)
        fetch = scope.launch {
            val fetchJob = coroutineContext.job
            val lastProgress = AtomicReference(TimeSource.Monotonic.markNow())
            val watchdog = launch {
                while (true) {
                    delay(minOf(stallTimeout, 1.seconds))
                    if (lastProgress.get().elapsedNow() > stallTimeout) {
                        _state.value = AttachmentState.Failed
                        fetchJob.cancel() // Stops the fetch.
                    }
                }
            }
            try {
                val result = ditto.store.fetchAttachment(token) { downloaded, total ->
                    lastProgress.set(TimeSource.Monotonic.markNow()) // Progress resets the stall timer.
                    if (total > 0u) _state.value = AttachmentState.Loading(downloaded.toDouble() / total.toDouble())
                }
                _state.value = when (result) {
                    is DittoAttachmentFetchResult.Completed ->
                        AttachmentState.Loaded(withContext(Dispatchers.IO) { result.attachment.getData() })
                    is DittoAttachmentFetchResult.Deleted -> AttachmentState.Failed
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: DittoException) {
                _state.value = AttachmentState.Failed // for example, Ditto was closed
            } finally {
                watchdog.cancel()
            }
        }
    }

    /** Call when the image is no longer shown. Cancels a fetch in progress. */
    fun clear() {
        fetch?.cancel()
    }
}

/** What a row shows before (and while) its image loads: from the token, without downloading. */
data class PhotoRow(val id: String, val name: String?, val sizeBytes: Long?, val token: DittoAttachmentToken?)

/**
 * ✅ GOOD: The observer delivers documents with their tokens. Each row's loader
 * starts when the row is shown and is cleared when the row goes away.
 */
class PhotoListModel(private val ditto: Ditto, private val scope: CoroutineScope) {
    val photos: StateFlow<List<PhotoRow>> = ditto.store
        .observe("SELECT * FROM COLLECTION photos (image ATTACHMENT) ORDER BY createdAt DESC, _id LIMIT 100") { result ->
            result.items.map { item ->
                val token = item.value["image"].attachmentTokenOrNull
                PhotoRow(
                    id = item.value["_id"].string,
                    name = token?.metadata?.get("name")?.stringOrNull,
                    sizeBytes = token?.len?.toLong(),
                    token = token,
                )
            }
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val loaders = mutableMapOf<String, AttachmentLoader>()

    /** Call when a row becomes visible. */
    fun onRowShown(row: PhotoRow): StateFlow<AttachmentState>? {
        val token = row.token ?: return null
        val loader = loaders.getOrPut(row.id) { AttachmentLoader(ditto, scope).also { it.load(token) } }
        return loader.state
    }

    /** Call when a row is recycled or scrolled away. */
    fun onRowHidden(row: PhotoRow) {
        loaders.remove(row.id)?.clear()
    }
}
