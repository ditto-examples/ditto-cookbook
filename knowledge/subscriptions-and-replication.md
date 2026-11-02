# Subscriptions and Replication

How Ditto decides what to send to a device, and how the data gets there: which documents a subscription delivers and what registering one costs, how relays, hubs, and devices that move between sites pass documents on, how an initial sync arrives, in what order and how completely changes arrive, how much traffic sync produces, what happens to a write when sync stops or Ditto closes, what the list of subscriptions shows, and how quickly the sync status follows a disconnection. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle), [Scope subscriptions to what the device needs](../best-practices/sync-and-subscriptions.md#scope-subscriptions-to-what-the-device-needs), [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay), [Sync Scopes](../best-practices/sync-and-subscriptions.md#sync-scopes), [Monitoring Sync Status](../best-practices/sync-and-subscriptions.md#monitoring-sync-status), [Transactions and Sync](../best-practices/transactions.md#transactions-and-sync), [Starting and Stopping Sync](../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), and [Resource Cleanup and Shutdown](../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown).

**In brief**

- The device that sends the data evaluates a subscription's `WHERE` clause like a local query. A `LIMIT` bounds only the first download, and a document that stops matching stays on the receiving device as a frozen copy ([The sending peer evaluates a subscription's WHERE clause like a local query](#the-sending-peer-evaluates-a-subscriptions-where-clause-like-a-local-query), [A LIMIT in a subscription limits only the first download](#a-limit-in-a-subscription-limits-only-the-first-download), [Documents that leave a subscription stay as frozen copies](#documents-that-leave-a-subscription-stay-as-frozen-copies)).
- Sync scopes, relays with narrower subscriptions, rewrites of the current value, and peers with different strict-mode settings behaved on SDK 5.2.0 as the guide describes ([Sync scopes behaved as documented on SDK 5.2.0](#sync-scopes-behaved-as-documented-on-sdk-520), [Relay, rewrite, and subscription behavior held on SDK 5.2.0](#relay-rewrite-and-subscription-behavior-held-on-sdk-520)).
- Subscriptions are not stored: a device that reopens its directory still sends its own changes, but on 5.1.0 and 5.2.0 it receives nothing until it registers its subscriptions again ([Subscriptions are not stored in the persistence directory](#subscriptions-are-not-stored-in-the-persistence-directory)).
- Each new subscription makes the device that holds the data read the whole collection, also with an index or a filter on `_id`. A set registered together costs a fraction of the same set registered one by one, and the number of subscriptions does not change the transfer ([Each new subscription makes the data holder read the whole collection](#each-new-subscription-makes-the-data-holder-read-the-whole-collection), [The number of subscriptions did not change the transfer](#the-number-of-subscriptions-did-not-change-the-transfer)).
- A relay forwards only the documents that it holds, also when it carries them between sites that never connect, and a new, empty hub recovers what its clients hold ([A relay forwards only the documents that it holds](#a-relay-forwards-only-the-documents-that-it-holds), [Devices that move between sites carry documents and deletions](#devices-that-move-between-sites-carry-documents-and-deletions), [A new, empty hub recovers the data from its clients](#a-new-empty-hub-recovers-the-data-from-its-clients)).
- With two relays, sync continued when one of them stopped, if the remaining relay subscribed to the data, and each relay hop added about 4 ms on one machine ([With two relays, sync continued when one of them stopped](#with-two-relays-sync-continued-when-one-of-them-stopped), [Each relay hop added about 4 ms](#each-relay-hop-added-about-4-ms)).
- An initial sync appears on the receiving device all at once, resumes where it stopped, and holds up that device's other sync until it completes ([An initial sync appears on the receiving device all at once](#an-initial-sync-appears-on-the-receiving-device-all-at-once), [An interrupted initial sync resumes where it stopped](#an-interrupted-initial-sync-resumes-where-it-stopped), [A large initial sync holds up the device's other sync](#a-large-initial-sync-holds-up-the-devices-other-sync)).
- Changes written in separate statements arrived in the order written, and large transactions and statements arrived at once, except when a faster relay with narrower subscriptions delivered part of them first ([Changes written in separate statements arrived in the order written](#changes-written-in-separate-statements-arrived-in-the-order-written), [Large transactions and statements arrived all at once](#large-transactions-and-statements-arrived-all-at-once), [A fast relay with narrower subscriptions can show part of a transaction](#a-fast-relay-with-narrower-subscriptions-can-show-part-of-a-transaction)).
- Sync sends compressed, field-level changes of the current state. In a full mesh, a device receives each new document from several neighbors, and when many devices reconnect at once with offline changes, the time until all of them agree grows faster than their number ([Sync traffic is compressed and carries field-level changes](#sync-traffic-is-compressed-and-carries-field-level-changes), [In a mesh, a new document arrives once from each neighbor](#in-a-mesh-a-new-document-arrives-once-from-each-neighbor), [Convergence after simultaneous reconnects grew faster than the number of devices](#convergence-after-simultaneous-reconnects-grew-faster-than-the-number-of-devices)).
- After many offline updates of one field, only the current value syncs: 1,000 updates cost about as much as one ([Only the current state syncs after offline edits](#only-the-current-state-syncs-after-offline-edits)).
- `close()` and `sync.stop()` do not wait for changes that are still being sent, and `sync_session_status` keeps showing `Connected` for about 73 seconds after a peer leaves ([A write made right before close or stop may not leave the device](#a-write-made-right-before-close-or-stop-may-not-leave-the-device), [The sync session status lags about 73 seconds behind a disconnection](#the-sync-session-status-lags-about-73-seconds-behind-a-disconnection)).
- Starting and stopping sync behaved as documented, but a change written right after another device stopped sync could still reach it ([Starting and stopping sync behaved as documented](#starting-and-stopping-sync-behaved-as-documented), [A change written right after another device stops sync can still reach it](#a-change-written-right-after-another-device-stops-sync-can-still-reach-it)).
- In JavaScript, `queryArguments` of a subscription registered without arguments is empty, and reading it does not end the process ([In JavaScript, queryArguments of a subscription without arguments is empty](#in-javascript-queryarguments-of-a-subscription-without-arguments-is-empty)).

## What a Subscription Delivers

### The sending peer evaluates a subscription's WHERE clause like a local query

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each, with the same results on both releases; the checks of rejected features, of composite IDs, and of directives: one run on each release |
| Setup | 16 conditions. The sending device held four documents whose `status` was `'open'`, `'closed'`, missing, and `null`. For each condition, a receiving device subscribed with it, and we compared the documents it received with the result of the same condition as a local query on the sending device |

- For every condition, the documents that arrived were exactly those that the same condition returned as a local query on the sending device:
  - `status != 'closed'`, `NOT (status = 'closed')`, and `status NOT IN :list` delivered only the `'open'` document. The document without `status` and the document with `null` did not arrive (see [MISSING and NULL](../best-practices/dql.md#missing-and-null)). On the receiving device, a missing field therefore looks like data that does not sync.
  - `status IS NOT NULL` also delivered the document without `status`, as a local query returns it.
  - Nested paths (`a.b = 1`), `array_contains(tags, 'x')`, `'x' IN tags`, `lower(name) = 'apple'`, `LIKE 'A%'`, comparisons of ISO strings, and `_id IN :ids` were accepted in subscriptions and delivered the same documents as the local query.
  - A value of another type (`n` as the string `'5'`) did not match `n > 4` and did not arrive.
- **Rejected features**: projections, aggregates, `DISTINCT *`, `GROUP BY`, `JOIN`, `USE IDS`, `LIMIT` and `ORDER BY`, and statements other than `SELECT` were rejected on 5.1.0 and 5.2.0 with exactly the error messages listed in [Subscription Rules](../best-practices/sync-and-subscriptions.md#subscription-rules) (one run). A syntax error, a missing argument, and an unknown function also throw when `registerSubscription` is called; such a subscription is never registered silently without delivering anything. A projection combined with `DISTINCT` or `GROUP BY` reports the projection error first. A subscription to a `system:` collection is registered.
- **Part of a composite ID**: a subscription with `WHERE _id.storeId = :s` delivered only the documents of that store. A document whose `_id` is a string and that holds the same `storeId` in another field did not arrive. `CREATE INDEX ... (_id.storeId)` also works, and the local query then uses an index scan (one run on 5.1.0 and 5.2.0).
- **Directives**: subscriptions with directives (`USE INDEX 'idx_status'`, `USE INDEX ''`, `/*+ {...} */`, and `USE INDEX 'nope'` for an index that does not exist) were registered without an error. Each registered on its own peer, every one of them delivered only the matching document, the one `open` document (one run on each of 5.1.0 and 5.2.0). A directive in a subscription does not break it.

**Used in:** [Subscription Rules](../best-practices/sync-and-subscriptions.md#subscription-rules), [Testing Subscription Rules](../best-practices/testing.md#testing-subscription-rules), [Composite IDs for permission scoping and grouping](../best-practices/data-modeling.md#composite-ids-for-permission-scoping-and-grouping), [Directives](../best-practices/indexing-and-performance.md#directives), [clock() in a subscription uses the sending device's clock](clocks-and-time.md#clock-in-a-subscription-uses-the-sending-devices-clock).

### A LIMIT in a subscription limits only the first download

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; the same result on both releases |
| Setup | The sending device held ten documents, `i01` to `i10`, with `rank` 1 to 10. The receiving device set `DQL_RESTRICT_SUBSCRIPTIONS` to `false` and subscribed with `SELECT * FROM items ORDER BY rank LIMIT 3`. After the first sync, the sending device inserted `i11` and `i12` and updated `i09` |

- The first sync delivered only the three documents `i01` to `i03`.
- The documents created afterwards (`i11` and `i12`) and the updated `i09`, which was outside the first three, arrived as well. On both releases, the receiving device ended with `["i01","i02","i03","i09","i11","i12"]`.

**Used in:** [LIMIT and ORDER BY in subscriptions](../best-practices/sync-and-subscriptions.md#limit-and-order-by-in-subscriptions).

### Documents that leave a subscription stay as frozen copies

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; the same result on both releases |
| Setup | The receiving device subscribed to `status = 'open'` and received the document `{"status": "open", "title": "v1"}`. The writer changed `status` to `'closed'`, then changed `title`, and then deleted the document, waiting 10 seconds after each of the last two steps |

- The change to `closed` arrived. Neither the later change of `title` nor the deletion arrived: the document stayed on the receiving device as `{"status": "closed", "title": "v1"}`.

**Used in:** [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay).

### Subscriptions are not stored in the persistence directory

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; the checks after `cancel()` and after stopping and starting sync: one run on each release, with the same result on all three |
| Setup | A hub and a client, both subscribed to the whole collection. The client received a document and closed Ditto. While it was closed, the hub updated that document and inserted a new one. The client opened the same directory again without registering its subscription, reconnected, and wrote a new document of its own. 8 seconds later, it registered the subscription again |

- After `close()`, the reopened directory had no subscriptions: `ditto.sync.subscriptions` was empty, against one entry before closing (the same on all three releases).
- **5.1.0 and 5.2.0**: until the subscription was registered again, neither the update of the document that the client held nor the new document arrived within 8 seconds. The client kept reading the earlier value, without an error or a warning: the same state as a frozen copy (see [Documents that leave a subscription stay as frozen copies](#documents-that-leave-a-subscription-stay-as-frozen-copies)).
- **5.0.3**: the new document did not arrive, but the update of the document that the client held, made while the client was closed, did arrive (in all three runs). On 5.1.0 and 5.2.0 it does not. The difference is limited to reopening: on 5.0.3 too, updates of documents the client held did not arrive after a subscription was cancelled with `cancel()` while Ditto was running, or after sync was stopped and started again, and a document that stopped matching a subscription stayed as a frozen copy.
- The document that the client wrote reached the hub, although the client had no subscription. Whether a change travels depends on the subscriptions of the receiving device (the same on all three releases).
- After the client registered the subscription again, the update and the new document both arrived within about 110 ms (the same on all three releases).

**Used in:** [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle), [Complete app startup](../best-practices/setup-and-lifecycle.md#complete-app-startup).

### Sync scopes behaved as documented on SDK 5.2.0

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the same results on both releases |
| Setup | The sending device held documents in a collection `drafts`, which it gave a sync scope, and in a collection `shared` without a scope; another Small Peer subscribed to both. The scopes were set with `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` before `sync.start()` |

| Scope of `drafts` on the sending device | Did the other Small Peer receive `drafts`? |
|---|---|
| `LocalPeerOnly` | No, not within 10 seconds, although it subscribed |
| `BigPeerOnly` | No, not within 10 seconds, although it subscribed |
| `SmallPeersOnly` | Yes |

- `shared`, which had no scope, arrived in every case.
- When only the receiving device set `drafts` to `LocalPeerOnly`, it still received the documents: a scope takes effect on the device that sends.
- When the sending device set `LocalPeerOnly` while sync was running, neither later updates of documents it had already sent nor new documents arrived: the copies already sent stayed as frozen copies.
- A second `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` that left out `drafts` replaced the whole map with `{"shared": "LocalPeerOnly"}`, and updates of `drafts` arrived again right away.
- A collection name that starts with `__`, such as `__presence`, was rejected with `Key "__presence" failed validation with predicate Not(StartsWith("__"))`.

**Used in:** [Sync Scopes](../best-practices/sync-and-subscriptions.md#sync-scopes).

### Relay, rewrite, and subscription behavior held on SDK 5.2.0

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; the same results on both releases |
| Setup | Five separate checks, one for each item below |
| Documentation | A comment in the JavaScript SDK's type definitions describes the sync group as "This is an optimization, not a security control" |

- **A relay with a narrower subscription**: when the relay subscribed only to `ta`, a device behind it received only `ta`, although `ta` and `tb` were written in one transaction. When the relay also subscribed to `tb`, `tb` arrived within about 0.1 seconds.
- **Rewriting the current value**: an `UPDATE` and a `DO UPDATE` that wrote the current value called a `SELECT *` observer on the other device once. `DO UPDATE_LOCAL_DIFF`, and an `UPDATE` whose `WHERE ... != :status` left out the documents that would not change, did not call it.
- **Peers with different strict-mode settings**: a nested `SET` on the strict peer failed with `Unsupported DML operation on REGISTER field "obj"`. After the non-strict peer ran `SET obj.c = 3`, an undeclared `SELECT` on the strict peer showed the REGISTER value `{a: 1, b: 1}`, while the non-strict peer showed the MAP value `{c: 3}`: the same field held two values side by side. A map written by the non-strict peer did not appear in an undeclared `SELECT *` on the strict peer. After concurrent edits, the two peers still showed different values.
- **Sync groups**: peers in sync groups 1 and 2 synced when they were connected explicitly over TCP.
- **Duplicate subscriptions**: two registrations of the same subscription appeared as two entries in `subscriptions`. Sync continued after one of them was cancelled and stopped when both were. The documents already received stayed after the cancel.

**Used in:** [Transactions and Sync](../best-practices/transactions.md#transactions-and-sync), [Prefer field-level updates over whole-document rewrites](../best-practices/dql.md#prefer-field-level-updates-over-whole-document-rewrites), [Peers with different settings](../best-practices/data-modeling.md#peers-with-different-settings), [Transport Configuration](../best-practices/setup-and-lifecycle.md#transport-configuration), [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle), [Cancelling subscriptions and local data](../best-practices/sync-and-subscriptions.md#cancelling-subscriptions-and-local-data).

## The Cost of Registering Subscriptions

### The number of subscriptions did not change the transfer

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; nearly the same results on both releases |
| Setup | 300 documents with 1 KB of random content each. The receiving device registered its subscriptions before it started sync, and a TCP relay between the two devices (see [How We Tested](how-we-tested.md#test-environment)) counted the bytes |

- With 300 subscriptions with `_id = :id`, with one subscription with `_id IN :ids`, and with one subscription for the whole collection, the first sync took 206 to 208 ms and about 318 to 320 KiB. An update of all 300 documents took 115 to 120 ms and about 9.3 KiB. Five idle seconds carried 0.1 KiB in every case.
- Registering the 300 subscriptions took 7 ms.
- When the sending device holds a large collection, the number of subscriptions does cost. On a hub with 50,000 documents, each subscription that a connected device added made the hub read the whole collection again, for about 0.1 seconds of CPU for the device's first subscription and about 0.2 seconds for its tenth (see [Each new subscription makes the data holder read the whole collection](#each-new-subscription-makes-the-data-holder-read-the-whole-collection)). The 300 subscriptions here were registered before sync started, on a collection of 300 documents, so that cost did not show.

**Not tested:** thousands of subscriptions, and sync with Ditto Server.

**Used in:** [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle).

### Each new subscription makes the data holder read the whole collection

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; all nine runs showed the same trend. Run alone, with the other checks stopped, on a 14-core Mac. The subscription by `_id` as the device's first subscription: one run on each release |
| Setup | A hub and a device, each in its own process, connected directly over TCP, and started again for each case. The hub held orders with 200 bytes of random content, 50 per customer, 50,000 or 200,000 in total; with 50,000, we compared the hub with and without an index on `customerId`. The device registered `SELECT * FROM orders WHERE customerId = :c` one at a time. We measured the time until the 50 documents of a customer had arrived, and the CPU time of the hub's process until 1 second after that |

Hub CPU time (and, where given, the time until the documents had arrived) with 50,000 documents. The CPU time includes 1 to 1.5 seconds of idle time in each measurement (1 to 6 ms per second):

| Case | 5.2.0 | 5.1.0 | 5.0.3 |
|---|---|---|---|
| The same query run on the hub, without an index (query time) | 49 to 50 ms | 66 to 72 ms | 129 to 132 ms |
| The same query run on the hub, with an index on `customerId`; `EXPLAIN` shows `indexScan` (query time) | 2.2 to 2.3 ms | 2.2 to 2.3 ms | 2.3 to 2.6 ms |
| A subscription that matches nothing (the device's first subscription) | 93 to 108 ms | 101 to 106 ms | 167 to 179 ms |
| The first customer subscription (the device's second) | CPU 113 to 115 ms; 50 documents after 97 to 104 ms | CPU 119 to 127 ms; 104 to 117 ms | CPU 180 to 190 ms; 167 to 180 ms |
| The tenth customer subscription (the device's eleventh) | CPU 215 to 223 ms; 208 to 224 ms | CPU 224 to 228 ms; 224 to 232 ms | CPU 305 to 315 ms; 303 to 328 ms |
| Ten registered one at a time, total CPU | 1,647 to 1,669 ms | 1,731 to 1,825 ms | 2,456 to 2,502 ms |
| Ten registered at the same time by a connected device | CPU 318 to 327 ms; 500 documents after 293 to 305 ms | CPU 337 to 341 ms; 317 to 329 ms | CPU 470 to 487 ms; 444 to 456 ms |
| Ten registered before sync started | CPU 265 to 275 ms; 253 to 266 ms | CPU 276 to 279 ms; 256 to 267 ms | CPU 352 to 362 ms; 332 to 346 ms |
| Cancelling one subscription (of 14, one of them a duplicate of another) | 6 to 7 ms | 4 to 5 ms | 336 to 349 ms |
| The device, with the remaining 13 subscriptions (12 distinct), reconnects after a 2-second disconnection, during which one new order was written | 51 to 54 ms | 45 to 49 ms | 45 to 55 ms |

The same with 200,000 documents (the index was compared only with 50,000):

| Case | 5.2.0 | 5.1.0 | 5.0.3 |
|---|---|---|---|
| The same query run on the hub, without an index (query time) | 191 to 199 ms | 267 to 273 ms | 519 to 525 ms |
| A subscription that matches nothing (the device's first subscription) | 369 to 384 ms | 415 to 423 ms | 663 to 684 ms |
| The first customer subscription (the device's second) | CPU 421 to 433 ms; 50 documents after 355 to 365 ms | CPU 456 to 464 ms; 387 to 399 ms | CPU 705 to 715 ms; 628 to 642 ms |
| The tenth customer subscription (the device's eleventh) | CPU 831 to 838 ms; 773 to 782 ms | CPU 870 to 880 ms; 811 to 822 ms | CPU 1,157 to 1,169 ms; 1,085 to 1,093 ms |
| Ten registered one at a time, total CPU | 6,271 to 6,324 ms | 6,671 to 6,732 ms | 9,320 to 9,470 ms |
| Ten registered at the same time by a connected device | CPU 1,165 to 1,208 ms; 500 documents after 1,037 to 1,079 ms | CPU 1,249 to 2,153 ms; 1,128 to 1,522 ms | CPU 1,777 to 1,878 ms; 1,605 to 1,702 ms |
| Ten registered before sync started | CPU 855 to 919 ms; 776 to 899 ms | CPU 883 to 896 ms; 804 to 821 ms | CPU 1,148 to 1,169 ms; 1,061 to 1,073 ms |
| Cancelling one subscription (of 14, one of them a duplicate of another) | 6 to 8 ms | 5 ms | 1,269 to 1,284 ms |
| The device, with the remaining 13 subscriptions (12 distinct), reconnects after a 2-second disconnection, during which one new order was written | 51 to 57 ms | 46 to 49 ms | 47 to 54 ms |

- **An index does not change how a subscription is served.** The index on `customerId` made the query on the hub about 22 times faster (5.0.3: about 55 times), but the time and the CPU for serving the subscriptions were the same as without the index in every row. Subscriptions do not use indexes.
- **The cost is proportional to the size of the collection.** Even a subscription that matched nothing cost about 100 ms of CPU with 50,000 documents and about 375 ms with 200,000 (on 5.2.0, about 2 µs per document). Sending the 50 documents accounted for about 10 ms; nearly all of the cost is reading the collection again.
- **The cost grows with the number of the device's subscriptions.** Each added subscription raised the hub's CPU by about 12 ms with 50,000 documents (5.0.3: about 14 ms) and by about 45 ms with 200,000 (5.0.3: about 50 ms). It grew steadily in all nine runs on every release. The subscriptions of other devices do not count: the first subscription of a second device (with the same condition) cost 97 to 101 ms (5.1.0: 104 to 112; 5.0.3: 168 to 176), although the first device held 11 subscriptions, and from the second device's second subscription on, the cost grew by the same steps again. We think the hub reads the whole collection again, with the combined condition of all of that device's subscriptions, every time the device adds one.
- **Filtering by `_id` does not avoid it.** Compared as the device's first subscription, `_id = :id` (one document) cost 109 to 117 ms of CPU on 5.1.0 and 5.2.0 (5.0.3: 161 ms), the same as `customerId = :c` at 107 to 123 ms (5.0.3: 162 to 169 ms). The one document took 91 to 92 ms to arrive (5.0.3: 154 ms). `_id IN :ids` (50 documents) cost 149 to 151 ms (5.0.3: 183 ms). Even the primary key does not avoid the read (one run on each release).
- **Registering together costs a fraction.** The total CPU for ten subscriptions was about a fifth of registering them one at a time when they were registered at the same time (in one run on 5.1.0 with 200,000 documents, about a third), and about a sixth to an eighth when they were registered before sync started. The time until all 500 documents had arrived was, on 5.2.0, 1.57 to 1.62 seconds with 50,000 documents and 5.7 seconds with 200,000 when each of the ten was registered after the previous one had arrived (the sum of the ten; 5.1.0: 1.68 to 1.74 seconds and 6.1 seconds; 5.0.3: 2.4 seconds and 8.6 to 8.7 seconds), 0.29 to 0.31 seconds and about 1.04 to 1.08 seconds when they were registered at the same time, and 0.25 to 0.27 seconds and 0.78 to 0.90 seconds, including the time to connect, when they were registered before sync started.
- **Registering the same subscription again costs almost nothing.** When the same device registered the same subscription a second time, the hub used 2 to 6 ms of CPU with 50,000 documents and 3 to 6 ms with 200,000, on every release.
- **Cancelling costs almost nothing on 5.1 and later.** On 5.0.3, a cancel made the hub read the collection again, about as much as adding a subscription.
- **Reconnecting does not repeat the read.** When a device with 13 subscriptions (12 distinct) reconnected after a 2-second disconnection, the hub used 45 to 57 ms of CPU, less than one read of the collection. The new order arrived after 14 to 139 ms; we think the spread comes from the reconnection retry cycle, which we did not compare.
- On 5.0.3, every read of the collection took about 1.5 to 1.8 times as long as on 5.1 and later.

**Not tested:** a hub with more than one collection (whether the documents of other collections add to the cost); more than one hub, or more than four devices; Ditto Server as the device that holds the data; whether the size of the documents (200 bytes here) or the number of their fields changes the cost per document; long disconnections; and a device restart, after which the device registers its subscriptions again (see [Subscriptions are not stored in the persistence directory](#subscriptions-are-not-stored-in-the-persistence-directory)). We think a restart resembles the case of subscriptions registered before sync starts.

**Used in:** [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle), [Where indexes live](../best-practices/indexing-and-performance.md#where-indexes-live).

## Relays, Hubs, and Carriers

### A relay forwards only the documents that it holds

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the same results on both releases |
| Setup | Four peers in a line, 0–1–2–3, each connected only to the previous one |

- When every peer subscribed to the whole collection, an insert, an edit, and a `DELETE` on one end passed the three hops and reached the other end in about 0.1 seconds (we checked every 0.1 seconds).
- When the two peers in the middle subscribed only to `status = 'open'`, a document that had never been open did not reach the far end. An open document arrived, and so did the change that closed it, but edits made after it was closed did not arrive within 8 seconds. When the document was opened again, it arrived in its latest state (`status: 'open', v: 3`).

**Used in:** [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay).

### With two relays, sync continued when one of them stopped

| | |
|---|---|
| Observed on | SDK 5.2.0, six runs of each case, and SDK 5.1.0, five runs of each case; the same trend on both releases |
| Setup | Devices A and C each connected over TCP to two relays, B and D; A and C were not connected to each other. Each of the four ran in its own process. A rewrote the same document, and we measured the time until C had the new value (C read every 20 ms, so the times include up to 20 ms for that). B was then suspended with SIGSTOP, like an app that stops with its connections open, and later killed with SIGKILL |

- **All four devices subscribed**: while both relays ran, after B was suspended, and after B was killed, updates reached C in about 30 ms. The first update right after B was suspended took 0.8 to 4.0 seconds in 5 of the 11 runs (5.2.0: 855, 859, and 3,963 ms; 5.1.0: 847 and 837 ms); from the second update on, about 30 ms. The first update right after B was killed was not delayed in any of the 11 runs. 12 seconds after the suspension, B was no longer in C's presence graph (see [A suspended device leaves the presence graph after about 9 seconds](connections-and-presence.md#a-suspended-device-leaves-the-presence-graph-after-about-9-seconds)).
- Before the suspension too, the first update took 0.4 to 1 second three times (5.2.0: 435 ms; 5.1.0: 942 and 1,011 ms).
- **D subscribed to nothing**: D held no documents throughout. After B was killed, A's updates did not reach C within 15 seconds (all 11 runs), while C's presence graph still listed A and D (with one connection for A). A device without subscriptions relays nothing.
- For a few seconds after B was killed, the number of peers in C's presence graph sometimes dropped: 1 where 2 were expected, and once on 5.2.0, 0 peers 2 seconds after the kill. An offline indicator that follows the number of peers in the presence graph can therefore show offline for a moment when only one of two relays fails.

**Used in:** [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay), [Key Characteristics](understanding-ditto.md#key-characteristics).

### Each relay hop added about 4 ms

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each (in the second run, each hop was 0 to 4 ms faster) |
| Setup | Six peers in a line, all subscribed. The first peer updated a document ten times, and we took the median time until each peer's observer had the new value |

Median time until the observer had the new value (first run):

| Peer | 5.2.0 | 5.1.0 |
|---|---|---|
| The writer's own observer | 4.9 ms | 5.1 ms |
| 1 hop away | 9.1 ms | 9.2 ms |
| 2 hops | 12.9 ms | 12.9 ms |
| 3 hops | 16.2 ms | 16.0 ms |
| 4 hops | 19.0 ms | 18.5 ms |
| 5 hops | 21.1 ms | 20.7 ms |

- Each hop added about 3 to 4 ms. In the slowest run too, the far end had the value within 23 ms.
- The peers ran on one Mac over TCP. On real devices, each hop adds its network round trip; the numbers show only that the hops themselves cost little.

**Used in:** [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay).

### Devices that move between sites carry documents and deletions

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; all nine runs gave the same results |
| Setup | Two hubs, A and B, that never connected to each other, both subscribed to the whole collection. One device moved between them by changing its `connect.tcpServers` from A to B and back, without stopping sync (see [TCP targets and listeners change while sync runs](connections-and-presence.md#tcp-targets-and-listeners-change-while-sync-runs)). A and B each wrote one order for site A and one for site B |

- **The carrying device subscribed to the whole collection**: after it had visited A, B received A's two orders within 3 seconds of the device moving to B, and the device received B's two. Back at A, A received B's two orders. A document deleted at A also disappeared from B on the device's next visit to B.
- **The carrying device subscribed only to `site = 'B'`**: only the documents for site B were carried. B did not receive the order for site A written at A, although hub B subscribed to the whole collection, and A did not receive the order for site A written at B, although it matched hub A's subscription too. Whether a document is carried depends on the subscription of the carrying device, not on that of the destination.
- The presence graph of the hub that the device was visiting did not list the other hub.
- **A large data set and a short visit**: to carry 20,000 documents of about 400 bytes written at A, the device first visited A for 1 second. None of the documents appeared on the device, and the following visit to B delivered nothing (an initial sync appears only when it completes; see [An initial sync appears on the receiving device all at once](#an-initial-sync-appears-on-the-receiving-device-all-at-once)). On its next visit to A, the device had all of them after 0.54 to 0.55 seconds on 5.0.3 and 0.89 to 1.0 seconds on 5.1.0 and 5.2.0, and on the visit to B after that, B had all of them after 1.2 to 1.5 seconds. The content was the same character repeated, which sync compresses (see [Sync traffic is compressed and carries field-level changes](#sync-traffic-is-compressed-and-carries-field-level-changes)), so real data takes longer.

**Not tested:** how long carrying the 20,000 documents takes without the short first visit. This test therefore cannot tell whether the part received during the 1-second visit was kept (that an interrupted initial sync resumes where it stopped is shown in [An interrupted initial sync resumes where it stopped](#an-interrupted-initial-sync-resumes-where-it-stopped)).

**Used in:** [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay).

### A new, empty hub recovers the data from its clients

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, six runs each (the collection that only the hub held was added in the last three runs); the same results in every run on both releases |
| Setup | A hub and three clients, all subscribed to every document. Two clients wrote 500 documents each. The third received all of them and stopped sync, so that it held copies from before the deletion. One client deleted 50 documents with `DELETE`. The hub then closed, and 1 second later a new hub with an empty directory opened on the same port. Finally, the third client started sync again |

- The new hub held all 950 live documents about 4.1 seconds after it opened. Most of that time was the clients' `connect.retryInterval` of 5 seconds before they reconnected (see [A lost TCP connection is retried at the retry interval](connections-and-presence.md#a-lost-tcp-connection-is-retried-at-the-retry-interval)).
- The 50 deleted documents did not come back on the new hub either: the tombstones that the clients hold reach the new hub too.
- When the third client, stopped since before the deletion, came back, the 50 documents came back on no device, and they disappeared from the third client as well.
- Documents that only the old hub held, in a collection `hubNotes` that no client subscribed to, were not recovered, even when the new hub subscribed to that collection (0 documents in all three runs).
- After the tombstones have been reaped, deleted documents do come back, as [A device with an old copy resurrects a document after its tombstone is reaped](storage-and-deletion.md#a-device-with-an-old-copy-resurrects-a-document-after-its-tombstone-is-reaped) describes.

**Used in:** [Transport Configuration](../best-practices/setup-and-lifecycle.md#transport-configuration).

## How an Initial Sync Arrives

### An initial sync appears on the receiving device all at once

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each (100,000 documents: one run on 5.2.0) |
| Setup | A hub held the documents. A new device subscribed to the collection, started sync, and counted the documents with `SELECT COUNT(*)` every 100 ms |

Time from the start of sync until all documents were visible (first run):

| Documents | Size of each | 5.2.0 | 5.1.0 |
|---|---|---|---|
| 1,000 | 500 bytes | 310 ms | 313 ms |
| 5,000 | 500 bytes | 726 ms | 724 ms |
| 20,000 | 500 bytes | 2,487 ms | 2,378 ms |
| 1,000 | 10 KB (9.5 MiB in total) | 311 ms | 309 ms |
| 100,000 | 500 bytes (48 MiB in total) | about 11.5 s | not tested |

- At every size, the first document became visible at the same moment as the last one. With 20,000 documents, 24 checks over about 2.4 seconds after sync started returned 0, and the next one returned 20,000. With 100,000 documents, the count stayed at 0 for 11.5 seconds.
- Local reads did not wait meanwhile: `COUNT(*)` on the same collection and reads of another collection returned within 2 ms. The initial sync is applied in one step at the end; the reads were not held back (confirmed in the second run on both releases).
- In this environment, the time depended on the number of documents; their size had little effect. 1,000 documents of 10 KB took as long as 1,000 documents of 500 bytes.
- The transfer was about 1.1 times the size of the content (random content, which does not compress).

**Not tested:** mobile devices and transports other than TCP, such as Bluetooth LE. The times there probably differ a lot, so do not use the numbers above as estimates.

**Used in:** [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle).

### An interrupted initial sync resumes where it stopped

| | |
|---|---|
| Observed on | SDK 5.1.0 (two runs) and 5.2.0 (three runs; the stop after half of the data had arrived: two runs) |
| Setup | As above, with 50,000 documents of 500 bytes, and a TCP relay between the two devices (see [How We Tested](how-we-tested.md#test-environment)) that counted the bytes. The receiving device interrupted the initial sync with `sync.stop()` and resumed it with `sync.start()` |

| Case | Result |
|---|---|
| No interruption | About 5.9 seconds in total: for the first 3.5 seconds or so, only 0.1 MiB flowed; then 26 MiB flowed in 0.5 seconds, and the receiving device spent the last 2 seconds or so applying them. The count stayed at 0 throughout and then jumped to 50,000 |
| Stopped before data flowed (at about 2.9 seconds) and resumed 1 second later | Done 2.3 to 2.4 seconds after resuming, sooner than the 5.9 seconds of a new start |
| Stopped after 17 to 19 MiB had arrived, then resumed | Only the remaining 7 to 9 MiB flowed after resuming, and the sync was done in 2.3 to 2.4 seconds. The data that had arrived was kept, although the count was still 0 when sync stopped |
| Stopped for 0.5 seconds every 3 seconds | Done in the second period |

The results were the same on both releases.

**Not tested:** Bluetooth LE and other transports, and a connection that drops instead of `sync.stop()`.

**Used in:** [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle).

### A large initial sync holds up the device's other sync

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each with the peers in one process, and three more runs each with each peer in its own process |
| Setup | A hub and a device. The device subscribed for the first time to 30,000 documents of 500 bytes each. 0.2 to 6 seconds later, the hub wrote one document to another collection, `alerts`, and the device wrote one to `orders`. In the second setup, each peer ran in its own process, a second client was connected to the hub, and both clients wrote every 100 ms |

Values are for 5.1.0 and 5.2.0; a number in parentheses right after a value is the value for 5.0.3.

- With one subscription, the initial sync took 1.8 to 2.4 seconds (1.7 to 2.6) and appeared at once (see [An initial sync appears on the receiving device all at once](#an-initial-sync-appears-on-the-receiving-device-all-at-once)). The `alerts` documents that the hub wrote meanwhile arrived together, 0.5 to 0.6 seconds (1.0 to 1.2) after the initial sync completed; the most delayed arrived 1.8 to 2.4 seconds (2.4 to 2.7) after it was written. Documents written after the initial sync arrived in 6 to 97 ms.
- The same happened when `alerts` had been subscribed and synced beforehand: changes for an existing subscription wait too. A document written 0.2 seconds after the initial sync started sometimes arrived together with it.
- The device's writes did not reach the hub for up to 1.3 to 1.9 seconds (1.2 to 1.7) during the initial sync. The device's own `INSERT` took 0.7 to 1.3 seconds on 5.1 and later (5.0.3: at most 0.05 to 0.55 seconds), because it waits until a large incoming change has been applied (see [Large statements delay incoming changes and local writes](transaction-behavior.md#large-statements-delay-incoming-changes-and-local-writes)). The hub's `INSERT` took 2 to 7 ms: the hub's store was not held up. The setup with each peer in its own process, described further down, showed that only the receiving device waits.
- Splitting the 30,000 documents by `shard` into six subscriptions of 5,000 each did not help when the six were registered together: the other sync waited as it did with one subscription.
- Registering the six one at a time, each after the previous part had arrived, took 4.6 to 4.9 seconds in total (9.4 to 9.8), about 2.5 times as long (5.0.3: about 4 to 5 times). In exchange, the `alerts` written meanwhile arrived within at most 1.0 to 1.1 seconds (3.3 to 3.7), the device's writes reached the hub within at most 0.65 to 0.83 seconds (1.0 to 1.2), and the device's `INSERT` took at most 0.19 seconds (0.13).
- **Each peer in its own process** (the same pattern on all three releases): on the receiving device, the `alerts` that the hub wrote meanwhile arrived 0.50 to 0.58 seconds (0.79 to 0.85) after the initial sync completed; the largest delay was 2.08 to 2.16 seconds. The second client of the same hub received the same documents in 34 to 96 ms, and its own writes, each of which took 2 to 5 ms, reached the hub in 34 to 96 ms. Only the receiving device's sync stops; the hub and the other devices keep syncing. The receiving device's writes took 1.20 to 1.29 seconds (0.58 to 0.63), and after that took up to another 0.54 to 0.61 seconds (0.89 to 0.94) to reach the hub. The results with the peers in one process therefore did not come from the peers competing for the CPU.
- We checked this over TCP on `127.0.0.1`. The size of the delays probably depends on the devices and on the speed of the connection.

**Not tested:** whether the receiving device's sync with peers other than the hub that it is directly connected to stops as well.

**Used in:** [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle), [Scope subscriptions to what the device needs](../best-practices/sync-and-subscriptions.md#scope-subscriptions-to-what-the-device-needs).

## Order and Atomicity of Incoming Changes

### Changes written in separate statements arrived in the order written

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each, with the same results on both releases. Orders and items in two collections, and sustained writes: SDK 5.0.3, 5.1.0, and 5.2.0, three runs each |
| Setup | Two devices connected directly. The writer inserted 300 documents, each in its own statement, while the receiving device observed the collection; then the same while the receiving device was offline. The writer also inserted a parent and then a child, in separate statements, 30 times, and the receiving device observed a `LEFT OUTER JOIN` of the two. The setups of the other checks are described with their results below |

- With 300 documents in separate statements, the receiving device's observer was called 16 to 17 times. Every result held the first n documents; a state with a gap never appeared.
- 300 documents written while the receiving device was offline arrived after it reconnected, in 1 or 2 callbacks, also without a gap.
- With parents inserted before their children (30 pairs in separate statements), the receiving device's `LEFT OUTER JOIN` observer never showed a child without its parent.

**Orders and items in two collections.** The writer wrote 30 orders (`orders`), each with 20 items (`orderItems`), and the receiving device received the two collections through separate subscriptions, directly and through one relay device. Right after each callback of one collection's observer, the receiving device read the other collection and counted what was missing. Because the read comes after the callback, this can miss a gap, but it never counts a gap that did not exist.

| How the writer wrote | Orders without all their items | Items without their order |
|---|---|---|
| One transaction | Never (all nine runs, directly and through the relay device) | Never |
| Separate statements, orders first | Seen: 22 to 30 times in total, counted per callback | Never |
| Separate statements, items first | Never | Seen: 5.2.0, 0 to 6 times; 5.1.0 and 5.0.3, 18 to 27 times |

- A transaction arrived whole across the two collections too.
- 5.2.0 more often delivered the arriving changes together.
- Writing the items first and the order last kept "an order that is visible has all its items" in this test, for a receiving device that was connected, directly or through one relay device.
- Writing the items first worked only while every path to the receiving device carried both collections. With a faster relay that subscribed only to the orders, writing the items first failed in 14 of 18 runs, and a backlog received after being offline appeared at once however it had been written (see [A fast relay with narrower subscriptions can show part of a transaction](#a-fast-relay-with-narrower-subscriptions-can-show-part-of-a-transaction)).

**Sustained writes.** The writer kept writing new documents at 100 to 10,000 a second (1, 50, or 100 per statement), and the receiving device queried every 50 ms. Up to 100,000 documents, at every rate, a document never appeared later than a document written after it (by `seq`), also at 10,000 a second on 5.0.3, where the receiving device fell behind (see [One document per statement tops out at about 600 writes a second](performance-measurements.md#one-document-per-statement-tops-out-at-about-600-writes-a-second)).

**Not tested:** whether writing the items first keeps orders complete when the receiving device registers the second subscription later; whether the order of arrival is guaranteed behavior; sustained writes through a relay, or received as a backlog after being offline.

**Used in:** [Transactions and Sync](../best-practices/transactions.md#transactions-and-sync).

### Large transactions and statements arrived all at once

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each, with the same results in every run; closing the receiving device during the transfer: one run on each release |
| Setup | A writer inserted 30,000 documents, and the receiving device observed `COUNT(*)` |

- With 30,000 documents in one transaction, the receiving device's `COUNT(*)` observer went from 0 to 30,000 in one step, after about 1.9 to 2.1 seconds. No intermediate count was visible.
- 30,000 documents in one `INSERT` statement, without a transaction, also appeared in one step, after about 1.7 to 1.8 seconds.
- 2,000 documents inserted one at a time, awaiting each, arrived in 10 steps on 5.1.0 and in 32 to 34 steps on 5.2.0: 5.2.0 delivers in smaller steps.
- Closing the receiving device during the transfer left no partial state. We closed it 0.3, 0.9, and 1.5 seconds after the write. At 0.3 seconds, nothing was kept (`close()` took 35 ms), and after the device reopened and synced, the 30,000 documents arrived at once after 1.8 seconds. At 0.9 and 1.5 seconds, the count before closing was 0, but `close()` took 0.2 to 0.8 seconds, and after reopening, the 30,000 documents were there. We think `close()` waited for the transaction that was being applied.

**Used in:** [Transactions and Sync](../best-practices/transactions.md#transactions-and-sync).

### A fast relay with narrower subscriptions can show part of a transaction

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, six runs of each case (the case without a relay device: three runs each). The backlog after being offline and the items from a second writer: three runs each |
| Setup | Three devices, with each connection going through a TCP relay that counted the bytes and could limit the bandwidth (see [How We Tested](how-we-tested.md#test-environment)). The writer wrote 30 orders (`orders`), each together with its 20 items (`orderItems`), 30 ms apart, in one of three ways: one transaction, two statements with the order first, or two statements with the items first. The receiving device subscribed to both collections. It was connected to the writer directly over a link limited to 20 KB/s, and over a fast link to a relay device, which subscribed either to the orders only or to both collections. For comparison, all links were fast, or there was no relay device and only the slow link. Every 10 ms, the receiving device read the orders, the number of items of each order, and the orders again, counted the orders without all their items and the items without their order, and measured the time until everything was complete; because of the order of the reads, a state that did not exist is never counted. It also counted per observer callback and measured the bytes it received over each link |

Orders visible without all their items: how many, and for how long:

| Case (the receiving device's direct link to the writer) | One transaction | Orders first | Items first |
|---|---|---|---|
| Relay device subscribed to the orders only (slow direct link) | All 30 orders in 6 of 18 runs (median 0.37 to 0.47 seconds, at most 0.50 to 0.66 seconds); 0 or 1 in the other runs | 19 to 30 in 10 of 18 runs (at most 0.24 to 0.52 seconds); 6 to 16 in the others (within 35 ms) | 19 to 30 in 14 of 18 runs (median 0.14 to 0.81 seconds, at most 0.24 to 1.14 seconds); in the others, only items without their order (within 37 ms) |
| Relay device subscribed to both collections (slow direct link) | 0 in all 18 runs | 3 to 17 (within 39 ms) | 0; 1 to 15 items without their order (within 64 ms) |
| Relay device subscribed to the orders only (fast direct link) | 0 in all 18 runs | 2 to 17 (within 34 ms) | 0; 1 to 17 items without their order (within 81 ms) |
| No relay device (only the slow link) | 0 in all 9 runs | 8 to 13 (within 48 ms) | 0; 10 to 15 items without their order (within 53 ms) |

- The runs of the first row by release: one transaction, 5.0.3 0 of 6, 5.1.0 4 of 6, 5.2.0 2 of 6; orders first, 2, 4, and 4 of 6; items first, 2, 6, and 6 of 6. It happened less often on 5.0.3.
- **It happens when the relay device delivers the orders first.** In the runs where it happened, the receiving device had received 3.1 to 4.3 KiB from the relay device, against 1.6 to 1.9 KiB in the other runs. We think the relay device delivered the orders first, and the items followed over the slow direct link. Why the relay device sent the orders in some runs and not in others was not examined. One run with the items first (on 5.1.0) was an exception: the receiving device had received only 1.7 KiB from the relay device, yet 23 orders were visible without their items for 743 ms, and the orders were complete only after 2.0 seconds, later than in the other runs; we did not look into the cause.
- **It takes a partial path together with a slow complete path.** With a relay device that subscribed only to the orders, it did not happen when all links were fast. With the slow link alone, writing the items first never showed an order without its items (as in [Changes written in separate statements arrived in the order written](#changes-written-in-separate-statements-arrived-in-the-order-written)).
- **Writing the items first does not work in this layout.** It holds only when every path to the receiving device carries both collections.
- In every case, everything was complete in the end, after 0.95 to 2.0 seconds.
- **A backlog after being offline**: 300 orders and 6,000 items written while the receiving device was offline appeared at once, after 0.47 to 0.60 seconds, however they had been written, directly or through a relay device that subscribed to both collections. In none of the 54 cases was an order without its items or an item without its order visible: a backlog arrives as one step also when it was written without a transaction.
- **Items written by a second device**: a second device saw each order in its own observer and then wrote its 20 items, and the receiving device was connected only to the second device, or to the first device as well over the slow link. In none of the 18 cases did the items appear on the receiving device before their order. We think this is because the second device sends the order too (the receiving device received the bytes of the orders and of the items from the second device). 4 to 30 orders were visible before their items arrived (within 39 ms), which follows the order in which they were written.

**Not tested:** link speeds other than 20 KB/s; the writes were a little faster than that, so the delay built up slowly. Over a link as slow as Bluetooth LE, the time that orders are visible without their items is probably longer. Layouts other than a triangle. Orders and items kept in one document (the items in a map).

**Used in:** [Transactions and Sync](../best-practices/transactions.md#transactions-and-sync).

## Sync Traffic and Convergence

### Sync traffic is compressed and carries field-level changes

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; nearly the same results on both releases |
| Setup | A TCP relay between the two devices (see [How We Tested](how-we-tested.md#test-environment)) counted the bytes that flowed in the 3 seconds before and after each operation, including TLS and the messages of the sync protocol itself |

| Operation | Transferred |
|---|---|
| Nothing, for 3 seconds | 0.1 KiB |
| First sync of 200 documents, each with a random string of 1 KB (195 KiB of content) | 205.7 KiB |
| A second registration of the same subscription | 0.1 KiB |
| Both registrations cancelled, 5 documents changed, the subscription registered again | 1.2 KiB |
| First sync of 200 documents, each with 1 KB of the same character repeated | 6.3 KiB |
| One field changed in a document of 50 fields of 1 KB random content (50 KB) with `UPDATE ... SET` | 1.3 KiB |
| The same with `DO UPDATE_LOCAL_DIFF` | 1.3 KiB |
| The same with a `DO UPDATE` of the whole document | 1.6 KiB |
| A `DO UPDATE` that changed nothing | 0.5 KiB |

- **Sync traffic is compressed.** Repeated characters made the first sync of 200 documents 6.3 KiB instead of 205.7 KiB, so content that compresses well transfers faster than its size suggests. In an earlier measurement with repeated content, a first sync of 200 KB came to 6.2 KiB: measuring transfer needs content that does not compress.
- A changed field travels as a field-level change however it was written; a `DO UPDATE` of the whole document cost little more than `UPDATE ... SET` (1.6 against 1.3 KiB).
- A `DO UPDATE` that changed nothing still produced sync traffic (0.5 KiB), which wakes an observer on the other device (see [Relay, rewrite, and subscription behavior held on SDK 5.2.0](#relay-rewrite-and-subscription-behavior-held-on-sdk-520)).
- Registering the same subscription a second time transferred almost nothing, and registering it again after a cancel fetched only what had changed in between.

**Used in:** [What Syncs after Offline Edits](crdt-types.md#what-syncs-after-offline-edits), [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle), [Document Size Limits](../best-practices/data-modeling.md#document-size-limits).

### Only the current state syncs after offline edits

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each |
| Setup | A TCP relay between the two devices (see [How We Tested](how-we-tested.md#test-environment)) counted the bytes. The writer wrote while the receiving device had stopped sync with `sync.stop()`. We counted from the receiving device's `sync.start()` until it had caught up, and for 3 seconds after that |

| Written while the receiving device was offline | Transferred | Time until caught up |
|---|---|---|
| Nothing (reconnecting only) | 5.2.0: 4.1 KiB; 5.1.0: 5.8 KiB | 5.2.0: 54 ms |
| One `UPDATE` | 5.2.0: 4.3 KiB; 5.1.0: 5.2 KiB | — |
| 1,000 `UPDATE`s of the same field | 5.2.0: 4.2 KiB; 5.1.0: 5.3 KiB | 5.2.0: 56 ms; 5.1.0: 57 ms |
| A random string of 1 KB rewritten 1,000 times (1 MB written in total) | 5.2.0: 5.5 KiB; 5.1.0: 6.3 KiB | 5.2.0: 110 ms; 5.1.0: 57 ms |
| 1,000 new documents of 100 bytes | 136.9 KiB on both releases | 5.2.0: 163 ms; 5.1.0: 111 ms |

- What syncs is the current state of each document, not the history of the writes: 1,000 updates of one field cost about as much as one. The intermediate values never reach other devices.

**Used in:** [What Syncs after Offline Edits](crdt-types.md#what-syncs-after-offline-edits).

### In a mesh, a new document arrives once from each neighbor

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; the transfer showed the same pattern in all nine runs, with no difference between releases. Writes 45 seconds apart: one run on 5.2.0 |
| Setup | Six peers in one process, all subscribed to `SELECT * FROM notes`, each listening on its own port. Every connection went through a TCP relay that counted the bytes in both directions (see [How We Tested](how-we-tested.md#test-environment)), which gave the transfer of the whole mesh and what each peer received. Four layouts: a hub (5 connections), a line (5), a ring (6), and a full mesh (15). Every peer had the other five in `remotePeers`, and we measured only after each peer's direct connections matched the layout. The content was random strings of 1 KB, which hardly compress |

Transfer of the whole mesh, as a multiple of the bytes that the other five peers need to receive each document once. Even with each document delivered once, the protocol's overhead makes this about 1.16 to 1.24:

| Writes | Hub | Line | Ring | Full mesh |
|---|---|---|---|---|
| One peer writes 100 new documents, 20 ms apart | 1.24 | 1.24 | 1.45 to 1.57 | 4.67 to 5.13 |
| One peer writes 10 new documents, 1 second apart | 1.26 to 1.32 | 1.26 to 1.33 | 1.50 to 1.54 | 5.97 to 6.27 |
| One peer replaces one 1 KB value 20 times, 100 ms apart | 1.24 to 1.29 | 1.24 to 1.27 | 1.38 to 1.41 | 1.96 to 2.03 |
| Six peers each write 20 new documents at the same time | 1.16 to 1.19 | 1.17 to 1.22 | 1.37 to 1.62 | 4.11 to 4.55 |

- **In a full mesh, a document arrives from every neighbor.** With 10 documents written 1 second apart, every peer received 57 to 61 KiB (in the hub layout, 11 to 12 KiB): once from the writer and once from each of the other four, five times in all. With 100 documents written 20 ms apart, the peers received 355 to 526 KiB each (about 3 to 4.5 times the hub layout); the shorter interval gave somewhat fewer duplicates.
- **Spacing the writes out does not reduce it.** In a full mesh with one document written every 45 seconds, each peer received 4.5 to 5.5 KiB in 45 seconds without a write. In 45 seconds with one write, the peers that did not write received 10.5 to 14.5 KiB, and the writer 4.6 to 7.6 KiB (one run on 5.2.0, three documents). The difference of about 6 to 7 KiB is about five copies. We think the duplicates come not from writes competing with each other but from each peer passing a document on to its neighbors right away, while it does not yet know that they have received it over another path. This test cannot tell whether a peer sends without checking or only learns too late.
- **In a ring, only the peer farthest from the writer receives a document twice**, from both sides (213 KiB, against 112 to 121 KiB for the other peers). The other peers received it once; in one of the nine runs, on 5.0.3, a neighbor of the farthest peer also received 172 KiB.
- **Updates of existing documents are duplicated less.** In a full mesh too, each peer received 35 to 38 KiB, about 1.6 times the 23 KiB of the hub layout.
- **Idle traffic is small in every layout**: 0.3 to 1 KiB in 5 seconds (1 KiB with the 15 connections of the full mesh).
- **Time until all peers agreed**: the 120 documents that six peers wrote at the same time took 0.45 to 0.52 seconds in the hub layout and in the line (about the time it took to write them), 1.16 to 1.33 seconds in the full mesh, and 0.48 to 1.15 seconds in the ring (5.0.3: about 0.5 seconds in all three runs; 5.1.0: about 1.1 seconds in all three; 5.2.0: 0.48 to 1.15 seconds). All peers ran in one process and competed for the CPU, so the differences cannot be put down to the layout alone.

**Not tested:** more than six peers, and links other than TCP on one Mac, which have almost no latency. Over transports on which devices choose their connections themselves, such as Bluetooth LE, LAN, and AWDL, the number and shape of the connections differ (on 5.2.0, devices that could all connect to each other kept about six connections each; see [A full TCP mesh keeps about six direct connections per device on 5.2.0](connections-and-presence.md#a-full-tcp-mesh-keeps-about-six-direct-connections-per-device-on-520)). Whether links with a high latency increase or reduce the duplicates. Sync through Ditto Server.

**Used in:** [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay), [Key Characteristics](understanding-ditto.md#key-characteristics).

### Convergence after simultaneous reconnects grew faster than the number of devices

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each. Run alone, with the other checks stopped, on one 14-core Mac running 6 to 21 processes |
| Setup | A hub and devices, each in its own process, started again for each case; the hub's TCP connection limit was 40. Each device stopped sync, confirmed that it was disconnected, and wrote orders with 200 bytes of random content, each in its own commit, incrementing a COUNTER in a shared document by 1 for each order. Then all devices started sync at the same time, or 0.5 seconds apart. The hub and the devices queried the number of orders and the COUNTER every 100 ms and recorded when they were complete |

In all 81 runs (9 cases × 3 releases × 3 runs), the hub and every device ended with all the documents they subscribed to and with a COUNTER that included every device's increments (at most 20 devices × 1,000 = 20,000). No COUNTER increment made offline was lost.

Times below are from the moment the first device started sync. Because they come from queries every 100 ms, they are accurate to about 0.1 seconds. Values are for 5.2.0. Parentheses of the form (x / y) give the values for 5.1.0 / 5.0.3, and "same" means the same as on 5.2.0; other parentheses are explanations.

**All devices subscribed to all orders and started at the same time:**

| Devices × orders on each | The hub had all orders | All devices complete | A new document, written by the hub 1 second after the start, reached the devices |
|---|---|---|---|
| 5 × 200 | 0.11 s | 0.32 to 0.33 s (0.33 / 0.44 to 0.45) | 0.04 to 0.06 s (same / 0.05 to 0.08); written after the devices were complete |
| 10 × 200 | 0.32 to 0.43 s | 0.96 to 0.97 s (0.97 to 0.99 / 1.1 to 1.3) | 0.06 to 0.08 s (0.06 to 0.19 / 0.10 to 0.32); written around the time they were complete |
| 20 × 200 | 0.64 to 0.75 s | 3.7 to 4.0 s (3.8 to 3.9 / 3.5 to 3.7) | 1.6 to 3.0 s (1.2 to 2.9 / 1.6 to 3.2) |
| 20 × 1,000 | 1.7 to 1.8 s (1.8 / 2.6 to 2.7) | 16.8 to 18.0 s (17.2 / 15.6 to 17.7) | 10.4 to 17.1 s (9.5 to 16.9 / 9.4 to 16.5) |

- The hub received everything within a few seconds. The time goes into each device receiving all the other devices' orders: what leaves the hub is the number of devices × the number of other devices × the number of orders. From 5 to 10 devices (twice as many), the time tripled, and with 20 devices (four times as many) it was about 12 times as long, about the 1.8th power. Because what leaves the hub grows with the square of the number of devices, we think the growth comes closer to the square with more devices. The cases with 5 and 10 devices used 10 to 60 percent of this Mac's CPU.
- Once things had settled, a document written by the hub reached all devices within 0.1 seconds (the query interval) in every case. A document written during the reconnection waits behind the changes that the devices had collected, as in [A large initial sync holds up the device's other sync](#a-large-initial-sync-holds-up-the-devices-other-sync).
- The writers' `INSERT`s waited too: with 20 × 1,000, the hub's `INSERT` took 0.67 to 0.74 seconds (0.75 to 0.78 / 1.36 to 1.45); with 20 × 200, a device's `INSERT` took 0.97 seconds in one of three runs (5.1.0: 0.83 seconds in one of three runs; 5.0.3: 0.14 to 0.24 seconds in all three) (see [Large statements delay incoming changes and local writes](transaction-behavior.md#large-statements-delay-incoming-changes-and-local-writes)).
- With 20 devices, the hub (about 2 cores) and the devices (9 to 10 cores in total) used about 80 percent of this Mac's CPU. On real devices, each device has its own CPU, so the times with 20 devices may be shorter there. The case with 5 devices used about 1.8 cores.

**Started 0.5 seconds apart** (20 × 200; the last device started 9.5 seconds after the first, and the new document was written after 5 seconds):

- All devices were complete after 10.1 seconds (11.4 to 11.6 / 10.6 to 10.7), later than with a simultaneous start (about 4 seconds). The last device was complete 0.6 seconds after it started (1.9 to 2.1 / 1.1 to 1.2).
- Devices that were already syncing received the new document after a median of 0.06 to 0.07 seconds (0.07 / 0.05) and at most 0.1 to 0.4 seconds (0.5 / 0.1 to 0.4). The devices that started later received it 0.3 to 0.6 seconds after they started (0.5 to 2.0 / 0.4 to 1.2).
- The hub used about 0.85 cores (1.0 / 1.2), less than half of what it used with a simultaneous start (about 2 cores). Because the staggered start took 2.5 times as long, the hub's total CPU time was about the same (about 8.5 core-seconds, against about 7.6 for the simultaneous start): staggering spreads the hub's work over time rather than reducing it.

**Narrower subscriptions on the devices** (20 × 1,000; the hub subscribed to everything):

| The devices subscribed to | COUNTER complete on all devices | The new document reached the devices | Hub CPU |
|---|---|---|---|
| All orders | 11.3 to 18.0 s (10.5 to 17.2 / 10.4 to 17.5) | 10.4 to 17.1 s | About 1.9 cores (2.1 / 2.9 to 3.2) |
| Their own orders only | 5.4 to 7.6 s (5.4 to 7.5 / 7.3 to 9.9) | 4.4 to 6.6 s (same / 6.3 to 8.9) | About 4.6 cores (4.5 to 4.7 / 5.5) |
| No orders | 5.3 to 7.3 s (5.2 to 7.1 / 7.2 to 9.4) | 4.3 to 6.3 s (4.2 to 6.2 / 6.2 to 8.4) | About 4.6 cores (4.5 to 4.7 / 5.5 to 5.7) |

- The hub's CPU was lower when the devices subscribed to all orders (about 1.9 cores) than with narrower subscriptions (about 4.6 cores). With all orders, the 20 devices used 9 to 10 cores in total (about 5.6 with narrower subscriptions), and we think the hub could not get more CPU. The times in that case (16.8 to 18.0 seconds, and also the about 4 seconds of 20 × 200) may have been set by 20 devices receiving on one Mac rather than by the hub.
- With narrower subscriptions, the devices were complete sooner, by the time they no longer spent receiving the other devices' orders. Subscribing to their own orders only and to no orders at all gave the same times: subscribing to its own orders costs a device almost nothing.
- Still, after the hub had received everything (after 1.6 to 1.8 seconds), the COUNTER document, a single document, took another 3.6 to 5.9 seconds to reach the devices, while the hub used about 4.6 cores.

**The same 20,000 orders from fewer devices** (the devices did not subscribe to orders): from the moment the hub had all orders until every device had the complete COUNTER took 1.1 to 1.6 seconds with 5 devices × 4,000 orders (same / 1.7 to 2.5), 1.7 to 2.8 seconds with 10 × 2,000 (1.7 to 2.7 / 2.5 to 3.8), and 3.6 to 5.7 seconds with 20 × 1,000 (3.6 to 5.5 / 5.2 to 7.7). That is about 10 µs (8.5 to 16 µs) per received order and per device, growing in proportion to the number of devices. In this test, every connected device also sent orders, so the number of connected devices and the number of devices that sent cannot be told apart; [Hub CPU per change grows with the number of connected devices](performance-measurements.md#hub-cpu-per-change-grows-with-the-number-of-connected-devices) shows that a device that is only connected also raises the hub's CPU per change. The hub's `INSERT` meanwhile took 0.19 to 0.23 seconds with 5 devices, 0.36 to 0.39 seconds with 10, and 0.61 to 0.64 seconds with 20.

- The hub's memory (RSS at the end) grew with the number of devices for the same 20,000 orders: 230 to 233 MiB with 5 devices, 292 to 311 MiB with 10, and 452 to 502 MiB with 20 (5.0.3: 157, 228 to 248, and 333 to 468 MiB). Each device used 110 to 235 MiB (the most in the cases where it received every order).
- Once all devices were complete, the CPU of the hub and of the devices fell below 10 percent within 2 to 4 seconds. No long-running work followed.
- On 5.0.3, the hub's CPU includes about 0.5 cores for the test's own query (a `COUNT(*)` of 20,000 documents every 100 ms): 48 to 51 percent while nothing synced, against 1 to 2 percent on 5.1 and later. The 5.0.3 devices that received every order ran the same query.
- An earlier form of this test ran the cases one after another in the same processes. There, the cases after 20 × 1,000 were slower (7 to 17 seconds until the COUNTER was complete), and on 5.0.3, in all three runs, the documents of a new collection created afterwards did not reach the devices within 30 seconds, although all devices were connected. We did not look into the cause, and those results are not used above.

**Used in:** [Scope subscriptions to what the device needs](../best-practices/sync-and-subscriptions.md#scope-subscriptions-to-what-the-device-needs), [Starting and Stopping Sync](../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync).

## Stopping Sync and Closing Ditto

### Starting and stopping sync behaved as documented

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the same results on both releases |
| Setup | Two connected devices. One of them called `sync.start()` while sync was running, then `sync.stop()`; both wrote while sync was stopped, the device registered a subscription, and then started sync again. A separate device called `sync.start()` without an offline license token |

- A second `start()` while sync was running did nothing.
- Right after `stop()`, `isActive` was `false`, and the device disappeared from the other device's presence graph within 22 to 23 ms.
- The subscriptions stayed registered, and the documents that both sides wrote while sync was stopped were exchanged after `start()`. A subscription registered while sync was stopped took effect after `start()`.
- `start()` without an offline license token threw an error whose message begins with `Sync could not be started because Ditto has not yet been activated. This can be achieved with a successful call to setOfflineOnlyLicenseToken`.

**Used in:** [Starting and Stopping Sync](../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Sync stop, close, and inspection](../best-practices/sync-and-subscriptions.md#sync-stop-close-and-inspection).

### A write made right before close or stop may not leave the device

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs of three trials each (nine trials per case and release); the same pattern in every run |
| Setup | A hub and a device, each in its own process. The device subscribed only to its own documents, connected to the hub, and 0.5 seconds later wrote one document with random content (so that the compression of sync traffic does not shrink it): 100 bytes, 1 MB, or 300 KB through a TCP relay limited to 100 KB per second (see [How We Tested](how-we-tested.md#test-environment)). It then ended in one of the ways in the table. We checked whether the hub received the document within 3 seconds (10 seconds over the slow link). If it did not, the device opened the same directory again, connected directly to the hub (also in the trials over the slow link), and we measured the time until the document arrived |

"Right after the `await`" was, in our test, about 1 ms after the write completed: the test sent its reply and ended on the next timer. An app that runs `await execute(); await ditto.close();` leaves less time than that, so the counts below are upper bounds. Where the count was 0 (1 MB, the slow link, and 100 bytes on 5.0.3), a shorter gap does not change it.

Trials (of 9) in which the hub received the document:

| How the device ended | 100 B, 5.0.3 | 100 B, 5.1.0 | 100 B, 5.2.0 | 1 MB | 300 KB over the slow link |
|---|---|---|---|---|---|
| Stayed open | 9 | 9 | 9 | 9 | 9 (after about 3.0 seconds) |
| `close()` after waiting for the confirmation | 9 | 9 | 9 | 9 | 9 |
| `close()` right after the `await` | 0 | 8 | 8 | 0 | 0 |
| `close()` without awaiting the write | 0 | 0 | 0 | 0 | not tested |
| `sync.stop()` right after the `await` | 0 | 9 | 8 | 0 | 0 |
| Process exit without `close()`, right after the `await` | 0 | 7 | 8 | 0 | not tested |
| SIGKILL right after the `await` (a crash, or the operating system ending the app) | 0 | 9 | 8 | 0 | not tested |
| SIGKILL 20 ms or 200 ms later (over the slow link: 1 second later) | 9 | 9 | 9 | 9 | 0 (1 second later) |

- The hub received the document 7 to 34 ms after the write started for 100 bytes, 21 to 24 ms for 1 MB (5.0.3: 25 to 63 ms), and 2.97 to 3.06 seconds for 300 KB over the slow link. When the write's `await` completed (on 5.2.0, after 2 to 6 ms for 100 bytes and 11 to 14 ms for 1 MB; on 5.0.3 and 5.1.0, after at most 17 to 38 ms), the document had not been sent yet.
- `synced_up_to_local_commit_id` reached the write's `commitID` at about the same moment as the hub received the document (we checked both every 5 ms; the difference was −9 to +17 ms). Closing after waiting for it delivered every write, at every size and over the slow link (81 of 81). `close()` and `sync.stop()` do not wait for changes that are being sent.
- When `close()` was called without awaiting the write, the JavaScript `close()` waited for the write to complete (see [In JavaScript, close() completes pending writes](transaction-behavior.md#in-javascript-close-completes-pending-writes)), but the write was not sent (0 of 54).
- A write that did not arrive was still in the device's store in every case. After the device opened the same directory again, the write reached the hub in 114 to 176 ms (over the direct connection; over the slow link it would take about 3 seconds again). If the device never syncs again, because it broke or its directory was deleted (see [Deleting the directory while Ditto is open loses later writes](persistence-directory.md#deleting-the-directory-while-ditto-is-open-loses-later-writes)), the change never reaches other devices.
- On 5.0.3, even 100 bytes did not arrive when the device ended right away. On 5.1 and later, 100 bytes arrived in most trials, but not reliably (8 of 9 with `close()`, for example), and in an app possibly in fewer, as described above.

**Not tested:** logging out. The `cleanup` callback of `logout()` runs after sync has stopped (see [Authentication](../best-practices/setup-and-lifecycle.md#authentication)), so for the same reason it could remove changes that have not been sent yet. `logout()` cannot be used in our small-peers-only setup, so we could not check this.

**Used in:** [Resource Cleanup and Shutdown](../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Monitoring Sync Status](../best-practices/sync-and-subscriptions.md#monitoring-sync-status).

### A change written right after another device stops sync can still reach it

| | |
|---|---|
| Observed on | SDK 5.1.0, one run; we did not try to reproduce it. The variant with a 1-second wait: six runs |
| Setup | A device X called `sync.stop()`. As soon as `presence.graph.remotePeers` on X was empty, a writer on another device set a flag in a document. In the variant, the writer waited 1 second after the presence graph showed the disconnection before writing |

- The flag reached X, although X had stopped sync and its presence graph listed no peers.
- When the writer waited 1 second, the flag did not reach X in any of the six runs.
- An empty `remotePeers` right after `sync.stop()` therefore did not yet mean that no more changes would arrive.

**Used in:** none yet.

## Inspecting Subscriptions

### In JavaScript, queryArguments of a subscription without arguments is empty

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each, and 5.0.3, one run |
| Setup | One device without sync. Two subscriptions, `SELECT * FROM orders` without arguments and `SELECT * FROM orders WHERE status = :status` with `{status: 'open'}`; then `queryString` and `queryArguments` of each element of `ditto.sync.subscriptions` |

- On every release, the subscription without arguments had no `queryArguments` (`null` or `undefined`), and reading it did not end the process. The other subscription returned `{status: 'open'}`.
- The order of `ditto.sync.subscriptions` differed between releases, the same in every run: on 5.0.3 and 5.1.0, the subscription registered second came first, and on 5.2.0, the one registered first. The order is not documented.

**Not tested:** `queryArgumentsJsonString`; the Flutter SDK, for which [Sync stop, close, and inspection](../best-practices/sync-and-subscriptions.md#sync-stop-close-and-inspection) describes a crash on 5.1.0.

**Used in:** [Sync stop, close, and inspection](../best-practices/sync-and-subscriptions.md#sync-stop-close-and-inspection).

## How Quickly Sync Status Changes

### The sync session status lags about 73 seconds behind a disconnection

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0: the session status, three runs each; the confirmation of empty commits, seven runs each; the idle observer, three runs each |
| Setup | (1) One of two connected devices called `sync.stop()`, and we measured how long the other device's `system:data_sync_info` row for it kept `sync_session_status` at `Connected`. (2) A device ran a statement that changed nothing and a statement that changed a document, and we measured how long each `commitID` took to be reflected in `synced_up_to_local_commit_id` of its `system:data_sync_info` row for the other device. (3) A device observed `system:data_sync_info` for 40 seconds while its one peer was idle |

**Session status.** `sync_session_status` stopped being `Connected` 73.1 to 73.2 seconds after the other device's `sync.stop()`, on 5.1.0 and on 5.2.0 (all three runs). The presence graph dropped the device after about 0.1 seconds. The constant value looks like a fixed timeout.

**Empty commits.** Time until the `commitID` appeared in `synced_up_to_local_commit_id`:

| Release | A statement that changed nothing | A statement that changed a document |
|---|---|---|
| 5.1.0 | 27.2 to 27.4 seconds in 5 runs, 2.8 seconds once, and 0.77 seconds once (in a full run of all checks) | 0.25 to 0.27 seconds in every run |
| 5.2.0 | 27.2 seconds in 2 runs, 2.5 to 4.8 seconds in 5 runs | 0.25 to 0.27 seconds in every run |

On both releases, an empty commit is not confirmed on its own but with the next sync exchange, at most about 27 seconds later. The time until confirmation therefore varies between about 0.8 and 27 seconds, depending on when that exchange happens; it can also be under 1 second. On 5.2.0, the confirmation often came sooner.

**An idle observer on `system:data_sync_info`.** With one idle peer, the observer was called 3 times in 40 seconds on 5.1.0 (at 0 seconds, at 2 to 5 seconds, and at 27.6 seconds), and 3 or 4 times on 5.2.0 (at 0 seconds, in some runs at 0.8 to 2.8 seconds, and at 27.3 seconds and again 33 ms later). We think there is a periodic update about every 27 seconds and that empty commits are confirmed with it.

**Used in:** [Monitoring Sync Status](../best-practices/sync-and-subscriptions.md#monitoring-sync-status).
