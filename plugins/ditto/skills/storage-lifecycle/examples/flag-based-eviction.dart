// SDK Version: ditto_live 5.1.0
// Platform: Flutter (the DQL applies to all SDKs)
// Last Updated: 2026-10-09
//
// Flag-based eviction: devices subscribe only to unflagged documents and
// evict the flagged ones.
//
// Guide: § Flag-based eviction
//
// Key rules:
// - A central component decides what is no longer needed and sets
//   evictionFlag = true. This approach works well when a Ditto Server is
//   available, because the server can make sure documents have synced before
//   they are marked (see
//   ttl-eviction-ditto-server.dart).
// - Devices subscribe with coalesce(evictionFlag, false) = false, so documents
//   without the field are included.
// - Because the subscription never matches flagged documents, it does not
//   need to be cancelled and re-registered before each eviction.
// - Do not confuse this with soft delete: an eviction flag means "this device
//   no longer needs it" and SHOULD leave the subscription; soft-deleted
//   documents stay in the subscriptions of devices that relay data, so they
//   can pass the deletion flag on (see soft-delete-relay.dart for Variant A
//   and Variant B).

import 'package:ditto_live/ditto_live.dart';

/// Owns the orders subscription and the scheduled eviction on a device.
class FlaggedOrderEviction {
  FlaggedOrderEviction(this.ditto);

  final Ditto ditto;
  SyncSubscription? _subscription;
  DateTime? _lastRun;

  /// ✅ GOOD: Subscribe to unflagged documents only. Call once at startup.
  void start() {
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE coalesce(evictionFlag, false) = false',
    );
  }

  /// ✅ GOOD: Evict the flagged documents, at most about once per day.
  /// The subscription stays registered: it does not match flagged documents,
  /// so they do not sync back.
  Future<int> evictFlaggedIfDue() async {
    final now = DateTime.now().toUtc();
    final last = _lastRun;
    if (last != null && now.difference(last) < const Duration(days: 1)) {
      return 0;
    }
    _lastRun = now;

    final result = await ditto.store.execute(
      'EVICT FROM orders WHERE evictionFlag = true RETURNING COUNT(*) AS evicted',
    );
    return result.items.first.value['evicted'] as int;
  }

  void dispose() => _subscription?.cancel();
}

/// ❌ BAD: `evictionFlag != true` excludes documents where the field is
/// missing or null, so documents written without the flag never sync to this
/// device.
SyncSubscription subscribeWithWrongFlagFilter(Ditto ditto) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE evictionFlag != true',
  );
}

/// ❌ BAD: The subscription matches flagged documents, so evicting them makes
/// connected peers sync them straight back.
Future<SyncSubscription> evictFlaggedWhileSubscribedToAll(Ditto ditto) async {
  final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
  await ditto.store.execute('EVICT FROM orders WHERE evictionFlag = true');
  return subscription;
}
