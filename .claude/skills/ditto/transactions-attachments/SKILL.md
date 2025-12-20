---
name: transactions-attachments
description: |
  Validates Ditto transaction usage and attachment operations.

  CRITICAL ISSUES PREVENTED:
  - Flutter transaction close() management (must await before closing Ditto)
  - Nested transaction deadlocks (all platforms)
  - Attachment auto-sync assumptions (attachments don't sync automatically)
  - Attachment immutability violations (cannot modify existing attachments)
  - Large binary data stored inline (should use ATTACHMENT type)
  - Missing attachment metadata (filename, size, type)

  TRIGGERS:
  - Using ditto.store.transaction()
  - Closing Ditto instance in Flutter (must track pending transactions)
  - Implementing atomic multi-step operations
  - Storing or fetching attachments (newAttachment(), fetchAttachment())
  - Handling large binary files (photos, documents, videos)
  - Creating or replacing attachment metadata

  PLATFORMS: Flutter (Dart - limited transaction support), JavaScript, Swift, Kotlin
---

# Ditto Transactions and Attachments

## Table of Contents

- [Purpose](#purpose)
- [When This Skill Applies](#when-this-skill-applies)
- [Platform Detection](#platform-detection)
- [SDK Version Compatibility](#sdk-version-compatibility)
- [Common Workflows](#common-workflows)
- [Critical Patterns](#critical-patterns)
  - [1. Flutter Transaction Close Management](#1-flutter-transaction-close-management-priority-critical---flutter-only)
  - [2. Nested Read-Write Transaction Deadlock](#2-nested-read-write-transaction-deadlock-priority-critical---all-platforms)
  - [3. Attachment Auto-Sync Assumption](#3-attachment-auto-sync-assumption-priority-critical)
  - [4. Attachment Immutability Violation](#4-attachment-immutability-violation-priority-high)
  - [5. Missing Attachment Metadata](#5-missing-attachment-metadata-priority-high)
  - [6. Inline Binary Data Storage](#6-inline-binary-data-storage-priority-high)
  - [7. Attachment Fetcher Cancellation](#7-attachment-fetcher-cancellation-priority-high)
  - [8. Thumbnail-First Pattern](#8-thumbnail-first-pattern-for-large-files-priority-medium)
  - [9. Transaction Duration Violations](#9-transaction-duration-violations-priority-medium---non-flutter)
  - [10. Attachment Fetch Timeout Handling](#10-attachment-fetch-timeout-handling-priority-medium)
  - [11. Attachment Availability Constraints](#11-attachment-availability-constraints-priority-medium)
  - [12. Garbage Collection Awareness](#12-garbage-collection-awareness-priority-low)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

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

## SDK Version Compatibility

This section consolidates all version-specific information referenced throughout this Skill.

### Transactions

**Flutter SDK**:
- Transaction API available in all versions
- **Critical limitation**: Must manually track and await all pending transactions before calling `ditto.close()`
- No automatic transaction tracking or cleanup
- Transaction timeouts not enforced (unlike non-Flutter SDKs)

**Non-Flutter SDKs**:
- Full transaction support with automatic timeout enforcement
- Transaction duration limit: Keep transactions short (avoid long-running operations)
- Nested read-write transactions cause deadlocks (all versions)

### Attachments

**All Platforms and SDK Versions**:
- Attachment operations available: `newAttachment()`, `fetchAttachment()`
- Attachments do NOT sync automatically (must be explicitly fetched)
- Attachments are immutable (cannot modify existing attachments)
- Lazy-loading pattern required for large files
- Metadata storage (filename, size, mimeType) recommended
- Thumbnail-first pattern for large files (all versions)
- Garbage collection after 24 hours of no references (all versions)

**Throughout this Skill**: Attachment patterns are universal. Transaction behavior differs between Flutter (manual tracking) and non-Flutter (automatic timeout).

---

## Common Workflows

### Workflow 1: Using Transactions Safely (Flutter)

**Flutter-specific** - Manual transaction tracking required:

```
Transaction Progress (Flutter):
- [ ] Step 1: Create list to track pending transactions
- [ ] Step 2: Store Future<void> for each transaction
- [ ] Step 3: Perform atomic operations inside transaction
- [ ] Step 4: Await all pending transactions before ditto.close()
```

```dart
class MyDittoService {
  final List<Future<void>> _pendingTransactions = [];

  Future<void> updateOrderAtomically(String orderId) async {
    final txFuture = ditto.store.transaction((tx) async {
      // Atomic operations
      await tx.execute('UPDATE orders SET status = :status WHERE _id = :id'
        arguments: {'status': 'shipped', 'id': orderId});
      await tx.execute('UPDATE inventory SET stock = stock - 1 WHERE productId = :pid'
        arguments: {'pid': 'prod_123'});
    });

    _pendingTransactions.add(txFuture);
    await txFuture;
    _pendingTransactions.remove(txFuture);
  }

  Future<void> cleanup() async {
    await Future.wait(_pendingTransactions);  // CRITICAL
    await ditto.close();
  }
}
```

---

### Workflow 2: Storing and Fetching Attachments

```
Attachment Workflow:
- [ ] Step 1: Create attachment from file/data
- [ ] Step 2: Store attachment metadata in document
- [ ] Step 3: Create document with attachment token
- [ ] Step 4: Fetch attachment when needed (lazy-loading)
- [ ] Step 5: Handle fetch completion/errors
```

```dart
// Step 1-3: Store attachment
final file = File('/path/to/photo.jpg');
final attachment = await ditto.store.newAttachment(
  file.path
  metadata: {'filename': 'photo.jpg', 'mimeType': 'image/jpeg'}
);

await ditto.store.execute(
  'INSERT INTO photos DOCUMENTS (:doc)'
  arguments: {
    'doc': {
      '_id': 'photo_123'
      'image': attachment.token,  // Attachment token
      'filename': 'photo.jpg'
      'size': file.lengthSync()
    }
  }
);

// Step 4-5: Fetch attachment (lazy-loading)
final fetcher = ditto.store.fetchAttachment(
  attachmentToken
  onFetchEvent: (event) {
    if (event is DittoAttachmentFetchEventCompleted) {
      // Attachment ready at event.attachment.path
    }
  }
);
```

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
    String? hint
    bool isReadOnly = false
  }) async {
    final transactionFuture = ditto.store.transaction(
      hint: hint
      isReadOnly: isReadOnly
      block
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
      'SELECT * FROM orders WHERE _id = :orderId'
      arguments: {'orderId': orderId}
    );

    if (orderResult.items.isEmpty) {
      throw Exception('Order not found');
    }

    final order = orderResult.items.first.value;

    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :orderId'
      arguments: {'orderId': orderId, 'status': 'shipped'}
    );

    await tx.execute(
      'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = :itemId'
      arguments: {'itemId': order['itemId']}
    );
  }
  hint: 'process-order'
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
    'SELECT * FROM orders WHERE _id = $args.orderId'
    { args: { orderId: 'order_123' } }
  );

  if (orderResult.items.length === 0) {
    throw new Error('Order not found');
  }

  const order = orderResult.items[0].value;

  // Update order status
  await tx.execute(
    'UPDATE orders SET status = $args.status WHERE _id = $args.orderId'
    { args: { orderId: 'order_123', status: 'shipped' } }
  );

  // Decrement inventory
  await tx.execute(
    'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = $args.itemId'
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
final result = await ditto.store.execute('SELECT * FROM products WHERE _id = :id'
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
  'SELECT * FROM products WHERE _id = :id'
  arguments: {'id': productId}
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



This section contains only the most critical (Tier 1) patterns that prevent data loss, deadlocks, and synchronization issues. For additional patterns, see:
- **[reference/platform-specific.md](reference/platform-specific.md)**: HIGH, MEDIUM, and LOW priority patterns for attachment immutability, metadata handling, binary data storage, fetcher management, thumbnails, transaction duration, timeouts, availability, and garbage collection

---

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
-  - Flutter alternative pattern
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
