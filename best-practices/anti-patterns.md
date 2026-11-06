# Anti-Pattern Checklist

Use this list in code reviews. Each item links to the section that explains the problem and the recommended pattern. The first three sections apply to every SDK, with the items of each grouped by area; [Specific to One SDK](#specific-to-one-sdk) lists the mistakes that only one SDK's API allows, so review both for the SDK of the app. To start from a symptom instead of the code, see [When Data Does Not Sync](sync-and-subscriptions.md#when-data-does-not-sync) and [When a Statement Fails or Returns Nothing](dql.md#when-a-statement-fails-or-returns-nothing).

## Critical (data loss, wrong results, crashes, security)

**Writes and data model**

- [ ] Reading a whole document, changing it in memory, and writing it back with `ON ID CONFLICT DO UPDATE`, or with `DO UPDATE_LOCAL_DIFF`, which writes the stale copy back as well, for data that other devices edit → [Prefer field-level updates over whole-document rewrites](dql.md#prefer-field-level-updates-over-whole-document-rewrites), [Prefer field-level updates](data-modeling.md#prefer-field-level-updates)
- [ ] Arrays for line items, participants, or other lists that several devices edit (one device's change is lost) → [Arrays and Maps](data-modeling.md#arrays-and-maps)
- [ ] `UNSET` of a map entry that other devices may edit at the same time (the entry survives with only the edited fields, or with them set to `null`; mark it removed with a flag instead) → [Adding, updating, and removing map entries](data-modeling.md#adding-updating-and-removing-map-entries)
- [ ] Expecting `SET obj = {...}` or `ON ID CONFLICT DO UPDATE` to remove keys that were left out → [Assigning an object merges it](dql.md#assigning-an-object-merges-it)
- [ ] Changing the value of a query result row to edit the document (the value is a copy for reading, and nothing is written) → [Materialize values, then let the result go](dql.md#materialize-values-then-let-the-result-go)
- [ ] `SET stock = stock - 1` on values that several devices change instead of a `COUNTER` → [Counters](data-modeling.md#counters)
- [ ] `RESTART WITH` to recalibrate a counter that other devices keep changing while offline (their unsynced increments are discarded, even later ones) → [RESTART](data-modeling.md#restart)
- [ ] An upsert (`ON ID CONFLICT DO UPDATE` or `DO UPDATE_LOCAL_DIFF`) of documents that contain a counter field, or a plain `INSERT` of such a document that another device has already created (the written value restarts the counter like `RESTART WITH`, and increments that have not reached this device are discarded) → [Writing documents that contain counters](data-modeling.md#writing-documents-that-contain-counters)
- [ ] A counter field written with `SET`, created with an undeclared `INSERT` and then incremented, or changed with both `PN_INCREMENT` and `INCREMENT` (the field then holds two values, and reads return the wrong count) → [Keep type declarations consistent](data-modeling.md#keep-type-declarations-consistent), [When counters are appropriate](data-modeling.md#when-counters-are-appropriate)
- [ ] `DELETE` or `UNSET` of a document or map entry that holds a counter (merged with a concurrent increment, it leaves the count at 0; remove it with a flag) → [Writing documents that contain counters](data-modeling.md#writing-documents-that-contain-counters), [Husk documents](deletion-and-storage.md#husk-documents)
- [ ] Sequential or timestamp-only document IDs (offline devices create the same ID, and the documents merge) → [Never use sequential or timestamp-only IDs](data-modeling.md#never-use-sequential-or-timestamp-only-ids)
- [ ] A plain `INSERT` or `ON ID CONFLICT DO UPDATE` for default data that every device creates (the second run fails with an ID conflict, or users' edits are overwritten) → [Default Data with INITIAL Documents](data-modeling.md#default-data-with-initial-documents)
- [ ] Different `INITIAL DOCUMENTS` content for the same `_id` across app versions (removed keys come back from old versions; IDs deleted elsewhere become documents with `null` fields) → [Default Data with INITIAL Documents](data-modeling.md#default-data-with-initial-documents)
- [ ] `DQL_STRICT_MODE = true` without understanding the consequences: fields written as MAP, COUNTER, or ATTACHMENT become invisible unless declared, and the planner (5.1.0 and 5.2.0) does not use secondary indexes; or peers with different `DQL_STRICT_MODE` values whose strict statements do not declare the map fields they read (the peers read different values for the same document) → [Strict Mode](data-modeling.md#strict-mode), [Peers with different settings](data-modeling.md#peers-with-different-settings)
- [ ] Different type declarations (or none) for the same field in different statements → [Keep type declarations consistent](data-modeling.md#keep-type-declarations-consistent)
- [ ] Timestamps without a zone designator, such as a local time formatted without `Z` or an offset (date functions return MISSING) → [Timestamps](data-modeling.md#timestamps) <!-- lint-ignore -->
- [ ] ISO timestamp strings with different fractional precision in one field that is sorted or compared, for example `.123456Z` and `.123Z`, which some standard formatters produce even on one device (string order no longer matches time order; use one fixed-precision helper) → [Timestamps](data-modeling.md#timestamps), [Date and Time](../knowledge/dql-functions.md#date-and-time)
- [ ] Documents that can grow toward the 5 MiB hard limit (writes fail, and devices can end up with different versions of the document), or a raised `DOCUMENT_SIZE_HARD_LIMIT_BYTES` (devices with a lower limit cannot update such documents, or drop the changes that make them larger) → [Document Size Limits](data-modeling.md#document-size-limits)

**Queries**

- [ ] Filters that mean "false or not set" written as `flag != true` or `NOT flag`, such as the soft-delete filter `isDeleted != true` (documents without the field disappear) → [MISSING and NULL](dql.md#missing-and-null), [Soft Delete](deletion-and-storage.md#soft-delete) <!-- lint-ignore -->
- [ ] An array parameter used the wrong way: `IN (:values)` (matches nothing), `field = :values` (compares with the whole array), or `USE IDS :ids` (treats the whole array as one ID); or a single value passed where the statement expects an array, such as a string for `IN :statuses` (matches nothing, without an error) → [Parameters and Literals](dql.md#parameters-and-literals), [Filtering by Membership](dql.md#filtering-by-membership), [USE IDS](dql.md#use-ids)
- [ ] `ANY` or `EVERY ... SATISFIES ... END` over a parameter or literal array in `WHERE`, such as `ANY s IN :statuses SATISFIES s = status END` (returns no rows in local queries and observers in 5.1.0 and 5.2.0, although the subscription syncs the documents; use `status IN :statuses`) → [Filtering by Membership](dql.md#filtering-by-membership) <!-- lint-ignore -->
- [ ] `IS NOT NULL` used to test that a field exists (it is also true for a missing field; use `IS NOT MISSING`) → [MISSING and NULL](dql.md#missing-and-null) <!-- lint-ignore -->
- [ ] DQL built with string interpolation or concatenation → [Always pass values as parameters](dql.md#always-pass-values-as-parameters)
- [ ] Unquoted keys in inline DQL object literals (rejected in `INSERT`, silently `{}` in `SELECT`) → [Quote every key in inline object literals](dql.md#quote-every-key-in-inline-object-literals)
- [ ] DQL that returns wrong values without an error: `type(x) = 'number'` (never matches), swapped arguments to `date_add` and other date functions (MISSING), `COUNT(flag)` on a boolean to count the documents that have it (`false` values are not counted), `MID` used as the median, or `ORDER BY flag = 'x'` in ascending order to put matching documents first (`false` sorts before `true`) → [Type Checking](../knowledge/dql-functions.md#type-checking), [Date and Time](../knowledge/dql-functions.md#date-and-time), [Aggregates](dql.md#aggregates), [ORDER BY](dql.md#order-by)
- [ ] A `JOIN` whose inner collection has no index (or `_id` lookup) for the join key (the query fails) → [Index requirement](dql.md#index-requirement)
- [ ] A `JOIN` over a collection that the device does not subscribe to (a join reads only the local store and pulls nothing from other peers) → [Separate collections with JOIN (SDK 5.1+)](data-modeling.md#separate-collections-with-join-sdk-51), [Performance tips](dql.md#performance-tips)

**Subscriptions and observers**

- [ ] Subscriptions registered only once instead of after every `Ditto.open()` (the device keeps sending its changes but receives nothing, without an error) → [Subscription Lifecycle](sync-and-subscriptions.md#subscription-lifecycle)
- [ ] Subscription filters with `!=` or `NOT IN` on a field that some documents lack (those documents never reach the device), or with `clock()` (documents that enter the time window later are not sent) → [Subscription Rules](sync-and-subscriptions.md#subscription-rules) <!-- lint-ignore -->
- [ ] Counting or processing every change in observer callbacks, for example to count sales or write an audit log (observers skip intermediate states; write each event as its own document) → [When Observers Fire](observers.md#when-observers-fire)

**Deletion and storage**

- [ ] `DELETE` for documents that other devices may update concurrently (husk documents: the document survives even if the `DELETE` happened later; untouched fields become missing) → [Husk documents](deletion-and-storage.md#husk-documents)
- [ ] `DELETE` when devices can stay offline longer than the tombstone TTL (deleted data comes back) → [Tombstone TTL and reaping](deletion-and-storage.md#tombstone-ttl-and-reaping)
- [ ] `DELETE` used to free storage on one device (it removes the documents for every peer; use `EVICT`) → [DELETE and Tombstones](deletion-and-storage.md#delete-and-tombstones), [EVICT](deletion-and-storage.md#evict)
- [ ] A `WHERE` clause of `DELETE`, `EVICT`, or `UPDATE` built from optional filters that can end up empty (the statement changes every document in the collection, without a confirmation or a warning) → [DELETE and EVICT](dql.md#delete-and-evict)

**Transactions**

- [ ] `ditto.store.execute` inside a transaction callback (what happens differs by SDK, and none makes it work), or a read-write transaction nested inside another (deadlock) → [Transaction Rules](transactions.md#transaction-rules)
- [ ] A transaction callback that returns before every `tx.execute` has completed, for example with a missing `await` or `forEach(async ...)` (the statement is not applied, and the transaction commits without an error) → [Transaction Rules](transactions.md#transaction-rules)
- [ ] Many writes started in parallel, such as a coroutine or `Task` per document, while a read-write transaction can be open (each waiting write holds a thread; when the threads run out, the transaction cannot resume and the app stops) → [Transaction Rules](transactions.md#transaction-rules)

**Setup, lifecycle, and transports**

- [ ] Assuming system parameters persist (strict mode, sync scopes, and TTLs silently revert after a restart), setting the app's fixed parameters with `ALTER SYSTEM` after open instead of in `DittoConfig.systemParameters` (SDK 5.2+), or changing parameters such as `DQL_STRICT_MODE` after sync has started or queries and observers have run → [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters)
- [ ] A second open of a persistence directory that is already open (it fails after about a second; in Flutter 5.1.0, it may never complete) → [One instance per persistence directory](setup-and-lifecycle.md#one-instance-per-persistence-directory)
- [ ] App code that reads, writes, or deletes files inside the persistence directory, or a persistence directory copied to another device or installation while the original stays in use, such as a cloned device image or an emulator snapshot (sync breaks without an error) → [One instance per persistence directory](setup-and-lifecycle.md#one-instance-per-persistence-directory)
- [ ] Closing Ditto when the app moves to the background (closing is final: every later call on that instance fails) → [Starting and Stopping Sync](setup-and-lifecycle.md#starting-and-stopping-sync)
- [ ] A `TransportConfig()` built from scratch and assigned (every transport, including peer-to-peer, is disabled; use `updateTransportConfig()`) → [Transport Configuration](setup-and-lifecycle.md#transport-configuration)
- [ ] A hub that more than six devices connect to over TCP without raising `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` before `ditto.sync.start()` (the extra devices get no data and no error), or with `MESH_CHOOSER_AT_CAPACITY_ACTION` used to admit more clients (the hub keeps replacing connections) → [Transport Configuration](setup-and-lifecycle.md#transport-configuration)

**Authentication and security**

- [ ] Throwing inside the authentication expiration handler, including rethrowing `response.exception` → [Authentication](setup-and-lifecycle.md#authentication)
- [ ] An expiration handler that logs in with a token cached for the app's lifetime instead of fetching a fresh one (the handler is called again whenever the credentials expire, so refreshes do not work) → [Authentication](setup-and-lifecycle.md#authentication)
- [ ] The development provider or development token in a production build → [Authentication in Production](security.md#authentication-in-production)
- [ ] `DittoConfigConnectSmallPeersOnly()` without a `privateKey` outside development and tests (peers are not authenticated; documented as unencrypted) → [Small-Peers-Only Deployments](security.md#small-peers-only-deployments)
- [ ] Shared keys, tokens, or API keys hardcoded in the app → [Small-Peers-Only Deployments](security.md#small-peers-only-deployments)
- [ ] Secrets, tokens, or personal data in peer metadata or in the `identityServiceMetadata` returned by the authentication webhook (shared with every peer in the mesh) → [Presence](setup-and-lifecycle.md#presence), [Identity metadata is visible to the mesh](security.md#identity-metadata-is-visible-to-the-mesh)
- [ ] Subscriptions filtered by personal data or secrets, such as an email address (the query and its arguments go to directly connected devices, and both devices write them to their on-disk logs) → [Input Validation and Query Parameters](security.md#input-validation-and-query-parameters)
- [ ] Tokens, keys, or other secrets stored in Ditto documents, or `DELETE` and `EVICT` relied on to remove sensitive data from a device (most deleted and evicted values stay readable in the database files; close Ditto and delete the persistence directory) → [Data at Rest](security.md#data-at-rest)
- [ ] Signing a user out of a shared device without evicting their documents (they stay visible to local queries), without cancelling their subscriptions first (the documents sync back), or before their writes are confirmed → [Switching users on a shared device](setup-and-lifecycle.md#switching-users-on-a-shared-device)
- [ ] Revocation checking (`PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED`) disabled in production → [Certificate Revocation (SDK 5.1+)](security.md#certificate-revocation-sdk-51)
- [ ] Access control that relies on mutable fields, `syncGroup`, sync scopes, or client-side checks → [Permissions](security.md#permissions), [Sync Scopes](sync-and-subscriptions.md#sync-scopes)

**Devices that still run SDK 5.1.0**

- [ ] Where devices still run SDK 5.1.0: `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (removes nothing; use `WHERE _id IN :ids`), composite indexes that mix `ASC` and `DESC` keys, including indexes created from `ADVISE` (results in the wrong order), `ANY ... SATISFIES` conditions on several properties of an element (match every document), 60 or more store observers in the app (every callback stops, without an exception), or very long `OR` or `AND` chains built in code (the process ended at 15,000 `OR` terms) → [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)

## High (sync cost, memory, performance)

**Writes and data model**

- [ ] `ON ID CONFLICT DO UPDATE` for periodic re-upserts of unchanged data, or `UPDATE` statements that write values already stored → [ON ID CONFLICT](dql.md#on-id-conflict)

**Queries**

- [ ] Storing `QueryResult` or `QueryResultItem` objects in state or caches → [Materialize values, then let the result go](dql.md#materialize-values-then-let-the-result-go)

**Subscriptions and observers**

- [ ] Subscriptions or observers that are never cancelled, whose handles are dropped (garbage collection does not stop them), or that are registered in code that runs on every render or rebuild, such as a Flutter `build()` or a React component body → [Subscription Lifecycle](sync-and-subscriptions.md#subscription-lifecycle), [Observer Lifecycle](observers.md#observer-lifecycle)
- [ ] Unfiltered subscriptions on large collections on every device → [Scope subscriptions to what the device needs](sync-and-subscriptions.md#scope-subscriptions-to-what-the-device-needs)
- [ ] Re-registering subscriptions when the user changes a filter, search term, or sort order, or changing subscriptions more often than about every 15 minutes → [Filter locally instead of re-registering](sync-and-subscriptions.md#filter-locally-instead-of-re-registering), [Subscription Lifecycle](sync-and-subscriptions.md#subscription-lifecycle)
- [ ] Projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, or `USE IDS` in subscriptions (rejected), or disabling `DQL_RESTRICT_SUBSCRIPTIONS` to use `LIMIT` and `ORDER BY` (stateful subscriptions; `LIMIT` bounds only the initial download) → [Subscription Rules](sync-and-subscriptions.md#subscription-rules)
- [ ] Subscription filters on mutable fields (`status`, `assignee`), or relay devices with narrower subscriptions than the devices behind them → [Multi-hop relay](sync-and-subscriptions.md#multi-hop-relay)
- [ ] Soft-deleted documents excluded from the subscriptions of devices that relay data to others, or evicted while the subscription still matches them → [Soft delete, subscriptions, and cleanup](deletion-and-storage.md#soft-delete-subscriptions-and-cleanup)
- [ ] An `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` that lists only some of the scoped collections (each statement replaces the whole map, and the collections left out sync again at once) → [Sync Scopes](sync-and-subscriptions.md#sync-scopes)
- [ ] Slow or asynchronous work inside a `registerObserver` listener → [Keep observer callbacks fast](observers.md#keep-observer-callbacks-fast)
- [ ] Observer callbacks that let an error escape, or that call `signalNext()` only when the work succeeds (depending on the SDK, the observer stops delivering updates without a trace, or the process ends) → [Observer Lifecycle](observers.md#observer-lifecycle), [Backpressure (SDK 5.1+)](observers.md#backpressure-sdk-51)
- [ ] Writes to the observed collection from inside its own observer without a guard (each write triggers the observer again) → [Keep observer callbacks fast](observers.md#keep-observer-callbacks-fast)
- [ ] One observer of a whole collection that rebuilds the entire screen, or whose results the app filters or paginates in its own code → [Partial UI Updates](observers.md#partial-ui-updates), [Query Scope and Execution](indexing-and-performance.md#query-scope-and-execution)
- [ ] An observer per list row instead of one for the list (on devices that still run 5.1.0, 60 or more observers stop every callback) → [Observer Lifecycle](observers.md#observer-lifecycle)
- [ ] Observers on `system:data_sync_info` in many UI components, or long-lived observers on `system:system_info` (it fires often, even when nothing changed) → [Monitoring Sync Status](sync-and-subscriptions.md#monitoring-sync-status), [System Virtual Collections](../knowledge/system-reference.md#system-virtual-collections)
- [ ] Reads of `system:data_sync_info` without a deadline (on a connected device, a read can stop responding in JavaScript, in Swift, and in Kotlin 5.1.0, and later reads of it then hang as well) → [Monitoring Sync Status](sync-and-subscriptions.md#monitoring-sync-status)
- [ ] Waiting on the `commitID` of a statement that changed nothing (`mutatedDocumentIDs()` is empty; confirmation takes up to about 27 s), a commit ID read inside the transaction that wrote it (it is empty until the transaction commits), or `sync_session_status` used as a live connection indicator (it lags about 73 s) → [Monitoring Sync Status](sync-and-subscriptions.md#monitoring-sync-status), [Transaction Rules](transactions.md#transaction-rules)

**Attachments**

- [ ] Binary data or base64 files in document fields instead of attachments → [Attachments](attachments.md)
- [ ] Fetching every attachment as soon as its document syncs, fetching large attachments automatically on devices that may only be connected over Bluetooth LE (document sync waits behind the transfer), or fetches without a stall timeout (Ditto has no fetch timeout) → [Fetching Attachments](attachments.md#fetching-attachments), [Size Guidance](attachments.md#size-guidance)
- [ ] Old attachment tokens kept in history documents without a need for them (every referenced blob stays on the device) → [Size Guidance](attachments.md#size-guidance)

**Deletion and storage**

- [ ] Evicting documents that an active subscription still matches (they sync straight back) → [EVICT](deletion-and-storage.md#evict)
- [ ] Evicting more than about once per day → [Eviction frequency](deletion-and-storage.md#eviction-frequency)
- [ ] A Small Peer tombstone TTL (`TOMBSTONE_TTL_HOURS`) above the Ditto Server tombstone TTL → [Tombstone TTL and reaping](deletion-and-storage.md#tombstone-ttl-and-reaping)

**Transactions**

- [ ] Long transactions, or network calls, dialogs, and timers inside a transaction → [Transaction Rules](transactions.md#transaction-rules), [Concurrency and Duration](transactions.md#concurrency-and-duration)

**Indexes and query performance**

- [ ] Missing indexes on the filter and sort fields of hot queries → [Index Usage Rules](indexing-and-performance.md#index-usage-rules)
- [ ] An index on a field with only a few distinct values on its own, such as a boolean or a status (it can be slower than no index), or indexes on every field (each costs write time and storage) → [Where indexes live](indexing-and-performance.md#where-indexes-live)
- [ ] `ORDER BY` in the opposite direction to the composite index that serves the query (an extra sort step) → [Composite indexes and key order (SDK 5.1+)](indexing-and-performance.md#composite-indexes-and-key-order-sdk-51)
- [ ] One `execute` per ID in a loop instead of one query with `_id IN :ids` (each call has a fixed cost: 500 single-ID queries took 0.8 to 0.9 seconds, one `IN` query 6 to 15 ms) → [Query Scope and Execution](indexing-and-performance.md#query-scope-and-execution)
- [ ] `USE INDEX ''` on a large inner collection to silence the JOIN index error (every outer row scans the whole inner collection) → [Performance tips](dql.md#performance-tips)
- [ ] Functions applied to indexed fields in `WHERE` (for example `lower(name) = :name`), or `OR` branches without indexes → [Index Usage Rules](indexing-and-performance.md#index-usage-rules)

**Setup, lifecycle, and transports**

- [ ] Closing Ditto (in Swift, releasing its last strong reference) without awaiting pending queries and transactions, or, where a write must reach another device, without waiting until it is confirmed → [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown)

**Logging and tests**

- [ ] `LogLevel.verbose` in production → [Log levels](logging-and-observability.md#log-levels)

## Medium (maintainability)

**Writes and data model**

- [ ] Stored derived values (totals, counts) that can diverge after merges → [Do not store derived values that can diverge](data-modeling.md#do-not-store-derived-values-that-can-diverge)
- [ ] UI state, progress flags, or device-local paths in synced documents → [Exclude transient and unnecessary fields](data-modeling.md#exclude-transient-and-unnecessary-fields)
- [ ] Own timestamp fields used to decide which concurrent write wins → [Clock drift](data-modeling.md#clock-drift)
- [ ] Field type changes, renames, or removals without a versioning pattern → [Schema Evolution](data-modeling.md#schema-evolution)

**Queries**

- [ ] No `ORDER BY` in queries whose order matters, such as observers, lists, and pages (results have no guaranteed order, not even insertion order) → [Stable ordering](observers.md#stable-ordering), [ORDER BY](dql.md#order-by)
- [ ] A collection named `collection` or other DQL keywords as bare identifiers → [Reserved words](dql.md#reserved-words)
- [ ] Projection aliases in `GROUP BY` or `HAVING` → [GROUP BY and HAVING](dql.md#group-by-and-having)

**Subscriptions and observers**

- [ ] Sync scopes on system collections, whose names start with `__` (the update fails) → [Sync Scopes](sync-and-subscriptions.md#sync-scopes)

**Transactions**

- [ ] Transactions without a `hint`, or a transaction object stored or used after its callback returns (the SDKs reject it) → [Transaction Rules](transactions.md#transaction-rules)

**Indexes and query performance**

- [ ] `CREATE INDEX` on demand before a query, or `ADVISE AND PROVISION` in production code → [Creating Indexes](indexing-and-performance.md#creating-indexes), [ADVISE (SDK 5.1+)](indexing-and-performance.md#advise-sdk-51)

**Logging and tests**

- [ ] No tests for the app's DQL statements, soft-delete filters, and observer cleanup, or local-store tests that start sync (not needed, and in small-peers-only mode it fails without an offline license token) → [Testing Strategies](testing.md)

## Specific to One SDK

Each SDK also allows mistakes that the others do not. The items below are ranked by severity within each SDK; the *Behavior Specific to the SDK* section at the end of each SDK page lists the behavior behind them.

### In Flutter apps

- [ ] **Critical**: `ditto.close()` on `AppLifecycleState.paused` (every later call on that instance throws `DittoClosedException`) → [Sync and the App Lifecycle in Flutter](platforms/flutter.md#sync-and-the-app-lifecycle-in-flutter)
- [ ] **Critical**: `ditto.close()` while a transaction, also a read-only one, is open (it stops the isolate, and the UI stops responding) → [Closing Ditto in Flutter](platforms/flutter.md#closing-ditto-in-flutter)
- [ ] **Critical**: Reading `queryArguments`, `queryArgumentsJsonString`, or `queryArgumentsCborBytes` from elements of `ditto.sync.subscriptions` for subscriptions registered without arguments (ends the app on SDK 5.1.0 and 5.2.0) → [Sync stop, close, and inspection](sync-and-subscriptions.md#sync-stop-close-and-inspection), [Subscriptions in Flutter](platforms/flutter.md#subscriptions-in-flutter)
- [ ] **High**: Observers registered with `onChange` while the `changes` stream is never listened to, or `registerObserverV2` observers whose `changes` stream is not listened to right after registration (memory grows with every update) → [Store Observers in Flutter](platforms/flutter.md#store-observers-in-flutter)
- [ ] **High**: A `Timer`, `Future.delayed`, observer listener, or other work started inside a transaction callback that calls `ditto.store.execute` later (it throws `Transaction is no longer valid`, also after the commit) → [Transactions in Flutter](platforms/flutter.md#transactions-in-flutter)
- [ ] **High**: `DateTime` values passed as arguments (stored with microseconds, or with a local offset, instead of the app's fixed-precision UTC format), `BigInt` values of 2^63 or more (they come back as a `double` or as bytes), or `double.nan` and `double.infinity` (the write fails) → [Arguments and value types in Flutter](platforms/flutter.md#arguments-and-value-types-in-flutter)
- [ ] **High**: On SDK 5.2.0, closing and reopening Ditto in one process, or dropping the `SyncSubscription` and `Transaction` objects of a closed instance (the next `Ditto.open()` or `close()` can stop) → [Subscriptions in Flutter](platforms/flutter.md#subscriptions-in-flutter), [Changes in SDK 5.2.0](../knowledge/upgrading.md#changes-in-sdk-520)
- [ ] **Medium**: `await for` over the `changes` of a `registerObserver` observer for slow work (it processes every queued result; use `registerObserverV2`) → [Backpressure in Flutter](platforms/flutter.md#backpressure-in-flutter)
- [ ] **Medium**: `DittoLogger.customLogCallback` set only once (`close()` resets it to `null` for the whole process) → [Logging in Flutter](platforms/flutter.md#logging-in-flutter)
- [ ] **Medium**: `Ditto.version` compared as a string (it includes a platform prefix and a build hash) → [Behavior Specific to the Flutter SDK](platforms/flutter.md#behavior-specific-to-the-flutter-sdk)

### In JavaScript apps

- [ ] **Critical**: `Date`, `Set`, function, or `Symbol` values in arguments (stored as `{}`, and the value is lost) → [Arguments and value types in JavaScript](platforms/javascript.md#arguments-and-value-types-in-javascript)
- [ ] **Critical**: An `async` observer handler that can reject (the SDK does not handle the promise, and the unhandled rejection ends a Node.js process by default) → [Store Observers in JavaScript](platforms/javascript.md#store-observers-in-javascript)
- [ ] **High**: An `async` handler passed to `registerObserver` for slow work (calls overlap, and an older result can finish last, so the screen shows an older state) → [Backpressure in JavaScript](platforms/javascript.md#backpressure-in-javascript)
- [ ] **High**: A `registerObserverWithSignalNext` handler that does not call `signalNext` on every path, including errors (the observer stops delivering updates) → [Backpressure in JavaScript](platforms/javascript.md#backpressure-in-javascript)
- [ ] **High**: A React `useEffect` that registers an observer, a subscription, or an attachment fetch and returns no cleanup, a registration in a component body outside its effects, or `Ditto.open()` in a component → [Observer lifecycle in JavaScript](platforms/javascript.md#observer-lifecycle-in-javascript), [Store Observers in JavaScript](platforms/javascript.md#store-observers-in-javascript), [One shared instance in JavaScript](platforms/javascript.md#one-shared-instance-in-javascript)
- [ ] **Medium**: An expiration handler that never reads the `error` of the result of `ditto.auth.login()` (`login()` does not throw when the token is rejected or the server is unreachable) → [Authentication in JavaScript](platforms/javascript.md#authentication-in-javascript)
- [ ] **Medium**: An `async` cleanup passed to `ditto.auth.logout(cleanup)` that must finish before the next step (`logout()` does not await it) → [Authentication in JavaScript](platforms/javascript.md#authentication-in-javascript)
- [ ] **Medium**: `setAllPeerToPeerEnabled(true)` on Node.js on macOS (the transport configuration becomes invalid; use `setAvailablePeerToPeerEnabled(true)`) → [Transports and Presence in JavaScript](platforms/javascript.md#transports-and-presence-in-javascript)
- [ ] **Medium**: `result.mutatedDocumentIDs()` (it does not exist in JavaScript; use `mutatedDocumentIDsV2()`) → [Query results in JavaScript](platforms/javascript.md#query-results-in-javascript)
- [ ] **Medium**: `isStopped` of the observers that `presence.observe()`, `auth.observeStatus()`, or `observeTransportConditions()` return, used as their state (it is `true` while the observer is active) → [Closing Ditto in JavaScript](platforms/javascript.md#closing-ditto-in-javascript)

### In Kotlin apps

- [ ] **Critical**: A `DittoQueryResult` or its items returned from an `execute` handler, or read after the handler has returned (the result is closed, and reading it throws `IllegalStateException`) → [Query results in Kotlin](platforms/kotlin.md#query-results-in-kotlin)
- [ ] **Critical**: Typed accessors such as `.string` or `.double` on fields that can be missing or `null` (they throw `DittoException.FatalException`), or `doubleOrNull` for decimal numbers (it returns `null` for a value such as `7.5`, which comes back as a `FloatValue`) → [Query results in Kotlin](platforms/kotlin.md#query-results-in-kotlin)
- [ ] **Critical**: `login()` inside the expiration handler without `try` (`login()` throws `DittoException.AuthenticationException` when the token is rejected or the server is unreachable, and a handler that throws is only logged, so the failure goes unreported) → [Authentication in Kotlin](platforms/kotlin.md#authentication-in-kotlin)
- [ ] **High**: Slow or blocking work in observer handlers while `DittoFactory.create` has the default scope (the handlers run on the main thread and freeze the UI) → [Opening Ditto in Kotlin](platforms/kotlin.md#opening-ditto-in-kotlin), [Store Observers in Kotlin](platforms/kotlin.md#store-observers-in-kotlin)
- [ ] **High**: A `registerObserver` handler that can throw, for example through `!!`, `require`, or `error()` (the observer is closed, the exception is only logged, and the screen stops updating) → [Observer lifecycle in Kotlin](platforms/kotlin.md#observer-lifecycle-in-kotlin)
- [ ] **High**: `store.execute` called on the main thread (it blocks the calling thread while the query runs and while it waits for a write transaction) → [Executing DQL in Kotlin](platforms/kotlin.md#executing-dql-in-kotlin)
- [ ] **High**: `java.util.Date`, `Instant`, `UUID`, `BigDecimal`, or `BigInteger` values in arguments (`IllegalArgumentException`; pass strings), or `NaN` and infinity (the write fails) → [Arguments and value types in Kotlin](platforms/kotlin.md#arguments-and-value-types-in-kotlin)

### In Swift apps

- [ ] **Critical**: No strong reference to the `Ditto` instance for as long as the app uses it, for example only `ditto.store` or `ditto.sync` kept, which reference it weakly (the instance shuts down at once; later calls throw `useAfterCloseError` or end the process with a `Fatal error`) → [Opening Ditto in Swift](platforms/swift.md#opening-ditto-in-swift), [Closing Ditto in Swift](platforms/swift.md#closing-ditto-in-swift)
- [ ] **Critical**: `as? Double` on numbers read from `item.value` (it is `nil` for a value that a 32-bit float holds exactly, such as `12.5`; use `as? NSNumber` or `JSONDecoder`) → [Query results in Swift](platforms/swift.md#query-results-in-swift)
- [ ] **High**: `Date`, `Decimal`, or `URL` values in arguments (stored as objects of their fields instead of a time, a number, or a string), or `"\(Date())"` and `Date().description` as timestamps (a space instead of `T`, no fractional seconds, and `+0000` instead of `Z`) → [Arguments and value types in Swift](platforms/swift.md#arguments-and-value-types-in-swift), [IDs and Timestamps in Swift](platforms/swift.md#ids-and-timestamps-in-swift)
- [ ] **High**: Slow work in a `handler:` that runs on `.main`, the default of `deliverOn` (it delays both the updates and the UI), or a `Task` started in the handler for every update (the tasks overlap, and an older result can finish last) → [Backpressure in Swift](platforms/swift.md#backpressure-in-swift)
- [ ] **Medium**: `UUID().uuidString` as a document ID without `lowercased()` (Swift's UUIDs are uppercase, most other platforms' lowercase) → [IDs and Timestamps in Swift](platforms/swift.md#ids-and-timestamps-in-swift)
- [ ] **Medium**: `Ditto.openSync` on the main thread (it blocks the thread until the store is open) → [Opening Ditto in Swift](platforms/swift.md#opening-ditto-in-swift)
