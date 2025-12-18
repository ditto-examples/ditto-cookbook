// ============================================================================
// Document Size Optimization
// ============================================================================
//
// This example demonstrates best practices for managing document sizes in
// Ditto to avoid performance issues and size limit violations.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Document size limits (5 MB hard, 250 KB soft target)
// 2. ✅ ATTACHMENT usage for large binary data
// 3. ✅ Embed vs flat decision tree
// 4. ✅ Field-level updates to minimize sync overhead
// 5. ✅ Large collection splitting strategies
// 6. ✅ Compression considerations
// 7. ✅ Performance impact on Bluetooth LE transport
//
// DOCUMENT SIZE LIMITS:
// - Hard limit: 5 MB per document (enforced by Ditto)
// - Soft target: 250 KB per document (recommended for performance)
// - Bluetooth LE: Performance degrades significantly above 250 KB
//
// WHY SIZE MATTERS:
// - Sync performance: Large documents slow down sync
// - Memory usage: Large documents consume more RAM
// - Bluetooth LE: Small MTU size makes large docs very slow
// - Merge overhead: Larger documents have higher merge costs
//
// WHEN TO USE ATTACHMENTS:
// - Binary data > 100 KB (images, videos, PDFs)
// - Files that can be lazy-loaded
// - Content that doesn't need to be queried
//
// ============================================================================

import 'dart:typed_data';
import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Understanding Document Size Limits
// ============================================================================

/// ❌ BAD: Storing large binary data inline in document
Future<void> antiPattern_InlineBinaryData(Ditto ditto, String productId) async {
  // Simulate large product image (2 MB)
  final largeImage = Uint8List(2 * 1024 * 1024); // 2 MB of data

  try {
    await ditto.store.execute(
      '''
      INSERT INTO products (
        _id, name, price, imageData, description
      )
      VALUES (:id, :name, :price, :imageData, :description)
      ''',
      arguments: {
        'id': productId,
        'name': 'Premium Laptop',
        'price': 1299.99,
        'imageData': largeImage, // ❌ BAD: Inline binary data
        'description': 'High-performance laptop with amazing features',
      },
    );

    print('❌ Stored 2 MB image inline in document');
    print('   Problems:');
    print('   - Document size: 2+ MB (approaching 5 MB limit)');
    print('   - Sync overhead: 2 MB transferred even for price updates');
    print('   - Bluetooth LE: Very slow sync (8x slower than target)');
    print('   - Memory: 2 MB loaded even if image not displayed');
  } catch (e) {
    print('❌ ERROR: $e');
  }
}

/// ✅ GOOD: Use ATTACHMENT for large binary data
Future<void> recommendedPattern_AttachmentForBinary(
  Ditto ditto,
  String productId,
  Uint8List imageData,
) async {
  // Create attachment for image
  final attachment = await ditto.store.newAttachment(
    'image/jpeg',
    imageData,
  );

  // Store only metadata and attachment token in document
  await ditto.store.execute(
    '''
    INSERT INTO products (
      _id, name, price, imageToken, imageMetadata, description
    )
    VALUES (:id, :name, :price, :imageToken, :metadata, :description)
    ''',
    arguments: {
      'id': productId,
      'name': 'Premium Laptop',
      'price': 1299.99,
      'imageToken': attachment, // ✅ GOOD: Attachment token (small)
      'imageMetadata': {
        'fileName': 'laptop.jpg',
        'mimeType': 'image/jpeg',
        'sizeBytes': imageData.length,
      },
      'description': 'High-performance laptop with amazing features',
    },
  );

  print('✅ Stored image as attachment (document ~1 KB)');
  print('   Benefits:');
  print('   - Document size: ~1 KB (excluding attachment)');
  print('   - Lazy loading: Image fetched only when needed');
  print('   - Efficient sync: Price updates don\'t transfer image');
  print('   - Bluetooth LE: Fast document sync');
}

// ============================================================================
// PATTERN 2: Document Size Targets by Transport
// ============================================================================

/// Document size recommendations by transport type
void printSizeRecommendations() {
  print('✅ Document Size Recommendations:');
  print('');
  print('Transport          | Target Size | Max Size | Notes');
  print('-------------------|-------------|----------|---------------------------');
  print('Bluetooth LE       | < 250 KB    | 5 MB     | Performance degrades >250KB');
  print('Wi-Fi/LAN          | < 1 MB      | 5 MB     | Acceptable up to 1 MB');
  print('Cloud Sync         | < 1 MB      | 5 MB     | Network latency impact');
  print('');
  print('General Rule: Keep documents under 250 KB for best performance');
  print('              Use attachments for binary data > 100 KB');
}

