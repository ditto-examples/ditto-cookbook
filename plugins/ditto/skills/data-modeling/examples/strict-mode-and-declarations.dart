// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Strict mode and type declarations
//
// The default is DQL_STRICT_MODE = false: objects are inferred as MAPs that
// merge field by field. Keep the default for new apps. When only a few fields
// need whole-object replacement, declare those fields as REGISTER in every
// statement that touches them.
//
// Guide: § Strict Mode, § Keep type declarations consistent

import 'package:ditto_live/ditto_live.dart';

// ---------------------------------------------------------------------------
// ✅ GOOD: A REGISTER object with consistent declarations
// ---------------------------------------------------------------------------

/// Keeps every statement that touches `customers.shippingAddress` in one
/// place, so the `(shippingAddress REGISTER)` declaration cannot drift apart.
/// A concurrent edit can never produce a mix of two addresses (the street of
/// one and the city of the other): one whole address wins.
class CustomerRepository {
  CustomerRepository(this.ditto);

  final Ditto ditto;

  Future<void> upsert(Map<String, dynamic> customer) async {
    await ditto.store.execute(
      '''
      INSERT INTO COLLECTION customers (shippingAddress REGISTER)
      DOCUMENTS (:customer)
      ON ID CONFLICT DO UPDATE_LOCAL_DIFF
      ''',
      arguments: {'customer': customer},
    );
  }

  /// Replaces the address as a whole: keys absent from [address] disappear.
  /// To change one part of a REGISTER object, write the whole object again;
  /// a nested `SET shippingAddress.city = ...` fails with
  /// `Unsupported DML operation on REGISTER field`.
  Future<void> setShippingAddress(
    String customerId,
    Map<String, dynamic> address,
  ) async {
    await ditto.store.execute(
      '''
      UPDATE COLLECTION customers (shippingAddress REGISTER)
      SET shippingAddress = :address
      WHERE _id = :id
      ''',
      arguments: {'id': customerId, 'address': address},
    );
  }

  Future<Map<String, dynamic>?> findById(String customerId) async {
    final result = await ditto.store.execute(
      '''
      SELECT * FROM COLLECTION customers (shippingAddress REGISTER)
      WHERE _id = :id
      ''',
      arguments: {'id': customerId},
    );
    return result.items.isEmpty ? null : result.items.first.value;
  }
}

// ---------------------------------------------------------------------------
// ❌ BAD: Mixed declarations for one field
// ---------------------------------------------------------------------------

/// ❌ BAD: The insert declares `obj` as REGISTER, the update leaves it
/// undeclared (so it is inferred as a MAP). Both CRDT values now exist under
/// the same key. An undeclared SELECT returns `"obj": {"a": 11}`, and `b` seems to
/// have vanished, even on a single device.
Future<void> mixedDeclarations(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO COLLECTION settings (obj REGISTER) DOCUMENTS (:doc)',
    arguments: {
      'doc': {
        '_id': 'cfg',
        'obj': {'a': 1, 'b': 2},
      },
    },
  );
  await ditto.store.execute(
    'UPDATE settings SET obj.a = 11 WHERE _id = :id',
    arguments: {'id': 'cfg'},
  );
}

// ---------------------------------------------------------------------------
// Opting in to strict mode (rarely)
// ---------------------------------------------------------------------------

/// Choose DQL_STRICT_MODE = true only when whole-object replacement is needed
/// for almost every object and you will declare every MAP, COUNTER, and
/// ATTACHMENT field in every statement. Trade-offs:
/// - Undeclared MAP/COUNTER/ATTACHMENT fields are invisible to SELECT/WHERE.
/// - Note (SDK 5.1.0): with strict mode on, the query planner does not use
///   secondary indexes (EXPLAIN shows a collection scan); ID lookups and
///   full-collection COUNT(*) are not affected.
/// - Each peer interprets data with its own setting: use the same value on
///   every peer.
///
/// ALTER SYSTEM settings are not persisted: apply this after every
/// Ditto.open, before ditto.sync.start(), queries, and observers.
Future<void> applyStrictMode(Ditto ditto) async {
  await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = true');
}

/// With strict mode on, a nested update requires a MAP declaration.
Future<void> updateMetadataInStrictMode(
  Ditto ditto,
  String orderId,
  String source,
) async {
  await ditto.store.execute(
    'UPDATE COLLECTION orders (metadata MAP) SET metadata.source = :source '
    'WHERE _id = :id',
    arguments: {'id': orderId, 'source': source},
  );
}

/// Reads the current setting.
Future<Object?> currentStrictMode(Ditto ditto) async {
  final result = await ditto.store.execute('SHOW DQL_STRICT_MODE');
  return result.items.isEmpty ? null : result.items.first.value;
}
