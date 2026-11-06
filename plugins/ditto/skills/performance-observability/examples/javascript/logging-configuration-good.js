// Logging and diagnostics configuration for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0).
//
// Facts:
// - Logger has static members only, and they work before any instance is
//   opened, so configure logging first.
// - Levels: 'Error', 'Warning', 'Info', 'Debug', 'Verbose'.
// - Logger.setCustomLogCallback() applies to the whole process, and
//   ditto.close() does not remove it; it throws in React Native.
// - Logger.exportToFile(path) writes the on-disk logs of the most recently
//   opened instance (Debug and above, whatever the console level); the file
//   must not exist, its directory must exist, and browsers do not support it.
// - System parameters are not persisted: pass them in DittoConfig on every
//   open (SDK 5.2+). A misspelled name or a wrong type makes Ditto.open() reject.
//
// Guide: § Logging in JavaScript, § DittoConfig in JavaScript, § Logging, § Support bundles (SDK 5.2+), § Applying System Parameters

import { Ditto, DittoConfig, Logger, init } from '@dittolive/ditto';
import path from 'node:path';

// Placeholder: fetches an authentication token from your backend.
async function fetchAuthToken() {
  return 'token';
}

// ✅ GOOD: Configure logging before Ditto.open().
export function configureDittoLogging({ production }) {
  Logger.enabled = true;
  Logger.minimumLogLevel = production ? 'Warning' : 'Debug';
}

// ✅ GOOD: Forwards Ditto warnings and errors. The callback is fast and does
// no I/O, because it runs for every log line. Install it once per process.
export async function installDittoLogForwarding(report) {
  await Logger.setCustomLogCallback((level, message) => {
    if (level === 'Error' || level === 'Warning') report(`[ditto ${level}] ${message}`);
  });
}

// ✅ GOOD: This app's system parameters, passed on every open (SDK 5.2+).
// Default is 60 seconds; a lower threshold surfaces slow queries early (SDK 5.1+).
export const appSystemParameters = (production) => (production ? {} : { DQL_SLOW_REQUEST_WARN_SECONDS: 10 });

// ✅ GOOD: Logging and log forwarding first, then open with the app's system
// parameters, then everything that depends on the instance (auth handler, sync).
export async function startDitto(report, { production = false } = {}) {
  await init();
  configureDittoLogging({ production });
  await installDittoLogForwarding(report);
  const ditto = await Ditto.open(
    new DittoConfig({
      databaseID: 'YOUR_DATABASE_ID',
      connect: { mode: 'server', url: 'YOUR_SERVER_URL' },
      systemParameters: appSystemParameters(production),
    }),
  );
  await ditto.auth.setExpirationHandler(async (ditto) => {
    // Do not throw inside the handler; the SDK only logs it. Report instead.
    try {
      const result = await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
      if (result.error) report(`login failed: ${result.error.message}`);
    } catch (error) {
      report(`login failed: ${error}`);
    }
  });
  ditto.sync.start();
  return ditto;
}

// ✅ GOOD: Closing and reopening keeps the log callback; nothing to re-install.
export class DittoSession {
  #config;
  #ditto = null;

  constructor(config) {
    this.#config = config;
  }

  async open() {
    this.#ditto = await Ditto.open(this.#config);
    return this.#ditto;
  }

  async close() {
    await this.#ditto?.close(); // The log callback stays installed.
    this.#ditto = null;
  }
}

// ✅ GOOD: Exports Ditto's on-disk logs to a new gzip-compressed JSON Lines
// file in an existing directory (Node.js and React Native).
export async function exportDittoLogs(directory) {
  const file = path.join(directory, `ditto-logs-${Date.now()}.jsonl.gz`);
  const bytes = await Logger.exportToFile(file);
  console.log(`Exported ${bytes} bytes of Ditto logs to ${file}`);
  return file;
}

// ✅ GOOD: Verbose logging can significantly slow down replication. Enable it
// only for a short, targeted investigation and restore the previous level.
export async function withVerboseLogging(investigate) {
  const previous = Logger.minimumLogLevel;
  Logger.minimumLogLevel = 'Verbose';
  try {
    return await investigate();
  } finally {
    Logger.minimumLogLevel = previous;
  }
}

// ✅ GOOD: Logs the parameters that differ from their defaults, for example
// after Ditto.open() in development builds, to confirm the configuration.
export async function logNonDefaultParameters(ditto) {
  const result = await ditto.store.execute(
    "SELECT key, value FROM system:system_info WHERE key LIKE 'non_default_system_parameter%'",
  );
  for (const item of result.items) console.log(`${item.value.key} = ${item.value.value}`);
}

// ✅ GOOD: Query system: virtual collections with execute when needed (a
// diagnostics screen or support action). They are local, read only, and never
// synced. Do not keep long-lived observers on system:system_info.
export async function diagnosticsSnapshot(ditto) {
  const values = async (query) => (await ditto.store.execute(query)).items.map((item) => item.value);
  return {
    core: await values("SELECT key, value FROM system:system_info WHERE namespace = 'core' AND key LIKE 'ditto_sdk%'"),
    logs: await values("SELECT key, value FROM system:system_info WHERE namespace = 'logs'"),
    indexes: await values('SELECT _id FROM system:indexes'),
    activeRequests: await values('SELECT _id, text, state, times FROM system:active_requests'),
    // Documents that stopped syncing on this device (SDK 5.2+).
    syncDegradations: await values('SELECT * FROM system:sync_degradations'),
  };
}

// ✅ GOOD: Create a support bundle (SDK 5.2+) and save it, for example to share
// it with Ditto support. SUPPORT_BUNDLE_REQUEST_RATE limits requests (3 per
// rolling 10 minutes by default). The archive contains peer keys of other
// devices and absolute file paths: review it before sharing it beyond Ditto
// support. copyToPath() needs Node.js or React Native and replaces an
// existing file.
export async function saveSupportBundle(ditto, filePath) {
  const result = await ditto.store.execute('EXECUTE FUNCTION system_request_support_bundle()');
  const token = result.items[0].value.file;
  const attachment = await ditto.store.fetchAttachment(token);
  await attachment.copyToPath(filePath);
}
