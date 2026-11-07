# Ditto on JavaScript

This page shows how to apply the guide with the JavaScript SDK, `@dittolive/ditto` 5.2.0: the API calls, the patterns for React components and for the lifecycles of Node.js, browsers, and React Native, and the behavior that is specific to this SDK. The rules themselves, the DQL, and the reasons are on the topic pages of the guide, which apply to every SDK; each section below links to them. The same sections exist for [Flutter](flutter.md), [Kotlin](kotlin.md), and [Swift](swift.md).

The examples are ES modules. Each one imports what it uses from `@dittolive/ditto`, from Node.js (`node:...`), or from `react`. Placeholders such as `'YOUR_DATABASE_ID'`, `fetchAuthToken()`, and `showError()` stand for values and code from your own app. UI examples are React function components with hooks; the same placement of registration and release applies to other frameworks.

## Installing the JavaScript SDK

One npm package, `@dittolive/ditto`, serves three runtimes. Version 5.2.0 has the following requirements:

| Runtime | Requirement | Storage | Transports |
|---|---|---|---|
| Node.js (and Electron) | An active or maintenance LTS release (18 or later); macOS 12+ on arm64, Linux x64 (Ubuntu 20.04+) and AArch64 (Ubuntu 22.04+), Windows 10+ x64 | Files in the persistence directory | Bluetooth LE, LAN, and WebSocket; AWDL on macOS; TCP listen and connect |
| Browsers | Chrome and Edge 84+, Firefox 79+, Safari 14.1+ (iOS 14.5+); not Internet Explorer | **In memory only**; nothing is written to IndexedDB or other browser storage, and the data is gone when the page closes | **WebSocket only**, to Ditto Server or another listener |
| React Native | React Native 0.70 or later; iOS 15+, Android 7+ (`minSdkVersion` 24), macOS 12+ with the React Native CLI; Expo Dev Builds (Expo 50+), not Expo Go | Files in the persistence directory | Bluetooth LE, LAN, and WebSocket; AWDL on iOS and macOS; Wi-Fi Aware on Android |

Pin the exact version in `package.json`, and commit the lock file, so every developer and CI build uses the same release:

```json
{
  "dependencies": {
    "@dittolive/ditto": "5.2.0"
  }
}
```

