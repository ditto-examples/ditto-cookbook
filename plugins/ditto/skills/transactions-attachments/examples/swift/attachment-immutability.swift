// Ditto SDK 5.2 (Swift, DittoSwift 5.2.0): Attachments are immutable
//
// Guide: § Attachments Are Immutable, § Attachments in Swift
//
// Once created, an attachment's contents never change. To "edit" a file,
// create a new attachment and replace the token in the document.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Replace an attachment by updating the token field
// 2. ✅ Replace the attachment and other fields atomically
//       (the attachment is created BEFORE the transaction)
// 3. ✅ Remove an attachment reference with UNSET
// 4. ❌ Overwriting the source file and expecting the attachment to change
//
// Attachments cannot be deleted directly. Remove the token (UNSET with the
// ATTACHMENT declaration, or a new token), delete the document with DELETE, or
// evict it from this device with EVICT. On Small Peers, blobs that no document
// on the device references are garbage-collected automatically.

import DittoSwift
import Foundation

private func utcTimestamp(_ date: Date = Date()) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
}

/// ✅ GOOD: Create a new attachment and point the document at it.
func replacePhoto(_ ditto: Ditto, photoID: String, newFileURL: URL) async throws {
    let attachment = try await ditto.store.newAttachment(
        path: newFileURL.path, metadata: ["name": newFileURL.lastPathComponent, "mimeType": "image/jpeg"]
    )
    try await ditto.store.execute(
        query: "UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id",
        arguments: ["id": photoID, "image": attachment]
    )
}

/// ✅ GOOD: newAttachment copies the file, so it runs before the transaction;
/// the transaction then swaps the token and updates the other fields atomically.
func replaceSignedContract(_ ditto: Ditto, contractID: String, signedFileURL: URL, signer: String) async throws {
    let signed = try await ditto.store.newAttachment(path: signedFileURL.path, metadata: ["name": "contract-signed.pdf"])
    try await ditto.store.transaction(hint: "replaceSignedContract") { tx in
        try await tx.execute(
            query: "UPDATE COLLECTION contracts (document ATTACHMENT) SET document = :document WHERE _id = :id",
            arguments: ["id": contractID, "document": signed]
        )
        try await tx.execute(
            query: "UPDATE contracts SET status = 'signed', signedBy = :signer, signedAt = :at WHERE _id = :id",
            arguments: ["id": contractID, "signer": signer, "at": utcTimestamp()]
        )
        return .commit
    }
}

/// ✅ GOOD: The blob becomes eligible for garbage collection once no document
/// references it.
func removePhoto(_ ditto: Ditto, photoID: String) async throws {
    try await ditto.store.execute(
        query: "UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id",
        arguments: ["id": photoID]
    )
}

/// ❌ BAD: newAttachment copied the file into Ditto's blob store. Writing new
/// bytes to the original file changes nothing in Ditto, on this device or any
/// other.
func editSourceFileInPlace(_ ditto: Ditto, photoID: String, fileURL: URL, edited: Data) async throws {
    try edited.write(to: fileURL) // the attachment still has the old bytes
}
// ✅ Fix: create a new attachment from the edited file and replace the token
// (replacePhoto above).
