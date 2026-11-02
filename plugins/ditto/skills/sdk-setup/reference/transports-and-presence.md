# Ditto Transports and Presence Reference

Transport configuration, TCP hubs, known peers, transport diagnostics, multicast, and presence for Ditto SDK 5.2.0 (Flutter). Copied from `§ Transport Configuration` and `§ Presence` in `../../guide/reference/best-practices/setup-and-lifecycle.md`.

## Contents

- [Defaults and updateTransportConfig](#defaults-and-updatetransportconfig)
- [TCP hub](#tcp-hub)
- [TCP connection limit per hub](#tcp-connection-limit-per-hub)
- [Invalid values and known peers](#invalid-values-and-known-peers)
- [WebSocket sync between Small Peers](#websocket-sync-between-small-peers)
- [Diagnosing transport problems (SDK 5.1+)](#diagnosing-transport-problems-sdk-51)
- [Multicast (Beta) (SDK 5.1+)](#multicast-beta-sdk-51)
- [Presence](#presence)

---

## Defaults and updateTransportConfig

A new Ditto instance enables the peer-to-peer transports that are stable on the current platform (Bluetooth LE, LAN, and AWDL or Wi-Fi Aware). When you connect with `DittoConfigConnectServer`, the Server URL is used automatically; you do not need to add it to the transport configuration.

`TransportConfig` is immutable. Change it with `ditto.updateTransportConfig()`, which gives you a builder initialized with the current configuration.

**✅ DO:**
- Use `updateTransportConfig()` and change only the settings you need.
- Enable or disable all peer-to-peer transports at once with `setAllPeerToPeerEnabled()`, or individual transports through `peerToPeer`.
- Observe transport conditions to detect missing permissions or disabled radios.

**❌ DON'T:**
- Build a `TransportConfig()` from scratch and assign it: a new `TransportConfig` has **every transport disabled**, including the peer-to-peer transports that a default instance enables.
- Treat `global.syncGroup` as a security boundary. It is an optimization only: in our testing, devices in different sync groups still synced when they were connected explicitly (`connect.tcpServers` or `TRANSPORTS_DISCOVERED_PEERS`).

```dart
// ✅ GOOD: Adjust the current configuration with the builder.
void configureTransports(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.setAllPeerToPeerEnabled(true); // BLE, LAN, AWDL / Wi-Fi Aware
    config.peerToPeer.bluetoothLE.isEnabled = false; // for example, LAN and P2P Wi-Fi only
  });
}
```

On Flutter Web, peer-to-peer transports are not available and `setAllPeerToPeerEnabled()` has no effect (see [startup-and-lifecycle.md](startup-and-lifecycle.md#flutter-web-limitations)).

`§ Transport Configuration`

## TCP hub

```dart
// ✅ GOOD: A hub device listens on TCP; other devices connect to it.
void configureHub(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.listen.tcp
      ..isEnabled = true
      ..interfaceIP = '[::]'
      ..port = 4040;
  });
}

void connectToHub(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.connect.tcpServers = {'192.168.1.10:4040'};
    // Additional WebSocket endpoints, if you run your own:
    // config.connect.webSocketUrls = {'wss://sync.example.com'};
  });
}
```

## TCP connection limit per hub

> **Note (SDK 5.1.0 and 5.2.0):** A device accepts a limited number of connections per transport. For TCP, the limit is 6 by default (system parameter `MESH_CHOOSER_MAX_WLAN_CONNECTIONS`). In our testing with a TCP hub and eight clients, the hub accepted six on both releases, and the remaining two received no data at all. No API reported this; only the log showed a `WARN` line, `failed to connect to peer error=... at capacity for this transport`. Rejected devices retry with an increasing backoff.
>
> On 5.2.0, a device also counts the connections that it opened itself when it decides whether to accept another one (the 5.2.0 release notes describe this as counting accepted and outgoing LAN connections together). In our testing, a hub that six clients had connected to and that also connected to two other devices kept all eight in sync on 5.1.0, but dropped two of the clients on 5.2.0, and a relay that connected to an upstream hub accepted only five clients on 5.2.0. Outgoing connections themselves are not limited: one device connected to 16 listening devices on both releases. A hub that only accepts connections still admitted six of eight clients on 5.2.0, and the default is still 6.
>
> A client that the hub did not accept appeared in no device's presence graph, and its own `remotePeers` stayed empty. Configure each TCP link in one direction only (the clients list the hub): two devices that listed each other in `connect.tcpServers` kept two TCP connections in `system:transport_connections`. When every device lists every other device, a device on 5.2.0 kept 3 to 7 direct connections, so a mesh of seven or more devices was not fully connected, but every device still listed all the others in `remotePeers` and received changes within 24 to 80 ms through the others (5.1.0 kept up to 15 TCP connections, many of them duplicates). Count devices with `remotePeers`, not with direct connections.
>
> `MESH_CHOOSER_AT_CAPACITY_ACTION` decides what a full hub does when another client arrives. With the default, the extra client never connected. According to the 5.2.0 release notes, the settings that drop the oldest or the newest peer wait until the new peer has finished connecting. In our testing with those settings, every client received data, but the hub kept replacing connections about every 5 seconds, on 5.1.0 and 5.2.0. Raise `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` instead.
>
> If more than six devices connect to one hub, raise the limit **on the hub** so that it is in effect **before** `ditto.sync.start()`: pass it in `DittoConfig.systemParameters` (SDK 5.2+), or on SDK 5.1 run `ALTER SYSTEM` after `Ditto.open` and before `ditto.sync.start()`. In our testing with SDK 5.1.0 and 5.2.0, a hub whose limit was raised before sync started admitted all eight clients; raising it after sync had started did not admit the rejected clients, even after 60 seconds.

```dart
// ✅ GOOD: A hub that serves up to 12 TCP clients. The limit is part of the
// hub's configuration, so it is applied on every open, before sync starts
// (SDK 5.2+).
DittoConfig hubConfig(DittoConfigConnect connect) => DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: connect,
      systemParameters: const {'MESH_CHOOSER_MAX_WLAN_CONNECTIONS': 12},
    );

// Call with an instance opened from hubConfig(), after the authentication
// handler or the offline license token is set.
void startHub(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.listen.tcp
      ..isEnabled = true
      ..interfaceIP = '[::]'
      ..port = 4040;
  });
  ditto.sync.start();
}
```

> **Note (SDK 5.1.0 and 5.2.0):** A device that only connects over TCP also accepts connections. In our testing with the JavaScript SDK on macOS, a device with the peer-to-peer transports disabled and only `connect.tcpServers` set listened for TCP on all interfaces at a free port, and another device connected to that port through the machine's LAN address and synced. To accept no TCP connections from other devices, enable `listen.tcp` with `interfaceIP` set to `127.0.0.1` (`port` 0 picks a free port); the device then accepted connections only from the same machine. Only devices with the same Database ID and valid credentials can sync, so this matters most for small-peers-only deployments without a shared key and for network reviews.

**Hub load**: the CPU that a hub spends on each change grows with the number of devices connected to it, even when no other device subscribes to the changed document. In our testing on a 14-core Mac with the JavaScript SDK (5.1.0 and 5.2.0), one change cost the hub at most about 6 ms of CPU with one client and about 40 ms with 30 clients. When every client wrote, the hub's CPU grew faster than the number of clients: 30 clients that each wrote 5 times a second used about 2.6 cores. Each connected client also added about 4.5 MiB of memory to the hub on 5.2.0. Before you use a mobile device as a hub, estimate the number of clients and how often they write, and write frequently changing values (positions, sensor readings) less often or in batches.

**Replacing a hub**: a new, empty hub device recovers the data from its clients. In our testing with SDK 5.1.0 and 5.2.0, a new hub held all 950 live documents about 4 seconds after it opened, most of it the clients' retry interval. The 50 deleted documents stayed deleted, also when a device that had been offline since before the deletion came back, because the clients still held the tombstones (until they are reaped; see `§ Tombstone TTL and reaping`). Documents that only the old hub held, in a collection that no client subscribed to, were not recovered. Back up data that only the hub writes, or let a client subscribe to it.

## Invalid values and known peers

Changes of `connect.tcpServers` and of the TCP listener take effect while sync is running, without `sync.stop()` and `start()`: in our testing with SDK 5.1.0 and 5.2.0, a device connected about 50 ms after it received the right address and disconnected when the address was removed, and clients disconnected about 50 ms after the hub stopped listening. System parameters such as `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` are different: raising the limit after sync had started had no effect.

A device that loses a TCP connection, or fails to connect, tries again after `connect.retryInterval` (5 seconds by default). In our testing with SDK 5.1.0 and 5.2.0, clients reconnected to a restarted hub about 4 seconds after it was open again with the default, and about 1.1 seconds with an interval of 1 second. A shorter interval suits devices that must stay connected to a hub, such as the terminals of a store.

Configuration changes are applied asynchronously while sync is running, and invalid values do not throw: an invalid `connect.tcpServers` entry or listen address only produces a log line (for example `Failed to start TCP server error=Bind address could not be parsed`). You can also point devices at a known peer with the `TRANSPORTS_DISCOVERED_PEERS` system parameter, which can be set before or after `ditto.sync.start()` and is validated (`type` is optional and must be `'force'` or `'candidate'`). It works only while the LAN transport (`peerToPeer.lan`) is enabled on the device that sets it, which is the default; with peer-to-peer transports disabled, the value is stored but nothing connects, so use `connect.tcpServers` instead. Like every system parameter, it is not persisted: pass a fixed address in `DittoConfig.systemParameters` (SDK 5.2+), or set it with `ALTER SYSTEM` after each open, for example when the address is discovered at run time:

```dart
Future<void> connectToKnownPeer(Ditto ditto) async {
  await ditto.store.execute(
    "ALTER SYSTEM SET TRANSPORTS_DISCOVERED_PEERS = [{'address': 'tcp://192.168.1.10:4040', 'type': 'force'}]",
  );
}
```

## WebSocket sync between Small Peers

WebSocket sync between Small Peers (accepting WebSocket connections on the HTTP listener) is **off by default** (`listen.http.websocketSync = false`). Enable it only when you need it and configure TLS (`tlsKeyPath` and `tlsCertificatePath`); without them the listener uses plain HTTP.

Connections that a hub accepts over WebSocket do not count toward its TCP limit. In our testing with SDK 5.0.3, 5.1.0, and 5.2.0, a Small Peer hub that accepted WebSocket connections synced with all of 30 clients, while over TCP it served six, and with its TCP limit lowered to 2, it still served 8 WebSocket clients next to 2 TCP clients. This is an alternative to raising `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` for hubs with more clients, with limits of its own: Ditto does not document a limit for WebSocket connections, we tested at most 30 clients on one machine without TLS, and a WebSocket connection that stops responding takes about 15 seconds to be dropped, against about 7 for TCP (`§ Key Characteristics`). Test the number of devices you plan before you rely on it.

## Diagnosing transport problems (SDK 5.1+)

Because configuration changes do not throw, `ditto.observeTransportConditions()` is the way to see why a transport is not working: missing Bluetooth permissions, Bluetooth or Wi-Fi turned off, no BLE hardware, the app being in the background, mDNS or TCP listen failures, and so on. Call `stop()` on the returned observer when you no longer need it.

On Android, `DittoSyncPermissions` reports which runtime permissions Ditto needs and which are missing. It returns empty lists on other platforms. Request the permissions with a package such as `permission_handler`. Since SDK 5.2, `requiredPermissions()` and `missingPermissions()` cover only the generally available transports; the permissions for multicast are returned separately (see [Multicast (Beta) (SDK 5.1+)](#multicast-beta-sdk-51)).

```dart
// ✅ GOOD: Surface transport problems and missing permissions.
Future<TransportConditionsObserver> watchTransports(Ditto ditto) async {
  final missing = await DittoSyncPermissions().missingPermissions();
  if (missing.isNotEmpty) {
    debugPrint('Ditto is missing Android permissions: $missing');
  }

  return ditto.observeTransportConditions((event) {
    if (event.condition != TransportCondition.ok) {
      debugPrint('Transport ${event.source.name}: ${event.condition.name}');
    }
  });
}
```

`§ Diagnosing transport problems (SDK 5.1+)`

## Multicast (Beta) (SDK 5.1+)

Multicast is an opt-in transport that sends each update once to a multicast group instead of once per connection, which reduces connection overhead in dense deployments. It is a private beta feature: **use it only in coordination with Ditto support**. It is configured through `peerToPeer.multicastBeta` and requires additional platform entitlements and permissions (for example the multicast entitlement on iOS and `CHANGE_WIFI_MULTICAST_STATE` on Android). It is not available on the Web or on Windows, and changes made while sync is active take effect only after sync is stopped and started again. On Android with SDK 5.2+, get its permissions with `await DittoSyncPermissions().requiredMulticastPermissions()` and check them with `missingPermissions(multicastPermissions)`; `requiredPermissions()` no longer includes them.

`§ Multicast (Beta) (SDK 5.1+)`

## Presence

`ditto.presence` shows which peers this device can see and how it is connected to them, which is useful for connection indicators and diagnostics.

- `ditto.presence.observe((graph) { ... })` returns a `PresenceObserver`. The callback is called with the current graph shortly after `observe()` returns (asynchronously), and again whenever peers appear, disappear, or change their connections. Updates are batched: in our testing with SDK 5.1.0 and 5.2.0, callbacks arrived at intervals of about 1 second, so a change reached the callback within about 1 second (a joining peer after about 1.2 seconds), and one callback can cover several changes. Peers that keep coming and going do not raise the rate: in our testing with SDK 5.0.3, 5.1.0, and 5.2.0, while ten peers each rejoined about every 3 seconds (about six changes a second), a stable device's callback still ran about once per second, its count of `remotePeers` swung between 1 and 11, and its own updates still reached the hub within a few milliseconds. Show a connection state only after it has held for a few seconds, not the raw count. The callback was also called with an unchanged graph during the first few seconds and then about every 15 seconds, so compare the graph with the previous one before you rebuild the UI. A peer in the graph is not necessarily up to date: over TCP limited to 20 KB/s, a peer transferring a 500 KB attachment stayed in the graph while other changes waited up to 25 s (in testing). Two connections to a peer in the graph do not mean that sync continues when one stalls: each device sends over one connection, and when it stalls without closing, sync waits until it is dropped (about 7 s for TCP and 15 s for WebSocket in testing with SDK 5.1.0 and 5.2.0); a closed connection is replaced at once. Call `stop()` on the observer when you no longer need it.
- `graph.localPeer` describes this device, and `graph.remotePeers` is a `Set<Peer>` of the other known peers, including peers that are reachable only through other peers. Each `Peer` has `peerKey`, `deviceName`, `isConnectedToDittoServer`, `connections`, and `peerMetadata`. To tell direct neighbors apart, check whether one of a peer's `connections` has this device's `peerKey` as `peer1` or `peer2`: a remote peer's `connections` lists all of that peer's connections, not only the one to this device (seen from a client of a TCP hub, the hub had one connection per client). `connectionType` has no TCP value: in our testing with the JavaScript SDK, TCP connections, including those to a hub, were reported as `AccessPoint` (`ConnectionType.accessPoint` in Flutter).
- A peer that stops responding without closing its connection stays in the graph for several seconds. In our testing over TCP with SDK 5.1.0 and 5.2.0, after the network went silent, both sides removed the other after about 7.3 seconds, and a shorter outage (up to 6.5 seconds) was not noticed at all: the writes made during it arrived about 60 ms after the network came back. A suspended process (5.0.3 to 5.2.0) disappeared after about 9.1 seconds, and a process that ended, whose connection the operating system closes, within 0.25 seconds. Other transports, such as Bluetooth LE, may take a different time; expect a connection indicator to lag by this much.
- `ditto.presence.graph` returns the current graph once, without observing.
- `ditto.presence.peerMetadata` sets metadata for this device (a JSON object of at most 4096 bytes when encoded; larger values throw). It reaches every peer in the mesh, but a peer that has just appeared can show empty `peerMetadata` until its metadata arrives. Setting it again replaces the whole object; keys are not merged. Changes reach other peers about once per second, as the value current at that moment: in our testing with SDK 5.1.0 and 5.2.0, 50 changes made 20 ms apart reached the other peer as three values, one second apart, and the last one arrived about 1.1 seconds after it was set.
- `ditto.deviceName` is the name that other peers see as `Peer.deviceName`. According to the API reference, it defaults to the host name. Set it before `ditto.sync.start()`: in our testing with SDK 5.1.0 and 5.2.0, a change made while sync was running did not reach other peers until sync was stopped and started again. Other peers also see each peer's `os` and `dittoSdkVersion`, which helps to find devices that run an older SDK.

**✅ DO:**
- Stop presence observers when the screen or feature that uses them goes away.
- Keep peer metadata small and non-sensitive, such as a role or a display name. Every connected device receives about twice its size whenever a device joins or changes it: in our testing over TCP, 3 KB of metadata cost each device about 6 KiB per change, so a device joining 30 others that each had 3 KB received about 180 KiB, about 9 seconds over Bluetooth LE. Write large or frequently changing values (positions, task state) to documents instead.
- Set peer metadata once at startup (for example `ditto.presence.peerMetadata = {'role': 'cashier'};`), not from individual screens. Other peers see at most about one change per second.
- Set `ditto.deviceName` to a name that identifies the device for your support staff and not a person, before you start sync.

**❌ DON'T:**
- Put secrets, tokens, or personal data in peer metadata. Peer metadata, and the `identityServiceMetadata` returned by your authentication webhook, are shared with every peer in the mesh, not only with directly connected peers.

```dart
// ✅ GOOD: Show connected peers and stop the observer when done.
class PeerList extends StatefulWidget {
  const PeerList({super.key, required this.ditto});
  final Ditto ditto;

  @override
  State<PeerList> createState() => _PeerListState();
}

class _PeerListState extends State<PeerList> {
  late final PresenceObserver _presence;
  List<Peer> _peers = const [];
  String _localPeerKey = '';

  @override
  void initState() {
    super.initState();
    _presence = widget.ditto.presence.observe((graph) {
      if (!mounted) return;
      setState(() {
        _localPeerKey = graph.localPeer.peerKey;
        _peers = graph.remotePeers.toList();
      });
    });
  }

  @override
  void dispose() {
    _presence.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          for (final peer in _peers)
            ListTile(
              title: Text(peer.deviceName),
              subtitle: Text(_route(peer)),
            ),
        ],
      );

  // A peer's connections include its links to other peers, so only the
  // connections that have this device at one end make it a direct neighbor.
  String _route(Peer peer) {
    final directTypes = {
      for (final connection in peer.connections)
        if (connection.peer1 == _localPeerKey ||
            connection.peer2 == _localPeerKey)
          connection.connectionType.name,
    };
    final route = directTypes.isEmpty
        ? 'Through other peers'
        : 'Direct (${directTypes.join(', ')})';
    return peer.isConnectedToDittoServer
        ? '$route, connected to Ditto Server'
        : route;
  }
}
```

The connection request handler (`ditto.presence.connectionRequestHandler`) is covered in [security.md](security.md#controlling-incoming-connections).

`§ Presence`
