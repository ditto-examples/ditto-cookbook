// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter
// Last Updated: 2026-10-08
//
// ============================================================================
// Logging and Diagnostics Configuration (Anti-Patterns)
// ============================================================================
//
// Guide sections (.claude/guides/best-practices/ditto.md):
// - #logging
// - #forwarding-logs-to-your-own-pipeline
// - #on-disk-logs-and-exporting-them
// - #system-virtual-collections
//
// Each function compiles, but fails at runtime or loses diagnostics.
// Corrected versions are in logging-configuration-good.dart.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ DittoLogger used before Ditto.init() (throws "Ditto not initialized")
// 2. ❌ Log level set only after Ditto.open() (startup logged with defaults)
// 3. ❌ Verbose logging in production
// 4. ❌ Log callback installed once, lost after close() and reopen
// 5. ❌ Slow, blocking work inside the log callback
// 6. ❌ Exporting logs to a fixed path that may already exist
// 7. ❌ Long-lived observer on system:system_info
// 8. ❌ Changing on-disk log rotation parameters without guidance
//
// ============================================================================

import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

const _config = DittoConfig(databaseID: 'YOUR_DATABASE_ID');

// ============================================================================
// ANTI-PATTERN 1: DittoLogger before Ditto.init()
// ============================================================================

/// ❌ BAD: Neither Ditto.init() nor Ditto.open() has completed, so this
/// setter throws a DittoError ("Ditto not initialized").
/// Fix: await Ditto.init() first.
Future<Ditto> configureLoggingTooEarly() async {
  DittoLogger.minimumLogLevel = LogLevel.debug; // Throws.
  return Ditto.open(_config);
}

// ============================================================================
// ANTI-PATTERN 2: Level set only after Ditto.open()
// ============================================================================

/// ❌ BAD: This does not throw (Ditto.open initializes the SDK in SDK 5.1+), but startup
/// is logged with the default level (info) instead of your settings.
/// Fix: await Ditto.init(), configure DittoLogger, then Ditto.open().
Future<Ditto> configureLoggingTooLate() async {
  final ditto = await Ditto.open(_config);
  DittoLogger.minimumLogLevel = LogLevel.debug;
  return ditto;
}

// ============================================================================
// ANTI-PATTERN 3: Verbose logging in production
// ============================================================================

/// ❌ BAD: Verbose logging can significantly slow down replication. Use
/// LogLevel.warning in production. The on-disk logs already contain
/// debug-level entries for support, regardless of this setting.
Future<void> verboseEverywhere() async {
  await Ditto.init();
  DittoLogger.minimumLogLevel = LogLevel.verbose;
}

// ============================================================================
// ANTI-PATTERN 4: Callback installed once
// ============================================================================

/// ❌ BAD: ditto.close() resets customLogCallback to null. After signing out
/// and back in, Ditto logs no longer reach the app's pipeline.
/// Fix: install the callback again before every Ditto.open() (after
/// Ditto.init()).
class SessionWithLostCallback {
  SessionWithLostCallback(void Function(String) report) {
    DittoLogger.customLogCallback = (level, message) => report(message);
  }

  Ditto? _ditto;

  Future<void> signIn() async => _ditto = await Ditto.open(_config);

  Future<void> signOut() async {
    await _ditto?.close(); // Clears DittoLogger.customLogCallback.
    _ditto = null;
  }
}

// ============================================================================
// ANTI-PATTERN 5: Blocking work in the log callback
// ============================================================================

/// ❌ BAD: The callback runs for every log event it receives.
/// Synchronous file I/O per event blocks the calling isolate. Keep the
/// callback fast: filter by level and hand lines to a buffered logger.
void installBlockingCallback(File logFile) {
  DittoLogger.customLogCallback = (LogLevel level, String message) {
    logFile.writeAsStringSync('$level $message\n', mode: FileMode.append, flush: true);
  };
}

// ============================================================================
// ANTI-PATTERN 6: Exporting to a fixed path
// ============================================================================

/// ❌ BAD: exportLogs throws a DittoError when the file already exists, so the
/// second export fails. Use a new, timestamped `.jsonl.gz` path in an existing
/// directory.
Future<int> exportToFixedPath(Directory directory) {
  return DittoLogger.exportLogs('${directory.path}/ditto-logs.jsonl.gz');
}

// ============================================================================
// ANTI-PATTERN 7: Observer on system:system_info
// ============================================================================

/// ❌ BAD: Observers on
/// system:system_info fire every 500 ms regardless of whether anything
/// changed. Query system collections with execute when you need them.
StoreObserver observeSystemInfo(Ditto ditto) {
  final observer = ditto.store.registerObserver(
    "SELECT key, value FROM system:system_info WHERE namespace = 'core'",
  );
  observer.changes.listen((result) => debugPrint('core: ${result.items.length}'));
  return observer;
}

// ============================================================================
// ANTI-PATTERN 8: Changing log rotation parameters
// ============================================================================

/// ❌ BAD: Leave the ROTATING_LOG_FILE_* parameters at their defaults unless
/// Ditto support advises otherwise.
Future<void> enlargeLogRotation(Ditto ditto) async {
  await ditto.store.execute('ALTER SYSTEM SET ROTATING_LOG_FILE_MAX_SIZE_MB = 5');
}
