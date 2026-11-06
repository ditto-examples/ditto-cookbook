# Scanner Rules

Generated with `python3 scripts/scan.py --list-rules`; do not edit by hand.
Lines that start with a comment marker are skipped. Without Python, search for the
patterns below with Grep, which does not support lookaheads such as `(?!...)`, so drop them
and filter the matches by eye.

## Line Rules

| Rule | Severity | Pattern | Condition | Skill | Guide |
|---|---|---|---|---|---|
| `dql-string-interpolation` | CRITICAL | `\$\{\|\$[A-Za-z_]\w*\|\\\(\|['\"]\s*\+\s*\w\|\w\s*\+\s*['\"]` | line also contains a DQL keyword; in the string that holds the DQL, when the line has one | query-sync | § Always pass values as parameters |
| `in-parenthesized-parameter` | CRITICAL | `\bIN\s*\(\s*:\w+\s*\)` | case-insensitive | query-sync | § Filtering by Membership |
| `any-every-satisfies-over-array` | CRITICAL | `\b(ANY\|EVERY)\s+\w+\s+IN\s+(:\w+\|\[\|\()` | case-insensitive | query-sync | § Filtering by Membership |
| `flag-not-equal-true` | CRITICAL | `\b(WHERE\|AND\|OR)\s+[\w.]+\s*!=\s*true\b\|\b(WHERE\|AND\|OR)\s+NOT\s+is[A-Z]\w*` | case-insensitive | storage-lifecycle | § MISSING and NULL |
| `delete-evict-use-ids` | CRITICAL | `\b(DELETE\|EVICT)\s+FROM\s+\S+\s+USE\s+IDS\b` | case-insensitive; not if `\bWHERE\s+(?!true\b)` matches | storage-lifecycle | § Known Issues in SDK 5.1.0 |
| `composite-index-mixed-direction` | CRITICAL | `\bCREATE\s+INDEX\b[^(]*\((?=[^)]*\bDESC\b)(?=[^)]*(?<!DESC)(?<=[\w\x60\"])\s*[,)])` | case-insensitive | performance-observability | § Known Issues in SDK 5.1.0 |
| `unquoted-object-literal-key` | CRITICAL | `DOCUMENTS\s*\(\s*\{\s*[A-Za-z_]\w*\s*:` | case-insensitive | query-sync | § Quote every key in inline object literals |
| `read-modify-write-counter` | CRITICAL | `\bSET\s+([\w.]+)\s*=\s*\1\s*[-+]` | case-insensitive | data-modeling | § Counters |
| `zone-less-timestamp` | CRITICAL | `DateTime\.now\(\)\.toIso8601String\(\)` | only dart | data-modeling | § Timestamps |
| `zone-less-timestamp` | CRITICAL | `LocalDateTime\.now\(\)\.toString\(\)` | only kotlin | data-modeling | § Timestamps |
| `zone-less-timestamp` | CRITICAL | `[\w$]\s*:\s*(?:new\s+Date\((?:[^()]\|\([^()]*\))*\)\.to(?:UTC\|Locale(?:Date\|Time)?\|Date\|Time)?String\([^)]*\)\|(?<![\w$.])Date\(\))` | only js | data-modeling | § Timestamps |
| `fresh-transport-config` | CRITICAL | `\b(Ditto)?TransportConfig\(\s*\)` | - | sdk-setup | § Transport Configuration |
| `development-authentication` | CRITICAL | `developmentProvider\|Authenticator\.development\|Authenticator\.DEVELOPMENT_PROVIDER\b\|OnlinePlayground\|AuthenticationProvider\.development\b\|provider:\s*\.development\b` | - | sdk-setup | § Authentication in Production |
| `small-peers-without-key` | CRITICAL | `DittoConfigConnectSmallPeersOnly\(\s*\)\|Connect\.SmallPeersOnly\(\s*\)\|\.smallPeersOnly\(\s*(privateKey:\s*nil\s*)?\)\|\bmode:\s*['\"]smallPeersOnly['\"]\s*(?:,\s*privateKey:\s*(?:null\|undefined)\s*)?\}` | - | sdk-setup | § Small-Peers-Only Deployments |
| `hardcoded-private-key` | CRITICAL | `privateKey\s*[:=]\s*['\"]` | - | sdk-setup | § Small-Peers-Only Deployments |
| `revocation-check-disabled` | CRITICAL | `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED['\"]?\s*(?:=\|:\|\bTO\b)\s*false` | case-insensitive | sdk-setup | § Certificate Revocation (SDK 5.1+) |
| `counter-upsert` | CRITICAL | `\bCOUNTER\b.*\bON\s+ID\s+CONFLICT\s+DO\s+UPDATE` | case-insensitive | data-modeling | § Writing documents that contain counters |
| `upsert-do-update` | HIGH | `ON\s+ID\s+CONFLICT\s+DO\s+UPDATE\b(?!_LOCAL_DIFF)` | case-insensitive | query-sync | § ON ID CONFLICT |
| `strict-mode-enabled` | HIGH | `DQL_STRICT_MODE['\"]?\s*(?:=\|:\|\bTO\b)\s*true` | case-insensitive | data-modeling | § Strict Mode |
| `restrict-subscriptions-disabled` | HIGH | `DQL_RESTRICT_SUBSCRIPTIONS['\"]?\s*(?:=\|:\|\bTO\b)\s*false` | case-insensitive | query-sync | § Subscription Rules |
| `subscription-query-arguments` | CRITICAL | `\bqueryArguments(JsonString\|CborBytes)?\b` | only dart | query-sync | § Sync stop, close, and inspection |
| `verbose-logging` | HIGH | `LogLevel\.[vV]erbose\b\|minimumLogLevel\s*=\s*\.verbose\b\|\bminimumLogLevel\s*=\s*['\"]Verbose['\"]` | - | performance-observability | § Log levels |
| `use-index-empty` | HIGH | `USE\s+INDEX\s+(''\|\"\")` | case-insensitive | query-sync | § Performance tips |
| `tombstone-ttl-change` | HIGH | `TOMBSTONE_TTL_HOURS['\"]?\s*(?:=\|:\|\bTO\b)\s*` | case-insensitive | storage-lifecycle | § Tombstone TTL and reaping |
| `is-not-null-existence` | MEDIUM | `\bIS\s+NOT\s+NULL\b` | case-insensitive; line also contains a DQL keyword | query-sync | § MISSING and NULL |
| `advise-and-provision` | MEDIUM | `\bADVISE\s+AND\s+PROVISION\b` | case-insensitive | performance-observability | § ADVISE (SDK 5.1+) |
| `type-equals-number` | MEDIUM | `\btype\(\s*[\w.]+\s*\)\s*=\s*['\"]number['\"]` | case-insensitive | guide | § Type Checking |
| `transaction-without-hint` | MEDIUM | `\.transaction(?:<[^>]*>)?\((?:\s*isReadOnly:\s*\w+\s*,)?\s*\(\w*\)\s*(?:async\s*)?(?:\{\|=>)` | only dart | transactions-attachments | § Transaction Rules |
| `transaction-without-hint` | MEDIUM | `\.transaction\s*(\((?![^)]*\bhint\b)[^)]*\))?\s*\{` | only kotlin | transactions-attachments | § Transaction Rules |
| `transaction-without-hint` | MEDIUM | `\.transaction\s*(\((?![^)]*\bhint\b)[^)]*\))?\s*\{` | only swift | transactions-attachments | § Transaction Rules |
| `variable-precision-timestamp` | MEDIUM | `\.toUtc\(\)\.toIso8601String\(\)` | only dart | data-modeling | § Timestamps |
| `variable-precision-timestamp` | MEDIUM | `\bInstant\.now\(\)\.toString\(\)` | only kotlin | data-modeling | § Timestamps |
| `unconvertible-argument` | HIGH | `double\.(nan\|infinity\|negativeInfinity)\b\|\bBigInt\.(parse\|from\|one\|two\|zero)\b\|['\"][\w.]+['\"]\s*:\s*DateTime\.(now\|utc\|parse\|fromMillisecondsSinceEpoch)\([^)]*\)(?!(?:\.\w+\([^)]*\))*\.(?:millisecondsSinceEpoch\|microsecondsSinceEpoch\|toIso8601String)\b)` | only dart | query-sync | § Always pass values as parameters |
| `unconvertible-argument` | HIGH | `\bto\s+(?:Instant\.now\(\)\|Date\(\)\|UUID\.randomUUID\(\)\|Big(?:Decimal\|Integer)\([^)]*\))(?!\s*\.)` | only kotlin | query-sync | § Always pass values as parameters |
| `unconvertible-argument` | HIGH | `^(?=.*\barguments\s*:).*[:\[,]\s*(Date\(\)\|Decimal\(\|URL\(string:\|[\w.]*\.(nan\|infinity)\b)` | only swift | query-sync | § Always pass values as parameters |
| `all-peer-to-peer-enabled` | MEDIUM | `\.setAllPeerToPeerEnabled\(\s*true\s*\)` | only js | sdk-setup | § Transports and Presence in JavaScript |
| `mutated-document-ids-without-v2` | MEDIUM | `\.mutatedDocumentIDs\(\)` | only js | query-sync | § Query results in JavaScript |
| `logout-cleanup-not-awaited` | MEDIUM | `\.auth\.logout\(\s*(?:async\b\|function\b\|\(?\s*[\w$]*\s*\)?\s*=>)` | only js | sdk-setup | § Authentication in JavaScript |
| `observer-is-stopped-inverted` | MEDIUM | `\.isStopped\b` | only js | sdk-setup | § Closing Ditto in JavaScript |
| `version-string-compare` | MEDIUM | `Ditto\.version\s*(==\|!=)\|Ditto\.version\.(startsWith\|compareTo\|split)\(` | only dart | sdk-setup | § Behavior Specific to the Flutter SDK |
| `float-read-as-double` | MEDIUM | `\]\s*\??\.(double\|doubleOrNull)\b` | only kotlin | query-sync | § Query results in Kotlin |
| `float-read-as-double` | MEDIUM | `\bas\?\s*Double\b` | only swift | query-sync | § Query results in Swift |
| `date-description-timestamp` | HIGH | `\\\(Date\(\)\)\|\bDate\(\)\.description\b` | only swift | data-modeling | § IDs and Timestamps in Swift |
| `open-sync` | MEDIUM | `\bDitto\.openSync\(` | only swift | sdk-setup | § Opening Ditto in Swift |
| `uppercase-uuid` | MEDIUM | `\bUUID\(\)\.uuidString\b(?!\.lowercased\(\))` | only swift | data-modeling | § IDs and Timestamps in Swift |

