// Logging and diagnostics anti-patterns for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0).
//
// Each function runs, but loses diagnostics, slows the app down, or fails
// later. The corrected versions are in logging-configuration-good.js.
//
// Guide: § Logging in JavaScript, § Log levels, § On-disk logs and exporting them

import { Ditto, DittoConfig, Logger } from '@dittolive/ditto';
import { appendFileSync } from 'node:fs';
import path from 'node:path';

// ❌ BAD: The level is set only after Ditto.open(), so the startup is logged
// with the previous level. Configure Logger first; it works before open.
export async function configureLoggingTooLate(config) {
  const ditto = await Ditto.open(config);
  Logger.minimumLogLevel = 'Debug';
  return ditto;
}

// ❌ BAD: Verbose logging in production can significantly slow down
// replication. The on-disk logs already contain debug-level entries for
// support, regardless of this setting. Use 'Warning' in production.
export function verboseEverywhere() {
  Logger.minimumLogLevel = 'Verbose';
}

// ❌ BAD: Synchronous file I/O for every log line blocks the event loop. Keep
// the callback fast: filter by level and hand lines to a buffered logger.
export async function installBlockingCallback(logFile) {
  await Logger.setCustomLogCallback((level, message) => {
    appendFileSync(logFile, `${level} ${message}\n`);
  });
}

// ❌ BAD: Installing a new callback on every open, from different places, and
// never removing one. The callback is process-wide and survives close(), so the
// last installation silently replaces the others. Install it once at startup.
export async function reinstallPerScreen(report, screenName) {
  await Logger.setCustomLogCallback((level, message) => report(`${screenName}: ${message}`));
}

// ❌ BAD: Exporting to a fixed path. The second export rejects with a
// DittoError (code io/already-exists, "File exists (os error 17)"). Use a new,
// timestamped .jsonl.gz path in an existing directory.
export function exportToFixedPath(directory) {
  return Logger.exportToFile(path.join(directory, 'ditto-logs.jsonl.gz'));
}

// ❌ BAD: An observer on system:system_info fires often even when nothing
// changed. Query system collections with execute when you need them.
export function observeSystemInfo(ditto, onRows) {
  return ditto.store.registerObserver('SELECT * FROM system:system_info', (result) =>
    onRows(result.items.map((item) => item.value)),
  );
}

// ❌ BAD: Leave the ROTATING_LOG_FILE_* parameters at their defaults unless
// Ditto support advises otherwise.
export async function enlargeLogRotation(ditto) {
  await ditto.store.execute('ALTER SYSTEM SET ROTATING_LOG_FILE_MAX_SIZE_MB = 5');
}

// ❌ BAD: Passing a system parameter only with ALTER SYSTEM after open. It is
// not persisted and applies only after Ditto has started; on SDK 5.2+, pass it
// in DittoConfig.systemParameters on every open.
export async function strictModeAfterOpen() {
  const ditto = await Ditto.open(new DittoConfig({ databaseID: 'YOUR_DATABASE_ID', connect: { mode: 'smallPeersOnly' } }));
  await ditto.store.execute('ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 10');
  return ditto;
}
