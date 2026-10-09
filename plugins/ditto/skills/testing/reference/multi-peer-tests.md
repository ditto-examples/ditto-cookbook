# Multi-Peer Sync Tests

Testing concurrent edits, merges, deletion propagation, relay, and attachments across peers, from `§ Testing on Multiple Devices` and `§ Several peers in one test process`. The test file was verified with `ditto_live` 5.1.0.

## Contents

- [Requirements](#requirements)
- [How the helpers work](#how-the-helpers-work)
- [Test file with the helpers](#test-file-with-the-helpers)
- [What this setup does not cover](#what-this-setup-does-not-cover)
- [Scenarios worth covering](#scenarios-worth-covering)

## Requirements

Concurrent edits, merges, deletion propagation, multi-hop relay, and attachment fetching across peers can only be tested with sync running between real Ditto instances. Most of these tests do not need several physical devices: several instances in one test process can sync with each other over TCP on localhost.

- **Small-peers-only sync** requires an **offline license token** from Ditto: `ditto.sync.start()` throws until `ditto.setOfflineOnlyLicenseToken(token)` has been called with a valid token (`§ Initializing Ditto`). Without a token, tests are limited to a single local store. Keep the token out of source control; pass it to tests from a CI secret.
- **Sync through Ditto Server** requires a Ditto Server database for testing. Use separate databases (apps) for development, staging, and production, or one database per developer; developers who share a database can prefix collection names to isolate their test data. There is no Ditto Server mock for CI, so run these tests against a test database.
- **Offline scenarios:** To simulate a Ditto Server outage while keeping peer-to-peer sync, let the app authenticate first and then block the Ditto Server host at the network level; blocking it before authentication makes sync fail entirely.

## How the helpers work

The helpers below open several small peers in one `integration_test` process and connect them over TCP on `127.0.0.1` only:
- Each peer has its own persistence directory, and all peers share one Database ID.
- Peer-to-peer transports are disabled, so a test never connects to devices nearby.
- `whileDisconnected` stops sync on every peer, runs the writes, and reconnects the peers. Writes made inside it are concurrent, like edits on devices that are offline at the same time. Writes made while the peers are connected reach the other peers within milliseconds and do not test a merge.
- `waitForConvergence` waits, with a timeout, until every peer returns the same rows.

Run the file with `flutter test integration_test/multipeer_test.dart -d macos --dart-define-from-file=license.json`, where `license.json` (not committed) contains `{"DITTO_LICENSE_TOKEN": "..."}`. Without the token, the test is skipped (`skip: 'Needs DITTO_LICENSE_TOKEN'`).

## Test file with the helpers

```dart
// integration_test/multipeer_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Offline license token, passed with --dart-define (never commit it).
const licenseToken = String.fromEnvironment('DITTO_LICENSE_TOKEN');

/// Opens [count] peers in this process that sync with each other over TCP on
/// localhost only: peer 0 listens, the others connect to it. A device accepts
/// at most 6 TCP connections by default, so keep [count] at 7 or below.
Future<List<Ditto>> openSyncedPeers(
  int count, {
  int port = 4041,
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final peers = <Ditto>[];
  for (var i = 0; i < count; i++) {
    final directory = await Directory.systemTemp.createTemp('ditto_peer${i}_');
    final ditto = await Ditto.open(
      DittoConfig(
        // All peers must use the same database ID to sync.
        databaseID: '00000000-0000-4000-8000-000000000002',
        persistenceDirectory: directory.path,
      ),
    );
    addTearDown(() async {
      await ditto.close();
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Best effort.
      }
    });
    ditto.setOfflineOnlyLicenseToken(licenseToken);
    ditto.updateTransportConfig((config) {
      config.setAllPeerToPeerEnabled(false); // no Bluetooth, LAN, or AWDL
      if (i == 0) {
        config.listen.tcp
          ..isEnabled = true
          ..interfaceIP = '127.0.0.1'
          ..port = port;
      } else {
        config.connect.tcpServers = {'127.0.0.1:$port'};
      }
    });
    await configure?.call(ditto); // system parameters, as in the app
    ditto.sync.start();
    peers.add(ditto);
  }
  await _waitUntil(() => peers.every(_isConnected));
  return peers;
}

bool _isConnected(Ditto ditto) => ditto.presence.graph.remotePeers.isNotEmpty;

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Stops sync on every peer, runs [writes] while the peers are disconnected,
/// then reconnects them, so the writes are concurrent.
Future<void> whileDisconnected(
  List<Ditto> peers,
  Future<void> Function() writes,
) async {
  for (final peer in peers) {
    peer.sync.stop();
  }
  await _waitUntil(() => peers.every((peer) => !_isConnected(peer)));
  await writes();
  for (final peer in peers) {
    peer.sync.start();
  }
  await _waitUntil(() => peers.every(_isConnected));
}

/// Waits until [query] returns the same rows on every peer and [until] holds
/// for them, then returns the rows.
Future<List<Map<String, dynamic>>> waitForConvergence(
  List<Ditto> peers,
  String query, {
  Map<String, dynamic> arguments = const {},
  bool Function(List<Map<String, dynamic>> rows)? until,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final results = <List<Map<String, dynamic>>>[];
    for (final peer in peers) {
      final result = await peer.store.execute(query, arguments: arguments);
      results.add(result.items.map((item) => item.value).toList());
    }
    final first = jsonEncode(results.first);
    final same = results.every((rows) => jsonEncode(rows) == first);
    if (same && (until == null || until(results.first))) return results.first;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Peers did not converge: $results', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final skip = licenseToken.isEmpty ? 'Needs DITTO_LICENSE_TOKEN' : null;

  test('concurrent edits of different line items both survive', () async {
    final [tablet, phone] = await openSyncedPeers(2);
    for (final peer in [tablet, phone]) {
      peer.sync.registerSubscription('SELECT * FROM orders');
    }
    await tablet.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': 'order-1',
          'items': {
            'item-1': {'productId': 'p1', 'quantity': 1},
          },
        },
      },
    );
    await waitForConvergence(
      [tablet, phone],
      'SELECT * FROM orders',
      until: (rows) => rows.length == 1,
    );

    // The code under test would be the app's repository functions.
    await whileDisconnected([tablet, phone], () async {
      await tablet.store.execute(
        'UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id',
        arguments: {'id': 'order-1'},
      );
      await phone.store.execute(
        'UPDATE orders SET items.`item-2` = :item WHERE _id = :id',
        arguments: {
          'id': 'order-1',
          'item': {'productId': 'p2', 'quantity': 1},
        },
      );
    });

    final rows = await waitForConvergence(
      [tablet, phone],
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': 'order-1'},
      until: (rows) => (rows.single['items'] as Map).length == 2,
    );
    final items = rows.single['items'] as Map;
    expect(items['item-1']['quantity'], 3);
    expect(items['item-2']['productId'], 'p2');
  }, skip: skip);
}
```

## What this setup does not cover

Keep a few tests on real devices for these:
- All peers share one clock. Clock skew between devices is not simulated.
- Only TCP is exercised. Bluetooth LE, P2P Wi-Fi, LAN discovery, permissions, and app lifecycle need real devices.
- A listening peer accepts at most 6 TCP connections by default (`§ Transport Configuration`). For a relay test, chain the peers: A listens, B listens and connects to A, and C connects to B.

## Scenarios worth covering

With the helpers above, or on real devices:
- Two devices edit **different fields** and the **same field** of one document while offline, then reconnect.
- Two devices add, edit, and remove entries of the same map (and, for comparison, the same array) while offline.
- One device deletes a document while another updates it (expect a husk document, `§ Husk documents`), and the same with a soft delete.
- A counter that one device recounts with `RESTART WITH` while another keeps incrementing it (`§ RESTART`).
- A device behind a relay with narrower subscriptions (`§ Multi-hop relay`).
- Attachments created offline and fetched by other peers later (`§ Availability`).
- Each transport your users rely on, including Bluetooth LE as the only transport (on real devices).

See the [testing guide](https://docs.ditto.live/sdk/latest/deployment/testing) for environment setup and offline simulation.
