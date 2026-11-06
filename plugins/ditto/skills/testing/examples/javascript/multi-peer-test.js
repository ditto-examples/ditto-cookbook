// Ditto SDK: 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, Node.js test runner)
// Several peers in one test process over TCP on 127.0.0.1, and a concurrent-edit
// test. Run with:
//   DITTO_LICENSE_TOKEN=... node --test multi-peer-test.js
// The test is skipped without the variable. Keep the token out of the repository.
// What the test checks, as DQL and expected results, is in § Testing on Multiple Devices.
//
// Guide: § Several peers in one test process, § Several peers in one test in JavaScript

import { Ditto, DittoConfig } from '@dittolive/ditto';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

// Offline license token, passed as an environment variable (never commit it).
const licenseToken = process.env.DITTO_LICENSE_TOKEN ?? '';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Opens `count` peers in this process that sync with each other over TCP on
// localhost only: peer 0 listens, the others connect to it. A device accepts at
// most 6 TCP connections by default, so keep `count` at 7 or below.
async function openSyncedPeers(t, count, { port = 4041, databaseID = '00000000-0000-4000-8000-000000000002', configure } = {}) {
  const peers = [];
  for (let i = 0; i < count; i += 1) {
    const directory = await mkdtemp(path.join(os.tmpdir(), `ditto-peer${i}-`));
    // All peers of a group use the same database ID; give every group that can
    // run at the same time its own ID and port.
    const ditto = await Ditto.open(new DittoConfig({ databaseID, connect: { mode: 'smallPeersOnly' }, persistenceDirectory: directory }));
    t.after(async () => {
      await ditto.close();
      await rm(directory, { recursive: true, force: true });
    });
    ditto.setOfflineOnlyLicenseToken(licenseToken);
    ditto.updateTransportConfig((config) => {
      config.setAllPeerToPeerEnabled(false); // no Bluetooth, LAN, or AWDL
      // A device that only connects still listens on every interface, so bind
      // every listener to this machine: test peers stay off the network.
      config.listen.tcp.isEnabled = true;
      config.listen.tcp.interfaceIP = '127.0.0.1';
      config.listen.tcp.port = i === 0 ? port : 0;
      if (i > 0) config.connect.tcpServers = [`127.0.0.1:${port}`];
    });
    // App setup after open, such as indexes. On SDK 5.2+, pass system
    // parameters in the DittoConfig above instead.
    await configure?.(ditto);
    ditto.sync.start();
    peers.push(ditto);
  }
  await waitUntil(() => peers.every(isConnected));
  return peers;
}

const isConnected = (ditto) => ditto.presence.graph.remotePeers.length > 0;

async function waitUntil(condition, { timeoutMs = 15_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (!(await condition())) {
    if (Date.now() > deadline) throw new Error('Condition not met');
    await sleep(100);
  }
}

// Stops sync on every peer, runs `writes` while the peers are disconnected,
// then reconnects them, so the writes are concurrent.
async function whileDisconnected(peers, writes) {
  for (const peer of peers) peer.sync.stop();
  await waitUntil(() => peers.every((peer) => !isConnected(peer)));
  await writes();
  for (const peer of peers) peer.sync.start();
  await waitUntil(() => peers.every(isConnected));
}

// Waits until `query` returns the same rows on every peer and `until` holds
// for them, then returns the rows.
async function waitForConvergence(peers, query, { args = {}, until = () => true, timeoutMs = 15_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (true) {
    const results = [];
    for (const peer of peers) {
      const result = await peer.store.execute(query, args);
      results.push(result.items.map((item) => item.jsonString()));
    }
    const first = JSON.stringify(results[0]);
    if (results.every((rows) => JSON.stringify(rows) === first)) {
      const rows = results[0].map((json) => JSON.parse(json));
      if (until(rows)) return rows;
    }
    if (Date.now() > deadline) throw new Error(`Peers did not converge: ${JSON.stringify(results)}`);
    await sleep(100);
  }
}

test('concurrent edits of different line items both survive', { skip: licenseToken === '' && 'Needs DITTO_LICENSE_TOKEN' }, async (t) => {
  const [tablet, phone] = await openSyncedPeers(t, 2);
  for (const peer of [tablet, phone]) peer.sync.registerSubscription('SELECT * FROM orders');
  await tablet.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: { _id: 'order-1', items: { 'item-1': { productId: 'p1', quantity: 1 } } },
  });
  await waitForConvergence([tablet, phone], 'SELECT * FROM orders', { until: (rows) => rows.length === 1 });

  // The code under test would be the app's repository functions.
  await whileDisconnected([tablet, phone], async () => {
    await tablet.store.execute('UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id', { id: 'order-1' });
    await phone.store.execute('UPDATE orders SET items.`item-2` = :item WHERE _id = :id', {
      id: 'order-1',
      item: { productId: 'p2', quantity: 1 },
    });
  });

  const rows = await waitForConvergence([tablet, phone], 'SELECT * FROM orders WHERE _id = :id', {
    args: { id: 'order-1' },
    until: (rows) => Object.keys(rows[0]?.items ?? {}).length === 2,
  });
  assert.equal(rows[0].items['item-1'].quantity, 3);
  assert.equal(rows[0].items['item-2'].productId, 'p2');
});
