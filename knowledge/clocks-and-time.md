# Clocks and Time

How device clocks affect Ditto: which concurrent write wins when a clock is wrong, how a wrong clock spreads to other devices through Ditto's Hybrid Logical Clock (HLC), and when `clock()` in a subscription or an observer is evaluated. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Clock drift](../best-practices/data-modeling.md#clock-drift) and [Date and Time](dql-functions.md#date-and-time).

**In brief**

- Ditto's last-writer-wins follows the device clocks: a device whose clock runs N seconds ahead wins against writes made up to N seconds later ([A device whose clock runs ahead wins concurrent edits](#a-device-whose-clock-runs-ahead-wins-concurrent-edits)).
- A clock that runs ahead spreads: every device that syncs with that device, even through a hub, then writes with future timestamps, also for other documents, until the app restarts ([A clock running ahead spreads to devices that sync with it](#a-clock-running-ahead-spreads-to-devices-that-sync-with-it), [Ditto's clock stays ahead until the app restarts](#dittos-clock-stays-ahead-until-the-app-restarts)).
- Stored documents with future timestamps do not move a clock forward ([Receiving future timestamps does not advance Ditto's clock](#receiving-future-timestamps-does-not-advance-dittos-clock)).
- `clock()` in a subscription is evaluated by the sending device with its own clock, only when a document is written or a new subscription arrives ([clock() in a subscription uses the sending device's clock](#clock-in-a-subscription-uses-the-sending-devices-clock)).

## Last-writer-wins and device clocks

### A device whose clock runs ahead wins concurrent edits

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | A hub and two writers, each in its own process, started again for each case. One writer's clock was shifted (see [How We Tested](how-we-tested.md#test-environment)). Both writers disconnected (we waited 1 second after presence showed the disconnection), the first writer wrote `v`, and after a set interval the second writer wrote the same field. Then both reconnected, and we waited until all devices held the same value. We also checked that the first write had not reached the hub before the second write |

| Case | Winner |
|---|---|
| The first writer's clock is 5 s ahead; the second writer writes 2 s later | The first writer: the value written later is lost |
| The first writer's clock is 5 s ahead; the second writer writes 8 s later | The second writer |
| The first writer's clock is 1 hour ahead; the second writer writes 5 s later | The first writer |
| The second writer's clock is 1 hour behind; both are offline and write 2 s apart | The first writer |
| The second writer's clock is 1 hour behind, and before writing it received a change to another document (made 1 s after the first write) | The second writer |
| As above, but the change it received was to another field of the same document | The second writer |

- A write from a device whose clock runs ahead wins against writes to the same field made later than it, as long as they were made within the clock difference. A clock that is a few seconds off, which is common on Android, is enough to reverse the outcome of edits made a few seconds apart.
- A device whose clock runs behind writes with a timestamp after any change it has received, also when that change was to another document. Ditto keeps one HLC per device, not one per document. Such a device therefore loses only against writes that other devices made after the last change it received.

**Used in:** [Clock drift](../best-practices/data-modeling.md#clock-drift).

### A clock running ahead spreads to devices that sync with it

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each with a clock 1 hour ahead and three with a clock 30 days ahead (the 1-hour case three more times); every run gave the same result |
| Setup | A hub, a device F whose clock ran ahead, a receiving device R, and a bystander B, each in its own process; R and B had correct clocks. B disconnected, F wrote `d1.v`, and R received the change and wrote the field again. Then R disconnected and wrote `d1.w` and `d2.w` (`d2` is a document that F never wrote). 2 seconds later, B, which had not seen F's write, wrote the same fields, and both reconnected |

- R could overwrite F's value: a device can always overwrite a change that it has received.
- R's later offline writes won against B's writes made 2 seconds later, for `d1` and for `d2`. A device that has received a timestamp from F writes after that timestamp in every document.
- A timestamp 30 days ahead was accepted and spread in the same way. Nothing rejected or limited it, and no log line at warning level or above mentioned the clock difference (checked by hand once on 5.2.0).
- As a result, while one device's clock runs N ahead, every device that syncs with it, directly or through a hub, writes with future timestamps until real time catches up or until that device's app restarts (see the next section). Concurrent edits by devices that have not synced with them lose meanwhile, and a device that comes back online joins them as soon as it receives a change.
- A deletion written with a future timestamp leaves a tombstone that is reaped correspondingly later (see [Tombstones and reaping](storage-and-deletion.md#a-device-with-an-old-copy-resurrects-a-document-after-its-tombstone-is-reaped)).

**Used in:** [Clock drift](../best-practices/data-modeling.md#clock-drift).

### Ditto's clock stays ahead until the app restarts

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result (three earlier runs each without the bystander gave the same result for overwriting the device's own writes) |
| Setup | A hub, a device F whose clock ran 1 hour ahead, and a bystander B with a correct clock. B disconnected, and F wrote two documents that reached the hub. (1) While F kept running, its clock was set right (DQL `clock()` then showed no difference), and F wrote the first document again; then F disconnected and wrote `d1.w`, and 2 seconds later B wrote the same field. (2) F closed, reopened with the correct clock without starting sync, wrote `d2.w` (a document F had not written with the fast clock), and wrote the second document again. 2 seconds later B wrote `d2.w`, and all devices reconnected |

- F's writes replaced its own earlier writes in both cases and reached the hub within 10 seconds. Values that the hub wrote afterwards also reached F.
- Against B: after the clock was set right while F kept running, F's write won against B's write made 2 seconds later, because F's HLC was still 1 hour ahead. After F reopened, its write lost against B's write made 2 seconds later, because its HLC had returned to the correct device time. The HLC lives only in the running process and is not stored.
- A device's new write replaces its own earlier write with a timestamp 1 hour ahead, either because the device continues its own sequence of writes or because it writes after the timestamp it finds on the document. This test cannot tell which.

**Used in:** [Clock drift](../best-practices/data-modeling.md#clock-drift).

### Receiving future timestamps does not advance Ditto's clock

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result (three earlier runs each, without the final overwrite, gave the same winners) |
| Setup | A device F whose clock ran 1 hour ahead wrote `d1`, which reached the hub, and F closed. The hub was reopened as well, so that no process that had run with the future time remained. A new device N with a correct clock connected and received `d1`, then disconnected and wrote `d2.w`. 2 seconds later, a device B that had been disconnected all along wrote the same field, and both reconnected. Finally, N wrote `d1.v` again |

- B's write, made 2 seconds later, won. N had received a document with timestamps 1 hour ahead, but its HLC did not move forward.
- N could overwrite `d1.v`, which had been written with a timestamp 1 hour ahead, and the change reached the hub: a value that a device has seen can be overwritten, even when its timestamp is later than the device's clock.
- Together with the observations above, this suggests that the HLC moves forward when a running peer sends a change, which carries that peer's current clock, and not from the timestamps of stored documents. The spread of a fast clock therefore stops once every process that ran with the future time has restarted, or once real time catches up. A tombstone whose timestamp moved forward although the deleting device's clock was behind (see [A device with an old copy resurrects a document after its tombstone is reaped](storage-and-deletion.md#a-device-with-an-old-copy-resurrects-a-document-after-its-tombstone-is-reaped)) fits the same explanation.

**Used in:** [Clock drift](../best-practices/data-modeling.md#clock-drift).

## clock() in queries

### clock() in a subscription uses the sending device's clock

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0: three runs each for each of the three procedures below; all nine runs of each procedure gave the same subscription results |
| Setup | A sending and a receiving device, each in its own process with its own clock. The sender held five documents whose `createdAt` (epoch milliseconds, in real time) was 10 minutes ago, 50 minutes ago, 2 hours ago, 30 minutes ahead, and 90 minutes ahead. The receiver subscribed to `SELECT * FROM ev WHERE createdAt > clock() - 3600000` ("the last hour"). The observer checks ran on a separate device without sync |
| Documentation | [Date and Time](dql-functions.md#date-and-time) describes `clock()` as the current time on this device. Nothing describes when or on which device `clock()` in a subscription is evaluated |

Which documents arrived:

| Clocks | Documents that the receiver received | Same query run locally on the receiver |
|---|---|---|
| Both correct | 10 and 50 minutes ago, 30 and 90 minutes ahead | The same four |
| The sender's clock 2 hours ahead | 90 minutes ahead only | 90 minutes ahead only |
| The receiver's clock 2 hours ahead | 10 and 50 minutes ago, 30 and 90 minutes ahead | 90 minutes ahead only |

- A subscription that contains `clock()` is accepted. The sending device evaluates the condition with its own clock, as it evaluates every subscription's `WHERE` clause (see [The sending peer evaluates a subscription's WHERE clause like a local query](subscriptions-and-replication.md#the-sending-peer-evaluates-a-subscriptions-where-clause-like-a-local-query)); the receiver's clock is not used. When the receiver's clock ran ahead, three of the four documents it received did not appear in its own query with the same condition.
- **When the condition is evaluated**: when a document is written, and when a new subscription arrives. Documents written before the subscription arrived were filtered correctly. When the sender's clock was set back so that a document entered the window, the document did not arrive:
  - after waiting 5 seconds, or 30 seconds
  - after the receiver reconnected (`sync.stop()` and `sync.start()`)
  - after the receiver registered the same subscription again
  - after the receiver closed and reopened the same persistence directory (same peer key) and registered the same subscription, with the same text and arguments
- **What moved the window**:
  - writing that document again on the sender delivered it. When two documents had entered the window and only one was written again, only that one arrived: the sender evaluates only the documents that are written, unlike an observer, which re-runs its query for the whole collection on a write
  - a subscription with different text (`clock() - 3600001`) delivered every document in the window, including those that had not arrived before: a new subscription makes the sender evaluate all documents with its current clock
  - a subscription with the same text and different arguments (`createdAt > clock() - :window`, with `:window` 1 ms longer) did the same. The earlier subscription stayed registered meanwhile
- **Observers**: an observer with `clock() - 60000` ("the last minute") showed a document written 57 seconds earlier. On 5.1.0 and 5.2.0, after 6 seconds, when the document had left the window, the observer was not called, and its last result still contained the document, while `execute` at the same moment returned none. A write to another collection did not call it either; a write to the same collection, even of a document outside the condition, did, and the document disappeared from the result. On 5.0.3, the observer was also called while nothing was written and sync was off (in 2 of 3 runs) or on a write to another collection (1 run), and the document disappeared: 5.0.3 re-runs observers on more events.

**Not tested:** periods longer than 30 seconds; cancelling a subscription and registering the same text and arguments again (by [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle), which says that re-registering after a cancel fetched only what had changed, it probably does not move the window); whether a write to one document makes the sender evaluate other documents that have entered the window; a new peer with a new persistence directory.

**Used in:** [Date and Time](dql-functions.md#date-and-time), [Subscription Rules](../best-practices/sync-and-subscriptions.md#subscription-rules).
