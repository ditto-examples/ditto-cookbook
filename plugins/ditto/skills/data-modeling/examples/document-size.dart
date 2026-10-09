// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Document size limits
//
// Limits apply to the size of each stored document:
//   Soft limit 256 KiB (DOCUMENT_SIZE_SOFT_LIMIT_BYTES): write succeeds,
//     warning "exceeds recommended limit" is logged.
//   Hard limit 5 MiB (DOCUMENT_SIZE_HARD_LIMIT_BYTES): INSERT/UPDATE fails,
//     the stored document is unchanged. It is checked only for local writes:
//     concurrent offline additions on two devices can merge into a larger
//     document, after which every UPDATE of it fails until UNSET removes data
//     (SDK 5.1.0).
// Design documents to stay well below 256 KiB; leave both limits at their
// defaults.
//
// Guide: § Document Size Limits

import 'package:ditto_live/ditto_live.dart';

/// Reports an error to the user (replace with your app's error UI).
void showError(Object error) {}

// ---------------------------------------------------------------------------
// ❌ BAD: Unbounded growth and binary data inside a document
// ---------------------------------------------------------------------------

/// ❌ BAD: A nested map that receives a new reading forever. The document
/// eventually exceeds the soft limit and then the hard limit, and merge cost
/// grows with the document, not with the change.
Future<void> appendReadingToDevice(
  Ditto ditto,
  String deviceId,
  String readingId,
  double value,
) async {
  await ditto.store.execute(
    'INSERT INTO devices DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': deviceId,
        'readings': {
          readingId: {
            'value': value,
            'recordedAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
      },
    },
  );
}

/// ❌ BAD: Base64-encoded files in a document field.
Future<void> savePhotoAsBase64(
  Ditto ditto,
  String visitId,
  String base64Jpeg,
) async {
  await ditto.store.execute(
    'UPDATE visits SET photoBase64 = :photo WHERE _id = :id',
    arguments: {'id': visitId, 'photo': base64Jpeg},
  );
}

// ---------------------------------------------------------------------------
// ✅ GOOD: Separate collection, attachments, error handling
// ---------------------------------------------------------------------------

/// ✅ GOOD: Each reading is its own document with a reference to its parent.
Future<void> recordReading(
  Ditto ditto, {
  required String readingId, // a new UUID
  required String deviceId,
  required double value,
}) async {
  await ditto.store.execute(
    'INSERT INTO readings DOCUMENTS (:reading)',
    arguments: {
      'reading': {
        '_id': readingId,
        'deviceId': deviceId,
        'value': value,
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      },
    },
  );
}

/// ✅ GOOD: Binary content goes into an ATTACHMENT field. Attachments are
/// fetched separately and do not count toward the document size.
Future<void> savePhoto(Ditto ditto, String visitId, String filePath) async {
  final attachment = await ditto.store.newAttachment(
    filePath,
    AttachmentMetadata({'name': 'photo.jpg'}),
  );
  await ditto.store.execute(
    'UPDATE COLLECTION visits (photo ATTACHMENT) SET photo = :photo '
    'WHERE _id = :id',
    arguments: {'id': visitId, 'photo': attachment},
  );
}

/// ✅ GOOD: Handle the hard-limit error at the call site that may produce it.
Future<bool> saveNotes(Ditto ditto, String visitId, String notes) async {
  try {
    await ditto.store.execute(
      'UPDATE visits SET notes = :notes WHERE _id = :id',
      arguments: {'id': visitId, 'notes': notes},
    );
    return true;
  } on DittoException catch (error) {
    // The message contains "exceeds limit of ... bytes" for oversized documents.
    showError(error);
    return false;
  }
}

/// ✅ GOOD: Estimate size with object_size(). It returns an
/// approximate size of the value, which can differ from the stored size,
/// so leave headroom.
Future<int?> approximateOrderBytes(Ditto ditto, String orderId) async {
  final result = await ditto.store.execute(
    'SELECT _id, object_size(o) AS approxBytes FROM orders AS o WHERE _id = :id',
    arguments: {'id': orderId},
  );
  if (result.items.isEmpty) return null;
  return (result.items.first.value['approxBytes'] as num?)?.toInt();
}

/// ✅ GOOD: To bring an oversized document back under the limits, remove the
/// data that made it grow: move the nested readings to their own collection
/// and remove them from the device document with UNSET, in one transaction.
Future<void> moveReadingsOut(Ditto ditto, String deviceId) async {
  await ditto.store.transaction(hint: 'moveReadingsOut', (tx) async {
    final result = await tx.execute(
      'SELECT readings FROM devices WHERE _id = :id',
      arguments: {'id': deviceId},
    );
    if (result.items.isEmpty) return;
    final readings =
        (result.items.first.value['readings'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
    final documents = [
      for (final entry in readings.entries)
        {
          ...(entry.value as Map<String, dynamic>),
          '_id': entry.key,
          'deviceId': deviceId,
        },
    ];
    if (documents.isNotEmpty) {
      await tx.execute(
        'INSERT INTO readings DOCUMENTS (:documents) ON ID CONFLICT DO NOTHING',
        arguments: {'documents': documents},
      );
    }
    await tx.execute(
      'UPDATE devices UNSET readings WHERE _id = :id',
      arguments: {'id': deviceId},
    );
  });
}