## Context Rules

| Rule | Severity | Detects | Skill | Guide |
|---|---|---|---|---|
| `subscription-rejected-feature` | HIGH | A `registerSubscription(` call whose query uses a projection, ORDER BY, LIMIT, JOIN, GROUP BY, DISTINCT, or USE IDS | query-sync | § Subscription Rules |
| `execute-inside-transaction` | CRITICAL | `.store.execute(`, `.transaction(`, or `.transaction {` inside the braces of a `.transaction(` callback or a `.transaction {` trailing closure | transactions-attachments | § Transaction Rules |
| `close-on-background` | CRITICAL | `.close()` within 8 lines after `AppLifecycleState.paused` (Dart) | sdk-setup | § Starting and Stopping Sync |
| `observer-onchange-only` | HIGH | `registerObserver*(` with `onChange:` and no `.changes` in the same declaration (Dart) | query-sync | § Store Observers in Flutter |
| `discarded-observer` | HIGH | A statement that starts with `store.registerObserver*(` (or `_ =` before it) and does not keep the returned observer: not assigned, returned, or collected | query-sync | § Observer Lifecycle |
| `discarded-subscription` | HIGH | A statement that starts with `sync.registerSubscription(` (or `_ =` before it) and does not keep the returned subscription | query-sync | § Subscription Lifecycle |
| `result-leaves-handler` | HIGH | An `.execute(` or `.observe(` whose mapping function returns the result or its `items` unchanged, such as `{ result -> result }` or `{ it.items }` (Kotlin) | query-sync | § Query results in Kotlin |
| `concurrent-writes-in-loop` | HIGH | `launch {`, `async {`, `Task {`, or `addTask {` inside a `for`, `repeat`, or `forEach`/`map` loop, with `.store.execute(` in its braces (Kotlin, Swift) | transactions-attachments | § Transaction Rules |
| `ditto-in-ui` | HIGH | `DittoFactory.create(` (Kotlin) or `Ditto.open(` (Dart, Swift) in a file that defines an Activity, Fragment, composable, widget, SwiftUI view, or view controller | sdk-setup | § One instance per persistence directory |
| `login-error-unreported` | MEDIUM | `.login(` inside an `expirationHandler = {` lambda without `try` or `runCatching` (Kotlin) | sdk-setup | § Authentication in Kotlin |
| `login-error-unreported` | MEDIUM | `.login(` inside a `setExpirationHandler(` call that throws or never reads `.error` (JavaScript) | sdk-setup | § Authentication in JavaScript |
| `throwing-observer-handler` | MEDIUM | `!!`, `throw`, `error(`, `require(`, or `check(` in a `registerObserver(` handler without `try` or `runCatching` (Kotlin) | query-sync | § Observer lifecycle in Kotlin |
| `execute-on-main` | MEDIUM | `.store.execute(` in a `lifecycleScope`/`viewModelScope`/`MainScope()` launch or a `Dispatchers.Main` block, before any `withContext(Dispatchers.IO)` (Kotlin) | performance-observability | § Executing DQL in Kotlin |
| `close-inside-transaction` | CRITICAL | `<ditto>.close()` inside the braces of a `.transaction(` callback (Dart) | transactions-attachments | § Closing Ditto in Flutter |
| `work-started-in-transaction` | HIGH | An observer, a `changes.listen(`, a `Timer`, `Future.delayed`, `unawaited(`, or `scheduleMicrotask(` inside a `.transaction(` callback (Dart) | transactions-attachments | § Transactions in Flutter |
| `signal-next-skipped-on-error` | HIGH | `signalNext()` in an async `changes.listen` or `onChange` callback with `await` and no `catch`/`finally` (Dart), in a `{ result, signalNext in` handler with `try` and no `catch`/`defer` (Swift), or in a `registerObserverWithSignalNext(` handler with `await` and no `catch`/`finally` (JavaScript) | performance-observability | § Backpressure (SDK 5.1+) |
| `await-for-without-backpressure` | MEDIUM | `await for (... in x.changes)` where `x` was assigned from `registerObserver(` (Dart) | performance-observability | § Backpressure in Flutter |
| `transaction-without-hint` | MEDIUM | A `.transaction(` call without `hint:` in its arguments (JavaScript) | transactions-attachments | § Transaction Rules |
| `unconvertible-argument` | HIGH | A property value `new Date(...)`, `new Set(...)`, `NaN`, or `Infinity` inside an `execute(`, `registerObserver(`, or `registerSubscription(` call (JavaScript) | query-sync | § Arguments and value types in JavaScript |
| `observer-task-without-backpressure` | HIGH | An `async` handler passed to `registerObserver(` (JavaScript) | performance-observability | § Backpressure in JavaScript |
| `missing-signal-next` | HIGH | A `registerObserverWithSignalNext(` handler without a second parameter, or that never uses it (JavaScript) | performance-observability | § Backpressure in JavaScript |
| `concurrent-writes-in-loop` | HIGH | `.forEach(async` with `.execute(` in its callback (JavaScript) | transactions-attachments | § Transaction Rules |
| `effect-without-cleanup` | HIGH | A `useEffect(` that registers an observer, a subscription, or a fetch and has no `return` (JavaScript) | query-sync | § Observer lifecycle in JavaScript |
| `register-in-render` | HIGH | A registration in the body of a component that returns JSX, outside its effects (JavaScript) | query-sync | § Store Observers in JavaScript |
| `ditto-in-ui` | HIGH | `Ditto.open(` inside a component that returns JSX (JavaScript) | sdk-setup | § One instance per persistence directory |
| `unbounded-data-sync-info-read` | HIGH | An `.execute(` of `system:data_sync_info` in a file without `Promise.race(` (JavaScript), both `withTimeout` and `.async {` (Kotlin), or `withDeadline` or a task group (Swift) | query-sync | § Monitoring Sync Status |
| `observer-task-without-backpressure` | MEDIUM | `Task {` inside the braces of a `registerObserver*(` handler that never mentions `signalNext` (Swift) | performance-observability | § Backpressure in Swift |
