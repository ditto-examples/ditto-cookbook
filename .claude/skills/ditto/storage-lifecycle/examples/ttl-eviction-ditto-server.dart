// SDK Version: ditto_live 5.1.0
// Platform: Flutter (the DQL applies to all SDKs)
// Last Updated: 2026-10-08
//
// Server-driven retention with a Ditto Server (formerly Big Peer).
//
// Guide: .claude/guides/best-practices/ditto.md#flag-based-eviction
//        .claude/guides/best-practices/ditto.md#deleting-on-the-ditto-server
//        .claude/guides/best-practices/ditto.md#soft-delete-subscriptions-and-cleanup
//
// Division of work documented by the guide:
// - The Ditto Server (for example through its HTTP API) or an authorized
//   device marks documents that devices no longer need with
//   evictionFlag = true. The server can make sure documents have synced
//   before they are marked.
// - Devices subscribe to unflagged documents and EVICT the flagged ones
//   locally. The Ditto Server keeps the data.
// - Permanent removal (for example of soft-deleted records after the
//   retention period, Variant A in soft-delete-relay.dart) runs as DELETE on
//   the Ditto Server, in batches of 30,000 documents or fewer. The DELETE
//   syncs to every device that has the documents.
//
// The HTTP API endpoint and its authentication are described in the Ditto
// Server documentation; this file only shows the DQL and the device
// side. The constants below are the statements to send to the server.

import 'package:ditto_live/ditto_live.dart';

// ============================================================================
// Statements executed on the Ditto Server (for example through the HTTP API)
// ============================================================================

/// Marks documents older than :cutoff so devices evict them.
const markExpiredOrdersStatement =
    'UPDATE orders SET evictionFlag = true WHERE createdAt < :cutoff';

/// Permanently removes soft-deleted orders after the retention period
/// (Variant A soft-delete cleanup). Repeat until no documents are affected.
/// Run it only once flagged documents are no longer edited (husk documents).
const purgeSoftDeletedOrdersStatement =
    'DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000';

// ============================================================================
// Optional: an authorized device marks the documents instead of the server
// ============================================================================

/// Run on a device whose permissions allow writing evictionFlag, for example
/// a back-office tablet. Queries run against the local store, so the device
/// can only mark documents it already has.
Future<int> markExpiredOrders(Ditto ditto, Duration retention) async {
  final cutoff = DateTime.now().toUtc().subtract(retention).toIso8601String();
  final result = await ditto.store.execute(
    'UPDATE orders SET evictionFlag = true WHERE createdAt < :cutoff',
    arguments: {'cutoff': cutoff},
  );
  return result.mutatedDocumentIDs().length;
}

// ============================================================================
// Device side: subscribe to unflagged documents, evict flagged ones
// ============================================================================

class ServerDrivenEviction {
  ServerDrivenEviction(this.ditto);

  final Ditto ditto;
  SyncSubscription? _subscription;

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    // coalesce() includes documents that do not have the flag yet.
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE coalesce(evictionFlag, false) = false',
    );
  }

  /// Call on a schedule, at most about once per day. The subscription never
  /// matches flagged documents, so it does not need to be cancelled first.
  Future<int> evictFlagged() async {
    final result = await ditto.store.execute(
      'EVICT FROM orders WHERE evictionFlag = true RETURNING COUNT(*) AS evicted',
    );
    return result.items.first.value['evicted'] as int;
  }

  void dispose() => _subscription?.cancel();
}

// ============================================================================
// ❌ Anti-pattern: permanent deletion from every device
// ============================================================================

/// ❌ BAD: DELETE removes the records for every peer, including the Ditto
/// Server, and risks husk documents when other devices still edit them.
/// Use it only when the records must disappear from the whole system.
/// ✅ FIX: Flag on the server and EVICT on devices; DELETE on the Ditto Server.
Future<void> deleteExpiredOnEveryDevice(Ditto ditto, String cutoff) async {
  await ditto.store.execute(
    'DELETE FROM orders WHERE createdAt < :cutoff',
    arguments: {'cutoff': cutoff},
  );
}
