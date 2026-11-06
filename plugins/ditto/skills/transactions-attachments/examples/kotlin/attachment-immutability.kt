// Attachments are immutable in Ditto SDK 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android).
//
// An attachment never changes after newAttachment. To change a file, create a
// new attachment and point the document's ATTACHMENT field at it; to remove
// it, UNSET the field. The old blob becomes eligible for garbage collection
// once no document references it.
//
// Guide: § Attachments Are Immutable, § Attachments in Kotlin
//
// 1. ✅ Replace an attachment by updating the token field
// 2. ✅ Replace the attachment and other fields atomically
// 3. ✅ Remove an attachment reference with UNSET
// 4. ❌ Overwriting the source file and expecting the attachment to change

import com.ditto.kotlin.*
import java.io.File

/** ✅ GOOD: Create a new attachment and point the document at it. */
suspend fun replacePhoto(ditto: Ditto, photoId: String, newFilePath: String) {
    val attachment = ditto.store.newAttachment(newFilePath, mapOf("name" to "receipt-v2.jpg", "mimeType" to "image/jpeg"))
    ditto.store.execute(
        "UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id",
        mapOf("id" to photoId, "image" to attachment),
    )
}

/**
 * ✅ GOOD: newAttachment copies the file, so it runs before the transaction;
 * the transaction then changes the token and the other fields together.
 */
suspend fun replacePhotoAndCaption(ditto: Ditto, photoId: String, newFilePath: String, caption: String) {
    val attachment = ditto.store.newAttachment(newFilePath, mapOf("name" to File(newFilePath).name))
    ditto.store.transaction(hint = "replacePhotoAndCaption") { tx ->
        tx.execute(
            "UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image, caption = :caption WHERE _id = :id",
            mapOf("id" to photoId, "image" to attachment, "caption" to caption),
        )
        DittoTransaction.Result.Commit(Unit)
    }
}

/** ✅ GOOD: The blob becomes eligible for garbage collection once no document references it. */
suspend fun removePhoto(ditto: Ditto, photoId: String) {
    ditto.store.execute(
        "UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id",
        mapOf("id" to photoId),
    )
}

/**
 * ❌ BAD: newAttachment copies the file into Ditto's blob store. Writing new
 * bytes to the source file afterwards changes nothing in Ditto.
 */
suspend fun editPhotoInPlace(ditto: Ditto, photoId: String, file: File, editedBytes: ByteArray) {
    val attachment = ditto.store.newAttachment(file.absolutePath, mapOf("name" to file.name))
    ditto.store.execute(
        "UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id",
        mapOf("id" to photoId, "image" to attachment),
    )
    file.writeBytes(editedBytes) // the attachment keeps the old bytes
}
// ✅ Fix: create a new attachment from the edited file and replace the token (replacePhoto).
