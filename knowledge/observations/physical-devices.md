# Physical Devices

How Ditto behaved between two and three physical iOS devices over the air: how fast Bluetooth LE and AWDL connected and how much they moved, what happened to sync while an app was in the background or frozen, and what changed with a third device. Every other observation in this guide ran on one Mac, over loopback TCP, or between simulators; this page is the one that ran on devices, and its limits are listed under each entry. How the tests were run in general is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [App lifecycle](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), and [Size Guidance](../../best-practices/attachments.md#size-guidance).

**In brief**

- Two iPads with only Bluetooth LE enabled saw each other 2.7 to 3.3 seconds after the apps started, and with only AWDL enabled 2.1 to 2.5 seconds after; with both enabled, the AWDL connection came first and the Bluetooth LE connection 3.9 to 10.2 seconds after the start ([Two iPads found each other over Bluetooth LE after about 3 seconds and over AWDL after about 2 seconds](#two-ipads-found-each-other-over-bluetooth-le-after-about-3-seconds-and-over-awdl-after-about-2-seconds), [With both Bluetooth LE and AWDL enabled, the AWDL connection came first](#with-both-bluetooth-le-and-awdl-enabled-the-awdl-connection-came-first)).
- Over Bluetooth LE, a document of 75 KB of random bytes took 7.6 to 9.6 seconds to arrive after the devices had found each other, and one of 225 KB about 23 seconds, about 10 KB/s in each direction while both directions carried a document; over AWDL, 768 KB of random bytes arrived 0.1 to 1.3 seconds after they had found each other ([Bluetooth LE moved about 10 KB/s in each direction, and AWDL moved 1 MB in about a second](#bluetooth-le-moved-about-10-kbs-in-each-direction-and-awdl-moved-1-mb-in-about-a-second)).
- With the two Bluetooth background modes enabled, an app that went to the background kept writing and receiving changes live over Bluetooth LE for 60 seconds on iPadOS 26.7 and 18.5, and for 300 seconds on iPadOS 26.7 ([Over Bluetooth LE, an app in the background kept syncing live](#over-bluetooth-le-an-app-in-the-background-kept-syncing-live)).
- The ticks crossed live only while the other app was in the foreground: when both apps were in the background, iOS suspended them for most of the stay and only 1 to 2 changes crossed in each direction, and an app whose process was frozen for 60 seconds received what the other device wrote after the resume; every device held all of the other's changes after the return ([When both apps were in the background or one was frozen, the devices caught up after the return](#when-both-apps-were-in-the-background-or-one-was-frozen-the-devices-caught-up-after-the-return)).
- Over AWDL, an app in the background wrote nothing and received at most 1 change there, on iPadOS 26.7 and 18.5; the devices caught up after the return ([Over AWDL, an app in the background took no part until it came back](#over-awdl-an-app-in-the-background-took-no-part-until-it-came-back)).
- With a third iPad (iPadOS 18.2) and SDK 5.2.0, every device saw its first peer over Bluetooth LE after 2.6 to 4.6 seconds in 29 of 30 device-runs (9.4 seconds in the other) and over AWDL after 1.8 to 3.7 seconds, and its presence graph held both others at once at some point in every run ([Three iPads saw their first peer over Bluetooth LE after about 3 seconds and over AWDL after about 2 seconds](#three-ipads-saw-their-first-peer-over-bluetooth-le-after-about-3-seconds-and-over-awdl-after-about-2-seconds)).
- With three iPads, the first of the two other payloads took 6.4 to 13.4 seconds to arrive over Bluetooth LE after a device had found a peer (7.6 to 9.6 seconds with two), and 0.1 to 0.9 seconds over AWDL ([With three iPads, the first of two payloads took 6 to 13 seconds over Bluetooth LE and under a second over AWDL](#with-three-ipads-the-first-of-two-payloads-took-6-to-13-seconds-over-bluetooth-le-and-under-a-second-over-awdl)).
- With three iPads, an app in the background kept syncing live over Bluetooth LE on each of the three iPadOS versions, for 60 seconds and, on iPadOS 18.2, for 300 seconds; with Bluetooth LE and AWDL both enabled it did as well, and the other two devices held every change of the device in the background ([Over Bluetooth LE, an app in the background kept syncing live](#over-bluetooth-le-an-app-in-the-background-kept-syncing-live), [With Bluetooth LE and AWDL both enabled, an app in the background kept syncing live](#with-bluetooth-le-and-awdl-both-enabled-an-app-in-the-background-kept-syncing-live)).
- With three iPads, a frozen process on iPadOS 18.5 and 18.2, and all three apps in the background, ended with every device holding every change, as with two; when one device was frozen, only its presence graph lost all its peers ([When both apps were in the background or one was frozen, the devices caught up after the return](#when-both-apps-were-in-the-background-or-one-was-frozen-the-devices-caught-up-after-the-return)).
- Over Bluetooth LE, the presence graph of the iPad on iPadOS 18.2 lost all its peers in 4 of 10 pairs and in all 7 runs in which it was the one app in the background, while the graphs of the iPads on 18.5 and 26.7 never did in the pairs or as the one app in the background (3 runs each); in the pairs it moved with the launch order, and the cause is not established ([Over Bluetooth LE, one of three iPads lost all its peers from its presence graph more often than the other two](#over-bluetooth-le-one-of-three-ipads-lost-all-its-peers-from-its-presence-graph-more-often-than-the-other-two)).

## Test Setup

All entries on this page share this setup:

- **Devices**: two iPad mini (6th generation), one on iPadOS 18.5 (called device A below) and one on iPadOS 26.7 (device B), wired to one Mac and close to each other (the distance was not measured). Unless an entry says that the roles were swapped, device B was the device that went to the background. The entries that say "three iPads" add a third iPad mini of the same model on iPadOS 18.2 (device C), on the same desk and wired to the same Mac. No run used more than three iPads.
- **App**: a small Swift app built and installed by the lab for these runs (a debug build), with the Bluetooth LE background modes **Uses Bluetooth LE accessories** and **Acts as a Bluetooth LE accessory** declared. It disables the idle timer while it is in the foreground, so the screen stays on then.
- **Ditto**: Swift SDK 5.1.0 and 5.2.0, small-peers-only mode with an offline license token, a new database ID and a new persistence directory for every run. Only the transports that the entry names were enabled, and the app read the configuration back from the SDK to check it. Each device subscribed to a collection, started sync, and wrote one document; "seen after" is measured from the start of the app to the first moment that the presence graph listed the other device.
- **Control**: before each run marked "paired", a control run with every transport disabled ran with the same devices; no device may see another in it. All 12 controls of the two-iPad runs and all 13 of the three-iPad runs passed (none saw another).
- **Background**: for 20 seconds, both apps ran in the foreground; then Settings was put in front of the app of one device (state `inactive`, then `background`) for 60 seconds, and the app was brought back. In runs with a background stay, each app also wrote a small "tick" document every 5 seconds and recorded, for every tick that arrived, the state that its writer and its receiver were in. A device is said to have had a "drop" when its presence graph went from at least one peer to none. With two devices, that is the loss of the other device; with three, a graph that keeps one peer is not a drop, so a count of zero does not show that a device never lost one of the others.
- **Runs**: each procedure ran three times on each release listed (the longer runs and the 300 KB payload on 5.2.0 only), one run after the other, because the radio is shared. A test harness that builds the app, installs it, starts both apps, and collects each device's result ran them; the devices' identifiers and names, and the signing team, are not part of this guide.
- **Three iPads**: the entries about three iPads ran on 2026-11-17 on SDK 5.2.0, and the series of Bluetooth LE in the background also on 5.1.0, with the setup above and these differences. The harness launches the apps one after the other in a fixed order, and the device that goes to the background (or is frozen) is the last in that order, so each series says the order. Each app also records the most peers that its presence graph held at once (2 means that it knew of both others at some moment, directly or through the other; the app records no time for the second peer and not whether a link was direct). The "first payload" of an entry is the first arrival of a payload written by another device; the app does not record a second arrival. The background stay lasted 60 seconds unless an entry says otherwise, with the tick documents written every 5 seconds as above.

## Connecting over the Air

### Two iPads found each other over Bluetooth LE after about 3 seconds and over AWDL after about 2 seconds

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three paired runs each for each transport; every run passed |
| Setup | The setup above, with only Bluetooth LE enabled in one series and only AWDL enabled in the other. Each device wrote one document after it started sync and waited for the other's |
| Documentation | [Mesh Networking](https://docs.ditto.live/key-concepts/mesh-networking) lists Bluetooth LE and AWDL as peer-to-peer transports of Apple devices |

- **Bluetooth LE**: each device saw the other after 2.7 to 3.3 seconds (5.2.0: 2.7 to 3.1; 5.1.0: 2.7 to 3.3) and received the other's document after 2.9 to 3.5 seconds. The only connection type in the presence graph was `Bluetooth`. No device saw its connection drop in any of the 6 runs.
- **AWDL**: each device saw the other after 2.1 to 2.5 seconds (both releases) and received the other's document after 2.3 to 3.2 seconds. The only connection type was `P2PWiFi`. One of the 12 device-runs saw its connection drop once.
- In all 12 controls, with every transport disabled, neither device saw the other.
- The two simulators of [Two iOS simulators synced over AWDL alone](connections-and-presence.md#two-ios-simulators-synced-over-awdl-alone) found each other after 0.6 to 1.5 seconds, measured from the start of sync; the devices took longer.

**Not tested:** devices of other models, other iOS versions, and iPhones; a distance, walls, or interference; more than two devices in this series (three are in [Three iPads saw their first peer over Bluetooth LE after about 3 seconds and over AWDL after about 2 seconds](#three-ipads-saw-their-first-peer-over-bluetooth-le-after-about-3-seconds-and-over-awdl-after-about-2-seconds)); a restart of one app while the other keeps running; a first launch, on which iOS asks for the permissions (the permissions were granted before these runs).

**Used in:** [Several peers in one test process](../../best-practices/testing.md#several-peers-in-one-test-process).

### With both Bluetooth LE and AWDL enabled, the AWDL connection came first

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; both types appeared in every run |
| Setup | The setup above, with Bluetooth LE and AWDL both enabled. No control run |
| Documentation | None on the order of the connections |

- The first connection that each device saw was `P2PWiFi`, after 2.6 to 3.4 seconds, in every run.
- The `Bluetooth` connection of the same pair appeared later: after 3.9 to 10.2 seconds on 5.1.0 (9.9 and 10.2 in two runs, about 4 in the third) and 4.1 to 8.4 seconds on 5.2.0 (about 4 in five of the six device-runs). With only Bluetooth LE enabled, it appeared after 2.7 to 3.3 seconds.
- Both types were in the presence graph of both devices during every run (each device's record lists both), and no device saw its connection drop.

**Not tested:** which connection carries the data when both exist; what happens to the other connection when AWDL is lost.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

### Bluetooth LE moved about 10 KB/s in each direction, and AWDL moved 1 MB in about a second

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each with a 100 KB payload over Bluetooth LE and a 1,024 KB payload over AWDL; SDK 5.2.0, three runs with a 300 KB payload over Bluetooth LE; every run passed |
| Setup | The setup above, with only Bluetooth LE or only AWDL enabled. Right after it started, each device wrote one document with a string field of N × 1,024 characters (the "N KB payload"), which was the base64 text of N × 768 random bytes. The bytes were random because the SDK compresses what it sends, and a repeated character made 1 MB arrive in 0.6 seconds over Bluetooth LE in an earlier try; the base64 text compresses back to about the 0.75 of its size. Both directions therefore carried a payload at the same time. The arrival time is measured on the receiving device |
| Documentation | The [FAQ](https://docs.ditto.live/home/faq) gives Bluetooth LE sync as "typically 20 kB/second", and 3 to 6 kB/second for the older GATT mode on Android below 10 |

- **Bluetooth LE, 100 KB (75 KB of random bytes)**: the payload was written 0.5 to 0.6 seconds after the start and arrived 10.3 to 13.0 seconds after it, which is 7.6 to 9.6 seconds after the devices had found each other. That is about 8 to 10 KB/s of content in each direction (11 to 13 KB/s counting the characters of the string), at the same time in both directions.
- **Bluetooth LE, 300 KB (225 KB of random bytes)**: the payload arrived 22.6 to 23.5 seconds after the devices had found each other, about 10 KB/s of content in each direction. Three times the payload took about three times as long, so the time of a transfer was its size divided by that rate, with a start-up delay of less than a second.
- The documentation's "about 20 kB/second" is consistent with this if it is the rate of the link in both directions together (about 16 to 20 KB/s in these runs). We did not send in one direction only, so we do not know whether one direction alone goes faster.
- **AWDL, 1 MB (768 KB of random bytes)**: the payload was written 1.7 to 1.8 seconds after the start and arrived 3.1 to 4.4 seconds after it, which is 0.1 to 1.3 seconds after the devices had found each other. We did not compute a rate, because the transfer may have begun before the presence graph listed the peer.
- During the Bluetooth LE payload runs, device A saw its connection drop once in 3 of the 6 runs with 100 KB and 1 of the 3 runs with 300 KB, and device B in 1 of the 3 runs with 300 KB and in none with 100 KB; the paired runs without a payload had no drop. We did not swap the roles in these runs, so we cannot say whether the iPadOS version, the device, or the position in the link is the cause. The documents arrived in all 9 runs. With AWDL, 2 of the 12 device-runs saw one drop.

**Not tested:** payloads other than 100 and 300 KB over Bluetooth LE and 1,024 KB over AWDL; one direction at a time; attachments; Android devices and Wi-Fi Aware.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [Size Guidance](../../best-practices/attachments.md#size-guidance).

### Three iPads saw their first peer over Bluetooth LE after about 3 seconds and over AWDL after about 2 seconds

| | |
|---|---|
| Observed on | SDK 5.2.0: ten paired runs over Bluetooth LE (30 device-runs), three paired runs over AWDL (the runs of the next entry), and seven runs with both transports (the runs of the entry on both transports in the background); every run passed |
| Setup | The three iPads of the setup above, close to each other. Bluetooth LE only, in three launch orders: A, B, C (4 runs), C, B, A (3 runs), and A, C, B (3 runs). AWDL only, and Bluetooth LE with AWDL, with the launch order A, B, C or B, C, A. Each paired run had a control. "Seen after" is measured from the start of the app, as above |
| Documentation | [Mesh Networking](https://docs.ditto.live/key-concepts/mesh-networking) lists Bluetooth LE and AWDL as peer-to-peer transports of Apple devices |

- **Bluetooth LE**: 29 of the 30 device-runs saw the first other device after 2.6 to 4.6 seconds, and the other (device C, launch order A, B, C) after 9.4 seconds. The first document written by another device was in the local store 2.9 to 9.8 seconds after the start (the app polls for it). The only connection type was `Bluetooth`. With two iPads, the devices saw each other after 2.7 to 3.3 seconds.
- **AWDL**: the 9 device-runs saw the first other device after 1.8 to 3.7 seconds; the only connection type was `P2PWiFi`. With two iPads, it took 2.1 to 2.5 seconds.
- **Bluetooth LE and AWDL together**: in all 21 device-runs, `P2PWiFi` came first, after 2.4 to 3.6 seconds, and `Bluetooth` after 3.9 to 5.2 seconds (4.1 to 8.4 seconds with two iPads on 5.2.0); both types were in every device's record.
- In all 60 device-runs of these three series, the presence graph of each device held both other devices at the same time at some point (a peak of 2), but the app does not record when the second one appeared, so the times above are those of the first peer. The graph also lists devices that a peer can reach, so the peak shows that a device knew of both others, not that it had a direct connection to each.
- In all 13 controls, with every transport disabled, no device saw another.

**Not tested:** three iPads on SDK 5.1.0 (this release ran only the Bluetooth LE background series); devices that are out of range of each other, so that one device reaches another only through the third; which pairs had a direct connection; more than three devices.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [Several peers in one test process](../../best-practices/testing.md#several-peers-in-one-test-process).

### With three iPads, the first of two payloads took 6 to 13 seconds over Bluetooth LE and under a second over AWDL

| | |
|---|---|
| Observed on | SDK 5.2.0, three runs with a 100 KB payload over Bluetooth LE and three paired runs with a 1,024 KB payload over AWDL; every run passed |
| Setup | The setup of the entry above, with the launch order A, B, C. Right after it started, each device wrote one document with a string field of N × 1,024 characters (the base64 text of N × 768 random bytes, as in the two-iPad entry), so each device was to receive two payloads. The app records only the first payload that arrives |
| Documentation | The [FAQ](https://docs.ditto.live/home/faq) gives Bluetooth LE sync as "typically 20 kB/second" |

- **Bluetooth LE, 100 KB (75 KB of random bytes)**: the payloads were written 0.6 seconds after the start. The first payload that a device received arrived 9.1 to 17.8 seconds after the start, which is 6.4 to 13.4 seconds after the device had found its first peer. Six of the 9 device-runs took 6.4 to 7.9 seconds and three took 12.3 to 13.4 seconds (one device in each run). With two iPads, a payload of the same size arrived 7.6 to 9.6 seconds after the devices had found each other. No device's presence graph lost all its peers in these runs.
- **AWDL, 1 MB (768 KB of random bytes)**: the payloads were written 1.7 to 1.9 seconds after the start, and the first one that a device received arrived 2.2 to 3.8 seconds after the start, which is 0.1 to 0.9 seconds after it had found its first peer (9 device-runs). With two iPads: 0.1 to 1.3 seconds.
- We do not know when the second payload arrived, and so we did not compute a rate: the first payload may have come from either of the other two devices, and the link may have been shared.

**Not tested:** when the second payload arrived; one sender at a time; payload sizes other than 100 KB and 1,024 KB; three iPads on SDK 5.1.0.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

### Over Bluetooth LE, one of three iPads lost all its peers from its presence graph more often than the other two

| | |
|---|---|
| Observed on | SDK 5.2.0 in all rows, and 5.1.0 where the row says so; the number of runs is in the table. Every run passed, and in the runs with tick documents, each device held every tick of the others after the end of the stay |
| Setup | The setup above. A "drop" is a presence graph that went from at least one peer to none, counted for each device. With three devices, a graph that keeps one peer is not a drop, so a count of zero for the other two devices does not show whether they lost the device that was in the background or frozen; only a loss of both others shows. The launch order is the order in which the harness started the apps; the device that went to the background or was frozen is the last in that order, and the row names it. Bluetooth LE only, unless a line below says otherwise |
| Documentation | None on drops of a connection |

Drops of the presence graph of each device in each run (one number for each run):

| Series | Runs | A (iPadOS 18.5) | B (iPadOS 26.7) | C (iPadOS 18.2) |
|---|---|---|---|---|
| Paired, order A, B, C | 4 | 0, 0, 0, 0 | 0, 0, 0, 0 | 0, 1, 1, 1 |
| Paired, order C, B, A | 3 | 0, 0, 0 | 0, 0, 0 | 1, 0, 0 |
| Paired, order A, C, B | 3 | 0, 0, 0 | 0, 0, 0 | 0, 0, 0 |
| 100 KB payload, order A, B, C | 3 | 0, 0, 0 | 0, 0, 0 | 0, 0, 0 |
| AWDL only, 1 MB payload, paired, order A, B, C | 3 | 2, 0, 0 | 0, 0, 1 | 0, 0, 0 |
| C in the background, order A, B, C | 3 | 0, 0, 0 | 0, 0, 0 | 1, 2, 2 |
| C in the background, SDK 5.1.0 | 3 | 0, 0, 0 | 0, 0, 0 | 4, 1, 2 |
| C in the background for 300 seconds | 1 | 0 | 0 | 10 |
| A in the background, order B, C, A | 3 | 0, 0, 0 | 0, 0, 0 | 0, 0, 0 |
| B in the background, order A, C, B | 3 | 0, 0, 0 | 0, 0, 0 | 0, 0, 0 |
| C frozen, order A, B, C | 3 | 0, 0, 0 | 0, 0, 0 | 1, 1, 1 |
| A frozen, order B, C, A | 3 | 1, 1, 1 | 0, 0, 0 | 0, 0, 0 |
| All three in the background, order A, B, C | 3 | 1, 2, 1 | 2, 1, 1 | 1, 1, 2 |

- The graph of device C lost all its peers 1 to 10 times in each of the 7 runs in which C was the one app in the background (4, 1, and 2 on 5.1.0), while the graphs of A and B never did as the one app in the background (3 runs each). Frozen, the graph of C and that of A lost all peers once in every run, and the graphs of the other two never did, which does not show whether they lost the frozen device.
- In the 10 Bluetooth LE paired runs, only the graph of C emptied (4 runs), and how often depended on the launch order: 3 of 4 when it started last, 1 of 3 when it started first, and 0 of 3 when it started in the middle. The runs with the 100 KB payload had the same order as the first row and no drop, so the order does not explain it alone. In the 3 AWDL pairs, the graph of A emptied in 1 run (twice) and that of B in 1 run, and that of C in none.
- With Bluetooth LE and AWDL both enabled and C in the background, the graph of C never emptied in 3 of 4 runs and emptied once in the fourth; the graphs of the other two never did. With A in the background, no graph emptied in 3 runs.
- In some runs, the last presence snapshot of a device listed no peer, although the device held every change of the others; the harness does not judge it.
- We cannot tell the device, its iPadOS version, and its place in the launch order apart: each iPadOS version ran on one device, and the order was varied only for the paired runs and for the background runs of A and B.

**Not tested:** whether the other two devices lost a single peer (the app counts only an empty graph); a second device on iPadOS 18.2, or iPadOS 18.2 on another device; a launch order for each series; Bluetooth LE with the three iPads in different places (a distance, walls, or interference).

**Used in:** [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Several peers in one test process](../../best-practices/testing.md#several-peers-in-one-test-process).

## Apps in the Background

### Over Bluetooth LE, an app in the background kept syncing live

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each with device B in the background, and 5.2.0, three runs with the roles swapped (device A in the background); one more run of 300 seconds on 5.2.0; every run gave the same result. iPadOS 26.7 (device B) and 18.5 (device A). With three iPads: 5.2.0, three runs each with device C (iPadOS 18.2), A, and B in the background, and one run of 300 seconds with C; 5.1.0, three runs with C |
| Setup | The setup above, with only Bluetooth LE enabled and the tick documents on. Settings was put in front of the app of one device for 60 seconds (300 seconds in the longer run), with the other app in the foreground. The screen state during the stay was not recorded; with Settings in front, the screen may have locked during the 300-second stay, which the app cannot tell from the background |
| Documentation | The [Swift install guide](https://docs.ditto.live/sdk/latest/install-guides/swift) says that enabling the Bluetooth background modes keeps the app syncing "while it runs in the background, as well as when the end-user device is locked". The [FAQ](https://docs.ditto.live/home/faq) calls iOS background sync "best-effort" and says it may become less reliable in Low Power Mode |

- **Device B in the background (iPadOS 26.7)**: in all 6 runs, the app wrote 12 ticks in the background and the other device received all 12 while its own app was in the foreground; the app in the background received 11 ticks there. Each device wrote 22 ticks and received all 22 of the other's.
- **Device A in the background (iPadOS 18.5)**: in all 3 runs, the app wrote 11 ticks in the background and received 11 or 12 there. Each device wrote and received 22 ticks, and no tick was missing.
- **300 seconds (device B, one run)**: the app wrote 59 ticks and received 59 in the background, and each device ended with every tick of the other (70 and 69 written, 70 and 69 received).
- **Three iPads, one app in the background for 60 seconds (SDK 5.2.0, 3 runs each; launch order A, B, C with C last, B, C, A with A last, and A, C, B with B last)**: the app in the background wrote 10 to 11 ticks there (device C), 11 (device A), or 11 to 12 (device B), and received 22 to 23 (C), 22 (A), or 22 to 24 (B) while the other two apps were in the foreground and writing. In all 9 runs, the device in the background held every tick that both others had written (22 from each), and each of the others held every tick of the device in the background (21 to 22 from C, 22 from A or B). The graphs of the other two never became empty in the 9 runs; the graph of the device in the background became empty 1 to 2 times if it was C, and never if it was A or B.
- **Three iPads, SDK 5.1.0 (device C in the background, 3 runs)**: C wrote 9 to 11 ticks in the background and received 23 there in each run, and the other two held all of its ticks. The graph of C became empty 4, 1, and 2 times.
- **Three iPads, 300 seconds (device C, SDK 5.2.0, one run)**: C wrote 55 ticks in the background (an awake app would have written 58) and received 118 there, 59 from each of the others. Both others held all 66 ticks that C wrote, and C held the 70 and 69 ticks that the others wrote. The graph of C became empty 10 times, and the graphs of the other two never did.
- Connection drops were reported in 5 of the 18 device-runs with a 60-second stay (0 to 2 drops each) and by 1 of the 2 devices of the longer run (1 drop), and the ticks arrived anyway, so a drop was followed by a new connection. We do not know whether a drop happened because of the background state. With three iPads, the graph that became empty was that of the device on iPadOS 18.2 (see [Over Bluetooth LE, one of three iPads lost all its peers from its presence graph more often than the other two](#over-bluetooth-le-one-of-three-ipads-lost-all-its-peers-from-its-presence-graph-more-often-than-the-other-two)).
- The background state in these runs is an app that another app (Settings) has replaced in the foreground. We did not set the screen to lock, and did not test Low Power Mode or a terminated app. The ticks crossed live only while the other device's app was in the foreground and writing every 5 seconds; with both apps in the background, see the next entry.

**Not tested:** a locked screen, Low Power Mode, an app that the user ended, an app that never had the background modes, stays longer than 300 seconds (and 300 seconds on iPadOS 18.5), other iOS versions, and Android (where a foreground service is documented, not Bluetooth LE).

**Used in:** [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Sync and the app lifecycle in Swift](../../best-practices/platforms/swift.md#sync-and-the-app-lifecycle-in-swift).

### When both apps were in the background or one was frozen, the devices caught up after the return

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each for each procedure; every run passed and gave the same result on both releases. With three iPads: SDK 5.2.0, three runs each with device A (iPadOS 18.5) or device C (iPadOS 18.2) frozen, and three runs with all three apps in the background |
| Setup | The setup above with only Bluetooth LE enabled and the tick documents on. In one series, the app of device B (iPadOS 26.7) was frozen for 60 seconds (the harness suspended the process, then resumed it, a repeatable version of what iOS does to a suspended app); in the other, both apps were sent to the background one after the other and brought back together. With three iPads, the frozen device was the last in the launch order (B, C, A with A frozen; A, B, C with C frozen), and all three apps were sent to the background one after the other and brought back together |
| Documentation | The FAQ and the Swift install guide do not describe what happens when the app is suspended or frozen |

- **A frozen process**: the frozen app wrote 10 ticks (none while frozen), the other device wrote 22. After the resume, device B held all 22 ticks of the other device and the other device held all 10 of device B's, in all 6 runs. Device A saw its connection drop once in every run, device B 1 to 3 times.
- **Both apps in the background**: iOS suspended both apps for most of the stay. Each app wrote 12 or 13 ticks in total, of which 1 to 3 in the background (against 22 in total when only one app was in the background), and received 1 or 2 ticks in the background. 1 or 2 ticks crossed in each direction while both apps were in the background. After the return, each device held every tick of the other. Each device saw its connection drop once or twice.
- So the sync did not stop for good in any of the 12 runs: a device that had been suspended or frozen received what the other device had written.
- **Three iPads, one frozen (SDK 5.2.0, 3 runs each with A or C frozen)**: the frozen app wrote 10 ticks (none while frozen), and each of the other two wrote 22. After the resume, the frozen device held all 22 ticks of each of the others, and each of the others held all 10 of its ticks, in all 6 runs. The graph of the frozen device became empty once in every run, and the graphs of the other two never did, which does not show whether they lost the frozen device (with two iPads, the graph of the other device lost its only peer once in every run).
- **Three iPads, all three in the background (SDK 5.2.0, 3 runs)**: each app wrote 12 or 13 ticks in total (an awake app would have written 12 in the stay), of which 2 or 3 in the background, and received 3 or 4 ticks there. Between each pair of devices, 1 or 2 ticks crossed in each direction while both were in the background. After the return, each device held every tick of both others, in all 9 device-runs. The graph of each device became empty once or twice in each run.

**Not tested:** a stay longer than 60 seconds with both apps in the background; a frozen process on iPadOS 26.7 with three iPads; a terminated app.

**Used in:** [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync).

### Over AWDL, an app in the background took no part until it came back

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each with device B (iPadOS 26.7) in the background, and 5.2.0, three runs with device A (iPadOS 18.5) in the background; every run passed. With three iPads: SDK 5.2.0, three runs with device C (iPadOS 18.2) in the background |
| Setup | The setup above with only AWDL enabled and the tick documents on, and one device in the background for 60 seconds. The harness judged only that the devices caught up after the return, because Ditto documents background sync for Bluetooth LE only |
| Documentation | The FAQ names Bluetooth LE as the transport of iOS background sync; it names no other transport |

- In all 9 runs, the app in the background wrote no tick there (its 10 ticks came before, and one came as the app returned), and it received 1 tick there in 1 of the 9 runs (0 in the others), while the same app wrote 11 or 12 and received 11 or 12 over Bluetooth LE. The other device, with its app in the foreground, received 1 tick that the background app wrote as it came back.
- After the return, each device held the other's ticks: the one that had been in the background held all 22 of the other's, and the other held all 11 of its ticks (10 of 11 in one run).
- The device in the background saw its connection drop 1 to 3 times (2 or 3 on iPadOS 26.7, 1 or 2 on iPadOS 18.5) and the other device 1 or 2 times.
- **Three iPads (device C in the background, launch order A, B, C, 3 runs)**: C wrote no tick in the background (10 ticks before, and one as it returned) and received 1 tick there in 2 of the 3 runs (none in the other). Each of the other two devices held all 11 ticks that C wrote, and C held all 22 ticks of each of the others. The graph of C became empty 2, 2, and 1 times, and the graphs of the other two never did.

**Not tested:** LAN (TCP) in the background; AWDL together with Bluetooth LE in the background is in [With Bluetooth LE and AWDL both enabled, an app in the background kept syncing live](#with-bluetooth-le-and-awdl-both-enabled-an-app-in-the-background-kept-syncing-live); a stay longer than 60 seconds.

**Used in:** [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Sync and the app lifecycle in Swift](../../best-practices/platforms/swift.md#sync-and-the-app-lifecycle-in-swift).

### With Bluetooth LE and AWDL both enabled, an app in the background kept syncing live

| | |
|---|---|
| Observed on | SDK 5.2.0, three iPads, seven runs (four with device C in the background and three with device A); every run passed and gave the same result |
| Setup | The setup above, with Bluetooth LE and AWDL both enabled and the tick documents on. One app was in the background for 60 seconds while the other two were in the foreground, writing a tick every 5 seconds. The launch order was A, B, C with C last, or B, C, A with A last. The harness judged only that the devices caught up after the return, because Ditto documents background sync for Bluetooth LE only |
| Documentation | The [FAQ](https://docs.ditto.live/home/faq) names Bluetooth LE as the transport of iOS background sync; it names no other transport |

- The app in the background wrote 11 or 12 ticks there (an awake app would have written 10) and received 24 there, in all 7 runs. With only AWDL, the same app wrote none there, and with only Bluetooth LE it wrote 10 to 12 and received 22 to 24.
- Each of the other two devices held every tick of the app in the background, and the device in the background held all 22 ticks of each of the others, in all 7 runs.
- The graph of the device in the background never became empty in 6 of the 7 runs (that of C did once in the seventh), and the graphs of the other two never did. With only Bluetooth LE, the graph of C became empty 1 to 2 times in each of the 3 runs.
- Both connection types (`Bluetooth` and `P2PWiFi`) were in the presence graphs of all three devices. The data does not say which connection carried the ticks that crossed while the app was in the background: both were up, and Bluetooth LE may have been the one that kept the app awake.

**Not tested:** which of the two transports carried the ticks in the background (for example, with the Bluetooth LE connection cut); a stay longer than 60 seconds; two iPads with both transports; SDK 5.1.0.

**Used in:** [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Sync and the app lifecycle in Swift](../../best-practices/platforms/swift.md#sync-and-the-app-lifecycle-in-swift).
