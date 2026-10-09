# Ditto Transports and Presence Reference

Transport configuration, TCP hubs, known peers, transport diagnostics, multicast, and presence for Ditto SDK 5.1.0 (Flutter). Copied from `§ Transport Configuration` and `§ Presence` in `../guide/reference/ditto.md`.

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

> **Note (SDK 5.1.0):** A device accepts a limited number of connections per transport. For TCP, the limit is 6 by default (system parameter `MESH_CHOOSER_MAX_WLAN_CONNECTIONS`). In our testing with a TCP hub and eight clients, the hub accepted six, and the remaining two received no data at all. No API reported this; only the log showed a `WARN` line, `failed to connect to peer error=... at capacity for this transport`. Rejected devices retry with an increasing backoff. The parameter is not part of the documented configuration, so its name and default may change in a later release; confirm the setting with Ditto support before you rely on it in production.
>
> If more than six devices connect to one hub, raise the limit **on the hub** after `Ditto.open` and **before** `ditto.sync.start()`. In our testing, raising it after sync had started did not admit the rejected clients, even after 60 seconds.

```dart
// ✅ GOOD: A hub that serves up to 12 TCP clients. Apply on every open,
// before ditto.sync.start() (system parameters are not persisted).
Future<void> startHub(Ditto ditto) async {
  await ditto.store.execute(
    'ALTER SYSTEM SET MESH_CHOOSER_MAX_WLAN_CONNECTIONS = 12',
  );
  ditto.updateTransportConfig((config) {
    config.listen.tcp
      ..isEnabled = true
      ..interfaceIP = '[::]'
      ..port = 4040;
  });
  ditto.sync.start();
}
```

## Invalid values and known peers

Configuration changes are applied asynchronously while sync is running, and invalid values do not throw: an invalid `connect.tcpServers` entry or listen address only produces a log line (for example `Failed to start TCP server error=Bind address could not be parsed`). You can also point devices at a known peer with the `TRANSPORTS_DISCOVERED_PEERS` system parameter, which can be set before or after `ditto.sync.start()` and is validated (`type` is optional and must be `'force'` or `'candidate'`). It works only while the LAN transport (`peerToPeer.lan`) is enabled on the device that sets it, which is the default; with peer-to-peer transports disabled, the value is stored but nothing connects, so use `connect.tcpServers` instead. Like every system parameter, it is not persisted, so apply it again after each open:

```dart
Future<void> connectToKnownPeer(Ditto ditto) async {
  await ditto.store.execute(
    "ALTER SYSTEM SET TRANSPORTS_DISCOVERED_PEERS = [{'address': 'tcp://192.168.1.10:4040', 'type': 'force'}]",
  );
}
```

## WebSocket sync between Small Peers

WebSocket sync between Small Peers (accepting WebSocket connections on the HTTP listener) is **off by default** (`listen.http.websocketSync = false`). Enable it only when you need it and configure TLS (`tlsKeyPath` and `tlsCertificatePath`); without them the listener uses plain HTTP.

## Diagnosing transport problems (SDK 5.1+)

Because configuration changes do not throw, `ditto.observeTransportConditions()` is the way to see why a transport is not working: missing Bluetooth permissions, Bluetooth or Wi-Fi turned off, no BLE hardware, the app being in the background, mDNS or TCP listen failures, and so on. Call `stop()` on the returned observer when you no longer need it.

On Android, `DittoSyncPermissions` reports which runtime permissions Ditto needs and which are missing. It returns empty lists on other platforms. Request the permissions with a package such as `permission_handler`.

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

Multicast is an opt-in transport that sends each update once to a multicast group instead of once per connection, which reduces connection overhead in dense deployments. It is a private beta feature: **use it only in coordination with Ditto support**. It is configured through `peerToPeer.multicastBeta` and requires additional platform entitlements and permissions (for example the multicast entitlement on iOS and `CHANGE_WIFI_MULTICAST_STATE` on Android). It is not available on the Web or on Windows, and changes made while sync is active take effect only after sync is stopped and started again.

`§ Multicast (Beta) (SDK 5.1+)`

## Presence

`ditto.presence` shows which peers this device can see and how it is connected to them, which is useful for connection indicators and diagnostics.

- `ditto.presence.observe((graph) { ... })` returns a `PresenceObserver`. The callback is called with the current graph shortly after `observe()` returns (asynchronously), and again whenever peers appear, disappear, or change their connections. Updates are batched: in our testing, a change reached the callback after about 0.5–1 second, and one callback can cover several changes. Call `stop()` on the observer when you no longer need it.
- `graph.localPeer` describes this device, and `graph.remotePeers` is a `Set<Peer>` of the other known peers, including peers that are reachable only through other peers. Each `Peer` has `peerKey`, `deviceName`, `isConnectedToDittoServer`, `connections`, and `peerMetadata`. To tell direct neighbors apart, check whether one of a peer's `connections` has this device's `peerKey` as `peer1` or `peer2`.
- `ditto.presence.graph` returns the current graph once, without observing.
- `ditto.presence.peerMetadata` sets metadata for this device (a JSON object of at most 4096 bytes when encoded; larger values throw). It reaches every peer in the mesh, but a peer that has just appeared can show empty `peerMetadata` until its metadata arrives.

**✅ DO:**
- Stop presence observers when the screen or feature that uses them goes away.
- Keep peer metadata small and non-sensitive, such as a role or a display name.
- Set peer metadata once at startup (for example `ditto.presence.peerMetadata = {'role': 'cashier'};`), not from individual screens.

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

  @override
  void initState() {
    super.initState();
    _presence = widget.ditto.presence.observe((graph) {
      if (!mounted) return;
      setState(() => _peers = graph.remotePeers.toList());
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
              subtitle: Text(peer.isConnectedToDittoServer
                  ? 'Connected to Ditto Server'
                  : '${peer.connections.length} connections'),
            ),
        ],
      );
}
```

The connection request handler (`ditto.presence.connectionRequestHandler`) is covered in [security.md](security.md#controlling-incoming-connections).

`§ Presence`