**Platform setup**: React Native apps need the Bluetooth, local network, and nearby-device permissions and usage descriptions of the native platforms; follow the [React Native install guide](https://docs.ditto.live/sdk/latest/install-guides/react-native) (or its Expo config plugin) and request runtime permissions before starting sync. The package contains the native libraries of every platform; when you package a Node.js or Electron app, keep only the `node/ditto.<platform>*.node` files of your target, as described in the [JavaScript install guide](https://docs.ditto.live/sdk/latest/install-guides/js).

**Browser limitations**:
- Data is stored **in memory only** and is lost when the page reloads or closes.
- Sync works **only over WebSocket**; Ditto ignores every other part of the transport configuration in a browser.
- In-memory stores do not support indexes ([Ditto's indexing reference](https://docs.ditto.live/dql/indexing)). Skip `CREATE INDEX` in a browser.
- `newAttachment` accepts only bytes, and `Logger.exportToFile()` and `attachment.copyToPath()` throw.
- `await init()` downloads Ditto's WebAssembly module, by default from Ditto's CDN. To serve it yourself, host `web/ditto.wasm` from the package with the `application/wasm` MIME type and pass its URL: `await init({ webAssemblyModule: url })`.

## Opening Ditto in JavaScript

- Call `await init()` once, before any other API. In browsers it loads the WebAssembly module; in Node.js it does nothing and resolves at once, so the same startup code runs everywhere. Later calls return the same promise.
- `await Ditto.open(config)` is the standard way to create an instance. `Ditto.openSync(config)` returns the instance without a promise, and blocks the thread while it opens.
- `Ditto.VERSION` is the SDK version (`'5.2.0'`), a static property.

```javascript
import { Ditto, DittoConfig, init } from '@dittolive/ditto';

// ✅ GOOD: Initialize once, then open. openSync() blocks the thread while it opens.
export async function openWithoutAwaitingOpen() {
  await init();
  // connect: { mode: 'smallPeersOnly' } without a key does not authenticate
  // peers; see DittoConfig in JavaScript.
  return Ditto.openSync(
    new DittoConfig({ databaseID: 'YOUR_DATABASE_ID', connect: { mode: 'smallPeersOnly' } }),
  );
}
```

On Node.js, `ditto.store.execute()` runs the query outside the JavaScript thread, but building a large result and reading its values run on it (see [Executing DQL in JavaScript](#executing-dql-in-javascript)).

### DittoConfig in JavaScript

`new DittoConfig({ ... })` takes the fields of [DittoConfig](../setup-and-lifecycle.md#dittoconfig) as named options (SDK 5.2+). The positional form `new DittoConfig(databaseID, connect, persistenceDirectory)` works on every 5.x release and cannot take system parameters.

| Field | Type | Default | JavaScript specifics |
|---|---|---|---|
| `databaseID` | `string` | Required (`DittoConfig.default` uses the all-zero UUID) | |
| `connect` | object | Required | `{ mode: 'server', url }`, or `{ mode: 'smallPeersOnly', privateKey }` (`privateKey: null` or omitted: no key) |
| `persistenceDirectory` | `string` | `ditto-<databaseID in lowercase>` inside `Ditto.DEFAULT_ROOT_DIRECTORY` | A relative path is resolved against `Ditto.DEFAULT_ROOT_DIRECTORY`: `~/Library/Application Support/ditto` on macOS, `~/AppData/Roaming/ditto` on Windows, and `~/.local/share/ditto` on Linux for Node.js; the Application Support directory (iOS, macOS) or the internal files directory (Android) for React Native. In browsers it is only a name for the in-memory store. `ditto.absolutePersistenceDirectory` returns the resolved path. |
| `systemParameters` (SDK 5.2+) | object | `{}` | Values are strings, numbers, `bigint`s, booleans, and arrays and objects of those; not `null` or bytes. An unknown name or a wrong type makes `Ditto.open()` reject with a `DittoError` whose `code` is `validation/invalid-ditto-config`. |

The named form is new in SDK 5.2: on 5.1.0, `new DittoConfig({ ... })` throws `TypeError: Expected id to be a string, but got: object` (see [In JavaScript, the named DittoConfig form throws on SDK 5.1.0](../../knowledge/observations/javascript-sdk.md#in-javascript-the-named-dittoconfig-form-throws-on-sdk-510)). `ditto.config` returns the configuration, frozen; `config.copy()` gives a copy that you can change. The JavaScript SDK has no encryption at rest (see [Data at Rest](../security.md#data-at-rest)), and no API to delete a store: delete the persistence directory after `close()` has completed.

```javascript
import { Ditto, DittoConfig } from '@dittolive/ditto';

// ✅ GOOD: Small-peers-only deployment. The shared key and the offline license
// token (issued by Ditto) come from secure provisioning, never from source code.
export async function openProvisionedSmallPeer({ readKeyFromSecureStorage, readLicenseFromSecureStorage }) {
  const ditto = await Ditto.open(
    new DittoConfig({
      databaseID: 'YOUR_DATABASE_ID', // any UUID shared by all peers
      connect: { mode: 'smallPeersOnly', privateKey: await readKeyFromSecureStorage() },
    }),
  );
  // Required before sync.start() in small-peers-only mode.
  ditto.setOfflineOnlyLicenseToken(await readLicenseFromSecureStorage());
  ditto.sync.start(); // no expiration handler is needed in this mode
  return ditto;
}
```

Pass system parameters on every open (see [Applying System Parameters](../setup-and-lifecycle.md#applying-system-parameters)):

```javascript
import { Ditto, DittoConfig } from '@dittolive/ditto';

// ✅ GOOD: Pass settings on every open. Ditto applies them before it starts,
// and a misspelled name or a wrong type makes Ditto.open() reject.
export async function openWithSystemParameters({ strictMode }) {
  const ditto = await Ditto.open(
    new DittoConfig({
      databaseID: 'YOUR_DATABASE_ID',
      connect: { mode: 'server', url: 'YOUR_SERVER_URL' },
      // true only for apps that opt into strict mode
      systemParameters: strictMode ? { DQL_STRICT_MODE: true } : {},
    }),
  );

  // Confirm the effective value. SHOW returns one row keyed by the
  // lowercase parameter name.
  const result = await ditto.store.execute('SHOW DQL_STRICT_MODE');
  console.log(`dql_strict_mode = ${result.items[0].value.dql_strict_mode}`);
  return ditto;
}
```

Pass sync scopes the same way, so that they are in effect before sync starts (see [Sync Scopes](../sync-and-subscriptions.md#sync-scopes)):

```javascript
import { DittoConfig } from '@dittolive/ditto';

// ✅ GOOD: Pass sync scopes in the configuration on every open (SDK 5.2+),
// so that they are in effect before sync starts.
export const scopedConfig = new DittoConfig({
  databaseID: 'YOUR_DATABASE_ID',
  connect: { mode: 'server', url: 'YOUR_SERVER_URL' },
  systemParameters: {
    USER_COLLECTION_SYNC_SCOPES: {
      localDrafts: 'LocalPeerOnly',
      kitchenTickets: 'SmallPeersOnly',
    },
  },
});
```

```javascript
import { Ditto, DittoConfig } from '@dittolive/ditto';

// ❌ BAD: No privateKey means peers are not authenticated (and the SDK
// documents the mode as unencrypted); a key in the bundle would be visible
// to anyone who downloads the app.
export function openUnprotectedSmallPeer() {
  return Ditto.open(
    new DittoConfig({ databaseID: 'YOUR_DATABASE_ID', connect: { mode: 'smallPeersOnly' } }),
  );
}
```

### One shared instance in JavaScript

Let concurrent callers await the same promise, and forget a failed attempt so that the next caller can retry (see [One instance per persistence directory](../setup-and-lifecycle.md#one-instance-per-persistence-directory)). Keep the provider in a module or an app-level service: an instance that only a short-lived scope references can be garbage-collected.

```javascript
import { Ditto } from '@dittolive/ditto';

// ✅ GOOD: One shared instance; concurrent callers await the same open.
export class DittoProvider {
  #config;
  #opening = null;

  constructor(config) {
    this.#config = config;
  }

  get instance() {
    this.#opening ??= Ditto.open(this.#config).catch((error) => {
      // Forget the failed attempt so that the next caller can retry.
      this.#opening = null;
      throw error;
    });
    return this.#opening;
  }
}
```

```javascript
import { Ditto, DittoConfig } from '@dittolive/ditto';

// ❌ BAD: Every call opens the same directory again. While the first instance
// is open, the second open fails after about a second.
export async function loadOrdersWithNewInstance() {
  const ditto = await Ditto.open(
    new DittoConfig({ databaseID: 'YOUR_DATABASE_ID', connect: { mode: 'smallPeersOnly' } }),
  );
  const result = await ditto.store.execute('SELECT * FROM orders');
  return result.items.map((item) => item.value);
}
```

In our testing with SDK 5.1.0 and 5.2.0, `Ditto.open()` on a directory that the same process already had open rejected after 1.02 to 1.04 seconds with a `DittoError` whose `code` is `store/persistence-directory-locked`, and `Ditto.openSync()` threw the same error after blocking for that time (see [In JavaScript, opening an open directory again fails](../../knowledge/observations/javascript-sdk.md#in-javascript-opening-an-open-directory-again-fails)).

**Development reloads**: React's Strict Mode runs every effect twice in development (mount, clean up, mount again), so code that registers in an effect must release in its cleanup, as the components on this page do. A dev server that re-runs the module that opens Ditto, such as hot module replacement, opens a second instance; keep the provider in a module that is not reloaded, or close the old instance first.

### App startup in JavaScript

The recommended order (see [Complete app startup](../setup-and-lifecycle.md#complete-app-startup)), as one service that owns the instance and its long-lived subscriptions:

```javascript
import { Ditto, DittoConfig, Logger, init } from '@dittolive/ditto';

// Most apps keep the default (strict mode off). See "Strict Mode".
const enableStrictMode = false;

// fetchAuthToken() and showError() stand for your app's own code.

export class DittoService {
  constructor(ditto, subscriptions) {
    this.ditto = ditto;
    this.subscriptions = subscriptions;
  }

  static async start({ production = false } = {}) {
    // 1. Initialize the module (loads WebAssembly in browsers; a no-op in Node.js).
    await init();

    // 2. Configure logging before open, so that startup is logged with your settings.
    Logger.minimumLogLevel = production ? 'Warning' : 'Debug';

    // 3. Open the single shared instance. System parameters are not persisted,
    //    so pass them on every open; Ditto applies them before it starts (SDK 5.2+).
    const ditto = await Ditto.open(
      new DittoConfig({
        databaseID: 'YOUR_DATABASE_ID',
        // Copy the URL from the Ditto Portal exactly as shown.
        connect: { mode: 'server', url: 'YOUR_SERVER_URL' },
        systemParameters: enableStrictMode ? { DQL_STRICT_MODE: true } : {},
      }),
    );

    // If a later step fails, close the instance before rethrowing: opening the
    // same directory again while it is still open fails.
    try {
      // 4. Server connections require an expiration handler before sync.start().
      await ditto.auth.setExpirationHandler(async (ditto, secondsRemaining) => {
        try {
          const result = await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
          if (result.error) showError(result.error); // login() reports rejection; it does not throw
        } catch (error) {
          showError(error); // for example, fetchAuthToken() failed
        }
      });

      // 5. Create the indexes your queries need before queries and observers run.
      //    Indexes persist, and IF NOT EXISTS makes this safe on every start.
      await ensureIndexes(ditto);

      // 6. Register long-lived subscriptions, then start sync.
      const subscriptions = [
        ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', {
          storeId: 'store-1',
        }),
      ];
      ditto.sync.start(); // synchronous; throws if prerequisites are missing

      return new DittoService(ditto, subscriptions);
    } catch (error) {
      await ditto.close();
      throw error;
    }
  }

  // Call only when the whole app no longer needs Ditto.
  async close() {
    for (const subscription of this.subscriptions) subscription.cancel();
    await this.ditto.close();
  }
}
```

Create the indexes your queries rely on once per launch, and skip them in browsers, whose in-memory store does not support indexes (see [Where indexes live](../indexing-and-performance.md#where-indexes-live)):

```javascript
// In a browser, the store is in memory and has no indexes.
const inMemoryStore = typeof document !== 'undefined' && typeof navigator !== 'undefined';

// ✅ GOOD: Create the indexes this app relies on, once per launch.
export async function ensureIndexes(ditto) {
  if (inMemoryStore) return;

  const statements = [
    'CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)',
    'CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)',
  ];
  for (const statement of statements) {
    try {
      await ditto.store.execute(statement);
    } catch (error) {
      // Without the index, queries that use it fall back to a collection scan
      // (and a JOIN on it fails): report and continue.
      showError(error);
    }
  }
}
```

## Authentication in JavaScript

Register the handler with `await ditto.auth.setExpirationHandler(async (ditto, secondsRemaining) => { ... })`. `secondsRemaining` is a number of seconds until the credentials expire; it is `0` when Ditto is not authenticated yet. `await ditto.auth.login(token, provider)` resolves to `{ clientInfo, error }`. **It does not throw when your authentication webhook rejects the token or the server is unreachable**: check `result.error`, a `DittoError` (code `authentication/failed-to-authenticate`) or `null`; `result.clientInfo` contains the optional `clientInfo` JSON returned by your webhook. The SDK awaits the handler and catches what it throws: an error thrown from the handler only produces a Ditto log line at the Error level, so report failures to your app yourself (see [In JavaScript, an error thrown by the expiration handler is only logged](../../knowledge/observations/javascript-sdk.md#in-javascript-an-error-thrown-by-the-expiration-handler-is-only-logged)). The rules are in [Authentication](../setup-and-lifecycle.md#authentication).

```javascript
import { Logger } from '@dittolive/ditto';

// ✅ GOOD: Production login with error reporting and no throwing.
// fetchAuthToken() and showError() stand for your app's own code.
export async function configureAuthentication(ditto) {
  await ditto.auth.setExpirationHandler(async (ditto, secondsRemaining) => {
    if (secondsRemaining > 0) {
      Logger.info(`Ditto credentials expire in ${secondsRemaining} s; refreshing`);
    }
    try {
      const result = await ditto.auth.login(
        await fetchAuthToken(), // from your identity provider or backend
        'YOUR_PROVIDER_NAME', // as configured in the Ditto Portal
      );
      if (result.error) showError(result.error);
    } catch (error) {
      showError(error);
    }
  });
}
```

```javascript
import { Authenticator } from '@dittolive/ditto';

// ✅ GOOD (development only): The development provider and Portal token.
export async function configureDevelopmentAuthentication(ditto, developmentToken) {
  await ditto.auth.setExpirationHandler(async (ditto) => {
    const result = await ditto.auth.login(developmentToken, Authenticator.DEVELOPMENT_PROVIDER);
    if (result.error) showError(result.error);
  });
}
```

```javascript
// ❌ BAD: The SDK catches what the handler throws and only logs it, so the app
// never learns that login failed.
export async function configureAuthenticationBadly(ditto) {
  await ditto.auth.setExpirationHandler(async (ditto) => {
    const result = await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
    if (result.error) throw result.error;
  });
}
```

`ditto.close()` waits for an expiration handler that is still running, so keep the handler's own work, such as fetching a token, bounded by a timeout (see [In JavaScript, close() waits for a running expiration handler](../../knowledge/observations/javascript-sdk.md#in-javascript-close-waits-for-a-running-expiration-handler)).

**Logging out**: `await ditto.auth.logout()` clears the credentials and stops sync; `ditto.auth.status` returns `{ isAuthenticated, userID }`, and `ditto.auth.observeStatus(callback)` returns an observer of changes (release it with `stop()`). `logout()` accepts a cleanup function, but it calls it without awaiting it, so an `async` cleanup finishes after `logout()` has resolved and a rejection in it is not handled (see [In JavaScript, logout() does not wait for its cleanup function](../../knowledge/observations/javascript-sdk.md#in-javascript-logout-does-not-wait-for-its-cleanup-function)). Remove local data after `await ditto.auth.logout()` instead, as below.

### Switching users in JavaScript

The order of the steps is in [Switching users on a shared device](../setup-and-lifecycle.md#switching-users-on-a-shared-device).

```javascript
// ✅ GOOD: Sign a user out of a shared device. waitUntilServerHas() is defined
// in "Closing Ditto in JavaScript"; OrderSync owns the subscriptions (see
// "Subscriptions in JavaScript").
export async function signOut(ditto, orderSync, { storeId, lastCommitId = null }) {
  if (lastCommitId !== null && !(await waitUntilServerHas(ditto, lastCommitId))) {
    // Evicting now could discard changes that no other device has yet.
    showError('Some changes have not been uploaded yet. Try again online.');
    return false;
  }
  // Components cancel their own observers when the user leaves them.
  orderSync.leaveStore(); // cancel first, or evicted documents sync back
  await ditto.auth.logout(); // stops sync
  // logout() does not await a cleanup function, so evict afterwards.
  await ditto.store.execute('EVICT FROM orders WHERE storeId = :storeId', { storeId });
  await ditto.store.execute('EVICT FROM orderItems WHERE storeId = :storeId', { storeId });
  const left = await ditto.store.execute(
    'SELECT COUNT(*) AS n FROM orders WHERE storeId = :storeId',
    { storeId },
  );
  return left.items[0].value.n === 0;
}
```

## Sync and the App Lifecycle in JavaScript

`ditto.sync.start()` and `ditto.sync.stop()` are synchronous and return nothing; `start()` throws if sync cannot start, for example `DittoError` `authentication/expiration-handler-missing` for a server connection without an expiration handler, or a plain `Error` (`Sync could not be started because Ditto has not yet been activated. ...`) in small-peers-only mode without `setOfflineOnlyLicenseToken()`. On Node.js, active sync keeps the process running until you stop it. The rules are in [Starting and Stopping Sync](../setup-and-lifecycle.md#starting-and-stopping-sync).

```javascript
// ✅ GOOD: Start sync only when it is not already running.
export function ensureSyncStarted(ditto) {
  if (!ditto.sync.isActive) {
    ditto.sync.start(); // throws if prerequisites are missing
  }
}
```

```javascript
// ❌ BAD: For server connections, sync.start() throws
// authentication/expiration-handler-missing because no handler is set yet,
// so the handler below is never registered.
export async function startTooEarly(ditto) {
  ditto.sync.start();
  await ditto.auth.setExpirationHandler(async () => {});
}
```

Do not call `ditto.close()` when the app or tab goes to the background: every later call on the instance fails. To stop syncing while the app is in the background, stop and restart sync. The class below does that and resumes only the sync that it paused. In a browser, drive it from the page's visibility, as `pauseSyncWhileHidden()` does; in React Native, call `pause()` and `resume()` from an `AppState` `change` listener.

```javascript
// ✅ GOOD: For apps that must not sync in the background: pause sync without
// closing Ditto, and resume only the sync that this object paused.
export class SyncPauser {
  #ditto;
  #pausedHere = false;

  constructor(ditto) {
    this.#ditto = ditto;
  }

  pause() {
    if (this.#ditto.sync.isActive) {
      this.#ditto.sync.stop(); // the local store stays usable
      this.#pausedHere = true;
    }
  }

  resume() {
    if (!this.#pausedHere) return;
    this.#pausedHere = false;
    try {
      this.#ditto.sync.start();
    } catch (error) {
      showError(error); // for example, prerequisites changed in the background
    }
  }
}

// Browsers: pause while the tab is hidden. Returns a function that removes the listener.
export function pauseSyncWhileHidden(ditto) {
  const pauser = new SyncPauser(ditto);
  const onChange = () => (document.visibilityState === 'hidden' ? pauser.pause() : pauser.resume());
  document.addEventListener('visibilitychange', onChange);
  return () => document.removeEventListener('visibilitychange', onChange);
}
```

A Node.js service closes Ditto when the process is asked to stop, so that pending writes complete and the directory is released:

```javascript
// ✅ GOOD (Node.js): Close Ditto once on SIGTERM or SIGINT, then exit.
export function closeOnSignals(service) {
  let closing = null;
  const stop = (signal) => {
    closing ??= service
      .close()
      .catch((error) => showError(error))
      .finally(() => process.exit(signal === 'SIGINT' ? 130 : 0));
  };
  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);
}
```

## Closing Ditto in JavaScript

| Object | How to release | Notes |
|---|---|---|
| `Ditto` | `await ditto.close()` | Releases everything below as well |
| `StoreObserver` | `observer.cancel()` | Also `using observer = ...` (SDK 5.1+) |
| `SyncSubscription` | `subscription.cancel()` | Required to stop syncing the data it matched; also `using` (SDK 5.1+) |
| `Observer` from `presence.observe()`, `auth.observeStatus()`, and `observeTransportConditions()` | `observer.stop()` | Also `using` (SDK 5.1+). Its `isStopped` is inverted: `true` while the observer is active, `false` after `stop()` (see [In JavaScript, Observer.isStopped is true while the observer is active](../../knowledge/observations/javascript-sdk.md#in-javascript-observerisstopped-is-true-while-the-observer-is-active)) |
| `AttachmentFetcher` | `fetcher.stop()` | Only needed to cancel a fetch in progress |
| Connection request handler | `ditto.presence.connectionRequestHandler = null` | |
| Custom log callback | `await Logger.setCustomLogCallback(undefined)` | `close()` does not remove it |

Release store observers and subscriptions explicitly: an observer or a subscription whose JavaScript object has been garbage-collected keeps running until you cancel it through `ditto.store.observers` or `ditto.sync.subscriptions`, or close Ditto (see [In JavaScript, garbage-collected subscriptions and observers keep running](../../knowledge/observations/javascript-sdk.md#in-javascript-garbage-collected-subscriptions-and-observers-keep-running)). These two lists return other objects than the registration did, but `cancel()` on them works. `ditto.store.attachmentFetchers` lists the active fetchers.

`ditto.close()` in JavaScript:
- **Waits for pending work**: in our testing with SDK 5.0.3 to 5.2.0, `close()` waited for `execute()` calls and transactions in progress, also for writes started right after `close()` was called (see [In JavaScript, close() completes pending writes](../../knowledge/observations/javascript-sdk.md#in-javascript-close-completes-pending-writes) and [In JavaScript, close() waits for open transactions](../../knowledge/observations/javascript-sdk.md#in-javascript-close-waits-for-open-transactions)). A transaction or an expiration handler that never ends therefore keeps `close()` from completing.
- **Is safe to repeat**: a second `close()` resolves, and `ditto.isClosed` tells whether it was called.
- **After closing**, observers and subscriptions report `isCancelled === true`, and `cancel()` and `stop()` still work. Other calls fail with a plain `Error` (`Can't perform operation using a Ditto instance that has been closed.`), not a `DittoError`: `execute()`, `transaction()`, and `newAttachment()` return a rejected promise, while registrations and properties such as `sync.isActive` throw at once (see [In JavaScript, calls after close() throw or reject with a plain Error](../../knowledge/observations/javascript-sdk.md#in-javascript-calls-after-close-throw-or-reject-with-a-plain-error)). Query results read before closing stay readable.
- **Does not wait for changes to be sent**: a write right before `close()` stays on the device until the next sync.

Before you close Ditto at a point where data must reach another device, wait with a timeout until Ditto Server has confirmed the last write (see [Resource Cleanup and Shutdown](../setup-and-lifecycle.md#resource-cleanup-and-shutdown)). `commitID` is a `bigint`, and `synced_up_to_local_commit_id` in the result row is a number, so compare them as `bigint`s. Bound each read as well as the whole wait, because a read of `system:data_sync_info` can stop responding (see the note below):

```javascript
// Resolves to the result, or to null if the statement has not completed within ms.
async function executeWithin(ditto, query, ms) {
  let timer;
  try {
    return await Promise.race([
      ditto.store.execute(query),
      new Promise((resolve) => {
        timer = setTimeout(() => resolve(null), ms);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

// ✅ GOOD: Wait (with a timeout) until Ditto Server has confirmed a write.
export async function waitUntilServerHas(ditto, commitId, { timeoutMs = 10_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = await executeWithin(
      ditto,
      'SELECT * FROM system:data_sync_info WHERE is_ditto_server = true',
      deadline - Date.now(),
    );
    if (result === null) return false; // The read did not complete in time.
    const confirmed = result.items.some((item) => {
      const synced = item.value.documents?.synced_up_to_local_commit_id;
      return synced != null && BigInt(synced) >= commitId;
    });
    if (confirmed) return true;
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  return false; // The change stays on the device and syncs later.
}

// lastCommitId is the commitID of the last write that must be uploaded.
export async function endShift(ditto, lastCommitId) {
  if (lastCommitId !== null && !(await waitUntilServerHas(ditto, lastCommitId))) {
    showError('Some changes have not been uploaded yet.');
  }
  await ditto.close();
}
```

> **Note (SDK 5.1.0 and 5.2.0):** A read of `system:data_sync_info` on a device that is connected to another peer can stop responding. In our testing, the second read after connecting never completed, or an observer of it was called once and then no more, in 4 of 10 runs on SDK 5.2.0 with the other peer in another process, in 17 of 40 runs with both peers in one process, and in 1 of 16 runs on 5.1.0; reading more slowly did not prevent it. Afterwards, every later read of `system:data_sync_info` on that device hung, an observer of it was no longer called, and `close()` did not complete, while queries of other collections kept working (see [In JavaScript, a read of system:data_sync_info can stop responding](../../knowledge/observations/javascript-sdk.md#in-javascript-a-read-of-systemdata_sync_info-can-stop-responding)). Bound every wait for it, as `waitUntilServerHas()` does, and treat a timeout as "not confirmed".

```javascript
// ✅ GOOD: Release resources in reverse order of creation, then close.
// This is app-level shutdown: call shutdown() only when the whole app no
// longer needs Ditto. Components release their own observers and keep Ditto open.
export class AppShutdown {
  #ditto;
  #subscription = null;
  #observer = null;

  constructor(ditto) {
    this.#ditto = ditto;
  }

  start() {
    this.#subscription = this.#ditto.sync.registerSubscription('SELECT * FROM orders');
    this.#observer = this.#ditto.store.registerObserver(
      'SELECT * FROM orders ORDER BY createdAt DESC',
      (result) => console.log(`orders: ${result.items.length}`),
    );
  }

  async shutdown() {
    this.#observer?.cancel();
    this.#subscription?.cancel();
    await this.#ditto.close(); // waits for running queries, not for unsent changes
  }
}
```

## Executing DQL in JavaScript

Pass each statement with its arguments as a plain object whose keys are the parameter names without the colon. The argument object comes second for `execute` and `registerSubscription`, and **after the handler** for observers:

| Call | Returns |
|---|---|
| `await ditto.store.execute(query, args)` | `QueryResult` |
| `await tx.execute(query, args)` inside `ditto.store.transaction` | `QueryResult` (see [Transactions in JavaScript](#transactions-in-javascript)) |
| `ditto.store.registerObserver(query, handler, args)` | `StoreObserver` (see [Store Observers in JavaScript](#store-observers-in-javascript)) |
| `ditto.sync.registerSubscription(query, args)` | `SyncSubscription` (see [Subscriptions in JavaScript](#subscriptions-in-javascript)) |

A statement that Ditto rejects fails with a `DittoError` whose `code` names the kind of error (`query/invalid`, `query/arguments-invalid`, `query/unsupported`, `query/evaluation`, `store/transaction-read-only`) and whose message names the cause (see [When a Statement Fails or Returns Nothing](../dql.md#when-a-statement-fails-or-returns-nothing)). `execute()` and `tx.execute()` return a rejected promise, and `registerObserver()` and `registerSubscription()` throw at once, so put the `try` around the `await` for the first and around the call for the second (see [In JavaScript, invalid statements and arguments fail with a DittoError when the call is made](../../knowledge/observations/javascript-sdk.md#in-javascript-invalid-statements-and-arguments-fail-with-a-dittoerror-when-the-call-is-made)). The rules for parameters are in [Always pass values as parameters](../dql.md#always-pass-values-as-parameters).

```javascript
// ✅ GOOD: Values travel as typed parameters
export async function findOrders(ditto, customerId, statuses, pageSize) {
  const result = await ditto.store.execute(
    'SELECT * FROM orders ' +
      'WHERE customerId = :customerId AND status IN :statuses ' +
      'ORDER BY createdAt DESC LIMIT :pageSize',
    { customerId, statuses, pageSize },
  );
  return result.items.map((item) => item.value);
}
```

```javascript
// ❌ BAD: Interpolated values (injection risk, broken quoting, no statement reuse)
export async function findOrdersUnsafe(ditto, customerId) {
  await ditto.store.execute(`SELECT * FROM orders WHERE customerId = '${customerId}'`);
}
```

Validate values before you write them, then pass them as parameters (see [Input Validation and Query Parameters](../security.md#input-validation-and-query-parameters)):

```javascript
// ✅ GOOD: Validate, then pass values as parameters.
const allowedStatuses = new Set(['open', 'preparing', 'done']);

export async function updateOrderStatus(ditto, orderId, status) {
  if (typeof orderId !== 'string' || orderId === '' || !allowedStatuses.has(status)) {
    throw new TypeError('Invalid order update');
  }
  await ditto.store.execute('UPDATE orders SET status = :status WHERE _id = :id', {
    id: orderId,
    status,
  });
}
```

**A map key in a path**: a path cannot be passed as a parameter, so validate a map key against a strict pattern before you place it inside a backtick-quoted path segment, and pass every value as a parameter (see [Adding, updating, and removing map entries](../data-modeling.md#adding-updating-and-removing-map-entries)). In a JavaScript template literal, write the DQL backticks as `` \` ``.

```javascript
// Map keys used in paths are validated: only lowercase UUID-shaped keys are accepted.
const uuidKey = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Removes one line item. A path cannot be passed as a parameter, so the key
// is validated before it is placed inside a backtick-quoted path segment.
export async function removeOrderItem(ditto, { orderId, itemId }) {
  if (!uuidKey.test(itemId)) {
    throw new TypeError(`itemId must be a lowercase UUID: ${itemId}`);
  }
  await ditto.store.execute(`UPDATE orders UNSET items.\`${itemId}\` WHERE _id = :id`, {
    id: orderId,
  });
}
```

**Handling the size error**: a write that would take a document over the hard size limit rejects with a `DittoError` whose `code` is `query/evaluation` and whose message contains `exceeds limit of ... bytes`; handle it at the call site that may produce it (see [Document Size Limits](../data-modeling.md#document-size-limits)).

```javascript
import { DittoError } from '@dittolive/ditto';

// ✅ GOOD: Handle the size error at the call site that may produce it.
export async function saveNotes(ditto, visitId, notes) {
  try {
    await ditto.store.execute('UPDATE visits SET notes = :notes WHERE _id = :id', {
      id: visitId,
      notes,
    });
    return true;
  } catch (error) {
    if (!(error instanceof DittoError)) throw error;
    // The message contains "exceeds limit of ... bytes" for oversized documents.
    showError(error); // your app's error UI
    return false;
  }
}
```

**Batched eviction**: `EVICT ... LIMIT ... RETURNING COUNT(*)` in a loop until the count is 0 (see [Batching evictions](../deletion-and-storage.md#batching-evictions)). First cancel or narrow every subscription that matches these documents.

```javascript
// ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict.
// First cancel or narrow every subscription that matches these documents (see EVICT).
export async function evictInBatches(ditto, cutoff) {
  let total = 0;
  while (true) {
    const result = await ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 RETURNING COUNT(*) AS evicted',
      { cutoff },
    );
    const evicted = result.items[0].value.evicted;
    total += evicted;
    if (evicted === 0) return total;
  }
}
```

**Development helpers for `ADVISE` and `PROFILE`**: `ADVISE` returns one row whose `advice` object holds `suggestedIndexes` (or an `outcome` when there is nothing to suggest), and `PROFILE` appends a row with the key `~request_profile` after the normal results (see [ADVISE (SDK 5.1+)](../indexing-and-performance.md#advise-sdk-51) and [Measuring with PROFILE](../indexing-and-performance.md#measuring-with-profile)). Profiles contain integers that come back as `bigint`, which `JSON.stringify` cannot write without a replacer. Use these helpers during development only.

```javascript
// ✅ GOOD (development only): print index suggestions for a query.
export async function printIndexAdvice(ditto, query, args = {}) {
  const result = await ditto.store.execute(`ADVISE ${query}`, args);
  const advice = result.items[0].value.advice;
  const suggested = advice.suggestedIndexes ?? [];
  if (suggested.length === 0) console.log(`No suggestions: ${advice.outcome}`);
  for (const index of suggested) {
    console.log(`${index.reason}\n  ${index.statement}`);
  }
}
```

```javascript
// Writes bigint values as strings, so that JSON.stringify accepts any row.
export const jsonReplacer = (key, value) => (typeof value === 'bigint' ? value.toString() : value);

// ✅ GOOD (development only): separate the profile row from the results.
export async function profileQuery(ditto, query, args = {}) {
  const result = await ditto.store.execute(`PROFILE ${query}`, args);
  const rows = result.items.map((item) => item.value);
  const profile = rows.findLast((row) => '~request_profile' in row)?.['~request_profile'];
  const resultCount = rows.length - (profile ? 1 : 0);
  console.log(`rows=${resultCount} times=${JSON.stringify(profile?.times, jsonReplacer)}`);
  console.log(JSON.stringify(profile?.plan, jsonReplacer, 2));
}
```

**Execution model**: on Node.js, `ditto.store.execute()` evaluates the query outside the JavaScript thread, but the result's rows are created on it, and reading `item.value` decodes each row on it. In our testing with SDK 5.1.0 and 5.2.0, the event loop kept running while an aggregate over 40,000 documents was evaluated (the longest pause of a 2 ms timer was 2 to 9 ms), but `SELECT *` of the 40,000 documents paused it for 65 to 139 ms before any value was read, and reading their values for another 216 to 445 ms (see [Query Scope and Execution](../indexing-and-performance.md#query-scope-and-execution) and [In JavaScript on Node.js, queries run off the event loop, but large results block it](../../knowledge/observations/javascript-sdk.md#in-javascript-on-nodejs-queries-run-off-the-event-loop-but-large-results-block-it)). Select only the rows and fields you need, and read `value` only for the rows you use.

**One query instead of a loop**: each `execute` call has a fixed cost, so read a list of documents with one `_id IN :ids` query (see [Query Scope and Execution](../indexing-and-performance.md#query-scope-and-execution)).

```javascript
// ❌ BAD: one query per ID
export async function loadOrdersOneByOne(ditto, ids) {
  const orders = [];
  for (const id of ids) {
    const result = await ditto.store.execute('SELECT * FROM orders WHERE _id = :id', { id });
    orders.push(...result.items.map((item) => item.value));
  }
  return orders;
}

// ✅ GOOD: one query, planned as an ID scan
export async function loadOrdersByIds(ditto, ids) {
  const result = await ditto.store.execute('SELECT * FROM orders WHERE _id IN :ids', { ids });
  return result.items.map((item) => item.value);
}
```

### Arguments and value types in JavaScript

Pass values that map to JSON: strings, numbers, booleans, `null`, arrays, and plain objects; `Uint8Array` for bytes and `bigint` for integers beyond 2^53. Other JavaScript values change on the way into the store, mostly without an error. In our testing with SDK 5.1.0 and 5.2.0 (see [JavaScript values that are not plain JSON change when stored](../../knowledge/observations/javascript-sdk.md#javascript-values-that-are-not-plain-json-change-when-stored) and [In JavaScript, function, Symbol, and Set values are stored as empty objects](../../knowledge/observations/javascript-sdk.md#in-javascript-function-symbol-and-set-values-are-stored-as-empty-objects)):

| JavaScript value | Stored as (`type()`) | Read back as |
|---|---|---|
| `Date` | `object` | `{}`: the time is lost. Store an ISO-8601 string instead (see [IDs and Timestamps in JavaScript](#ids-and-timestamps-in-javascript)) |
| `undefined` as a field value | `null` | `null`, so the field no longer matches `IS MISSING`; leave the field out instead |
| `NaN`, `Infinity` | not written | The statement rejects with `query/arguments-invalid` |
| `10.0` | `integer` | `10`: JavaScript has no whole-number floats (see [Integers and floats are equal in WHERE but separate in GROUP BY](../../knowledge/observations/dql-behavior.md#integers-and-floats-are-equal-in-where-but-separate-in-group-by)) |
| `bigint` | `integer` | `bigint` when its magnitude is 2^53 or more, otherwise a number |
| An integer of 2^53 or more in the store, also from a DQL literal | `integer` | `bigint`, which `JSON.stringify` cannot serialize |
| `Uint8Array`, `ArrayBuffer` | `binary` | `Uint8Array` |
| `Map` | `object` | A plain object with the map's entries |
| `Set`, a function, a `Symbol` | `object` | `{}`: the contents are lost |
| A string with an unpaired surrogate | `string` | A different string (see [char_length counts code points, and JavaScript damages lone surrogates](../../knowledge/observations/dql-behavior.md#char_length-counts-code-points-and-javascript-damages-lone-surrogates)) |

Text that contains backslashes, such as a Windows path, is safest as an argument written with `String.raw`, because a statement written inside a JavaScript string is unescaped twice, first by JavaScript and then by DQL (see [Literals](../dql.md#literals)):

```javascript
// ✅ GOOD: The path is passed as data and stored exactly as given
export async function saveExportPath(ditto) {
  await ditto.store.execute('UPDATE settings SET exportPath = :path WHERE _id = :id', {
    id: 'device',
    path: String.raw`C:\temp\exports`,
  });
}
```

### Query results in JavaScript

`ditto.store.execute` resolves to a `QueryResult` (see [Working with Query Results](../dql.md#working-with-query-results)):

| Member | Type | Description |
|---|---|---|
| `items` | `QueryResultItem[]` | The result rows, an array |
| `item.value` | object | The row decoded into JavaScript values. Decoded on first access, then cached: every read returns **the same object** until `item.dematerialize()` |
| `item.jsonString()` | `string` | The row as a JSON string, with exact 64-bit integers (a method; not cached) |
| `item.cborData()` | `Uint8Array` | The row as CBOR bytes (a method; not cached) |
| `mutatedDocumentIDsV2()` | `Array` | IDs of documents changed by a write, as strings or objects for composite IDs. A method that builds a new array on every call; call it once and keep the array. There is no `mutatedDocumentIDs()` in JavaScript. |
| `commitID` | `bigint \| null` | ID of the local commit for a mutating statement; `null` for reads |

Because `item.value` returns the same object, a change to it is visible to every later read of that item but never reaches the store (see [In JavaScript, query results return the same objects](../../knowledge/observations/javascript-sdk.md#in-javascript-query-results-return-the-same-objects)). Copy a row before you edit it for display, and write changes with `UPDATE`. Results stay readable after `close()`, and they are released with garbage collection; do not keep them in caches or across observer callbacks.

```javascript
// Read: convert rows to plain values right away
export async function openOrders(ditto) {
  const result = await ditto.store.execute(
    'SELECT _id, total, status FROM orders WHERE status = :status ORDER BY _id',
    { status: 'open' },
  );
  return result.items.map((item) => item.value);
}

// Write: inspect which documents changed
export async function closeOrders(ditto, ids) {
  const result = await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id IN :ids',
    { status: 'closed', ids },
  );
  const commitId = result.commitID; // a bigint; null for reads
  console.log(`Committed as ${commitId}`);
  return result.mutatedDocumentIDsV2(); // call once and keep the array
}

// Alternative encoding, for example to send rows to a worker or a server
export async function openOrdersAsJson(ditto) {
  const result = await ditto.store.execute('SELECT * FROM orders WHERE status = :status', {
    status: 'open',
  });
  return result.items.map((item) => item.jsonString());
}
```

```javascript
export class Order {
  constructor({ id, status, total }) {
    this.id = id;
    this.status = status;
    this.total = total;
  }

  static fromValue(value) {
    return new Order({
      id: value._id,
      status: typeof value.status === 'string' ? value.status : 'unknown',
      total: typeof value.total === 'number' ? value.total : 0,
    });
  }
}

// ✅ GOOD: One pass, plain objects out
export async function loadOpenOrderModels(ditto) {
  const result = await ditto.store.execute(
    'SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id',
    { status: 'open' },
  );
  return result.items.map((item) => Order.fromValue(item.value));
}
```

**Deriving values at read time**: compute totals and the current status from the stored source data when you read a document, and skip entries whose required fields are missing or `null` (see [Do not store derived values that can diverge](../data-modeling.md#do-not-store-derived-values-that-can-diverge) and [Pattern 1: Audit-log map inside the document](../data-modeling.md#pattern-1-audit-log-map-inside-the-document)).

```javascript
// ✅ GOOD: Store the source data; derive totals at read time. Entries with a
// missing or null price or quantity (an entry removed on one device while
// another device edited it) are skipped instead of crashing the screen.
export function orderSubtotalCents(order) {
  let subtotal = 0;
  for (const entry of Object.values(order.items ?? {})) {
    const price = entry?.unitPriceCents;
    const quantity = entry?.quantity;
    if (!Number.isInteger(price) || !Number.isInteger(quantity)) continue;
    subtotal += price * quantity;
  }
  return subtotal;
}
```

```javascript
// The workflow states, from earliest to most advanced.
const statusOrder = ['created', 'confirmed', 'shipped', 'delivered'];

// Derives the current status as the most advanced state, so a late write from
// a device that was offline cannot move the order backwards.
export function currentStatus(order) {
  let best = null;
  for (const status of Object.values(order.statusLog ?? {})) {
    if (typeof status !== 'string') continue;
    if (best === null || statusOrder.indexOf(status) > statusOrder.indexOf(best)) {
      best = status;
    }
  }
  return best;
}
```

**Tolerating older documents**: a model class reads a field that newer app versions added with a default, because older documents do not have it (see [Prefer additive changes](../data-modeling.md#prefer-additive-changes)).

```javascript
// ✅ GOOD: A new field, read with a default for older documents.
export class Car {
  constructor({ id, make, mileageKm = null }) {
    this.id = id;
    this.make = make;
    this.mileageKm = mileageKm; // added in app version 2; absent in older documents
  }

  static fromDocument(doc) {
    return new Car({
      id: doc._id,
      make: doc.make,
      mileageKm: Number.isInteger(doc.mileageKm) ? doc.mileageKm : null,
    });
  }
}
```

## Subscriptions in JavaScript

`ditto.sync.registerSubscription(query, args)` returns a `SyncSubscription`; release it with `subscription.cancel()`, which does nothing if it is already cancelled or Ditto was closed. Registering a query that subscriptions do not accept, such as one with a projection, throws a `DittoError` whose `code` is `query/unsupported` (see [Subscription Rules](../sync-and-subscriptions.md#subscription-rules)). The rules for when to register and cancel are in [Subscription Lifecycle](../sync-and-subscriptions.md#subscription-lifecycle).

```javascript
// ✅ GOOD: A session-level service owns long-lived subscriptions.
export class OrderSync {
  #ditto;
  #subscriptions = [];
  #storeId = null;

  constructor(ditto) {
    this.#ditto = ditto;
  }

  // Call once after login or when the user enters a store.
  enterStore(storeId) {
    if (storeId === this.#storeId) return; // Already subscribed; do not re-register.
    this.leaveStore();
    this.#storeId = storeId;
    // Scope by stable partition keys; the UI filters further with local queries.
    this.#subscriptions.push(
      this.#ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId }),
      this.#ditto.sync.registerSubscription('SELECT * FROM orderItems WHERE storeId = :storeId', { storeId }),
    );
  }

  // Call on logout or when the user leaves the store.
  leaveStore() {
    for (const subscription of this.#subscriptions) {
      subscription.cancel(); // Does nothing if already cancelled or Ditto was closed.
    }
    this.#subscriptions = [];
    this.#storeId = null;
  }
}
```

```jsx
// ❌ BAD: A new subscription on every render, never cancelled.
export function OrdersBadge({ ditto, storeId }) {
  // A component can render many times per second; each render adds a
  // subscription that keeps replicating until the Ditto instance is closed.
  ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId });
  return <span className="orders-badge">Orders</span>;
}
```

When the user changes a filter, replace the component's observer, not the subscription (see [Filter locally instead of re-registering](../sync-and-subscriptions.md#filter-locally-instead-of-re-registering)). The effect's dependencies make React cancel the old observer and register a new one whenever they change:

```jsx
import { useEffect, useState } from 'react';

// ✅ GOOD: The subscription (owned by OrderSync) stays stable; only the local observer changes.
export function OrdersByStatus({ ditto, storeId, status }) {
  const [orders, setOrders] = useState([]);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT * FROM orders WHERE storeId = :storeId AND status = :status ORDER BY createdAt DESC, _id',
      (result) => setOrders(result.items.map((item) => item.value)),
      { storeId, status },
    );
    return () => observer.cancel(); // Replacing a local observer is cheap.
  }, [ditto, storeId, status]);

  return (
    <ul>
      {orders.map((order) => (
        <li key={order._id}>
          {order._id} ({order.status})
        </li>
      ))}
    </ul>
  );
}
```

To switch stores, cancel first, then evict, then subscribe (see [Cancelling subscriptions and local data](../sync-and-subscriptions.md#cancelling-subscriptions-and-local-data)):

```javascript
// ✅ GOOD: Switching stores: cancel first, then evict data the device no longer needs.
export async function switchStore(ditto, currentSubscriptions, newStoreId) {
  // 1. Stop asking for the old store's data.
  for (const subscription of currentSubscriptions) subscription.cancel();

  // 2. Remove the old store's documents from this device only.
  await ditto.store.execute('EVICT FROM orders WHERE storeId != :storeId', { storeId: newStoreId });
  await ditto.store.execute('EVICT FROM orderItems WHERE storeId != :storeId', { storeId: newStoreId });

  // 3. Ask for the new store's data.
  return [
    ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId: newStoreId }),
    ditto.sync.registerSubscription('SELECT * FROM orderItems WHERE storeId = :storeId', { storeId: newStoreId }),
  ];
}
```

`ditto.sync.subscriptions` returns the active subscriptions; their `queryString` and `queryArguments` describe what each one matches, and a subscription without arguments has no `queryArguments` (`null` or `undefined`; see [In JavaScript, a subscription without arguments has no queryArguments](../../knowledge/observations/javascript-sdk.md#in-javascript-a-subscription-without-arguments-has-no-queryarguments)). After `await ditto.close()`, every subscription reports `isCancelled === true`.

**Upload status**: one lightweight observer of `system:data_sync_info` per screen, which re-renders only when the derived state changes, and the writes whose `commitID` it tracks (see [Monitoring Sync Status](../sync-and-subscriptions.md#monitoring-sync-status)):

```jsx
import { useEffect, useState } from 'react';

// ✅ GOOD: One lightweight observer that re-renders only when the derived state changes.
// Use one instance per screen (for example, in the header), not one per list row.
export function UploadStatusIcon({ ditto, commitId }) {
  const [uploaded, setUploaded] = useState(false);

  useEffect(() => {
    // May fire often, so keep the callback trivial.
    const observer = ditto.store.registerObserver(
      'SELECT * FROM system:data_sync_info WHERE is_ditto_server = true',
      (result) => {
        const isUploaded = result.items.some((item) => {
          const synced = item.value.documents?.synced_up_to_local_commit_id;
          return synced != null && BigInt(synced) >= commitId;
        });
        setUploaded(isUploaded); // React bails out when the value is unchanged.
      },
    );
    return () => observer.cancel();
  }, [ditto, commitId]);

  return <span aria-label={uploaded ? 'Uploaded' : 'Waiting to upload'}>{uploaded ? '☁️✓' : '☁️…'}</span>;
}
```

```javascript
// Obtain the commit ID from the write you want to track.
export async function submitOrder(ditto, order) {
  const result = await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', { order });
  return result.commitID; // a bigint for local writes; null for SELECT.
}
```

```javascript
// ✅ GOOD: Track the commitID only if the upsert actually changed the document.
export async function saveSettings(ditto, settings) {
  const result = await ditto.store.execute(
    'INSERT INTO settings DOCUMENTS (:settings) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    { settings },
  );
  // An unchanged document still gets a commitID, but peers confirm it only
  // with their next sync exchange (up to about 27 seconds later).
  return result.mutatedDocumentIDsV2().length === 0 ? null : result.commitID;
}
```

**Subscriptions for a JOIN**: a feature-level service creates the index of the join key and subscribes to every collection that the join reads (see [Separate collections with JOIN (SDK 5.1+)](../data-modeling.md#separate-collections-with-join-sdk-51)).

```javascript
// Keeps the three collections needed by the order screens in sync.
// Subscriptions belong to an app- or feature-level service, not to a component.
export class StoreSync {
  #subscriptions = [];

  constructor(ditto, storeId) {
    this.ditto = ditto;
    this.storeId = storeId;
  }

  async start() {
    await this.ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)',
    );
    this.#subscriptions.push(
      this.ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId: this.storeId }),
      this.ditto.sync.registerSubscription('SELECT * FROM orderItems WHERE storeId = :storeId', { storeId: this.storeId }),
      this.ditto.sync.registerSubscription('SELECT * FROM products'),
    );
  }

  stop() {
    for (const subscription of this.#subscriptions) subscription.cancel();
    this.#subscriptions = [];
  }
}
```

If the key of a joined observer (such as the `orderId`) can change while the component is mounted, list it in the effect's dependencies so that the observer is registered again.

**Retention windows**: a long-lived service that keeps only recent documents moves the boundary of its subscription and evicts the complement in three steps: cancel the subscription, evict with the new cutoff, and subscribe again with the same cutoff, even if the eviction failed (see [Time-based eviction](../deletion-and-storage.md#time-based-eviction)). `utcTimestamp()` is defined in [IDs and Timestamps in JavaScript](#ids-and-timestamps-in-javascript).

```javascript
const dayMs = 24 * 60 * 60 * 1000;

// ✅ GOOD: Keep the last 7 days of orders on this device.
export class OrderRetention {
  static retentionMs = 7 * dayMs;
  #subscription = null;

  constructor(ditto) {
    this.ditto = ditto;
  }

  // Same fixed-precision format as createdAt (utcTimestamp() from "IDs and Timestamps in JavaScript").
  #cutoff() {
    return utcTimestamp(new Date(Date.now() - OrderRetention.retentionMs));
  }

  // Call once at startup (before ditto.sync.start()).
  start() {
    this.#subscription = this.#subscribeFrom(this.#cutoff());
  }

  // Call on a schedule, for example once a day.
  async evictExpired() {
    const cutoff = this.#cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    this.#subscription?.cancel();

    try {
      // 2. Evict exactly the complement of the new subscription.
      const result = await this.ditto.store.execute('EVICT FROM orders WHERE createdAt < :cutoff', {
        cutoff,
      });
      return result.mutatedDocumentIDsV2().length;
    } finally {
      // 3. Subscribe again with the moved boundary, even if the eviction failed.
      this.#subscription = this.#subscribeFrom(cutoff);
    }
  }

  #subscribeFrom(cutoff) {
    return this.ditto.sync.registerSubscription('SELECT * FROM orders WHERE createdAt >= :cutoff', {
      cutoff,
    });
  }

  dispose() {
    this.#subscription?.cancel();
  }
}
```

The same steps keep active orders and orders soft-deleted within a retention window, and evict older soft-deleted orders (Variant B in [Soft delete, subscriptions, and cleanup](../deletion-and-storage.md#soft-delete-subscriptions-and-cleanup)):

```javascript
// ✅ GOOD (Variant B): A long-lived service keeps active orders and orders
// deleted within the retention window, and evicts older deleted orders.
export class OrderSoftDeleteRetention {
  // Longer than the longest time a device is expected to stay offline.
  static retentionMs = 30 * 24 * 60 * 60 * 1000;
  #subscription = null;

  constructor(ditto, storeId) {
    this.ditto = ditto;
    this.storeId = storeId;
  }

  // Same fixed-precision format as deletedAt (utcTimestamp() from "IDs and Timestamps in JavaScript").
  #cutoff() {
    return utcTimestamp(new Date(Date.now() - OrderSoftDeleteRetention.retentionMs));
  }

  // Call once at startup (before ditto.sync.start()).
  start() {
    this.#subscription = this.#subscribe(this.#cutoff());
  }

  // Call on a schedule, at most about once a day.
  async evictExpired() {
    const cutoff = this.#cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    this.#subscription?.cancel();

    try {
      // 2. Evict only documents outside the new subscription.
      await this.ditto.store.execute(
        'EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff',
        { storeId: this.storeId, cutoff },
      );
    } finally {
      // 3. Subscribe again with the moved boundary, even if the eviction failed.
      this.#subscription = this.#subscribe(cutoff);
    }
  }

  #subscribe(cutoff) {
    return this.ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId ' +
        'AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)',
      { storeId: this.storeId, cutoff },
    );
  }

  dispose() {
    this.#subscription?.cancel();
  }
}
```

## Store Observers in JavaScript

`ditto.store.registerObserver(query, handler, args)` returns a `StoreObserver`. Register it in an effect (or in a service), keep only plain values in state, and cancel the observer in the effect's cleanup. The handler is called with the first result after `registerObserver` has returned, and then whenever the result changes. The rules that every SDK shares are in [Observing Changes](../observers.md).

```jsx
import { useEffect, useState } from 'react';

// ✅ GOOD: The recommended observer pattern for components.
export function OrdersList({ ditto }) {
  const [orders, setOrders] = useState([]);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      (result) => setOrders(result.items.map((item) => item.value)),
      { status: 'open' },
    );
    return () => observer.cancel();
  }, [ditto]);

  return (
    <ul>
      {orders.map((order) => (
        <li key={order._id}>{order._id}</li>
      ))}
    </ul>
  );
}
```

**✅ DO:**
- Register observers in an effect (or in a service), never in the component body.
- Copy plain values out of the result (`item.value`, or your own model objects) before storing them in state; do not keep `QueryResult` or `QueryResultItem` objects around (see [Query results in JavaScript](#query-results-in-javascript)).
- Add `ORDER BY` with a tie-breaker whenever the order of results matters (see [Stable ordering](../observers.md#stable-ordering)).
- Return a cleanup that calls `observer.cancel()`, and list the query's arguments in the effect's dependencies.
- Catch errors inside the handler.

**❌ DON'T:**
- Pass an `async` handler that can reject: the SDK does not handle the promise it returns (see below).
- Rely on garbage collection to stop an observer.
- Create an observer per list item; observe the list once and pass values down.

An exception that the handler throws synchronously is discarded, and the observer keeps being called. An `async` handler returns a promise that the SDK neither awaits nor handles: in our testing with SDK 5.1.0 and 5.2.0, every rejection became an unhandled promise rejection, and without a handler for those, Node.js ended the process at the first callback (see [In JavaScript, exceptions thrown synchronously in observer callbacks are discarded](../../knowledge/observations/javascript-sdk.md#in-javascript-exceptions-thrown-synchronously-in-observer-callbacks-are-discarded) and [In JavaScript, an async observer callback that rejects causes an unhandled rejection](../../knowledge/observations/javascript-sdk.md#in-javascript-an-async-observer-callback-that-rejects-causes-an-unhandled-rejection)).

```javascript
// ❌ BAD: An async handler that can reject. Each failure is an unhandled
// rejection, which ends a Node.js process by default.
export function observeAndPrintBadly(ditto, printReceipt) {
  return ditto.store.registerObserver('SELECT * FROM orders WHERE status = :status', async (result) => {
    for (const item of result.items) await printReceipt(item.value);
  }, { status: 'ready' });
}

// ✅ GOOD: Keep the handler synchronous, and catch the async work that it starts.
export function observeAndPrint(ditto, printReceipt) {
  return ditto.store.registerObserver('SELECT * FROM orders WHERE status = :status', (result) => {
    const orders = result.items.map((item) => item.value);
    Promise.all(orders.map((order) => printReceipt(order))).catch((error) => showError(error));
  }, { status: 'ready' });
}
```

For work that must not overlap, use the backpressure API in [Backpressure in JavaScript](#backpressure-in-javascript).

### Observer lifecycle in JavaScript

| Behavior | Consequence |
|---|---|
| The first callback comes after `registerObserver` has returned, with the current result | Initialize state to an empty value; there is no separate "loading" event |
| `observer.cancel()` stops callbacks; `isCancelled` reports it | Call it in the effect's cleanup or the service's `dispose()` |
| A `StoreObserver` whose object was garbage-collected keeps running | Never drop the handle; cancel it, or find it in `ditto.store.observers` |
| `using observer = ditto.store.registerObserver(...)` cancels the observer at the end of the block (SDK 5.1+) | Useful in scripts and tests; in React, cancel in the cleanup |
| React's Strict Mode runs effects twice in development | The cleanup cancels the first observer before the second is registered; nothing leaks |
| `await ditto.close()` cancels every observer (`isCancelled === true`) | Cancelling afterwards does nothing and raises no error |

In our testing with SDK 5.2.0 on Node.js 24, a `using` declaration cancelled the observer at the end of its block, and it disappeared from `ditto.store.observers` (see [In JavaScript, using cancels observers and subscriptions at the end of the block](../../knowledge/observations/javascript-sdk.md#in-javascript-using-cancels-observers-and-subscriptions-at-the-end-of-the-block)).

A reusable hook keeps the registration and cleanup in one place. It takes the arguments as a JSON-compatible object and re-registers the observer only when their JSON changes, so callers can pass a new object on every render:

```jsx
import { useEffect, useState } from 'react';

// ✅ GOOD: A hook that owns one observer per component and returns plain rows.
export function useDittoQuery(ditto, query, args = {}) {
  const argsKey = JSON.stringify(args);
  const [rows, setRows] = useState(null); // null until the first result

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      query,
      (result) => setRows(result.items.map((item) => item.value)),
      JSON.parse(argsKey),
    );
    return () => observer.cancel();
  }, [ditto, query, argsKey]);

  return rows;
}

export function OpenOrdersWithHook({ ditto }) {
  const orders = useDittoQuery(
    ditto,
    'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
    { status: 'open' },
  );
  if (orders === null) return <p>Loading…</p>;
  return (
    <ul>
      {orders.map((order) => (
        <li key={order._id}>{order._id}</li>
      ))}
    </ul>
  );
}
```

With state libraries (Redux, Zustand, MobX, or a context provider), let one store module own each observer, cancel it when the module or provider is torn down, and keep only plain values in the state.

Scripts and tests can rely on `using` instead of a cleanup:

```javascript
// ✅ GOOD (scripts and tests, SDK 5.1+): `using` cancels the observer when the block ends.
export async function countOpenOrdersOnce(ditto) {
  const counts = [];
  {
    using observer = ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      (result) => counts.push(result.items[0].value.n),
      { status: 'open' },
    );
    await new Promise((resolve) => setTimeout(resolve, 100)); // let the first result arrive
    void observer; // cancelled when the block ends
  }
  return counts.at(-1) ?? 0;
}
```

### Backpressure in JavaScript

`registerObserver` asks for the next result as soon as the handler **returns**. A synchronous handler therefore gets automatic backpressure, but an `async` handler returns at its first `await`, so calls overlap: in our testing with SDK 5.0.3 to 5.2.0, a handler that took 600 ms on one call ran at the same time as the next call, and that slow call finished last, so the final state showed 1 document while the store held 5 (see [In JavaScript, registerObserver does not await async callbacks](../../knowledge/observations/javascript-sdk.md#in-javascript-registerobserver-does-not-await-async-callbacks)). Keep the handler short and synchronous.

```javascript
// ❌ BAD: Slow async work per update without backpressure; uploads overlap,
// and an older upload can finish after a newer one.
export function uploadOnEveryChange(ditto, uploadOrders) {
  return ditto.store.registerObserver('SELECT * FROM orders WHERE status = :status', async (result) => {
    try {
      await uploadOrders(result.items.map((item) => item.value));
    } catch (error) {
      showError(error);
    }
  }, { status: 'open' });
}
```

For slow or asynchronous work per update, use `registerObserverWithSignalNext(query, (result, signalNext) => { ... }, args)`: Ditto delivers one result and then waits until you call `signalNext()`; changes that happen meanwhile are merged into one later call with the latest result (see [Backpressure (SDK 5.1+)](../observers.md#backpressure-sdk-51)). **If you never call it, the observer stops delivering updates.** JavaScript has no `registerObserverV2`.

```javascript
// ✅ GOOD: registerObserverWithSignalNext: request the next update when done.
export class OpenOrdersUploader {
  #ditto;
  #uploadOrders;
  #observer = null;

  constructor(ditto, uploadOrders) {
    this.#ditto = ditto;
    this.#uploadOrders = uploadOrders;
  }

  start() {
    this.stop(); // Cancel a previous start, if any.
    this.#observer = this.#ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
      (result, signalNext) => {
        const orders = result.items.map((item) => item.value);
        this.#handle(orders, signalNext);
      },
      { status: 'open' },
    );
  }

  async #handle(orders, signalNext) {
    try {
      await this.#uploadOrders(orders);
    } catch (error) {
      showError(error);
    } finally {
      signalNext(); // Always signal, even after an error; otherwise updates stop.
    }
  }

  stop() {
    this.#observer?.cancel();
    this.#observer = null;
  }
}
```

```javascript
// ❌ BAD: signalNext is skipped when the work throws; the observer silently
// stops updating (and the rejection is unhandled).
export function fragileObserver(ditto, uploadOrders) {
  return ditto.store.registerObserverWithSignalNext('SELECT * FROM orders ORDER BY createdAt', async (result, signalNext) => {
    await uploadOrders(result.items.map((item) => item.value));
    signalNext(); // Never reached if uploadOrders() throws.
  });
}
```

To consume results one at a time with `for await`, wrap `registerObserverWithSignalNext` in an async generator that signals only when the loop asks for the next result. Ending the loop, or aborting the signal, cancels the observer:

```javascript
// ✅ GOOD: One result at a time with for await. The loop body runs before
// Ditto may deliver the next result; break, return, a throw, or abort() cancel
// the observer.
export async function* observeOneAtATime(ditto, query, args, signal) {
  let pending = null; // { result, signalNext }
  let wake = null;
  const observer = ditto.store.registerObserverWithSignalNext(
    query,
    (result, signalNext) => {
      pending = { result, signalNext };
      wake?.();
    },
    args,
  );
  const onAbort = () => {
    observer.cancel();
    wake?.();
  };
  signal?.addEventListener('abort', onAbort, { once: true });
  try {
    while (!signal?.aborted && !observer.isCancelled) {
      if (pending === null) {
        await new Promise((resolve) => {
          wake = resolve;
        });
        wake = null;
        continue;
      }
      const { result, signalNext } = pending;
      pending = null;
      yield result; // The caller's loop body runs here.
      signalNext();
    }
  } finally {
    signal?.removeEventListener('abort', onAbort);
    observer.cancel();
  }
}

export async function aggregateReadings(ditto, deviceId, persistAggregates, signal) {
  const query =
    'SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100';
  for await (const result of observeOneAtATime(ditto, query, { deviceId }, signal)) {
    await persistAggregates(result.items.map((item) => item.value));
  }
}
```

### Diffing results in JavaScript

`new Differ().diff(result.items)` takes the items of a result and returns a `Diff` with `insertions`, `deletions`, and `updates` (arrays of indexes) and `moves` (`{ from, to }` objects). The first call reports every item as an insertion. Items are identified by `_id`, so project `_id`. Every item whose position shifts is reported as a move, not only the item that was moved (see [The JavaScript Differ reports every shifted item as a move](../../knowledge/observations/javascript-sdk.md#the-javascript-differ-reports-every-shifted-item-as-a-move)). A `Differ` has no release call; it is released with garbage collection. The semantics that every SDK shares are in [Diffing Results](../observers.md#diffing-results).

```javascript
import { Differ } from '@dittolive/ditto';

// ✅ GOOD: Logging changes between results with Differ.
export function logOrderChanges(ditto) {
  const differ = new Differ();
  let previousIds = [];
  return ditto.store.registerObserver('SELECT _id, status FROM orders ORDER BY status, _id', (result) => {
    const diff = differ.diff(result.items);
    const currentIds = result.items.map((item) => item.value._id);
    for (const index of diff.deletions) console.log(`deleted ${previousIds[index]}`); // OLD list
    for (const index of diff.insertions) console.log(`inserted ${currentIds[index]}`); // NEW list
    for (const index of diff.updates) console.log(`updated ${currentIds[index]}`); // NEW list
    for (const { from, to } of diff.moves) console.log(`moved ${from} -> ${to}`);
    previousIds = currentIds;
  });
}
```

A keyed React list needs no `Differ`: React matches rows by `key`. `Differ` is useful when the UI must react to the kind of change, for example to highlight rows that were added or changed:

```jsx
import { Differ } from '@dittolive/ditto';
import { useEffect, useState } from 'react';

// ✅ GOOD: Highlight rows that were inserted or updated by the latest result.
export function HighlightedOrders({ ditto }) {
  const [state, setState] = useState({ orders: [], changed: new Set() });

  useEffect(() => {
    const differ = new Differ(); // one per observer
    const observer = ditto.store.registerObserver(
      'SELECT _id, status FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200',
      (result) => {
        const diff = differ.diff(result.items);
        const orders = result.items.map((item) => item.value);
        const changed = new Set([...diff.insertions, ...diff.updates].map((index) => orders[index]._id));
        setState({ orders, changed });
      },
      { status: 'open' },
    );
    return () => observer.cancel();
  }, [ditto]);

  return (
    <ul>
      {state.orders.map((order) => (
        <li key={order._id} className={state.changed.has(order._id) ? 'changed' : undefined}>
          {order._id} ({order.status})
        </li>
      ))}
    </ul>
  );
}
```

### Partial UI updates in JavaScript

Give each region its own component with its own observer, and keep values in state that React can compare: when a state setter receives a value that is `Object.is` equal to the current one, React bails out (it may call the component once more, but it does not re-render its children or commit changes). A new result produces new objects even when nothing changed, so for an object or array, compare a key such as `item.jsonString()` and pass the current state back when it is the same. The rules that every SDK shares are in [Partial UI Updates](../observers.md#partial-ui-updates).

```jsx
import { useEffect, useState } from 'react';

// ✅ GOOD: The count badge and the list each observe what they need.
export function OpenOrdersCount({ ditto }) {
  const [count, setCount] = useState(0);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      (result) => {
        const n = result.items[0]?.value.n;
        setCount(typeof n === 'number' ? n : 0); // React bails out when the count is unchanged.
      },
      { status: 'open' },
    );
    return () => observer.cancel();
  }, [ditto]);

  return <span>Open orders: {count}</span>;
}

// orderList is a list component with its own observer, such as OrdersByStatus
// in "Subscriptions in JavaScript".
export function OrdersScreen({ ditto, orderList }) {
  // The screen itself observes nothing; each region re-renders independently.
  return (
    <main>
      <header>
        <OpenOrdersCount ditto={ditto} />
      </header>
      {orderList}
    </main>
  );
}
```

```jsx
import { useEffect, useState } from 'react';

// ✅ GOOD: An aggregate row as an object: set state only when its JSON changes.
export function StatusTotals({ ditto }) {
  const [totals, setTotals] = useState({ key: '', value: {} });

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT COUNT(*) AS orders, SUM(total) AS revenue FROM orders WHERE status = :status',
      (result) => {
        const item = result.items[0];
        if (!item) return;
        const key = item.jsonString();
        setTotals((current) => (current.key === key ? current : { key, value: item.value }));
      },
      { status: 'closed' },
    );
    return () => observer.cancel();
  }, [ditto]);

  return (
    <p>
      {totals.value.orders ?? 0} closed orders, revenue {totals.value.revenue ?? 0}
    </p>
  );
}
```

Use the React Developer Tools profiler to confirm which components render before optimizing further.

## Transactions in JavaScript

Run statements through `tx.execute(query, args)`, never through `ditto.store.execute`: in the JavaScript SDK, a write through `ditto.store.execute` inside a read-write transaction never completes and raises no exception, and a read through it does not see the transaction's writes (see [In JavaScript, store.execute writes inside a transaction deadlock](../../knowledge/observations/javascript-sdk.md#in-javascript-storeexecute-writes-inside-a-transaction-deadlock)). A read-write transaction started inside another one waits until the outer one ends, so awaiting it inside never ends; read-only transactions inside, and read-write transactions inside a read-only one, completed at once (see [In JavaScript, a read-write transaction started inside another one waits until the outer one ends](../../knowledge/observations/javascript-sdk.md#in-javascript-a-read-write-transaction-started-inside-another-one-waits-until-the-outer-one-ends)). The rules are in [Transaction Rules](../transactions.md#transaction-rules).

`store.transaction(scope, options)`:

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `scope` | `async (tx) => T` | required | The work to do. Use only the `Transaction` passed in, and await every `tx.execute`. |
| `options.isReadOnly` | `boolean` | `false` | Read-only transactions reject mutating statements (`store/transaction-read-only`) and can run concurrently |
| `options.hint` | `string` | none | A label written to the logs |

How a transaction ends:

| Callback outcome | Result |
|---|---|
| Returns `'commit'` | Committed; `transaction()` resolves to `'commit'` |
| Returns `'rollback'` | Rolled back; no changes are applied; `transaction()` resolves to `'rollback'` |
| Returns any other value (including nothing) | Committed; `transaction()` resolves to that value |
| Throws (or rejects) | Rolled back; `transaction()` rejects with the same error |
| A statement fails, but the callback catches the error | The transaction **continues**; the remaining changes are committed unless you roll back (see [In JavaScript, an error caught inside a transaction callback does not roll back the transaction](../../knowledge/observations/javascript-sdk.md#in-javascript-an-error-caught-inside-a-transaction-callback-does-not-roll-back-the-transaction)) |

```javascript
// ✅ GOOD: Close an order and create its invoice atomically.
export async function closeOrderWithInvoice(ditto, orderId, invoiceId) {
  await ditto.store.transaction(
    async (tx) => {
      const result = await tx.execute('SELECT * FROM orders WHERE _id = :id', { id: orderId });
      if (result.items.length === 0) {
        throw new Error(`Order ${orderId} not found`); // Throwing rolls back.
      }
      const order = result.items[0].value;

      await tx.execute('INSERT INTO invoices DOCUMENTS (:invoice)', {
        invoice: {
          _id: invoiceId,
          orderId,
          total: order.total,
          createdAt: utcTimestamp(), // Defined in the Timestamps section.
        },
      });
      await tx.execute(
        'UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id',
        { id: orderId, status: 'closed', invoiceId },
      );
    },
    { hint: 'closeOrderWithInvoice' }, // Appears in logs; useful for debugging.
  );
}
```

```javascript
// ✅ GOOD: Explicit rollback without throwing, and a typed return value.
export async function shipOrder(ditto, orderId) {
  const action = await ditto.store.transaction(
    async (tx) => {
      const result = await tx.execute('SELECT * FROM orders WHERE _id = :id AND status = :status', {
        id: orderId,
        status: 'paid',
      });
      if (result.items.length === 0) return 'rollback'; // Nothing to ship.
      await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
        id: orderId,
        status: 'shipped',
      });
      return 'commit';
    },
    { hint: 'shipOrder' },
  );
  return action === 'commit';
}

// ✅ GOOD: A read-only transaction for a consistent multi-query snapshot.
export function orderCounts(ditto) {
  return ditto.store.transaction(
    async (tx) => {
      const open = await tx.execute('SELECT COUNT(*) AS n FROM orders WHERE status = :status', {
        status: 'open',
      });
      const closed = await tx.execute('SELECT COUNT(*) AS n FROM orders WHERE status = :status', {
        status: 'closed',
      });
      return { open: open.items[0].value.n, closed: closed.items[0].value.n };
    },
    { hint: 'orderCounts', isReadOnly: true },
  );
}
```

A `tx` used after its callback has returned fails with `No active write transaction found`, and a `tx.execute` that the callback does not await is not applied (see [A tx.execute that is not awaited is not applied](../../knowledge/observations/javascript-sdk.md#a-txexecute-that-is-not-awaited-is-not-applied)). Run statements one after another, or await them together with `Promise.all`; never with `forEach(async ...)`.

```javascript
// ❌ BAD: Mixing store.execute into a transaction, nesting, and doing network I/O.
export async function badCheckout(ditto, orderId, chargeCard) {
  await ditto.store.transaction(async (tx) => {
    await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'checkout',
    });
    // Network call inside the transaction: every other write, and every change
    // from other devices, waits until the transaction ends.
    await chargeCard();
    // Never completes in JavaScript: use tx.execute instead.
    await ditto.store.execute('UPDATE orders SET status = :status WHERE _id = :id', {
      id: orderId,
      status: 'paid',
    });
    // Never completes either: the inner read-write transaction waits for the outer one.
    await ditto.store.transaction(async (inner) => {
      await inner.execute('UPDATE orders SET paidAt = :paidAt WHERE _id = :id', {
        id: orderId,
        paidAt: utcTimestamp(),
      });
    });
  });
}

// ✅ GOOD: Do the I/O first, then record the outcome in one short transaction.
export async function checkout(ditto, orderId, chargeCard) {
  await chargeCard(); // Outside the transaction.
  await ditto.store.transaction(
    async (tx) => {
      await tx.execute('UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id', {
        id: orderId,
        status: 'paid',
        paidAt: utcTimestamp(), // fixed-precision helper (see Timestamps)
      });
      await tx.execute('INSERT INTO payments DOCUMENTS (:payment)', {
        payment: { _id: `payment-${orderId}`, orderId },
      });
    },
    { hint: 'recordPayment' },
  );
}
```

`ditto.close()` waits for open transactions in the JavaScript SDK (see [Closing Ditto in JavaScript](#closing-ditto-in-javascript)), so you do not need to track them for shutdown; a transaction that never ends keeps `close()` from completing. **Node.js scripts**: a script that keeps neither sync nor a timer running, such as a seed or migration script, ended with a panic (`Panic: Error { status: PendingException ... }`) while it awaited a transaction, in our testing with SDK 5.0.3 to 5.2.0 (see [A Node.js script that keeps neither sync nor a timer running ends with a panic while awaiting a transaction](../../knowledge/observations/javascript-sdk.md#a-nodejs-script-that-keeps-neither-sync-nor-a-timer-running-ends-with-a-panic-while-awaiting-a-transaction)). Keep the event loop alive while it runs:

```javascript
// ✅ GOOD (Node.js scripts): keep the event loop alive while awaiting transactions.
export async function runMigration(ditto, migrate) {
  const keepAlive = setInterval(() => {}, 1000);
  try {
    return await ditto.store.transaction((tx) => migrate(tx), { hint: 'migration' });
  } finally {
    clearInterval(keepAlive);
  }
}
```

**Read, change, and write in one transaction**: replacing an array, or copying a document to a new `_id`, reads a value and writes a new one. Doing both in one transaction keeps two local calls from interleaving; a concurrent edit on another device can still win the merge (see [Working with arrays](../data-modeling.md#working-with-arrays) and [IDs are immutable](../data-modeling.md#ids-are-immutable)).

```javascript
// The array is a register: this write replaces it as a whole. Reading and
// writing in one transaction keeps two local calls from interleaving and
// dropping a tag; a concurrent edit on another device can still win the merge.
export async function addTag(ditto, productId, tag) {
  await ditto.store.transaction(
    async (tx) => {
      const result = await tx.execute('SELECT tags FROM products WHERE _id = :id', { id: productId });
      if (result.items.length === 0) return;
      const current = result.items[0].value.tags ?? [];
      await tx.execute('UPDATE products SET tags = :tags WHERE _id = :id', {
        id: productId,
        tags: [...current, tag],
      });
    },
    { hint: 'addTag' },
  );
}
```

```javascript
// Copies an order to a new ID and deletes the original, atomically.
// Both statements declare the order's COUNTER, ATTACHMENT, and REGISTER
// fields exactly as the other statements on orders do, so the copy keeps
// their CRDT types. Undeclared objects such as shippingAddress are MAPs.
export async function moveOrder(ditto, oldId, newId) {
  await ditto.store.transaction(
    async (tx) => {
      const result = await tx.execute(
        `SELECT * FROM COLLECTION orders
           (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
         WHERE _id = :id`,
        { id: oldId },
      );
      if (result.items.length === 0) return;
      const copy = { ...result.items[0].value, _id: newId };
      await tx.execute(
        `INSERT INTO COLLECTION orders
           (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
         DOCUMENTS (:doc)`,
        { doc: copy },
      );
      await tx.execute('DELETE FROM orders WHERE _id = :id', { id: oldId });
    },
    { hint: 'moveOrder' },
  );
}
```

## Attachments in JavaScript

Create attachments with `await ditto.store.newAttachment(pathOrBytes, metadata)`. The rules are in [Attachments](../attachments.md).

| `newAttachment` detail | Behavior |
|---|---|
| First argument | A file path (`string`; Node.js and React Native) or the bytes (`Uint8Array`) |
| File paths | The file is copied into Ditto's store. Pass an absolute path: Node.js resolves a relative path against the current working directory. Browsers accept only bytes (a path throws `DittoError` `unsupported`). |
| Metadata | An optional object whose values must be strings |
| Result | An `Attachment` with `id`, `len` (a number or `bigint`), `metadata`, `data()` (resolves to a `Uint8Array`), and `copyToPath(path)` (Node.js and React Native) |

```javascript
// ✅ GOOD: Create an attachment from a file and insert it with a declared ATTACHMENT field.
export async function savePhoto(ditto, photoId, filePath) {
  // The file is copied into Ditto's blob store; the original can be deleted afterwards.
  const attachment = await ditto.store.newAttachment(filePath, {
    name: 'receipt.jpg', // String values only.
    mimeType: 'image/jpeg',
  });

  await ditto.store.execute('INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)', {
    photo: {
      _id: photoId,
      image: attachment,
      createdAt: utcTimestamp(), // Defined in the Timestamps section.
    },
  });
}

// ✅ GOOD: Create an attachment from bytes (the only option in browsers).
export function attachmentFromBytes(ditto, bytes, name) {
  return ditto.store.newAttachment(bytes, { name });
}
```

`ditto.store.fetchAttachment(token, onEvent)` returns an `AttachmentFetcher` at once and reports `{ type: 'Progress', downloadedBytes, totalBytes }` (numbers or `bigint`s), `{ type: 'Completed', attachment }` (read the bytes with `await attachment.data()`), and `{ type: 'Deleted' }`. The token is the field's value in a query result, an object with `id`, `len`, and `metadata`.

Fetch with a token from a document that the store received by sync. In our testing with SDK 5.1.0 and 5.2.0, a token that reached the store in another way, for example passed from another store through the app, produced a `Deleted` event and rejected with `store/attachment-not-found` at once, even while the device that held the blob was connected; a value that was not a valid token rejected with `store/attachment-token-invalid` without an event, or threw. With a synced token whose holder was offline, the fetch waited without an event or an error until the holder came back (see [In JavaScript, fetchAttachment fails at once for a token that the store did not receive by sync](../../knowledge/observations/javascript-sdk.md#in-javascript-fetchattachment-fails-at-once-for-a-token-that-the-store-did-not-receive-by-sync)). Only a stall timer notices that wait, and it also ends a fetch that rejected without an event.

| `AttachmentFetcher` member | Meaning |
|---|---|
| `stop()` | Cancels an in-flight fetch. Not required after completion. |
| `await fetcher` or `await fetcher.attachment` | Resolves to the attachment when the fetch completes; rejects if it fails. Do not await it once you have stopped the fetcher. |

The component below starts the fetch when it mounts, restarts a stall timer on every progress event, stops the fetcher and offers a retry when the timer fires, and stops the fetcher when it unmounts or receives another token. In a browser it shows the bytes through an object URL; in React Native, write them to a file with `attachment.copyToPath()` and show that file's `file://` URI instead.

```jsx
import { useEffect, useState } from 'react';

// ✅ GOOD: Lazy, cancellable attachment loading with a stall timeout.
export function AttachmentImage({ ditto, token, stallTimeoutMs = 30_000 }) {
  const [state, setState] = useState({ url: null, progress: null, failed: false });
  const [attempt, setAttempt] = useState(0); // Incremented by the retry button.

  useEffect(() => {
    let current = true; // False after cleanup: ignore events of a replaced fetch.
    let url = null;
    let stallTimer = null;
    setState({ url: null, progress: null, failed: false });

    const fail = () => {
      fetcher.stop();
      if (current) setState((s) => ({ ...s, failed: true }));
    };
    // Ditto has no fetch timeout: no event simply means no peer is delivering the blob.
    const restartStallTimer = () => {
      clearTimeout(stallTimer);
      stallTimer = setTimeout(fail, stallTimeoutMs);
    };

    const fetcher = ditto.store.fetchAttachment(token, async (event) => {
      if (!current) return;
      if (event.type === 'Progress') {
        restartStallTimer(); // Progress resets the stall timer.
        const total = Number(event.totalBytes);
        if (total > 0) setState((s) => ({ ...s, progress: Number(event.downloadedBytes) / total }));
      } else if (event.type === 'Completed') {
        clearTimeout(stallTimer);
        try {
          const bytes = await event.attachment.data();
          if (!current) return; // The token can change while the bytes are read.
          url = URL.createObjectURL(new Blob([bytes], { type: token.metadata?.mimeType }));
          setState({ url, progress: 1, failed: false });
        } catch {
          if (current) setState((s) => ({ ...s, failed: true }));
        }
      } else if (event.type === 'Deleted') {
        clearTimeout(stallTimer);
        setState((s) => ({ ...s, failed: true }));
      }
    });
    restartStallTimer();

    return () => {
      current = false;
      clearTimeout(stallTimer);
      fetcher.stop(); // Cancel the download if the component goes away first.
      if (url) URL.revokeObjectURL(url);
    };
  }, [ditto, token.id, stallTimeoutMs, attempt]); // eslint-disable-line react-hooks/exhaustive-deps

  if (state.url) return <img src={state.url} alt={token.metadata?.name ?? ''} />;
  if (state.failed) {
    return (
      <button type="button" onClick={() => setAttempt((n) => n + 1)}>
        Retry
      </button>
    );
  }
  return <progress value={state.progress ?? undefined} max={1} />;
}
```

```javascript
// Reading the token from a document.
export function imageToken(photo) {
  const token = photo.image;
  return token && typeof token === 'object' && typeof token.id === 'string' ? token : null;
}
```

To replace or remove an attachment (see [Attachments Are Immutable](../attachments.md#attachments-are-immutable)):

```javascript
// ✅ GOOD: Replace an attachment by creating a new one and updating the token field.
export async function replacePhoto(ditto, photoId, newFilePath) {
  const attachment = await ditto.store.newAttachment(newFilePath, {
    name: 'receipt-v2.jpg',
    mimeType: 'image/jpeg',
  });
  await ditto.store.execute(
    'UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id',
    { id: photoId, image: attachment },
  );
}

// ✅ GOOD: Remove the reference; the blob becomes eligible for garbage collection.
export async function removePhoto(ditto, photoId) {
  await ditto.store.execute('UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id', {
    id: photoId,
  });
}
```

Thumbnails and full-size images (see [Thumbnail Pattern](../attachments.md#thumbnail-pattern)):

```javascript
// ✅ GOOD: Insert a thumbnail attachment and a full-size attachment together.
export async function savePhotoWithThumbnail(ditto, { photoId, thumbnailBytes, fullSizePath }) {
  // thumbnailBytes is a Uint8Array, downscaled by your app beforehand.
  const thumbnail = await ditto.store.newAttachment(thumbnailBytes, {
    kind: 'thumbnail',
    mimeType: 'image/jpeg',
  });
  const fullSize = await ditto.store.newAttachment(fullSizePath, { kind: 'full', mimeType: 'image/jpeg' });

  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)',
    {
      photo: {
        _id: photoId,
        thumbnail,
        image: fullSize,
        createdAt: utcTimestamp(), // Defined in the Timestamps section.
      },
    },
  );
}
```

```jsx
import { useState } from 'react';

// ✅ GOOD: Rows fetch only thumbnails; the full-size image is fetched when opened.
// AttachmentImage is the component above.
export function PhotoRow({ ditto, photo }) {
  const [open, setOpen] = useState(false);
  const thumbnail = photo.thumbnail?.id ? photo.thumbnail : null;
  const fullSize = photo.image?.id ? photo.image : null;
  return (
    <li>
      {thumbnail ? <AttachmentImage ditto={ditto} token={thumbnail} stallTimeoutMs={30_000} /> : <span>No image</span>}
      <button type="button" disabled={!fullSize} onClick={() => setOpen(true)}>
        {photo._id}
      </button>
      {open && fullSize && (
        <dialog open>
          {/* Larger files need a longer stall timeout. */}
          <AttachmentImage ditto={ditto} token={fullSize} stallTimeoutMs={120_000} />
          <button type="button" onClick={() => setOpen(false)}>
            Close
          </button>
        </dialog>
      )}
    </li>
  );
}
```

## IDs and Timestamps in JavaScript

**IDs**: generate a random (version 4) UUID for every new document with `crypto.randomUUID()`, which Node.js and browsers provide (React Native needs a polyfill or a package); never derive IDs from a counter or the clock. Keep human-readable numbers in a separate field. The rules are in [Document IDs](../data-modeling.md#document-ids).

```javascript
export async function createOrder(ditto, storeId) {
  const orderId = crypto.randomUUID();
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: {
      _id: orderId,
      storeId,
      status: 'open',
      createdAt: utcTimestamp(), // defined below
    },
  });
  return orderId;
}
```

```javascript
// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
export const badSequentialId = (dailyCount) => `order-${dailyCount}`;

// ❌ BAD: Collides when two devices write within the same millisecond.
export const badTimestampId = () => `order-${Date.now()}`;
```

```javascript
// A display label, not an identifier: uniqueness is not guaranteed across
// devices, so never use it as _id or as a lookup key.
export const displayNumber = (terminalCode, localSequence) =>
  `${terminalCode}-${String(localSequence).padStart(4, '0')}`;

export async function createOrderWithLabel(ditto, { orderId, terminalCode, localSequence }) {
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: {
      _id: orderId, // UUID
      displayNumber: displayNumber(terminalCode, localSequence),
      createdAt: utcTimestamp(),
    },
  });
}
```

**Timestamps**: store UTC with a zone designator, and produce every timestamp that is sorted or compared with one fixed-precision helper (see [Timestamps](../data-modeling.md#timestamps)). In JavaScript, `Date.prototype.toISOString()` already returns UTC with a `Z` and exactly three fractional digits (`2026-10-08T10:30:00.123Z`), so the helper only wraps it. Two mistakes are common: passing a `Date` object as an argument, which is stored as an empty object `{}`, and formatting with `toString()`, `toLocaleString()`, or `toUTCString()`, which produce strings that DQL date functions cannot read. In our testing with SDK 5.1.0 and 5.2.0, `date_part` and `date_cast` returned MISSING, without an error, for the strings of `toString()`, `toLocaleString()`, `toUTCString()`, and `toDateString()`, also when they named a zone, and read the `toISOString()` form and epoch milliseconds (see [Date functions read only the ISO 8601 and epoch-millisecond forms of a JavaScript date](../../knowledge/observations/dql-behavior.md#date-functions-read-only-the-iso-8601-and-epoch-millisecond-forms-of-a-javascript-date)). Epoch milliseconds (`Date.now()`) are the compact alternative.

```javascript
// Returns the time as an ISO-8601 UTC string with exactly millisecond
// precision, e.g. "2026-10-08T10:30:00.123Z".
export function utcTimestamp(time = new Date()) {
  return time.toISOString();
}

// ✅ GOOD: Consistent UTC timestamps from the one helper.
export async function markReady(ditto, orderId) {
  await ditto.store.execute('UPDATE orders SET readyAt = :readyAt WHERE _id = :id', {
    id: orderId,
    readyAt: utcTimestamp(),
  });
}
```

```javascript
// ❌ BAD: A Date object is stored as {}, and toLocaleString() is local time
// without a zone that DQL date functions return MISSING for.
export async function markReadyBadly(ditto, orderId) {
  await ditto.store.execute('UPDATE orders SET readyAt = :readyAt, readyLabel = :label WHERE _id = :id', {
    id: orderId,
    readyAt: new Date(),
    label: new Date().toLocaleString(),
  });
}
```

## Transports and Presence in JavaScript

`ditto.transportConfig` is frozen. Change it with `ditto.updateTransportConfig((config) => { ... })`, which passes a copy of the current configuration; never assign a `new TransportConfig()`, which has every transport disabled, whereas a newly opened instance on Node.js on macOS has Bluetooth LE, LAN, and AWDL enabled (in our testing with SDK 5.1.0 and 5.2.0; see [A new instance enables the platform's peer-to-peer transports, and an empty configuration enables none](../../knowledge/observations/connections-and-presence.md#a-new-instance-enables-the-platforms-peer-to-peer-transports-and-an-empty-configuration-enables-none)). In JavaScript the names are `connect.tcpServers` and `connect.websocketURLs`, both arrays. The rules are in [Transport Configuration](../setup-and-lifecycle.md#transport-configuration).

Enable the peer-to-peer transports with `setAvailablePeerToPeerEnabled(true)`, which enables only those that the platform supports. `setAllPeerToPeerEnabled(true)` also enables Wi-Fi Aware: in our testing with SDK 5.1.0 and 5.2.0 on Node.js on macOS, `updateTransportConfig()` then threw `Expected valid TransportConfig. Invalid config: The following P2P transports are enabled in the transport config but are not supported in the current environment: WiFi Aware` (see [In JavaScript on macOS, enabling every peer-to-peer transport makes the transport configuration invalid](../../knowledge/observations/javascript-sdk.md#in-javascript-on-macos-enabling-every-peer-to-peer-transport-makes-the-transport-configuration-invalid)).

```javascript
// ✅ GOOD: Adjust the current configuration.
export function configureTransports(ditto) {
  ditto.updateTransportConfig((config) => {
    config.setAvailablePeerToPeerEnabled(true); // only what this platform supports
    config.peerToPeer.bluetoothLE.isEnabled = false; // for example, LAN and P2P Wi-Fi only
  });
}
```

```javascript
// ✅ GOOD: A hub device listens on TCP; other devices connect to it.
export function configureHub(ditto) {
  ditto.updateTransportConfig((config) => {
    config.listen.tcp.isEnabled = true;
    config.listen.tcp.interfaceIP = '[::]';
    config.listen.tcp.port = 4040;
  });
}

export function connectToHub(ditto) {
  ditto.updateTransportConfig((config) => {
    config.connect.tcpServers = ['192.168.1.10:4040'];
    // Additional WebSocket endpoints, if you run your own:
    // config.connect.websocketURLs = ['wss://sync.example.com'];
  });
}
```

```javascript
import { DittoConfig } from '@dittolive/ditto';

// ✅ GOOD: A hub that serves up to 12 TCP clients. The limit is part of the
// hub's configuration, so it is applied on every open, before sync starts
// (SDK 5.2+).
export function hubConfig(connect) {
  return new DittoConfig({
    databaseID: 'YOUR_DATABASE_ID',
    connect,
    systemParameters: { MESH_CHOOSER_MAX_WLAN_CONNECTIONS: 12 },
  });
}

// Call with an instance opened from hubConfig(), after the authentication
// handler or the offline license token is set.
export function startHub(ditto) {
  ditto.updateTransportConfig((config) => {
    config.listen.tcp.isEnabled = true;
    config.listen.tcp.interfaceIP = '[::]';
    config.listen.tcp.port = 4040;
  });
  ditto.sync.start();
}
```

**Transport conditions (SDK 5.1+)**: `ditto.observeTransportConditions((condition, source) => { ... })` reports why a transport is not working, with `condition` values such as `'NoBLECentralPermission'` or `'TCPListenFailure'` and `source` values such as `'BLE'` or `'TCP'`; call `stop()` on the returned observer when you no longer need it. On Node.js, an active transport-conditions observer keeps the process running. The JavaScript SDK has no permissions helper: React Native apps request the platform permissions themselves, for example with React Native's `PermissionsAndroid` (see [Diagnosing transport problems (SDK 5.1+)](../setup-and-lifecycle.md#diagnosing-transport-problems-sdk-51)).

```javascript
// ✅ GOOD: Surface transport problems. Stop the returned observer when done.
export function watchTransports(ditto) {
  return ditto.observeTransportConditions((condition, source) => {
    if (condition !== 'OK') console.warn(`Transport ${source}: ${condition}`);
  });
}
```

**Presence**: `ditto.presence.observe((graph) => { ... })` returns an observer whose first call comes at once; call `stop()` on it when you no longer need it. `graph.localPeer` and `graph.remotePeers` (an array) hold `Peer` objects with `peerKey`, `deviceName`, `isConnectedToDittoServer`, `connections` (with `peer1`, `peer2`, and `connectionType`, which is `'AccessPoint'` for TCP), `os`, `dittoSdkVersion`, and `peerMetadata`. Set this device's metadata with `await ditto.presence.setPeerMetadata({ role: 'cashier' })` (at most 4 KB as JSON) and its name with `ditto.deviceName`, which is truncated to 24 bytes when sync starts (see [Presence](../setup-and-lifecycle.md#presence)).

```jsx
import { useEffect, useState } from 'react';

// A peer's connections include its links to other peers, so only the
// connections that have this device at one end make it a direct neighbor.
function routeOf(peer, localPeerKey) {
  const directTypes = new Set(
    peer.connections
      .filter((connection) => connection.peer1 === localPeerKey || connection.peer2 === localPeerKey)
      .map((connection) => connection.connectionType),
  );
  const route = directTypes.size === 0 ? 'Through other peers' : `Direct (${[...directTypes].join(', ')})`;
  return peer.isConnectedToDittoServer ? `${route}, connected to Ditto Server` : route;
}

// ✅ GOOD: Show connected peers and stop the observer when done.
export function PeerList({ ditto }) {
  const [graph, setGraph] = useState({ localPeerKey: '', peers: [] });

  useEffect(() => {
    const observer = ditto.presence.observe((presenceGraph) => {
      setGraph({ localPeerKey: presenceGraph.localPeer.peerKey, peers: presenceGraph.remotePeers });
    });
    return () => observer.stop();
  }, [ditto]);

  return (
    <ul>
      {graph.peers.map((peer) => (
        <li key={peer.peerKey}>
          {peer.deviceName}: {routeOf(peer, graph.localPeerKey)}
        </li>
      ))}
    </ul>
  );
}
```

**Incoming connections**: `ditto.presence.connectionRequestHandler` receives each connection request and resolves to `'allow'` or `'deny'`; a handler that throws, or takes longer than 10 seconds, denies. Set it to `null` to remove it (see [Controlling Incoming Connections](../security.md#controlling-incoming-connections)).

```javascript
// ✅ GOOD: Accept only peers whose signed metadata belongs to this store.
// Requires a server connection: identityServiceMetadata comes from your
// authentication webhook and is empty ({}) in small-peers-only mode.
export function restrictConnectionsToStore(ditto, storeId) {
  ditto.presence.connectionRequestHandler = async (request) => {
    try {
      return request.identityServiceMetadata.storeId === storeId ? 'allow' : 'deny';
    } catch {
      return 'deny'; // decide now, not after the timeout
    }
  };
}
```

## Logging in JavaScript

`Logger` has static members only, and they work before any instance is opened. The levels are `'Error'`, `'Warning'`, `'Info'`, `'Debug'`, and `'Verbose'`. The rules are in [Logging](../logging-and-observability.md#logging).

```javascript
import { Logger } from '@dittolive/ditto';

// Call before Ditto.open().
export function configureDittoLogging({ production }) {
  Logger.enabled = true;
  Logger.minimumLogLevel = production ? 'Warning' : 'Debug';
}
```

`await Logger.setCustomLogCallback((level, message) => { ... })` forwards the log lines that Ditto emits. It throws in React Native. It applies to the whole process, and `ditto.close()` does not remove it: in our testing with SDK 5.2.0, the callback kept receiving log lines after `close()`, also from an instance opened afterwards (see [In JavaScript, the custom log callback stays installed after close()](../../knowledge/observations/javascript-sdk.md#in-javascript-the-custom-log-callback-stays-installed-after-close)). Install it once at startup, and remove it with `await Logger.setCustomLogCallback(undefined)`.

```javascript
import { Ditto, Logger } from '@dittolive/ditto';

// Forwards Ditto warnings and errors to the app's logging pipeline.
// Install once per process; close() does not remove it.
export async function installDittoLogForwarding(report) {
  await Logger.setCustomLogCallback((level, message) => {
    if (level === 'Error' || level === 'Warning') {
      report(`[ditto ${level}] ${message}`);
    }
  });
}

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
```

`await Logger.exportToFile(path)` writes the on-disk logs of the most recently opened instance as gzip-compressed JSON lines and resolves to the number of bytes. The file must not exist yet (`DittoError` `io/already-exists`), and its directory must exist. It is not available in browsers (see [On-disk logs and exporting them](../logging-and-observability.md#on-disk-logs-and-exporting-them)):

```javascript
import { Logger } from '@dittolive/ditto';
import path from 'node:path';

// Exports Ditto's on-disk logs, for example for a "Send diagnostics" command.
// directory must exist, for example os.tmpdir() or a support directory.
export async function exportDittoLogs(directory) {
  const file = path.join(directory, `ditto-logs-${Date.now()}.jsonl.gz`);
  const bytes = await Logger.exportToFile(file);
  console.log(`Exported ${bytes} bytes of Ditto logs to ${file}`);
  return file;
}
```

A support bundle (SDK 5.2+) is created with DQL and fetched like any other attachment; saving it with `copyToPath()` needs Node.js or React Native (see [Support bundles (SDK 5.2+)](../logging-and-observability.md#support-bundles-sdk-52)):

```javascript
// ✅ GOOD: Create a support bundle and save it, for example to share it with
// Ditto support. An existing file at filePath is replaced.
export async function saveSupportBundle(ditto, filePath) {
  const result = await ditto.store.execute('EXECUTE FUNCTION system_request_support_bundle()');
  const token = result.items[0].value.file;
  const attachment = await ditto.store.fetchAttachment(token);
  await attachment.copyToPath(filePath);
}
```

**Storage snapshot**: read `system:system_info` with `execute` when you need it, ordered by `timestamp`, and let later rows of a key overwrite earlier ones (see [Monitoring Storage](../deletion-and-storage.md#monitoring-storage)).

```javascript
// ✅ GOOD: Read the latest storage snapshot on demand (for example from a
// diagnostics screen or a daily maintenance task).
export async function storageSnapshot(ditto) {
  const result = await ditto.store.execute(
    "SELECT key, value, timestamp FROM system:system_info " +
      "WHERE key LIKE 'fs_%' OR key LIKE 'collection_num_docs%' ORDER BY timestamp ASC",
  );
  const snapshot = {};
  for (const item of result.items) {
    // Later rows overwrite earlier ones, so the newest value wins.
    snapshot[item.value.key] = item.value.value;
  }
  return snapshot;
}
```

## Testing in JavaScript

The tests below use Node.js's built-in test runner (`node --test`) and the helper from [A local-store test helper in JavaScript](#a-local-store-test-helper-in-javascript). The test runner keeps the event loop running, so the panic of a script that awaits a transaction does not occur in a test (see [A Node.js script that keeps neither sync nor a timer running ends with a panic while awaiting a transaction](../../knowledge/observations/javascript-sdk.md#a-nodejs-script-that-keeps-neither-sync-nor-a-timer-running-ends-with-a-panic-while-awaiting-a-transaction)). What each test checks is described in [Testing Strategies](../testing.md).

```javascript
// test/merge.test.mjs
import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { openTestDitto } from './helper.mjs';

let ditto;
beforeEach(async (t) => {
  ditto = await openTestDitto(t);
});

test('adding a line item keeps the existing items (map keyed by ID)', async () => {
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: { _id: 'order-1', items: { 'item-1': { productId: 'p1', quantity: 2 } } },
  });

  // The code under test: an upsert of a partial document (see "Arrays and Maps").
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF', {
    patch: { _id: 'order-1', items: { 'item-2': { productId: 'p2', quantity: 1 } } },
  });

  const result = await ditto.store.execute('SELECT * FROM orders WHERE _id = :id', { id: 'order-1' });
  const items = result.items[0].value.items;
  assert.ok(!Array.isArray(items)); // not an array
  assert.deepEqual(Object.keys(items).sort(), ['item-1', 'item-2']);
});

test('re-upserting unchanged data is a no-op', async () => {
  const product = { _id: 'p1', name: 'Pen', priceCents: 250 };
  await ditto.store.execute('INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF', { product });

  const again = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    { product },
  );
  assert.equal(again.mutatedDocumentIDsV2().length, 0);
});

// The code under test: the app's replaceAddress() (see "Assigning an object merges it").
async function replaceAddress(ditto, customerId, address) {
  await ditto.store.transaction(
    async (tx) => {
      await tx.execute('UPDATE customers UNSET address WHERE _id = :id', { id: customerId });
      await tx.execute('UPDATE customers SET address = :address WHERE _id = :id', { id: customerId, address });
    },
    { hint: 'replaceAddress' },
  );
}

test('replaceAddress removes keys that are not in the new address', async () => {
  await ditto.store.execute('INSERT INTO customers DOCUMENTS (:customer)', {
    customer: { _id: 'c1', address: { city: 'Oslo', zip: '0150' } },
  });

  await replaceAddress(ditto, 'c1', { city: 'Bergen' });

  const result = await ditto.store.execute('SELECT * FROM customers WHERE _id = :id', { id: 'c1' });
  // A plain SET would keep "zip": objects merge under the default settings.
  assert.deepEqual(result.items[0].value.address, { city: 'Bergen' });
});
```

```javascript
// test/deletion.test.mjs
import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { openTestDitto } from './helper.mjs';

let ditto;
beforeEach(async (t) => {
  ditto = await openTestDitto(t);
});

test('active-orders query treats a missing or null flag as not deleted', async () => {
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:a), (:b), (:c), (:d)', {
    a: { _id: 'deleted', isDeleted: true },
    b: { _id: 'active', isDeleted: false },
    c: { _id: 'nullFlag', isDeleted: null },
    d: { _id: 'noFlag' },
  });

  // The query used by the app's repository.
  const result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id',
  );
  assert.deepEqual(
    result.items.map((item) => item.value._id),
    ['active', 'noFlag', 'nullFlag'],
  );
});

test('deleting by ID removes exactly the listed documents', async () => {
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:a), (:b), (:c)', {
    a: { _id: 'o1' },
    b: { _id: 'o2' },
    c: { _id: 'o3' },
  });

  // The statement used by the app; WHERE _id IN :ids, not USE IDS.
  const deleted = await ditto.store.execute('DELETE FROM orders WHERE _id IN :ids', { ids: ['o1', 'o2'] });
  assert.equal(deleted.mutatedDocumentIDsV2().length, 2);

  const remaining = await ditto.store.execute('SELECT _id FROM orders');
  assert.deepEqual(remaining.items.map((item) => item.value._id), ['o3']);
});
```

```javascript
// test/observer.test.mjs
import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { openTestDitto } from './helper.mjs';

let ditto;
beforeEach(async (t) => {
  ditto = await openTestDitto(t);
});

test('observer sees a new order and is cancelled cleanly', async () => {
  let resolveSawOrder;
  const sawOrder = new Promise((resolve) => {
    resolveSawOrder = resolve;
  });
  const observer = ditto.store.registerObserver(
    'SELECT * FROM orders WHERE status = :status ORDER BY _id',
    (result) => {
      if (result.items.length === 1) resolveSawOrder();
    },
    { status: 'open' },
  );

  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: { _id: 'order-1', status: 'open' },
  });
  await Promise.race([
    sawOrder,
    new Promise((_, reject) => setTimeout(() => reject(new Error('no callback within 5 s')), 5000)),
  ]);

  // The same cleanup that the component's effect performs.
  observer.cancel();
  assert.equal(observer.isCancelled, true);
  assert.equal(ditto.store.observers.length, 0);
});
```

For component tests of screens that own observers, keep the observer behind your own interface and pass a fake. `Differ` only accepts items produced by Ditto, so code that uses it needs a real store.

`registerSubscription` throws a `DittoError` for a query that subscriptions do not accept:

```javascript
// test/subscriptions.test.mjs
import { DittoError } from '@dittolive/ditto';
import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { openTestDitto } from './helper.mjs';

let ditto;
beforeEach(async (t) => {
  ditto = await openTestDitto(t);
});

test('subscriptions with projections or ORDER BY/LIMIT are rejected', () => {
  const unsupported = (error) => error instanceof DittoError && error.code === 'query/unsupported';
  assert.throws(() => ditto.sync.registerSubscription('SELECT _id, status FROM orders'), unsupported);
  assert.throws(
    () => ditto.sync.registerSubscription('SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50'),
    unsupported,
  );
});

test("the app's subscriptions are valid", () => {
  const subscriptions = [
    ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId: 'store-1' }),
    ditto.sync.registerSubscription('SELECT * FROM products'),
  ];
  for (const subscription of subscriptions) {
    subscription.cancel();
    assert.equal(subscription.isCancelled, true);
  }
});
```

```javascript
// test/statements.test.mjs
import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { openTestDitto } from './helper.mjs';

let ditto;
beforeEach(async (t) => {
  ditto = await openTestDitto(t);
});

// The app's statements with representative arguments. In a real app, keep
// the statement strings in your repository module and import them here.
const appStatements = [
  ['SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC', { status: 'open' }],
  ['UPDATE orders SET status = :status WHERE _id = :id', { status: 'closed', id: 'order-1' }],
  ['DELETE FROM orders WHERE _id IN :ids', { ids: ['order-1'] }],
];

// Writes bigint values as strings, so that JSON.stringify accepts the plan.
const toJson = (value) => JSON.stringify(value, (key, v) => (typeof v === 'bigint' ? v.toString() : v));

test('every app statement can be planned', async () => {
  for (const [statement, args] of appStatements) {
    // EXPLAIN rejects if a statement cannot be parsed or planned.
    await ditto.store.execute(`EXPLAIN ${statement}`, args);
  }
});

test('the open-orders query uses its index', async () => {
  // In your suite, create indexes with the same startup code as the app
  // (for example, through the configure option of openTestDitto).
  await ditto.store.execute(
    'CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)',
  );
  const plan = await ditto.store.execute(
    'EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
    { status: 'open' },
  );
  assert.match(toJson(plan.items[0].value), /indexScan/);
});
```

### A local-store test helper in JavaScript

The module below opens a small-peers-only instance in its own temporary directory and closes it automatically when the test ends (see [A Test Helper for a Local Store](../testing.md#a-test-helper-for-a-local-store)). Pass the same `systemParameters` that your app passes in its `DittoConfig`, and a `configure` function for the indexes that your app creates at startup. Run the suite with `node --test`, which runs the files whose names end in `.test.mjs`.

```javascript
// test/helper.mjs
import { Ditto, DittoConfig } from '@dittolive/ditto';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

// Opens a Ditto instance for one test. Sync is never started, so no
// license token or network connection is needed. `t` is the test context
// (beforeEach and test pass it); the store is closed after that test.
export async function openTestDitto(t, { systemParameters = {}, configure } = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ditto-test-'));
  const ditto = await Ditto.open(
    new DittoConfig({
      // Any UUID works for local tests; each test gets its own directory.
      databaseID: '00000000-0000-4000-8000-000000000001',
      connect: { mode: 'smallPeersOnly' },
      persistenceDirectory: directory,
      // The same parameters as the app's DittoConfig (SDK 5.2+).
      systemParameters,
    }),
  );

  // Runs after the test, even when it fails.
  t.after(async () => {
    await ditto.close();
    await rm(directory, { recursive: true, force: true });
  });

  // Create the app's indexes, as at app startup.
  await configure?.(ditto);
  return ditto;
}
```

```javascript
// test/helper.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { openTestDitto } from './helper.mjs';

test('a new store is empty', async (t) => {
  const ditto = await openTestDitto(t);
  const result = await ditto.store.execute('SELECT COUNT(*) AS n FROM orders');
  assert.equal(result.items[0].value.n, 0);
});
```

**Running the tests:** the tests open real stores, so they run on Node.js, where the SDK's native library is available; `node --test` needs no other setup. Code that runs in a browser or in React Native can be tested the same way on Node.js, apart from what differs there: the browser store is in memory and has no indexes (see [Installing the JavaScript SDK](#installing-the-javascript-sdk)).

### Several peers in one test in JavaScript

The helpers below open several small peers in one `node --test` process and connect them over TCP on `127.0.0.1` only (see [Several peers in one test process](../testing.md#several-peers-in-one-test-process)). Run them with `DITTO_LICENSE_TOKEN=... node --test test/multipeer.test.mjs`; the test is skipped without the variable. Keep the token out of the repository.

```javascript
// test/multipeer.test.mjs
import { Ditto, DittoConfig } from '@dittolive/ditto';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

// Offline license token, passed as an environment variable (never commit it).
const licenseToken = process.env.DITTO_LICENSE_TOKEN ?? '';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Opens `count` peers in this process that sync with each other over TCP on
// localhost only: peer 0 listens, the others connect to it. A device accepts
// at most 6 TCP connections by default, so keep `count` at 7 or below.
async function openSyncedPeers(t, count, { port = 4041, databaseID = '00000000-0000-4000-8000-000000000002', configure } = {}) {
  const peers = [];
  for (let i = 0; i < count; i += 1) {
    const directory = await mkdtemp(path.join(os.tmpdir(), `ditto-peer${i}-`));
    // All peers of a group use the same database ID; give every group that
    // can run at the same time its own ID and port.
    const ditto = await Ditto.open(
      new DittoConfig({ databaseID, connect: { mode: 'smallPeersOnly' }, persistenceDirectory: directory }),
    );
    t.after(async () => {
      await ditto.close();
      await rm(directory, { recursive: true, force: true });
    });
    ditto.setOfflineOnlyLicenseToken(licenseToken);
    ditto.updateTransportConfig((config) => {
      config.setAllPeerToPeerEnabled(false); // no Bluetooth, LAN, or AWDL
      // A device that only connects still listens on every interface, so bind
      // every listener to this machine: test peers stay off the network.
      config.listen.tcp.isEnabled = true;
      config.listen.tcp.interfaceIP = '127.0.0.1';
      config.listen.tcp.port = i === 0 ? port : 0;
      if (i > 0) config.connect.tcpServers = [`127.0.0.1:${port}`];
    });
    // App setup after open, such as indexes. On SDK 5.2+, pass system
    // parameters in the DittoConfig above instead.
    await configure?.(ditto);
    ditto.sync.start();
    peers.push(ditto);
  }
  await waitUntil(() => peers.every(isConnected));
  return peers;
}

const isConnected = (ditto) => ditto.presence.graph.remotePeers.length > 0;

async function waitUntil(condition, { timeoutMs = 15_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (!(await condition())) {
    if (Date.now() > deadline) throw new Error('Condition not met');
    await sleep(100);
  }
}

// Stops sync on every peer, runs `writes` while the peers are disconnected,
// then reconnects them, so the writes are concurrent.
async function whileDisconnected(peers, writes) {
  for (const peer of peers) peer.sync.stop();
  await waitUntil(() => peers.every((peer) => !isConnected(peer)));
  await writes();
  for (const peer of peers) peer.sync.start();
  await waitUntil(() => peers.every(isConnected));
}

// Waits until `query` returns the same rows on every peer and `until` holds
// for them, then returns the rows.
async function waitForConvergence(peers, query, { args = {}, until = () => true, timeoutMs = 15_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (true) {
    const results = [];
    for (const peer of peers) {
      const result = await peer.store.execute(query, args);
      results.push(result.items.map((item) => item.jsonString()));
    }
    const first = JSON.stringify(results[0]);
    if (results.every((rows) => JSON.stringify(rows) === first)) {
      const rows = results[0].map((json) => JSON.parse(json));
      if (until(rows)) return rows;
    }
    if (Date.now() > deadline) throw new Error(`Peers did not converge: ${JSON.stringify(results)}`);
    await sleep(100);
  }
}

test('concurrent edits of different line items both survive', { skip: licenseToken === '' && 'Needs DITTO_LICENSE_TOKEN' }, async (t) => {
  const [tablet, phone] = await openSyncedPeers(t, 2);
  for (const peer of [tablet, phone]) peer.sync.registerSubscription('SELECT * FROM orders');
  await tablet.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: { _id: 'order-1', items: { 'item-1': { productId: 'p1', quantity: 1 } } },
  });
  await waitForConvergence([tablet, phone], 'SELECT * FROM orders', { until: (rows) => rows.length === 1 });

  // The code under test would be the app's repository functions.
  await whileDisconnected([tablet, phone], async () => {
    await tablet.store.execute('UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id', { id: 'order-1' });
    await phone.store.execute('UPDATE orders SET items.`item-2` = :item WHERE _id = :id', {
      id: 'order-1',
      item: { productId: 'p2', quantity: 1 },
    });
  });

  const rows = await waitForConvergence([tablet, phone], 'SELECT * FROM orders WHERE _id = :id', {
    args: { id: 'order-1' },
    until: (rows) => Object.keys(rows[0]?.items ?? {}).length === 2,
  });
  const items = rows[0].items;
  assert.equal(items['item-1'].quantity, 3);
  assert.equal(items['item-2'].productId, 'p2');
});
```

## Behavior Specific to the JavaScript SDK

The behavior below differs from the other SDKs or is easy to miss. Each item links to its observation; the observations that are specific to the JavaScript SDK are collected on [JavaScript SDK Behavior](../../knowledge/observations/javascript-sdk.md).

**Opening and closing**:
- **Note (SDK 5.1.0 and 5.2.0):** `Ditto.open()` on a directory that the same process already has open rejects after about 1 second with `DittoError` `store/persistence-directory-locked` (`File already locked, ... Multiple Ditto instances cannot run at the same time within the same working directory.`). Share the existing instance instead (see [In JavaScript, opening an open directory again fails](../../knowledge/observations/javascript-sdk.md#in-javascript-opening-an-open-directory-again-fails)).
- `close()` waits for running `execute()` calls, transactions, and expiration handlers before it completes, so one that never ends keeps it from completing (see [In JavaScript, close() waits for open transactions](../../knowledge/observations/javascript-sdk.md#in-javascript-close-waits-for-open-transactions) and [In JavaScript, close() waits for a running expiration handler](../../knowledge/observations/javascript-sdk.md#in-javascript-close-waits-for-a-running-expiration-handler)).
- **Note (SDK 5.1.0 and 5.2.0):** calls after `close()` fail with a plain `Error` that has no `code`, either at once or as a rejected promise (see [In JavaScript, calls after close() throw or reject with a plain Error](../../knowledge/observations/javascript-sdk.md#in-javascript-calls-after-close-throw-or-reject-with-a-plain-error)).
- The named `new DittoConfig({ ... })` form, and with it `systemParameters`, needs SDK 5.2; on 5.1.0 it throws a `TypeError` (see [In JavaScript, the named DittoConfig form throws on SDK 5.1.0](../../knowledge/observations/javascript-sdk.md#in-javascript-the-named-dittoconfig-form-throws-on-sdk-510)).

**Authentication**:
- The SDK catches what the expiration handler throws and logs it at the Error level; nothing reaches the app (see [In JavaScript, an error thrown by the expiration handler is only logged](../../knowledge/observations/javascript-sdk.md#in-javascript-an-error-thrown-by-the-expiration-handler-is-only-logged)).
- `auth.logout(cleanup)` calls the cleanup without awaiting it (see [In JavaScript, logout() does not wait for its cleanup function](../../knowledge/observations/javascript-sdk.md#in-javascript-logout-does-not-wait-for-its-cleanup-function)).

**Observers and results**:
- **Note (SDK 5.0.3 to 5.2.0):** `registerObserver` does not await an `async` handler; calls overlap, and an older result can finish last (see [In JavaScript, registerObserver does not await async callbacks](../../knowledge/observations/javascript-sdk.md#in-javascript-registerobserver-does-not-await-async-callbacks)).
- **Note (SDK 5.1.0 and 5.2.0):** a synchronous throw in a handler is discarded; an `async` handler that rejects causes an unhandled rejection, which ends a Node.js process by default (see [In JavaScript, exceptions thrown synchronously in observer callbacks are discarded](../../knowledge/observations/javascript-sdk.md#in-javascript-exceptions-thrown-synchronously-in-observer-callbacks-are-discarded) and [In JavaScript, an async observer callback that rejects causes an unhandled rejection](../../knowledge/observations/javascript-sdk.md#in-javascript-an-async-observer-callback-that-rejects-causes-an-unhandled-rejection)).
- `item.value` returns the same object every time, and changes to it never reach the store (see [In JavaScript, query results return the same objects](../../knowledge/observations/javascript-sdk.md#in-javascript-query-results-return-the-same-objects)).
- Garbage collection stops neither store observers nor subscriptions; `ditto.store.observers` and `ditto.sync.subscriptions` list other objects than the registrations returned, but they can cancel (see [In JavaScript, garbage-collected subscriptions and observers keep running](../../knowledge/observations/javascript-sdk.md#in-javascript-garbage-collected-subscriptions-and-observers-keep-running) and [In JavaScript, store.observers exists since 5.0 and lists other objects](../../knowledge/observations/javascript-sdk.md#in-javascript-storeobservers-exists-since-50-and-lists-other-objects)).
- `result.mutatedDocumentIDsV2()` replaces `mutatedDocumentIDs()`, which does not exist in JavaScript, and `commitID` is a `bigint`.
- **Note (SDK 5.0.3 to 5.2.0):** `isStopped` of the observers that `presence.observe()`, `auth.observeStatus()`, and `observeTransportConditions()` return is `true` while the observer is active and `false` after `stop()`; keep your own flag instead (see [In JavaScript, Observer.isStopped is true while the observer is active](../../knowledge/observations/javascript-sdk.md#in-javascript-observerisstopped-is-true-while-the-observer-is-active)).

**DQL and values**:
- `execute()` rejects, and registrations throw at once, with a `DittoError` for an invalid statement or argument (see [In JavaScript, invalid statements and arguments fail with a DittoError when the call is made](../../knowledge/observations/javascript-sdk.md#in-javascript-invalid-statements-and-arguments-fail-with-a-dittoerror-when-the-call-is-made)).
- `Date`, `Set`, function, and `Symbol` values become `{}`; `undefined` becomes `null`; `NaN` and `Infinity` are rejected; integers of 2^53 or more come back as `bigint`; unpaired surrogates are changed (see [Arguments and value types in JavaScript](#arguments-and-value-types-in-javascript)).

**Sync status**:
- **Note (SDK 5.1.0 and 5.2.0):** a read of `system:data_sync_info`, or an observer of it, can stop responding on a connected device, and then `close()` does not complete (see [In JavaScript, a read of system:data_sync_info can stop responding](../../knowledge/observations/javascript-sdk.md#in-javascript-a-read-of-systemdata_sync_info-can-stop-responding)).

**Transports**:
- `setAllPeerToPeerEnabled(true)` makes the configuration invalid on Node.js on macOS, because it enables Wi-Fi Aware; use `setAvailablePeerToPeerEnabled(true)` (see [In JavaScript on macOS, enabling every peer-to-peer transport makes the transport configuration invalid](../../knowledge/observations/javascript-sdk.md#in-javascript-on-macos-enabling-every-peer-to-peer-transport-makes-the-transport-configuration-invalid)).

**Transactions**:
- **Note (SDK 5.0.3 to 5.2.0):** a write through `ditto.store.execute` inside a read-write transaction never completes and raises no exception (see [In JavaScript, store.execute writes inside a transaction deadlock](../../knowledge/observations/javascript-sdk.md#in-javascript-storeexecute-writes-inside-a-transaction-deadlock)).
- **Note (SDK 5.1.0 and 5.2.0):** a read-write transaction started inside another one waits until the outer one ends (see [In JavaScript, a read-write transaction started inside another one waits until the outer one ends](../../knowledge/observations/javascript-sdk.md#in-javascript-a-read-write-transaction-started-inside-another-one-waits-until-the-outer-one-ends)).
- A `tx.execute` that is not awaited is not applied, and its failure can end a Node.js process as an unhandled rejection (see [A tx.execute that is not awaited is not applied](../../knowledge/observations/javascript-sdk.md#a-txexecute-that-is-not-awaited-is-not-applied)).
- **Note (SDK 5.0.3 to 5.2.0):** a Node.js script that keeps neither sync nor a timer running ends with a panic while it awaits a transaction (see [A Node.js script that keeps neither sync nor a timer running ends with a panic while awaiting a transaction](../../knowledge/observations/javascript-sdk.md#a-nodejs-script-that-keeps-neither-sync-nor-a-timer-running-ends-with-a-panic-while-awaiting-a-transaction)).

**Logging**:
- The custom log callback applies to the whole process and stays installed after `close()` (see [In JavaScript, the custom log callback stays installed after close()](../../knowledge/observations/javascript-sdk.md#in-javascript-the-custom-log-callback-stays-installed-after-close)).
- `Logger.exportToFile()` fails for an existing file with `File exists (os error 17)`, and exported logs include debug lines whatever the console level (see [Exported logs include debug lines regardless of the console level](../../knowledge/observations/configuration-and-diagnostics.md#exported-logs-include-debug-lines-regardless-of-the-console-level)).
