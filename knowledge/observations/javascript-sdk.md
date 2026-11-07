# JavaScript SDK Behavior

What we observed when we ran the JavaScript SDK (`@dittolive/ditto`) where its API or behavior is specific to it: configuration, authentication, how statements and values fail, how queries use the Node.js event loop, observers and their handles, transactions, closing, attachment fetches, and logging. Every entry ran on Node.js 24 on one Mac; browsers and React Native were not tested. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Ditto on JavaScript](../../best-practices/platforms/javascript.md).

**In brief**

- The named `new DittoConfig({ ... })` form needs SDK 5.2; on 5.1.0 it throws a `TypeError`. On macOS, enabling every peer-to-peer transport makes the transport configuration invalid, because Node.js does not support Wi-Fi Aware there ([In JavaScript, the named DittoConfig form throws on SDK 5.1.0](#in-javascript-the-named-dittoconfig-form-throws-on-sdk-510), [In JavaScript on macOS, enabling every peer-to-peer transport makes the transport configuration invalid](#in-javascript-on-macos-enabling-every-peer-to-peer-transport-makes-the-transport-configuration-invalid)).
- The SDK catches what the expiration handler throws and only logs it, `logout()` does not wait for its cleanup function, and `close()` waits for an expiration handler that is still running ([In JavaScript, an error thrown by the expiration handler is only logged](#in-javascript-an-error-thrown-by-the-expiration-handler-is-only-logged), [In JavaScript, logout() does not wait for its cleanup function](#in-javascript-logout-does-not-wait-for-its-cleanup-function), [In JavaScript, close() waits for a running expiration handler](#in-javascript-close-waits-for-a-running-expiration-handler)).
- Invalid statements and arguments fail with a `DittoError` when the call is made: `execute` rejects and registrations throw. Function, `Symbol`, and `Set` values are stored as empty objects without an error ([In JavaScript, invalid statements and arguments fail with a DittoError when the call is made](#in-javascript-invalid-statements-and-arguments-fail-with-a-dittoerror-when-the-call-is-made), [In JavaScript, function, Symbol, and Set values are stored as empty objects](#in-javascript-function-symbol-and-set-values-are-stored-as-empty-objects)).
- On Node.js, a query is evaluated off the event loop, but a large result and its values block it ([In JavaScript on Node.js, queries run off the event loop, but large results block it](#in-javascript-on-nodejs-queries-run-off-the-event-loop-but-large-results-block-it)).
- On a device connected to another peer, a read of `system:data_sync_info` can stop responding, and then later reads of it, an observer of it, and `close()` hang as well ([In JavaScript, a read of system:data_sync_info can stop responding](#in-javascript-a-read-of-systemdata_sync_info-can-stop-responding)).
- An `async` observer callback that rejects causes an unhandled rejection, which ends a Node.js process by default; `using` cancels observers and subscriptions; `isStopped` of the generic `Observer` is inverted ([In JavaScript, an async observer callback that rejects causes an unhandled rejection](#in-javascript-an-async-observer-callback-that-rejects-causes-an-unhandled-rejection), [In JavaScript, using cancels observers and subscriptions at the end of the block](#in-javascript-using-cancels-observers-and-subscriptions-at-the-end-of-the-block), [In JavaScript, Observer.isStopped is true while the observer is active](#in-javascript-observerisstopped-is-true-while-the-observer-is-active)).
- A read-write transaction started inside another one waits until the outer one ends; an error caught inside a transaction callback does not roll it back; calls after `close()` fail with a plain `Error` ([In JavaScript, a read-write transaction started inside another one waits until the outer one ends](#in-javascript-a-read-write-transaction-started-inside-another-one-waits-until-the-outer-one-ends), [In JavaScript, an error caught inside a transaction callback does not roll back the transaction](#in-javascript-an-error-caught-inside-a-transaction-callback-does-not-roll-back-the-transaction), [In JavaScript, calls after close() throw or reject with a plain Error](#in-javascript-calls-after-close-throw-or-reject-with-a-plain-error)).
- The custom log callback stays installed after `close()` ([In JavaScript, the custom log callback stays installed after close()](#in-javascript-the-custom-log-callback-stays-installed-after-close)).
- Values that are not plain JSON change when stored: a `Date` becomes `{}`, `undefined` becomes `null`, `NaN` and `Infinity` fail, and integers above 2^53 − 1 come back as `BigInt` ([JavaScript values that are not plain JSON change when stored](#javascript-values-that-are-not-plain-json-change-when-stored)).
- Opening a directory that the process already has open fails after about 1 second ([In JavaScript, opening an open directory again fails](#in-javascript-opening-an-open-directory-again-fails)).
- `registerObserver` does not await `async` callbacks, so they overlap and can finish out of order; synchronous exceptions in callbacks are discarded; garbage collection stops neither observers nor subscriptions ([In JavaScript, registerObserver does not await async callbacks](#in-javascript-registerobserver-does-not-await-async-callbacks), [In JavaScript, exceptions thrown synchronously in observer callbacks are discarded](#in-javascript-exceptions-thrown-synchronously-in-observer-callbacks-are-discarded), [In JavaScript, garbage-collected subscriptions and observers keep running](#in-javascript-garbage-collected-subscriptions-and-observers-keep-running)).
- Query results return the same objects on every read, so changes to them stay in the object but never reach the store; `store.observers` lists other objects than the ones that the registration returned; the `Differ` reports every item whose position shifted as a move; a subscription registered without arguments has no `queryArguments` ([In JavaScript, query results return the same objects](#in-javascript-query-results-return-the-same-objects), [In JavaScript, store.observers exists since 5.0 and lists other objects](#in-javascript-storeobservers-exists-since-50-and-lists-other-objects), [The JavaScript Differ reports every shifted item as a move](#the-javascript-differ-reports-every-shifted-item-as-a-move), [In JavaScript, a subscription without arguments has no queryArguments](#in-javascript-a-subscription-without-arguments-has-no-queryarguments)).
- A write through `store.execute` inside a transaction never completes, a `tx.execute` that is not awaited is not applied, and a Node.js script that keeps neither sync nor a timer running ends with a panic while it awaits a transaction ([In JavaScript, store.execute writes inside a transaction deadlock](#in-javascript-storeexecute-writes-inside-a-transaction-deadlock), [A tx.execute that is not awaited is not applied](#a-txexecute-that-is-not-awaited-is-not-applied), [A Node.js script that keeps neither sync nor a timer running ends with a panic while awaiting a transaction](#a-nodejs-script-that-keeps-neither-sync-nor-a-timer-running-ends-with-a-panic-while-awaiting-a-transaction)).
- `close()` waits for open transactions and completes pending writes, but does not wait until changes have been sent to other devices ([In JavaScript, close() waits for open transactions](#in-javascript-close-waits-for-open-transactions), [In JavaScript, close() completes pending writes](#in-javascript-close-completes-pending-writes)).
- `fetchAttachment` with a token that the store did not receive in a document by sync fails at once: a `Deleted` event and `store/attachment-not-found`, also when the holder is connected, and `store/attachment-token-invalid` or an exception for a value that is not a token. With a synced token whose holder is offline, it waits without an event ([In JavaScript, fetchAttachment fails at once for a token that the store did not receive by sync](#in-javascript-fetchattachment-fails-at-once-for-a-token-that-the-store-did-not-receive-by-sync)).

## JavaScript Configuration

### In JavaScript, the named DittoConfig form throws on SDK 5.1.0

| | |
|---|---|
| Observed on | SDK 5.1.0, four runs; SDK 5.2.0, five runs; every run gave the same result |
| Setup | `new DittoConfig({ databaseID, connect: { mode: 'smallPeersOnly' } })` |
| Documentation | The SDK 5.2.0 type definitions add the constructor `new DittoConfig(options)` next to the positional `new DittoConfig(id, connect, persistenceDirectory)`, and `systemParameters` only as an option of the named form |

- On 5.2.0, the configuration was created, and a store opened with it.
- On 5.1.0, the constructor threw `TypeError: Expected id to be a string, but got: object`.

**Used in:** [DittoConfig in JavaScript](../../best-practices/platforms/javascript.md#dittoconfig-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript on macOS, enabling every peer-to-peer transport makes the transport configuration invalid

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, three runs each; every run gave the same result, on both releases |
| Setup | One device on Node.js on macOS: `ditto.updateTransportConfig((c) => c.setAllPeerToPeerEnabled(true))`, then `setAvailablePeerToPeerEnabled(true)` instead |
| Documentation | The type definitions say that `setAllPeerToPeerEnabled()` enables every peer-to-peer transport "regardless of whether the current platform can actually drive those transport implementations", and `setAvailablePeerToPeerEnabled()` only those that the platform supports |

- `setAllPeerToPeerEnabled(true)` made `updateTransportConfig()` throw `Expected valid TransportConfig. Invalid config: The following P2P transports are enabled in the transport config but are not supported in the current environment: WiFi Aware`. The error is a `DittoFFIError`, an internal class, not a `DittoError`.
- `setAvailablePeerToPeerEnabled(true)` enabled Bluetooth LE, LAN, and AWDL, and left Wi-Fi Aware disabled.

**Not tested:** Linux and Windows; browsers, where only WebSocket is used.

**Used in:** [Transports and Presence in JavaScript](../../best-practices/platforms/javascript.md#transports-and-presence-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, opening an open directory again fails

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; again on SDK 5.1.0 (three runs) and 5.2.0 (four runs), with times |
| Setup | In one process, we called `Ditto.open()` (and, in the later runs, `Ditto.openSync()`) a second time on a directory that was already open, and again after `close()` of the first instance had completed |

- The second `Ditto.open()` failed with a `DittoError` with code `store/persistence-directory-locked` and the message `File already locked, working dir = ..., retried 5 times. Multiple Ditto instances cannot run at the same time within the same working directory.` In the later runs, it failed after 1.02 to 1.04 seconds, on both releases.
- `Ditto.openSync()` on the open directory threw the same `DittoError` after 1.02 to 1.03 seconds, blocking the thread for that time.
- After `close()` had completed, the directory opened, in 0.02 to 0.03 seconds.

**Used in:** [One instance per persistence directory](../../best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory), [One shared instance in JavaScript](../../best-practices/platforms/javascript.md#one-shared-instance-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

## JavaScript Authentication

### In JavaScript, an error thrown by the expiration handler is only logged

| | |
|---|---|
| Observed on | SDK 5.2.0, ten runs; SDK 5.1.0, three runs; every run gave the same result |
| Setup | One device with a server connection to `http://127.0.0.1:9`, where nothing listens. An `async` expiration handler that threw (in seven of the 5.2.0 runs, after calling `login()`), with a custom log callback and an `unhandledRejection` listener; then `sync.start()` |
| Documentation | The SDK 5.2.0 source wraps the handler in `try`/`catch` and logs `The authentication handler set via ditto.auth.setExpirationHandler() failed: <message>` at the Error level |

- `setExpirationHandler()` did not call the handler. After `sync.start()`, it was called once, with `0` seconds remaining.
- `login()` with the unreachable server resolved to `{ clientInfo: null, error }`, where `error` is a `DittoError` with code `authentication/failed-to-authenticate` and the message `Ditto failed to authenticate.`; it did not throw.
- The error that the handler threw produced the Error-level log line `The authentication handler set via ditto.auth.setExpirationHandler() failed: thrown by the handler`, and no unhandled rejection. Nothing else reported it.
- Without an expiration handler, `sync.start()` threw a `DittoError` with code `authentication/expiration-handler-missing`.

**Not tested:** a real Ditto Server and authentication webhook; a handler that throws before it awaits anything.

**Used in:** [Authentication in JavaScript](../../best-practices/platforms/javascript.md#authentication-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, logout() does not wait for its cleanup function

| | |
|---|---|
| Observed on | SDK 5.2.0, ten runs; SDK 5.1.0, three runs; every run gave the same result. The rejecting cleanup: three runs each |
| Setup | One device with a server connection. `await ditto.auth.logout(cleanup)` with an `async` cleanup function that waited 300 ms; then the same with a cleanup function that rejected, while the process counted unhandled rejections. On a small-peers-only device: `logout()` with a synchronous cleanup |
| Documentation | The SDK 5.2.0 source calls `cleanupFn?.(ditto)` after stopping sync, without awaiting it; the type definitions declare the cleanup as `(ditto: Ditto) => void` |

- The recorded order was "cleanup started", "logout resolved", "cleanup finished": `logout()` resolved while the cleanup was still running.
- The cleanup that rejected caused one unhandled rejection.
- After `logout()`, sync was stopped, and an `EVICT` statement still ran (5.2.0, seven runs).
- On a small-peers-only device, `logout()` resolved and called the cleanup function (5.2.0, seven runs).

**Used in:** [Authentication in JavaScript](../../best-practices/platforms/javascript.md#authentication-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, close() waits for a running expiration handler

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, three runs each; every run gave the same result |
| Setup | One device with a server connection to an address where nothing listens. An expiration handler that waited for a promise that the test resolved later. After the handler had started, `sync.stop()` and `close()`; 2 seconds later, the test resolved the promise |
| Documentation | The SDK 5.2.0 source runs the handler inside `deferCloseAsync`, the mechanism that makes `close()` wait for pending operations |

- `close()` had not completed after 2 seconds while the handler was waiting. It completed 0.03 to 0.06 seconds after the handler finished.

**Not tested:** a handler that never finishes, which presumably keeps `close()` from completing.

**Used in:** [Authentication in JavaScript](../../best-practices/platforms/javascript.md#authentication-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

## JavaScript Queries and Values

### In JavaScript, invalid statements and arguments fail with a DittoError when the call is made

| | |
|---|---|
| Observed on | SDK 5.2.0, three runs; SDK 5.1.0, two runs; every run gave the same result, on both releases |
| Setup | One device without sync, with one document `{_id: 'a', n: 1}`. Each of ten statements was passed to `store.execute`, `store.registerObserver`, and `sync.registerSubscription`: a syntax error (`SELEC * FROM t`), an unknown function, `n + 'a'`, a placeholder without an argument, an argument that the statement does not use, `NaN`, a function, and a `Symbol` as the argument, an `UPDATE`, and an empty string. Observers and subscriptions that were accepted were checked again 1 second later. Separately, an oversized `UPDATE` (5,300,000 characters, 5.2.0) |
| Documentation | The type definitions list `query/invalid` for invalid DQL, `query/arguments-invalid` for invalid arguments, and `query/unsupported` for a non-`SELECT` query in an observer or a subscription |

| Statement | `store.execute` | `registerObserver` | `registerSubscription` |
|---|---|---|---|
| Syntax error | Rejected, `query/invalid` | Threw, `query/invalid` | Threw, `query/invalid` |
| Unknown function | Rejected, `query/invalid` (`Function "nosuchfunction" not found`) | Threw, `query/invalid` | Threw, `query/unsupported` (`A projection other than wildcard (*)`) |
| `SELECT n + 'a' AS x` | Resolved, one row without `x` | Accepted | Threw, `query/unsupported` (`A projection other than wildcard (*)`) |
| Placeholder without an argument | Rejected, `query/invalid` (`Parameter missing was not provided`) | Threw, `query/invalid` | Threw, `query/invalid` |
| Unused argument | Resolved | Accepted | Accepted |
| `NaN` argument | Rejected, `query/arguments-invalid` (`Non-finite float values are not supported`) | Threw, `query/arguments-invalid` | Threw, `query/arguments-invalid` |
| Function or `Symbol` argument | Resolved, 0 rows | Accepted | Accepted |
| `UPDATE` | Resolved (it is a valid statement) | Threw, `query/unsupported` (`non-SELECT statement in store observer`) | Threw, `query/unsupported` (`non-SELECT statement in sync subscription`) |
| Empty string | Rejected, `query/invalid` (`Unexpected end of input`) | Threw, `query/invalid` | Threw, `query/invalid` |

- Every error was a `DittoError` with the `code` shown, at the moment of the call: `store.execute` returned a rejected promise, and the registrations threw synchronously. No observer or subscription that was accepted reported an error later; 1 second after registration, each one's `isCancelled` was still `false`.
- A subscription rejects any projection other than `*`, before it checks the function names in the projection.
- A syntax error message has the form ``Invalid query: `DQL parser error: Unexpected token SELEC at line 1 column 1 near "SELEC * FROM t"; expected a DQL statement`. For more information on Ditto's query language see: https://ditto.com/link/dql-guide``.
- The oversized `UPDATE` rejected with a `DittoError` with code `query/evaluation` whose message contains `size is 5300177 bytes and exceeds limit of 5242880 bytes`; the stored document kept its previous value.

**Not tested:** `registerObserverWithSignalNext` with these statements (in the SDK 5.2.0 source, `registerObserver` calls `registerObserverWithSignalNext`, so the registration checks are the same); evaluation errors in `WHERE` that are not type mismatches.

**Used in:** [Executing DQL in JavaScript](../../best-practices/platforms/javascript.md#executing-dql-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, function, Symbol, and Set values are stored as empty objects

| | |
|---|---|
| Observed on | `Set`: SDK 5.2.0, four runs, and 5.1.0, three runs. Function and `Symbol` arguments: 5.2.0, three runs, and 5.1.0, two runs. A function as a field value: two runs each. Every run gave the same result |
| Setup | One device without sync. Each value was written as the field `v` of its own document through an argument and read back with `SELECT v, type(v) ...`; a function and a `Symbol` were also passed as the argument of `SELECT type(:n) AS t FROM system:dual` and of `WHERE n = :n` |
| Documentation | The type definitions accept strings, numbers, booleans, `Uint8Array`, `null`, attachments, `bigint`, arrays, and plain objects as argument values |

- A `Set` (`new Set([1, 2])`) was stored as an empty object: `type(v)` was `object`, and the value read back was `{}`. A `Map` was stored as an object with its entries.
- A function and a `Symbol` passed as an argument became an empty object (`type(:n)` returned `object`), so `WHERE n = :n` matched nothing. A document with a function as a field value stored `{}` in that field.
- None of these writes raised an error.

**Used in:** [Arguments and value types in JavaScript](../../best-practices/platforms/javascript.md#arguments-and-value-types-in-javascript).

### In JavaScript on Node.js, queries run off the event loop, but large results block it

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, three runs each |
| Setup | One device without sync, with 40,000 documents of about 400 bytes. A timer that fired every 2 ms recorded the longest pause between its calls, including the pause up to the end of each phase, during (1) an aggregate (`GROUP BY` with `LIKE`) over all documents, (2) `SELECT *` of all documents without reading any value, and (3) reading `item.value` of all 40,000 rows of that result |

| Phase | Time | Longest timer pause |
|---|---|---|
| Aggregate over 40,000 documents | 66 to 73 ms (5.2.0), 76 to 192 ms (5.1.0) | 2 to 3 ms (5.2.0), 3 to 9 ms (5.1.0) |
| `SELECT *` of 40,000 documents | 140 to 159 ms (5.2.0), 186 to 285 ms (5.1.0) | 65 to 82 ms (5.2.0), 95 to 139 ms (5.1.0) |
| Reading the 40,000 values | 216 to 272 ms (5.2.0), 251 to 445 ms (5.1.0) | The whole time |

- While the aggregate was evaluated, the event loop kept running. A large result paused the event loop for about half of the `execute` call, before any value was read, and reading the values ran on the JavaScript thread without a pause.

**Not tested:** browsers and React Native; smaller results, where the pause is presumably shorter.

**Used in:** [Executing DQL in JavaScript](../../best-practices/platforms/javascript.md#executing-dql-in-javascript).

### In JavaScript, a read of system:data_sync_info can stop responding

| | |
|---|---|
| Observed on | SDK 5.2.0, 10 runs with the other peer in another process and 76 runs with both peers in one process; SDK 5.1.0, 16 runs with both peers in one process |
| Setup | Two devices, each subscribed to `orders` and connected over TCP on `127.0.0.1`, in one Node.js process or with the other peer in a separate process. After they saw each other in presence, one device inserted a document (in eight runs on each release, it did not), and then read `SELECT * FROM system:data_sync_info` up to 20 times, 50 ms apart (also 200 ms and 1,000 ms apart), or registered only an observer of it for 20 seconds. A read that had not completed after 3 seconds counted as stuck |

The runs in which a read or the observer got stuck:

| Variant | 5.2.0 | 5.1.0 |
|---|---|---|
| Other peer in another process, reads 50 ms apart after an insert | 4 of 10 | not run |
| One process, reads 50 ms apart after an insert | 5 of 8 | 0 of 8 |
| One process, reads 50 ms apart without an insert | 4 of 8 | 1 of 8 |
| One process, reads 200 ms apart | 4 of 8 | not run |
| One process, reads 1,000 ms apart | 2 of 8 | not run |
| One process, an observer only | 2 of 8 | not run |
| One process, with a connection request handler, a presence observer, a transport-conditions observer, peer metadata, all of these, or none (six runs each) | 12 of 36 | not run |

- A stuck read was always the second read after the devices had connected; the first one completed. With an observer only, the observer was called once and then not again, and a read afterwards hung.
- Once a read was stuck, it had not completed 20 seconds later, every later read of `system:data_sync_info` on that device hung, an observer of it that had been registered before was not called again, and `close()` of that device did not complete within 5 seconds. Reads of other collections on the same device, and reads of `system:data_sync_info` on the other device, completed.
- None of the added factors (the connection request handler, observers, peer metadata) changed the outcome.

- With the other peer in another process, reads also got stuck with the Swift SDK on 5.2.0 and 5.1.0, and with the Kotlin SDK only on 5.1.0 ([In Swift, a read of system:data_sync_info can stop responding](swift-sdk.md#in-swift-a-read-of-systemdata_sync_info-can-stop-responding), [On Kotlin SDK 5.1.0, a read of system:data_sync_info could stop responding](kotlin-sdk.md#on-kotlin-sdk-510-a-read-of-systemdata_sync_info-could-stop-responding)).

**Not tested:** devices on separate machines or over other transports; a device connected to Ditto Server; whether the device recovers after a longer time.

**Used in:** [Closing Ditto in JavaScript](../../best-practices/platforms/javascript.md#closing-ditto-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk), [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Monitoring Sync Status](../../best-practices/sync-and-subscriptions.md#monitoring-sync-status).

### JavaScript values that are not plain JSON change when stored

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; again on 5.1.0 (three runs) and 5.2.0 (four runs) with `type()`; every run gave the same result, and the results were the same on all releases |
| Setup | One device without sync. JavaScript values of each kind written as field values through arguments, then read back; large integers also written as DQL literals; the result of `SHOW ALL` |

| JavaScript value | Stored and read back as |
|---|---|
| `Date` | An empty object `{}`: the time is lost, without an error |
| A field whose value is `undefined` | `null`, so the field no longer matches `IS MISSING`; `undefined` inside arrays and objects also becomes `null` |
| `NaN`, `Infinity` | The write fails: `Unable to encode query arguments: Non-finite float values are not supported` |
| `-0` | `-0` |
| `BigInt` | An integer, read back as a `BigInt` |
| `Uint8Array` | Bytes, read back as a `Uint8Array` |
| `Map` | An object |
| An integer above 2^53 − 1, also when written as a DQL literal | Read back as a `BigInt` (`9007199254740993n`) |
| The largest int64 value plus 1 | No error; read back as `9223372036854775808n` |

- A row that contains a `BigInt` makes `JSON.stringify` fail with `Do not know how to serialize a BigInt`. The result of `SHOW ALL` contains two `BigInt` values.

Later runs on SDK 5.1.0 (three runs) and 5.2.0 (four runs), which also read the stored type with `type()`, gave the same results for the values above and added these:

| JavaScript value | `type()` | Read back as |
|---|---|---|
| `Date` | `object` | `{}` |
| `ArrayBuffer` | `binary` | A `Uint8Array` |
| A small `BigInt` such as `5n` | `integer` | The `number` 5 |
| `10.0` | `integer` | `10` |
| `NaN`, `Infinity` | Not written | A `DittoError` with code `query/arguments-invalid` |
| `Set`, a function | `object` | `{}`: the elements are lost, without an error (see [In JavaScript, function, Symbol, and Set values are stored as empty objects](#in-javascript-function-symbol-and-set-values-are-stored-as-empty-objects)) |
| `-5` inside a map argument | `integer` | `-5`; a filter on the value matched the document |

**Not tested:** integers written as int64 values by the other SDKs (they probably come back as `BigInt` in JavaScript as well).

**Used in:** [Store UTC with a zone designator](../../best-practices/data-modeling.md#store-utc-with-a-zone-designator), [MISSING and NULL](../../best-practices/dql.md#missing-and-null), [Arguments and value types in JavaScript](../../best-practices/platforms/javascript.md#arguments-and-value-types-in-javascript).

## JavaScript Observers and Handles

### In JavaScript, an async observer callback that rejects causes an unhandled rejection

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, three runs each, and three runs each of the case without a listener; every run gave the same result, on both releases |
| Setup | One device without sync. Observers whose callback failed on every call, in four variants: a synchronous `throw` and an `async` callback that rejected (after `await` of 1 ms), each with `registerObserver` and with `registerObserverWithSignalNext` (calling `signalNext()` before failing). Three documents were inserted 200 ms apart after registration while the process counted `uncaughtException` and `unhandledRejection` events. A second case registered the rejecting `async` callback with no `unhandledRejection` listener |
| Documentation | The type definitions declare the handler as returning `void` |

| Callback | Calls (of 4) | `isCancelled` | `uncaughtException` | `unhandledRejection` |
|---|---|---|---|---|
| Synchronous `throw`, `registerObserver` | 4 | `false` | 0 | 0 |
| Synchronous `throw`, `registerObserverWithSignalNext` | 4 | `false` | 0 | 0 |
| `async` rejection, `registerObserver` | 4 | `false` | 0 | 4 |
| `async` rejection, `registerObserverWithSignalNext` | 4 | `false` | 0 | 4 |

- The SDK discards an exception that a callback throws synchronously, but it does not handle the promise that an `async` callback returns: every rejection became an unhandled rejection.
- The SDK's code matches: in the JavaScript SDK 5.2.0, `registerObserver` wraps the callback in a handler for `registerObserverWithSignalNext` that calls it without awaiting the promise it returns and calls `signalNext()` in a `finally` block. This is also why `registerObserver` does not wait for async work.
- Without an `unhandledRejection` listener, Node.js ended the process at the first callback, the one with the initial result, about 0.3 seconds after the case started, with exit code 1 and `Error: async rejection` (Node.js's default for unhandled rejections).

**Not tested:** browsers and React Native, where an unhandled rejection is reported but does not end the app.

**Used in:** [Observer Lifecycle](../../best-practices/observers.md#observer-lifecycle), [Store Observers in JavaScript](../../best-practices/platforms/javascript.md#store-observers-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, using cancels observers and subscriptions at the end of the block

| | |
|---|---|
| Observed on | SDK 5.2.0, five runs; SDK 5.1.0, three runs; every run gave the same result |
| Setup | Node.js 24. A store observer and a subscription declared with `using` inside a block; after the block, their `isCancelled`, `ditto.store.observers`, and `ditto.sync.subscriptions` |
| Documentation | Since SDK 5.1.0, the type definitions give `StoreObserver`, `SyncSubscription`, and `Observer` a `[Symbol.dispose]()` method, "instead of waiting for `FinalizationRegistry`"; the 5.0.3 type definitions have none |

- Inside the block, the observer was active and `ditto.store.observers` had one entry. After the block, `isCancelled` was `true` for the observer and the subscription, and both lists were empty.

**Not tested:** `await using`; runtimes without explicit resource management, where `using` is a syntax error.

**Used in:** [Observer lifecycle in JavaScript](../../best-practices/platforms/javascript.md#observer-lifecycle-in-javascript).

### In JavaScript, Observer.isStopped is true while the observer is active

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, three runs each; the callbacks after `stop()`: three more runs on each release (2026-11-07). Every run gave the same result |
| Setup | One device without sync. The observers that `presence.observe()`, `observeTransportConditions()`, and `auth.observeStatus()` return: `isStopped` before and after `stop()`, and of another presence observer after `close()`. Then two presence observers on one device, one of them stopped, while a second device connected over TCP on `127.0.0.1` and later stopped sync; we counted each observer's callbacks |
| Documentation | The type definitions say that `isStopped` "returns `true` if the observer has been explicitly stopped via the `stop()` method". The SDK 5.0.3, 5.1.0, and 5.2.0 sources return `token !== undefined && observerManager.hasObserver(token)`, which is true while the observer is registered |

- Before `stop()`, `isStopped` was `true` for all three observers; after `stop()`, it was `false`.
- A presence observer that had not been stopped still returned `true` after `close()`.
- `stop()` itself worked: after it, the stopped presence observer was not called again, while the other one was called once when the second device connected and three times by the time it had left.

**Not tested:** whether `stop()` stops the callbacks of the transport-conditions and auth-status observers.

**Used in:** [Closing Ditto in JavaScript](../../best-practices/platforms/javascript.md#closing-ditto-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, registerObserver does not await async callbacks

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result, and the results were the same on all three releases |
| Setup | Five documents were inserted 60 ms apart. The observer's callback took 600 ms on its second call and 10 ms on the others, and when it finished, it wrote the number of documents in its result to the app's state |

- With an async function passed to `registerObserver`, the callback was called 6 times, and two calls ran at the same time. The slow second call (1 document) finished last, so the final state was 1 document, while the store held 5. If no newer result arrives after that, the screen keeps showing the old state.
- With `registerObserverWithSignalNext`, calling `signalNext()` after the work, the callback was called only 3 times (the intermediate results were skipped), one call at a time, and the final state was 5 documents.
- With ten documents inserted 50 ms apart and a callback that always took 500 ms (SDK 5.1.0 and 5.2.0, three runs each), the `async` callback was called 11 times, with up to 9 or 10 calls running at the same time; `registerObserverWithSignalNext` was called 3 times, one at a time, and its last call had all 10 documents in every run.

**Used in:** [Keep observer callbacks fast](../../best-practices/observers.md#keep-observer-callbacks-fast), [Backpressure in JavaScript](../../best-practices/platforms/javascript.md#backpressure-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, exceptions thrown synchronously in observer callbacks are discarded

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; the results were the same on all three releases |
| Setup | An observer whose callback threw on every call, while the process listened for `uncaughtException` and `unhandledRejection`. We also passed an `UPDATE` statement to `registerObserver`, timed the first callback, and closed Ditto with an observer active |

- A synchronous callback that threw on every call kept being called (4 times out of 4), and `isCancelled` stayed `false`. Nothing reached `uncaughtException` or `unhandledRejection`: the exceptions are silently discarded.
- An `async` callback that rejects is different: each rejection is an unhandled rejection, which ends a Node.js process by default (SDK 5.1.0 and 5.2.0; see [In JavaScript, an async observer callback that rejects causes an unhandled rejection](#in-javascript-an-async-observer-callback-that-rejects-causes-an-unhandled-rejection)).
- `registerObserver` with an `UPDATE` statement throws at once: `Unsupported feature: non-SELECT statement in store observer`.
- The first callback arrives asynchronously, about 1 ms after the registration; it is not called inside the registration call.
- After `ditto.close()`, the observer's `isCancelled` is `true`, and the callbacks stop.

**Used in:** [Store Observers in JavaScript](../../best-practices/platforms/javascript.md#store-observers-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, query results return the same objects

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result, and the results were the same on all three releases |
| Setup | We read `items`, `items[0]`, and `item.value` of one `QueryResult` several times, changed `item.value`, and read results after `ditto.close()` |

- `result.items` returns the same array every time, `result.items[0]` the same object, and `item.value` the same object: a value is kept once it has been created.
- After `item.value.n = 99`, later reads of `item.value.n` also return 99. The value in the store does not change (it stays 1).
- After `ditto.close()`, the `value` and `jsonString()` of results that had not been read yet could still be read.

**Used in:** [Query results in JavaScript](../../best-practices/platforms/javascript.md#query-results-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, store.observers exists since 5.0 and lists other objects

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result, and the results were the same on all three releases |
| Setup | We registered two observers with `registerObserver` and one with `registerObserverWithSignalNext`, cancelled one, and closed Ditto, and read `ditto.store.observers` after each step |
| Documentation | The JavaScript SDK's type definitions list `store.observers`, next to `store.attachmentFetchers`, on 5.0.3 as well |

- `store.observers` also works on 5.0.3.
- With two observers from `registerObserver`, it returned 2; with one from `registerObserverWithSignalNext` added, 3. However, `observers.includes(withSignal)` was `false`: the list holds other objects than the ones that the registration returned.
- After `cancel()` on one observer, the list had one fewer. `close()` set `isCancelled` to `true` on the remaining observers, and reading `store.observers` after `close()` threw `Can't perform operation using a Ditto instance that has been closed.`

**Used in:** [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### The JavaScript Differ reports every shifted item as a move

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, one run each, with the JavaScript `Differ` |
| Setup | An observer of three items whose results we passed to one `Differ`. We moved one item to the top of the list, changed a value and changed it back, and looked at the first `diff()` |

- Moving the third item to the top reported three moves (`2→0`, `0→1`, `1→2`) and one update for the moved item: every item whose position shifted is a move, not just the one that was moved.
- A value that changed and changed back between two results was not reported as an update.
- The first `diff()` reported every item as an insertion.
- On 5.2.0, rows of a query that did not project `_id` have no `_id`, so `Differ` cannot tell the items apart (see [On SDK 5.2.0, observer rows include _id only when it is projected, except with Flutter's registerObserver](observer-behavior.md#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected-except-with-flutters-registerobserver)).

**Used in:** [Diffing Results](../../best-practices/observers.md#diffing-results), [Diffing results in JavaScript](../../best-practices/platforms/javascript.md#diffing-results-in-javascript).

### In JavaScript, garbage-collected subscriptions and observers keep running

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; every run gave the same result |
| Setup | A device registered a subscription and a store observer without keeping a reference to either. After their JavaScript objects had been garbage-collected (checked with a `WeakRef` to each), we checked whether new documents still arrived and whether the observer was still called, then cancelled both through `ditto.sync.subscriptions` and `ditto.store.observers` |

- The JavaScript objects of the subscription and the observer were garbage-collected (each `WeakRef` was empty). Ditto kept both running: `ditto.sync.subscriptions` and `ditto.store.observers` each returned one entry, new documents arrived, and the observer was called.
- `cancel()` on the objects from these lists stopped both: the lists were empty, no new documents arrived, and the observer was not called. The lists return other objects than the ones that the registration returned (see [In JavaScript, store.observers exists since 5.0 and lists other objects](#in-javascript-storeobservers-exists-since-50-and-lists-other-objects)), but they can be used to cancel.
- Garbage collection stops neither subscriptions nor observers. Once the reference is gone, the only ways to stop them are these lists and `close()`.

**Not tested:** Dart.

**Used in:** [Subscription Lifecycle](../../best-practices/sync-and-subscriptions.md#subscription-lifecycle), [Observer Lifecycle](../../best-practices/observers.md#observer-lifecycle), [Closing Ditto in JavaScript](../../best-practices/platforms/javascript.md#closing-ditto-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, a subscription without arguments has no queryArguments

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each, and 5.0.3, one run |
| Setup | One device without sync. Two subscriptions, `SELECT * FROM orders` without arguments and `SELECT * FROM orders WHERE status = :status` with `{status: 'open'}`; then `queryString` and `queryArguments` of each element of `ditto.sync.subscriptions` |

- On every release, the subscription without arguments had no `queryArguments` (`null` or `undefined`), and reading it did not end the process. The other subscription returned `{status: 'open'}`.
- The order of `ditto.sync.subscriptions` differed between releases, the same in every run: on 5.0.3 and 5.1.0, the subscription registered second came first, and on 5.2.0, the one registered first. The order is not documented.

**Not tested:** `queryArgumentsJsonString`; the Flutter SDK, for which [Sync stop, close, and inspection](../../best-practices/sync-and-subscriptions.md#sync-stop-close-and-inspection) describes a crash on 5.1.0.

**Used in:** [Subscriptions in JavaScript](../../best-practices/platforms/javascript.md#subscriptions-in-javascript).

## JavaScript Transactions and Closing

### In JavaScript, a read-write transaction started inside another one waits until the outer one ends

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, three runs each; every run gave the same result, on both releases |
| Setup | One device without sync, a new store per scenario. Inside a transaction (the outer one), the callback started a second transaction (the inner one) with `ditto.store.transaction` and waited up to 5 seconds for it; then the outer callback returned and committed. Four combinations of read-write and read-only. In the read-write outer transaction, the callback inserted a document before starting the inner one, and the inner one read that document. A fifth scenario started an inner read-write transaction without awaiting it, and the outer callback returned 300 ms later |
| Documentation | The description of `Store.transaction()` in the type definitions warns: "Calling `ditto.store.execute()` or creating a nested transaction within a transaction may lead to a deadlock." It also says that only one read-write transaction runs at a time and that others wait until it ends |

| Outer | Inner | Inner while the outer one was open |
|---|---|---|
| Read-write | Read-write | Did not start within 5 seconds |
| Read-write | Read-only | Completed at once; it did not see the outer transaction's uncommitted insert |
| Read-only | Read-write | Completed at once |
| Read-only | Read-only | Completed at once |

- The inner read-write transaction waits for the outer one, not forever: once the outer callback returned (here because the test stopped waiting after 5 seconds), the inner one started at once (0.00 s later), read the committed insert of the outer one, and committed its own. An outer callback that awaits the inner read-write transaction therefore never ends, which is the deadlock that [In JavaScript, store.execute writes inside a transaction deadlock](javascript-sdk.md#in-javascript-storeexecute-writes-inside-a-transaction-deadlock) describes.
- An inner read-write transaction that was started but not awaited ran after the outer callback had returned, read the outer transaction's committed insert, and committed.

**Not tested:** a nested read-write transaction with sync running.

**Used in:** [Transaction Rules](../../best-practices/transactions.md#transaction-rules), [Transactions in JavaScript](../../best-practices/platforms/javascript.md#transactions-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, an error caught inside a transaction callback does not roll back the transaction

| | |
|---|---|
| Observed on | SDK 5.2.0, three runs; SDK 5.1.0, two runs; every run gave the same result, on both releases |
| Setup | One device without sync. A read-write transaction whose callback ran an invalid statement through `tx.execute` inside `try`/`catch` and then inserted a document; a second transaction that inserted a document and then ran the invalid statement without catching it; a read-only transaction that ran an `INSERT` |
| Documentation | The type definitions say: "If errors occur in an `execute()` call within a transaction block and the error is caught and handled within the block, the transaction will continue to run and not be rolled back. When an error is thrown at any point inside the transaction block or while committing the transaction, the transaction is implicitly rolled back, and the error is propagated to the caller." |

- With the error caught, the transaction continued, and the later insert was committed.
- With the error not caught, `ditto.store.transaction()` rejected with the same `DittoError` (`query/invalid`), and the earlier insert was rolled back.
- An `INSERT` in a read-only transaction failed with a `DittoError` with code `store/transaction-read-only` and the message `A mutating DQL query was attempted using a read-only transaction.`

**Used in:** [Transactions in JavaScript](../../best-practices/platforms/javascript.md#transactions-in-javascript).

### In JavaScript, calls after close() throw or reject with a plain Error

| | |
|---|---|
| Observed on | SDK 5.2.0, three runs; SDK 5.1.0, two runs; every run gave the same result, on both releases |
| Setup | One device without sync. Before `ditto.close()`, we inserted a document, registered a store observer, a subscription, and a presence observer, read one query result (and kept another unread), created an attachment from bytes, and passed the result's items to a `Differ`. After `close()` had completed, we called each API once and recorded whether it threw synchronously, returned a promise that rejected, or worked |
| Documentation | The type definitions say that `ditto.config` and `store.observers` throw after `close()`, and that `auth.login` throws `authentication/failed-to-authenticate` when the instance is closed |

- `close()` set `isCancelled` to `true` on the store observer and the subscription.
- Rejected with `Error: Can't perform operation using a Ditto instance that has been closed.`: `store.execute` (reads and writes), `store.transaction`, `store.newAttachment`, and `data()` of the attachment created before `close()`.
- Threw the same error synchronously: `store.registerObserver`, `store.registerObserverWithSignalNext`, `store.observers`, `store.fetchAttachment`, `sync.registerSubscription`, `sync.subscriptions`, `sync.start()`, `sync.stop()`, `sync.isActive`, `presence.graph`, `updateTransportConfig`, `setTransportConfig`, `setOfflineOnlyLicenseToken`, `config`, and `absolutePersistenceDirectory`. `presence.observe` threw a different message: `Internal inconsistency, can't add 'PresenceObservation' observer, observer mananger close()-ed.`
- Each of these is a plain `Error`, not a `DittoError`, so it has no `code`. The exception is `auth.login`, which rejected with a `DittoError` with code `authentication/failed-to-authenticate` and the message `Ditto instance is closed`.
- Kept working: `auth.status`, `deviceName`, `item.value` of the result that had been read and of the one that had not, `Differ.diff()` of the earlier items, `cancel()` on the observer and the subscription, `stop()` on the presence observer, `Logger.exportToFile()`, and a second `close()`.

**Not tested:** browsers and React Native; calls made while `close()` is in progress (see [In JavaScript, close() completes pending writes](javascript-sdk.md#in-javascript-close-completes-pending-writes)).

**Used in:** [Closing Ditto in JavaScript](../../best-practices/platforms/javascript.md#closing-ditto-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, store.execute writes inside a transaction deadlock

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each; the results were the same on all three releases |
| Setup | Inside a read-write transaction, we ran an `INSERT` and a `SELECT` through `ditto.store.execute`, and started a read-write transaction and a read-only transaction. A call that had not completed after 4 seconds counted as deadlocked (in [A deadlocked transaction does not end the process](transaction-behavior.md#a-deadlocked-transaction-does-not-end-the-process), one had still not completed after 306 seconds) |
| Documentation | The description of `Store.transaction()` in the JavaScript SDK's type definitions (the same text in 5.0.3 and 5.2.0) warns: "**Warning:** Calling `ditto.store.execute()` or creating a nested transaction within a transaction may lead to a deadlock." |

- An `INSERT` through `ditto.store.execute` inside a read-write transaction never completes, and raises no exception. A `SELECT` completes, but, like any read outside the transaction, it does not see the transaction's writes (see [Reads outside a read-write transaction see only committed data](transaction-behavior.md#reads-outside-a-read-write-transaction-see-only-committed-data)).
- A read-write transaction started inside a read-write transaction never completes. A read-only transaction started inside completes.

**Used in:** [Transaction Rules](../../best-practices/transactions.md#transaction-rules), [Transactions in JavaScript](../../best-practices/platforms/javascript.md#transactions-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### A tx.execute that is not awaited is not applied

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; without a handler for the statement's failure, five runs each; the `forEach` case, three runs each. The results were the same on all three releases |
| Setup | The callback of a read-write transaction called `tx.execute(...)` to change `v`, which was 1, without `await`, and returned. Variants: with and without a handler for the statement's failure; three `INSERT` statements in `[1, 2, 3].forEach(async (i) => { await tx.execute(INSERT ...) })`; and, for comparison, `await Promise.all(items.map((item) => tx.execute(...)))` |

- When the callback returns without awaiting `tx.execute(...)`, the transaction ends without an error. The statement fails afterwards with a `store/backend` error, `No active write transaction found with id ... Active write transaction id: None`, and the value does not change (`v` stays 1).
- When nothing handles that failure, it becomes an unhandled promise rejection, and Node.js ends the process with exit code 1. This happened in 4 of 5 runs on 5.2.0 and in 1 of 5 runs on 5.1.0, depending on when the rejection occurred.
- The `forEach` form behaves the same: the transaction ends without an error, none of the three documents is inserted, and all three statements become unhandled rejections. Each is caused by `No active write transaction found`; on 5.1.0 and 5.2.0, the message has the prefix `Query failed: ... Insert failed: <store> No active write transaction found ...`. Later transactions and `close()` worked normally.
- `await Promise.all(items.map((item) => tx.execute(...)))` worked correctly on all three releases, with 10 `INSERT` statements, and with 10 `SELECT` statements in a read-only transaction. Running the statements in parallel is not the problem; not awaiting them is.
- A `tx` taken out of the transaction and used after the transaction has ended fails with the same error.
- The callback's return value becomes the result of `transaction()`, and a callback that throws rolls back its writes.

**Not tested:** Dart. A `tx.execute` left `unawaited` there probably behaves the same.

**Used in:** [Transaction Rules](../../best-practices/transactions.md#transaction-rules), [Transactions in JavaScript](../../best-practices/platforms/javascript.md#transactions-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### A Node.js script that keeps neither sync nor a timer running ends with a panic while awaiting a transaction

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, five runs each for each kind of callback, for `store.execute`, and for the script that kept a timer; deterministic. The CommonJS script, and the script that started sync: three runs each on 5.1.0 and 5.2.0. The results were the same on all three releases |
| Setup | A Node.js script with nothing else that kept the event loop alive (no timer, no server) awaited `ditto.store.transaction(...)` with a read-write callback, a read-only callback, or a callback that did nothing. For comparison, the same script ran `store.execute` without a transaction, and kept a `setInterval` timer. Variants: a CommonJS script without top-level `await`, which called `async function main()`, and a script that started sync with `sync.start()` before the same transaction |

- Without anything that keeps the event loop alive, `await ditto.store.transaction(...)` makes Node.js print `Warning: Detected unsettled top-level await` and begin to exit. An SDK callback that arrives afterwards ends the process with `Panic: Error { status: PendingException, reason: "" }` (exit code 134). This happened with all three kinds of callback, in all five runs.
- A CommonJS script without top-level `await` fails the same way. No warning appears: Node.js begins to exit normally (`process.on('exit')` is called with exit code 0), and then the same panic ends the process (exit code 134). In both forms, the code after the transaction does not run.
- `store.execute` without a transaction completed in all five runs, and so did 500 `store.execute` calls run in parallel with `Promise.all` (see [Parallel writes are safe, but parallel read-modify-write loses updates](transaction-behavior.md#parallel-writes-are-safe-but-parallel-read-modify-write-loses-updates)).
- With a `setInterval` timer kept running, the failure did not occur in any of the five runs. It did not occur inside a `node --test` test either, because the test runner keeps the event loop alive. Apps whose event loop always runs, such as servers or Electron apps, are not affected.
- A script that started sync (`sync.start()`, then the same transaction) completed in every run. Run again without sync on the same day, the script ended abnormally in every run (exit code 134 or 139, with `PendingException` or `InvalidArg` in the panic message). Only scripts that do not start sync, such as seed, migration, and command-line scripts, are affected.
- The same kind of abnormal exit also occurs occasionally with `fetchAttachment()`; with a transaction, it occurred every time. The other tests behind these pages always kept a timer running, so this failure did not affect them.

**Used in:** [Transactions in JavaScript](../../best-practices/platforms/javascript.md#transactions-in-javascript), [Testing in JavaScript](../../best-practices/platforms/javascript.md#testing-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, close() waits for open transactions

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | While a read-write transaction was paused at an `await` inside its callback, we called `ditto.close()`, and then let the transaction continue |
| Documentation | The description of `Store.transaction()` in the JavaScript SDK's type definitions says: "When a Ditto instance goes out of scope, it will drive all pending transactions to completion before being shut down." |

- `close()` had not completed after 3 seconds. When the transaction continued, its next `tx.execute` succeeded, the transaction ended, and then `close()` completed.
- The SDK's code matches: in the JavaScript SDK 5.2.0, `Ditto.close()` sets `isClosed`, stops sync, and then waits with `Promise.allSettled` until all pending operations have finished.
- A transaction that never ends, such as a deadlocked one, therefore probably keeps `close()` from completing as well.

**Not tested:** Flutter.

**Used in:** [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Concurrency and Duration](../../best-practices/transactions.md#concurrency-and-duration), [Closing Ditto in JavaScript](../../best-practices/platforms/javascript.md#closing-ditto-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).

### In JavaScript, close() completes pending writes

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, two runs each (cancelling an observer: one run each). Calls after `close()`: one run each on 5.1.0 and 5.2.0. Sending to another device: 54 runs |
| Setup | We started 200 `INSERT` statements without awaiting them and then awaited `ditto.close()` at once; we also started an `INSERT` right after calling `close()`, before awaiting it. Then we reopened the directory and counted the documents. Separately, we cancelled a store observer while writes continued, called each API after `close()`, and closed Ditto right after a write that was not awaited while another device was connected |

- `close()` completed in 81 to 172 ms, and all 200 inserts had succeeded; after reopening, all 200 documents were there.
- An `INSERT` started right after `close()` was called, before it was awaited, also succeeded and was there after reopening.
- `execute` after `close()` had completed failed with `Can't perform operation using a Ditto instance that has been closed.`
- After a store observer was cancelled with `cancel()` while writes continued, it received 0 callbacks.
- The JavaScript SDK wraps `execute` in `deferCloseAsync`, the same mechanism as for transactions (see [In JavaScript, close() waits for open transactions](#in-javascript-close-waits-for-open-transactions)), so `close()` waits for operations in progress.
- After `close()`, `store.execute`, `store.transaction`, `registerObserver`, `registerSubscription`, `sync.start()`, `sync.isActive`, `presence.graph`, and `updateTransportConfig` all throw `Error: Can't perform operation using a Ditto instance that has been closed.` This is a plain `Error`, not a `DittoError`. `cancel()` on subscriptions and observers registered before closing, and a second `close()`, raise no error, so cleanup code can cancel after closing and can call `close()` twice.
- `close()` waits only for local writes, not until they have been sent. When `close()` followed right after a write that was not awaited, the write was stored but reached the other device in 0 of 54 runs; it arrives at the next sync (see [A write made right before close or stop may not leave the device](subscriptions-and-replication.md#a-write-made-right-before-close-or-stop-may-not-leave-the-device)).

**Not tested:** Flutter, including whether its `close()` waits for pending work on 5.2.0.

**Used in:** [Resource Cleanup and Shutdown](../../best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown), [Closing Ditto in JavaScript](../../best-practices/platforms/javascript.md#closing-ditto-in-javascript).

## JavaScript Attachments

### In JavaScript, fetchAttachment fails at once for a token that the store did not receive by sync

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each; the results were the same on both releases, except one result that depends on random bytes (below). Fetches that only had an event handler, one run on each release |
| Setup | `fetchAttachment(token, onEvent)` on: (1) the store that had created the attachment; (2) a store that had never connected to another, with four values that are not valid tokens and with the first store's token; (3) a store connected to the holder over 127.0.0.1 without a subscription to the document, with tokens passed inside the process, while the holder was connected and after it had stopped sync; (4) a store that had received a document with a 20,000-byte attachment by sync, after the holder had stopped sync; the holder started sync again 5 seconds into the fetch. Each fetch was awaited for up to 5 seconds, the last one for 30 more seconds after the restart. Separately, failing fetches that only had an event handler and were never awaited |
| Documentation | The `fetchAttachment` documentation of `@dittolive/ditto` 5.2.0 lists the errors `store/attachment-not-found` and `store/attachment-token-invalid` |

| Token | What `fetchAttachment` did |
|---|---|
| On the store that created the attachment | Resolved within 2 ms with the same bytes, after one `Completed` event |
| An `id` that is not base64 | Threw at once: a `DittoError` with the code `internal` (`Invalid base64 encoding.`) |
| An object without `id` | Threw at once: a plain `Error` (`` InvalidArg: Expected a pointer (`{ addr }` object) ``) |
| An `id` of random bytes, 8 bytes or 34 (the length of a real ID) | Rejected within 2 ms with `store/attachment-token-invalid`, without an event, in 7 of 8 fetches; once (8 bytes, SDK 5.2.0), a `Deleted` event and `store/attachment-not-found`, as in the next row |
| A valid token on a store that had never connected | A `Deleted` event, then rejected with `store/attachment-not-found` (`The attachment was not found.`), within 2 ms |
| A valid token passed inside the process to a store connected to the holder, which had not received the document | The same, also while the holder was connected: the fetch did not ask the holder for the blob |
| A token received by sync, after the holder had stopped sync | Pending for 5 seconds, without an event or an error. After the holder had started sync again, it completed 5.05 to 5.14 seconds later with all 20,000 bytes, after one `Completed` event and no `Progress` event |

- A store can fetch a blob only through a token that it received in a document by sync. A token that an app passes to another store in some other way fails at once, even when the holder is connected. Which conditions make a fetch end at once and which make it wait, including a store that deleted the document and opened again (it ends at once on SDK 5.2.0 and waits on 5.1.0), is in [A fetch waits while no device holds the blob, and a device that deleted the document still serves it](attachment-behavior.md#a-fetch-waits-while-no-device-holds-the-blob-and-a-device-that-deleted-the-document-still-serves-it).
- The `Deleted` event in these rows reports a token that Ditto rejected as not found when the fetch started; the SDK emits it before it rejects. A fetch that was already pending did not end with `Deleted` when its document was deleted (see the entry linked above). The Kotlin SDK reports the same case as an exception (see [In Kotlin, fetchAttachment waits without progress while no peer delivers the blob](kotlin-sdk.md#in-kotlin-fetchattachment-waits-without-progress-while-no-peer-delivers-the-blob)).
- A fetch whose holder is not connected gives no sign; only a timer of the app notices it.
- Failing fetches that had only an event handler, with `Deleted` and `store/attachment-not-found` or with `store/attachment-token-invalid`, and a fetcher stopped from its `Deleted` event caused no unhandled rejection, so an app does not need to await the fetcher to avoid one.

**Not tested:** browsers and React Native; attachments large enough for `Progress` events; how long a fetch whose holder is offline waits before it gives up, if it ever does.

**Used in:** [Attachments in JavaScript](../../best-practices/platforms/javascript.md#attachments-in-javascript).

## JavaScript Logging

### In JavaScript, the custom log callback stays installed after close()

| | |
|---|---|
| Observed on | SDK 5.2.0 and 5.1.0, three runs each; every run gave the same result |
| Setup | `Logger.setCustomLogCallback()` with a callback that collected messages starting with `marker`; one store opened and closed; `Logger.info()` before `close()`, after `close()`, and after another store had been opened; then `Logger.setCustomLogCallback(undefined)` and one more `Logger.info()` |
| Documentation | The type definitions describe the callback as process-wide; they say nothing about `close()` |

- The callback received all three messages: before `close()`, after `close()`, and with the new instance. `Logger.customLogCallback` was still the function after `close()`.
- After `setCustomLogCallback(undefined)`, the callback received nothing.

**Not tested:** React Native, where `setCustomLogCallback()` throws according to the type definitions.

**Used in:** [Logging in JavaScript](../../best-practices/platforms/javascript.md#logging-in-javascript), [Behavior Specific to the JavaScript SDK](../../best-practices/platforms/javascript.md#behavior-specific-to-the-javascript-sdk).
