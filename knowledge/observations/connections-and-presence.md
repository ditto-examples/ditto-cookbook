# Connections and Presence

How devices connect to each other and how presence reports them: the TCP connection limit and how each release counts it, meshes and WebSocket hubs, changing and retrying connections, how long a lost or stalled connection takes to notice, the presence graph and peer metadata, and the connection handler and shared keys that decide which peers connect. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [Presence](../../best-practices/setup-and-lifecycle.md#presence), [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Controlling Incoming Connections](../../best-practices/security.md#controlling-incoming-connections), [Small-Peers-Only Deployments](../../best-practices/security.md#small-peers-only-deployments), and [Key Characteristics](../understanding-ditto.md#key-characteristics).

**In brief**

- A device accepts six TCP connections by default. Further devices get no data and no error, and raising the limit works only before sync starts ([A device accepts six TCP connections by default](#a-device-accepts-six-tcp-connections-by-default), [Raising the TCP limit takes effect only before sync starts](#raising-the-tcp-limit-takes-effect-only-before-sync-starts)).
- The at-capacity actions 1 and 2 let extra clients in on 5.2.0, but the hub then replaces connections in a 5-second cycle, and at every check, at least one client was not connected ([At-capacity actions 1 and 2 admit extra clients but keep replacing connections](#at-capacity-actions-1-and-2-admit-extra-clients-but-keep-replacing-connections)).
- On 5.2.0, a device probably counts the connections that it opened itself when it decides whether to accept another one, but the connections it opens are not limited. In a full mesh of seven or more devices, a device keeps 3 to 7 direct connections and receives changes from the other devices through its neighbors ([SDK 5.2.0 counts outgoing connections toward the TCP limit](#sdk-520-counts-outgoing-connections-toward-the-tcp-limit), [Outgoing TCP connections are not limited](#outgoing-tcp-connections-are-not-limited), [On SDK 5.2.0, devices in a full TCP mesh of seven or more keep 3 to 7 direct connections](#on-sdk-520-devices-in-a-full-tcp-mesh-of-seven-or-more-keep-3-to-7-direct-connections)).
- WebSocket connections to a Small Peer hub do not count toward the TCP limit: 30 clients synced ([WebSocket connections to a Small Peer hub do not count toward the TCP limit](#websocket-connections-to-a-small-peer-hub-do-not-count-toward-the-tcp-limit)).
- Changes of TCP targets and listeners take effect while sync runs, a lost connection is retried at `connect.retryInterval` (5 seconds by default in JavaScript), and a device that only connects over TCP also listens for TCP on all interfaces ([TCP targets and listeners change while sync runs](#tcp-targets-and-listeners-change-while-sync-runs), [A lost TCP connection is retried at the retry interval](#a-lost-tcp-connection-is-retried-at-the-retry-interval), [A device that only connects over TCP also listens for TCP connections](#a-device-that-only-connects-over-tcp-also-listens-for-tcp-connections)).
- A second hub can listen on a port that another hub already uses, without an error, and on macOS, new connections then go to the hub that started listening last ([A second hub listened on a port already in use without an error](#a-second-hub-listened-on-a-port-already-in-use-without-an-error)).
- A network that goes silent removes the peer from presence after about 7.3 seconds, and a suspended process after about 9.1 seconds. Until a stalled connection that carries sync is dropped, sync waits on it, even when another connection to the same peer works ([A silent network outage removes a peer after about 7 seconds](#a-silent-network-outage-removes-a-peer-after-about-7-seconds), [A suspended device leaves the presence graph after about 9 seconds](#a-suspended-device-leaves-the-presence-graph-after-about-9-seconds), [Each device sends over one of two connections and waits when it stalls](#each-device-sends-over-one-of-two-connections-and-waits-when-it-stalls)).
- Presence callbacks arrive about once a second while peers change and about every 15 seconds when nothing changes, the graph includes indirect peers and all of their connections, and a peer in the graph is not necessarily up to date ([Presence reports a joining peer after about 1.2 seconds](#presence-reports-a-joining-peer-after-about-12-seconds), [The presence graph includes indirect peers and all of their connections](#the-presence-graph-includes-indirect-peers-and-all-of-their-connections), [Slow links keep the connection and the presence entry](#slow-links-keep-the-connection-and-the-presence-entry)).
- The presence graph shows each peer's `dittoSdkVersion`, also across SDK releases, which identifies the devices that still run an older release ([Presence shows each peer's SDK version](#presence-shows-each-peers-sdk-version)).
- Presence and sync worked across a line of 20 devices, and while ten devices kept reconnecting, a stable device got presence callbacks about once per second and its sync was barely delayed ([Presence and sync work across a chain of 20 devices](#presence-and-sync-work-across-a-chain-of-20-devices), [Presence callbacks stay at about one per second while peers come and go](#presence-callbacks-stay-at-about-one-per-second-while-peers-come-and-go)).
- Peer metadata is replaced, not merged, reaches other peers about once per second, and is sent to every device whenever a device joins or changes it ([Peer metadata is replaced, not merged, and the device name is read when sync starts](#peer-metadata-is-replaced-not-merged-and-the-device-name-is-read-when-sync-starts), [Peer metadata changes reach other peers about once per second](#peer-metadata-changes-reach-other-peers-about-once-per-second), [Presence traffic carries each peer's metadata, and idle traffic grows faster than the number of devices](#presence-traffic-carries-each-peers-metadata-and-idle-traffic-grows-faster-than-the-number-of-devices)).
- A denied peer retries at its retry interval. Peers connect only when their shared keys match, and traffic without a key is TLS-wrapped but not authenticated ([A denied peer retries at the retry interval](#a-denied-peer-retries-at-the-retry-interval), [Shared keys must match, and traffic is TLS-wrapped without a key](#shared-keys-must-match-and-traffic-is-tls-wrapped-without-a-key)).

## The TCP Connection Limit

### A device accepts six TCP connections by default

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | A hub that listened on TCP, and eight clients that listed it in `connect.tcpServers`. We checked which clients received the hub's data, and counted the hub's TCP connections in `system:transport_connections` and its peers in `presence.graph.remotePeers` |
| Documentation | The 5.2.0 release notes describe a change in how connections are counted toward the limit: accepted and outgoing connections count together |

- On both releases, six clients received the data. The other two received nothing, even after 30 seconds.
- The hub had six TCP connections in `system:transport_connections`, and six peers in `presence.graph.remotePeers`.
- The change in the 5.2.0 release notes did not change how many clients a hub that only accepts connections admits. How 5.2.0 counts the connections that a device opens itself is described in [SDK 5.2.0 counts outgoing connections toward the TCP limit](#sdk-520-counts-outgoing-connections-toward-the-tcp-limit).

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [Multi-hop relay](../../best-practices/sync-and-subscriptions.md#multi-hop-relay), [Several peers in one test process](../../best-practices/testing.md#several-peers-in-one-test-process), [System Parameters Reference](../system-reference.md#system-parameters-reference).

### Raising the TCP limit takes effect only before sync starts

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each. Lowering the limit before sync started: SDK 5.0.3, 5.1.0, and 5.2.0, three runs each |
| Setup | The hub and eight clients of the previous entry. The hub set `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` to 12 before `sync.start()`: on 5.2.0 in `DittoConfig.systemParameters`, on 5.1.0 with `ALTER SYSTEM`. In a second case, the hub started sync with the default of 6 and then set 12 with `ALTER SYSTEM` |

- With the limit set before `sync.start()`, all eight clients received the data, and the hub's presence showed eight peers.
- With the limit raised after sync had started, the hub still served six clients after 60 seconds.
- On 5.0.3, `ALTER SYSTEM` before `sync.start()` also takes effect: with the limit lowered to 2, only two of three TCP clients synced, as on 5.1.0 and 5.2.0 (see [WebSocket connections to a Small Peer hub do not count toward the TCP limit](#websocket-connections-to-a-small-peer-hub-do-not-count-toward-the-tcp-limit)).

**Not tested:** raising the limit on 5.0.3.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [Multi-hop relay](../../best-practices/sync-and-subscriptions.md#multi-hop-relay), [System Parameters Reference](../system-reference.md#system-parameters-reference).

### SDK 5.2.0 counts outgoing connections toward the TCP limit

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; the two devices that connect to each other and the relay with six clients: one run each. Every run gave the same result |
| Setup | Four layouts, each with the default limit of 6: (1) six clients connected to a hub, and the hub also connected to two devices that only listened; (2) six clients connected to a hub, and the hub also connected to three of them, so that three pairs were connected in both directions; (3) two devices that listed each other in `connect.tcpServers`, watched for 40 seconds; (4) a relay device that connected to an upstream hub and accepted six clients. We counted the accepted and outgoing TCP connections and checked which devices received data |
| Documentation | The 5.2.0 release notes say that accepted and outgoing connections count together toward the limit. We saw this on 5.2.0 |

| Layout | 5.1.0 | 5.2.0 |
|---|---|---|
| (1) Hub with six clients that also connects to two listening devices | All eight devices received data (6 accepted, 2 outgoing) | Six devices received data: two of the clients that had connected to the hub were dropped (4 accepted, 2 outgoing) |
| (2) Hub with six clients that also connects to three of them | The hub held 9 TCP connections; all six clients received data | The hub reduced them to 6 (3 accepted, 3 outgoing); all six clients received data |
| (3) Two devices that connect to each other | 2 TCP connections remained for 40 seconds | The same |
| (4) Relay connected to an upstream hub, with six clients | Kept the upstream connection and accepted all six clients (6 accepted, 1 outgoing) | Kept the upstream connection and accepted five clients; the sixth received nothing |

- On 5.2.0, the limit applies to the sum of accepted and outgoing connections, as the release notes say. On 5.1.0, it applies only to accepted connections, so a hub that opened connections itself kept more than six devices in sync.
- A relay that also listens accepts as many fewer clients on 5.2.0 as it has connections upstream.
- Duplicate connections did not reduce the number of devices that synced, on either release.
- Two devices below the limit kept both of their connections, which suggests that duplicate connections are not cleaned up while a device is below the limit.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [System Parameters Reference](../system-reference.md#system-parameters-reference).

### Outgoing TCP connections are not limited

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result. The case with eight targets, and the full mesh of eight devices watched for 150 seconds (5.2.0): one run each |
| Setup | A device that did not listen listed 8, 12, or 16 devices that only listened in `connect.tcpServers`. In a second case, eight devices each listened and listed all the others |
| Documentation | The 5.2.0 release notes say that accepted and outgoing connections count together |

- The device connected to all of them: 8, 12, and 16 direct connections and as many TCP connections, all of them outgoing. A document that it wrote reached every device.
- In the full mesh of eight devices on 5.2.0, the device that opened first kept 9 connections (5 accepted, 4 outgoing) for the whole 150 seconds, without change.
- Together with [SDK 5.2.0 counts outgoing connections toward the TCP limit](#sdk-520-counts-outgoing-connections-toward-the-tcp-limit), this suggests that on 5.2.0 a device counts its outgoing connections when it decides whether to accept a new connection (the more connections it opened, the fewer it accepts), while the connections it opens are not limited. The "count together" of the release notes probably describes only how connections are counted when one is accepted. 5.1.0 does not count outgoing connections, also when it accepts one.
- By the same count, a hub on 5.2.0 that has opened six or more connections itself probably accepts no further connections (not checked directly).

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [System Parameters Reference](../system-reference.md#system-parameters-reference).

### At-capacity actions 1 and 2 admit extra clients but keep replacing connections

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each, checked every 5 seconds for 150 seconds and, for the values 1 and 2, every second for 90 seconds. Later, with the clients listening on `127.0.0.1` only: checked every 5 seconds, three runs on 5.1.0 and one on 5.2.0; checked every second, three runs each. A reproduction with both client setups, checked every 5 seconds: three runs each on 5.1.0 and one each on 5.2.0. In a full run of all checks, with the clients listening on `127.0.0.1` only: one run each on 5.1.0 and 5.2.0, both ways of checking |
| Setup | A hub with the default limit of 6, and a seventh client that arrived when six were connected. The hub set `MESH_CHOOSER_AT_CAPACITY_ACTION` to 0, 1, or 2 and wrote a document at each check. At each check, every 5 seconds or every second, we recorded which clients had the hub among their remote peers, and at the end, which of the documents each client had received. A connection change is a check at which that set of clients differed from the previous check |
| Documentation | The 5.2.0 release notes say that with `DropOldest` or `DropNewest`, the hub waits until the new peer has finished connecting before it drops an existing peer |

- The value is an integer: strings such as `'DropOldest'` were rejected with a type error. The values 0 to 3 were accepted, and the default is 0. We did not confirm from the documentation which of 1 and 2 is `DropOldest` and which `DropNewest`.
- With 0 (the default), the seventh client never connected in 150 seconds and received nothing, on both releases.
- With 1 or 2 on 5.2.0, the seventh client started to receive data within 1 second, and all seven clients received all 90 documents. But the hub kept replacing connections in a cycle of 5 seconds, and at every check, at least one of the seven clients was not connected:
  - With 1, clients 5, 6, and 7 were dropped in turn, one second apart, and client 7 then stayed out for about 3 seconds.
  - With 2, client 6 was out for about 2 seconds and client 7 for about 3, alternately.
  - Clients 1 to 4 were not part of the cycle. With 1, in each of the three later runs, one or two of them were missing at one check, at about 26 seconds.

| Value (5.2.0) | Clients that were dropped | Connection changes in 90 seconds | Share of the checks at which each was connected |
|---|---|---|---|
| 1 | The three newest (clients 5 to 7), in turn | 52 to 53 | 0.79 to 0.8, 0.79 to 0.8, and 0.41 to 0.42 |
| 2 | The two newest (clients 6 and 7), alternately | 36 to 37 | 0.59, and 0.4 to 0.41 |

- On 5.1.0 with 2, clients 6 and 7 were dropped alternately, as on 5.2.0, in every run (36 or 37 changes in 90 seconds).
- On 5.1.0 with 1, the cycle sometimes stopped, and all seven clients then stayed connected (5.1.0 sometimes accepted more connections than the limit; see [SDK 5.2.0 counts outgoing connections toward the TCP limit](#sdk-520-counts-outgoing-connections-toward-the-tcp-limit)):
  - With the clients listening on all interfaces (as a device that only sets `connect.tcpServers` does; see [A device that only connects over TCP also listens for TCP connections](#a-device-that-only-connects-over-tcp-also-listens-for-tcp-connections)): in the first run, after about 25 seconds. In the reproduction, two of three runs stopped after about 30 seconds, and the hub then had 7 TCP connections, all accepted.
  - With the clients listening on `127.0.0.1` only, checked every 5 seconds: the cycle never stopped in 150 seconds in the three runs, nor in the three runs of the reproduction, where the hub had 6 TCP connections at the end. Checked every second: two of three runs stopped after 6 and 11 seconds. In the third, the cycle was still going at 48 seconds, the last of the first 30 changes, which are all that the run kept. In the full run of all checks, the cycle stopped after 10 seconds when checked every 5 seconds, and all seven clients were connected at every check when checked every second.
  - We do not know what decides whether the cycle stops: with either listener, it stopped in some runs and not in others. On 5.1.0, the result depends on the run.
- Each reconnection also costs a few KiB of handshake traffic (see [Only the current state syncs after offline edits](subscriptions-and-replication.md#only-the-current-state-syncs-after-offline-edits)).

**Not tested:** the value 3; the documented meaning of each value.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [Test Environment](how-we-tested.md#test-environment).

## Meshes and WebSocket Hubs

### On SDK 5.2.0, devices in a full TCP mesh of seven or more keep 3 to 7 direct connections

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each |
| Setup | 4, 7, 8, or 10 devices in one process, each listening on its own port and listing every other device in `connect.tcpServers` (N − 1 requested connections per device). After 10 seconds, we counted each device's direct connections (`presence.graph.localPeer.connections`) and TCP connections (`system:transport_connections`), and then watched them every second for 20 seconds. Finally, we measured how long changes written on the two devices at the ends of the list took to reach every device |

Direct connections per device (TCP connections in parentheses):

| Devices | 5.1.0 | 5.2.0 |
|---|---|---|
| 4 | 3 (6) | 3 (6) |
| 7 | 6 (12) | 4 to 6 |
| 8 | 6 to 7 (9 to 13) | 3 to 7 |
| 10 | 6 to 9 (8 to 15) | 4 to 7 |

- With 4 devices, every pair was directly connected on both releases. Each device had 6 TCP connections: two remained for each pair, the same duplicates as in [The presence graph includes indirect peers and all of their connections](#the-presence-graph-includes-indirect-peers-and-all-of-their-connections).
- On 5.1.0, devices went beyond the limit of 6 to an almost full mesh: the limit applies only to accepted connections (see [SDK 5.2.0 counts outgoing connections toward the TCP limit](#sdk-520-counts-outgoing-connections-toward-the-tcp-limit)).
- On 5.2.0, with 7 or more devices, some pairs were not directly connected. Devices had 6 to 9 TCP connections, at times slightly more than 6. In the hub test of [SDK 5.2.0 counts outgoing connections toward the TCP limit](#sdk-520-counts-outgoing-connections-toward-the-tcp-limit), accepted and outgoing connections added up to exactly 6, but in a full mesh, 7 to 9 remained for 30 seconds, and were not dropped when watched for 150 seconds. We think this is because the limit applies only to the connections that a device accepts, not to those it opens ([Outgoing TCP connections are not limited](#outgoing-tcp-connections-are-not-limited)).
- In every case, every device had all the others in `remotePeers`, and changes reached every device in 24 to 80 ms (once 630 ms, with 10 devices on 5.2.0). Pairs that are not directly connected receive changes through other devices.
- Direct connections changed during the 20 seconds only in one run with 10 devices on 5.1.0 (12 changes in total). Otherwise they did not change.
- In a full mesh, a new document arrives from nearly every directly connected neighbor: with six devices all connected to each other, each device received the same document about 3 to 5 times, and the mesh carried about 3.5 to 5 times the bytes of a hub layout (see [In a full mesh, a new document arrives from nearly every neighbor](subscriptions-and-replication.md#in-a-full-mesh-a-new-document-arrives-from-nearly-every-neighbor)). Keeping about six connections per device on 5.2.0 also caps this duplication.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

### WebSocket connections to a Small Peer hub do not count toward the TCP limit

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result |
| Setup | A Small Peer hub (not Ditto Server) that enabled `websocketSync` on its `listen.http` listener on `127.0.0.1`, and clients that connected only through `connect.websocketURLs`, over `ws://` without TLS. All devices ran in one process. For comparison, 10 clients connected to the same hub over TCP only. In a third case, the hub lowered `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` to 2 before `sync.start()`, and 3 TCP clients and 8 WebSocket clients connected to it |

- 10 clients over TCP only: six synced, as in [A device accepts six TCP connections by default](#a-device-accepts-six-tcp-connections-by-default), and the hub had 6 direct connections.
- 10 and 30 clients over WebSocket only: every client received the hub's documents, and the hub received every client's documents. The hub had 10 and 30 direct connections, and presence showed `WebSocket` as the only connection type.
- Limit lowered to 2, with 3 TCP and 8 WebSocket clients: two TCP clients synced, and the third did not appear in the hub's presence. All eight WebSocket clients synced; the hub had 2 TCP and 8 WebSocket connections. The limit applies only to TCP, and WebSocket connections are not counted: many WebSocket connections did not take TCP slots.
- 20 WebSocket clients stayed connected for 150 seconds (longer than `mesh_chooser_churn_interval_ms`, 120,000 in `SHOW ALL`), while the hub wrote one document every 5 seconds: at all 30 writes, the hub had 20 direct connections, and each document reached all 20 clients within 1 second. Connections were not replaced over and over, as they were over TCP beyond the limit ([At-capacity actions 1 and 2 admit extra clients but keep replacing connections](#at-capacity-actions-1-and-2-admit-extra-clients-but-keep-replacing-connections)).
- `SHOW ALL` has no parameter for the number of accepted WebSocket connections (checked on 5.0.3 and 5.2.0). The parameters with `websocket` in their names are `transport_websocket_connect_timeout` (20), `transports_websocket_watchdog_interval_secs` (600), `transports_websocket_include_jwt_in_header`, and, on 5.2.0 only, `transports_websocket_so_keepalive_*` (idle 30 seconds, interval 10 seconds, count 3); none of them is a number of devices. Another count parameter is `mesh_chooser_max_wlan_clients` (4); we did not check what it counts.
- A WebSocket connection that stalls without closing is dropped after about 15 seconds, later than a TCP connection (about 7 seconds); see [Each device sends over one of two connections and waits when it stalls](#each-device-sends-over-one-of-two-connections-and-waits-when-it-stalls).

**Not tested:** more than 30 clients, and whether there is a limit at all; the hub's CPU, memory, and traffic; TLS (`wss://`); clients in separate processes or on other machines; meshes that also include Bluetooth LE or AWDL devices; a mobile device as the hub.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

## Changing and Retrying Connections

### TCP targets and listeners change while sync runs

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each; both releases gave the same results |
| Setup | While sync was running, we changed a client's `connect.tcpServers` and a hub's TCP listener with `updateTransportConfig()`, and measured when the connection was made or dropped |

- A device that had started sync with a target where nothing listened connected 52 ms after it received the correct target.
- Clearing the targets disconnected it within 0 to 52 ms; restoring them reconnected it in 105 to 157 ms.
- When the hub stopped listening, the client disconnected after 52 ms. When the hub listened again, the client reconnected after about 5 seconds, the default `connect.retryInterval` in JavaScript.
- In contrast, raising the connection limit (`MESH_CHOOSER_MAX_WLAN_CONNECTIONS`) after sync had started had no effect ([Raising the TCP limit takes effect only before sync starts](#raising-the-tcp-limit-takes-effect-only-before-sync-starts)).

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

### A lost TCP connection is retried at the retry interval

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each with three restarts per run (six attempts per release); both releases gave the same results. Longer outages: SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | The hub closed and opened again on the same port 1 second later, three times per run, with the clients' `connect.retryInterval` at the default of 5,000 ms and at 1,000 ms. For longer outages, the hub opened again 3, 30, and 70 seconds after it closed, with the default retry interval |

- Clients removed the hub from presence as soon as it closed.
- From the hub opening again until the client reconnected: 3.95 to 4.06 seconds with a `retryInterval` of 5,000 ms, and 1.09 to 1.15 seconds with 1,000 ms. In one attempt, which coincided with a retry, the client reconnected after 52 ms.
- After a failed connection, a device waits `retryInterval` before it tries again. This matches how often the connection request handler runs for a denied peer ([A denied peer retries at the retry interval](#a-denied-peer-retries-at-the-retry-interval)).
- A long outage did not slow reconnection down: with the hub reopened 3, 30, or 70 seconds after it closed, clients with the default `retryInterval` reconnected in 0.3 to 2.0 seconds, on all three releases.
- `SHOW ALL` lists `transports_connection_failure_threshold` (3), `transports_connection_failure_window_secs` (60), and `mesh_chooser_peer_block_time_ms` (1,800,000). Still, a peer listed in `connect.tcpServers` that could not be reached for 70 seconds (14 retries) was not blocked for 30 minutes.

**Not tested:** what these three parameters apply to (for example, whether they apply to peers found over Bluetooth LE or LAN); the default `retryInterval` of the SDKs other than JavaScript.

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

### A device that only connects over TCP also listens for TCP connections

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each, with the JavaScript SDK on macOS; both releases gave the same results. Whether each combination of settings listens: one run each. Connecting through the machine's LAN address: two runs on 5.2.0 and one on 5.1.0 |
| Setup | A device with the peer-to-peer transports disabled, `listen.tcp` not enabled, and only `connect.tcpServers` set. We read the listening address from its log and let a third device connect to that port. We repeated the check with other combinations of transport settings |

- At startup, the device logged `TCP server listening listen_addr=[::]:<free port>` and accepted TCP connections on all interfaces. A third device that connected to that port synced, and the hub's data reached it through this device.
- With the default settings, in which the peer-to-peer transports are enabled, the device also listens on `[::]`. A device with the peer-to-peer transports disabled and nothing to connect to does not listen, and neither does a device that connects only over WebSocket.
- Besides the `[::]` in the log, a connection from the LAN side worked: connecting to that port through this Mac's LAN address (a connection within the same machine, which did not leave it) succeeded. With `listen.tcp` enabled on `127.0.0.1`, the same connection failed with `ECONNREFUSED`.
- Setting only `listen.tcp.interfaceIP = '127.0.0.1'` changes nothing: it is ignored unless `listen.tcp` is enabled. With `listen.tcp.isEnabled = true`, `interfaceIP = '127.0.0.1'`, and `port = 0`, the device listened only on `127.0.0.1:<free port>`, and other devices could not connect to it.
- With the clients listening on `127.0.0.1`, the hub did not log failed attempts to connect to them (one run on 5.2.0: a hub and two clients for 60 seconds at the Info level, with no `failed to connect` line and no `WARN` line).

**Not tested:** mobile devices and Flutter; whether the connections that this listener accepts count toward the TCP limit (probably they do, as described in [Outgoing TCP connections are not limited](#outgoing-tcp-connections-are-not-limited)).

**Used in:** [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration), [Security Checklist](../../best-practices/security.md#security-checklist), [Several peers in one test process](../../best-practices/testing.md#several-peers-in-one-test-process), [Test Environment](how-we-tested.md#test-environment).

### A second hub listened on a port already in use without an error

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each, on macOS; every run gave the same result, with the peers in one process and in separate processes |
| Setup | A hub and a client of group A opened, and then a hub and a client of group B opened on the same port. Group B had the same Database ID as group A in one case and a different one in the other. With separate processes, we also tried a port that a program other than Ditto was using |

- B's hub listened on the same port as A's hub without an error; the log showed the usual `TCP server listening`. Devices of either group that opened afterwards connected to B's hub. On this Mac, the hub that started listening last receives new connections.
- With the same Database ID:
  - when A's client reconnected with `sync.stop()` and `start()` (as the `whileDisconnected` helper in [Several peers in one test process](../../best-practices/testing.md#several-peers-in-one-test-process) does), it connected to B's hub. It brought A's document (`fromA`) to B's hub and received B's documents. No device was connected to A's hub any longer
  - when B's hub closed, B's client connected to A's hub, and B's documents reached A's hub
- With different Database IDs:
  - A's client, after it reconnected, did not connect to B's hub (`remotePeers` stayed empty), and did not return to A's hub either. The documents did not mix. A device of group A that opened afterwards did not connect either
  - when B's hub closed, A's client connected to A's hub again
- When a program other than Ditto was using the port, Ditto logged an `ERROR`, `Failed to start TCP server error=bind() failed: Address already in use (os error 48)`, and a retry `WARN`, `Unable to restart TCP server in ideal state`. `Ditto.open` succeeded, and no device connected.

**Not tested:** Linux, where connections to one port may be distributed over several hubs.

**Used in:** [Several peers in one test process](../../best-practices/testing.md#several-peers-in-one-test-process).

## Detecting Lost Connections

### A silent network outage removes a peer after about 7 seconds

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0; both releases gave the same results. Outages of 3, 5, 6.5, and 10 seconds: 6 to 8 runs each over both releases; 12 seconds: two runs on each release; 15 and 40 seconds: one run on each release |
| Setup | A relay between a hub and a client held the bytes in both directions while it kept the connection open, as when Wi-Fi drops or a cable is unplugged beyond a switch. During the outage, the hub updated one document. After the set time, the relay delivered the bytes it had held |

- With outages of 10 seconds or longer, the hub and the client both removed the other from presence after about 7.3 seconds (7,296 to 7,349 ms). A suspended process took about 9.1 seconds ([A suspended device leaves the presence graph after about 9 seconds](#a-suspended-device-leaves-the-presence-graph-after-about-9-seconds)).
- Outages of 3, 5, and 6.5 seconds were not noticed by either side. The write made during the outage arrived about 60 ms after the traffic resumed.
- The relay also holds the bytes of new connections and delivers them later, so the time to reconnect after a long outage (about 55 ms here) is shorter than on a real network, where `connect.retryInterval` probably applies ([A lost TCP connection is retried at the retry interval](#a-lost-tcp-connection-is-retried-at-the-retry-interval)).
- When the same peer is also connected over another connection, a stalled connection took a similar time to be dropped, and until then sync did not move to the other connection: a TCP connection that carried changes after 7.20 to 8.01 seconds, an unused TCP connection after 3.89 to 3.92 seconds, and a WebSocket connection that carried changes after 14.89 to 14.92 seconds (SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; see [Each device sends over one of two connections and waits when it stalls](#each-device-sends-over-one-of-two-connections-and-waits-when-it-stalls)).

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence), [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync), [Monitoring Sync Status](../../best-practices/sync-and-subscriptions.md#monitoring-sync-status).

### A suspended device leaves the presence graph after about 9 seconds

| | |
|---|---|
| Observed on | SDK 5.2.0, three runs; SDK 5.0.3 and 5.1.0, two runs each. The runs differed by at most 0.02 seconds, and the three releases gave the same results |
| Setup | A hub and a device, each in its own process. We suspended the device's process (`SIGSTOP`), resumed it (`SIGCONT`), or killed it (`SIGKILL`), and checked the hub's presence graph every 0.25 seconds |

- Suspending the process leaves its TCP connection open, but nothing responds, close to an app that the operating system suspended or a device that moved out of range. The device disappeared from the hub's presence after 9.09 to 9.11 seconds.
- Documents that the hub wrote while the device was suspended arrived within 0.25 seconds after the process resumed, and the device returned to presence within 0.25 seconds. The checks were 0.25 seconds apart, so both may be shorter.
- Killing the process, whose connection the operating system then closes, removed the device from presence within 0.25 seconds.
- `sync_session_status` stays `Connected` for about 73 seconds after a disconnection ([The sync session status lags about 73 seconds behind a peer that stops sync or closes](subscriptions-and-replication.md#the-sync-session-status-lags-about-73-seconds-behind-a-peer-that-stops-sync-or-closes)), so presence reacts much sooner.

**Not tested:** Bluetooth LE and LAN transports, which may take a different time.

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence), [Monitoring Sync Status](../../best-practices/sync-and-subscriptions.md#monitoring-sync-status).

### Each device sends over one of two connections and waits when it stalls

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; the three releases gave the same results |
| Setup | A hub listened on TCP and over WebSocket (`websocketSync` on a Small Peer's `listen.http`, not Ditto Server), and a client connected to both, each through its own relay. The relays counted the bytes in each direction, which showed the connection that carried each change. Both connections were made from the start, or the WebSocket connection was added after the TCP connection. Then one relay held its traffic or closed, and both devices wrote a small document every 250 ms for 20 seconds |

- Presence showed both connections (`AccessPoint` and `WebSocket`). Still, each change and its response went over one connection only; the other carried 0 bytes. Each device chooses the connection it sends over, and we do not know by what:

| How the connections were made | Runs | Hub sent over | Client sent over |
|---|---|---|---|
| Both from the start | 8 of 9 | WebSocket | WebSocket |
| Both from the start | 1 of 9 (5.1.0) | WebSocket | TCP |
| WebSocket added after TCP | 9 of 9 | WebSocket | TCP |

| Case | Result |
|---|---|
| The WebSocket connection that both directions used stalled (left open) | Documents stopped in both directions: 56 of 80 were delayed by 1 second or more, at most 14.90 to 14.93 seconds. Both devices removed the WebSocket connection from presence after 14.89 to 14.92 seconds. Right after that, the held documents arrived together, and later ones went over TCP. The TCP connection worked the whole time |
| The unused TCP connection stalled | Sync was not delayed (at most 60 ms). The TCP connection was dropped after 3.89 to 3.92 seconds |
| WebSocket added after TCP, and the TCP connection stalled (it carried the client's changes and its responses to the hub's changes) | Both directions stopped until the TCP connection was dropped after 7.20 to 8.01 seconds. Changes from the hub, which went over WebSocket, also waited, up to 6.9 to 7.7 seconds |
| The WebSocket connection in use closed (the relay closed the connection and stopped listening) | Sync moved to TCP at once; documents were not delayed (at most 167 ms) |

- The 7 seconds match the about 7.3 seconds of a single connection ([A silent network outage removes a peer after about 7 seconds](#a-silent-network-outage-removes-a-peer-after-about-7-seconds)). We do not know why the TCP connection in use is dropped later than the unused one (3.9 seconds).
- In every case, no document written during the stall was lost; the documents arrived when the stalled connection was dropped.
- Both connections ran over TCP on `127.0.0.1`, and the relay only held the bytes. What carries over is the shape: sync does not move to another connection until a connection that stalled silently is dropped, and it leaves a closed connection at once.

**Not tested:** Bluetooth LE, AWDL, and LAN transports, which check in other ways whether a connection is alive, so the time until a connection is dropped is probably different; whether the client reconnects over the path that closed (that relay also stopped listening).

**Used in:** [Key Characteristics](../understanding-ditto.md#key-characteristics), [Presence](../../best-practices/setup-and-lifecycle.md#presence), [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

### Slow links keep the connection and the presence entry

| | |
|---|---|
| Observed on | SDK 5.0.3 and 5.1.0, six runs each; SDK 5.2.0, seven runs. The 3 MB attachment and the amount of data queued ahead of a document: three runs on each release (four on 5.2.0). How much loopback TCP holds: seven runs |
| Setup | As in [A large attachment holds up documents on a slow link](attachment-behavior.md#a-large-attachment-holds-up-documents-on-a-slow-link), with a relay that limited each direction to 100 KB/s or 20 KB/s. While the client fetched an attachment from the hub, or ran an initial sync, both devices wrote small documents, and we measured how long each took to arrive. From the fetch's progress (`downloadedBytes` of the `Progress` events), we computed how much of the attachment arrived between the time a document in the same direction was written and the time it arrived, that is, how much data was queued ahead of the document |

Delay of a small document, median / maximum (the three releases gave the same results). Before and after a transfer, the delay was 19 to 60 ms / 25 to 193 ms in both directions.

| Transfer (duration) | Same direction as the transfer (hub to client) | Opposite direction | Data queued ahead of a document, median / maximum |
|---|---|---|---|
| 1 MB attachment at 100 KB/s (10.0 to 10.1 s) | 5.1 to 5.2 s / 9.7 to 9.8 s | 3.3 to 3.4 s / 8.2 to 8.3 s | 0.54 MB / 1.0 MB: the whole attachment was queued ahead of the document |
| 500 KB attachment at 20 KB/s (25.1 to 25.2 s) | 12.8 to 13.0 s / 25.1 s | 12.4 to 12.7 s / 25.0 s | Both directions waited until the end of the transfer |
| 3 MB attachment at 100 KB/s (30.2 s) | 10.9 to 12.3 s / 17.6 to 22.0 s | 3.7 to 5.0 s / 9.0 to 13.0 s | 1.1 to 1.2 MB / 1.7 to 2.2 MB, less than the 3 MB attachment |
| Initial sync of 1,000 documents (about 0.5 MB) at 20 KB/s (26.5 to 26.7 s) | 13.4 to 13.7 s / 26.7 to 26.8 s | 6.8 to 13.4 s / 20.0 to 26.5 s (2 of 19 runs were shorter, about 7 s / 20 s) | |

- With the 3 MB attachment, documents in the same direction did not wait until the end of the transfer. In the opposite direction, the delay was about the same as with the 1 MB attachment: the delay in the opposite direction depends on the link speed, not on the size of the attachment. Its median was 0.37 to 0.65 seconds at 1 MB/s ([A large attachment holds up documents on a slow link](attachment-behavior.md#a-large-attachment-holds-up-documents-on-a-slow-link)) and 3.3 to 5.0 seconds at 100 KB/s; at 20 KB/s, it was about the same as in the same direction, until the end of the transfer. We did not examine the mechanism.
- The initial sync held up the other sync until it finished, as in [A large initial sync holds up the device's other sync](subscriptions-and-replication.md#a-large-initial-sync-holds-up-the-devices-other-sync).
- In short, other documents wait behind the transfer data that is queued toward the other device at that moment, and the delay is close to the queued amount divided by the link speed. Here, 1 to 3 MB was queued (at 100 KB/s, 1.1 to 1.2 MB median and 1.7 to 2.2 MB maximum; at 1 MB/s, 1.3 to 1.8 MB and 2.1 to 3.2 MB), so 1 MB queued on a 20 KB/s link would mean a wait of 50 seconds. When an attachment is smaller than that amount, documents wait until the end of the transfer.
- We think that most of the queued data was in the operating system's socket buffers. On this Mac, loopback TCP held 0.82 to 1.21 MB per connection when the receiver did not read (seven runs), and the relay itself holds at most 64 KiB. We did not check whether the rest is Ditto's own send queue. By median, more data was queued at 1 MB/s than at 100 KB/s (1.3 to 1.8 MB against 1.1 to 1.2 MB), which fits an operating system that grows its buffers. However, the maximum ranges overlap, and at 1 MB/s `Progress` arrived only about every 0.28 MB, so those values are coarse.
- Presence: during the transfers of 10 to 30 seconds, neither device ever removed the other (checked about every 20 ms). The relay carried one TCP connection throughout, with no reconnection. Every fetch completed, in about the size of the attachment divided by the link speed; the bytes through the relay, in both directions and including the small documents, were 1.02 to 1.06 times the attachment.
- A silent outage of about 7.3 seconds removes a peer ([A silent network outage removes a peer after about 7 seconds](#a-silent-network-outage-removes-a-peer-after-about-7-seconds)), but while data keeps flowing, a peer is not removed, even when its documents wait 27 seconds. That presence shows a peer does not mean that its changes arrive promptly.

**Not tested:** Bluetooth LE. The relay used TCP on `127.0.0.1` and limited only the bandwidth, without adding latency. Ditto's Bluetooth LE transport is not TCP and has different buffers, so the queued amount and the wait are probably different; what carries over is that the delay is about the queued amount divided by the link speed.

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence), [Size Guidance](../../best-practices/attachments.md#size-guidance).

## The Presence Graph

### Presence reports a joining peer after about 1.2 seconds

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each. The callbacks with an unchanged graph: one run each (7 devices: 5.2.0 only). The comparison of each callback with the previous one: three runs each; every run gave the same result |
| Setup | We registered a presence observer and recorded when its callback ran, and when it reported a peer that joined or left with `sync.stop()`. Later, 4 and 7 devices were watched for 60 seconds without changes. Finally, each callback was compared with the previous one (the peer keys, device names, metadata, and connection IDs of the local and the remote peers) for a hub registered right after it opened and started sync (watched for 12 seconds), a hub and a client registered 5 seconds after they connected (20 seconds), and a hub whose client was opened 2 seconds after registration (20 seconds) |

- The callback ran right after registration (0 ms). An observer registered right after Ditto opened and started sync was called once more about 1 second later, with an unchanged graph. One registered 5 seconds after a client had connected was not; its next callback came after about 10.7 seconds, with the callbacks every 15 seconds described below.
- Callbacks were never less than 1 second apart: at least 1,001 ms in every run. When a client was opened 2 seconds after registration, the callback ran about 0.2 seconds after we started to open it, with an unchanged graph, and the join was reported with the next callback, 1.0 second later.
- A joining peer was reported after 1.16 to 1.19 seconds in all three runs. A peer that left: after about 1.0 second in all three runs on 5.1.0; after 1 ms, 1 ms, and 1.0 second on 5.2.0.
- Even when nothing changes, the observer is called about every 15 seconds. With 4 and 7 devices watched for 60 seconds, after the callback right after registration, it was called four times, from about 11 seconds on, 15.0 seconds apart (the same on 5.1.0 and 5.2.0; 7 devices on 5.2.0 only). Each graph was identical to the previous one: the peer keys, connections, metadata, and `deviceName`.
- The same runs also checked two behaviors outside presence; see [The JavaScript Differ reports every shifted item as a move](javascript-sdk.md#the-javascript-differ-reports-every-shifted-item-as-a-move) and [ANY and EVERY over a parameter or literal array return no rows since SDK 5.1.0](dql-behavior.md#any-and-every-over-a-parameter-or-literal-array-return-no-rows-since-sdk-510).

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence).

### The presence graph includes indirect peers and all of their connections

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each; the line and the mesh: one run on 5.1.0 and two on 5.2.0; three hubs with 15 devices: one run each. Both releases gave the same results |
| Setup | (1) Clients joined a TCP hub one at a time up to six, and then a seventh, beyond the hub's limit. (2) Five devices in a line. (3) Two devices that both listened and listed each other in `connect.tcpServers`, and four devices that all did so. (4) Three hubs connected to each other, each with four clients (15 devices) |
| Documentation | The JavaScript type definitions have no TCP value for `connectionType` |

- Hub with up to six clients: every device had all the others in `remotePeers`. The hub was directly connected to all six clients; each client was directly connected to the hub only and reached the others through it. Checking whether one of a peer's `connections` has this device's `peerKey` at one end identified the direct neighbors correctly.
- A remote peer's `connections` lists all of that peer's connections, not only the one to this device. Seen from a client, the hub had 6 connections and each other client 1.
- From opening a new client until it was listed: 0.14 to 0.24 seconds on the hub, and about 0.7 seconds on the other clients (through the hub). In a line of five devices, an end device listed the other end after about 0.9 to 1.0 seconds, including the time to open the five devices.
- A seventh client, beyond the hub's limit, did not appear in the hub's list, and its own `remotePeers` stayed empty. It received no data within 15 seconds. Presence correctly shows that it is not connected.
- TCP connections have the `connectionType` `AccessPoint`.
- Three hubs with four clients each (15 devices): 1.5 to 1.9 seconds after the first hub opened, every device had the other 14 in `remotePeers`. A client's graph contained 15 connections (3 between the hubs and 12 to clients), and each hub's `connections` had 6 entries. An update reached a client of another hub in 22 to 35 ms. Each hub used exactly 6 connections, so on 5.2.0 it cannot accept another client ([SDK 5.2.0 counts outgoing connections toward the TCP limit](#sdk-520-counts-outgoing-connections-toward-the-tcp-limit)).
- Two devices that connect to each other (both listen and list the other in `connect.tcpServers`) had one connection in presence, whose ID is determined by the two devices, but two in `system:transport_connections`, one with `side` `server` and one with `client`. With four devices all connected to each other, presence showed 6 connections, and device 0 had 4 to 5 TCP connections.

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence), [Transport Configuration](../../best-practices/setup-and-lifecycle.md#transport-configuration).

### Presence shows each peer's SDK version

| | |
|---|---|
| Observed on | Three pairs of releases, one run each: 5.0.3 with 5.2.0, 5.1.0 with 5.2.0, and 5.2.0 with 5.1.0 |
| Setup | Two peers on different releases, each in its own process, each with peer metadata set. We read the other peer in each peer's presence graph |

- In every pair, the presence graph showed the other peer's `dittoSdkVersion` (`5.0.3`, `5.1.0`, or `5.2.0`), `os`, and `isCompatible` (`true`), and the peer metadata that the other peer had set arrived.
- During a rollout, `dittoSdkVersion` therefore identifies the devices that still run an older release.

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence), [Mixed Releases](../upgrading.md#mixed-releases).

### Presence and sync work across a chain of 20 devices

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each |
| Setup | Lines of 4, 8, 12, 16, and 20 devices in one process, each connected over TCP only to the device before it. A document's arrival was the time it appeared in each device's store observer. Then a device in the middle stopped sync and started it again |

Values for 5.2.0, with 5.1.0 / 5.0.3 in parentheses ("same" means the same as on 5.2.0):

| Devices (hops) | Until every device listed all the others, from when all were open and had their first connection | From a write on the first device until the document appeared in the last device's observer | Per hop |
|---|---|---|---|
| 4 (3) | 0.31 s (same / 0.33) | 7 to 10 ms (7 to 11 / 19 to 28) | 1.7 to 2.3 ms (same / 5.3 to 8) |
| 8 (7) | 0.33 s (0.33 to 0.41 / 0.35 to 0.37) | 15 to 21 ms (15 to 23 / 40 to 46) | 1.9 to 2.6 ms (1.9 to 2.9 / 5.1 to 6) |
| 12 (11) | 0.33 to 0.44 s (same / 0.38 to 0.46) | 35 to 43 ms (34 to 51 / 60 to 69) | 2.9 to 3.6 ms (2.8 to 4.3 / 5.2 to 5.9) |
| 16 (15) | 0.37 to 0.49 s (0.31 to 0.50 / 0.42 to 0.51) | 74 to 92 ms (72 to 108 / 95 to 108) | 4.8 to 5.9 ms (4.6 to 6.9 / 6.1 to 6.9) |
| 20 (19) | 0.60 to 0.73 s (0.73 to 0.86 / 0.60 to 0.79) | 121 to 160 ms (124 to 175 / 150 to 169) | 6.2 to 8.2 ms (6.3 to 8.9 / 7.6 to 8.5) |

- At every length, both end devices had all the others in `remotePeers` and saw every connection of the line in the graph (one fewer than the devices). Up to 20 devices, we saw no limit on the number of hops.
- On the writing device itself, the document appeared in its observer after 2 to 5 ms (5.0.3: 3 to 10 ms). We think that the time per hop grows with the number of devices because all devices shared the CPU of one process; with six devices, a hop took 3 to 4 ms ([Each relay hop added about 2 to 4 ms](subscriptions-and-replication.md#each-relay-hop-added-about-2-to-4-ms)). On real devices, each hop adds its network round trip.
- When the device in the middle called `sync.stop()`, an end device that was directly connected to it had removed it at the first check, 21 to 23 ms later; the checks were 20 ms apart, so it was removed within 20 ms. Only the last device of the line of four was such a direct neighbor. Devices two or more hops away disappeared from both ends' lists after 0.51 to 0.64 seconds, and each end kept only the devices on its own side. This is faster than the about 9 seconds of a device that stops responding ([A suspended device leaves the presence graph after about 9 seconds](#a-suspended-device-leaves-the-presence-graph-after-about-9-seconds)).
- When the stopped device called `sync.start()`, both ends listed every device again after about 2 seconds in most runs (1.0 to 3.0 seconds; 5.0.3: 1.0 to 5.2 seconds), in steps of about 1 second, probably set by the interval at which reconnection is attempted ([A lost TCP connection is retried at the retry interval](#a-lost-tcp-connection-is-retried-at-the-retry-interval)). The time did not follow the length of the line (on 5.2.0, 3.0 seconds in all three runs with 4 devices, 2.0 seconds with 8 to 16 devices, and 1.0 second with 20 devices), so the number of hops did not cause it. After the return, documents arrived as fast as before the stop.

**Used in:** [Multi-hop relay](../../best-practices/sync-and-subscriptions.md#multi-hop-relay).

### Presence callbacks stay at about one per second while peers come and go

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; the three releases showed the same pattern |
| Setup | A hub, one stable client, and ten clients that came and went, all in one process. After 10 quiet seconds, each of the ten repeatedly stopped sync for 0.5 to 2 seconds and started it for 1 to 3 seconds, for 30 seconds, followed by 10 seconds of recovery. The stable client updated one document every 200 ms, and we measured when each update reached the hub's observer. Devices came and went with `sync.stop()` and `sync.start()` over TCP on `127.0.0.1` |

- The stable client's presence observer was not called at all during the quiet and recovery periods, and about once per second while the others came and went. The ten clients reconnected 94 to 99 times in 30 seconds (each about every 3 seconds; 6 to 7 changes a second, counting both leaving and returning), so one callback covers several changes.
- The stable client's count of `remotePeers`, read every 200 ms while the others came and went: minimum 1 (only the hub; seen at least once in all nine runs; not weighted by time), average 6.6 to 7.0, maximum 11. This is close to the share of the time that the ten were connected (about 60 percent): a connected device is almost always listed. After the recovery period, every device was listed.

Time until the stable client's update reached the hub's observer, on 5.1.0 and 5.2.0 (5.0.3 in parentheses):

| Period | Median | 95th percentile | Maximum |
|---|---|---|---|
| Quiet | 5 ms (8 ms) | 5 ms (9 ms) | |
| While the others came and went | 4 to 5 ms (8 ms) | 7 to 9 ms (21 to 22 ms) | 13 to 53 ms (35 to 45 ms) |

- Other devices that come and go barely delay a stable device's sync.
- A device that called `sync.start()` had the latest value written while it was disconnected after a median of 25 ms (5.0.3: 47 ms), 47 to 96 ms at the 95th percentile (5.0.3: 57 to 120 ms), and at most 113 to 156 ms. In all 94 to 99 reconnections, it caught up before it disconnected again. At the end, every device had the last value.
- The CPU use of the process (12 devices) rose from 61 to 67 percent in the quiet period to 103 to 117 percent while the clients came and went.

**Not tested:** more devices, and whether the callback then stays at one per second; real network outages. When a radio link drops, noticing it takes seconds (about 7 seconds in [A silent network outage removes a peer after about 7 seconds](#a-silent-network-outage-removes-a-peer-after-about-7-seconds)), so devices leave the list later, and the catch-up times above do not apply.

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence), [Starting and Stopping Sync](../../best-practices/setup-and-lifecycle.md#starting-and-stopping-sync).

## Peer Metadata

### Peer metadata is replaced, not merged, and the device name is read when sync starts

| | |
|---|---|
| Observed on | SDK 5.1.0, two runs; SDK 5.2.0, three runs; both releases gave the same results. Changing the device name after sync started: two runs each |
| Setup | Three devices in a line (0–1–2). A device at one end set peer metadata before `sync.start()` and again later, and changed `ditto.deviceName` after sync had started. The other devices observed presence |

- Metadata of 4,096 bytes was accepted; 4,097 bytes failed with `validation/size-limit-exceeded` (`Size limit exceeded: 4097 bytes > 4096 bytes.`).
- Metadata set before `sync.start()` reached the neighbor after about 50 ms, and the device two hops away after about 0.4 seconds. An empty `peerMetadata` before the metadata arrived was not seen with this procedure.
- Setting the metadata again replaces the previous value instead of adding to it: after `{role, lane}`, setting `{role: 'manager'}` removed `lane`. The change took about 0.5 seconds to arrive.
- `deviceName` defaults to the host name on Node.js. Remote peers also carried `os` (`macOS`), `dittoSdkVersion`, and `isCompatible` (`true`).
- Changing `ditto.deviceName` after sync had started raised no error and changed the local value, but the new name did not reach the other peers' presence within 15 seconds. It arrived after `sync.stop()` and `start()`. Peer metadata set again while sync runs does arrive (see above), so the two are handled differently.

**Not tested:** the default `deviceName` in Flutter on mobile devices.

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence).

### Peer metadata changes reach other peers about once per second

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | One device called `setPeerMetadata({n})` 50 times, 20 ms apart (about 1.4 seconds in total), and another device's presence observer recorded the values it received |

- The other device's presence observer received only three values (for example 19, 38, and 50), about 0.52, 1.52, and 2.52 seconds after the first change: exactly one second apart.
- The last value (50) arrived about 1.1 seconds after it was set. The 47 values in between were never visible to the other device.
- Together with [Peer metadata is replaced, not merged, and the device name is read when sync starts](#peer-metadata-is-replaced-not-merged-and-the-device-name-is-read-when-sync-starts), another device sees the value that is current at intervals of about one second.

**Not tested:** whether the sending device batches the changes or the receiving device's presence updates do (`presence_debounce_interval` is 500 ms in `SHOW ALL`).

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence).

### Presence traffic carries each peer's metadata, and idle traffic grows faster than the number of devices

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; SDK 5.0.3, two runs (two more runs did not finish within 900 seconds; see the last item below). The three releases gave the same results |
| Setup | A TCP hub whose limit was raised to 40. Clients were added in steps, to 0, 5, 10, 20, and 30 other devices. One observing device connected to the hub through a relay that counted the bytes. No documents and no subscriptions. Two variants: no metadata, and 3 KB of random text as each device's metadata |

What the observing device received:

| Other devices | Until all were listed | While they joined, no metadata | While they joined, 3 KB each | Idle, received / sent per second |
|---|---|---|---|---|
| 0 | — | 0.8 to 0.9 KiB | 0.8 to 0.9 KiB | 4 B / 4 B |
| 5 (+5) | 0.51 to 0.61 s | 1.7 to 1.9 KiB | 28.8 to 30.2 KiB | 4 B / 4 B |
| 10 (+5) | 0.51 to 0.61 s | 2.2 to 2.4 KiB | 29.2 to 30.1 KiB | 9 to 10 B / 12 to 13 B |
| 20 (+10) | 0.61 to 0.72 s | 3.3 to 3.9 KiB | 58.4 to 59.5 KiB | 45 to 57 B / 33 to 35 B |
| 30 (+10) | 0.61 to 0.82 s | 3.7 to 4.6 KiB | 58.1 to 60.7 KiB | 73 to 107 B / 39 to 58 B |

- For each device with 3 KB of metadata that joined, the observing device received about 5.9 KiB, about twice the metadata. The text was random, so the compression of sync traffic barely reduced it.
- When one device changed its 3 KB of metadata once a second, ten times, the observing device received 57.8 to 59.5 KiB (about 5.9 KiB per change). With metadata of only 16 characters, it received 6.3 to 7.8 KiB (about 0.7 KiB per change, with 30 devices). In both cases, the callback ran 10 times.
- Idle traffic stayed small, about 100 B a second with 30 devices, but it grew faster than the number of devices: about 8 to 11 times from 10 to 30 devices.
- During 20 idle seconds, the presence callback ran once, regardless of the number of devices.
- From these numbers, we estimate that a device that joins 30 devices that each hold 3 KB of metadata receives about 180 KiB, which takes about 9 seconds at the roughly 20 KB/s of Bluetooth LE (a calculation, not a measurement).
- On 5.0.3, after a run with metadata, closing the 32 devices one by one sometimes stopped at a `close()` that never returned: 2 of 4 runs hit the 900-second timeout. In one run that logged every step, the `close()` of device 28, after three devices had closed, had not returned after about 18 minutes, and its directory remained. After runs without metadata, the 32 devices closed in about 1.4 seconds. On 5.1.0 and 5.2.0, this did not happen in any of the six runs.

**Used in:** [Presence](../../best-practices/setup-and-lifecycle.md#presence).

## Accepting Connections and Shared Keys

### A denied peer retries at the retry interval

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; both releases gave the same results |
| Setup | A hub whose connection request handler (`connectionRequestHandler`) returned `deny`, was set back to `null`, or threw, and a client that connected to it. In another case, the device that opened the connection returned `deny` |

- When the hub returned `deny`, the client did not connect. The hub's handler ran 0.15, 5.26, and 10.37 seconds after the client opened (the same in all three runs whose times were recorded). In JavaScript, `connect.retryInterval` defaults to 5,000 ms on 5.0.3, 5.1.0, and 5.2.0, and it sets the interval of the retries.
- Setting the handler back to `null` let the client connect, and switching it to `deny` again kept the existing connection.
- `deny` returned by the device that opened the connection also prevented the connection; the handler ran twice in 8 seconds.
- With a handler that throws, the client had not connected after 15 seconds.

**Not tested:** how long it takes until a handler that throws denies the connection.

**Used in:** [Controlling Incoming Connections](../../best-practices/security.md#controlling-incoming-connections).

### Shared keys must match, and traffic is TLS-wrapped without a key

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each; both releases gave the same results |
| Setup | Two devices in small-peers-only mode, with combinations of `privateKey` values. A TCP relay between them recorded the bytes, which we searched for a marker string written to a document |

- Devices with the same key, and devices without a key, connected and synced. A different key on each device, a key on the hub only, and a key on the client only: none of these three connected within 10 seconds.
- With and without a key, the traffic began with a TLS handshake (`16 03 01 00 fa 01`), and the marker string did not appear in the captured bytes (about 6.4 KB). Without a key, the traffic is TLS-wrapped, but no shared secret authenticates the peers: any two devices without a key connected.
- `privateKey` accepts a P-256 key with a named curve, as PKCS#8 DER encoded in base64 on one line (`openssl ecparam -name prime256v1 -genkey -noout | openssl pkcs8 -topk8 -nocrypt -outform DER | base64`). With a PEM file, `Ditto.open()` failed with `Invalid symbol 45, offset 0`. With a key that has explicit curve parameters (what `openssl genpkey` produces by default with LibreSSL on macOS) or a key in SEC1 DER, it failed with `Invalid Private Key`.

**Used in:** [Small-Peers-Only Deployments](../../best-practices/security.md#small-peers-only-deployments), [DittoConfig](../../best-practices/setup-and-lifecycle.md#dittoconfig).
