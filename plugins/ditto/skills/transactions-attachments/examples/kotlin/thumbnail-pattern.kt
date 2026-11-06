// Thumbnails and full-size images in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Store a small thumbnail and the full-size image as two attachments of the
// same document. List rows fetch only the thumbnail; the full-size image is
// fetched when the user opens the photo, with a longer stall timeout.
//
// Guide: § Thumbnail Pattern, § Attachments in Kotlin
//
// 1. ✅ Insert a thumbnail attachment and a full-size attachment together
// 2. ✅ List rows fetch only thumbnails (lazily, one fetch per row)
// 3. ✅ The full-size image is fetched when the user opens the photo,
//       with a longer stall timeout for the larger file

import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import java.io.ByteArrayInputStream
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.concurrent.atomic.AtomicReference
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

private val utcMillis: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

fun utcTimestamp(time: Instant = Instant.now()): String = utcMillis.format(time)

/**
 * ✅ GOOD: The app downscales the image beforehand (for example, with
 * android.graphics.Bitmap) and inserts both attachments in one document.
 */
suspend fun savePhotoWithThumbnail(ditto: Ditto, photoId: String, thumbnailBytes: ByteArray, fullSizePath: String) {
    val thumbnail = ditto.store.newAttachment(
        ByteArrayInputStream(thumbnailBytes),
        mapOf("kind" to "thumbnail", "mimeType" to "image/jpeg"),
    )
    val fullSize = ditto.store.newAttachment(fullSizePath, mapOf("kind" to "full", "mimeType" to "image/jpeg"))
    ditto.store.execute(
        "INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)",
        mapOf(
            "photo" to mapOf(
                "_id" to photoId,
                "thumbnail" to thumbnail,
                "image" to fullSize,
                "createdAt" to utcTimestamp(),
            ),
        ),
    )
}

sealed interface ImageState {
    data object Loading : ImageState
    class Loaded(val bytes: ByteArray) : ImageState
    data object Failed : ImageState
}

/** One fetch with a stall timeout, cancelled with [clear]. */
class ImageLoader(private val ditto: Ditto, private val scope: CoroutineScope) {
    private val _state = MutableStateFlow<ImageState>(ImageState.Loading)
    val state: StateFlow<ImageState> = _state
    private var fetch: Job? = null

    fun load(token: DittoAttachmentToken, stallTimeout: Duration) {
        fetch?.cancel()
        _state.value = ImageState.Loading
        fetch = scope.launch {
            val fetchJob = coroutineContext.job
            val lastProgress = AtomicReference(TimeSource.Monotonic.markNow())
            val watchdog = launch {
                while (true) {
                    delay(minOf(stallTimeout, 1.seconds))
                    if (lastProgress.get().elapsedNow() > stallTimeout) {
                        _state.value = ImageState.Failed
                        fetchJob.cancel()
                    }
                }
            }
            try {
                val result = ditto.store.fetchAttachment(token) { _, _ -> lastProgress.set(TimeSource.Monotonic.markNow()) }
                _state.value = if (result is DittoAttachmentFetchResult.Completed) {
                    ImageState.Loaded(withContext(Dispatchers.IO) { result.attachment.getData() })
                } else {
                    ImageState.Failed
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: DittoException) {
                _state.value = ImageState.Failed
            } finally {
                watchdog.cancel()
            }
        }
    }

    fun clear() {
        fetch?.cancel()
    }
}

/**
 * ✅ GOOD: A row fetches only its thumbnail; the full-size image is fetched when
 * the user opens it, with a longer stall timeout for the larger file.
 */
class PhotoRowModel(ditto: Ditto, scope: CoroutineScope, photo: DittoCborSerializable.Dictionary) {
    private val thumbnailToken = photo["thumbnail"].attachmentTokenOrNull
    private val fullSizeToken = photo["image"].attachmentTokenOrNull

    val thumbnail = ImageLoader(ditto, scope)
    val fullSize = ImageLoader(ditto, scope)

    /** Call when the row is shown. */
    fun onShown() {
        thumbnailToken?.let { thumbnail.load(it, stallTimeout = 30.seconds) }
    }

    /** Call when the user opens the photo. */
    fun onOpened() {
        fullSizeToken?.let { fullSize.load(it, stallTimeout = 2.minutes) }
    }

    /** Call when the row and the detail view are gone. */
    fun clear() {
        thumbnail.clear()
        fullSize.clear()
    }
}
