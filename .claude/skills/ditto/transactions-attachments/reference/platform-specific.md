# Transactions and Attachments Platform-Specific Patterns

This reference contains HIGH, MEDIUM, and LOW priority patterns for transaction management and attachment handling across different platforms. These patterns address common scenarios and optimizations for Ditto transactions and attachments.

## Table of Contents

- [Pattern 4: Attachment Immutability Violation](#pattern-4-attachment-immutability-violation)
- [Pattern 5: Missing Attachment Metadata](#pattern-5-missing-attachment-metadata)
- [Pattern 6: Inline Binary Data Storage](#pattern-6-inline-binary-data-storage)
- [Pattern 7: Attachment Fetcher Cancellation](#pattern-7-attachment-fetcher-cancellation)
- [Pattern 8: Thumbnail-First Pattern for Large Files](#pattern-8-thumbnail-first-pattern-for-large-files)
- [Pattern 9: Transaction Duration Violations](#pattern-9-transaction-duration-violations)
- [Pattern 10: Attachment Fetch Timeout Handling](#pattern-10-attachment-fetch-timeout-handling)
- [Pattern 11: Attachment Availability Constraints](#pattern-11-attachment-availability-constraints)
- [Pattern 12: Garbage Collection Awareness](#pattern-12-garbage-collection-awareness)

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
  'UPDATE products SET imageAttachment = :newData WHERE _id = :id'
  arguments: {'newData': newImageBytes, 'id': productId}
);
// Won't work - must create new attachment first
```

**✅ DO**:
```dart
// Create new attachment
final newImageBytes = await File('new_image.jpg').readAsBytes();
final newToken = await ditto.store.newAttachment(
  newImageBytes
  metadata: {
    'filename': 'new_image.jpg'
    'mime_type': 'image/jpeg'
  }
);

// Replace token in document using UPDATE
await ditto.store.execute(
  'UPDATE products SET imageAttachment = :token, imageMetadata = :metadata WHERE _id = :id'
  arguments: {
    'token': newToken
    'metadata': {
      'filename': 'new_image.jpg'
      'size': newImageBytes.length
      'type': 'image/jpeg'
      'updatedAt': DateTime.now().toIso8601String()
    }
    'id': productId
  }
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
  'UPDATE products SET imageAttachment = :data WHERE _id = :id'
  arguments: {'data': newBytes, 'id': productId}
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
  'INSERT INTO products DOCUMENTS (:product)'
  arguments: {
    'product': {
      '_id': productId
      'imageAttachment': token, // Token only, no metadata
    }
  }
);

// Later - no way to know size before fetching
final fetcher = ditto.store.fetchAttachment(token);
// Can't display "Image • 2.5 MB" without fetching first
```

**✅ DO**:
```dart
// Store attachment with comprehensive metadata
final imageBytes = await File('product.jpg').readAsBytes();
final token = await ditto.store.newAttachment(
  imageBytes
  metadata: {
    'filename': 'product.jpg'
    'mime_type': 'image/jpeg'
  }
);

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)'
  arguments: {
    'product': {
      '_id': productId
      'imageAttachment': token
      'imageMetadata': {
        'filename': 'product.jpg'
        'size': imageBytes.length
        'type': 'image/jpeg'
        'width': 1920,  // If available
        'height': 1080
        'uploadedAt': DateTime.now().toIso8601String()
      }
    }
  }
);

// Later - display size before fetching
final metadata = product['imageMetadata'];
Text('${metadata['filename']} • ${_formatSize(metadata['size'])}');
```

**❌ DON'T**:
```dart
// Store only attachment token
{
  '_id': 'product_123'
  'imageAttachment': 'ditto_attachment_abc...'
}

// Store filename in separate field without grouping
{
  '_id': 'product_123'
  'imageAttachment': 'ditto_attachment_abc...'
  'filename': 'product.jpg'  // Metadata should be grouped
}

// Duplicate metadata in attachment and document
final token = await ditto.store.newAttachment(
  imageBytes
  metadata: {'filename': 'product.jpg'},  // Here
);
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)'
  arguments: {
    'product': {
      'imageAttachment': token
      'filename': 'product.jpg',  // And here - duplication!
    }
  }
);
```

**Why**: Metadata enables:
- Efficient UI display without fetching attachment
- Conditional fetching based on size/type
- User experience (progress bars, file type icons)
- Debugging and analytics

**Recommended Metadata Fields**:
```dart
{
  'filename': 'document.pdf',         // Display name
  'size': 1024000,                    // Bytes (for progress/limits)
  'type': 'application/pdf',          // MIME type (for icons/handling)
  'uploadedAt': '2025-01-15T...',     // Timestamp
  'width': 1920,                      // For images (optional)
  'height': 1080,                     // For images (optional)
  'duration': 120,                    // For videos/audio (optional)
  'checksum': 'sha256:abc...',        // For integrity (optional)
}
```

**See**: 

---

### 6. Inline Binary Data Storage (Priority: HIGH)

**Platform**: All platforms

**Problem**: Storing large binary data (images, PDFs, videos) inline as base64 strings causes document size limit violations (5 MB hard limit, 250 KB warning threshold) and inefficient sync.

**Detection**:
```dart
// RED FLAGS
// Storing base64 image inline
final imageBytes = await File('photo.jpg').readAsBytes();
final base64Image = base64Encode(imageBytes);

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)'
  arguments: {
    'product': {
      '_id': productId
      'image': base64Image,  // ❌ Inline binary - causes document bloat!
    }
  }
);
// Problems:
// - Entire document must sync before displaying anything
// - Exceeds size limits if image > 5 MB
// - Wastes bandwidth syncing unchanged images
```

**✅ DO**:
```dart
// Use ATTACHMENT type for binary data
final imageBytes = await File('photo.jpg').readAsBytes();
final token = await ditto.store.newAttachment(
  imageBytes
  metadata: {
    'filename': 'photo.jpg'
    'mime_type': 'image/jpeg'
  }
);

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)'
  arguments: {
    'product': {
      '_id': productId
      'name': 'Product Name'
      'imageAttachment': token,  // ✅ Reference only
      'imageMetadata': {
        'filename': 'photo.jpg'
        'size': imageBytes.length
        'type': 'image/jpeg'
      }
    }
  }
);