// ============================================================================
// PATTERN 3: Embed vs Flat Decision Tree
// ============================================================================

/// Decision tree for embedding vs flattening data
Future<void> demonstrateEmbedVsFlat(Ditto ditto) async {
  print('✅ Embed vs Flat Decision Tree:');
  print('');
  print('Question 1: Is the related data accessed together frequently?');
  print('  YES → Consider embedding');
  print('  NO  → Keep flat (separate collections)');
  print('');
  print('Question 2: Will the embedded data exceed 250 KB?');
  print('  YES → Keep flat (use references)');
  print('  NO  → Embedding is acceptable');
  print('');
  print('Question 3: Does the embedded data change frequently?');
  print('  YES → Keep flat (to avoid sync overhead)');
  print('  NO  → Embedding is acceptable');
  print('');
  print('Question 4: Is this historical/snapshot data?');
  print('  YES → Embed (snapshot semantics)');
  print('  NO  → Consider current/fresh needs');

  // ✅ Example: Embed order items (accessed together, historical snapshot)
  await ditto.store.execute(
    '''
    INSERT INTO orders (_id, customerId, items, total)
    VALUES (:id, :customerId, :items, :total)
    ''',
    arguments: {
      'id': 'order_001',
      'customerId': 'cust_123',
      'items': {
        'item_1': {'productId': 'prod_1', 'quantity': 2, 'price': 29.99},
        'item_2': {'productId': 'prod_2', 'quantity': 1, 'price': 99.99},
      },
      'total': 159.97,
    },
  );
  print('');
  print('✅ Embedded order items: Small size, accessed together, historical');

  // ✅ Example: Keep user profile separate (changes frequently)
  await ditto.store.execute(
    '''
    INSERT INTO posts (_id, authorId, content)
    VALUES (:id, :authorId, :content)
    ''',
    arguments: {
      'id': 'post_001',
      'authorId': 'user_123', // Reference, not embedded
      'content': 'My blog post content',
    },
  );
  print('✅ Post references author: Profile changes frequently, keep separate');
}

// ============================================================================
// PATTERN 4: Large Collection Splitting
// ============================================================================

/// ✅ GOOD: Split large collections into separate documents
Future<void> splitLargeCollection(Ditto ditto, String catalogId) async {
  // ❌ BAD: Single document with 1000 products (huge!)
  // ✅ GOOD: Split into categories

  // Category: Laptops
  await ditto.store.execute(
    '''
    INSERT INTO productCategories (_id, categoryName, products)
    VALUES (:id, :name, :products)
    ''',
    arguments: {
      'id': 'category_laptops',
      'name': 'Laptops',
      'products': {
        'prod_1': {'name': 'Laptop A', 'price': 999.99},
        'prod_2': {'name': 'Laptop B', 'price': 1299.99},
        // ... up to ~50 products (keep under 250 KB)
      },
    },
  );

  // Category: Accessories
  await ditto.store.execute(
    '''
    INSERT INTO productCategories (_id, categoryName, products)
    VALUES (:id, :name, :products)
    ''',
    arguments: {
      'id': 'category_accessories',
      'name': 'Accessories',
      'products': {
        'prod_51': {'name': 'Mouse A', 'price': 29.99},
        'prod_52': {'name': 'Keyboard A', 'price': 79.99},
        // ... up to ~50 products
      },
    },
  );

  print('✅ Split large catalog into category documents');
  print('   Benefits:');
  print('   - Each document < 250 KB');
  print('   - Selective sync (only needed categories)');
  print('   - Faster queries (smaller document scans)');
}

// ============================================================================
// PATTERN 5: Field-Level Updates for Large Documents
// ============================================================================

