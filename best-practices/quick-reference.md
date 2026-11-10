# Quick Reference

A condensed summary of the main recommendations. Follow the links for the reasoning and complete examples.

## DO

**Setup and lifecycle** ([SDK Setup and Lifecycle](setup-and-lifecycle.md))
- ✅ Open one `Ditto` instance per persistence directory and share it.
- ✅ For Ditto Server connections, set the expiration handler before you start sync; check the login result the way your SDK reports it, and never let an error escape from the handler.
- ✅ Pass system parameters in the system parameters of `DittoConfig` on every open (SDK 5.2+); use `ALTER SYSTEM` only for values that change while the app runs.
- ✅ Configure the logger before you open Ditto (in Flutter, after `Ditto.init()`).
- ✅ Release observers and subscriptions, stop fetchers, and await pending work before you close Ditto; where a write must reach another device, wait until it is confirmed.
- ✅ On a shared device, sign a user out in the order of [Switching users on a shared device](setup-and-lifecycle.md#switching-users-on-a-shared-device).

**Data modeling** ([Data Modeling](data-modeling.md))
- ✅ Update fields, not whole documents; use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts.
- ✅ Use maps keyed by ID for items that several devices edit; use `COUNTER` for concurrent tallies, leave counter fields out of upserts and re-imports, and recalibrate with `RESTART WITH` only while every device that changes the counter is in sync.
- ✅ Use UUIDs (or composite IDs with a UUID) for `_id`; put permission scopes in `_id`.
- ✅ Treat a check before a write as valid on this device only: no locks, uniqueness checks, or sequence numbers from a local query, a conditional `UPDATE`, or a transaction (see [Checks and Claims across Devices](data-modeling.md#checks-and-claims-across-devices)).
- ✅ Keep documents well below 256 KiB; store binary data as attachments.
- ✅ Store timestamps as UTC ISO-8601 strings ending in `Z`, produced by one fixed-precision helper, or as epoch milliseconds.
- ✅ Keep the default `DQL_STRICT_MODE = false` unless you have a specific reason.

**Queries** ([DQL Fundamentals](dql.md#dql-fundamentals))
- ✅ Pass every value as a parameter (`:name`); use `IN :values` for membership.
- ✅ Read an empty result as "not on this device", and read synced data through an observer.
- ✅ Filter optional flags with `coalesce(flag, false) = false`; test whether a field is absent with `IS MISSING` (present: `IS NOT MISSING`).
- ✅ Project only the fields you need, and add `ORDER BY` (with a tie-breaker) to observer queries.
- ✅ Create indexes at startup with `CREATE INDEX IF NOT EXISTS`; check plans with `EXPLAIN` and `ADVISE` (SDK 5.1+).

**Sync and observers** ([Sync and Subscriptions](sync-and-subscriptions.md), [Observing Changes](observers.md))
- ✅ Scope subscriptions by stable partition keys (tenant, store, user), keep them stable and owned by an app- or feature-level service, and filter UI views locally instead of re-registering.
- ✅ Register the subscriptions again every time you open Ditto; they are not persisted.
- ✅ Use `SELECT * FROM <collection> [WHERE ...]` for subscriptions; subscribe to every collection a JOIN reads. Bound what syncs with `WHERE`, not `LIMIT`.
- ✅ On a TCP hub with more than six clients, raise `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` before sync starts.
- ✅ Register each observer once per owner and release it when the owner goes away; use the SDK's backpressure API for slow work (in Flutter, register without `onChange` and consume `changes`; see [Store Observers in Flutter](platforms/flutter.md#store-observers-in-flutter)).

**Writes, deletion, and storage** ([Transactions](transactions.md), [Deletion and Storage Management](deletion-and-storage.md))
- ✅ Keep transactions short, use only the transaction's own `execute` and await each call before the callback returns, and give them a `hint`.
- ✅ Track a commit ID for upload progress only when the result lists mutated document IDs; use presence for live connection status.
- ✅ Prefer soft delete for shared records, keep soft-deleted documents in the subscriptions of devices that relay data, and target deletions with `WHERE _id IN :ids`.
- ✅ Cancel or narrow subscriptions before `EVICT`, and evict at most about once per day.

**Security** ([Security](security.md))
- ✅ Use a webhook authentication provider in production, and a provisioned private key in small-peers-only deployments.
- ✅ Validate input, and encrypt sensitive fields at the application level.

## Where to Look When Something Goes Wrong

| Symptom | Start with |
|---|---|
| A statement throws, or returns nothing although the data is on the device | [When a Statement Fails or Returns Nothing](dql.md#when-a-statement-fails-or-returns-nothing) |
| Data does not appear on another device, stops updating, or comes back | [When Data Does Not Sync](sync-and-subscriptions.md#when-data-does-not-sync) |
| No peer connects | [Diagnosing transport problems (SDK 5.1+)](setup-and-lifecycle.md#diagnosing-transport-problems-sdk-51) |
| A query is slow | The steps at the top of [Indexing and Query Performance](indexing-and-performance.md) |
| A screen janks or memory grows | [Observing Changes](observers.md) and [Query Scope and Execution](indexing-and-performance.md#query-scope-and-execution) |

## Common Code Shapes

The DQL that apps use most, with its arguments:

```sql
-- Upsert that writes only what changed (INSERT and Conflict Handling)
-- Arguments: {"product": {"_id": "p1", "name": "Pen", "priceCents": 250}}
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Counter update (Counters)
-- Arguments: {"id": "p1"}
UPDATE COLLECTION products (viewCount COUNTER) APPLY viewCount INCREMENT BY 1 WHERE _id = :id

-- Soft delete and its filter (Soft Delete)
-- Arguments: {"id": "order-1", "now": "2026-01-15T10:30:00.000Z"}
UPDATE orders SET isDeleted = true, deletedAt = :now WHERE _id = :id

SELECT * FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY createdAt DESC

-- Index creation at startup (Creating Indexes)
CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)

-- Attachment field: insert the object that newAttachment returned, and read
-- the token later to fetch the blob (Attachments)
-- Arguments: {"photo": {"_id": "photo-1", "image": "<the attachment object>"}}
INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)

-- Arguments: {"id": "photo-1"}
SELECT * FROM COLLECTION photos (image ATTACHMENT) WHERE _id = :id
```

The code for each SDK:

| Shape | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Startup sequence | [App startup in Flutter](platforms/flutter.md#app-startup-in-flutter) | [App startup in JavaScript](platforms/javascript.md#app-startup-in-javascript) | [App startup in Kotlin](platforms/kotlin.md#app-startup-in-kotlin) | [App startup in Swift](platforms/swift.md#app-startup-in-swift) |
| A service that owns subscriptions | [Subscriptions in Flutter](platforms/flutter.md#subscriptions-in-flutter) | [Subscriptions in JavaScript](platforms/javascript.md#subscriptions-in-javascript) | [Subscriptions in Kotlin](platforms/kotlin.md#subscriptions-in-kotlin) | [Subscriptions in Swift](platforms/swift.md#subscriptions-in-swift) |
| An observer in UI code | [Store Observers in Flutter](platforms/flutter.md#store-observers-in-flutter) | [Store Observers in JavaScript](platforms/javascript.md#store-observers-in-javascript) | [Store Observers in Kotlin](platforms/kotlin.md#store-observers-in-kotlin) | [Store Observers in Swift](platforms/swift.md#store-observers-in-swift) |
| A transaction | [Transactions in Flutter](platforms/flutter.md#transactions-in-flutter) | [Transactions in JavaScript](platforms/javascript.md#transactions-in-javascript) | [Transactions in Kotlin](platforms/kotlin.md#transactions-in-kotlin) | [Transactions in Swift](platforms/swift.md#transactions-in-swift) |
| Creating and fetching an attachment | [Attachments in Flutter](platforms/flutter.md#attachments-in-flutter) | [Attachments in JavaScript](platforms/javascript.md#attachments-in-javascript) | [Attachments in Kotlin](platforms/kotlin.md#attachments-in-kotlin) | [Attachments in Swift](platforms/swift.md#attachments-in-swift) |
| Logging | [Logging in Flutter](platforms/flutter.md#logging-in-flutter) | [Logging in JavaScript](platforms/javascript.md#logging-in-javascript) | [Logging in Kotlin](platforms/kotlin.md#logging-in-kotlin) | [Logging in Swift](platforms/swift.md#logging-in-swift) |
| A local-store test helper | [A local-store test helper in Flutter](platforms/flutter.md#a-local-store-test-helper-in-flutter) | [A local-store test helper in JavaScript](platforms/javascript.md#a-local-store-test-helper-in-javascript) | [A local-store test helper in Kotlin](platforms/kotlin.md#a-local-store-test-helper-in-kotlin) | [A local-store test helper in Swift](platforms/swift.md#a-local-store-test-helper-in-swift) |
