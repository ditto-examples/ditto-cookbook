// Ditto SDK 5.1 (Flutter, ditto_live 5.1.0): Attachments are immutable
//
// Guide: .claude/guides/best-practices/ditto.md#attachments-are-immutable
//
// Once created, an attachment's contents never change. To "edit" a file,
// create a new attachment and replace the token in the document.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Replace an attachment by updating the token field
// 2. ✅ Replace the attachment and other fields atomically
//       (attachment created BEFORE the transaction)
// 3. ✅ Remove an attachment reference with UNSET
// 4. ❌ Overwriting the source file and expecting the attachment to change
//
// Also avoid keeping old tokens in history documents unless you need the old
// versions: every referenced blob stays on the device.
//
// Deleting and garbage collection:
// - Attachments cannot be deleted directly. Remove the token (UNSET with the
//   ATTACHMENT declaration, or a new token), delete the document with DELETE
//   (for every peer), or evict it from this device with EVICT.
// - On Small Peers, blobs that no document on the device references are
//   garbage-collected automatically every 10 minutes. Garbage collection runs
//   only on Small Peers, not on Ditto Server.

import 'dart:io';

import 'package:ditto_live/ditto_live.dart';

/// ISO-8601 UTC timestamp with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z". Fixed precision keeps values sortable as text
/// (native Dart omits zero microseconds, so even one device would otherwise
/// mix precisions).
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// ============================================================================
// PATTERN 1: Replace by updating the token
// ============================================================================

/// ✅ GOOD: Create a new attachment and point the document at it.
Future<void> replacePhoto(Ditto ditto, String photoId, String newFilePath) async {
  final attachment = await ditto.store.newAttachment(
    newFilePath,
    AttachmentMetadata({'name': 'receipt-v2.jpg', 'mimeType': 'image/jpeg'}),
  );
  await ditto.store.execute(
    'UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id',
    arguments: {'id': photoId, 'image': attachment},
  );
}

// ============================================================================
// PATTERN 2: Replace together with other fields, atomically
// ============================================================================

/// ✅ GOOD: newAttachment does file I/O, so it runs before the transaction.
/// The transaction then only records the new token and the edit history.
Future<void> replaceSignedContract(
  Ditto ditto, {
  required String contractId,
  required String signedPdfPath,
  required String historyId,
}) async {
  final signed = await ditto.store.newAttachment(
    signedPdfPath,
    AttachmentMetadata({'name': 'contract-signed.pdf', 'mimeType': 'application/pdf'}),
  );

  await ditto.store.transaction(hint: 'replaceSignedContract', (tx) async {
    await tx.execute(
      'UPDATE COLLECTION contracts (document ATTACHMENT) '
      'SET document = :document, status = :status WHERE _id = :id',
      arguments: {'id': contractId, 'document': signed, 'status': 'signed'},
    );
    await tx.execute(
      'INSERT INTO contractHistory DOCUMENTS (:entry)',
      arguments: {
        'entry': {
          '_id': historyId,
          'contractId': contractId,
          'event': 'signed',
          'createdAt': utcTimestamp(),
        },
      },
    );
  });
}

// ============================================================================
// PATTERN 3: Remove the reference
// ============================================================================

/// ✅ GOOD: The blob becomes eligible for garbage collection once no document
/// on the device references it. Declare the field: with DQL_STRICT_MODE = true,
/// an undeclared UNSET leaves the attachment unchanged without an error.
Future<void> removePhoto(Ditto ditto, String photoId) async {
  await ditto.store.execute(
    'UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id',
    arguments: {'id': photoId},
  );
}

// ============================================================================
// ANTI-PATTERN 4: Overwriting the source file
// ============================================================================

/// ❌ BAD: newAttachment copies the file into Ditto's blob store. Writing new
/// bytes to the original path afterwards changes nothing in Ditto: every peer
/// still sees the old content.
Future<void> editSourceFileInPlace(Ditto ditto, String photoId, String path) async {
  final attachment = await ditto.store.newAttachment(path);
  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {'_id': photoId, 'image': attachment},
    },
  );

  // Later, the user crops the photo...
  await File(path).writeAsBytes(await _cropped(path));
  // ...but the document still references the original blob.
}

// ✅ Fix: create a new attachment from the edited file and replace the token
// (PATTERN 1).

Future<List<int>> _cropped(String path) async => File(path).readAsBytes();