// Fetch attachment lazily when needed
final fetcher = ditto.store.fetchAttachment(token);
fetcher.fetch((attachment) {
  displayImage(attachment.data);
});
```

**❌ DON'T**:
```dart
// Store large files inline
{
  '_id': 'product_123'
  'image': 'data:image/jpeg;base64,/9j/4AAQSkZJRg...',  // Huge string!
}

// Store multiple large files inline
{
  '_id': 'product_123'
  'images': [
    'data:image/jpeg;base64,...',  // Image 1
    'data:image/jpeg;base64,...',  // Image 2
    'data:image/jpeg;base64,...',  // Image 3
  ]
}
// Document size explodes, may exceed 5 MB limit
```

**Why ATTACHMENT Type**:
- ✅ Lazy-loading (fetch only when needed)
- ✅ No document size limit (attachments up to 2 GB)
- ✅ Efficient sync (separate from document data)
- ✅ Automatic caching and garbage collection
- ✅ Conditional fetching (check metadata before fetch)

**Size Limits**:

| Storage Method | Size Limit | Sync Behavior |
|----------------|------------|---------------|
| **Inline (base64)** | 5 MB (document limit) | ❌ Syncs with document (inefficient) |
| **ATTACHMENT type** | 2 GB per attachment | ✅ Lazy-loaded (efficient) |

**Use Cases for ATTACHMENT**:
- Images (photos, avatars, thumbnails)
- PDFs (documents, receipts)
- Videos (recordings, clips)
- Audio (voice memos, music)
- Any binary data > 100 KB

**Use Cases for Inline**:
- Small icons (< 10 KB)
- Emoji or Unicode characters
- Short text snippets

**See**: 

---

### 7. Attachment Fetcher Cancellation (Priority: HIGH)

**Platform**: All platforms

**Problem**: Fetchers for large attachments continue downloading in background if not canceled when UI navigates away, wasting bandwidth and battery.

**Detection**:
```dart
// RED FLAGS
// Starting fetch without storing reference
void displayProduct(String productId) {
  final product = await ditto.store.execute(...);
  final token = product['imageAttachment'];

  ditto.store.fetchAttachment(token).fetch((attachment) {
    displayImage(attachment.data);
  });
  // No reference to cancel when user navigates away!
}

