# Multi-Peer Sync Tests

Testing concurrent edits, merges, deletion propagation, relay, and attachments across peers, from `§ Testing on Multiple Devices` and `§ Several peers in one test process`, for every SDK. The helpers and the test for each SDK are `multi-peer-test` in `../examples/<sdk>/` and the *Several peers in one test in <SDK>* section of its page.

## Testing on Multiple Devices

Concurrent edits, merges, deletion propagation, multi-hop relay, and attachment fetching across peers can only be tested with sync running between real Ditto instances. Most of these tests do not need several physical devices: several instances in one test process can sync with each other over TCP on localhost (see the next section).

- **Small-peers-only sync** requires an **offline license token** from Ditto: starting sync fails until a valid token has been set with `setOfflineOnlyLicenseToken` (see [Initializing Ditto](../../guide/reference/best-practices/setup-and-lifecycle.md#initializing-ditto)). Without a token, tests are limited to a single local store. Keep the token out of source control; pass it to tests from a CI secret.
- **Sync through Ditto Server** requires a Ditto Server database for testing. Use separate databases (apps) for development, staging, and production, or one database per developer; developers who share a database can prefix collection names to isolate their test data. There is no Ditto Server mock for CI, so run these tests against a test database.
- **Offline scenarios:** To simulate a Ditto Server outage while keeping peer-to-peer sync, let the app authenticate first and then block the Ditto Server host at the network level; blocking it before authentication makes sync fail entirely.

### Several peers in one test process

Helpers for multi-peer tests open several small peers in one test process and connect them over TCP on `127.0.0.1` only (see [A device that only connects over TCP also listens for TCP connections](../../guide/reference/knowledge/observations/connections-and-presence.md#a-device-that-only-connects-over-tcp-also-listens-for-tcp-connections)):
- Each peer has its own persistence directory, and all peers share one Database ID.
- Each group of peers needs its own port and Database ID. Pass different values when a test opens two groups (two stores, for example) and in test processes that can run at the same time on one machine (parallel CI jobs). In our testing, a second hub listened on a port that another Ditto hub already used, without an error, and a client that reconnected then moved to the newer hub and mixed the documents of both groups; with different Database IDs, the groups did not mix, and the test failed visibly (see [A second hub listened on a port already in use without an error](../../guide/reference/knowledge/observations/connections-and-presence.md#a-second-hub-listened-on-a-port-already-in-use-without-an-error) and [Devices with different Database IDs do not sync](../../guide/reference/knowledge/observations/persistence-directory.md#devices-with-different-database-ids-do-not-sync)).
- Peer-to-peer transports are disabled, so a test never connects to devices nearby.
- `whileDisconnected` stops sync on every peer, runs the writes, and reconnects the peers. Writes made inside it are concurrent, like edits on devices that are offline at the same time. Writes made while the peers are connected reach the other peers within milliseconds and do not test a merge.
- `waitForConvergence` waits, with a timeout, until every peer returns the same rows.

```sql
-- Test: concurrent edits of different line items both survive
-- On the first peer, before the peers disconnect:
-- Arguments: {"order": {"_id": "order-1", "items": {"item-1": {"productId": "p1", "quantity": 1}}}}
INSERT INTO orders DOCUMENTS (:order)

-- While disconnected, on the first peer:
-- Arguments: {"id": "order-1"}
UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id

-- While disconnected, on the second peer:
-- Arguments: {"id": "order-1", "item": {"productId": "p2", "quantity": 1}}
UPDATE orders SET items.`item-2` = :item WHERE _id = :id

-- After reconnecting, every peer converges on two items: item-1 with
-- quantity 3 and item-2 with productId p2
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id
```

The helpers and this test for each SDK: [Several peers in one test in Flutter](../../guide/reference/best-practices/platforms/flutter.md#several-peers-in-one-test-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#several-peers-in-one-test-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#several-peers-in-one-test-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#several-peers-in-one-test-in-swift).

This setup does not cover the following, so keep a few tests on real devices:
- All peers share one clock. Clock skew between devices is not simulated.
- Only TCP is exercised. Bluetooth LE, P2P Wi-Fi, LAN discovery, permissions, and app lifecycle need real devices. Two iOS simulators on one Mac can also sync over AWDL (in testing with SDK 5.1.0 and 5.2.0, they synced with only AWDL enabled and did not with no transport enabled); because the simulators share the Mac's network, this checks your app's transport configuration, not AWDL over the air (`§ Two iOS simulators synced over AWDL alone`).
- A listening peer accepts at most 6 TCP connections by default (in our testing with SDK 5.1.0 and 5.2.0; see [A device accepts six TCP connections by default](../../guide/reference/knowledge/observations/connections-and-presence.md#a-device-accepts-six-tcp-connections-by-default)). On 5.2.0, the connections that a peer opened itself count toward the limit too (see [Transport Configuration](../../guide/reference/best-practices/setup-and-lifecycle.md#transport-configuration)). For a relay test, chain the peers: A listens, B listens and connects to A, and C connects to B.

Scenarios worth covering (with the helpers above, or on real devices):
- Two devices edit **different fields** and the **same field** of one document while offline, then reconnect.
- Two devices add, edit, and remove entries of the same map (and, for comparison, the same array) while offline.
- One device deletes a document while another updates it (expect a [husk document](../../guide/reference/best-practices/deletion-and-storage.md#husk-documents)), and the same with a soft delete.
- A device that missed a soft delete while offline and then syncs only through a relay (see [Soft delete, subscriptions, and cleanup](../../guide/reference/best-practices/deletion-and-storage.md#soft-delete-subscriptions-and-cleanup)).
- A counter that one device recounts with `RESTART WITH`, or re-imports with an upsert, while another keeps incrementing it (see [RESTART](../../guide/reference/best-practices/data-modeling.md#restart) and [Writing documents that contain counters](../../guide/reference/best-practices/data-modeling.md#writing-documents-that-contain-counters)).
- Shutdown right after a write: the code waits until the hub confirms the write's `commitID` before `close()`, and the hub then has the document (see [Resource Cleanup and Shutdown](../../guide/reference/best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown)).
- A user signs out of a shared device and another signs in: the first user's documents are gone and do not sync back after sync starts again (see [Switching users on a shared device](../../guide/reference/best-practices/setup-and-lifecycle.md#switching-users-on-a-shared-device)).
- A device behind a relay with narrower subscriptions (see [Multi-hop relay](../../guide/reference/best-practices/sync-and-subscriptions.md#multi-hop-relay)).
- Attachments created offline and fetched by other peers later (see [Availability](../../guide/reference/best-practices/attachments.md#availability)).
- Each transport your users rely on, including Bluetooth LE as the only transport (on real devices).

See the [testing guide](https://docs.ditto.live/sdk/latest/deployment/testing) for environment setup and offline simulation.
