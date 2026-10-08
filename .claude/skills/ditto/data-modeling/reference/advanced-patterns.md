# Data Modeling Advanced Patterns

Less frequent patterns that complement [SKILL.md](../SKILL.md). Targets Ditto SDK 5.1.0 with the default `DQL_STRICT_MODE = false`. The source of truth is the [Data Modeling](../../../../guides/best-practices/ditto.md#data-modeling) section of the guide.

## Table of Contents

- [Pattern 1: Current State Plus History](#pattern-1-current-state-plus-history)
- [Pattern 2: Default Data with INITIAL Documents](#pattern-2-default-data-with-initial-documents)
- [Pattern 3: Schema Evolution](#pattern-3-schema-evolution)
- [Pattern 4: Composite IDs and Display Numbers](#pattern-4-composite-ids-and-display-numbers)

---

## Pattern 1: Current State Plus History

When you need both the latest value with low latency and a complete history, write each change to two collections in **one transaction**:

1. **Current state** (`vehicles`): one bounded document per entity; real-time screens observe it.
2. **History** (`vehiclePositions`): one append-only document per change; analysis reads it.

```dart
Future<void> recordPosition(
  Ditto ditto,
  String vehicleId,
  String eventId,
  double lat,
  double lon,
) async {
  final recordedAt = DateTime.now().toUtc().toIso8601String();
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'INSERT INTO vehiclePositions DOCUMENTS (:event)',
      arguments: {
        'event': {
          '_id': eventId,
          'vehicleId': vehicleId,
          'position': {'lat': lat, 'lon': lon},
          'recordedAt': recordedAt,
        },
      },
    );
    // position is a REGISTER: latitude and longitude from two readings never mix.
    await tx.execute(
      'INSERT INTO COLLECTION vehicles (position REGISTER) DOCUMENTS (:vehicle) '
      'ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
      arguments: {
        'vehicle': {
          '_id': vehicleId,
          'position': {'lat': lat, 'lon': lon},
          'lastSeenAt': recordedAt,
        },
      },
    );
  }, hint: 'recordPosition');
}
```

Devices subscribe to what they need: a live map only to `vehicles`, an analysis tool to both. Ditto's [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) describes that a peer that subscribes to only part of the documents a transaction changed receives, and can relay, only that part, so peers that need both halves together subscribe to both collections.

Guide: [Event History and Audit Logs](../../../../guides/best-practices/ditto.md#event-history-and-audit-logs), [Transactions and Sync](../../../../guides/best-practices/ditto.md#transactions-and-sync). Example: [two-collection-pattern.dart](../examples/two-collection-pattern.dart).

---

## Pattern 2: Default Data with INITIAL Documents

`INSERT ... INITIAL DOCUMENTS` seeds defaults that every peer may create independently (built-in categories, default settings). Ditto's [INSERT documentation](https://docs.ditto.live/dql/insert) describes initial documents as inserted "at the beginning of time" and viewed by all peers as the same insert, so several devices can initialize the same defaults without overwriting later edits.

| Situation on a device | Result |
|---|---|
| No document with that `_id` exists | Inserted |
| A document exists, even an edited one | Nothing happens; no error |
| The document was deleted earlier on this device | The deletion wins; a document with `null` fields remains |
| The document was evicted earlier on this device | Inserted again |
| Combined with `ON ID CONFLICT` | Parser error |

```sql
INSERT INTO categories INITIAL DOCUMENTS (:categories)
```

```sql
INSERT INTO COLLECTION inventory (stockCount COUNTER)
INITIAL DOCUMENTS (:item)
```

**✅ DO:**
- Use fixed, well-known `_id` values, and ship identical seed content in every app version that seeds them. Do not rely on how peers reconcile initial documents with *different* content for the same `_id`.
- Let users "remove" seed documents with a flag (`isArchived`), because seeding a deleted ID leaves a document with `null` fields.

**❌ DON'T:**
- Seed shared defaults with a regular `INSERT` (the second run fails with an ID conflict) or with `ON ID CONFLICT DO UPDATE` (overwrites users' edits).
- Use `INITIAL DOCUMENTS` for data only one device should create (orders, events), or to keep data off the network: subscriptions decide what syncs.

Guide: [Default Data with INITIAL Documents](../../../../guides/best-practices/ditto.md#default-data-with-initial-documents). Example: [initial-documents.dart](../examples/initial-documents.dart).

---

## Pattern 3: Schema Evolution

Devices run different app versions for weeks or months, so a schema change must work while old and new versions read and write the same data.

**✅ Prefer additive changes.** Old versions ignore unknown fields; new versions must tolerate documents without the field (`MISSING`). Instead of changing a field's meaning or unit (`mileage` from miles to kilometers), add a new field (`mileageKm`).

**❌ DON'T** change a field's type, remove it, or rename it without a versioning pattern. A type change on an **indexed** field can make queries return wrong results, because Ditto tracks only the most recently written data-type variant for a field.

| | Version in a composite `_id` | New collection per version |
|---|---|---|
| Example | `_id: {"id": "...", "schemaVersion": 2}` | `cars` to `carsV2` |
| Subscription | `WHERE _id.schemaVersion = 2` | `SELECT * FROM carsV2` |
| References from other collections | Unchanged | Must point at the new collection |
| Type change on an indexed field | Risky while both versions coexist locally | Safe (separate indexes) |

```sql
SELECT * FROM cars WHERE _id.schemaVersion = :version
```

**Rolling out a breaking change:**

1. Ship a bridge version that reads v1 and v2 but still writes v1.
2. Wait until the bridge version has reached every deployed device.
3. Ship the version that writes v2 and still reads both.
4. Retire v1 once old documents have been removed (`EVICT` per device, or `DELETE` with tombstones).

**Do not backfill** (reading every v1 document and writing a v2 copy): devices that are offline during the backfill reintroduce v1 documents later.

**Changing CRDT types** (a REGISTER object to a MAP, a number to a COUNTER) is also breaking: old and new values coexist under the same key. Introduce a new field with the new type (`stockCount` as a COUNTER next to the old `stock` register).

Guide: [Schema Evolution](../../../../guides/best-practices/ditto.md#schema-evolution). Example: [composite-id-patterns.dart](../examples/composite-id-patterns.dart).

---

## Pattern 4: Composite IDs and Display Numbers

Permission rules are queries on `_id` and its subfields. A hierarchical composite `_id` grants access at any level (`_id.region = 'eu'`, `_id.locationId = 'store-12'`); the same subfields filter subscriptions and can be indexed. Key order inside a composite `_id` does not matter.

```sql
CREATE INDEX IF NOT EXISTS orders_locationId ON orders (_id.locationId)
```

```sql
SELECT * FROM orders WHERE _id.locationId = :locationId
```

- Combine stable scope fields with a UUID: `{"region": "eu", "locationId": "store-12", "orderId": "<uuid>"}`.
- Put only **immutable** attributes into `_id`; a store that may change region or an order that may be reassigned needs those values as regular fields.
- Human-readable numbers ("#A-0042") are labels in a separate field, never `_id` or a lookup key. A terminal code that you assign plus a local sequence, shown with the date, avoids coordination.

Guide: [Composite IDs for permission scoping and grouping](../../../../guides/best-practices/ditto.md#composite-ids-for-permission-scoping-and-grouping), [Human-readable display IDs](../../../../guides/best-practices/ditto.md#human-readable-display-ids), [Security](../../../../guides/best-practices/ditto.md#security). Examples: [composite-id-patterns.dart](../examples/composite-id-patterns.dart), [id-generation-patterns.dart](../examples/id-generation-patterns.dart).
