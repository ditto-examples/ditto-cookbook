// Ditto SDK 5.2 (JavaScript, @dittolive/ditto 5.2.0): Attachments are immutable
//
// Once created, an attachment's contents never change. To "edit" a file,
// create a new attachment and point the document at it. The old blob becomes
// eligible for garbage collection once no document on the device references it.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Replace an attachment by updating the token field
// 2. ✅ Replace the attachment and other fields atomically
// 3. ✅ Remove an attachment reference with UNSET
// 4. ❌ Overwriting the source file and expecting the attachment to change
//
// Declare ATTACHMENT fields in every statement that writes them, as below.
//
// Guide: § Attachments in JavaScript, § Attachments Are Immutable

import { writeFile } from 'node:fs/promises';

// ISO-8601 UTC timestamp with exactly millisecond precision.
export const utcTimestamp = (time = new Date()) => time.toISOString();

// PATTERN 1: Replace by updating the token.

// ✅ GOOD: Create a new attachment and point the document at it.
export async function replacePhoto(ditto, photoId, newFilePath) {
  const attachment = await ditto.store.newAttachment(newFilePath, { name: 'receipt-v2.jpg', mimeType: 'image/jpeg' });
  await ditto.store.execute('UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id', {
    id: photoId,
    image: attachment,
  });
}

// PATTERN 2: Replace together with other fields, atomically.

// ✅ GOOD: newAttachment does file I/O, so it runs before the transaction. The
// transaction then only records the new token and the edit history.
export async function replaceSignedContract(ditto, { contractId, signedPdfPath, historyId }) {
  const signed = await ditto.store.newAttachment(signedPdfPath, { name: 'contract-signed.pdf', mimeType: 'application/pdf' });
  await ditto.store.transaction(
    async (tx) => {
      await tx.execute(
        'UPDATE COLLECTION contracts (document ATTACHMENT) SET document = :document, status = :status WHERE _id = :id',
        { id: contractId, document: signed, status: 'signed' },
      );
      await tx.execute('INSERT INTO contractHistory DOCUMENTS (:entry)', {
        entry: { _id: historyId, contractId, event: 'signed', createdAt: utcTimestamp() },
      });
    },
    { hint: 'replaceSignedContract' },
  );
}

// PATTERN 3: Remove the reference.

// ✅ GOOD: The blob becomes eligible for garbage collection once no document on
// the device references it. Declare the field: with DQL_STRICT_MODE = true, an
// undeclared UNSET leaves the attachment unchanged without an error.
export async function removePhoto(ditto, photoId) {
  await ditto.store.execute('UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id', { id: photoId });
}

// ANTI-PATTERN 4: Overwriting the source file.

// ❌ BAD: newAttachment copies the file into Ditto's blob store. Writing new
// bytes to the original path afterwards changes nothing in Ditto: every peer
// still sees the old content.
export async function editSourceFileInPlace(ditto, photoId, filePath, croppedBytes) {
  const attachment = await ditto.store.newAttachment(filePath);
  await ditto.store.execute('INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)', {
    photo: { _id: photoId, image: attachment },
  });
  // Later, the user crops the photo...
  await writeFile(filePath, croppedBytes); // ...but the stored attachment keeps the old bytes.
}