// User navigates to different screen
// Fetch continues in background - wasted bandwidth
```

**✅ DO**:
```dart
// Store fetcher reference and cancel in dispose
class ProductDetailScreen extends StatefulWidget {
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  DittoAttachmentFetcher? _imageFetcher;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    final product = await ditto.store.execute(...);
    final token = product['imageAttachment'];

    _imageFetcher = ditto.store.fetchAttachment(token);
    _imageFetcher!.fetch((attachment) {
      if (mounted) {
        setState(() {
          _imageData = attachment.data;
        });
      }
    });
  }

  @override
  void dispose() {
    _imageFetcher?.cancel();  // ✅ Cancel ongoing fetch
    super.dispose();
  }
}
```

**❌ DON'T**:
```dart
// Fire-and-forget fetch
void loadImage(String token) {
  ditto.store.fetchAttachment(token).fetch((attachment) {
    displayImage(attachment.data);
  });
}
// No way to cancel if user navigates away

// Multiple fetches without canceling previous
void updateImage(String newToken) {
  // Previous fetch still running!
  _imageFetcher = ditto.store.fetchAttachment(newToken);
  _imageFetcher!.fetch((attachment) {
    displayImage(attachment.data);
  });
}
// Multiple fetches compete for bandwidth
```

**Why Cancellation Matters**:
- ✅ Saves bandwidth (mobile data limits)
- ✅ Improves battery life
- ✅ Reduces memory pressure
- ✅ Prevents stale data from displaying

**Cancellation Best Practices**:

1. **Cancel in dispose/cleanup**:
```dart
@override
void dispose() {
  _fetcher?.cancel();
  super.dispose();
}
```

2. **Cancel before starting new fetch**:
```dart
void fetchNewImage(String token) {
  _fetcher?.cancel();  // Cancel previous
  _fetcher = ditto.store.fetchAttachment(token);
  _fetcher!.fetch(...);
}
```

3. **Check mounted state before setState**:
```dart
_fetcher!.fetch((attachment) {
  if (mounted) {
    setState(() => _data = attachment.data);
  }
});
```

**See**: 

---

### 8. Thumbnail-First Pattern for Large Files (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Fetching large attachments (images, videos) without thumbnails creates poor UX with blank states during download.

**Solution**: Store separate thumbnail attachment for immediate display while full-size loads in background.

**✅ DO**:
```dart
// Create thumbnail and full-size attachments
final imageBytes = await File('photo.jpg').readAsBytes();
final thumbnailBytes = await _generateThumbnail(imageBytes, maxWidth: 200);

final fullToken = await ditto.store.newAttachment(
  imageBytes
  metadata: {'filename': 'photo.jpg', 'mime_type': 'image/jpeg'}
);

final thumbToken = await ditto.store.newAttachment(
  thumbnailBytes
  metadata: {'filename': 'photo_thumb.jpg', 'mime_type': 'image/jpeg'}
);

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)'
  arguments: {
    'product': {
      '_id': productId
      'imageAttachment': fullToken
      'thumbnailAttachment': thumbToken
      'imageMetadata': {
        'fullSize': imageBytes.length
        'thumbSize': thumbnailBytes.length
        'width': 1920
        'height': 1080
      }
    }
  }
);

// UI: Fetch thumbnail first, then full-size
class ProductImage extends StatefulWidget {
  @override
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  Uint8List? _thumbnailData;
  Uint8List? _fullImageData;
  DittoAttachmentFetcher? _thumbnailFetcher;
  DittoAttachmentFetcher? _fullImageFetcher;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final product = widget.product;

