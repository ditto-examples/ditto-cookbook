// Ditto SDK: 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, Node.js test runner)
// A local-store test helper and the skeleton of a test file. Run with:
//   node --test local-store-test-helper.js
// What each test checks, as DQL and expected results, is in
// § Testing Strategies; the tests themselves are in local-store-tests.js.
//
// The test runner keeps the event loop running, so awaiting a transaction in a
// test does not end the process.
//
// Guide: § A Test Helper for a Local Store, § A local-store test helper in JavaScript

import { Ditto, DittoConfig } from '@dittolive/ditto';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { beforeEach, test } from 'node:test';

// Opens a Ditto instance for one test. Sync is never started, so no license
// token or network connection is needed. `t` is the test context (beforeEach
// and test pass it); the store is closed after that test.
export async function openTestDitto(t, { systemParameters = {}, configure } = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ditto-test-'));
  const ditto = await Ditto.open(
    new DittoConfig({
      // Any UUID works for local tests; each test gets its own directory.
      databaseID: '00000000-0000-4000-8000-000000000001',
      connect: { mode: 'smallPeersOnly' },
      persistenceDirectory: directory,
      // The same parameters as the app's DittoConfig (SDK 5.2+).
      systemParameters,
    }),
  );

  // Runs after the test, even when it fails.
  t.after(async () => {
    await ditto.close();
    await rm(directory, { recursive: true, force: true });
  });

  // Create the app's indexes, as at app startup.
  await configure?.(ditto);
  return ditto;
}

// Every test starts with an empty store. Pass `systemParameters` and
// `configure` with the settings and indexes your app uses.
let ditto;
beforeEach(async (t) => {
  ditto = await openTestDitto(t);
});

test('a new store is empty', async () => {
  const result = await ditto.store.execute('SELECT COUNT(*) AS n FROM orders');
  assert.equal(result.items[0].value.n, 0);
});

// The tests of local-store-tests.js go here.
