# Test Helper for a Local Store

The helper and test file skeleton from `§ A Test Helper for a Local Store` (verified with `ditto_live` 5.1.0).

## Contents

- [What the helper does](#what-the-helper-does)
- [Test file with the helper](#test-file-with-the-helper)
- [Running the tests](#running-the-tests)
- [How the other examples fit in](#how-the-other-examples-fit-in)

## What the helper does

- Opens a small-peers-only instance (the default `connect` mode, `DittoConfigConnectSmallPeersOnly()`) in its own temporary directory, and closes it automatically when the test ends (`addTearDown`), even when the test fails.
- Never starts sync, so it needs no license token and no network, and can run in CI. The local store works without a license; in small-peers-only mode `ditto.sync.start()` throws without an offline license token (`§ Initializing Ditto`).
- Takes a `configure` callback to apply the same system parameters and indexes that your app applies at startup (system parameters are not persisted; `§ Applying System Parameters`).
- Gives every test an empty store. Never share one persistence directory between tests or open it twice; in Flutter, a second `Ditto.open()` on an open directory may never complete (`§ One instance per persistence directory`).
- As your suite grows, move the helper into a shared file under `integration_test/`.

## Test file with the helper

```dart
// integration_test/orders_test.dart
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Opens a Ditto instance for one test. Sync is never started, so no
/// license token or network connection is needed.
Future<Ditto> openTestDitto({
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final directory = await Directory.systemTemp.createTemp('ditto_test_');
  final ditto = await Ditto.open(
    DittoConfig(
      // Any UUID works for local tests; each test gets its own directory.
      databaseID: '00000000-0000-4000-8000-000000000001',
      persistenceDirectory: directory.path,
    ),
  );

  // Runs after the test, even when it fails.
  addTearDown(() async {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort: the OS removes temporary directories eventually.
    }
  });

  // Apply the app's system parameters and indexes, as at app startup.
  await configure?.call(ditto);
  return ditto;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Every test starts with an empty store.
  late Ditto ditto;
  setUp(() async {
    // Pass `configure:` with the setup your app runs after Ditto.open
    // (system parameters, indexes); see "Applying System Parameters".
    ditto = await openTestDitto();
  });

  test('a new store is empty', () async {
    final result = await ditto.store.execute('SELECT COUNT(*) AS n FROM orders');
    expect(result.items.first.value['n'], 0);
  });

  // The tests in the following sections go here.
}
```

## Running the tests

A real `Ditto` instance needs the SDK's native library, which is packaged with your app build for each platform. Run tests that open Ditto with the `integration_test` package on a supported desktop or device target, for example `flutter test integration_test/orders_test.dart -d macos`. Tests that use only a mock of your own interface run with a plain `flutter test`. On Flutter Web the store is in memory and does not support indexes (`§ Requirements`), so skip index assertions there.

## How the other examples fit in

The examples in [local-store-tests.md](local-store-tests.md) are written as `test(...)` calls (and, in one case, a helper function) that go inside `main()` of such a file, with `ditto` provided by `setUp`. Their `import` lines belong at the top of the file. The examples define the statements and functions under test inline so that each one is complete; in your suite, call your app's repository functions instead, so that a test fails when the app code changes.
