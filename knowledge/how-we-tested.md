# How We Tested

The knowledge pages describe how Ditto behaved when we ran it, next to what Ditto's documentation says. This page describes how we ran it, so that you can judge how far a result carries over to your app. Each observation names the SDK releases and the number of runs it is based on; this page explains the setup they share.

## Test Environment

- **SDK**: the JavaScript SDK (`@dittolive/ditto`) 5.0.3, 5.1.0, and 5.2.0 on Node.js 24, on one Mac. Most observations compare 5.1.0 and 5.2.0; 5.0.3 was added where a difference between releases mattered. Some key cases on 5.1.0 were also run with the Flutter SDK on macOS.
- **Peers**: Small Peers in small-peers-only mode with an offline license token, each in a new persistence directory. The peer-to-peer transports (Bluetooth LE, LAN discovery, AWDL) were disabled, and the peers connected over TCP on `127.0.0.1`: one peer (the hub) listened on a port, and the others listed it in `connect.tcpServers`. A peer that only connects still listens on all interfaces (see [A device that only connects also listens for TCP connections](connections-and-presence.md#a-device-that-only-connects-also-listens-for-tcp-connections)); since we found that, every peer also listens on `127.0.0.1` only, which did not change the results.
- **Processes**: most observations ran several Ditto instances in one Node.js process. Observations that needed different SDK releases, a peer that crashes or is suspended, or a different clock per peer ran each peer in its own process.
- **Relay**: to see what travels between two peers, a TCP relay sat between them. It counted the bytes in each direction, could limit each direction to a bandwidth (a slow link such as Bluetooth LE), and could pause the traffic without closing the connections (a network that stops passing data, as when Wi-Fi drops), then deliver what it had held. The relay itself buffers about 20 ms of traffic, at least 64 KiB.
- **Clocks**: to give one peer a clock that runs ahead or behind, its process ran with a library that shifts the wall clock by a set offset. Ditto's `clock()`, its log timestamps, and `Date.now()` all followed the shifted clock, while timers and timeouts kept working, because the monotonic clock was not shifted. Peers in one process share one clock, so only peers in separate processes can have different clocks.

## Reading the Results

- **Runs**: "three runs each" means that the same procedure was repeated three times on each listed release. Timing results were repeated at least three times before we drew a conclusion; results from a single run say so. "Deterministic" means that every run gave the same result.
- **Numbers**: times, sizes, and rates come from one machine over loopback TCP. Phones, real networks, and other transports will differ, often by a lot. Use the numbers for the order of magnitude and for the shape of the behavior (what waits for what, what grows with what), not as estimates for your app.
- **Releases**: when a result differs between releases, the observation gives each release's value. The best-practices pages carry the same information as labels such as **Note (SDK 5.1.0 and 5.2.0)**.
- **Documentation**: when Ditto's documentation, API reference, or release notes describe the behavior, the observation says so and whether we saw the same.
- **Scope**: what an observation did not cover is listed under "Not tested". The limits of the environment above apply to every observation.

## What We Did Not Test

- Mobile devices, and the Flutter, Swift, and Kotlin SDKs, except for the key Flutter cases on macOS
- Bluetooth LE, AWDL, Wi-Fi Aware, LAN discovery, and multicast; a slow or paused link was simulated with the relay
- Ditto Server, its HTTP API, and authentication through a webhook
- Real networks between machines, and more devices than each observation names

## Checks of the Guide Itself

These checks run on every change of the guide:

- **DQL statements**: every DQL statement in the guide, about 300 from the `sql` code blocks and from the Dart code passed to `execute`, observers, and subscriptions, runs in a new, empty store with placeholder arguments on 5.1.0 and 5.2.0 (and 5.0.3 when needed). The only statements that fail are those that the guide presents as errors, joins that need an index (an empty store has none, as [Index requirement](../best-practices/dql.md#index-requirement) describes), and, on 5.1.0, the statements marked (SDK 5.2+).
- **Expression examples**: every `expression` → `result` example in the guide is evaluated with `SELECT <expression> AS v FROM system:dual` and compared with the stated result; on 5.1.0 and 5.2.0 all of them matched (the `clock()` examples are checked for their type only). On 5.0.3, `serialize_json()` does not exist. One example shows a detail worth knowing: `tz_offset('America/New_York', 'TZN')` returned `-300` on 2026-10-31, while daylight saving time was in effect, so it returns the standard-time offset, not the current one.
- **Full runs**: all checks behind the knowledge pages ran in one pass on 5.2.0 (173 checks) and on 5.1.0 (177 checks) without errors, timeouts, or crashes, and the main numbers matched the earlier runs.
- **Dart code**: the Dart examples were compiled against `ditto_live` 5.1.0. Examples that use APIs added in 5.2 (such as `DittoConfig.systemParameters`), and the presence example, follow the `ditto_live` 5.1.0 and 5.2.0 API references.
