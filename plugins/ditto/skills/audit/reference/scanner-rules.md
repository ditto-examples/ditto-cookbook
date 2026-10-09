# Scanner Rules

Generated with `python3 scripts/scan.py --list-rules`; do not edit by hand.
Lines that start with a comment marker are skipped. Without Python, search for the
patterns below with Grep, which does not support lookaheads such as `(?!...)`, so drop them
and filter the matches by eye.

## Line Rules

| Rule | Severity | Pattern | Condition | Skill | Guide |
|---|---|---|---|---|---|
| `dql-string-interpolation` | CRITICAL | `\$\{\|\$[A-Za-z_]\w*\|\\\(\|['\"]\s*\+\s*\w\|\w\s*\+\s*['\"]` | line also contains a DQL keyword | query-sync | § Always pass values as parameters |
| `in-parenthesized-parameter` | CRITICAL | `\bIN\s*\(\s*:\w+\s*\)` | case-insensitive | query-sync | § Filtering by Membership |
| `any-every-satisfies-over-array` | CRITICAL | `\b(ANY\|EVERY)\s+\w+\s+IN\s+(:\w+\|\[\|\()` | case-insensitive | query-sync | § Filtering by Membership |
| `flag-not-equal-true` | CRITICAL | `\b(WHERE\|AND\|OR)\s+[\w.]+\s*!=\s*true\b\|\b(WHERE\|AND\|OR)\s+NOT\s+is[A-Z]\w*` | case-insensitive | storage-lifecycle | § MISSING and NULL |
| `delete-evict-use-ids` | CRITICAL | `\b(DELETE\|EVICT)\s+FROM\s+\S+\s+USE\s+IDS\b` | case-insensitive; not if `\bWHERE\s+(?!true\b)` matches | storage-lifecycle | § DELETE and EVICT |
| `unquoted-object-literal-key` | CRITICAL | `DOCUMENTS\s*\(\s*\{\s*[A-Za-z_]\w*\s*:` | case-insensitive | query-sync | § Quote every key in inline object literals |
| `read-modify-write-counter` | CRITICAL | `\bSET\s+([\w.]+)\s*=\s*\1\s*[-+]` | case-insensitive | data-modeling | § Counters |
| `zone-less-timestamp` | CRITICAL | `DateTime\.now\(\)\.toIso8601String\(\)` | only dart | data-modeling | § Timestamps |
| `fresh-transport-config` | CRITICAL | `\bTransportConfig\(\s*\)` | - | sdk-setup | § Transport Configuration |
| `development-authentication` | CRITICAL | `developmentProvider\|Authenticator\.development\|OnlinePlayground` | - | sdk-setup | § Authentication in Production |
| `small-peers-without-key` | CRITICAL | `DittoConfigConnectSmallPeersOnly\(\s*\)` | - | sdk-setup | § Small-Peers-Only Deployments |
| `hardcoded-private-key` | CRITICAL | `privateKey\s*[:=]\s*['\"]` | - | sdk-setup | § Small-Peers-Only Deployments |
| `revocation-check-disabled` | CRITICAL | `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED\s*=\s*false` | case-insensitive | sdk-setup | § Certificate Revocation (SDK 5.1+) |
| `upsert-do-update` | HIGH | `ON\s+ID\s+CONFLICT\s+DO\s+UPDATE\b(?!_LOCAL_DIFF)` | case-insensitive | query-sync | § ON ID CONFLICT |
| `strict-mode-enabled` | HIGH | `DQL_STRICT_MODE\s*=\s*true` | case-insensitive | data-modeling | § Strict Mode |
| `restrict-subscriptions-disabled` | HIGH | `DQL_RESTRICT_SUBSCRIPTIONS\s*=\s*false` | case-insensitive | query-sync | § Subscription Rules |
| `subscription-query-arguments` | CRITICAL | `\bqueryArguments(JsonString)?\b` | - | query-sync | § Sync stop, close, and inspection |
| `verbose-logging` | HIGH | `LogLevel\.verbose` | - | performance-observability | § Log levels |
| `use-index-empty` | HIGH | `USE\s+INDEX\s+(''\|\"\")` | case-insensitive | query-sync | § Performance tips |
| `tombstone-ttl-change` | HIGH | `TOMBSTONE_TTL_HOURS\s*=` | case-insensitive | storage-lifecycle | § Tombstone TTL and reaping |
| `is-not-null-existence` | MEDIUM | `\bIS\s+NOT\s+NULL\b` | case-insensitive; line also contains a DQL keyword | query-sync | § MISSING and NULL |
| `advise-and-provision` | MEDIUM | `\bADVISE\s+AND\s+PROVISION\b` | case-insensitive | performance-observability | § ADVISE (SDK 5.1+) |
| `type-equals-number` | MEDIUM | `\btype\(\s*[\w.]+\s*\)\s*=\s*['\"]number['\"]` | case-insensitive | guide | § Type Checking |
| `await-sync-start` | MEDIUM | `await\s+[\w.]*\.sync\.(start\|stop)\(\)` | only dart | sdk-setup | § Starting and Stopping Sync |
| `transaction-without-hint` | MEDIUM | `\.transaction\(\s*\(` | only dart | transactions-attachments | § Transaction Rules |

## Context Rules

| Rule | Severity | Detects | Skill | Guide |
|---|---|---|---|---|
| `subscription-rejected-feature` | HIGH | A `registerSubscription(` call whose query uses a projection, ORDER BY, LIMIT, JOIN, GROUP BY, DISTINCT, or USE IDS | query-sync | § Subscription Rules |
| `execute-inside-transaction` | CRITICAL | `.store.execute(` or `.transaction(` inside the braces of a `.transaction(` callback | transactions-attachments | § Transaction Rules |
| `close-on-background` | CRITICAL | `.close()` within 8 lines after `AppLifecycleState.paused` (Dart) | sdk-setup | § Starting and Stopping Sync |
| `observer-onchange-only` | HIGH | `registerObserver*(` with `onChange:` and no `.changes` in the same declaration (Dart) | query-sync | § Store Observers in Flutter |
