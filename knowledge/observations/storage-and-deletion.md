# Storage and Deletion

What happens to data that is removed: how a deletion flag, `DELETE`, and `EVICT` reach other devices, when tombstones are reaped and what a device with an old copy does after that, what removed data costs in queries, documents, and sync traffic, and how much of it stays on disk. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [DELETE and Tombstones](../../best-practices/deletion-and-storage.md#delete-and-tombstones), [Soft Delete](../../best-practices/deletion-and-storage.md#soft-delete), [EVICT](../../best-practices/deletion-and-storage.md#evict), [Choosing DELETE, Soft Delete, or EVICT](../../best-practices/deletion-and-storage.md#choosing-delete-soft-delete-or-evict), [Monitoring Storage](../../best-practices/deletion-and-storage.md#monitoring-storage), and [Data at Rest](../../best-practices/security.md#data-at-rest).

**In brief**

- Husk documents, soft delete with a subscription that excludes flagged documents, eviction, tombstones, and `INITIAL DOCUMENTS` behaved the same on SDK 5.1.0 and 5.2.0 ([Soft delete, husk, eviction, and tombstone behavior held on SDK 5.1.0 and 5.2.0](#soft-delete-husk-eviction-and-tombstone-behavior-held-on-sdk-510-and-520)).
- Once a device has reaped an expired tombstone, a device that missed the deletion brings the old document back to every device, without an error or a warning. The TTL counts from the tombstone's HLC timestamp, so a deleting device whose clock runs ahead delays reaping ([A device with an old copy resurrects a document after its tombstone is reaped](#a-device-with-an-old-copy-resurrects-a-document-after-its-tombstone-is-reaped)).
- On a new store, reaping first runs at a random time within 10 minutes of starting, drawn again at every start, so apps that run for short periods reap rarely. With a preferred hour, a device reaps only if it runs during that hour of its local time ([Reaping at a preferred hour runs at startup or a whole number of hours later, within that hour](#reaping-at-a-preferred-hour-runs-at-startup-or-a-whole-number-of-hours-later-within-that-hour)).
- A deletion flag sends about 28 bytes per document and `DELETE` about 43 bytes. Evicting documents that a subscription still matches downloads all of them again within seconds ([Deletion flags and DELETE transfer little, and eviction under a subscription refetches](#deletion-flags-and-delete-transfer-little-and-eviction-under-a-subscription-refetches)).
- `EVICT` makes a device forget what it knew: a relay that evicts flagged documents receives the old, unflagged versions back from devices that missed the flag, and a document inserted with an evicted ID merges with the old version that other devices hold ([A relay that evicts flagged documents receives old versions back from devices that missed the flag](#a-relay-that-evicts-flagged-documents-receives-old-versions-back-from-devices-that-missed-the-flag), [Inserting with an evicted document's ID merges with the old version](#inserting-with-an-evicted-documents-id-merges-with-the-old-version)).
- Tombstones and evicted documents do not slow queries; flagged documents made `COUNT(*)` and filters 15 to 20 times slower unless every document had the flag, it was indexed, and the query used `isDeleted = false`; reads by ID were not affected ([Tombstones and evicted documents do not slow queries, but flagged documents do](#tombstones-and-evicted-documents-do-not-slow-queries-but-flagged-documents-do)).
- Every different map key removed with `UNSET` adds about 54 bytes to a new device's first sync, and reaping does not remove these records; adding and removing the same key again and again adds almost nothing ([Removed map keys keep adding to a new device's first sync](#removed-map-keys-keep-adding-to-a-new-devices-first-sync)).
- Since 5.1, 10,000 writes grew the write-ahead logs of the document store and of the attachment store to about 20 MB each, and on 5.2.0, the on-disk logs kept the lines of about 200,000 writes. On 5.2.0, `system:system_info` keeps old rows of each storage value, so read the newest row by `timestamp` ([Since SDK 5.1, the write-ahead log grows to about 20 MB](#since-sdk-51-the-write-ahead-log-grows-to-about-20-mb), [On SDK 5.2.0, the on-disk logs kept about 200,000 writes](#on-sdk-520-the-on-disk-logs-kept-about-200000-writes), [On SDK 5.2.0, system:system_info keeps old rows of each storage value](#on-sdk-520-systemsystem_info-keeps-old-rows-of-each-storage-value)).
- Removing data does not shrink the files at once, and most removed values can still be read from them after Ditto closes. By default, SDK 5.2.0 reclaims free space only above 100 MB ([Evicting data does not free disk space at once](#evicting-data-does-not-free-disk-space-at-once), [Most deleted and evicted values remain in the database files](#most-deleted-and-evicted-values-remain-in-the-database-files)).

## Deletion across Devices

### Soft delete, husk, eviction, and tombstone behavior held on SDK 5.1.0 and 5.2.0

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; both releases gave the same results |
| Setup | Five checks: a husk document and its cleanup; a device whose subscription excludes soft-deleted documents; eviction with and without a matching subscription, followed by an insert with the evicted ID; a deletion and a device that never had the document; `INITIAL DOCUMENTS` seeds for an ID that another device deleted |

| What we checked | Result on 5.1.0 and 5.2.0 | Described in |
|---|---|---|
| Husk documents | `COUNT(*)` counted the husks (2). `WHERE year >= 2000` and `WHERE make IS NOT MISSING AND make IS NOT NULL` excluded them; `make IS NOT NULL` alone kept them. Running the `DELETE` again removed the husk from the other device within 0.25 seconds. The shape of the husk was the same on both releases | [Husk documents](../../best-practices/deletion-and-storage.md#husk-documents) |
| A subscription that excludes soft-deleted documents, on a device that already held the document | All five cases behaved as described: the flag arrived; edits made while the document was flagged did not arrive; a restore arrived together with those edits; the cleanup `DELETE` did not arrive; a flag set while the device was offline also arrived | [Soft delete, subscriptions, and cleanup](../../best-practices/deletion-and-storage.md#soft-delete-subscriptions-and-cleanup) |
| `EVICT` | A document evicted while a subscription still matched it came back in about 0.26 seconds. A document evicted after the subscription was cancelled had not come back after 10 seconds. Inserting `{c: 1}` with the evicted `_id` merged on the other device into `{a: 1, b: 1, c: 1}`. The inserting device held only its own `{c: 1}` while it did not subscribe, and received the merged document when it subscribed | [EVICT](../../best-practices/deletion-and-storage.md#evict) |
| Tombstones and a device that never had the document | A device B that was offline during the deletion connected with a device N that had never seen the document: N received the old version. When N then connected with device A, which had deleted it, the document disappeared from N and B | [DELETE and Tombstones](../../best-practices/deletion-and-storage.md#delete-and-tombstones) |
| `INITIAL DOCUMENTS` | A seed that another device had deleted stayed deleted when it was seeded again with the same content. With different content, it became `{"theme": null}` on every device. A new device that seeded different content before its first connection also turned it into `null` on every device | [Default Data with INITIAL Documents](../../best-practices/data-modeling.md#default-data-with-initial-documents) |

**Used in:** [Husk documents](../../best-practices/deletion-and-storage.md#husk-documents), [Soft delete, subscriptions, and cleanup](../../best-practices/deletion-and-storage.md#soft-delete-subscriptions-and-cleanup), [EVICT](../../best-practices/deletion-and-storage.md#evict), [DELETE and Tombstones](../../best-practices/deletion-and-storage.md#delete-and-tombstones), [Default Data with INITIAL Documents](../../best-practices/data-modeling.md#default-data-with-initial-documents).

## Tombstones and Reaping

### A device with an old copy resurrects a document after its tombstone is reaped

| | |
|---|---|
| Observed on | SDK 5.2.0 (six runs) and 5.1.0 (seven runs). Three earlier runs on 5.1.0 are not counted: 5.1.0 does not read `DittoConfig.systemParameters`, so the parameters had not taken effect; the later runs passed them as environment variables (see [DITTO_ environment variables set system parameters at startup](configuration-and-diagnostics.md#ditto_-environment-variables-set-system-parameters-at-startup)). The conclusions rest on the three cases that change only the TTL; the cases with a shifted clock on the deleting device are reported as observed, because they varied on 5.1.0. The time of the reaper's first run was checked by hand in seven runs on 5.2.0 |
| Setup | A hub H, a deleting device D, and an owner C held a document `z`. C closed; D deleted `z`, the deletion reached H, and D closed. H was reopened with its clock 26 hours ahead (see [How We Tested](how-we-tested.md#test-environment)) and `REAPER_TIMING_RANDOM_VARIATION_SECONDS` set to 0, and C was also reopened 26 hours ahead and connected to H. The cases differ in `TOMBSTONE_TTL_HOURS` and in D's clock |

| TTL | D's clock | Tombstone reaped on H | `z` on H after C came back |
|---|---|---|---|
| 168 hours (default) | Correct | No | Stayed deleted (and C's `z` was deleted too) |
| 1 hour | Correct | Yes (5.2.0: 6 of 6 runs; 5.1.0: 7 of 7) | Came back (C's old version) |
| 30 hours | Correct | No | Stayed deleted |
| 30 hours | 10 hours behind; D had created `z` | Yes (5.2.0: 6 of 6 runs; 5.1.0: 3 of 7) | Came back |
| 30 hours | 10 hours behind; D had received `z` from H | No (0 runs on either release) | Stayed deleted |
| 1 hour | 30 hours ahead; D had created `z` | No | Stayed deleted |

- Zombie data occurs. When a device that was offline during the deletion comes back to a device that has reaped the expired tombstone, the deleted document returns to every device in its old version, without an error or a warning. The reaping shows in the log line `Evicted ~1 tombstones from t due to expired TTL` at level INFO (`t` was the collection).
- The TTL counts from Ditto's timestamp on the tombstone (its HLC timestamp). The HLC follows the deleting device's clock, so the TTL is roughly measured from that clock. If the deleting device has received changes first, however, its HLC has already moved forward to their time, and its slow clock no longer matters (see [A device whose clock runs ahead wins concurrent edits made within the clock difference](clocks-and-time.md#a-device-whose-clock-runs-ahead-wins-concurrent-edits-made-within-the-clock-difference)). On 5.1.0, the tombstone was not reaped in 4 of 7 runs even though D had created `z` itself; we think D's HLC had moved forward through the exchange of sync messages.
- A deletion by a device whose clock runs behind expires earlier: with a 30-hour TTL, the tombstone from a device 10 hours behind was reaped after 26 hours. A deletion by a device whose clock runs ahead is reaped later by the size of the offset: with a 1-hour TTL, the tombstone from a device 30 hours ahead was still there after 26 hours.
- **When the reaper runs**: on a new store, the first run happens at a random time within `REAPER_TIMING_RANDOM_VARIATION_SECONDS` (600 by default) after startup: after 59, 89, 253, and 471 seconds, and not within 90 seconds in three more runs (seven runs). With the parameter set to 0, it ran 0.35 seconds after startup. On a reopened store, it runs at startup if `DAYS_BETWEEN_REAPING` (1 day) has passed since the previous run by the device clock, and not otherwise: reopened 2 hours later, it did not run; 26 hours later, it did. The time of the previous run is kept in the store.
- The random delay is drawn again at every start. With the default settings, six starts of 8 seconds each, with the clock moved 11 minutes ahead between them, never reaped. Opening once more with the delay set to 0 then reaped at startup (5.1.0 and 5.2.0, one run each by hand). An app that is used again and again for less than 10 minutes therefore reaps only by chance, at some of its starts.

**Used in:** [Tombstone TTL and reaping](../../best-practices/deletion-and-storage.md#tombstone-ttl-and-reaping), [Choosing DELETE, Soft Delete, or EVICT](../../best-practices/deletion-and-storage.md#choosing-delete-soft-delete-or-evict).

### Reaping at a preferred hour runs at startup or a whole number of hours later, within that hour

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, one run of each procedure below. Altogether, local time was confirmed in three runs, reaping at startup in two, and the hourly check in four. `DittoConfig.systemParameters`: one more run on 5.2.0 |
| Setup | A peer reopened a store on which reaping had already run, with its device clock about 26 hours ahead, so that `DAYS_BETWEEN_REAPING` had passed. `REAPER_TIMING_RANDOM_VARIATION_SECONDS` was 0. `ENABLE_REAPER_PREFERRED_HOUR_SCHEDULING` and `REAPER_PREFERRED_HOUR` (an hour from 0 to 23, 0 by default) were passed as environment variables. The procedures varied the time of reopening, by the device clock in Japan Standard Time (JST, UTC+9), and the preferred hour |

| Procedure | Reopened at (JST) | `REAPER_PREFERRED_HOUR` | Watched for | Runs |
|---|---|---|---|---|
| Local time or UTC | 12:59:40 | 13 (13:00 local time) and 4 (the same hour in UTC) | 62 minutes | 5.2.0, one run |
| Hourly check | 14:30 and 14:10 | 15 and 14 | 62 minutes | 5.2.0, one run |
| At startup | 15:10 | 14, 15, and 16 | 90 seconds | 5.2.0 and 5.1.0, one run each |
| Two hours later | 15:30 (5.2.0) and 17:30 (5.1.0) | 17 (5.2.0) and 19 (5.1.0) | 130 minutes | 5.2.0 and 5.1.0, one run each |

- `REAPER_PREFERRED_HOUR` is an hour of the device's local time, not of UTC. In the first procedure, only 13 reaped; 4 did not reap in 62 minutes. At startup, too, the peer with 15 reaped at 15:10 JST.
- When the local hour at reopening matched the setting, the peer reaped at startup: 14 at 14:10 and 15 at 15:10, 0.3 seconds after opening, on 5.2.0 and 5.1.0 alike. Otherwise it did not reap at startup: 14 and 16 at 15:10 did not reap in 90 seconds.
- A peer that had not reaped at startup reaped exactly a whole number of hours after startup, when the local hour matched. None of them reaped at the start of the hour (13:00, 15:00, 17:00):

  | Reopened at (JST) | Preferred hour | Reaped |
  |---|---|---|
  | 12:59:40 | 13 | At 13:59:40, 3,600 seconds after startup |
  | 14:30 | 15 | At 15:30:00, 3,600 seconds after startup |
  | 15:30 (5.2.0) | 17 | Not at 16:30; at 17:30:00, 7,200 seconds after startup |
  | 17:30 (5.1.0) | 19 | At 19:30:00, 7,200 seconds after startup |

  At an hourly point where the hour does not match, nothing appears in the log. That the device checks every hour is therefore our inference from reaping at exactly +3,600 and +7,200 seconds.
- As a result, a device that runs through the whole preferred hour reaps at some point within it. A device that does not run during that hour, or that closes within the hour before its check comes, does not reap. A point-of-sale app that is closed at night and keeps the default hour 0, for example, would never remove its tombstones.
- Values passed as environment variables (`DITTO_ENABLE_REAPER_PREFERRED_HOUR_SCHEDULING`, `DITTO_REAPER_PREFERRED_HOUR`) appear in the INFO log at startup as `system parameter default overridden` (see [DITTO_ environment variables set system parameters at startup](configuration-and-diagnostics.md#ditto_-environment-variables-set-system-parameters-at-startup)). They took effect on 5.1.0 as well.
- On 5.2.0, passing the parameters in `DittoConfig.systemParameters` gave the same result (one run): reopened at 19:10 by the device clock, the peer with 19 reaped after 0.29 seconds, and those with 18 and 20 did not reap in 90 seconds.

**Used in:** [Tombstone TTL and reaping](../../best-practices/deletion-and-storage.md#tombstone-ttl-and-reaping).

## Deletion Traffic and Eviction

### Deletion flags and DELETE transfer little, and eviction under a subscription refetches

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each; the results were nearly the same on both releases. The eviction warning: one run on 5.2.0 |
| Setup | Two devices held 5,000 documents with 500 bytes of random content each, and the relay between them counted the bytes (see [How We Tested](how-we-tested.md#test-environment)). The writing device removed documents in three ways. We measured the time until the other device reflected each change, and the bytes that flowed |

| Removal on the writing device | Until the other device reflected it | Bytes sent | Per document |
|---|---|---|---|
| `UPDATE ... SET isDeleted = true` on 2,500 documents | About 240 ms | About 70 KiB | About 28 bytes |
| `DELETE` of 2,500 documents | About 250 to 315 ms | About 106 KiB | About 43 bytes |
| `EVICT` of the remaining 2,500 documents, with the subscription to the whole collection kept | The local documents were gone in 19 to 27 ms, and all 2,500 were received again within 3 seconds | About 1.35 MiB | — |

- `DELETE` does not send the content (about 1.2 MiB). A deletion flag and `DELETE` both send little; `DELETE` sends about 1.5 times as much.
- The eviction did not change the other device's documents; the evicting device simply downloaded everything it had evicted again.
- **Eviction warning** (one run on 5.2.0): since SDK 5.1, Ditto writes a warning when post-eviction session cleanup runs too frequently (see [Eviction frequency](../../best-practices/deletion-and-storage.md#eviction-frequency)). It did not appear in this pattern: on two connected devices, 40 evictions of one document each, 0.5 seconds apart, produced no WARN line about eviction, cleanup, or sessions in the log at level Info.

**Not tested:** the frequency and the time window that trigger the eviction warning.

**Used in:** [EVICT](../../best-practices/deletion-and-storage.md#evict), [Choosing DELETE, Soft Delete, or EVICT](../../best-practices/deletion-and-storage.md#choosing-delete-soft-delete-or-evict), [Cancelling subscriptions and local data](../../best-practices/sync-and-subscriptions.md#cancelling-subscriptions-and-local-data).

### A relay that evicts flagged documents receives old versions back from devices that missed the flag

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, four runs each, with the same result on both releases. One earlier run on 5.1.0, before we added more observation points, found the flag on X; it could not tell when the flag arrived, and no later run showed it again (see [A change written right after another device stops sync did not reach it](subscriptions-and-replication.md#a-change-written-right-after-another-device-stops-sync-did-not-reach-it)) |
| Setup | A writer W and a device X connected through a relay R that subscribed to active documents only. While X was disconnected, W set the deletion flag on a document; R received the flag and then evicted the flagged document with `EVICT FROM orders WHERE isDeleted = true`. Then W disconnected and X connected |

On both releases:

- X did not receive the flag and kept the document as `isDeleted: false`.
- **R received the old, active version (`isDeleted: false`) back from X within 1 second.** R had seen the flagged version, but forgot it by evicting it, and from then on held the old version as an active document, which it can show as active and pass on to other devices.
- When R widened its subscription to the whole collection and W connected, the flag reached X within 3 ms.

**Used in:** [Soft delete, subscriptions, and cleanup](../../best-practices/deletion-and-storage.md#soft-delete-subscriptions-and-cleanup), [Flag-based eviction](../../best-practices/deletion-and-storage.md#flag-based-eviction).

### Inserting with an evicted document's ID merges with the old version

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; all nine runs gave the same result |
| Setup | A hub and a device held `{a: 1, b: 1, items: {k1: 1}}`. The device cancelled its subscription (otherwise it receives the document again at once; see [Deletion flags and DELETE transfer little, and eviction under a subscription refetches](#deletion-flags-and-delete-transfer-little-and-eviction-under-a-subscription-refetches)), evicted the document, and inserted `{a: 2, items: {k2: 2}}` with the same ID. Then it subscribed again, and we waited until both devices held the same document |

- The `INSERT` after `EVICT` succeeded without an ID conflict, and the device showed only the new version, `{a: 2, items: {k2: 2}}`.
- After the device subscribed again, both devices held `{a: 2, b: 1, items: {k1: 1, k2: 2}}`. `a`, which the new version wrote, took the new value; `b` and `items.k1`, which the new version did not have, came back from the old version. `EVICT` is not a deletion, so an insert with the same ID merges with the version that other devices still hold.

**Not tested:** a `DELETE` before inserting again. How a deletion merges with a later insert of the same ID is a row of the table in [The merge table held on SDK 5.1.0 and 5.2.0](merge-behavior.md#the-merge-table-held-on-sdk-510-and-520).

**Used in:** [EVICT](../../best-practices/deletion-and-storage.md#evict).

## Removed Data in Queries and Documents

### Tombstones and evicted documents do not slow queries, but flagged documents do

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run on both releases showed the same tendency |
| Setup | Five collections, each with 1,000 live documents: one that only ever held those 1,000; one of 50,000 documents of which 49,000 were deleted with `DELETE`; one of 50,000 of which 49,000 were evicted with `EVICT`; one of 50,000 of which 49,000 were flagged with `isDeleted = true` and excluded with `coalesce(isDeleted, false) = false`; and one in which every document had `isDeleted`, with an index on `isDeleted`, and the 49,000 flagged ones were excluded with `isDeleted = false`. On each, we measured the median of seven runs of `COUNT(*)`, of a filter on a field without an index, and of a read by ID |

| Collection (1,000 live documents each) | `COUNT(*)` | Filter on a field without an index | Read by ID |
|---|---|---|---|
| Only 1,000 documents; 49,000 deleted (49,000 tombstones); 49,000 evicted | About 1.4 ms | 2.3 to 3.0 ms | About 1.4 ms |
| 49,000 flagged, excluded with `coalesce(isDeleted, false) = false` | 41 to 61 ms | 41 to 61 ms | About 1.4 ms |
| 49,000 flagged, `isDeleted` on every document and indexed, excluded with `isDeleted = false` | About 2.3 ms | 3.7 to 4.0 ms | About 1.4 ms |

- The collections with 49,000 tombstones and with 49,000 evicted documents were as fast as the one that only ever held 1,000 documents.
- With the flag, `COUNT(*)` and the filter were about 15 to 20 times slower: every query also read the 49,000 flagged documents.
- With `isDeleted` on every document, an index on it, and `isDeleted = false` as the condition, the queries were back near the speed of the 1,000-document collection.
- Reads by ID took about 1.4 ms in every collection.

**Used in:** [Indexing soft-delete filters](../../best-practices/deletion-and-storage.md#indexing-soft-delete-filters), [Choosing DELETE, Soft Delete, or EVICT](../../best-practices/deletion-and-storage.md#choosing-delete-soft-delete-or-evict).

### Removed map keys keep adding to a new device's first sync

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each of both procedures and of the comparison with one document per entry; the results were the same on all three releases |
| Setup | (1) A hub kept a map with 10 entries and repeatedly added a UUID key and removed it with `UNSET`. A new peer subscribed to that document only, through the relay that counts bytes, and we measured what it received in its first sync. (2) On a hub with `TOMBSTONE_TTL_HOURS` set to 1, we added and removed 1,000 keys, deleted another document with `DELETE`, and reopened the hub with its clock 26 hours ahead (see [How We Tested](how-we-tested.md#test-environment)), so that the reaper ran at startup |

What a new peer received in its first sync:

| History of the map (10 entries remain) | First sync | Time to write the history (5.2.0; 5.1.0 / 5.0.3 in parentheses) |
|---|---|---|
| No history | 4.2 to 4.7 KiB | — |
| 100 keys added and removed | 10.8 to 11.5 KiB | 0.32 to 0.33 s (0.32 / 0.38 to 0.66) |
| 1,000 keys added and removed | 59.4 to 60.2 KiB | 3.6 s (3.6 to 3.7 / 5.3 to 5.9) |
| 5,000 keys added and removed | 269.2 to 270.1 KiB | 57 to 62 s (28 / 41) |
| The same key added and removed 1,000 times | 5.3 to 6.1 KiB | 3.1 s (3.1 to 3.2 / 8.5) |
| 1,000 keys, then the whole map assigned again | 60.3 to 60.7 KiB | — |
| 1,000 keys, then the whole map removed with `UNSET` and assigned again | 5.6 to 6.3 KiB | — |

- The first sync grew by about 54 bytes per removed key (a 36-character UUID; bytes counted at the relay, so after compression and including TLS). Adding and removing the same key again and again added almost nothing: the growth follows the number of different keys removed. (Disk usage is in the comparison below.) Extrapolated from the results up to 5,000 keys, 10,000 removed keys would add about 0.5 MB.
- Assigning the whole map again did not reduce it, because assigning an object merges with it. Removing the whole map with `UNSET` and then assigning it brought the first sync almost back to that of a map without history. That removal has a side effect: an entry that an offline device added before the `UNSET` (by timestamp) stays as a key whose value is `null` (see [A key added concurrently survives a later removal as null](merge-behavior.md#a-key-added-concurrently-survives-a-later-removal-as-null)).
- Writes slowed down as removed keys accumulated: on 5.2.0, about 1.8 ms per statement up to 1,000 keys and about 5.9 ms up to 5,000. At 5,000 keys, 5.2.0 was the slowest release, about twice as slow as 5.1.0 (57 to 62 seconds against 28). Reads (`SELECT *`) took 1.3 to 1.8 ms and hardly changed (2.9 ms only on 5.0.3 with 5,000 keys).
- Reaping did not remove the records. After the hub reopened 26 hours ahead, the tombstone of the deleted document was reaped (`Evicted ~1 tombstones from carts due to expired TTL`; on 5.0.3, `Evicting ...`), but the map's first sync went from 58.8 to 59.4 KiB before reopening to 64.2 to 64.8 KiB after it. It did not shrink and grew by the 100 keys added and removed in between (the same in all nine runs). Adding and removing 100 keys took as long before reopening as after it (0.42 to 0.44 seconds on 5.2.0).

**One document per entry** (three runs each on 5.0.3, 5.1.0, and 5.2.0): we kept the same list as one document per entry and compared. With 10 entries kept and 1,000 added and removed, a new peer's first sync was 58.8 to 59.5 KiB with one map (`UNSET`), and 4.6 to 5.3 KiB with one document per entry (`DELETE`).

- A new peer hardly receives anything for the deletion of documents it never held. (We did not measure 10 documents without deletions, but the result is about the same as the map without history, 4.2 to 4.7 KiB.)
- A peer that already held the entries receives every removal in both shapes (`DELETE` costs about 43 bytes per document, from the 2,500 documents and about 106 KiB in [Deletion flags and DELETE transfer little, and eviction under a subscription refetches](#deletion-flags-and-delete-transfer-little-and-eviction-under-a-subscription-refetches)). The shapes differ in a new peer's first sync and in whether reaping removes the records: after the hub reopened 26 hours ahead, the reaper removed the 1,000 documents' tombstones (`Evicted ~1000 tombstones from tickets`), while the map did not change.
- On disk, the writing hub's `ditto_store` was large right after the writes (about 20 MB on 5.1.0 and 5.2.0, and `ditto_attachments`, without any attachment, was also about 20 MB, probably the write-ahead log and similar files; about 4.3 MB on 5.0.3), so the two shapes could not be compared then. After reopening and closing on 5.1.0 and 5.2.0, it was 357 to 425 KiB for the map and 1,071 to 1,103 KiB for the documents per entry; we think this is because freed space is not returned even after reaping (see [Evicting data does not free disk space at once](#evicting-data-does-not-free-disk-space-at-once)). On 5.0.3, it stayed at 4,316 to 4,480 KiB after reopening.

**Not tested:** a collection of 10 documents without deletions, for comparison with the documents per entry.

**Used in:** [Adding, updating, and removing map entries](../../best-practices/data-modeling.md#adding-updating-and-removing-map-entries).

## Disk Space and the Write-Ahead Log

### Evicting data does not free disk space at once

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result. `DELETE` instead of `EVICT`, and an earlier start and shorter interval with the default threshold: one run each on 5.2.0 |
| Setup | We inserted about 60 MB (3,000 documents with random content), evicted all of them, and measured the size of the persistence directory 12 and 42 seconds after `EVICT`, after closing, and 15 seconds after reopening. On 5.2.0, we also measured with the incremental vacuum's start delay set to 0 seconds, its interval to 5 seconds, and its threshold to 1 MB or 30 MB, passed in `DittoConfig.systemParameters` |

- With the default settings, the directory did not shrink on either release up to 42 seconds after `EVICT` (5.2.0: 69 to 71 MB → 71 to 73 MB; 5.1.0: 85 MB → 87 MB). Closing folded the write-ahead log (WAL) into the database file, leaving 63 MB, and after reopening it stayed at 64 to 65 MB. The evicted data remains as free space inside the SQLite files.
- **The 5.2.0 defaults** (from `SHOW ALL`): the automatic reclaim starts 300 seconds plus a random delay of up to 1,200 seconds after startup (5 to 25 minutes), runs every 3,600 seconds, and reclaims only when the free space exceeds `BACKEND_SQLITE3_INCREMENTAL_VACUUM_THRESHOLD_BYTES` (104,857,600, that is, 100 MB). After the `EVICT`, the debug log showed 15,044 free pages (`reclaimable_bytes=61620224`, about 62 MB). With only the start and the interval brought forward and the threshold left at 100 MB, this free space was not reclaimed (one run). SDK 5.1.0 does not reclaim free space automatically.
- With the threshold at 1 MB, the directory shrank to 56 MB 12 seconds after `EVICT`, to 33 MB after 42 seconds, and to 19 MB after reopening. According to the log, each run of the reclaim removed 1,000 pages (about 4 MB, the default of `BACKEND_SQLITE3_INCREMENTAL_VACUUM_BATCH_PAGES`). At the default interval of 3,600 seconds, that would free only about 4 MB an hour, even above the threshold (a calculation; we did not measure it with the default interval).
- With the threshold at 30 MB, the directory shrank as with 1 MB until closing, but stopped at 28 MB after reopening (19 MB with 1 MB).
- With `DELETE` instead of `EVICT`, the directory shrank in the same way (one run; tombstones are small).
- These parameters are read only at startup; on 5.2.0, they took effect when passed in `DittoConfig.systemParameters`.

**Not tested:** the reclaim at the default interval; why the reclaim with a 30 MB threshold stopped at 28 MB.

**Used in:** [Monitoring Storage](../../best-practices/deletion-and-storage.md#monitoring-storage), [Choosing DELETE, Soft Delete, or EVICT](../../best-practices/deletion-and-storage.md#choosing-delete-soft-delete-or-evict).

### Since SDK 5.1, the write-ahead log grows to about 20 MB

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; all nine runs showed the same tendency. The attachment store's write-ahead log after closing: one run each on 5.1.0 and 5.2.0. Five devices: three runs on each release |
| Setup | One device updated a document holding 1 KB of random data 10,000 times with `UPDATE`, awaiting one statement at a time, and incremented a COUNTER 10,000 times, and we measured the size of each file in the persistence directory, right after the writes and after closing. Separately, five devices synced for 10 minutes |

5.1.0 and 5.2.0 gave nearly the same values; values for 5.0.3 are given separately.

- **Write-ahead log**: after the 10,000 writes, the document store's `ditto_store/db.sql-wal` was about 20 MB, and the attachment store's `ditto_attachments/db.sql-wal` was also about 20 MB, although no attachment was used (5.0.3: about 4 MB each). The database file `db.sql` itself was 148 KiB (5.0.3: 52 KiB). In a separate run, 3,000 writes already reached the same 20 MB. Closing folded the document store's WAL into its database file. On 5.1.0 and 5.2.0, however, the attachment store's 20 MB WAL and its `db.sql-shm` remained after closing; on 5.0.3, they were removed. In one run, the WAL was still 20 MB 5 seconds after closing, and after reopening and closing again.
- **The whole directory**: with three documents in the store, about 54 to 57 MB right after the writes and about 31.5 MB after closing (5.0.3: 16 to 24 MB and 14.8 MB). Of the 31.5 MB after closing, 20 MB was the attachment store's WAL and 11 MB the on-disk logs (5.0.3: 14.6 MB of logs).
- With five devices (the setup of [An observer of 200 documents grows memory on every callback](performance-measurements.md#an-observer-of-200-documents-grows-memory-on-every-callback)): five devices synced for 10 minutes, two of them updating about 42 times a second each. On 5.1.0 and 5.2.0, `ditto_system_info`, `ditto_store`, `ditto_replication`, and `ditto_attachments` each reached about 20 MB (no attachment was used), and on the hub, to which four devices were connected, `ditto_replication` was 79.3 MB (the same value in all six runs). With the on-disk logs (7 to 26 MB), the persistence directory of a store with 200 documents moved between 63 and 107 MB on the clients and between 130 and 169 MB on the hub. On 5.0.3, each was about 4 MB (the hub's `ditto_replication` 16.3 MB), and the directory 15 to 57 MB.

**Used in:** [Monitoring Storage](../../best-practices/deletion-and-storage.md#monitoring-storage).

### On SDK 5.2.0, system:system_info keeps old rows of each storage value

| | |
|---|---|
| Observed on | SDK 5.2.0, three runs; reading repeatedly after the writes: one run. SDK 5.1.0 and 5.0.3 have no keys for the write-ahead log |
| Setup | One device updated a document holding 1 KB of random data 10,000 times with `UPDATE`, awaiting one statement at a time, and incremented a COUNTER 10,000 times, and we read the storage keys of `system:system_info` right after the writes and then repeatedly |

- The same key appears in several rows with different `timestamp` values. Read right after the 10,000 writes, `fs_usage_store_db_sql_wal` had 16 to 17 rows: the newest held the actual file size (about 20.7 MB), the oldest the size before the writes (about 342 KB). `wal_current_size_bytes` and `wal_peak_size_bytes` had only one row each, 37,112 from before the writes, in all three runs. Reading repeatedly in one run, a row with 20,925,512 appeared about 60 seconds later, and the old rows remained. The WAL values are recorded about once a minute, and the `fs_usage` values more often. A query that takes one row without ordering by `timestamp` gets an old value, as our first measurement did. 5.1.0 and 5.0.3 have no WAL keys.

**Used in:** [Monitoring Storage](../../best-practices/deletion-and-storage.md#monitoring-storage).

### On SDK 5.2.0, the on-disk logs kept about 200,000 writes

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each. The rotation: one run on 5.2.0 |
| Setup | One device updated a document holding 1 KB of random data 10,000 times with `UPDATE`, awaiting one statement at a time, and incremented a COUNTER 10,000 times, and we read the on-disk logs. For the rotation, one device wrote continuously for 5.5 minutes |

- On 5.1.0 and 5.2.0, each write added four debug lines, three for the transaction and one for the store, without values (see [Subscription queries and arguments appear in other devices' logs](configuration-and-diagnostics.md#subscription-queries-and-arguments-appear-in-other-devices-logs)): about 1.5 KB per write (5.0.3: about 0.75 KB). In one run on 5.2.0, the active log file grew to about 15 to 18 MB before it rotated, and a rotated file was about 0.62 MB with gzip, the log of about 14,000 to 15,000 writes. After 5.5 minutes of continuous writes (about 220,000), the compressed files stopped at 14: 15 files with the active one, about 8.7 MB of compressed files and up to about 18 MB for the active file. The logs therefore keep about 200,000 writes, which is about 5 minutes at 600 writes a second, or about 5 hours at 10 writes a second.
- The rotation size of 1 MB (`ROTATING_LOG_FILE_MAX_SIZE_MB`, 1 by default) probably refers to the compressed file; the active file grows far beyond 1 MB. On 5.0.3, the log was still one file (14.6 MB) after 20,000 writes.

**Used in:** [On-disk logs and exporting them](../../best-practices/logging-and-observability.md#on-disk-logs-and-exporting-them).

## Deleted Data on Disk

### Most deleted and evicted values remain in the database files

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, six runs each (in three of them, the document with the overwritten field was the same size as the others); the same pattern on all three releases. JavaScript SDK on macOS, where Ditto does not encrypt the store (see [Data at Rest](../../best-practices/security.md#data-at-rest)) |
| Setup | 220 documents of about 1.5 KB, each holding a different string (standing in for an email address). We closed Ditto and searched the files in the persistence directory for the bytes of each string. Then we reopened, deleted 100 documents with `DELETE`, evicted 100 with `EVICT`, overwrote a field of one document, closed, and searched again |

- After closing, every value was found in `ditto_store/db.sql`, byte for byte (in a small store of a few dozen documents, in `db.sql-wal`; see [After close(), a small store keeps its values in the write-ahead log](persistence-directory.md#after-close-a-small-store-keeps-its-values-in-the-write-ahead-log)).
- After the removals and closing, most removed values were still in the files:

  | Removed with | Values still in the files after closing |
  |---|---|
  | `DELETE` (100 documents) | 55 to 69 on 5.1.0 and 5.2.0; 89 to 90 on 5.0.3 |
  | `EVICT` (100 documents) | 98 to 100 |

  The removed documents no longer appear in queries, but their values can be read from the files. We think this is because SQLite leaves freed pages as they are (see [Evicting data does not free disk space at once](#evicting-data-does-not-free-disk-space-at-once)). We also think that fewer `DELETE` values remain because writing the tombstones reused some of the freed pages at once; we did not verify this.
- The old value of the overwritten field was not found after closing, also when the document was the same size (1.5 KB) as the others. This was one document only, not enough to say that overwriting a field removes its old value.
- On 5.2.0, with the incremental vacuum's threshold lowered to 64 KB and Ditto open for 25 seconds, the remaining values dropped to 3 to 5 for `DELETE` and 0 to 2 for `EVICT`. With the default threshold (100 MB), free space is not reclaimed until it exceeds the threshold (see [Evicting data does not free disk space at once](#evicting-data-does-not-free-disk-space-at-once)), so we think the values remain until new writes reuse the freed pages or the space is reclaimed. 5.1.0 and 5.0.3 have no automatic reclaim.
- The on-disk logs do not contain document values (see [Subscription queries and arguments appear in other devices' logs](configuration-and-diagnostics.md#subscription-queries-and-arguments-appear-in-other-devices-logs)).

**Not tested:** how long the values remain with the default settings; whether overwriting a field removes its old value in general (one document only).

**Used in:** [Data at Rest](../../best-practices/security.md#data-at-rest), [Authentication](../../best-practices/setup-and-lifecycle.md#authentication), [Platform Differences](../platform-differences.md).
