# Configuration and Diagnostics

How Ditto's configuration behaves and what its diagnostics show: the defaults and validation of system parameters, environment variables that set them at startup, the expiry check of the offline license token, slow-request warnings, timeouts, and the request history, the diagnostic system collections, and what Ditto's logs contain. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Applying System Parameters](../../best-practices/setup-and-lifecycle.md#applying-system-parameters), [System Parameters Reference](../system-reference.md#system-parameters-reference), [Request diagnostics](../system-reference.md#request-diagnostics), [Long-running requests (SDK 5.1+)](../../best-practices/indexing-and-performance.md#long-running-requests-sdk-51), [Small-Peers-Only Deployments](../../best-practices/security.md#small-peers-only-deployments), and [On-disk logs and exporting them](../../best-practices/logging-and-observability.md#on-disk-logs-and-exporting-them).

**In brief**

- The parameter defaults in [System Parameters Reference](../system-reference.md#system-parameters-reference) match `SHOW ALL` on 5.2.0, and out-of-range values, unknown names, and values of the wrong type fail with an error ([The documented parameter defaults match SHOW ALL](#the-documented-parameter-defaults-match-show-all)).
- On 5.2.0, parameters passed in `DittoConfig.systemParameters` are in effect when `Ditto.open()` returns, and once one instance has enabled `system:metrics`, every later instance in the process has it too ([System parameters passed in DittoConfig take effect when Ditto.open returns](#system-parameters-passed-in-dittoconfig-take-effect-when-dittoopen-returns)).
- An environment variable `DITTO_<NAME>` sets a system parameter at startup on 5.0.3, 5.1.0, and 5.2.0; on 5.1, it is the only way to pass parameters that Ditto reads only at startup ([DITTO_ environment variables set system parameters at startup](#ditto_-environment-variables-set-system-parameters-at-startup)).
- Ditto reads the value of such a variable as JSON. A value that is not valid JSON, or that has the wrong type, is ignored with one log line, and Ditto starts with the default without any error in the app ([Environment variable values are read as JSON and ignored when invalid](#environment-variable-values-are-read-as-json-and-ignored-when-invalid)).
- The expiry of the offline license token is checked against the device clock when the token is set: a device whose clock runs past the expiry cannot start sync, while a running device kept syncing for the 10 seconds we watched after its clock passed the expiry ([The offline license token expiry is checked against the device clock](#the-offline-license-token-expiry-is-checked-against-the-device-clock)).
- The slow-request warning and the request timeout work on 5.1.0 and 5.2.0. With the default qualifiers, 5.2.0 records in `system:request_history` only queries of about 10 seconds or more, not 1 second as documented, and on both releases setting the qualifiers merges them into the current ones, while `RESET` leaves them in effect ([Slow-request warnings and request timeouts work as documented](#slow-request-warnings-and-request-timeouts-work-as-documented), [On SDK 5.2.0, the request history records queries of about 10 seconds or more by default](#on-sdk-520-the-request-history-records-queries-of-about-10-seconds-or-more-by-default), [Setting the request history qualifiers merges them, and RESET leaves them in effect](#setting-the-request-history-qualifiers-merges-them-and-reset-leaves-them-in-effect)).
- The queries of the diagnostics snapshot run on 5.1.0 and 5.2.0, except `system:sync_degradations`, which fails on 5.1.0, and on 5.2.0 a support bundle holds the logs, device metadata, and a configuration snapshot, with a rate limit on requests ([The diagnostics snapshot queries run on both releases, except system:sync_degradations on 5.1.0](#the-diagnostics-snapshot-queries-run-on-both-releases-except-systemsync_degradations-on-510), [A support bundle holds the logs, device metadata, and a configuration snapshot](#a-support-bundle-holds-the-logs-device-metadata-and-a-configuration-snapshot)).
- Exported logs contain debug lines at every console log level. On 5.2.0, the console log level hardly changed the write rate, but it changed the number of console log lines for 2,000 writes from 6 to about 83,000 ([Exported logs include debug lines regardless of the console level](#exported-logs-include-debug-lines-regardless-of-the-console-level)).
- Subscription queries and their argument values reach directly connected devices and appear in the on-disk logs of both devices; document values and `execute` statements did not appear ([Subscription queries and arguments appear in other devices' logs](#subscription-queries-and-arguments-appear-in-other-devices-logs)).

## System Parameter Defaults and Validation

### The documented parameter defaults match SHOW ALL

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | We took the name and the default of each parameter in the table of [System Parameters Reference](../system-reference.md#system-parameters-reference) (24 parameters with a default) and compared them with the values that `SHOW ALL` returned. We also set an out-of-range value, an unknown name, and a value of the wrong type with `ALTER SYSTEM SET`, and wrote a 500 KB document with different settings of `DOCUMENT_SIZE_SOFT_LIMIT_BYTES` and `DOCUMENT_SIZE_HARD_LIMIT_BYTES` |

| Release | Parameters in `SHOW ALL` | Compared with the 24 defaults in the table |
|---|---|---|
| 5.2.0 | 476 | All 24 matched |
| 5.1.0 | 388 | Only five differed: the four parameters marked (SDK 5.2+), which do not exist (`SUPPORT_BUNDLE_REQUEST_RATE`, `SUPPORT_BUNDLE_REQUEST_TIMEOUT`, `SUPPORT_BUNDLE_RETENTION_LIMIT`, and `BACKEND_SQLITE3_WAL_SIZE_THRESHOLD_BYTES`), and `DQL_REQUEST_HISTORY_SIZE`, whose default is `4096`, as the table states for 5.1 |
| 5.0.3 | 265 | In addition to the differences on 5.1.0, the four parameters marked (SDK 5.1+) do not exist either (`TOMBSTONE_REAP_BATCH_SIZE`, `DQL_SLOW_REQUEST_WARN_SECONDS`, `DQL_REQUEST_TIMEOUT_SECONDS`, and `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED`). The default of `DQL_REQUEST_HISTORY_SIZE` is `4096` here as well |

- **Validation**: on all three releases, `ALTER SYSTEM SET TOMBSTONE_TTL_HOURS = 0` failed with `parameter validation for tombstone_ttl_hours failed: value U64(0) is outside of acceptable range ...`, while `1` was accepted. `-1` failed with a type error. An unknown name failed with `unknown parameter 'not_a_real_parameter'`, and a value of the wrong type with `type error: value String("yes") doesn't match system parameter dql_strict_mode type of bool`.
- **Size limits**: with the hard limit lowered to 100,000 bytes, below a soft limit of 1,000,000 bytes, the 500 KB document could be written on 5.1.0 and 5.2.0: a hard limit set below the soft limit was not enforced. With the soft limit then lowered to 50,000 bytes, the same write failed with `exceeds limit of 100000 bytes`.
- On 5.0.3, the parameter `DOCUMENT_SIZE_HARD_LIMIT_BYTES` exists, but the 500 KB document could be written with every setting: 5.0.3 does not check the limit when a document is written (see [SDK 5.0.3 does not check the hard size limit when a document is written](documents-and-limits.md#sdk-503-does-not-check-the-hard-size-limit-when-a-document-is-written)).

**Used in:** [System Parameters Reference](../system-reference.md#system-parameters-reference), [Document Size Limits](../../best-practices/data-modeling.md#document-size-limits).

### System parameters passed in DittoConfig take effect when Ditto.open returns

| | |
|---|---|
| Observed on | JavaScript: SDK 5.2.0, two runs; SDK 5.1.0, two runs, for comparison. The `ALTER SYSTEM` case: 5.1.0 and 5.2.0, two runs each. Every case except `ALTER SYSTEM` again with Flutter, JavaScript, Kotlin, and Swift on SDK 5.2.0, three runs each; every run gave the same result |
| Setup | We opened Ditto with `DittoConfig.systemParameters` and read the parameters with `SHOW` right after `Ditto.open()` returned: `DQL_STRICT_MODE` set to `true`, the same with the lowercase name `dql_strict_mode`, an unknown name, a value of the wrong type, and `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED`, which Ditto reads only at startup. We also set that parameter with `ALTER SYSTEM` after `Ditto.open()`, and opened a second and a third instance in the same process without it. We repeated the cases, each in a new store, with Flutter (`ditto_live`) and Swift on macOS, Kotlin on the Android 16 emulator, and JavaScript on Node.js 24, with the store without parameters opened before the one with the metrics parameter. In Flutter, we also passed a `DateTime` as a value |
| Documentation | The SDK 5.2.0 release notes ("Apply System Parameters Before Ditto Starts") describe passing system parameters in `DittoConfig`, applied before Ditto starts, and `Ditto.open()` failing on an unknown name or a wrong type |

| Case | 5.2.0 | 5.1.0 |
|---|---|---|
| `DQL_STRICT_MODE: true` in the configuration | `true` when `Ditto.open()` returned | `false`: the configuration's parameters are not read |
| The lowercase name `dql_strict_mode` | `true`, like the uppercase name | `false` |
| An unknown name | `Ditto.open()` failed with `Invalid DittoConfig: unknown parameter 'not_a_real_parameter'` | Opened without an error |
| A value of the wrong type | `Ditto.open()` failed with `Invalid DittoConfig: type error: value String("yes") doesn't match system parameter dql_strict_mode type of bool` | Opened without an error |
| `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED: true` in the configuration | `system:metrics` was enabled (52 rows) | Still disabled |
| The same parameter set with `ALTER SYSTEM` after `Ditto.open()` | `system:metrics` stayed disabled | Stayed disabled |

On 5.2.0, every SDK gave the results of the 5.2.0 column: both names were in effect when the store opened, `system:metrics` had 52 rows with the metrics parameter and one row with `"status": "disabled"` without it, and an unknown name and a wrong type made opening fail with the messages above. Each SDK reported the failure with its own type:

| SDK | Unknown name or wrong type |
|---|---|
| Flutter | `Ditto.open()` threw `DittoException`; a `DateTime` value threw `ArgumentError: Invalid argument(s): Unsupported system parameter value type DateTime` |
| JavaScript | `Ditto.open()` rejected with `DittoError` |
| Kotlin | `DittoFactory.create` threw `DittoException.ValidationException` (`The provided DittoConfig is invalid: ...`) |
| Swift | `Ditto.open` threw `DittoError.validationError(reason: .invalidDittoConfig(message: ...))` |

- After one instance had enabled `system:metrics` through its configuration, a second instance opened in the same process without the parameter, and a third one opened after the first had closed, also had `system:metrics` enabled (57 rows each, 5.2.0). Once enabled at startup, the collection stays enabled for the rest of the process.

**Used in:** [Applying System Parameters](../../best-practices/setup-and-lifecycle.md#applying-system-parameters), [System Virtual Collections](../system-reference.md#system-virtual-collections), [DittoConfig in Flutter](../../best-practices/platforms/flutter.md#dittoconfig-in-flutter), [DittoConfig in JavaScript](../../best-practices/platforms/javascript.md#dittoconfig-in-javascript), [DittoConfig in Kotlin](../../best-practices/platforms/kotlin.md#dittoconfig-in-kotlin), [DittoConfig in Swift](../../best-practices/platforms/swift.md#dittoconfig-in-swift).

## System Parameters from Environment Variables

### DITTO_ environment variables set system parameters at startup

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, checked by hand with `SHOW ALL`, once on each release; our tests of tombstone reaping on 5.1.0 also pass their parameters this way. SDK 5.0.3: see the next entry (three runs on each of the three releases) |
| Setup | A peer started with the environment variables `DITTO_TOMBSTONE_TTL_HOURS=1` and `DITTO_REAPER_TIMING_RANDOM_VARIATION_SECONDS=0`, and we read the values with `SHOW ALL`. Our test scripts also set `DITTO_SDK` and `DITTO_LOG_LEVEL` for their own use; these names are not system parameters |

- On 5.1.0 and on 5.2.0, `SHOW ALL` showed the values `1` and `0`. 5.1.0 does not read `DittoConfig.systemParameters`, so on 5.1.0 environment variables are the only way to pass parameters at startup.
- 5.0.3 reads them as well. On all three releases, Ditto reads the values as JSON and ignores a value that is not valid JSON or has the wrong type (see the next entry, [Environment variable values are read as JSON and ignored when invalid](#environment-variable-values-are-read-as-json-and-ignored-when-invalid)).
- A `DITTO_` variable that is not a system parameter logs a line at every start, here for `DITTO_SDK`: `WARN ditto_configuration: The Ditto environment variable sdk is set, but it is not a known system parameter, so it is being ignored for the purposes of ALTER SYSTEM configuration.` An app that uses `DITTO_` names for its own settings gets this warning; it does no harm.

**Used in:** [Applying System Parameters](../../best-practices/setup-and-lifecycle.md#applying-system-parameters), [Tombstone TTL and reaping](../../best-practices/deletion-and-storage.md#tombstone-ttl-and-reaping).

### Environment variable values are read as JSON and ignored when invalid

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; all nine runs gave the same results, and only the wording of the log lines and the handling of lowercase names differed between releases. The `DittoConfig.systemParameters` case at the end: SDK 5.2.0, three runs |
| Setup | For each value, a separate process set the environment variable `DITTO_<NAME>` and opened a peer. We read the parameter with `SHOW` and looked for the log lines about it |

| Value | Examples | Result |
|---|---|---|
| Valid JSON of the parameter's type | `true`, `24`, `{"threshold": 500}` (a map), `[{"address": "tcp://127.0.0.1:1", "type": "candidate"}]` (a list), a string with its quotes, such as `"127.0.0.1:9100"` | Applied, with an `INFO` line `system parameter default overridden parameter_name="..." default_value=... value=...` |
| Not valid JSON | a string without quotes (`127.0.0.1:9100`), `TRUE`, an empty value | Ignored with one `ERROR` line; the parameter kept its default |
| Valid JSON, but of the wrong type or out of range | `1` for a boolean parameter, `"24"`, `24.5`, `0` (`TOMBSTONE_TTL_HOURS` must be 1 or more) | Ignored with a `WARN` line; the parameter kept its default |

- **Log lines**: the `ERROR` line was `The Ditto system parameter environment variable <name> is set, but it could not be parsed as a JSON value, so it is being ignored!` on 5.1.0 and 5.2.0, and `error while resolving parameter <name> error=failed to deserialize value: ...` on 5.0.3. A `WARN` line was, for example, `the value is not valid for dql_strict_mode error=type error: value U64(1) doesn't match system parameter dql_strict_mode type of bool`. At the console log level of our tests (Error), the `WARN` lines do not appear on the console; they are kept in the on-disk logs (see [Exported logs include debug lines regardless of the console level](#exported-logs-include-debug-lines-regardless-of-the-console-level)).
- In every case, the store opened and accepted writes. No error reached the app.
- A lowercase name, `DITTO_tombstone_ttl_hours=24`, took effect on 5.1.0 and 5.2.0. 5.0.3 ignored it without a log line.
- `DITTO_METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED=true` works because `true`, as written, is valid JSON; the same holds for numbers. What does not work when written as usual in a shell: values of string parameters, whose quotes must be part of the value (`DITTO_<NAME>='"value"'`), and booleans written as uppercase `TRUE` or as `1`.
- `DittoConfig.systemParameters` (SDK 5.2+) takes values as they are, so a string value needs no quotes inside it: a string parameter passed as `'127.0.0.1:47990'` took effect.

**Used in:** [Applying System Parameters](../../best-practices/setup-and-lifecycle.md#applying-system-parameters), [System Virtual Collections](../system-reference.md#system-virtual-collections).

## Offline License Token Expiry

### The offline license token expiry is checked against the device clock

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; the results were the same on both releases. Which calls fail was checked by hand, once on each release |
| Setup | Peers in small-peers-only mode whose clocks were shifted (see [How We Tested](how-we-tested.md#test-environment)): 30 days and 1 year ahead, and 1 day and 1 year behind. Each peer opened Ditto, set our offline license token with `setOfflineOnlyLicenseToken`, started sync, and synced with another peer. Our token had about two months left before its expiry. In one more case, the clock of a running device that was already syncing jumped 1 year ahead |

- **Clock 1 year ahead**: `setOfflineOnlyLicenseToken` threw `activation/license-token-expired` (`The license expired on <expiry> UTC`), and `sync.start()` failed with `Sync could not be started because Ditto has not yet been activated`. `Ditto.open` and local reads and writes worked.
- **Clock 30 days ahead**: the device could sync, because our token had about two months left.
- **Clock 1 day or 1 year behind**: the device could set the token and sync. The check therefore probably does not look at when the token's validity starts, or the start lies far enough back.
- **Clock of a running device jumped 1 year ahead**: sync continued in both directions for the 10 seconds we watched, and no log line at warning level or above mentioned the license. As far as these 10 seconds show, the expiry is checked only when the token is set.
- A device whose clock was behind took a little longer from `Ditto.open` until it synced: 0.33 to 1.24 seconds, against 0.22 seconds for a device with a correct clock. This makes no practical difference.

**Used in:** [Small-Peers-Only Deployments](../../best-practices/security.md#small-peers-only-deployments).

## Slow Requests and Diagnostic Queries

### Slow-request warnings and request timeouts work as documented

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each, in two separate tests that showed the same behavior |
| Setup | A join without an index (`JOIN ... USE INDEX ''`) of 3,000 by 3,000 documents, which took about 8 seconds on 5.2.0 and about 11 seconds on 5.1.0. We set `DQL_SLOW_REQUEST_WARN_SECONDS` and `DQL_REQUEST_TIMEOUT_SECONDS`, and read the log |
| Documentation | The SDK 5.1 release notes say that `DQL_SLOW_REQUEST_WARN_SECONDS` (default `60`) logs the request details at the threshold and repeats while the request runs, that `DQL_REQUEST_TIMEOUT_SECONDS` (default `0`) cooperatively cancels requests that exceed the limit, and that `0` disables either |

- **Slow-request warning**: with `DQL_SLOW_REQUEST_WARN_SECONDS = 1`, a warning `Slow DQL request dump entry="{...}"` was logged every second while the query ran: 8 times on 5.2.0 and 11 times on 5.1.0. The entry is JSON with `_id`, `directives`, the `plan` with `#stats`, and more.
- **Timeout**: with `DQL_REQUEST_TIMEOUT_SECONDS = 1`, the query failed after 1.00 seconds with `Request exceeded maximum permitted execution time.`

**Used in:** [Long-running requests (SDK 5.1+)](../../best-practices/indexing-and-performance.md#long-running-requests-sdk-51).

### On SDK 5.2.0, the request history records queries of about 10 seconds or more by default

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result. Earlier runs: one on each release with joins of about 2 and 8 to 11 seconds, and two more on 5.2.0 |
| Setup | One device without sync, with the default `DQL_REQUEST_HISTORY_QUALIFIERS`. Joins that scan the inner collection (`USE INDEX ''`, `SELECT COUNT(*)`) over pairs of collections of 1,500, 2,600, 2,900, 3,000, 3,100, and 3,300 documents each, run one after another, each after `DELETE FROM system:request_history`. We timed each join and read whether `system:request_history` held it. We also ran a failing statement and a lookup by ID |
| Documentation | The [virtual collections documentation](https://docs.ditto.live/dql/virtual-collections) (Qualifiers) says that the `threshold` qualifier, "the total execution time in milliseconds", "is set by default to 1000 (1 second) and is always active", that `failed` and `system_delete` are `true` by default, and that `mutation` is `false` by default |

| Join | 5.1.0 | 5.2.0 |
|---|---|---|
| 1,500 × 1,500 | 3.1 s, recorded | 2.7 to 2.8 s, **not recorded** |
| 2,600 × 2,600 | 9.1 to 9.4 s, recorded | 7.8 to 8.5 s, **not recorded** |
| 2,900 × 2,900 | 11.5 to 11.9 s, recorded | 10.1 to 10.6 s, recorded |
| 3,000 × 3,000 and larger | 11.9 to 14.7 s, recorded | 10.1 to 13.3 s, recorded |

- `DQL_REQUEST_HISTORY_QUALIFIERS` is `{}` by default on both releases.
- **5.1.0** with the default setting recorded every join, with `~qualifier: "threshold"`, as a threshold of 1 second would.
- **5.2.0 with the default setting recorded the joins that took 10.1 seconds or more, and none that took 8.5 seconds or less.** In the earlier runs on 5.2.0, joins of 1.9, 2.7, 2.8, 5.7, 7.8, 8, and 9.9 seconds were not recorded, and joins of 10.5 and 12.0 seconds were. The default threshold of 5.2.0 therefore lies between 9.9 and 10.1 seconds, probably 10 seconds, instead of the documented 1 second. The `times.elapsed` that the history recorded for a join (in nanoseconds, with `{'threshold': 0}`) matched the time we measured.
- With `{'threshold': 1000}` set, 5.2.0 recorded a join of 2.8 seconds, and with `{'threshold': 500}` one of 1.9 seconds (earlier runs).
- On both releases, the failing statement was recorded with `failed` and the lookup by ID was not recorded. On 5.2.0, `DELETE FROM system:request_history` was recorded with `system_delete` (not checked on 5.1.0).

**Not tested:** a threshold between 1 and 3 seconds on 5.1.0; Ditto Server; SDKs other than JavaScript.

**Used in:** [Request diagnostics](../system-reference.md#request-diagnostics), [Changes in SDK 5.2.0](../upgrading.md#changes-in-sdk-520).

### Setting the request history qualifiers merges them, and RESET leaves them in effect

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, three runs each; every run gave the same result |
| Setup | One device without sync. Starting from the default, we set `DQL_REQUEST_HISTORY_QUALIFIERS` with `ALTER SYSTEM SET` to `{'threshold': 0}`, then `{'mutation': true}`, then `{'failed': false}`, then `{}`. After each step we read `SHOW DQL_REQUEST_HISTORY_QUALIFIERS`, cleared `system:request_history`, and checked which qualifier recorded a lookup by ID, a failing statement, and an `INSERT`. In a new store, we set `{'threshold': 0, 'mutation': true}`, ran `ALTER SYSTEM RESET DQL_REQUEST_HISTORY_QUALIFIERS`, and checked the same |
| Documentation | The [virtual collections documentation](https://docs.ditto.live/dql/virtual-collections): "Qualifiers not included in the object are removed (or reset)." The [ALTER SYSTEM documentation](https://docs.ditto.live/dql/alter-system): `RESET` resets a parameter "to its default value" |

| Step | `SHOW` | Lookup by ID | Failing statement | `INSERT` |
|---|---|---|---|---|
| Default | `{}` | not recorded | `failed` | not recorded |
| `{'threshold': 0}` | `{"threshold": 0}` | `threshold` | `failed` | `threshold` |
| then `{'mutation': true}` | `{"mutation": true, "threshold": 0}` | `threshold` | `failed` | `mutation` |
| then `{'failed': false}` | `{"failed": false, "mutation": true, "threshold": 0}` | `threshold` | `threshold` | `mutation` |
| then `{}` | unchanged | unchanged | unchanged | unchanged |
| `RESET` after `{'threshold': 0, 'mutation': true}` | `{}` | `threshold` | `failed` | `mutation` |

- On both releases, `ALTER SYSTEM SET` merged the new qualifiers into the current ones: a qualifier that the new value did not name kept its value, and `{}` changed nothing. This differs from the documentation, which says that qualifiers not in the object are removed or reset.
- After `ALTER SYSTEM RESET`, `SHOW` reported `{}`, but the qualifiers set before stayed in effect: every statement was still recorded, also 5 seconds and 20 statements later, and after `ALTER SYSTEM RESET ALL` (three more runs on each release). Only a value that names a qualifier changed it.
- Naming the qualifiers again restored them: after `{'threshold': 0, 'mutation': true}`, setting `{'threshold': 1000, 'mutation': false}` made `SHOW` report those values, and neither the lookup by ID nor the `INSERT` was recorded any longer (three more runs on each release).

**Not tested:** the qualifiers passed in `DittoConfig.systemParameters`; whether closing and reopening Ditto restores the defaults (system parameters are not persisted); SDKs other than JavaScript.

**Used in:** [Request diagnostics](../system-reference.md#request-diagnostics).

### The diagnostics snapshot queries run on both releases, except system:sync_degradations on 5.1.0

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each |
| Setup | We ran the queries of the `diagnosticsSnapshot()` example in [Request diagnostics](../system-reference.md#request-diagnostics) on a store in which `TOMBSTONE_TTL_HOURS` was set to 200 |

- The `ditto_sdk%` keys of `system:system_info` returned four rows: commit, language, platform, and version.
- The `non_default_system_parameter%` keys returned a row for each parameter set to a value other than its default: `non_default_system_parameter[tombstone_ttl_hours]: 200`.
- `system:active_requests` returned one row, for the query itself, with `elapsed`, `parse`, `plan`, and `start` in `times`.
- `system:sync_degradations` failed on 5.1.0 with `Unsupported feature`.
- The namespaces in `system:system_info` were `backend_sqlite3`, `core`, `logs`, `replication`, and `sync_scopes`. 5.2.0 has three more keys for the write-ahead log (WAL).

**Used in:** [Request diagnostics](../system-reference.md#request-diagnostics), [system:system_info](../system-reference.md#systemsystem_info).

### A support bundle holds the logs, device metadata, and a configuration snapshot

| | |
|---|---|
| Observed on | SDK 5.2.0, two runs; SDK 5.1.0, two runs, for comparison |
| Setup | We requested a support bundle with `EXECUTE FUNCTION system_request_support_bundle()`, listed `system:support_bundles`, fetched the archive with `fetchAttachment()`, and listed its files. With `support_bundle_request_rate` set to 1, we requested a second bundle right after the first |
| Documentation | The SDK 5.2.0 release notes ("Generate and query support bundles with DQL") introduce the function, and Ditto's documentation on capturing support bundles describes the rate limit |

- On 5.2.0, the function returned a document with `reason` `USER_INITIATED` and an `_id` with the keys `created_at` and `pk`; `system:support_bundles` listed one bundle; and the archive, 30,720 bytes, contained `ditto-logs.log.gz` (2,749 bytes), `device_logs_METADATA.json` (81 bytes), and `config_snapshot.json` (24,254 bytes).
- With the rate limit at 1, the second request failed with `support bundle request rate exceeded: at most 1 requests are allowed per 10 minutes; retry in 600 seconds`.
- On 5.1.0, the function does not exist: `unknown function 'system_request_support_bundle'`.

**Used in:** [Support bundles (SDK 5.2+)](../../best-practices/logging-and-observability.md#support-bundles-sdk-52).

## Log Export and Log Contents

### Exported logs include debug lines regardless of the console level

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; the results were the same on all three. The log volume per console level: SDK 5.2.0 only, two runs per level |
| Setup | With the console log level set to Error, the app wrote a line with `Logger.debug()`, and we exported the on-disk logs with the JavaScript SDK's `Logger.exportToFile(path)`. For the log volume, one of two devices wrote 2,000 documents one at a time, and we measured the time until all of them had reached the other device, at the console log levels `Error`, `Info`, `Debug`, and `Verbose`, with the console output written to a file |

- The exported file contained `DEBUG` and `INFO` lines (41 and 18 on 5.2.0), although the console level was Error, including the line that the app had written with `Logger.debug()`. `exportToFile` returned a size of about 2.7 KB.
- Each line has the fields `timestamp`, `level`, `message`, `target`, `span`, `spans`, and `threadId`.
- An export to an existing file fails with `File exists (os error 17)`, and an export to a directory that does not exist with `No such file or directory (os error 2)`.
- **Log volume**: the console log level hardly affected the write rate. The 2,000 writes reached the other device in about 3.15 to 3.24 seconds at every level, while the number of log lines differed a lot:

| Console log level | Log lines for 2,000 writes |
|---|---|
| `Error` | 6 |
| `Info` | 154 |
| `Debug` | About 76,000 (about 38 per write) |
| `Verbose` | About 83,000 |

- This suggests that a production app that keeps `Debug` logging pays mainly in storage for the log output and in the amount of log data it sends, rather than in speed.

**Used in:** [On-disk logs and exporting them](../../best-practices/logging-and-observability.md#on-disk-logs-and-exporting-them), [Configuring logging](../../best-practices/logging-and-observability.md#configuring-logging), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### Subscription queries and arguments appear in other devices' logs

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0: three runs each with a hub and two clients, and one run each with two devices only; the results were the same on all three releases. The comparison of console log levels (Error, Info, Debug, and Verbose): one run with two devices in one process |
| Setup | A hub and two clients that connected to it, each in its own process. The first client subscribed with `SELECT * FROM people WHERE email = :email`, with an email address as the argument, and with a string written directly into the query (`WHERE owner = '...'`). The test also used observers with arguments, `store.execute` statements with literal strings and with arguments, an `INSERT` that failed, one small document that synced, and peer metadata. We searched the on-disk logs of every device, and the exported log files, for these values |

- The query text and the argument value appeared in the client's own on-disk logs (1 to 3 lines) and in the logs of the hub it was connected to (2 to 5 lines). A string written directly into the query appeared in the same way. All of these were replication lines (`outbound_cycle` and `inbound_cycle`) of the form `Statement { statement: "SELECT ...", parameters: ParametersDto({"email": String("...")}) }`.
- They appeared also with the console log level set to Error, because the on-disk logs always contain debug lines and above (see [Exported logs include debug lines regardless of the console level](#exported-logs-include-debug-lines-regardless-of-the-console-level)). With Error, Info, and Debug, the exported file contained the same number of them.
- They did not appear in the logs of the second client, which was connected only to the hub, two hops from the first client. That device's presence graph did show the first client's peer metadata: peer metadata reaches the whole mesh.
- These values appeared in no device's logs: the arguments of observer queries, document IDs and field values (also after sync), literal strings and arguments of `store.execute` statements, the arguments of the failed `INSERT`, and peer metadata values. The console output at Debug and Verbose did not contain document values or `store.execute` statements either (one run on 5.1.0 and on 5.2.0).
- The exception message of an `INSERT` that failed because of an ID conflict contains the document ID (`Identifier conflict on document "<ID>"`). An app that sends exception messages to its own logs or crash reports sends the ID there as well.
- A string written directly into a subscription query is also stored, apart from the logs, in the device's `ditto_system_info/db.sql` (see [After close(), a small store keeps its values in the write-ahead log](persistence-directory.md#after-close-a-small-store-keeps-its-values-in-the-write-ahead-log); checked on one device).
- The on-disk logs are kept for about 15 days or up to about 15 MB (see [On-disk logs and exporting them](../../best-practices/logging-and-observability.md#on-disk-logs-and-exporting-them)), so the arguments of a subscription probably stay on both devices for some time after the subscription is cancelled.

**Not tested:** more than one small document and about 3 seconds of activity, such as a large sync; the log lines of other kinds of errors; how long the values stay in the logs after a subscription is cancelled; whether argument values are also stored in `ditto_system_info/db.sql`; SDKs other than JavaScript and operating systems other than macOS.

**Used in:** [On-disk logs and exporting them](../../best-practices/logging-and-observability.md#on-disk-logs-and-exporting-them), [Input Validation and Query Parameters](../../best-practices/security.md#input-validation-and-query-parameters).
