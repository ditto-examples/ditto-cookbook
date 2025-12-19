// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Attachment Immutability Pattern
// ============================================================================
//
// This example demonstrates the correct pattern for handling attachment
// immutability in Ditto: attachments cannot be modified, only replaced.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Creating new attachments
// 2. ✅ Replacing attachment tokens in documents
// 3. ✅ Garbage collection behavior
// 4. ✅ Source file deletion pattern
// 5. ✅ Version history with attachments
// 6. ✅ Attachment lifecycle management
// 7. ✅ Storage optimization
//
// CRITICAL RULE: ATTACHMENTS ARE IMMUTABLE
// - Cannot modify attachment content
// - Must create new attachment for changes
// - Replace token in document to "update"
// - Old attachments garbage collected automatically
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'dart:typed_data';
import 'dart:io';

// ============================================================================
// PATTERN 1: Creating New Attachments
// ============================================================================

/// ✅ GOOD: Create new attachment for new content
class AttachmentCreation {
  final Ditto ditto;

  AttachmentCreation(this.ditto);

  Future<void> uploadNewDocument(File file, String documentType) async {
    print('📤 Uploading new document...');
    print('  File: ${file.path}');
    print('  Type: $documentType');

    // ✅ Create new attachment from file
    final attachment = await ditto.store.newAttachment(
      file.path,
      metadata: {
        'type': documentType,
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Attachment created');

    // Store document with attachment token
    final docId = 'doc_${DateTime.now().millisecondsSinceEpoch}';

    await ditto.store.execute(
      '''INSERT INTO documents (
        _id, fileName, fileToken, fileSize, documentType, createdAt
      ) VALUES (
        :id, :fileName, :token, :size, :type, :createdAt
      )''',
      arguments: {
        'id': docId,
        'fileName': file.path.split('/').last,
        'token': attachment,
        'size': await file.length(),
        'type': documentType,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Document uploaded: $docId');
  }
}

// ============================================================================
// PATTERN 2: Replacing Attachment Tokens (The "Update" Pattern)
// ============================================================================

/// ✅ GOOD: "Update" attachment by replacing token
class AttachmentReplacement {
  final Ditto ditto;

  AttachmentReplacement(this.ditto);

  Future<void> updateDocument(String documentId, File newFile) async {
    print('📝 Updating document: $documentId');

    // Query existing document
    final result = await ditto.store.execute(
      'SELECT * FROM documents WHERE _id = :id',
      arguments: {'id': documentId},
    );

    if (result.items.isEmpty) {
      print('❌ Document not found');
      return;
    }

    final doc = result.items.first.value;
    final oldToken = doc['fileToken'] as DittoAttachmentToken;

    print('  Old attachment token: ${oldToken.toString()}');

    // ✅ CRITICAL: Create NEW attachment (cannot modify existing)
    final newAttachment = await ditto.store.newAttachment(
      newFile.path,
      metadata: {
        'type': doc['documentType'],
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ New attachment created');
    print('  New attachment token: ${newAttachment.toString()}');

    // ✅ Replace token in document
    await ditto.store.execute(
      '''UPDATE documents
         SET fileToken = :newToken,
             fileName = :fileName,
             fileSize = :size,
             updatedAt = :updatedAt
         WHERE _id = :id''',
      arguments: {
        'id': documentId,
        'newToken': newAttachment, // New token replaces old
        'fileName': newFile.path.split('/').last,
        'size': await newFile.length(),
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Document updated with new attachment');
    print('  Old attachment will be garbage collected');

    // ✅ IMPORTANT: Old attachment (oldToken) is now unreferenced
    // Ditto's garbage collector will clean it up automatically
  }
}

// ============================================================================
// PATTERN 3: Garbage Collection Behavior
// ============================================================================

/// ✅ GOOD: Understanding attachment garbage collection
class GarbageCollectionDemo {
  final Ditto ditto;

  GarbageCollectionDemo(this.ditto);

  Future<void> demonstrateGarbageCollection() async {
    print('🗑️ Attachment Garbage Collection Demo');
    print('');

    // Step 1: Create document with attachment
    print('Step 1: Create document with attachment A');
    final fileA = File('/path/to/fileA.pdf');
    final attachmentA = await ditto.store.newAttachment(fileA.path);

    await ditto.store.execute(
      'INSERT INTO documents (_id, fileToken) VALUES (:id, :token)',
      arguments: {'id': 'doc_1', 'token': attachmentA},
    );

    print('  ✅ Document created with attachment A');
    print('  Attachment A is REFERENCED (will be kept)');
    print('');

    // Step 2: Replace attachment
    print('Step 2: Replace with attachment B');
    final fileB = File('/path/to/fileB.pdf');
    final attachmentB = await ditto.store.newAttachment(fileB.path);

    await ditto.store.execute(
      'UPDATE documents SET fileToken = :token WHERE _id = :id',
      arguments: {'id': 'doc_1', 'token': attachmentB},
    );

    print('  ✅ Attachment A replaced with B');
    print('  Attachment A is now UNREFERENCED');
    print('  Attachment B is REFERENCED (will be kept)');
    print('');

    // Step 3: Garbage collection
    print('Step 3: Garbage collection runs automatically');
    print('  ⏱️ After some time...');
    print('  🗑️ Attachment A is deleted (unreferenced)');
    print('  ✅ Attachment B is kept (referenced in doc_1)');
    print('');

    // Step 4: Delete document
    print('Step 4: Delete document');
    await ditto.store.execute(
      'DELETE FROM documents WHERE _id = :id',
      arguments: {'id': 'doc_1'},
    );

    print('  ✅ Document deleted');
    print('  Attachment B is now UNREFERENCED');
    print('  🗑️ Attachment B will be garbage collected');
    print('');

    print('✅ Key takeaway:');
    print('  - Attachments live as long as referenced in any document');
    print('  - Unreferenced attachments are automatically cleaned up');
    print('  - No manual cleanup required');
  }
}

// ============================================================================
// PATTERN 4: Source File Deletion Pattern
// ============================================================================

/// ✅ GOOD: Safe to delete source file after attachment creation
class SourceFileDeletion {
  final Ditto ditto;

  SourceFileDeletion(this.ditto);

  Future<void> uploadAndCleanup(File sourceFile) async {
    print('📤 Uploading with cleanup...');
    print('  Source: ${sourceFile.path}');

    // Create attachment (Ditto copies file content)
    final attachment = await ditto.store.newAttachment(sourceFile.path);

    print('  ✅ Attachment created (content copied to Ditto store)');

    // Store document
    await ditto.store.execute(
      'INSERT INTO documents (_id, fileToken) VALUES (:id, :token)',
      arguments: {
        'id': 'doc_${DateTime.now().millisecondsSinceEpoch}',
        'token': attachment,
      },
    );

    print('  ✅ Document stored');

    // ✅ SAFE: Delete source file (Ditto has copy)
    await sourceFile.delete();
    print('  🗑️ Source file deleted (Ditto has copy)');

    print('✅ Upload complete, source cleaned up');
  }
}

// ============================================================================
// PATTERN 5: Version History with Attachments
// ============================================================================

/// ✅ GOOD: Keep version history by storing multiple tokens
class AttachmentVersionHistory {
  final Ditto ditto;

  AttachmentVersionHistory(this.ditto);

  Future<void> createDocumentWithVersioning(File file) async {
    print('📄 Creating document with version history...');

    final attachment = await ditto.store.newAttachment(file.path);

    final docId = 'doc_${DateTime.now().millisecondsSinceEpoch}';

    // Store current version in document
    await ditto.store.execute(
      '''INSERT INTO documents (
        _id, fileName, currentVersionToken, createdAt
      ) VALUES (
        :id, :fileName, :token, :createdAt
      )''',
      arguments: {
        'id': docId,
        'fileName': file.path.split('/').last,
        'token': attachment,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Document created: $docId (version 1)');
  }

  Future<void> updateDocumentWithVersioning(String documentId, File newFile) async {
    print('📝 Updating document with version history...');

    // Query current version
    final result = await ditto.store.execute(
      'SELECT * FROM documents WHERE _id = :id',
      arguments: {'id': documentId},
    );

    if (result.items.isEmpty) {
      print('❌ Document not found');
      return;
    }

    final doc = result.items.first.value;
    final currentToken = doc['currentVersionToken'] as DittoAttachmentToken;

    // Create new version
    final newAttachment = await ditto.store.newAttachment(newFile.path);

    final versionNumber = (doc['versionNumber'] as int? ?? 1) + 1;

    // ✅ Save old version to history (keeps attachment alive)
    await ditto.store.execute(
      '''INSERT INTO documentVersions (
        _id, documentId, versionNumber, versionToken, createdAt
      ) VALUES (
        :id, :docId, :versionNum, :token, :createdAt
      )''',
      arguments: {
        'id': 'version_${DateTime.now().millisecondsSinceEpoch}',
        'docId': documentId,
        'versionNum': versionNumber - 1,
        'token': currentToken, // Old version preserved
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Old version saved to history (version ${versionNumber - 1})');

    // Update document with new version
    await ditto.store.execute(
      '''UPDATE documents
         SET currentVersionToken = :newToken,
             versionNumber = :versionNum,
             updatedAt = :updatedAt
         WHERE _id = :id''',
      arguments: {
        'id': documentId,
        'newToken': newAttachment,
        'versionNum': versionNumber,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Document updated to version $versionNumber');
    print('  Old attachment preserved in version history');
  }

  Future<void> retrieveVersion(String documentId, int versionNumber) async {
    print('📥 Retrieving version $versionNumber of document $documentId...');

    final result = await ditto.store.execute(
      '''SELECT * FROM documentVersions
         WHERE documentId = :docId AND versionNumber = :versionNum''',
      arguments: {'docId': documentId, 'versionNum': versionNumber},
    );

    if (result.items.isEmpty) {
      print('❌ Version not found');
      return;
    }

    final doc = result.items.first.value;
    final versionToken = doc['versionToken'] as DittoAttachmentToken;

    // Fetch historical attachment
    final fetcher = ditto.store.fetchAttachment(versionToken);
    final attachment = await fetcher.attachment;

    if (attachment != null) {
      final data = attachment.getData();
      print('✅ Version $versionNumber retrieved: ${data.length} bytes');
    } else {
      print('❌ Version attachment not available');
    }
  }
}

// ============================================================================
// PATTERN 6: Attachment Lifecycle Management
// ============================================================================

/// ✅ GOOD: Manage attachment lifecycle across operations
class AttachmentLifecycle {
  final Ditto ditto;

  AttachmentLifecycle(this.ditto);

  Future<void> demonstrateLifecycle() async {
    print('🔄 Attachment Lifecycle Demonstration');
    print('');

    // Phase 1: Creation
    print('Phase 1: CREATION');
    final file = File('/path/to/document.pdf');
    final attachment = await ditto.store.newAttachment(file.path);
    print('  ✅ Attachment created from source file');
    print('  Source file can now be deleted');
    print('');

    // Phase 2: Storage
    print('Phase 2: STORAGE');
    await ditto.store.execute(
      'INSERT INTO documents (_id, fileToken) VALUES (:id, :token)',
      arguments: {'id': 'doc_1', 'token': attachment},
    );
    print('  ✅ Attachment token stored in document');
    print('  Attachment is now REFERENCED');
    print('');

    // Phase 3: Retrieval
    print('Phase 3: RETRIEVAL');
    final result = await ditto.store.execute(
      'SELECT * FROM documents WHERE _id = :id',
      arguments: {'id': 'doc_1'},
    );
    final doc = result.items.first.value;
    final token = doc['fileToken'] as DittoAttachmentToken;
    print('  ✅ Attachment token retrieved from document');
    print('');

    // Phase 4: Fetch
    print('Phase 4: FETCH');
    final fetcher = ditto.store.fetchAttachment(token);
    final fetchedAttachment = await fetcher.attachment;
    if (fetchedAttachment != null) {
      final data = fetchedAttachment.getData();
      print('  ✅ Attachment content fetched: ${data.length} bytes');
    }
    print('');

    // Phase 5: Replacement
    print('Phase 5: REPLACEMENT');
    final newFile = File('/path/to/updated.pdf');
    final newAttachment = await ditto.store.newAttachment(newFile.path);
    await ditto.store.execute(
      'UPDATE documents SET fileToken = :token WHERE _id = :id',
      arguments: {'id': 'doc_1', 'token': newAttachment},
    );
    print('  ✅ Attachment token replaced');
    print('  Old attachment now UNREFERENCED');
    print('');

    // Phase 6: Garbage Collection
    print('Phase 6: GARBAGE COLLECTION');
    print('  ⏱️ Automatic cleanup runs periodically');
    print('  🗑️ Unreferenced attachments deleted');
    print('  Referenced attachments preserved');
    print('');

    // Phase 7: Document Deletion
    print('Phase 7: DOCUMENT DELETION');
    await ditto.store.execute(
      'DELETE FROM documents WHERE _id = :id',
      arguments: {'id': 'doc_1'},
    );
    print('  ✅ Document deleted');
    print('  New attachment now UNREFERENCED');
    print('  Will be garbage collected');
    print('');

    print('✅ Complete lifecycle demonstrated');
  }
}

// ============================================================================
// PATTERN 7: Storage Optimization
// ============================================================================

/// ✅ GOOD: Optimize storage by removing unused attachments
class StorageOptimization {
  final Ditto ditto;

  StorageOptimization(this.ditto);

  Future<void> cleanupOldDocuments() async {
    print('🧹 Cleaning up old documents...');

    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 365))
        .toIso8601String();

    // Query old documents
    final result = await ditto.store.execute(
      'SELECT _id FROM documents WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('  Found ${result.items.length} old documents to remove');

    // ✅ EVICT old documents (removes document + unreferences attachments)
    await ditto.store.execute(
      'EVICT FROM documents WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('✅ Old documents evicted');
    print('  Attachments no longer referenced will be garbage collected');
    print('  Storage space will be reclaimed');
  }

  Future<void> removeUnusedVersions() async {
    print('🧹 Cleaning up old versions...');

    // Keep only last 5 versions per document
    final result = await ditto.store.execute(
      '''SELECT documentId, MAX(versionNumber) as maxVersion
         FROM documentVersions
         GROUP BY documentId''',
    );

    for (final item in result.items) {
      final doc = item.value;
      final documentId = doc['documentId'] as String;
      final maxVersion = doc['maxVersion'] as int;

      if (maxVersion > 5) {
        final cutoffVersion = maxVersion - 5;

        await ditto.store.execute(
          '''EVICT FROM documentVersions
             WHERE documentId = :docId AND versionNumber <= :cutoff''',
          arguments: {'docId': documentId, 'cutoff': cutoffVersion},
        );

        print('  ✅ Removed old versions for $documentId (kept last 5)');
      }
    }

    print('✅ Version cleanup complete');
    print('  Old attachment versions unreferenced');
    print('  Will be garbage collected');
  }
}

// ============================================================================
// Complete Example: Document Management with Immutability
// ============================================================================

/// Production-ready document manager respecting attachment immutability
class ImmutableDocumentManager {
  final Ditto ditto;

  ImmutableDocumentManager(this.ditto);

  Future<String> createDocument(File file, String documentType) async {
    print('📄 Creating document...');

    // Create attachment (immutable from creation)
    final attachment = await ditto.store.newAttachment(file.path);

    final docId = 'doc_${DateTime.now().millisecondsSinceEpoch}';

    await ditto.store.execute(
      '''INSERT INTO documents (
        _id, fileName, fileToken, fileSize, documentType, versionNumber, createdAt
      ) VALUES (
        :id, :fileName, :token, :size, :type, 1, :createdAt
      )''',
      arguments: {
        'id': docId,
        'fileName': file.path.split('/').last,
        'token': attachment,
        'size': await file.length(),
        'type': documentType,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Document created: $docId');
    return docId;
  }

  Future<void> updateDocument(String documentId, File newFile) async {
    print('📝 Updating document...');

    final result = await ditto.store.execute(
      'SELECT * FROM documents WHERE _id = :id',
      arguments: {'id': documentId},
    );

    if (result.items.isEmpty) {
      throw Exception('Document not found');
    }

    final doc = result.items.first.value;
    final oldToken = doc['fileToken'] as DittoAttachmentToken;
    final versionNumber = (doc['versionNumber'] as int) + 1;

    // Archive old version
    await ditto.store.execute(
      '''INSERT INTO documentVersions (
        _id, documentId, versionNumber, versionToken, createdAt
      ) VALUES (
        :id, :docId, :versionNum, :token, :createdAt
      )''',
      arguments: {
        'id': 'version_${DateTime.now().millisecondsSinceEpoch}',
        'docId': documentId,
        'versionNum': versionNumber - 1,
        'token': oldToken,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    // Create new attachment (cannot modify old one)
    final newAttachment = await ditto.store.newAttachment(newFile.path);

    // Replace token in document
    await ditto.store.execute(
      '''UPDATE documents
         SET fileToken = :newToken,
             fileName = :fileName,
             fileSize = :size,
             versionNumber = :versionNum,
             updatedAt = :updatedAt
         WHERE _id = :id''',
      arguments: {
        'id': documentId,
        'newToken': newAttachment,
        'fileName': newFile.path.split('/').last,
        'size': await newFile.length(),
        'versionNum': versionNumber,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Document updated to version $versionNumber');
    print('  Old version preserved in history');
  }

  Future<Uint8List?> fetchDocument(String documentId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM documents WHERE _id = :id',
      arguments: {'id': documentId},
    );

    if (result.items.isEmpty) return null;

    final doc = result.items.first.value;
    final token = doc['fileToken'] as DittoAttachmentToken;

    final fetcher = ditto.store.fetchAttachment(token);
    final attachment = await fetcher.attachment;

    return attachment?.getData();
  }
}
