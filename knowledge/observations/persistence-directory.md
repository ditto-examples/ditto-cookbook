# The Persistence Directory

What the persistence directory holds, and what happens when it is copied, restored from an older copy, opened with another Database ID, deleted in part or while Ditto is open, or opened by a second instance. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory) and [DittoConfig](../../best-practices/setup-and-lifecycle.md#dittoconfig).

**In brief**

- A copy of a directory that runs at the same time as its original has the same peer key, and updates from one of them stop reaching the other devices, without an error, so the two never converge ([Updates from a copied directory and its original never converge](#updates-from-a-copied-directory-and-its-original-never-converge)).
- A copy that replaces the original, and a device that goes back to an older copy of its own directory, sync normally ([A copy that replaces the original syncs normally](#a-copy-that-replaces-the-original-syncs-normally), [Restoring an older copy of a directory loses nothing that had synced](#restoring-an-older-copy-of-a-directory-loses-nothing-that-had-synced)).
- Peers with different Database IDs never see each other, but a directory written with one Database ID opens with another, and its documents sync into the new database ([Devices with different Database IDs do not sync](#devices-with-different-database-ids-do-not-sync), [A directory written with another Database ID opens and syncs its documents](#a-directory-written-with-another-database-id-opens-and-syncs-its-documents)).
- A device whose `ditto_store` subdirectory alone was deleted keeps its peer key, and on SDK 5.1.0 and 5.2.0 some documents that it creates before sync starts do not reach other devices, without an error; a device whose whole directory was deleted comes back with a new peer key and syncs everything ([Deleting only ditto_store keeps the peer key, and on SDK 5.1.0 and 5.2.0 leaves some writes unsynced](#deleting-only-ditto_store-keeps-the-peer-key-and-on-sdk-510-and-520-leaves-some-writes-unsynced)).
- A directory deleted after `close()` opens as an empty store with a new peer key, and no earlier value remains in any file; in a small store, the values stay in the write-ahead log file after `close()` ([Deleting the directory after close() leaves no data behind](#deleting-the-directory-after-close-leaves-no-data-behind), [After close(), a small store keeps its values in the write-ahead log](#after-close-a-small-store-keeps-its-values-in-the-write-ahead-log)).
- On macOS, deleting the directory while Ditto is open raises no error, but the writes made afterwards are lost when Ditto closes ([On macOS, deleting the directory while Ditto is open loses later writes](#on-macos-deleting-the-directory-while-ditto-is-open-loses-later-writes)).
- A directory that another process holds, even a suspended one, fails to open after about 1 second; the lock of a process that crashed does not remain ([A directory locked by another process fails to open after about 1 second](#a-directory-locked-by-another-process-fails-to-open-after-about-1-second), [In JavaScript, opening an open directory again fails](#in-javascript-opening-an-open-directory-again-fails), [The lock file keeps a process ID after the process is killed](#the-lock-file-keeps-a-process-id-after-the-process-is-killed)).

## Copies of a Directory

### Updates from a copied directory and its original never converge

| | |
|---|---|
| Observed on | SDK 5.1.0 (five runs) and 5.2.0 (four runs); the devices diverged in all nine runs, and the final values differed from run to run |
| Setup | We closed a device X, copied its persistence directory, and connected X (the original) and Y (the copy) to the same hub. X and Y wrote different fields of the same document, and each inserted one new document. After 10 seconds, after 30 seconds, and 10 seconds after X and Y had each written once more, we compared the contents of the three devices and of a fourth device that joined later |
| Documentation | We found no description of this case in Ditto's documentation (searched on 2026-10-31) |

The tendency was the same on both releases:

- X and Y have the same peer key. The hub's `remotePeers` listed one peer, and only one of X and Y was connected at a time; in some runs, which one changed during the run.
- The new documents (`byOriginal` and `byClone`) reached every device.
- The updates of fields of the same document never converged on all devices, in all nine runs. For example, on 5.1.0, X had `fromOriginal: 2`, while the hub, Y, and the device that joined later still had `fromOriginal: 0`. On 5.2.0 as well, Y never received an update from X, and in some runs X's second update did not reach the hub.
- X holds its own updates, so looking at X alone, nobody can notice that its updates did not reach the other devices.
- We think Ditto tracks which updates each peer already has by the peer's identity. With two peers of the same identity, the hub then assumes that one of them already has the other's updates. We have not confirmed this.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory).

### A copy that replaces the original syncs normally

| | |
|---|---|
| Observed on | SDK 5.1.0 (one run) and 5.2.0 (two runs) |
| Setup | We closed the original device X without opening it again and started to use a copy Y of its directory, as when a device is replaced. Later, we opened X again, and X and Y wrote different fields of the same document. Finally, Y evicted that document, and a device with a new directory joined |

- While X stayed closed, Y received the hub's changes, and Y's changes reached the hub (all three runs, on both releases).
- After X was opened again, Y's write reached every device. X's write reached neither the hub nor Y in two runs (one on 5.1.0, one on 5.2.0); in the other run on 5.2.0, it reached the hub but not Y.
- After Y evicted the document: in the run where the hub had X's value, Y received X's value again. In the runs where the hub did not have it, X's value appeared nowhere, neither after the eviction on Y nor on the device with a new directory. X's write stayed only on X.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory).

### Restoring an older copy of a directory loses nothing that had synced

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | We copied the directory of a device X. X then wrote changes (`v = 2` and a new document), and after the hub had received them, X was put back to the older copy |

- X, reopened on the older copy, received `v = 2` and the new document from the hub again within 6 seconds.
- The changes that it wrote after going back (another field, another document, and a new document) reached the hub and a device that joined later.
- Going back to an older copy of the same device lost nothing; the problem in [Updates from a copied directory and its original never converge](#updates-from-a-copied-directory-and-its-original-never-converge) is that the original keeps running.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory).

## Directories and Database IDs

### Devices with different Database IDs do not sync

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; the results were the same on both releases |
| Setup | Two devices with different Database IDs and the same offline license token, with an explicit TCP connection address configured |

- Both devices opened with the same offline license token. Even with the explicit TCP connection, they did not list each other in presence, and they did not sync within 10 seconds.
- This is why devices that run development and production builds with different Database IDs do not sync with each other.

**Used in:** [DittoConfig](../../best-practices/setup-and-lifecycle.md#dittoconfig), [Several peers in one test process](../../best-practices/testing.md#several-peers-in-one-test-process).

### A directory written with another Database ID opens and syncs its documents

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | We opened a directory with Database ID A, wrote one document, and closed it. Then we opened the same directory with Database ID B, the ID that our other tests use, and connected it to a hub with Database ID B |
| Documentation | Ditto's documentation on [testing](https://docs.ditto.live/sdk/latest/deployment/testing) states that after the Database ID is changed, the data already in the app keeps syncing, as new data. We saw the same |

- The directory opened with Database ID B without an error, and the document written with Database ID A was visible.
- After the device connected to the hub, the document synced to the hub. Ditto opens a directory written with another Database ID as it is and syncs its documents to the devices of the new database, so development data can mix into production, for example.

**Used in:** [DittoConfig](../../best-practices/setup-and-lifecycle.md#dittoconfig).

## Deleting a Directory or Part of It

### Deleting only ditto_store keeps the peer key, and on SDK 5.1.0 and 5.2.0 leaves some writes unsynced

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each |
| Setup | A hub and a device. The device synced the hub's 10 documents and one document of its own, received the hub's deletion of one document, and closed. We then deleted its persistence directory in one of four ways and reopened it at the same path: the whole directory; only `ditto_store`; `ditto_store` and `ditto_replication`; everything except `ditto_auth`. The reopened device wrote either after sync had started or before starting sync: five new documents, an update of a document of the hub, and an `INSERT` of the document that it had written before |

- **The whole directory** (the same on all three releases): the device came back with a new peer key and received the hub's documents again within 0.23 to 0.27 seconds. The document that the hub had deleted did not come back. Writes made after and before sync started reached the hub within 0.1 to 0.2 seconds. The old peer key disappeared from the hub's presence.
- **Only `ditto_store`**: the peer key stayed the same, and changes written after sync had started reached the hub. On 5.1.0 and 5.2.0, however, of the five new documents created before sync started, the first three had not reached the hub after 30 seconds (the same three in all three runs). The device held them, and neither device reported an error. The update of the hub's document and the `INSERT` of the device's earlier document, written at the same time, did reach the hub, probably because the hub held the same documents and the changes merged. On 5.0.3, all five documents arrived. In an informal check on 5.2.0, documents that had not arrived did arrive after they were updated later. With a different number of writes before the deletion, the number of documents that did not arrive was 0 or 2; we found no rule.
- **`ditto_store` and `ditto_replication`**: `ditto_replication` holds the sync state for each peer (it contained two directories named after peer keys). With both deleted, all five documents arrived on 5.1.0 and 5.2.0 as well.
- **Everything except `ditto_auth`**: the peer key stayed the same, and all five documents arrived.
- On all three releases, a device whose `ditto_store` had been deleted logged four lines with the error `NonMonotonicLastDocLinkCommitId` when it reopened; on 5.1 and later, a device that wrote after sync had started also logged one line `Document database and metadata are out of sync`. The same lines appeared on 5.0.3, where every document arrived, and when `ditto_replication` was deleted as well, so these errors do not tell whether documents are being left behind.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory).

### Deleting the directory after close() leaves no data behind

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result on all three releases. macOS only: what happens when files in use are deleted depends on the operating system (Windows, in general, does not allow deleting a file that is open) |
| Setup | After `close()`, we deleted the whole directory and opened the same path again |

- opening the same path gave an empty store with no documents and a new peer key. The earlier values (document values and subscription queries) remained in no file. The logs on disk (`ditto_logs`, which contain subscription arguments; see [Subscription queries and arguments appear in other devices' logs](configuration-and-diagnostics.md#subscription-queries-and-arguments-appear-in-other-devices-logs)) are inside this directory and are deleted with it.

**Not tested:** other operating systems than macOS; whether sync must be stopped before `close()` and the deletion.

**Used in:** [Authentication](../../best-practices/setup-and-lifecycle.md#authentication), [Platform Differences](../platform-differences.md).

### On macOS, deleting the directory while Ditto is open loses later writes

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result on all three releases. macOS only: what happens when files in use are deleted depends on the operating system (Windows, in general, does not allow deleting a file that is open) |
| Setup | While Ditto was open, we deleted the directory, wrote and read, opened a second instance at the same path, then closed both and opened the path again |

- `INSERT` and reads after the deletion raised no error, and the documents written before it could still be read, probably because the operating system keeps deleted files for a process that has them open. After 1 second, the files had still not been created again. A second instance at the same path meanwhile opened, because the lock file was gone too (no error as in [In JavaScript, opening an open directory again fails](#in-javascript-opening-an-open-directory-again-fails)), and the two instances held different contents (the first 4 documents, the second 1). After both were closed and the path was opened again, only the 1 document written by the second instance remained. Everything else was gone, including the documents that the first instance wrote after the deletion.

**Not tested:** other operating systems than macOS.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory).

### After close(), a small store keeps its values in the write-ahead log

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result on all three releases |
| Setup | We wrote a few dozen documents and a subscription, closed Ditto, and read the files of the directory |

- in a small store of a few dozen documents, the document values were only in `ditto_store/db.sql-wal` after `close()`, and `db.sql` stayed at 4 KB: closing did not write the write-ahead log back into the main file. (With 220 documents, in [Most deleted and evicted values remain in the database files](storage-and-deletion.md#most-deleted-and-evicted-values-remain-in-the-database-files), they were in `db.sql`.) The subscription query strings were in `ditto_system_info/db.sql`; the subscriptions themselves do not come back when the directory is reopened (see [Subscriptions are not stored in the persistence directory](subscriptions-and-replication.md#subscriptions-are-not-stored-in-the-persistence-directory)). On 5.0.3, a file that we read right after `close()` had completed (`ditto_system_info/db.sql-shm`) disappeared before the read finished, in 1 of 3 runs and once in a trial run: cleanup continues for a moment after `close()`.
- On 5.2.0, `ditto_store`, `ditto_attachments`, and `ditto_system_info` each contain a 6-byte file `__ditto_encryption` (`0100be23c258` in all three). 5.1.0 and 5.0.3 have no such file. We did not check what it means.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory).

### The lock file keeps a process ID after the process is killed

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result on all three releases |
| Setup | In a second process, we read the lock file while the directory was open, after `close()`, while the process was stopped with `SIGSTOP`, and after it was killed with `SIGKILL` |

- The lock file (`__ditto_lock_file`) holds the process ID of the process while the directory is open, and is empty after `close()`. While the process was stopped with `SIGSTOP`, the file still held the process ID, and other processes could not open the directory (see [A directory locked by another process fails to open after about 1 second](#a-directory-locked-by-another-process-fails-to-open-after-about-1-second)). After `SIGKILL`, the process ID remained, but another process could open the directory at once. The contents of the file therefore do not tell whether the directory is in use. We think the lock is an operating-system file lock that the process holds and that is released when the process ends.

**Used in:** none yet.

## Locks on the Directory

### A directory locked by another process fails to open after about 1 second

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result on all three releases |
| Setup | A first process opened a directory and wrote `v = 2`. A second process called `Ditto.open()` on the same directory while the first process had it open, while the first process was stopped with `SIGSTOP` (as when an app is suspended), after the first process had called `close()`, and after it had been killed with `SIGKILL` |

| The first process | `Ditto.open()` in the second process |
|---|---|
| Has the directory open | Failed after about 1.1 s with a `DittoError` with the code `store/persistence-directory-locked` (`File already locked ... retried 5 times. Multiple Ditto instances cannot run at the same time within the same working directory`) |
| Is stopped with `SIGSTOP` | Failed in the same way |
| Has called `close()` | Opened in about 0.3 s and read the value that the first process wrote (`v = 2`) |
| Was killed with `SIGKILL` | Opened in about 0.3 s and read `v = 2` |

- The 1.1 seconds match the values of `filelock_retry_maximum` (5) and `filelock_retry_delay` (200 ms) in `SHOW ALL`.
- The lock of a process that crashed does not remain, and its committed writes are not lost.
- Opening the same directory again in the same process also fails in JavaScript (see [In JavaScript, opening an open directory again fails](#in-javascript-opening-an-open-directory-again-fails)).

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory).

### In JavaScript, opening an open directory again fails

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | In one process, we called `Ditto.open()` a second time on a directory that was already open, and again after `close()` of the first instance had completed |

- The second `Ditto.open()` failed within 10 seconds with `File already locked, working dir = ..., retried 5 times. Multiple Ditto instances cannot run at the same time within the same working directory.`
- After `close()` had completed, the directory opened.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory), [Platform Differences](../platform-differences.md).
