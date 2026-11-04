# Logging and Observability

Ditto provides three complementary sources of diagnostic information: SDK logs, local system virtual collections that describe the state of the device and the query engine, and remote diagnostics through the Ditto Portal. The collections and the system parameters are listed in [System Collections and Parameters](../knowledge/system-reference.md).

## Logging

### Configuring logging in Flutter

`DittoLogger` is a set of static members. Every member throws `Ditto not initialized` until the SDK is initialized, and `Ditto.open` initializes it implicitly. To configure logging **before** opening Ditto (recommended, so that startup is logged with your settings), call `await Ditto.init()` first:

```dart
import 'package:flutter/foundation.dart';

/// Call before Ditto.open().
Future<void> configureDittoLogging() async {
  // DittoLogger throws until Ditto is initialized.
  await Ditto.init();

  DittoLogger.isEnabled = true;
  DittoLogger.minimumLogLevel =
      kReleaseMode ? LogLevel.warning : LogLevel.debug;
}
```

**✅ DO:**
- Call `await Ditto.init()` before touching `DittoLogger` while Ditto is not open.
- Use `LogLevel.warning` in production and `LogLevel.debug` while debugging.
- Use `LogLevel.verbose` only for short, targeted investigations.

**❌ DON'T:**
- Leave `LogLevel.verbose` enabled in production. It multiplies the log output: in our testing on SDK 5.2.0, 2,000 writes produced about 83,000 log lines at verbose, against 154 at info, while the write rate itself did not change (see [Exported logs include debug lines regardless of the console level](../knowledge/observations/configuration-and-diagnostics.md#exported-logs-include-debug-lines-regardless-of-the-console-level)).
- Set `DittoLogger` properties before `Ditto.init()` (or `Ditto.open`) has completed; they throw.

### Log levels

`LogLevel` has five values, from most to least severe:

| `LogLevel` | Typical use |
|---|---|
| `error` | Failures that need attention |
| `warning` | Unexpected situations Ditto handled (recommended for production) |
| `info` | High-level lifecycle events |
| `debug` | Detailed diagnostics (recommended while debugging) |
| `verbose` | Very detailed tracing; a very large log volume |

Defaults: `DittoLogger.isEnabled` is `true`, `DittoLogger.minimumLogLevel` is `LogLevel.info`, and `customLogCallback` is `null`. Set the level explicitly instead of relying on the default.

`DittoLogger.isEnabled` and `minimumLogLevel` control the logs Ditto emits at runtime. They do not affect the on-disk logs described below.

### Forwarding logs to your own pipeline

`DittoLogger.customLogCallback` receives the log events that Ditto emits. Use it to forward Ditto logs to your logging or crash-reporting tool.

`ditto.close()` resets `customLogCallback` to `null` for the whole process, even if other `Ditto` instances are still open. If your app closes and reopens Ditto (for example when the user signs out and in again), set the callback again before each `Ditto.open()`, after `Ditto.init()`, so that logs emitted while Ditto opens are forwarded too.

```dart
/// Forwards Ditto warnings and errors to the app's logging pipeline.
/// Call after Ditto.init() and before every Ditto.open(), because
/// ditto.close() clears the callback.
void installDittoLogForwarding(void Function(String line) report) {
  DittoLogger.customLogCallback = (LogLevel level, String message) {
    if (level == LogLevel.error || level == LogLevel.warning) {
      report('[ditto ${level.name}] $message');
    }
  };
}

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
```

Keep the callback fast and non-blocking; it is called for every log event.

In Flutter, `DittoLogger.isDevtoolsLoggingEnabled = true` additionally sends Ditto logs to Flutter DevTools through `dart:developer`.

### On-disk logs and exporting them

Independently of `isEnabled` and `minimumLogLevel`, Ditto always collects a limited amount of logs at `LogLevel.debug` and above in the persistence directory of the most recently created `Ditto` instance. By default, Ditto retains about 15 MB of compressed logs or 15 days of logs, and periodically discards older entries once one of these limits is reached.

On-disk logs rotate in files of up to 1 MB or 24 hours each, and at most 15 files are kept (`ROTATING_LOG_FILE_MAX_SIZE_MB`, `ROTATING_LOG_FILE_MAX_AGE_H`, `ROTATING_LOG_FILE_MAX_FILES_ON_DISK`). In our testing on SDK 5.2.0, the files kept the log of about 200,000 writes, about 5 hours at 10 writes a second (see [On SDK 5.2.0, the on-disk logs kept about 200,000 writes](../knowledge/observations/storage-and-deletion.md#on-sdk-520-the-on-disk-logs-kept-about-200000-writes)). Leave these at their defaults unless Ditto support advises otherwise.

**What the logs contain**: in our testing with SDK 5.0.3 to 5.2.0, the on-disk logs of a device, and of each device directly connected to it, contained the text and the argument values of the device's subscriptions, at every console log level, while document IDs and values, `execute` statements, observer arguments, and peer metadata did not appear (see [Subscription queries and arguments appear in other devices' logs](../knowledge/observations/configuration-and-diagnostics.md#subscription-queries-and-arguments-appear-in-other-devices-logs)). The logs leave the device when you export them or request them through the Portal, so do not filter subscriptions by personal data (see [Input Validation and Query Parameters](security.md#input-validation-and-query-parameters)). Error messages can contain document IDs (`Identifier conflict on document "<id>"`); keep that in mind when you forward exceptions to your own logging.

The on-disk logs can be retrieved in two ways:

- **From the Ditto Portal:** request logs from a device on the device dashboard (see [Remote Diagnostics](#remote-diagnostics)).
- **From the app:** `DittoLogger.exportLogs(path)` (in JavaScript, `Logger.exportToFile(path)`) writes them to a gzip-compressed JSON Lines file and returns the number of bytes written. The file must not already exist (otherwise it throws a `DittoError`) and its directory must exist. The recommended extension is `.jsonl.gz`. Only logs of the most recently created `Ditto` instance are exported.

```dart
import 'dart:io';

/// Exports Ditto's on-disk logs, for example for a "Send diagnostics" button.
/// [directory] must exist, for example a temporary or support directory.
Future<File> exportDittoLogs(Directory directory) async {
  final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final file = File('${directory.path}/ditto-logs-$timestamp.jsonl.gz');
  final bytes = await DittoLogger.exportLogs(file.path);
  debugPrint('Exported $bytes bytes of Ditto logs to ${file.path}');
  return file;
}
```

Because the on-disk logs always include debug-level entries, setting the console level to `warning` in production does not reduce what you can retrieve later for support (see [Exported logs include debug lines regardless of the console level](../knowledge/observations/configuration-and-diagnostics.md#exported-logs-include-debug-lines-regardless-of-the-console-level)).

### Configuration snapshots in data bundles (SDK 5.1+)

Data bundles requested through the Ditto Portal (see [Remote Diagnostics](#remote-diagnostics)) include a `config_snapshot.json` file with the device's effective configuration. This gives Ditto support the device's configuration at the start of every investigation.

### Support bundles (SDK 5.2+)

A support bundle packages the device's on-disk logs, its effective configuration, and runtime telemetry into one `tar` archive for Ditto support. Since SDK 5.2, an app can create one on the device with a DQL statement, without a connection to Ditto Server, for example from an admin screen or a "Send diagnostics" button. It is available on native platforms only, not on the Web.

```sql
EXECUTE FUNCTION system_request_support_bundle({'metadata': {'requested_by': 'support'}})

SELECT * FROM system:support_bundles ORDER BY _id.created_at DESC
```

The function returns one document with `_id` (the peer key and the capture time), `reason` (`USER_INITIATED`), and `file`, an attachment token for the archive. Fetch the archive with `fetchAttachment()` like any other attachment (see [Fetching Attachments](attachments.md#fetching-attachments)). In our testing with the JavaScript SDK 5.2.0, the archive contained the logs, the device metadata, and a configuration snapshot (see [A support bundle holds the logs, device metadata, and a configuration snapshot](../knowledge/observations/configuration-and-diagnostics.md#a-support-bundle-holds-the-logs-device-metadata-and-a-configuration-snapshot)).

```dart
// ✅ GOOD: Create a support bundle and save it, for example to share it with
// Ditto support. [path] must not exist yet.
Future<void> saveSupportBundle(Ditto ditto, String path) async {
  final result = await ditto.store.execute(
    "EXECUTE FUNCTION system_request_support_bundle()",
  );
  final token = Map<String, dynamic>.from(result.items.single.value['file'] as Map);
  final fetcher = ditto.store.fetchAttachment(token, (event) {});
  final attachment = await fetcher.attachment;
  await attachment!.copyToPath(path);
}
```

| System parameter | Default | Behavior |
|---|---|---|
| `SUPPORT_BUNDLE_REQUEST_RATE` | `3` | Requests allowed per rolling 10-minute window; `0` turns bundles off. A rejected request fails with `support bundle request rate exceeded`, and the count survives restarts. |
| `SUPPORT_BUNDLE_REQUEST_TIMEOUT` | `30` | Seconds allowed to collect and write one bundle |
| `SUPPORT_BUNDLE_RETENTION_LIMIT` | `10` | Bundles kept on the device; the oldest is removed first |

The log export in a bundle contains the full peer keys of other devices and absolute file paths on the device. Review a bundle before you share it beyond Ditto support.

## Remote Diagnostics

The Ditto Portal complements on-device diagnostics. The [device dashboard](https://docs.ditto.live/cloud/portal/capturing-small-peer-info), which is populated from the Small Peer Info system collection, shows each device's mesh connection status, the time it was last seen by Ditto Server, its name and peer key, its operating system, its latest logs, and custom metadata that your app sets through `ditto.smallPeerInfo`. From a device's detail page you can request its logs or a data bundle (logs and other diagnostic data). Requests and uploads travel through sync, so a device does not need to be online when you make the request; it uploads the data when it next connects. Since SDK 5.2, the app can also create a support bundle on the device itself with DQL (see [Support bundles (SDK 5.2+)](#support-bundles-sdk-52)); such bundles stay on the device until the app fetches and shares them. See the [Ditto Portal troubleshooting documentation](https://docs.ditto.live/cloud/portal/troubleshooting) for the steps and required Portal permissions, and [Remote Observability](https://docs.ditto.live/sdk/latest/deployment/device-observability-and-ditto-logs) for the SDK side.