/// ✅ GOOD: Use field-level updates for large documents
Future<void> optimizeLargeDocumentUpdates(Ditto ditto, String reportId) async {
  // Imagine: Report document with large embedded data (~2 MB)
  // Only need to update status field

  // ✅ GOOD: Field-level update with DO UPDATE_LOCAL_DIFF
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE reports
    SET status = :status, completedAt = :timestamp
    WHERE _id = :reportId
    ''',
    arguments: {
      'reportId': reportId,
      'status': 'completed',
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Field-level update on large document:');
  print('   Document size: ~2 MB');
  print('   Update size: ~100 bytes (status + timestamp only)');
  print('   Sync efficiency: 99.995% bandwidth saved');

  // ❌ BAD: Without DO UPDATE_LOCAL_DIFF, entire 2 MB synced
}

// ============================================================================
// PATTERN 6: Document Size Monitoring
// ============================================================================

/// Monitor document sizes in collection
Future<void> monitorDocumentSizes(Ditto ditto, String collectionName) async {
  print('✅ Monitoring document sizes in $collectionName:');

  // Note: Ditto doesn't provide built-in size API
  // Must estimate based on JSON serialization

  final result = await ditto.store.execute(
    'SELECT * FROM $collectionName',
  );

  final sizeBuckets = {
    'under_10KB': 0,
    '10KB_100KB': 0,
    '100KB_250KB': 0,
    '250KB_1MB': 0,
    'over_1MB': 0,
  };

  for (final item in result.items) {
    // Rough size estimation (actual size may vary)
    final docString = item.value.toString();
    final sizeBytes = docString.length;

    if (sizeBytes < 10 * 1024) {
      sizeBuckets['under_10KB'] = sizeBuckets['under_10KB']! + 1;
    } else if (sizeBytes < 100 * 1024) {
      sizeBuckets['10KB_100KB'] = sizeBuckets['10KB_100KB']! + 1;
    } else if (sizeBytes < 250 * 1024) {
      sizeBuckets['100KB_250KB'] = sizeBuckets['100KB_250KB']! + 1;
    } else if (sizeBytes < 1024 * 1024) {
      sizeBuckets['250KB_1MB'] = sizeBuckets['250KB_1MB']! + 1;
      print('  ⚠️ Document over 250 KB: ${item.value['_id']}');
    } else {
      sizeBuckets['over_1MB'] = sizeBuckets['over_1MB']! + 1;
      print('  🚨 Document over 1 MB: ${item.value['_id']}');
    }
  }

  print('');
  print('Size Distribution:');
  for (final entry in sizeBuckets.entries) {
    print('  ${entry.key}: ${entry.value} documents');
  }
}

// ============================================================================
// PATTERN 7: Thumbnail Pattern for Large Images
// ============================================================================

/// ✅ GOOD: Store thumbnail + full image separately
Future<void> storeImageWithThumbnail(
  Ditto ditto,
  String photoId,
  Uint8List fullImageData,
  Uint8List thumbnailData,
) async {
  // Create attachments
  final fullImageAttachment = await ditto.store.newAttachment(
    'image/jpeg',
    fullImageData,
  );
  final thumbnailAttachment = await ditto.store.newAttachment(
    'image/jpeg',
    thumbnailData,
  );

  // Store both tokens
  await ditto.store.execute(
    '''
    INSERT INTO photos (
      _id, thumbnailToken, fullImageToken, metadata, uploadedAt
    )
    VALUES (:id, :thumbnail, :fullImage, :metadata, :uploadedAt)
    ''',
    arguments: {
      'id': photoId,
      'thumbnailToken': thumbnailAttachment,
      'fullImageToken': fullImageAttachment,
      'metadata': {
        'thumbnailSizeBytes': thumbnailData.length,
        'fullImageSizeBytes': fullImageData.length,
        'dimensions': {'width': 4000, 'height': 3000},
      },
      'uploadedAt': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Stored photo with thumbnail pattern:');
  print('   Document size: ~2 KB (metadata + tokens)');
  print('   Thumbnail: ${thumbnailData.length ~/ 1024} KB (auto-fetch)');
  print('   Full image: ${fullImageData.length ~/ 1024} KB (on-demand)');
}

// ============================================================================
// PATTERN 8: Text Content Pagination
// ============================================================================

/// ✅ GOOD: Paginate long text content
Future<void> storeLongTextWithPagination(
  Ditto ditto,
  String articleId,
  String fullText,
) async {
  const chunkSize = 50000; // ~50 KB per chunk
  final chunks = <String>[];

  // Split text into chunks
  for (var i = 0; i < fullText.length; i += chunkSize) {
    final end = (i + chunkSize < fullText.length) ? i + chunkSize : fullText.length;
    chunks.add(fullText.substring(i, end));
  }

  // Store main article with preview
  await ditto.store.execute(
    '''
    INSERT INTO articles (
      _id, title, preview, chunkCount, publishedAt
    )
    VALUES (:id, :title, :preview, :chunkCount, :publishedAt)
    ''',
    arguments: {
      'id': articleId,
      'title': 'Long Article Title',
      'preview': fullText.substring(0, 500), // First 500 chars
      'chunkCount': chunks.length,
      'publishedAt': DateTime.now().toIso8601String(),
    },
  );

  // Store chunks separately
  for (var i = 0; i < chunks.length; i++) {
    await ditto.store.execute(
      '''
      INSERT INTO articleChunks (_id, articleId, chunkIndex, content)
      VALUES (:id, :articleId, :index, :content)
      ''',
      arguments: {
        'id': '${articleId}_chunk_$i',
        'articleId': articleId,
        'index': i,
        'content': chunks[i],
      },
    );
  }

  print('✅ Stored long article with pagination:');
  print('   Article document: ~1 KB (title + preview)');
  print('   Content chunks: ${chunks.length} × ~50 KB');
  print('   Total: ${fullText.length ~/ 1024} KB (lazy-loaded by chunk)');
}

// ============================================================================
// PATTERN 9: Compression Considerations
// ============================================================================

/// Document compression notes
void printCompressionGuidelines() {
  print('✅ Compression Guidelines:');
  print('');
  print('Ditto automatically compresses data at transport level.');
  print('You should NOT manually compress document fields because:');
  print('');
  print('❌ Manual compression:');
  print('  - Prevents query/indexing of compressed fields');
  print('  - Double compression (manual + transport) wastes CPU');
  print('  - Binary data harder to work with in application code');
  print('');
  print('✅ Instead:');
  print('  - Keep documents in native format');
  print('  - Rely on Ditto\'s automatic compression');
  print('  - Use attachments for large binary data');
  print('  - Split large collections into smaller documents');
}

// ============================================================================
// PATTERN 10: Document Size Impact on Performance
// ============================================================================

/// Demonstrate performance impact of document size
Future<void> demonstratePerformanceImpact(Ditto ditto) async {
  print('✅ Document Size Performance Impact:');
  print('');
  print('Bluetooth LE (MTU: 23 bytes, practical: ~20 bytes):');
  print('  Document Size | BLE Packets | Transfer Time (est)');
  print('  --------------|-------------|---------------------');
  print('  10 KB         | ~500        | ~0.5 seconds');
  print('  50 KB         | ~2,500      | ~2.5 seconds');
  print('  250 KB        | ~12,500     | ~12.5 seconds (target max)');
  print('  1 MB          | ~50,000     | ~50 seconds (very slow)');
  print('  5 MB          | ~250,000    | ~4 minutes (unusable)');
  print('');
  print('Wi-Fi/LAN (10 Mbps typical):');
  print('  Document Size | Transfer Time');
  print('  --------------|---------------');
  print('  10 KB         | ~10 ms');
  print('  50 KB         | ~40 ms');
  print('  250 KB        | ~200 ms');
  print('  1 MB          | ~800 ms');
  print('  5 MB          | ~4 seconds');
  print('');
  print('Key Takeaway: Keep documents under 250 KB for Bluetooth LE performance');
}

// ============================================================================
// PATTERN 11: Attachment Sizing Best Practices
// ============================================================================

/// Best practices for attachment sizes
void printAttachmentSizingGuidelines() {
  print('✅ Attachment Sizing Guidelines:');
  print('');
  print('Content Type     | Inline (Doc) | Attachment | Notes');
  print('-----------------|--------------|------------|------------------------');
  print('Small text       | < 10 KB      | No         | Inline is fine');
  print('Medium text      | 10-50 KB     | Optional   | Consider pagination');
  print('Large text       | > 50 KB      | Yes        | Use chunks or attachment');
  print('Thumbnail image  | < 20 KB      | Optional   | Auto-fetch acceptable');
  print('Photo            | N/A          | Yes        | Always use attachment');
  print('Video            | N/A          | Yes        | Always use attachment');
  print('Audio            | N/A          | Yes        | Always use attachment');
  print('PDF              | N/A          | Yes        | Always use attachment');
  print('');
  print('Rule of Thumb: Binary data > 100 KB should use attachments');
}
