// Ditto SDK: 5.2.0 (Flutter package ditto_live), verified with ditto_live 5.2.0
//
// A local-store test helper and the skeleton of a test file. Run with: flutter test integration_test/orders_test.dart -d macos
//
// What each test checks, as DQL and expected results, is in
// ../../reference/test-helpers.md and in the guide's Testing Strategies; the same
// tests for the other SDKs are in examples/<sdk>/ with the same base name.
//
// Guide: § A Test Helper for a Local Store, § A local-store test helper in Flutter

// integration_test/orders_test.dart
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The stores that the tests of this file opened. They close together after
/// the last test: on SDK 5.2.0, opening a store after another store of the
/// process was closed could stop (guide: § A local-store test helper in Flutter).
final _testStores = <(Ditto, Directory)>[];

/// Opens a Ditto instance for one test. Sync is never started, so no
/// license token or network connection is needed.
Future<Ditto> openTestDitto({
  Map<String, Object> systemParameters = const {},
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final directory = await Directory.systemTemp.createTemp('ditto_test_');
  final ditto = await Ditto.open(
    DittoConfig(
      // Any UUID works for local tests; each test gets its own directory.
      databaseID: '00000000-0000-4000-8000-000000000001',
      persistenceDirectory: directory.path,
      // The same parameters as the app's DittoConfig (SDK 5.2+).
      systemParameters: systemParameters,
    ),
  );

  _testStores.add((ditto, directory)); // closed by closeTestDittos()

  // Create the app's indexes, as at app startup.
  await configure?.call(ditto);
  return ditto;
}

/// Closes every store that openTestDitto() opened and deletes its directory.
/// Register it once per file: tearDownAll(closeTestDittos).
Future<void> closeTestDittos() async {
  for (final (ditto, directory) in _testStores) {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort: the OS removes temporary directories eventually.
    }
  }
  _testStores.clear();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(closeTestDittos);

  // Every test starts with an empty store.
  late Ditto ditto;
  setUp(() async {
    // Pass `systemParameters:` and `configure:` with the settings and
    // indexes your app uses; see "Applying System Parameters".
    ditto = await openTestDitto();
  });

  test('a new store is empty', () async {
    final result = await ditto.store.execute('SELECT COUNT(*) AS n FROM orders');
    expect(result.items.first.value['n'], 0);
  });

  // The tests in the following sections go here.
}
