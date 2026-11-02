# System Collections and Parameters

Reference for the local `system:` virtual collections and for the system parameters. How to pass system parameters is described in [Applying System Parameters](../best-practices/setup-and-lifecycle.md#applying-system-parameters), and how to use the collections for diagnostics in [Logging and Observability](../best-practices/logging-and-observability.md).

## System Virtual Collections

The `system:` namespace contains virtual collections that describe the local device and its query engine. They are queried with ordinary `SELECT` statements and have these properties:

- **Local only:** they describe this device and are never synced. Use [Remote Diagnostics](../best-practices/logging-and-observability.md#remote-diagnostics) to query other devices.
- **Read only:** `INSERT` and `UPDATE` on the `system` namespace are rejected. The one exception is `DELETE FROM system:request_history`, which clears the request history.
- **Snapshots:** values such as storage usage are collected periodically.

| Collection | Purpose |
|---|---|
| `system:system_info` | Key/value rows about the device: SDK version, database ID, peer key, storage usage, document counts per collection, local subscriptions, log settings, non-default system parameters (storage keys: see [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage)) |
| `system:indexes` | Indexes defined on this device (see [Listing indexes](../best-practices/indexing-and-performance.md#listing-indexes)) |
| `system:data_sync_info` | One row per sync connection with its sync status (see [Monitoring Sync Status](../best-practices/sync-and-subscriptions.md#monitoring-sync-status)) |
| `system:active_requests` | DQL requests that are executing right now, with their plan and timings |
| `system:request_history` | Recently completed DQL requests that matched the history qualifiers (in memory, not persisted) |
| `system:shared_statements` | The prepared-statement cache, with per-statement execution statistics |
| `system:metrics` | SDK metrics. Disabled by default (`METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED` is `false`); when disabled, it returns a single row with `"status": "disabled"`. The parameter is read only at startup: `ALTER SYSTEM` after `Ditto.open` sets it but does not enable the collection. Pass it in `DittoConfig.systemParameters` (SDK 5.2+), or set the environment variable `DITTO_METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED=true` before the process starts. In our testing with the JavaScript SDK on Node.js, both ways worked, and once enabled, the collection stayed enabled for every `Ditto` instance in the process, including instances opened later without the parameter. SDK 5.2 adds query metrics (`ditto.query.requests`, `ditto.query.failed`, `ditto.query.execution_time`), `ditto.store.observer.retained_bytes`, `ditto.store.database.sync_degraded_document_count`, SQLite WAL values, and transport counters |
| `system:sync_degradations` (SDK 5.2+) | Documents whose sync is degraded on this device, with the reason (currently `documentTooBig`; see [Document Size Limits](../best-practices/data-modeling.md#document-size-limits)). Not available on Ditto Server |
| `system:support_bundles` (SDK 5.2+) | Support bundles stored on this device (see [Support bundles (SDK 5.2+)](../best-practices/logging-and-observability.md#support-bundles-sdk-52)) |

`system:vitals` (query engine summary statistics) and `system:collections` (collection list) also exist.

**✅ DO:**
- Query system collections with `execute` when you need the information (a diagnostics screen, a support action, a periodic health log).
- Project only the keys you need from `system:system_info`.
- Include `system:sync_degradations` (SDK 5.2+) in your diagnostics, so that a document that stopped syncing on a device is found before a user reports it.

**❌ DON'T:**
- Register long-lived observers on `system:system_info` (they fire often even when nothing changed; see [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage)), or observers on `system:data_sync_info` in many places. For live sync status, use a single observer with a trivial callback, as shown in [Monitoring Sync Status](../best-practices/sync-and-subscriptions.md#monitoring-sync-status).

### system:system_info

Each row has `namespace`, `key`, `value`, and `timestamp`. Namespaces include `core`, `store`, `logs`, `replication`, `sync_scopes`, and `backend_sqlite3`.

```sql
-- SDK version, database ID, peer key, storage usage
SELECT key, value FROM system:system_info WHERE namespace = 'core'

-- Current log configuration: {"key": "enabled", ...}, {"key": "minimum_level", "value": "INFO"}
SELECT key, value FROM system:system_info WHERE namespace = 'logs'

-- Subscriptions registered on this device (value contains query and params)
SELECT key, value FROM system:system_info WHERE key LIKE 'local_subscriptions%'

-- System parameters that differ from their defaults
SELECT key, value FROM system:system_info WHERE key LIKE 'non_default_system_parameter%'
```

The last query is a convenient way to confirm that your system parameters were applied; for example, after `ALTER SYSTEM SET TOMBSTONE_TTL_HOURS = 120` it returns `{"key": "non_default_system_parameter[tombstone_ttl_hours]", "value": 120}`.

### Request diagnostics

`system:active_requests` and `system:request_history` contain, per request, the statement `text`, its `state`, the executed `plan` with `#stats`, `queryType`, `requestType`, `resultCount`, and `times`.

```sql
SELECT _id, text, state, times FROM system:active_requests

SELECT text, state, times, `~qualifier` AS qualifier FROM system:request_history
```

- `system:request_history` is held in memory and is not persisted across restarts. Its size is controlled by `DQL_REQUEST_HISTORY_SIZE` (default `128` entries in SDK 5.2; `4096` in 5.1). Bundles requested through the Ditto Portal include these entries.
- Which requests are recorded is controlled by `DQL_REQUEST_HISTORY_QUALIFIERS`, for example failed requests and requests slower than a threshold. Setting this parameter replaces the whole qualifier object; see the [virtual collections documentation](https://docs.ditto.live/dql/virtual-collections) for the available qualifiers.
- On Small Peers, querying `system:active_requests` at exactly the right moment is often impractical; the slow-request warning (see [Long-running requests (SDK 5.1+)](../best-practices/indexing-and-performance.md#long-running-requests-sdk-51)) writes the same details to the log.

```dart
// ✅ GOOD: Collect a small diagnostics snapshot on demand.
Future<Map<String, Object?>> diagnosticsSnapshot(Ditto ditto) async {
  Future<List<Map<String, dynamic>>> rows(String query) async {
    final result = await ditto.store.execute(query);
    return result.items.map((item) => item.value).toList();
  }

  return {
    'core': await rows(
      "SELECT key, value FROM system:system_info "
      "WHERE namespace = 'core' AND key LIKE 'ditto_sdk%'",
    ),
    'nonDefaultParameters': await rows(
      "SELECT key, value FROM system:system_info "
      "WHERE key LIKE 'non_default_system_parameter%'",
    ),
    'syncConnections': await rows('SELECT * FROM system:data_sync_info'),
    // Documents that stopped syncing on this device (SDK 5.2+).
    'syncDegradations': await rows('SELECT * FROM system:sync_degradations'),
    'indexes': await rows('SELECT _id FROM system:indexes'),
    'activeRequests': await rows(
      'SELECT _id, text, state, times FROM system:active_requests',
    ),
  };
}
```

## System Parameters Reference

System parameters tune the behavior of the local Ditto instance. Set them when opening Ditto with `DittoConfig.systemParameters` (SDK 5.2+), read them with `SHOW`, and change them at run time with `ALTER SYSTEM`:

```sql
SHOW TOMBSTONE_TTL_HOURS

SHOW ALL LIKE 'dql_slow%'

ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 30

ALTER SYSTEM RESET DQL_SLOW_REQUEST_WARN_SECONDS
```

- `ALTER SYSTEM SET <name> = <value>` and `ALTER SYSTEM SET <name> TO <value>` are equivalent; `SET <name> TO DEFAULT` and `RESET <name>` restore the default (`RESET ALL` restores every parameter).
- `SHOW ALL` returns a single row with every parameter; `SHOW ALL LIKE '<pattern>'` (or `ILIKE`; SDK 5.1+) narrows it.
- Parameter names are case-insensitive (`DQL_STRICT_MODE` and `dql_strict_mode` are the same parameter).
- Unknown names fail with `unknown parameter '<name>'`, and values of the wrong type fail with a type error. In `DittoConfig.systemParameters`, the same mistakes make `Ditto.open()` fail.
- **Settings are not persisted.** After closing and reopening Ditto, every parameter is back at its default. Pass your settings in `DittoConfig.systemParameters` on every open (on SDK 5.1, run `ALTER SYSTEM` after every `Ditto.open`, before `ditto.sync.start()` and before queries or observers run); see [Applying System Parameters](../best-practices/setup-and-lifecycle.md#applying-system-parameters).

Parameters most relevant to app developers:

| Parameter | Default | Purpose | See |
|---|---|---|---|
| `DQL_STRICT_MODE` | `false` | When `true`, objects are treated as registers unless declared; in 5.1.0 and 5.2.0 the planner then does not use secondary indexes | [Strict Mode](../best-practices/data-modeling.md#strict-mode) |
| `DQL_RESTRICT_SUBSCRIPTIONS` | `true` | Rejects `LIMIT` and `ORDER BY` in subscription queries | [Subscription Rules](../best-practices/sync-and-subscriptions.md#subscription-rules) |
| `USER_COLLECTION_SYNC_SCOPES` | `{}` | Per-collection sync scopes; set before `ditto.sync.start()` | [Sync Scopes](../best-practices/sync-and-subscriptions.md#sync-scopes) |
| `TOMBSTONE_TTL_ENABLED` | `true` | Automatic removal of expired tombstones | [Tombstone TTL and reaping](../best-practices/deletion-and-storage.md#tombstone-ttl-and-reaping) |
| `TOMBSTONE_TTL_HOURS` | `168` | Tombstone TTL on this device (never above the Ditto Server TTL) | [Tombstone TTL and reaping](../best-practices/deletion-and-storage.md#tombstone-ttl-and-reaping) |
| `DAYS_BETWEEN_REAPING` | `1` | Days between tombstone reaping runs | [Tombstone TTL and reaping](../best-practices/deletion-and-storage.md#tombstone-ttl-and-reaping) |
| `TOMBSTONE_REAP_BATCH_SIZE` (SDK 5.1+) | `10000` | Batch size for removing expired tombstones | [Tombstone TTL and reaping](../best-practices/deletion-and-storage.md#tombstone-ttl-and-reaping) |
| `DISABLE_REPLICATION_GC_ON_EVICT` | `false` | Skips immediate per-peer metadata cleanup on eviction (advanced) | [Eviction frequency](../best-practices/deletion-and-storage.md#eviction-frequency) |
| `DQL_SLOW_REQUEST_WARN_SECONDS` (SDK 5.1+) | `60` | Warning log for requests running longer than this; `0` disables | [Long-running requests (SDK 5.1+)](../best-practices/indexing-and-performance.md#long-running-requests-sdk-51) |
| `DQL_REQUEST_TIMEOUT_SECONDS` (SDK 5.1+) | `0` | Request timeout in seconds; `0` disables | [Long-running requests (SDK 5.1+)](../best-practices/indexing-and-performance.md#long-running-requests-sdk-51) |
| `DQL_REQUEST_HISTORY_SIZE` | `128` (`4096` in 5.1) | Number of entries kept in `system:request_history` | [Request diagnostics](#request-diagnostics) |
| `DQL_DEFAULT_DIRECTIVES` | `{}` | Default directives for every statement | [Directives](../best-practices/indexing-and-performance.md#directives) |
| `DOCUMENT_SIZE_SOFT_LIMIT_BYTES` | `262144` (256 KiB) | Documents above this size log a warning | [Document Size Limits](../best-practices/data-modeling.md#document-size-limits) |
| `DOCUMENT_SIZE_HARD_LIMIT_BYTES` | `5242880` (5 MiB) | Writes that make a document larger than this fail | [Document Size Limits](../best-practices/data-modeling.md#document-size-limits) |
| `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED` (SDK 5.1+) | `true` | Certificate revocation checks for peer connections | [Certificate Revocation (SDK 5.1+)](../best-practices/security.md#certificate-revocation-sdk-51) |
| `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED` | `false` | Enables the `system:metrics` virtual collection; read only at startup (`DittoConfig.systemParameters` in SDK 5.2+, or the environment variable `DITTO_METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED`) | [System Virtual Collections](#system-virtual-collections) |
| `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` | `6` | Maximum number of LAN connections that a device accepts (TCP in our testing). On 5.2.0, connections that the device opened itself also count when it decides whether to accept another one; outgoing connections are not limited. Set it on a hub before `ditto.sync.start()` | [Transport Configuration](../best-practices/setup-and-lifecycle.md#transport-configuration) |
| `SUPPORT_BUNDLE_REQUEST_RATE` / `SUPPORT_BUNDLE_REQUEST_TIMEOUT` / `SUPPORT_BUNDLE_RETENTION_LIMIT` (SDK 5.2+) | `3` / `30` / `10` | Support bundle requests per 10 minutes, seconds per bundle, and bundles kept | [Support bundles (SDK 5.2+)](../best-practices/logging-and-observability.md#support-bundles-sdk-52) |
| `BACKEND_SQLITE3_WAL_SIZE_THRESHOLD_BYTES` (SDK 5.2+) | `1073741824` (1 GiB) | WAL size above which Ditto logs a warning | [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage) |
| `ROTATING_LOG_FILE_MAX_SIZE_MB` / `ROTATING_LOG_FILE_MAX_AGE_H` / `ROTATING_LOG_FILE_MAX_FILES_ON_DISK` | `1` / `24` / `15` | On-disk log rotation; leave at defaults unless Ditto support advises otherwise | [On-disk logs and exporting them](../best-practices/logging-and-observability.md#on-disk-logs-and-exporting-them) |

`SHOW ALL` lists several hundred parameters. Most of them are internal tuning parameters for transports, sync, and storage. Do not change parameters that are not documented for your use case without guidance from Ditto support.

### Applying parameters at startup

Because settings are not persisted, keep them in one place and pass them each time Ditto is opened. A compact way to verify the result is to read back the non-default parameters:

```dart
/// This app's system parameters, passed in DittoConfig.systemParameters on
/// every open (SDK 5.2+).
const appSystemParameters = <String, Object>{
  'DQL_SLOW_REQUEST_WARN_SECONDS': 30,
};

/// Logs the parameters that differ from their defaults, for example after
/// Ditto.open() in debug builds.
Future<void> logNonDefaultParameters(Ditto ditto) async {
  final result = await ditto.store.execute(
    "SELECT key, value FROM system:system_info "
    "WHERE key LIKE 'non_default_system_parameter%'",
  );
  for (final item in result.items) {
    debugPrint('${item.value['key']} = ${item.value['value']}');
  }
}
```

See [Applying System Parameters](../best-practices/setup-and-lifecycle.md#applying-system-parameters) for the complete startup sequence.
