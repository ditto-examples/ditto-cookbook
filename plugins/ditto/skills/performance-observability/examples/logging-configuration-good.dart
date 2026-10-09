// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter
// Last Updated: 2026-10-08
//
// ============================================================================
// Logging and Diagnostics Configuration (Correct Patterns)
// ============================================================================
//
// Guide sections (.claude/guides/best-practices/ditto.md):
// - #logging
// - #dittoopen-dittoopensync-and-dittoinit
// - #forwarding-logs-to-your-own-pipeline
// - #on-disk-logs-and-exporting-them
// - #system-virtual-collections
// - #long-running-requests-sdk-51
//
// Facts:
// - Every DittoLogger member throws "Ditto not initialized" until the SDK is
//   initialized. Ditto.open initializes it implicitly (SDK 5.1+); call await Ditto.init()
//   to configure logging BEFORE opening, so startup is logged with your settings.
// - LogLevel values: error, warning, info, debug, verbose. Defaults:
//   isEnabled = true, minimumLogLevel = LogLevel.info, customLogCallback = null.
// - ditto.close() resets DittoLogger.customLogCallback to null for the whole
//   process; set it again before every Ditto.open(), after Ditto.init().
// - On-disk logs always include debug-level entries, independent of
//   isEnabled and minimumLogLevel; DittoLogger.exportLogs(path) exports them.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Ditto.init() -> DittoLogger -> Ditto.open() startup order
// 2. ✅ Forwarding warnings and errors, re-installed before every open
// 3. ✅ Exporting on-disk logs for a "Send diagnostics" action
// 4. ✅ Temporary verbose logging for a targeted investigation
// 5. ✅ Slow-request warnings during development (SDK 5.1+)
// 6. ✅ On-demand diagnostics snapshot from system: virtual collections
//
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// PATTERN 1: Startup order
// ============================================================================

/// ✅ GOOD: Call before Ditto.open().
Future<void> configureDittoLogging() async {
  // DittoLogger throws until Ditto is initialized.
  await Ditto.init();

  DittoLogger.isEnabled = true;
  // warning in production, debug while debugging; never verbose in production.
  DittoLogger.minimumLogLevel = kReleaseMode ? LogLevel.warning : LogLevel.debug;
}

/// ✅ GOOD: Logging and log forwarding first, then open, then everything that
/// depends on the instance (system parameters, auth handler, sync).
Future<Ditto> startDitto(void Function(String line) report) async {
  await configureDittoLogging();
  installDittoLogForwarding(report); // Forwards logs emitted while Ditto opens.

  final ditto = await Ditto.open(
    const DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
    ),
  );

  await applyDiagnosticsParameters(ditto);

  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    final response = await ditto.auth.login(
      token: await fetchAuthToken(),
      provider: 'YOUR_PROVIDER_NAME',
    );
    if (response.exception != null) {
      // Do not throw inside the handler; report instead.
      report('Ditto login failed: ${response.exception}');
    }
  });

  ditto.sync.start();
  return ditto;
}

// ============================================================================
// PATTERN 2: Forwarding logs to your own pipeline
// ============================================================================

/// ✅ GOOD: Forwards Ditto warnings and errors. The callback is fast and
/// non-blocking because it runs for every log event it receives.
void installDittoLogForwarding(void Function(String line) report) {
  DittoLogger.customLogCallback = (LogLevel level, String message) {
    if (level == LogLevel.error || level == LogLevel.warning) {
      report('[ditto ${level.name}] $message');
    }
  };
}

/// ✅ GOOD: Re-installs the callback before every open, because ditto.close()
/// clears it (for example when the user signs out and in again).
class DittoSession {
  DittoSession(this._config, this._report);

  final DittoConfig _config;
  final void Function(String line) _report;
  Ditto? _ditto;

  Future<Ditto> open() async {
    await Ditto.init(); // No-op after the first call.
    installDittoLogForwarding(_report); // Set before every open.
    final ditto = await Ditto.open(_config);
    return _ditto = ditto;
  }

  Future<void> close() async {
    await _ditto?.close(); // Also resets DittoLogger.customLogCallback.
    _ditto = null;
  }
}

// ============================================================================
// PATTERN 3: Exporting on-disk logs
// ============================================================================

/// ✅ GOOD: Exports Ditto's on-disk logs to a new gzip-compressed JSON Lines
/// file. The file must not exist yet and [directory] must exist. Only logs of
/// the most recently created Ditto instance are exported.
Future<File> exportDittoLogs(Directory directory) async {
  final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final file = File('${directory.path}/ditto-logs-$timestamp.jsonl.gz');
  final bytes = await DittoLogger.exportLogs(file.path);
  debugPrint('Exported $bytes bytes of Ditto logs to ${file.path}');
  return file;
}

// ============================================================================
// PATTERN 4: Temporary verbose logging
// ============================================================================

/// ✅ GOOD: Verbose logging can significantly slow down replication. Enable it
/// only for a short, targeted investigation and restore the previous level.
Future<T> withVerboseLogging<T>(Future<T> Function() investigate) async {
  final previous = DittoLogger.minimumLogLevel;
  DittoLogger.minimumLogLevel = LogLevel.verbose;
  try {
    return await investigate();
  } finally {
    DittoLogger.minimumLogLevel = previous;
  }
}

// ============================================================================
// PATTERN 5: Slow-request warnings (SDK 5.1+)
// ============================================================================

/// ✅ GOOD: System parameters are not persisted. Apply them after every
/// Ditto.open() and before ditto.sync.start(), then read back the
/// non-default parameters to confirm.
Future<void> applyDiagnosticsParameters(Ditto ditto) async {
  if (!kReleaseMode) {
    // Default is 60 seconds; a lower threshold surfaces slow queries early.
    await ditto.store.execute('ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 10');
  }

  final result = await ditto.store.execute(
    "SELECT key, value FROM system:system_info "
    "WHERE key LIKE 'non_default_system_parameter%'",
  );
  for (final item in result.items) {
    debugPrint('${item.value['key']} = ${item.value['value']}');
  }
}

// ============================================================================
// PATTERN 6: On-demand diagnostics snapshot
// ============================================================================

/// ✅ GOOD: Query system: virtual collections with execute when needed (a
/// diagnostics screen or support action). They are local to this device,
/// read only, and never synced. Do not register long-lived observers on
/// system:system_info, or observers on system:data_sync_info in many places
/// (for live sync status, use a single observer with a trivial callback).
Future<Map<String, Object?>> diagnosticsSnapshot(Ditto ditto) async {
  List<Map<String, dynamic>> values(QueryResult result) =>
      result.items.map((item) => item.value).toList();

  final core = await ditto.store.execute(
    "SELECT key, value FROM system:system_info "
    "WHERE namespace = 'core' AND key LIKE 'ditto_sdk%'",
  );
  final logs = await ditto.store.execute(
    "SELECT key, value FROM system:system_info WHERE namespace = 'logs'",
  );
  final syncConnections = await ditto.store.execute('SELECT * FROM system:data_sync_info');
  final indexes = await ditto.store.execute('SELECT _id FROM system:indexes');
  final activeRequests = await ditto.store.execute(
    'SELECT _id, text, state, times FROM system:active_requests',
  );

  return {
    'core': values(core),
    'logs': values(logs),
    'syncConnections': values(syncConnections),
    'indexes': values(indexes),
    'activeRequests': values(activeRequests),
  };
}

/// Placeholder for fetching an authentication token from your backend.
Future<String> fetchAuthToken() async => 'token';