    // Fetch thumbnail immediately
    final thumbToken = product['thumbnailAttachment'];
    _thumbnailFetcher = ditto.store.fetchAttachment(thumbToken);
    _thumbnailFetcher!.fetch((attachment) {
      if (mounted) {
        setState(() => _thumbnailData = attachment.data);
      }
    });

    // Fetch full-size in background
    final fullToken = product['imageAttachment'];
    _fullImageFetcher = ditto.store.fetchAttachment(fullToken);
    _fullImageFetcher!.fetch((attachment) {
      if (mounted) {
        setState(() => _fullImageData = attachment.data);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_fullImageData != null) {
      return Image.memory(_fullImageData!);  // Full quality
    } else if (_thumbnailData != null) {
      return Image.memory(_thumbnailData!);  // Placeholder thumbnail
    } else {
      return CircularProgressIndicator();   // Loading state
    }
  }

  @override
  void dispose() {
    _thumbnailFetcher?.cancel();
    _fullImageFetcher?.cancel();
    super.dispose();
  }
}
```

**❌ DON'T**:
```dart
// Store only full-size attachment
{
  '_id': 'product_123'
  'imageAttachment': fullToken  // No thumbnail - slow to display
}

// Use base64 thumbnail inline
{
  '_id': 'product_123'
  'thumbnail': 'data:image/jpeg;base64,...',  // Inline - not ideal
  'imageAttachment': fullToken
}
// Thumbnail syncs with document, not lazy-loaded
```

**Why Thumbnail-First**:
- ✅ Immediate visual feedback (thumbnail < 50 KB loads fast)
- ✅ Progressive loading (thumbnail → full-size)
- ✅ Bandwidth-aware (can skip full-size on slow connections)
- ✅ Better perceived performance

**Thumbnail Sizing Guidelines**:

| Use Case | Thumbnail Size | Full-Size Size |
|----------|----------------|----------------|
| **List view** | 100-200px (10-50 KB) | 1920px (500 KB - 5 MB) |
| **Gallery grid** | 300px (50-100 KB) | 2560px (1-10 MB) |
| **Profile avatars** | 100px (10-30 KB) | 500px (100-500 KB) |

**See**: 

---

### 9. Transaction Duration Violations (Priority: MEDIUM - Non-Flutter)

**Platform**: Non-Flutter SDKs only (JavaScript, Swift, Kotlin)

**Note**: Flutter SDK v4.x does not support transactions (use discrete operations). Non-Flutter SDKs support `write` transactions.

**Problem**: Transactions held open for extended periods (> 500 ms) block other operations and cause performance degradation.

**Detection**:
```javascript
// RED FLAGS (JavaScript SDK example)
// Long-running transaction
const transaction = ditto.store.write((txn) => {
  // Heavy computation inside transaction - blocks other operations
  for (let i = 0; i < 10000; i++) {
    const data = expensiveComputation(i);  // ❌ CPU-bound work
    txn.execute(
      'INSERT INTO items DOCUMENTS (:item)'
      { item: { _id: `item_${i}`, data } }
    );
  }

  // Network call inside transaction - blocks for seconds
  const externalData = await fetch('https://api.example.com/data');  // ❌ I/O
  txn.execute('INSERT INTO cache DOCUMENTS (:data)', { data: externalData });
});
```

**✅ DO**:
```javascript
// Prepare data BEFORE transaction
const items = [];
for (let i = 0; i < 10000; i++) {
  const data = expensiveComputation(i);  // ✅ Outside transaction
  items.push({ _id: `item_${i}`, data });
}

// Fetch external data BEFORE transaction
const externalData = await fetch('https://api.example.com/data');  // ✅ Outside

// Transaction only performs database writes
const transaction = ditto.store.write((txn) => {
  // Fast batch insert
  for (const item of items) {
    txn.execute('INSERT INTO items DOCUMENTS (:item)', { item });
  }
  txn.execute('INSERT INTO cache DOCUMENTS (:data)', { data: externalData });
});
// Transaction completes in < 100 ms
```

**❌ DON'T**:
```javascript
// Heavy processing inside transaction
const transaction = ditto.store.write((txn) => {
  const image = loadImage('large_file.jpg');  // ❌ File I/O
  const processed = processImage(image);      // ❌ CPU-bound
  txn.execute('INSERT INTO images DOCUMENTS (:img)', { img: processed });
});

// Multiple round-trips inside transaction
const transaction = ditto.store.write((txn) => {
  for (let i = 0; i < 1000; i++) {
    const result = txn.execute('SELECT * FROM items WHERE _id = :id', { id: i });
    const updated = transform(result);  // ❌ Processing per iteration
    txn.execute('UPDATE items SET data = :data WHERE _id = :id', { data: updated, id: i });
  }
});
```

**Why Fast Transactions**:
- ✅ Prevents blocking other database operations
- ✅ Reduces lock contention
- ✅ Improves app responsiveness
- ✅ Minimizes transaction failure risk

**Best Practices**:

1. **Prepare data outside transaction** (CPU/I/O work)
2. **Batch operations** (minimize transaction scope)
3. **Avoid round-trips** (fetch data before transaction)
4. **Target < 100 ms** transaction duration

**See**: 

---

### 10. Attachment Fetch Timeout Handling (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Attachment fetches can stall indefinitely on poor network conditions without timeout handling.

**Solution**: Implement timeout and retry logic for attachment fetches.

**✅ DO**:
```dart
// Fetch with timeout and retry
Future<Uint8List?> fetchAttachmentWithTimeout(
  Ditto ditto
  DittoAttachmentToken token, {
  Duration timeout = const Duration(seconds: 30)
  int maxRetries = 3
}) async {
  for (int attempt = 0; attempt < maxRetries; attempt++) {
    try {
      final completer = Completer<Uint8List>();
      final fetcher = ditto.store.fetchAttachment(token);

      fetcher.fetch((attachment) {
        if (!completer.isCompleted) {
          completer.complete(attachment.data);
        }
      });

      // Wait with timeout
      final data = await completer.future.timeout(
        timeout
        onTimeout: () {
          fetcher.cancel();
          throw TimeoutException('Attachment fetch timeout');
        }
      );

      return data;
    } on TimeoutException catch (e) {
      if (attempt == maxRetries - 1) {
        print('Attachment fetch failed after $maxRetries attempts');
        return null;
      }
      print('Timeout on attempt ${attempt + 1}, retrying...');
      await Future.delayed(Duration(seconds: attempt + 1));
    }
  }
  return null;
}

// Usage
final imageData = await fetchAttachmentWithTimeout(ditto, token);
if (imageData != null) {
  displayImage(imageData);
} else {
  showErrorPlaceholder();
}
```

**❌ DON'T**:
```dart
// No timeout - can stall indefinitely
final fetcher = ditto.store.fetchAttachment(token);
fetcher.fetch((attachment) {
  displayImage(attachment.data);
});
// User stuck waiting forever on poor network
```

**Why Timeout Handling**:
- ✅ Better UX (clear failure states)
- ✅ Prevents indefinite hangs
- ✅ Enables retry logic
- ✅ Graceful degradation

**Recommended Timeouts**:

| Attachment Size | Timeout | Reason |
|----------------|---------|--------|
| **< 1 MB** (thumbnails) | 10-15 seconds | Fast on most networks |
| **1-10 MB** (images) | 30-60 seconds | Reasonable wait time |
| **> 10 MB** (videos) | 2-5 minutes | Large files, longer acceptable |

**See**: 

---

### 11. Attachment Availability Constraints (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Attachments may not be immediately available after document sync. Fetchers must handle unavailable attachments gracefully.

**Background**: Ditto syncs document metadata first, then attachments. Attachment tokens appear in documents before actual attachment data is available on the peer.

**✅ DO**:
```dart
// Handle unavailable attachments gracefully
class AttachmentDisplay extends StatefulWidget {
  final DittoAttachmentToken token;

