---
name: transactions-attachments
description: Validates Ditto transaction usage and attachment operations. Prevents platform-specific bugs like Flutter transaction close() management (must await all transactions before closing Ditto instance), nested transaction deadlocks, and attachment auto-sync assumptions. Enforces lazy-loading patterns, metadata storage, and immutability constraints. Use when implementing transactions, handling attachments, storing large files, or performing atomic multi-step operations.
---

# Ditto Transactions and Attachments

## Purpose

This Skill ensures correct usage of Ditto's transaction API and attachment system across platforms. It prevents critical platform-specific bugs like Flutter transaction close() management and nested transaction deadlocks, while enforcing best practices for binary data handling.

**Critical issues prevented**:
- Flutter transaction close() management (must await all transactions before closing Ditto instance)
- Nested transaction deadlocks (all platforms)
- Attachment auto-sync assumptions (attachments don't sync automatically)
- Attachment immutability violations (trying to modify existing attachments)
- Large binary data stored inline (should use ATTACHMENT type)
- Missing attachment metadata (filename, size, type)

## When This Skill Applies

Use this Skill when:
- Using `ditto.store.transaction()` (all platforms)
- Closing Ditto instance in Flutter (must track and await pending transactions)
- Implementing atomic multi-step operations
- Storing or fetching attachments (`newAttachment()`, `fetchAttachment()`)
- Handling large binary files (photos, documents, videos, media)
- Creating or updating attachment metadata
- Replacing existing attachments
- Implementing thumbnail patterns for large files

## Platform Detection

**Automatic Detection**:
1. **Flutter/Dart**: `*.dart` files with `import 'package:ditto/ditto.dart'` → "Transaction API available with close() limitation"
2. **JavaScript**: `*.js`, `*.ts` files with `import { Ditto } from '@dittolive/ditto'` → Full transaction support
3. **Swift**: `*.swift` files with `import DittoSwift` → Full transaction support
4. **Kotlin**: `*.kt` files with `import live.ditto.*` → Full transaction support

**Platform-Specific Warnings**:
- **Flutter**: Transaction API available, but must manually await all transactions before calling `ditto.close()`
- **All platforms**: Transaction rules, deadlock prevention, read-only mode
- **All platforms**: Attachment patterns (lazy-loading, metadata, immutability)

---

## Critical Patterns

### 1. Flutter Transaction Close Management (Priority: CRITICAL - Flutter Only)

**Platform**: Flutter/Dart only

**Problem**: The Flutter SDK supports `ditto.store.transaction()` but does not wait for pending transactions to complete when closing the Ditto instance. You must manually track and await all transactions before calling `ditto.close()`, or transactions may be incomplete.

**Detection**:
```dart
// RED FLAGS (Flutter only)
// Starting transaction without tracking
unawaited(ditto.store.transaction((tx) async {
  await tx.execute('UPDATE orders SET status = :status ...', ...);
}));

// Closing Ditto immediately without awaiting pending transactions
await ditto.close(); // WRONG! Transaction may be incomplete
```

**✅ DO (Flutter - Track Pending Transactions)**:
```dart
// Track pending transactions with DittoManager
class DittoManager {
  final Ditto ditto;
  final Set<Future<void>> _pendingTransactions = {};

  DittoManager(this.ditto);

  Future<void> executeTransaction(
    Future<void> Function(DittoTransaction) block, {
    String? hint,
    bool isReadOnly = false,
  }) async {
    final transactionFuture = ditto.store.transaction(
      hint: hint,
      isReadOnly: isReadOnly,
      block,
    );

    _pendingTransactions.add(transactionFuture);

    try {
      await transactionFuture;
    } finally {
      _pendingTransactions.remove(transactionFuture);
    }
  }

  Future<void> close() async {
    // ✅ CRITICAL: Wait for all transactions before closing
    await Future.wait(_pendingTransactions);
    await ditto.close();
  }
}

// Usage
final dittoManager = DittoManager(ditto);

await dittoManager.executeTransaction(
  (tx) async {
    final orderResult = await tx.execute(
      'SELECT * FROM orders WHERE _id = :orderId',
      arguments: {'orderId': orderId},
    );

    if (orderResult.items.isEmpty) {
      throw Exception('Order not found');
    }

    final order = orderResult.items.first.value;

    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :orderId',
      arguments: {'orderId': orderId, 'status': 'shipped'},
    );

    await tx.execute(
      'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = :itemId',
      arguments: {'itemId': order['itemId']},
    );
  },
  hint: 'process-order',
);

// Safe close - awaits all transactions
await dittoManager.close();
```

**❌ DON'T (Flutter)**:
```dart
// Close without awaiting transactions
Future<void> cleanup() async {
  // Start transaction without tracking
  unawaited(ditto.store.transaction((tx) async {
    await tx.execute('UPDATE ...');
  }));

  // Close immediately - transaction may be incomplete!
  await ditto.close(); // WRONG!
}

// Use transaction without tracking in production
await ditto.store.transaction((tx) async {
  await tx.execute('UPDATE ...');
});
// If app closes before completion, transaction may be incomplete
```

**Why**: Flutter SDK supports transactions but does not wait for them to complete when closing. Closing Ditto without awaiting pending transactions can result in incomplete operations, data loss, or corruption. You must manually track pending transactions and await them before closing.

**See**: [examples/flutter-transaction-close-management.dart](examples/flutter-transaction-close-management.dart)

---

### 2. Nested Read-Write Transaction Deadlock (Priority: CRITICAL - All Platforms)

**Platform**: All platforms (Flutter, JavaScript, Swift, Kotlin)

**Problem**: Nesting read-write transactions creates permanent deadlock where inner transaction waits for outer, outer waits for inner. Only one read-write transaction executes at a time.

**Detection**:
```javascript
// RED FLAGS (all platforms)
await ditto.store.transaction(async (outerTx) => {
  await outerTx.execute('UPDATE orders SET status = $args.status ...', ...);

  // DEADLOCK: Nested transaction waits for outer
  await ditto.store.transaction(async (innerTx) => {
    await innerTx.execute('UPDATE inventory ...', ...);
  });
  // Outer transaction waits for inner, inner waits for outer = deadlock
});
```

**✅ DO (All Platforms)**:
```javascript
// Single transaction for related operations
await ditto.store.transaction({ hint: 'process-order' }, async (tx) => {
  // All statements see the same data snapshot
  const orderResult = await tx.execute(
    'SELECT * FROM orders WHERE _id = $args.orderId',
    { args: { orderId: 'order_123' } }
  );

  if (orderResult.items.length === 0) {
    throw new Error('Order not found');
  }

  const order = orderResult.items[0].value;

  // Update order status
  await tx.execute(
    'UPDATE orders SET status = $args.status WHERE _id = $args.orderId',
    { args: { orderId: 'order_123', status: 'shipped' } }
  );

  // Decrement inventory
  await tx.execute(
    'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = $args.itemId',
    { args: { itemId: order.itemId } }
  );

  return; // Automatic commit
});

// Separate transactions if independence needed
await ditto.store.transaction({ hint: 'update-order' }, async (tx) => {
  await tx.execute('UPDATE orders ...', ...);
});

await ditto.store.transaction({ hint: 'update-inventory' }, async (tx) => {
  await tx.execute('UPDATE inventory ...', ...);
});
```

**❌ DON'T (All Platforms)**:
```javascript
// Nested read-write transactions (DEADLOCK!)
await ditto.store.transaction(async (outerTx) => {
  await ditto.store.transaction(async (innerTx) => {
    // Permanent deadlock
  });
});

// Using ditto.store instead of tx inside transaction
await ditto.store.transaction(async (tx) => {
  await ditto.store.execute('UPDATE orders ...', ...); // WRONG - bypasses transaction
  await tx.execute('UPDATE inventory ...', ...);
});

// Long-running transactions blocking others
await ditto.store.transaction(async (tx) => {
  await tx.execute('UPDATE orders ...', ...);
  await heavyComputation(); // Blocks other read-write transactions!
  await tx.execute('UPDATE inventory ...', ...);
});
```

**Why**: Only one read-write transaction executes at a time in Ditto. Nesting creates circular dependency: outer waits for inner to complete, inner waits for outer's lock to release. Keep transactions fast, don't nest, use transaction object (`tx`) not `ditto.store`.

**Transaction Duration Warnings**: Ditto logs warnings after 10 seconds, escalating every 5 seconds.

**See**: [examples/transaction-good.js](examples/transaction-good.js), [examples/transaction-bad.js](examples/transaction-bad.js)

---

### 3. Attachment Auto-Sync Assumption (Priority: CRITICAL)

**Platform**: All platforms

**Problem**: Attachments do NOT sync automatically with subscriptions. Explicit `fetchAttachment()` calls are required after querying documents.

**How Attachments Work**:
- Documents contain attachment tokens (references)
- Tokens sync with subscriptions
- **Blob data does NOT sync automatically**
- Must explicitly call `fetchAttachment(token)` to get blob

**Detection**:
```dart
// RED FLAGS
final result = await ditto.store.execute('SELECT * FROM products WHERE _id = :id',
  arguments: {'id': productId});

final product = result.items.first.value;
final attachmentToken = product['imageAttachment'];

// Attempting to use token directly
displayImage(attachmentToken); // WRONG - token is not image data!

// Assuming subscription fetches blobs
final subscription = ditto.sync.registerSubscription('SELECT * FROM products');
// Only tokens sync, not blob data
```

**✅ DO**:
```dart
// Query document to get attachment token
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE _id = :id',
  arguments: {'id': productId},
);

if (result.items.isNotEmpty) {
  final product = result.items.first.value;
  final attachmentToken = product['imageAttachment'];
  final metadata = product['imageMetadata'];

  if (attachmentToken != null) {
    try {
      // Explicitly fetch attachment blob
      final attachment = await ditto.store.fetchAttachment(attachmentToken);
      displayImage(attachment.data, metadata);
    } catch (e) {
      // Handle fetch failure (network error, missing blob, etc.)
      showError('Failed to load image: $e');
    }
  }
}

// Alternative: Stream-based fetching with progress
final fetcher = ditto.store.fetchAttachment(attachmentToken, (event) {
  if (event is AttachmentFetchEventProgress) {
    updateProgress(event.downloadedBytes, event.totalBytes);
  } else if (event is AttachmentFetchEventCompleted) {
    displayImage(event.attachment.data);
  } else if (event is AttachmentFetchEventDeleted) {
    showError('Attachment deleted during fetch');
  }
});
```

**❌ DON'T**:
```dart
// Assume subscription fetches blobs automatically
final subscription = ditto.sync.registerSubscription('SELECT * FROM products');
// Only tokens sync!

// Display token directly
final token = product['imageAttachment'];
displayImage(token); // Token is not image data

// No error handling for fetch failures
final attachment = await ditto.store.fetchAttachment(token);
displayImage(attachment.data); // May throw if network fails
```

**Why**: Attachments use separate blob sync protocol from document sync. Automatic syncing would waste bandwidth for large files users may not need. Lazy-loading gives apps control over when to fetch blobs.

**Attachment Architecture**:
- **Metadata**: Stored with document (filename, size, type, description)
- **Blob Data**: Stored externally, fetched on demand
- **Tokens**: References to blobs, sync with documents

**See**: [examples/attachment-lazy-loading-good.dart](examples/attachment-lazy-loading-good.dart)

---

### 4. Attachment Immutability Violation (Priority: HIGH)

**Platform**: All platforms

**Problem**: Attachments are immutable once created. Attempting to modify existing attachments fails. Must create new attachment and replace token in document.

**Detection**:
```dart
// RED FLAGS
// Attempting to update existing attachment
await ditto.store.updateAttachment(existingToken, newImageBytes);
// No such method - attachments are immutable!

// Trying to change attachment without new token
await ditto.store.execute(
  'UPDATE products SET imageAttachment = :newData WHERE _id = :id',
  arguments: {'newData': newImageBytes, 'id': productId},
);
// Won't work - must create new attachment first
```

**✅ DO**:
```dart
// Create new attachment
final newImageBytes = await File('new_image.jpg').readAsBytes();
final newToken = await ditto.store.newAttachment(
  newImageBytes,
  metadata: {
    'filename': 'new_image.jpg',
    'mime_type': 'image/jpeg',
  },
);

// Replace token in document using UPDATE
await ditto.store.execute(
  'UPDATE products SET imageAttachment = :token, imageMetadata = :metadata WHERE _id = :id',
  arguments: {
    'token': newToken,
    'metadata': {
      'filename': 'new_image.jpg',
      'size': newImageBytes.length,
      'type': 'image/jpeg',
      'updatedAt': DateTime.now().toIso8601String(),
    },
    'id': productId,
  },
);

// Old attachment automatically garbage collected if unreferenced
// Garbage collection runs on 10-minute cadence on Small Peers
```

**❌ DON'T**:
```dart
// Try to modify existing attachment
existingToken.data = newBytes; // Immutable!

// Replace token without creating new attachment
await ditto.store.execute(
  'UPDATE products SET imageAttachment = :data WHERE _id = :id',
  arguments: {'data': newBytes, 'id': productId},
);
// Must create attachment first with newAttachment()

// Keep source files without cleanup strategy
await ditto.store.newAttachment(imageBytes);
// Source file still exists - may want to delete to avoid duplication
```

**Why**: Attachments are immutable for data integrity and caching efficiency. To update, create new attachment and replace token. Ditto automatically garbage collects unreferenced attachments on 10-minute cadence.

**Garbage Collection**:
- Small Peers run GC every 10 minutes
- Unreferenced attachments removed automatically
- No manual cleanup required

**See**: [examples/attachment-immutability.dart](examples/attachment-immutability.dart)

---

### 5. Missing Attachment Metadata (Priority: HIGH)

**Platform**: All platforms

**Problem**: Storing attachments without descriptive metadata (filename, size, type) makes efficient fetching and UI display difficult.

**Detection**:
```dart
// RED FLAGS
// Creating attachment without metadata
final token = await ditto.store.newAttachment(imageBytes);

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageAttachment': token, // Token only, no metadata
    },
  },
);

// No metadata for UI display before fetch
// Can't show "image.jpg (2.5 MB)" without fetching blob
```

**✅ DO**:
```dart
// Create attachment with metadata parameter
final imageFile = File('product_photo.jpg');
final imageBytes = await imageFile.readAsBytes();

final token = await ditto.store.newAttachment(
  imageBytes,
  metadata: {
    'filename': 'product_photo.jpg',
    'mime_type': 'image/jpeg',
  },
);

// Store both token and descriptive metadata in document
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageAttachment': token,
      'imageMetadata': {
        'filename': 'product_photo.jpg',
        'size': imageBytes.length,
        'type': 'image/jpeg',
        'description': 'Product photo taken at store',
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    },
  },
);

// UI can display metadata before fetching blob
// "product_photo.jpg (2.5 MB) - Product photo taken at store"
```

**❌ DON'T**:
```dart
// Omit metadata parameter
final token = await ditto.store.newAttachment(bytes);
// Lost opportunity to store metadata at creation time

// Omit document metadata
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageAttachment': token, // No descriptive metadata
    },
  },
);
// Can't show filename, size, or type without fetching blob
```

**Why**: Metadata enables efficient UI display (filename, size, type) before fetching potentially large blobs. The `metadata` parameter in `newAttachment()` stores metadata alongside the blob. Document metadata provides context for app logic.

**Metadata Uses**:
- Display filename and size before fetch
- Determine if auto-fetch based on size
- Show upload date, description
- Filter by file type

**See**: [examples/attachment-lazy-loading-good.dart](examples/attachment-lazy-loading-good.dart)

---

### 6. Inline Binary Data Storage (Priority: HIGH)

**Platform**: All platforms

**Problem**: Storing large binary data directly in documents bloats document size, causes sync performance issues, and hits document size limits (5 MB max).

**Detection**:
```dart
// RED FLAGS
// Base64 encoding large image in document
final base64Image = base64Encode(imageBytes);
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageData': base64Image, // Bloats document size!
    },
  },
);

// Storing byte array directly
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'photoBytes': imageBytes, // Large binary data inline
    },
  },
);
```

**✅ DO**:
```dart
// Use ATTACHMENT type for binary data > 250 KB
final imageBytes = await File('photo.jpg').readAsBytes();

// Create attachment
final attachmentToken = await ditto.store.newAttachment(
  imageBytes,
  metadata: {
    'filename': 'photo.jpg',
    'mime_type': 'image/jpeg',
  },
);

// Store token (small) in document, not binary data
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageAttachment': attachmentToken, // Token is small
      'imageMetadata': {
        'filename': 'photo.jpg',
        'size': imageBytes.length,
      },
    },
  },
);

// Small data (< 1 KB) can be inline
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'thumbnailBase64': base64ThumbnailSmall, // < 1 KB OK
    },
  },
);
```

**❌ DON'T**:
```dart
// Store large binary data inline
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'photoData': base64EncodedLargeImage, // 5 MB bloats document
    },
  },
);
// Performance issues, may exceed 5 MB document limit

// Store multiple large files inline
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'photo1': largeImage1,
      'photo2': largeImage2,
      'photo3': largeImage3, // Document too large
    },
  },
);
```

**Why**: Documents have 5 MB hard limit (won't sync if exceeded), 250 KB soft limit (performance warnings). Large binary data should use ATTACHMENT type for efficient storage and lazy-loading. Inline storage bloats documents, slows queries, wastes bandwidth.

**Size Guidelines**:
- < 1 KB: Inline OK (small thumbnails, icons)
- 1 KB - 250 KB: Consider ATTACHMENT
- > 250 KB: **Must use ATTACHMENT**
- > 5 MB: Won't sync

**See**: [examples/thumbnail-pattern.dart](examples/thumbnail-pattern.dart)

---

### 7. Attachment Fetcher Cancellation (Priority: HIGH)

**Platform**: All platforms

**Problem**: Canceling attachment fetchers before completion wastes resources and prevents blob retrieval.

**Detection**:
```dart
// RED FLAGS
final fetcher = ditto.store.fetchAttachment(token, (event) {
  // Handle events
});

// Canceling too early
fetcher.cancel(); // Cancelled before completion!

// Not keeping fetcher reference
ditto.store.fetchAttachment(token, (event) {
  // No reference - can't cancel if needed
});
```

**✅ DO**:
```dart
// Keep fetcher reference until completion
AttachmentFetcher? currentFetcher;

void fetchProductImage(String productId) {
  final fetcher = ditto.store.fetchAttachment(attachmentToken, (event) {
    if (event is AttachmentFetchEventProgress) {
      updateProgress(event.downloadedBytes, event.totalBytes);
    } else if (event is AttachmentFetchEventCompleted) {
      displayImage(event.attachment.data);
      currentFetcher = null; // Clear reference on completion
    } else if (event is AttachmentFetchEventDeleted) {
      showError('Attachment deleted');
      currentFetcher = null;
    }
  });

  currentFetcher = fetcher; // Keep reference
}

// Cancel only when necessary (screen navigation, user cancels)
void onScreenDispose() {
  currentFetcher?.cancel();
  currentFetcher = null;
}

// Future-based fetch keeps fetcher alive internally
Future<Attachment> fetchAttachmentAsync(AttachmentToken token) async {
  final completer = Completer<Attachment>();

  final fetcher = ditto.store.fetchAttachment(token, (event) {
    if (event is AttachmentFetchEventCompleted) {
      completer.complete(event.attachment);
    } else if (event is AttachmentFetchEventDeleted) {
      completer.completeError('Attachment deleted');
    }
  });

  return completer.future;
}
```

**❌ DON'T**:
```dart
// Cancel immediately
final fetcher = ditto.store.fetchAttachment(token, callback);
fetcher.cancel(); // Too early!

// No fetcher reference for cleanup
void fetchImage() {
  ditto.store.fetchAttachment(token, (event) {
    // No way to cancel if user navigates away
  });
}

// Cancel all fetchers without checking completion
void onDispose() {
  for (var fetcher in allFetchers) {
    fetcher.cancel(); // May cancel in-progress fetches
  }
}
```

**Why**: Attachment fetchers must remain active until completion or explicit cancellation. Canceling too early prevents blob retrieval. Keep fetcher references for proper lifecycle management and cancellation on screen disposal.

**See**: [examples/attachment-fetch-timeout.dart](examples/attachment-fetch-timeout.dart)

---

### 8. Thumbnail-First Pattern for Large Files (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Syncing large files (photos, videos) over bandwidth-constrained mesh networks (Bluetooth LE) blocks critical data. A 5 MB photo takes ~6 minutes over Bluetooth LE at 100 Kbps.

**Solution**: Store two attachments per file:
1. **Thumbnail** (~50 KB): Auto-fetch, provides immediate preview
2. **Full resolution** (~5 MB): On-demand fetch when user requests

**Detection**:
```dart
// SUBOPTIMAL: Single large attachment
final largeImageToken = await ditto.store.newAttachment(fullResolutionBytes);
// All peers must fetch 5 MB for preview
```

**✅ DO**:
```dart
// Generate thumbnail (resize to 200x200, quality 70%)
final thumbnailData = await generateThumbnail(imageData);

// Create both attachments
final thumbnailToken = await ditto.store.newAttachment(
  thumbnailData,
  metadata: {'name': 'photo_thumb.jpg', 'mime_type': 'image/jpeg'},
);

final fullResToken = await ditto.store.newAttachment(
  imageData,
  metadata: {'name': 'photo_full.jpg', 'mime_type': 'image/jpeg'},
);

// Insert document with BOTH attachment tokens
await ditto.store.execute(
  'INSERT INTO photos DOCUMENTS (:photo)',
  arguments: {
    'photo': {
      '_id': photoId,
      'caption': caption,
      'thumbnail': thumbnailToken,
      'full_resolution': fullResToken,
      'created_at': DateTime.now().toIso8601String(),
    },
  },
);

// Size-based auto-download strategy
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM photos ORDER BY created_at DESC',
  onChange: (result, signalNext) {
    for (final item in result.items) {
      final photo = item.value;
      final thumbnailToken = photo['thumbnail'];
      final thumbnailSize = thumbnailToken['len'];

      // Auto-fetch thumbnails if small enough (< 100 KB)
      if (thumbnailSize < 100 * 1024 && !_alreadyFetched(thumbnailToken)) {
        ditto.store.fetchAttachment(thumbnailToken, (event) {
          if (event is AttachmentFetchEventCompleted) {
            updateThumbnailInUI(photo['_id'], event.attachment);
          }
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
);

// User-initiated full resolution download
Future<void> downloadFullResolution(String photoId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM photos WHERE _id = :id',
    arguments: {'id': photoId},
  );

  final fullResToken = result.items.first.value['full_resolution'];

  ditto.store.fetchAttachment(fullResToken, (event) {
    if (event is AttachmentFetchEventProgress) {
      updateDownloadProgress(event.downloadedBytes, event.totalBytes);
    } else if (event is AttachmentFetchEventCompleted) {
      displayFullResolutionImage(event.attachment);
    }
  });
}
```

**❌ DON'T**:
```dart
// Single large attachment
final token = await ditto.store.newAttachment(fullResImage);
// Blocks mesh with large file

// Auto-fetch full resolution for all photos
for (var photo in photos) {
  ditto.store.fetchAttachment(photo['full_resolution'], ...);
  // Wastes bandwidth, battery
}
```

**Why**: Bluetooth LE transfer at ~20 KB/s means 5 MB takes 250 seconds. Thumbnail-first provides immediate preview (50 KB = 2.5 seconds), full resolution on-demand. Reduces mesh congestion, improves UX.

**Benefits**:

| Metric | Full Resolution Only | Thumbnail + On-Demand |
|--------|----------------------|-----------------------|
| Initial sync | 5 MB | 50 KB |
| Time over BLE | ~6 minutes | ~4 seconds |
| User feedback | Delayed | Immediate |
| Mesh impact | High | Minimal |

**See**: [examples/thumbnail-pattern.dart](examples/thumbnail-pattern.dart)

---

### 9. Transaction Duration Violations (Priority: MEDIUM - Non-Flutter)

**Platform**: Non-Flutter only (JavaScript, Swift, Kotlin)

**Problem**: Long-running transactions block all other read-write transactions. Keep transaction blocks minimal and fast (milliseconds, not seconds).

**Detection**:
```javascript
// RED FLAGS (non-Flutter platforms)
await ditto.store.transaction(async (tx) => {
  await tx.execute('UPDATE orders ...', ...);

  // Heavy computation inside transaction
  const complexResult = await performExpensiveAnalysis(data);
  const reportData = await generateDetailedReport(complexResult);
  await sendToAnalyticsService(reportData); // Network call!

  await tx.execute('UPDATE inventory ...', ...);
  // Long-running transaction blocks other operations
});
```

**✅ DO (All Platforms)**:
```javascript
// Move heavy operations outside transaction
const analysisData = await performExpensiveAnalysis(data);
const reportData = await generateDetailedReport(analysisData);

// Fast transaction block (milliseconds)
await ditto.store.transaction({ hint: 'process-order' }, async (tx) => {
  await tx.execute('UPDATE orders SET status = $args.status ...', ...);
  await tx.execute('UPDATE inventory ...', ...);
  return; // Complete quickly
});

// Send report after transaction completes
await sendToAnalyticsService(reportData);

// Use read-only transactions when mutation not needed
await ditto.store.transaction(
  { hint: 'read-summary', isReadOnly: true },
  async (tx) => {
    const orders = await tx.execute('SELECT * FROM orders', {});
    const items = await tx.execute('SELECT * FROM order_items', {});
    return calculateSummary(orders, items);
  }
);
// Read-only transactions allow concurrency
```

**❌ DON'T (All Platforms)**:
```javascript
// Long-running operations inside transaction
await ditto.store.transaction(async (tx) => {
  await tx.execute('UPDATE orders ...', ...);
  await heavyComputation(); // Blocks other transactions!
  await networkCall(); // Blocks other transactions!
  await tx.execute('UPDATE inventory ...', ...);
});

// No hint parameter for debugging
await ditto.store.transaction(async (tx) => {
  // No hint - harder to debug warnings
});
```

**Why**: Only one read-write transaction executes at a time. Long-running transactions block all other read-write operations. Ditto logs warnings after 10 seconds, escalating every 5 seconds. Keep transactions fast (< 100ms ideal).

**Performance Guidelines**:
- Complete in milliseconds, not seconds
- Move heavy computation outside transaction blocks
- Use read-only mode when possible
- Provide descriptive hint parameters

**See**: [examples/transaction-good.js](examples/transaction-good.js)

---

### 10. Attachment Fetch Timeout Handling (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Attachment fetches can stall indefinitely if all sources disconnect. No error is raised, but fetch never completes.

**Ditto Behavior**:
- Progress preserved across interruptions
- Multiple sources can continue fetch
- **No error on stall** - fetch simply stops progressing

**Detection**:
```dart
// RED FLAGS
final fetcher = ditto.store.fetchAttachment(token, (event) {
  // No timeout detection
});
// May stall indefinitely if sources disconnect
```

**✅ DO**:
```dart
// Timeout wrapper for attachment fetch
Future<Attachment> fetchAttachmentWithTimeout(
  AttachmentToken token,
  Duration timeout,
) async {
  final completer = Completer<Attachment>();
  DateTime lastProgress = DateTime.now();
  Timer? timer;
  AttachmentFetcher? fetcher;

  timer = Timer.periodic(Duration(seconds: 5), (t) {
    if (DateTime.now().difference(lastProgress) > timeout) {
      t.cancel();
      fetcher?.cancel();
      completer.completeError(
        'Fetch stalled: no progress for ${timeout.inSeconds}s'
      );
    }
  });

  fetcher = ditto.store.fetchAttachment(token, (event) {
    lastProgress = DateTime.now();
    if (event is AttachmentFetchEventCompleted) {
      timer?.cancel();
      completer.complete(event.attachment);
    } else if (event is AttachmentFetchEventDeleted) {
      timer?.cancel();
      completer.completeError('Attachment deleted during fetch');
    }
  });

  return completer.future;
}

// Usage
try {
  final attachment = await fetchAttachmentWithTimeout(
    token,
    Duration(minutes: 5),
  );
  displayImage(attachment.data);
} catch (e) {
  showError('Download failed: $e');
}
```

**❌ DON'T**:
```dart
// No timeout detection
final fetcher = ditto.store.fetchAttachment(token, callback);
// Stalls indefinitely if sources disconnect

// Too short timeout
await fetchAttachmentWithTimeout(token, Duration(seconds: 5));
// Large attachments legitimately take longer

// Blocking wait without timeout
await Future.delayed(Duration(minutes: 10));
final attachment = await fetchAttachment(token);
// No guarantee fetch completes in 10 minutes
```

**Why**: Stalled fetches tie up resources indefinitely. Timeout detection allows retry, user notification, or graceful abandonment. Choose timeout based on expected file size and network conditions (5-10 minutes reasonable).

**See**: [examples/attachment-fetch-timeout.dart](examples/attachment-fetch-timeout.dart)

---

### 11. Attachment Availability Constraints (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Attachments can only be fetched from immediate peers (directly connected devices) that have already fetched the attachment themselves. Multi-hop relay doesn't work for attachments.

**Scenario**:
```
Device A (has full res) ← connected → Device B (has thumbnail only) ← connected → Device C (wants full res)
```

In this mesh:
- Device C **cannot** fetch full resolution from Device A (not directly connected)
- Device C can only fetch from Device B (directly connected)
- Device B must first fetch full resolution before C can access it

**Detection**:
```dart
// SUBOPTIMAL: Assuming multi-hop attachment sync
// Device C attempts to fetch from Device A (not directly connected)
// Fetch stalls because Device B doesn't have full resolution
```

**✅ DO**:
```dart
// Show attachment availability in UI
Future<void> checkAttachmentAvailability(String photoId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM photos WHERE _id = :id',
    arguments: {'id': photoId},
  );

  final fullResToken = result.items.first.value['full_resolution'];

  // Check how many directly connected peers have this attachment
  final peerCount = ditto.store.getAttachmentPeerCount(fullResToken);

  if (peerCount == 0) {
    showUI('Full resolution not available yet');
    // Retry later or show as unavailable
  } else {
    showUI('Available from $peerCount peer(s) - Download now?');
  }
}

// Implement retry logic when attachments become available
Future<void> fetchWithRetry(AttachmentToken token) async {
  int retries = 0;
  const maxRetries = 3;

  while (retries < maxRetries) {
    try {
      final attachment = await fetchAttachmentWithTimeout(token, Duration(minutes: 2));
      return displayImage(attachment.data);
    } catch (e) {
      retries++;
      if (retries < maxRetries) {
        await Future.delayed(Duration(seconds: 30)); // Wait before retry
      } else {
        showError('Attachment unavailable after $maxRetries attempts');
      }
    }
  }
}
```

**❌ DON'T**:
```dart
// Assume multi-hop attachment relay
// Device C: "I'll get full res from Device A through Device B"
// Won't work - must fetch from direct peers only

// No availability check before fetch
final attachment = await ditto.store.fetchAttachment(token);
// May stall if no direct peers have the attachment
```

**Why**: Attachment availability limited to immediate peers that have fetched the blob. Multi-hop doesn't work for attachments (only for documents). Show availability status in UI, implement retry logic.

**Mitigation Strategies**:
- Use thumbnails to reduce impact
- Relay/hub devices always fetch attachments
- Show availability status in UI
- Implement retry logic

---

### 12. Garbage Collection Awareness (Priority: LOW)

**Platform**: All platforms

**Problem**: Understanding when attachments are garbage collected prevents confusion about storage usage.

**How It Works**:
- Small Peers run GC on 10-minute cadence
- Unreferenced attachments automatically removed
- No manual cleanup required

**Detection**:
```dart
// CONFUSION: Where did my attachment go?
final token = await ditto.store.newAttachment(bytes);
// Don't store token in any document
// After 10 minutes, attachment garbage collected
```

**✅ DO**:
```dart
// Store token in document to prevent GC
final token = await ditto.store.newAttachment(bytes);

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageAttachment': token, // Referenced - won't be GC'd
    },
  },
);

// When ready to delete, remove reference
await ditto.store.execute(
  'UPDATE products SET imageAttachment = NULL WHERE _id = :id',
  arguments: {'id': productId},
);
// Attachment GC'd after 10-minute cadence

// Optional: Delete source file after creating attachment
await ditto.store.newAttachment(imageBytes);
await imageFile.delete(); // Avoid storage duplication
// Keep source if: app needs quick access, maintaining backups
```

**❌ DON'T**:
```dart
// Create attachment without storing reference
final token = await ditto.store.newAttachment(bytes);
// GC'd after 10 minutes if not stored in document

// Manual cleanup attempts
// No API for manual attachment deletion - GC handles it

// Keep all source files indefinitely
// Storage duplication - attachments + source files
```

**Why**: Automatic GC removes unreferenced attachments, freeing storage. No manual cleanup needed. Store token in document to keep attachment alive. GC runs every 10 minutes on Small Peers.

---

## Quick Reference Checklist

### Transactions (Non-Flutter Only)
- [ ] Never nest read-write transactions (causes deadlock)
- [ ] Use transaction object (`tx`) not `ditto.store` inside transaction
- [ ] Keep transaction blocks fast (< 100ms ideal, < 1s acceptable)
- [ ] Move heavy computation outside transaction blocks
- [ ] Use read-only transactions when mutation not needed
- [ ] Provide descriptive hint parameters for debugging

### Flutter Alternatives (Flutter Only)
- [ ] Use sequential DQL statements (no transaction API)
- [ ] Handle errors without automatic rollback
- [ ] Use status flags to track multi-step operations
- [ ] Consider logical deletion for safer data management

### Attachment Operations (All Platforms)
- [ ] Call `fetchAttachment()` explicitly (attachments don't auto-sync)
- [ ] Store metadata with attachments (filename, size, type)
- [ ] Create new attachment for updates (attachments immutable)
- [ ] Replace token in document using UPDATE
- [ ] Use ATTACHMENT type for binary data > 250 KB
- [ ] Keep fetcher references until completion or cancellation
- [ ] Implement timeout wrappers for fetch operations

### Large File Handling (All Platforms)
- [ ] Use thumbnail-first pattern for photos/videos
- [ ] Auto-fetch small attachments (< 100 KB)
- [ ] User-initiated fetch for full resolution
- [ ] Show attachment availability status in UI
- [ ] Implement retry logic for failed fetches

### Attachment Lifecycle (All Platforms)
- [ ] Store token in document to prevent GC
- [ ] Understand 10-minute GC cadence
- [ ] Delete source files after creating attachments (optional)
- [ ] Check attachment availability before fetch
- [ ] Handle fetch failures gracefully (network errors, missing blob)

---

## See Also

### Main Guide
- Attachments: [.claude/guides/best-practices/ditto.md lines 2514-2850](../../guides/best-practices/ditto.md)
- Transactions: [.claude/guides/best-practices/ditto.md lines 2851-3000](../../guides/best-practices/ditto.md)
- Thumbnail Pattern: [.claude/guides/best-practices/ditto.md lines 2652-2753](../../guides/best-practices/ditto.md)
- Flutter Limitation: [.claude/guides/best-practices/ditto.md lines 2857-2860, 2948-2983](../../guides/best-practices/ditto.md)

### Other Skills
- [query-sync](../query-sync/SKILL.md) - Subscription and observer patterns
- [storage-lifecycle](../storage-lifecycle/SKILL.md) - Attachment garbage collection
- [data-modeling](../data-modeling/SKILL.md) - ATTACHMENT type in document schema

### Examples
- [examples/flutter-sequential-operations.dart](examples/flutter-sequential-operations.dart) - Flutter alternative pattern
- [examples/transaction-good.js](examples/transaction-good.js) - Proper transaction usage (non-Flutter)
- [examples/transaction-bad.js](examples/transaction-bad.js) - Transaction anti-patterns (non-Flutter)
- [examples/attachment-lazy-loading-good.dart](examples/attachment-lazy-loading-good.dart) - Lazy-loading pattern
- [examples/attachment-lazy-loading-bad.dart](examples/attachment-lazy-loading-bad.dart) - Attachment anti-patterns
- [examples/thumbnail-pattern.dart](examples/thumbnail-pattern.dart) - Thumbnail-first pattern
- [examples/attachment-fetch-timeout.dart](examples/attachment-fetch-timeout.dart) - Timeout handling
- [examples/attachment-immutability.dart](examples/attachment-immutability.dart) - Attachment updates

### Reference
- [Ditto Attachments Documentation](https://docs.ditto.live/sdk/latest/attachments)
- [Ditto Transactions Documentation](https://docs.ditto.live/sdk/latest/crud/transactions)
- [Photo Sharing Guide](https://docs.ditto.live/guides/photo-sharing)
