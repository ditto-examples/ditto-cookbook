// Attachment loading anti-patterns in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// Every example compiles, but downloads far more than needed, never finishes,
// or keeps fetching after the UI is gone. The corrected versions are in
// attachment-lazy-loading-good.kt and attachment-fetch-timeout.kt.
//
// Guide: § Fetching Attachments, § Attachments in Kotlin
//
// 1. ❌ Treating the token as the file (subscriptions never download blobs)
// 2. ❌ Fetching every attachment as soon as documents sync (eager loading)
// 3. ❌ Starting a new fetch on every bind
// 4. ❌ Fetching in a scope that never ends (GlobalScope), so nothing cancels it
// 5. ❌ A total timeout instead of a stall timeout
// 6. ❌ File bytes stored in a regular field instead of an attachment

import com.ditto.kotlin.*
import java.util.Base64
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * ❌ BAD: A subscription delivers the document with its token, not the blob.
 * The token's metadata says what the file is; its bytes are only on the
 * device after fetchAttachment completes.
 */
suspend fun photoBytesFromDocument(ditto: Ditto, photoId: String): ByteArray? =
    ditto.store.execute("SELECT * FROM photos WHERE _id = :id", mapOf("id" to photoId)) { result ->
        result.items.firstOrNull()?.value?.get("image")?.byteArrayOrNull // a token is not a byte string
    }

/**
 * ❌ BAD: Every observer update starts a fetch for every photo, including
 * photos the user never scrolls to, and repeats the fetches on each update.
 */
fun prefetchEverything(ditto: Ditto, scope: CoroutineScope): Job =
    scope.launch {
        ditto.store.collect("SELECT * FROM COLLECTION photos (image ATTACHMENT)") { result ->
            for (item in result.items) {
                val token = item.value["image"].attachmentTokenOrNull ?: continue
                scope.launch { ditto.store.fetchAttachment(token) }
            }
        }
    }

/**
 * ❌ BAD: bind() runs every time a row is (re)bound, so each bind starts another
 * fetch of the same blob, and none is cancelled.
 */
fun bindPhotoRow(ditto: Ditto, scope: CoroutineScope, token: DittoAttachmentToken, show: (ByteArray) -> Unit) {
    scope.launch {
        val result = ditto.store.fetchAttachment(token)
        if (result is DittoAttachmentFetchResult.Completed) show(result.attachment.getData())
    }
}
// ✅ Fix: one AttachmentLoader per row, started when shown and cleared when hidden.

/** ❌ BAD: GlobalScope never ends, so leaving the screen does not cancel the fetch. */
@OptIn(DelicateCoroutinesApi::class)
fun fetchForever(ditto: Ditto, token: DittoAttachmentToken) {
    GlobalScope.launch { ditto.store.fetchAttachment(token) }
}

/**
 * ❌ BAD: A total timeout gives up on a large file over a slow link even while
 * it makes progress.
 */
suspend fun fetchWithNaiveTimeout(ditto: Ditto, token: DittoAttachmentToken): DittoAttachmentFetchResult? =
    withTimeoutOrNull(30.seconds) { ditto.store.fetchAttachment(token) }
// ✅ Fix: a stall timer that restarts on every progress event (attachment-fetch-timeout.kt).

/**
 * ❌ BAD: The photo is stored as base64 in a regular field. Every edit of the
 * document syncs the whole image again, and documents have a size limit. Use
 * newAttachment and an ATTACHMENT field.
 */
suspend fun savePhotoInline(ditto: Ditto, photoId: String, bytes: ByteArray) {
    ditto.store.execute(
        "INSERT INTO photos DOCUMENTS (:photo)",
        mapOf("photo" to mapOf("_id" to photoId, "imageBase64" to Base64.getEncoder().encodeToString(bytes))),
    )
}
// ✅ Fix: `ditto.store.newAttachment(ByteArrayInputStream(bytes), mapOf("name" to "photo.jpg"))`
