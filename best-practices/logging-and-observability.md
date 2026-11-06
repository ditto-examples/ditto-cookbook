# Logging and Observability

**Set the log level explicitly (`warning` in production) before you open Ditto, forward warnings and errors to your own logging, and give support a way to export the on-disk logs or a support bundle.** Ditto provides three complementary sources of diagnostic information: SDK logs, local system virtual collections that describe the state of the device and the query engine, and remote diagnostics through the Ditto Portal. The collections and the system parameters are listed in [System Collections and Parameters](../knowledge/system-reference.md).

## Logging

### Configuring logging

Every SDK has one process-wide logger with the same settings: whether logging is enabled, the minimum level, a way to forward log events to your code, and an export of the on-disk logs.

| | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Logger | `DittoLogger` (static members) | `Logger` (static members) | `DittoLogger` (an object) | `DittoLogger` (static members) |
| Minimum level | `minimumLogLevel` | `minimumLogLevel` | `minimumLogLevel` | `minimumLogLevel` |
| Forward log events | `customLogCallback` | `setCustomLogCallback(callback)` | `observeLogEvents()`, a `Flow` | `setCustomLogCallback(_:)` |
| Export the on-disk logs | `exportLogs(path)` | `exportToFile(path)` | `exportToFile(path)` | `export(to:)` |
| Code | [Logging in Flutter](platforms/flutter.md#logging-in-flutter) | [Logging in JavaScript](platforms/javascript.md#logging-in-javascript) | [Logging in Kotlin](platforms/kotlin.md#logging-in-kotlin) | [Logging in Swift](platforms/swift.md#logging-in-swift) |

Configure the logger before you open Ditto, so that startup is logged with your settings. In Flutter, the logger throws until the SDK is initialized, so call `Ditto.init()` first (see [Logging in Flutter](platforms/flutter.md#logging-in-flutter)).

**✅ DO:**
- Use the `warning` level in production and `debug` while debugging.
- Use `verbose` only for short, targeted investigations.

**❌ DON'T:**
- Leave `verbose` enabled in production. It multiplies the log output: in our testing on SDK 5.2.0, 2,000 writes produced about 83,000 log lines at verbose, against 154 at info, while the write rate itself did not change (see [Exported logs include debug lines regardless of the console level](../knowledge/observations/configuration-and-diagnostics.md#exported-logs-include-debug-lines-regardless-of-the-console-level)).

### Log levels

There are five levels, from most to least severe:

| Level | Typical use |
|---|---|
| `error` | Failures that need attention |
| `warning` | Unexpected situations Ditto handled (recommended for production) |
| `info` | High-level lifecycle events |
| `debug` | Detailed diagnostics (recommended while debugging) |
| `verbose` | Very detailed tracing; a very large log volume |

By default, logging is enabled, the minimum level is `info`, and no log events are forwarded. Set the level explicitly instead of relying on the default. The enabled setting and the minimum level control the logs Ditto emits at runtime. They do not affect the on-disk logs described below.

### Forwarding logs to your own pipeline

Forward Ditto's log events to your logging or crash-reporting tool, and keep the code that receives them fast and non-blocking: it runs for every log event. Forward only warnings and errors in production.

In Flutter, `ditto.close()` resets the log callback for the whole process, even if other `Ditto` instances are still open, so set it again before every open (see [Logging in Flutter](platforms/flutter.md#logging-in-flutter)).

### On-disk logs and exporting them

Independently of the enabled setting and the minimum level, Ditto always collects a limited amount of logs at the `debug` level and above in the persistence directory of the most recently created `Ditto` instance. By default, Ditto retains about 15 MB of compressed logs or 15 days of logs, and periodically discards older entries once one of these limits is reached.

On-disk logs rotate in files of up to 1 MB or 24 hours each, and at most 15 files are kept (`ROTATING_LOG_FILE_MAX_SIZE_MB`, `ROTATING_LOG_FILE_MAX_AGE_H`, `ROTATING_LOG_FILE_MAX_FILES_ON_DISK`). In our testing on SDK 5.2.0, the files kept the log of about 200,000 writes, about 5 hours at 10 writes a second (see [On SDK 5.2.0, the on-disk logs kept about 200,000 writes](../knowledge/observations/storage-and-deletion.md#on-sdk-520-the-on-disk-logs-kept-about-200000-writes)). Leave these at their defaults unless Ditto support advises otherwise.

**What the logs contain**: in our testing with SDK 5.0.3 to 5.2.0, the on-disk logs of a device, and of each device directly connected to it, contained the text and the argument values of the device's subscriptions, at every console log level, while document IDs and values, `execute` statements, observer arguments, and peer metadata did not appear (see [Subscription queries and arguments appear in other devices' logs](../knowledge/observations/configuration-and-diagnostics.md#subscription-queries-and-arguments-appear-in-other-devices-logs)). The logs leave the device when you export them or request them through the Portal, so do not filter subscriptions by personal data (see [Input Validation and Query Parameters](security.md#input-validation-and-query-parameters)). Error messages can contain document IDs (`Identifier conflict on document "<id>"`); keep that in mind when you forward exceptions to your own logging.

The on-disk logs can be retrieved in two ways:

- **From the Ditto Portal:** request logs from a device on the device dashboard (see [Remote Diagnostics](#remote-diagnostics)).
- **From the app:** the logger's export (see the table above) writes them to a gzip-compressed JSON Lines file and returns the number of bytes written. The file must not already exist (otherwise the export fails) and its directory must exist. The recommended extension is `.jsonl.gz`. Only logs of the most recently created `Ditto` instance are exported.

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

The code for creating a support bundle and saving the archive: [Logging in Flutter](platforms/flutter.md#logging-in-flutter) · [JavaScript](platforms/javascript.md#logging-in-javascript) · [Kotlin](platforms/kotlin.md#logging-in-kotlin) · [Swift](platforms/swift.md#logging-in-swift).

| System parameter | Default | Behavior |
|---|---|---|
| `SUPPORT_BUNDLE_REQUEST_RATE` | `3` | Requests allowed per rolling 10-minute window; `0` turns bundles off. A rejected request fails with `support bundle request rate exceeded`, and the count survives restarts. |
| `SUPPORT_BUNDLE_REQUEST_TIMEOUT` | `30` | Seconds allowed to collect and write one bundle |
| `SUPPORT_BUNDLE_RETENTION_LIMIT` | `10` | Bundles kept on the device; the oldest is removed first |

The log export in a bundle contains the full peer keys of other devices and absolute file paths on the device. Review a bundle before you share it beyond Ditto support.

## Remote Diagnostics

The Ditto Portal complements on-device diagnostics. The [device dashboard](https://docs.ditto.live/cloud/portal/capturing-small-peer-info), which is populated from the Small Peer Info system collection, shows each device's mesh connection status, the time it was last seen by Ditto Server, its name and peer key, its operating system, its latest logs, and custom metadata that your app sets through `ditto.smallPeerInfo`. From a device's detail page you can request its logs or a data bundle (logs and other diagnostic data). Requests and uploads travel through sync, so a device does not need to be online when you make the request; it uploads the data when it next connects. Since SDK 5.2, the app can also create a support bundle on the device itself with DQL (see [Support bundles (SDK 5.2+)](#support-bundles-sdk-52)); such bundles stay on the device until the app fetches and shares them. See the [Ditto Portal troubleshooting documentation](https://docs.ditto.live/cloud/portal/troubleshooting) for the steps and required Portal permissions, and [Remote Observability](https://docs.ditto.live/sdk/latest/deployment/device-observability-and-ditto-logs) for the SDK side.
