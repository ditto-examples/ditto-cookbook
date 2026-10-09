# Flutter Code for Transactions and Attachments (SDK 5.1.0)

Complete Flutter (`ditto_live` 5.1.0) versions of the snippets that [SKILL.md](../SKILL.md) shortens. The rule numbers match SKILL.md. `utcTimestamp()` stands for a fixed-precision timestamp helper (`§ Timestamps` in `../guide/reference/ditto.md`). For widget-level code, see the [examples](../examples/).

## Table of Contents

- [Atomic Multi-Document Change (Rule 1)](#atomic-multi-document-change-rule-1)
- [I/O Before the Transaction (Rule 2)](#io-before-the-transaction-rule-2)
- [Create and Insert an Attachment (Rule 3)](#create-and-insert-an-attachment-rule-3)
- [PhotoLoader: One Fetcher per Token (Rule 4)](#photoloader-one-fetcher-per-token-rule-4)
- [TransactionTracker: Await Before close() (Rule 6)](#transactiontracker-await-before-close-rule-6)
- [Replace an Attachment (Rule 8)](#replace-an-attachment-rule-8)
- [Insert a Thumbnail and a Full-Size Attachment (Rule 10)](#insert-a-thumbnail-and-a-full-size-attachment-rule-10)

---

## Atomic Multi-Document Change (Rule 1)

```dart
// ✅ GOOD: Close an order and create its invoice atomically, using only tx.
Future<void> closeOrderWithInvoice(Ditto ditto, String orderId, String invoiceId) async {
  await ditto.store.transaction(hint: 'closeOrderWithInvoice', (tx) async {
    final result = await tx.execute(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': orderId},
    );
    if (result.items.isEmpty) {
      throw StateError('Order $orderId not found'); // Throwing rolls back.
    }
    final order = result.items.first.value;
    await tx.execute(
      'INSERT INTO invoices DOCUMENTS (:invoice)',
      arguments: {
        'invoice': {
          '_id': invoiceId,
          'orderId': orderId,
          'total': order['total'],
          'createdAt': utcTimestamp(), // Fixed-precision helper (see the guide's Timestamps section).
        },
      },
    );
    await tx.execute(
      'UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'closed', 'invoiceId': invoiceId},
    );
  });
}
```

## I/O Before the Transaction (Rule 2)

```dart
// ✅ GOOD: Do the I/O first, then record the outcome in one short transaction.
Future<void> checkout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await chargeCard(); // Outside the transaction.
  await ditto.store.transaction(hint: 'recordPayment', (tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id',
      arguments: {
        'id': orderId,
        'status': 'paid',
        'paidAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await tx.execute(
      'INSERT INTO payments DOCUMENTS (:payment)',
      arguments: {
        'payment': {'_id': 'payment-$orderId', 'orderId': orderId},
      },
    );
  });
}
```

## Create and Insert an Attachment (Rule 3)

```dart
// ✅ GOOD: Create the attachment, then insert it with a declared ATTACHMENT field.
Future<void> savePhoto(Ditto ditto, String photoId, String filePath) async {
  // The file is copied into Ditto's blob store.
  final attachment = await ditto.store.newAttachment(
    filePath,
    AttachmentMetadata({'name': 'receipt.jpg', 'mimeType': 'image/jpeg'}), // String values only.
  );
  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'image': attachment,
        'createdAt': utcTimestamp(), // Fixed-precision helper (see the guide's Timestamps section).
      },
    },
  );
}
```

## PhotoLoader: One Fetcher per Token (Rule 4)

```dart
// ✅ GOOD: One fetcher per token, owned by the code that displays it.
class PhotoLoader {
  PhotoLoader(this.ditto);

  final Ditto ditto;
  AttachmentFetcher? _fetcher;

  void load(Map<String, dynamic> token, void Function(List<int> bytes) onLoaded) {
    _fetcher?.stop();
    _fetcher = ditto.store.fetchAttachment(token, (event) async {
      switch (event) {
        case AttachmentFetchEventCompleted(:final attachment):
          onLoaded(await attachment.data);
        case AttachmentFetchEventDeleted():
          debugPrint('Attachment was deleted during the fetch');
        default: // AttachmentFetchEvent is not sealed; progress events land here.
          break;
      }
    });
  }

  void dispose() => _fetcher?.stop(); // Cancel if the screen goes away first.
}
```

A complete widget version (generation counter, list rows, progress) is in [../examples/attachment-lazy-loading-good.dart](../examples/attachment-lazy-loading-good.dart).

## TransactionTracker: Await Before close() (Rule 6)

```dart
// ✅ GOOD: Track in-flight transactions so shutdown can wait for them.
class TransactionTracker {
  final _pending = <Future<Object?>>{};

  Future<T> run<T>(Ditto ditto, String hint, Future<T> Function(Transaction tx) work) {
    final future = ditto.store.transaction(hint: hint, work);
    _pending.add(future);
    return future.whenComplete(() => _pending.remove(future));
  }

  Future<void> closeWhenIdle(Ditto ditto) async {
    // Errors are reported to the callers of run(); ignore them here.
    // then() with an onError callback works for any result type T, whereas a
    // catchError handler would have to return a value of type T.
    await Future.wait(_pending.map((f) => f.then<void>((_) {}, onError: (Object _) {})));
    await ditto.close();
  }
}
```

## Replace an Attachment (Rule 8)

```dart
// ✅ GOOD: Replace the attachment by updating the token field.
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
```

## Insert a Thumbnail and a Full-Size Attachment (Rule 10)

```dart
import 'dart:typed_data';

// ✅ GOOD: Insert a thumbnail and a full-size attachment together.
Future<void> savePhotoWithThumbnail(
  Ditto ditto, {
  required String photoId,
  required Uint8List thumbnailBytes, // Downscaled by your app beforehand.
  required String fullSizePath,
}) async {
  final thumbnail = await ditto.store.newAttachment(
    thumbnailBytes,
    AttachmentMetadata({'kind': 'thumbnail', 'mimeType': 'image/jpeg'}),
  );
  final fullSize = await ditto.store.newAttachment(
    fullSizePath,
    AttachmentMetadata({'kind': 'full', 'mimeType': 'image/jpeg'}),
  );
  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'thumbnail': thumbnail,
        'image': fullSize,
        'createdAt': utcTimestamp(), // Fixed-precision helper (see the guide's Timestamps section).
      },
    },
  );
}
```