  @override
  State<AttachmentDisplay> createState() => _AttachmentDisplayState();
}

class _AttachmentDisplayState extends State<AttachmentDisplay> {
  Uint8List? _data;
  String _status = 'Loading...';
  DittoAttachmentFetcher? _fetcher;

  @override
  void initState() {
    super.initState();
    _fetchAttachment();
  }

  Future<void> _fetchAttachment() async {
    _fetcher = ditto.store.fetchAttachment(widget.token);

    _fetcher!.fetch(
      (attachment) {
        if (mounted) {
          setState(() {
            _data = attachment.data;
            _status = 'Loaded';
          });
        }
      }
      onFetchEvent: (event) {
        if (mounted) {
          setState(() {
            if (event.type == DittoAttachmentFetchEventType.completed) {
              _status = 'Downloaded';
            } else if (event.type == DittoAttachmentFetchEventType.progress) {
              final progress = (event.downloadedBytes / event.totalBytes * 100).toInt();
              _status = 'Downloading... $progress%';
            }
          });
        }
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) {
      return Image.memory(_data!);
    } else {
      return Column(
        children: [
          CircularProgressIndicator()
          SizedBox(height: 8)
          Text(_status)
        ]
      );
    }
  }

  @override
  void dispose() {
    _fetcher?.cancel();
    super.dispose();
  }
}
```

**❌ DON'T**:
```dart
// Assume attachment is immediately available
final fetcher = ditto.store.fetchAttachment(token);
fetcher.fetch((attachment) {
  displayImage(attachment.data);  // May never be called if unavailable
});
// No fallback for unavailable attachment
```

**Why Availability Handling**:
- ✅ Better UX (progress feedback)
- ✅ Handles offline scenarios
- ✅ Graceful degradation
- ✅ Clear user expectations

**Fetch Event Types** (SDK 4.x+):
- `progress`: Download in progress (provides bytes downloaded/total)
- `completed`: Download finished
- `deleted`: Attachment deleted from source peer

**See**: 

---

### 12. Garbage Collection Awareness (Priority: LOW)

**Platform**: All platforms

**Background**: Ditto automatically garbage collects unreferenced attachments on a 10-minute cadence (Small Peers). Understanding GC behavior helps optimize storage.

**How GC Works**:
1. **Reference Tracking**: Ditto scans all documents for attachment tokens
2. **Unreferenced Detection**: Attachments not referenced by any document are marked for deletion
3. **10-Minute Cadence**: GC runs every 10 minutes on Small Peers
4. **Automatic Cleanup**: No manual intervention required

**Implications for Development**:

**✅ DO**:
```dart
// Replace attachment token - old attachment auto-GC'd
final newToken = await ditto.store.newAttachment(newImageBytes);
await ditto.store.execute(
  'UPDATE products SET imageAttachment = :token WHERE _id = :id'
  arguments: {'token': newToken, 'id': productId}
);
// Old attachment automatically removed after 10 minutes if unreferenced
```

**❌ DON'T**:
```dart
// Manually track attachment references for deletion
final oldToken = product['imageAttachment'];
_attachmentRegistry[oldToken] = _attachmentRegistry[oldToken]! - 1;
if (_attachmentRegistry[oldToken] == 0) {
  // No manual deletion API - Ditto handles this automatically
}
```

**Why GC Matters**:
- ✅ No manual cleanup code needed
- ✅ Storage automatically optimized
- ✅ Prevents storage leaks
- ⚠️ 10-minute delay (not immediate)

**Testing GC Behavior**:
- Replace attachment tokens in tests
- Wait > 10 minutes or trigger manual sync
- Verify old attachments removed from storage

**See**: Pattern 4 (Attachment Immutability) for replacement workflow

---

## Further Reading

- **SKILL.md**: Critical patterns (Tier 1)
- **Main Guide**: `.claude/guides/best-practices/ditto.md`
- **Related Skills**:
  - `data-modeling/SKILL.md`: Document design for attachments
  - `query-sync/SKILL.md`: Querying documents with attachments
