// Ditto SDK: 5.2.0 (Flutter package ditto_live), verified with ditto_live 5.2.0
//
// Several peers in one test process over TCP on 127.0.0.1, and a concurrent-edit test. Run with: flutter test integration_test/multipeer_test.dart -d macos --dart-define-from-file=license.json (license.json is not committed)
//
// What each test checks, as DQL and expected results, is in
// ../../reference/multi-peer-tests.md and in the guide's Testing Strategies; the same
// tests for the other SDKs are in examples/<sdk>/ with the same base name.
//
// Guide: § Several peers in one test process, § Several peers in one test in Flutter

// integration_test/multipeer_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Offline license token, passed with --dart-define (never commit it).
const licenseToken = String.fromEnvironment('DITTO_LICENSE_TOKEN');

/// The peers that the tests of this file opened. They close together after
/// the last test (guide: § A local-store test helper in Flutter).
final _peerStores = <(Ditto, Directory)>[];

/// Opens [count] peers in this process that sync with each other over TCP on
/// localhost only: peer 0 listens, the others connect to it. A device accepts
/// at most 6 TCP connections by default, so keep [count] at 7 or below.
Future<List<Ditto>> openSyncedPeers(
  int count, {
  int port = 4041,
  String databaseID = '00000000-0000-4000-8000-000000000002',
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final peers = <Ditto>[];
  for (var i = 0; i < count; i++) {
    final directory = await Directory.systemTemp.createTemp('ditto_peer${i}_');
    final ditto = await Ditto.open(
      DittoConfig(
        // All peers of a group use the same database ID; give every group
        // that can run at the same time its own ID and port.
        databaseID: databaseID,
        persistenceDirectory: directory.path,
      ),
    );
    _peerStores.add((ditto, directory)); // closed by closeSyncedPeers()
    addTearDown(ditto.sync.stop); // frees the port for the next test
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
        // A device that only connects still listens on every interface, so
        // bind its listener to this machine: test peers stay off the network.
        config.listen.tcp
          ..isEnabled = true
          ..interfaceIP = '127.0.0.1'
          ..port = 0;
      }
    });
    // App setup after open, such as indexes. On SDK 5.2+, pass system
    // parameters in the DittoConfig above instead.
    await configure?.call(ditto);
    ditto.sync.start();
    peers.add(ditto);
  }
  await _waitUntil(() => peers.every(_isConnected));
  return peers;
}

/// Closes every peer that openSyncedPeers() opened. Register it once per file:
/// tearDownAll(closeSyncedPeers).
Future<void> closeSyncedPeers() async {
  for (final (ditto, directory) in _peerStores) {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  }
  _peerStores.clear();
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
  tearDownAll(closeSyncedPeers);

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
