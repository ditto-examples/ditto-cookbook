# Physical Devices

How Ditto behaved between two physical iOS devices over the air: how fast Bluetooth LE and AWDL connected and how much they moved, and what happened to sync while an app was in the background or frozen. Every other observation in this guide ran on one Mac, over loopback TCP, or between simulators; this page is the one that ran on devices, and its limits are listed under each entry. How the tests were run in general is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [App lifecycle](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), and [Size Guidance](../../best-practices/attachments.md#size-guidance).

**In brief**

- Two iPads with only Bluetooth LE enabled saw each other 2.7 to 3.3 seconds after the apps started, and with only AWDL enabled 2.1 to 2.5 seconds after; with both enabled, the AWDL connection came first and the Bluetooth LE connection 3.9 to 10.2 seconds after the start ([Two iPads found each other over Bluetooth LE after about 3 seconds and over AWDL after about 2 seconds](#two-ipads-found-each-other-over-bluetooth-le-after-about-3-seconds-and-over-awdl-after-about-2-seconds), [With both Bluetooth LE and AWDL enabled, the AWDL connection came first](#with-both-bluetooth-le-and-awdl-enabled-the-awdl-connection-came-first)).
- Over Bluetooth LE, a document of 75 KB of random bytes took 7.6 to 9.6 seconds to arrive after the devices had found each other, and one of 225 KB about 23 seconds, about 10 KB/s in each direction while both directions carried a document; over AWDL, 768 KB of random bytes arrived 0.1 to 1.3 seconds after they had found each other ([Bluetooth LE moved about 10 KB/s in each direction, and AWDL moved 1 MB in about a second](#bluetooth-le-moved-about-10-kbs-in-each-direction-and-awdl-moved-1-mb-in-about-a-second)).
- With the two Bluetooth background modes enabled, an app that went to the background kept writing and receiving changes live over Bluetooth LE for 60 seconds on iPadOS 26.7 and 18.5, and for 300 seconds on iPadOS 26.7 ([Over Bluetooth LE, an app in the background kept syncing live](#over-bluetooth-le-an-app-in-the-background-kept-syncing-live)).
- The ticks crossed live only while the other app was in the foreground: when both apps were in the background, iOS suspended them for most of the stay and only 1 to 2 changes crossed in each direction, and an app whose process was frozen for 60 seconds received what the other device wrote after the resume; every device held all of the other's changes after the return ([When both apps were in the background or one was frozen, the devices caught up after the return](#when-both-apps-were-in-the-background-or-one-was-frozen-the-devices-caught-up-after-the-return)).
- Over AWDL, an app in the background wrote nothing and received at most 1 change there, on iPadOS 26.7 and 18.5; the devices caught up after the return ([Over AWDL, an app in the background took no part until it came back](#over-awdl-an-app-in-the-background-took-no-part-until-it-came-back)).

## Test Setup

All entries on this page share this setup:

- **Devices**: two iPad mini (6th generation), one on iPadOS 18.5 (called device A below) and one on iPadOS 26.7 (device B), wired to one Mac and close to each other (the distance was not measured). Unless an entry says that the roles were swapped, device B was the device that went to the background.
- **App**: a small Swift app built and installed by the lab for these runs (a debug build), with the Bluetooth LE background modes **Uses Bluetooth LE accessories** and **Acts as a Bluetooth LE accessory** declared. It disables the idle timer while it is in the foreground, so the screen stays on then.
- **Ditto**: Swift SDK 5.1.0 and 5.2.0, small-peers-only mode with an offline license token, a new database ID and a new persistence directory for every run. Only the transports that the entry names were enabled, and the app read the configuration back from the SDK to check it. Each device subscribed to a collection, started sync, and wrote one document; "seen after" is measured from the start of the app to the first moment that the presence graph listed the other device.
- **Control**: before each run marked "paired", a control run with every transport disabled ran with the same two devices; neither device may see the other in it. All 12 controls passed (none saw the other).
- **Background**: for 20 seconds, both apps ran in the foreground; then Settings was put in front of the app of one device (state `inactive`, then `background`) for 60 seconds, and the app was brought back. In runs with a background stay, each app also wrote a small "tick" document every 5 seconds and recorded, for every tick that arrived, the state that its writer and its receiver were in. A device is said to have seen its connection "drop" when its presence graph lost the other device.
- **Runs**: each procedure ran three times on each release listed (the longer runs and the 300 KB payload on 5.2.0 only), one run after the other, because the radio is shared. A test harness that builds the app, installs it, starts both apps, and collects each device's result ran them; the devices' identifiers and names, and the signing team, are not part of this guide.

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

**Not tested:** devices of other models, other iOS versions, and iPhones; a distance, walls, or interference; more than two devices; a restart of one app while the other keeps running; a first launch, on which iOS asks for the permissions (the permissions were granted before these runs).

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

## Apps in the Background

### Over Bluetooth LE, an app in the background kept syncing live

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each with device B in the background, and 5.2.0, three runs with the roles swapped (device A in the background); one more run of 300 seconds on 5.2.0; every run gave the same result. iPadOS 26.7 (device B) and 18.5 (device A) |
| Setup | The setup above, with only Bluetooth LE enabled and the tick documents on. Settings was put in front of the app of one device for 60 seconds (300 seconds in the longer run), with the other app in the foreground. The screen state during the stay was not recorded; with Settings in front, the screen may have locked during the 300-second stay, which the app cannot tell from the background |
| Documentation | The [Swift install guide](https://docs.ditto.live/sdk/latest/install-guides/swift) says that enabling the Bluetooth background modes keeps the app syncing "while it runs in the background, as well as when the end-user device is locked". The [FAQ](https://docs.ditto.live/home/faq) calls iOS background sync "best-effort" and says it may become less reliable in Low Power Mode |

- **Device B in the background (iPadOS 26.7)**: in all 6 runs, the app wrote 12 ticks in the background and the other device received all 12 while its own app was in the foreground; the app in the background received 11 ticks there. Each device wrote 22 ticks and received all 22 of the other's.
- **Device A in the background (iPadOS 18.5)**: in all 3 runs, the app wrote 11 ticks in the background and received 11 or 12 there. Each device wrote and received 22 ticks, and no tick was missing.
- **300 seconds (device B, one run)**: the app wrote 59 ticks and received 59 in the background, and each device ended with every tick of the other (70 and 69 written, 70 and 69 received).
- Connection drops were reported in 5 of the 18 device-runs with a 60-second stay (0 to 2 drops each) and by 1 of the 2 devices of the longer run (1 drop), and the ticks arrived anyway, so a drop was followed by a new connection. We do not know whether a drop happened because of the background state.
- The background state in these runs is an app that another app (Settings) has replaced in the foreground. We did not set the screen to lock, and did not test Low Power Mode or a terminated app. The ticks crossed live only while the other device's app was in the foreground and writing every 5 seconds; with both apps in the background, see the next entry.

**Not tested:** a locked screen, Low Power Mode, an app that the user ended, an app that never had the background modes, stays longer than 300 seconds, other iOS versions, and Android (where a foreground service is documented, not Bluetooth LE).

**Used in:** [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Sync and the app lifecycle in Swift](../../best-practices/platforms/swift.md#sync-and-the-app-lifecycle-in-swift).

### When both apps were in the background or one was frozen, the devices caught up after the return

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each for each procedure; every run passed and gave the same result on both releases |
| Setup | The setup above with only Bluetooth LE enabled and the tick documents on. In one series, the app of device B (iPadOS 26.7) was frozen for 60 seconds (the harness suspended the process, then resumed it, a repeatable version of what iOS does to a suspended app); in the other, both apps were sent to the background one after the other and brought back together |
| Documentation | The FAQ and the Swift install guide do not describe what happens when the app is suspended or frozen |

- **A frozen process**: the frozen app wrote 10 ticks (none while frozen), the other device wrote 22. After the resume, device B held all 22 ticks of the other device and the other device held all 10 of device B's, in all 6 runs. Device A saw its connection drop once in every run, device B 1 to 3 times.
- **Both apps in the background**: iOS suspended both apps for most of the stay. Each app wrote 12 or 13 ticks in total, of which 1 to 3 in the background (against 22 in total when only one app was in the background), and received 1 or 2 ticks in the background. 1 or 2 ticks crossed in each direction while both apps were in the background. After the return, each device held every tick of the other. Each device saw its connection drop once or twice.
- So the sync did not stop for good in any of the 12 runs: a device that had been suspended or frozen received what the other device had written.

**Not tested:** a stay longer than 60 seconds with both apps in the background; a frozen process on iPadOS 18.5; a terminated app.

**Used in:** [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync).

### Over AWDL, an app in the background took no part until it came back

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each with device B (iPadOS 26.7) in the background, and 5.2.0, three runs with device A (iPadOS 18.5) in the background; every run passed |
| Setup | The setup above with only AWDL enabled and the tick documents on, and one device in the background for 60 seconds. The harness judged only that the devices caught up after the return, because Ditto documents background sync for Bluetooth LE only |
| Documentation | The FAQ names Bluetooth LE as the transport of iOS background sync; it names no other transport |

- In all 9 runs, the app in the background wrote no tick there (its 10 ticks came before, and one came as the app returned), and it received 1 tick there in 1 of the 9 runs (0 in the others), while the same app wrote 11 or 12 and received 11 or 12 over Bluetooth LE. The other device, with its app in the foreground, received 1 tick that the background app wrote as it came back.
- After the return, each device held the other's ticks: the one that had been in the background held all 22 of the other's, and the other held all 11 of its ticks (10 of 11 in one run).
- The device in the background saw its connection drop 1 to 3 times (2 or 3 on iPadOS 26.7, 1 or 2 on iPadOS 18.5) and the other device 1 or 2 times.

**Not tested:** LAN (TCP) in the background; AWDL together with Bluetooth LE in the background (the Bluetooth LE connection may have kept syncing); a stay longer than 60 seconds.

**Used in:** [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Sync and the app lifecycle in Swift](../../best-practices/platforms/swift.md#sync-and-the-app-lifecycle-in-swift).
