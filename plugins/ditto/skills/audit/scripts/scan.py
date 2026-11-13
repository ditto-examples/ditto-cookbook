#!/usr/bin/env python3
"""Scan source files for known Ditto SDK anti-patterns.

Every hit is a *candidate*: the scanner matches text, not program behavior.
Read the surrounding code and confirm each hit against the skill and guide
section it names before reporting it. The severity of each rule is that of the
item of the guide's anti-pattern checklist that it detects.

Usage:
    python3 scan.py [PATH ...] [--json] [--min-severity LEVEL] [--fail-on LEVEL]
                    [--exclude GLOB ...] [--list-rules]

PATH defaults to the current directory. Directories are searched for .dart,
.js, .mjs, .cjs, .jsx, .ts, .tsx, .swift, .kt, and .kts files, skipping
generated and vendored code: the directories .git, .idea, .next, .dart_tool,
build, node_modules, Pods, .swiftpm, Carthage, vendor, .gradle, .expo,
coverage, dist, DerivedData, and .build, and the files *.g.dart,
*.freezed.dart, *.d.ts, and *.min.js. --exclude GLOB (repeatable) skips more:
a glob is matched against each file and directory name and against its path
relative to the directory given on the command line, such as
--exclude 'lib/generated' or --exclude '*_test.dart'. A file or directory
named on the command line is always scanned.

To silence a hit that has been reviewed, put a comment with
`ditto-scan: ignore` (every rule) or `ditto-scan: ignore[rule-id, ...]` on its
line or on a comment line directly above it.

The hits go to stdout (text, or a JSON array with --json); a summary goes to
stderr: files scanned, hits by severity, and how many hits --min-severity hid
and suppression comments silenced.

Exit status:
    0  the scan finished (also with hits, unless --fail-on applies)
    1  --fail-on LEVEL is given and a reported hit is at LEVEL or above
    2  a path does not exist, no source file was scanned, or the arguments
       are invalid (2 takes precedence over 1)

Requires Python 3.8+ and no third-party packages.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from typing import Callable, Dict, Iterable, List, Optional, Sequence, Tuple, Union

SEVERITIES = ("CRITICAL", "HIGH", "MEDIUM")

EXTENSIONS = {
    ".dart": "dart",
    ".js": "js",
    ".mjs": "js",
    ".cjs": "js",
    ".jsx": "js",
    ".ts": "js",
    ".tsx": "js",
    ".swift": "swift",
    ".kt": "kotlin",
    ".kts": "kotlin",
}

LANGUAGES = ("dart", "js", "kotlin", "swift")

# Generated, vendored, and tool directories, skipped below a directory given on the
# command line.
SKIPPED_DIRS = {
    ".git",
    ".idea",
    ".next",
    ".dart_tool",
    "build",
    "node_modules",
    "Pods",
    ".swiftpm",
    "Carthage",
    "vendor",
    ".gradle",
    ".expo",
    "coverage",
    "dist",
    "DerivedData",
    ".build",
}
# Generated and bundled files, skipped unless named on the command line.
SKIPPED_FILES = ("*.g.dart", "*.freezed.dart", "*.d.ts", "*.min.js")

DQL_KEYWORDS = re.compile(
    r"\b(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|EVICT\s+FROM|ALTER\s+SYSTEM)\b"
)


@dataclass
class Finding:
    path: str
    line: int
    severity: str
    rule: str
    message: str
    skill: str
    guide: str
    code: str


@dataclass
class LineRule:
    rule: str
    severity: str
    # One pattern, or one pattern per language for a rule whose code differs by SDK.
    pattern: Union[re.Pattern, Dict[str, re.Pattern]]
    message: str
    skill: str
    # One guide section, or one per language when each SDK page explains the rule.
    guide: Union[str, Dict[str, str]]
    # The item of best-practices/anti-patterns.md that the rule detects, as a distinctive
    # part of its text (one per language where the SDKs' items differ), or None when no
    # item covers it. The rule's severity is that item's severity.
    checklist: Union[Optional[str], Dict[str, Optional[str]]]
    languages: Optional[Sequence[str]] = None
    # Only report the line if it also looks like DQL.
    requires_dql: bool = False
    # Do not report the line if this pattern also matches it.
    unless: Optional[re.Pattern] = None
    # Only report the line if this also returns True for it, and say so in the rule list.
    refine: Optional[Callable[[str], bool]] = None
    refine_note: str = ""

    def guide_for(self, language: str) -> str:
        if isinstance(self.guide, dict):
            return self.guide[language]
        return self.guide

    def pattern_for(self, language: str) -> Optional[re.Pattern]:
        if isinstance(self.pattern, dict):
            return self.pattern.get(language)
        if self.languages and language not in self.languages:
            return None
        return self.pattern


@dataclass
class ContextRule:
    """A rule that needs more than one line, reported by a scan_* function through report()."""
    rule: str
    severity: str
    detects: str
    skill: str
    guide: str
    # As in LineRule: the checklist item that the rule detects, or None.
    checklist: Optional[str]
    languages: Sequence[str] = LANGUAGES
    # A second row for the same rule and language, when one case of it has another severity.
    variant: str = ""


def rx(pattern: str, flags: int = re.IGNORECASE) -> re.Pattern:
    return re.compile(pattern, flags)


LITERAL = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"|`[^`]*`")
INTERPOLATION = re.compile(r"\$\{|\$[A-Za-z_]\w*|\\\(")


def interpolates_statement(line: str) -> bool:
    """Whether the string literal that holds the DQL is interpolated or concatenated.

    A line without a complete literal that holds DQL (a multi-line string) counts."""
    statements = [match for match in LITERAL.finditer(line) if DQL_KEYWORDS.search(match.group())]
    if not statements:
        return True
    for match in statements:
        before = line[:match.start()].rstrip()
        after = line[match.end():].lstrip()
        if INTERPOLATION.search(match.group()) or before.endswith("+") or after.startswith("+"):
            return True
    return False


# A system parameter being set: `ALTER SYSTEM SET NAME = value` or `... TO value`,
# or a map entry in DittoConfig.systemParameters (SDK 5.2+), such as
# 'NAME': value (Dart, Swift, JavaScript) or "NAME" to value (Kotlin).
SETS = r"['\"]?\s*(?:=|:|\bTO\b)\s*"


LINE_RULES: List[LineRule] = [
    # --- CRITICAL: wrong results, data loss, crashes, security ---
    LineRule(
        "dql-string-interpolation",
        "CRITICAL",
        rx(r"\$\{|\$[A-Za-z_]\w*|\\\(|['\"]\s*\+\s*\w|\w\s*\+\s*['\"]", 0),
        "DQL built with interpolation or concatenation; pass values as :parameters "
        "(a backtick map key cannot be a parameter: validate it strictly before splicing)",
        "query-sync",
        "Always pass values as parameters",
        "DQL built with string interpolation or concatenation",
        requires_dql=True,
        refine=interpolates_statement,
        refine_note="in the string that holds the DQL, when the line has one",
    ),
    LineRule(
        "in-parenthesized-parameter",
        "CRITICAL",
        rx(r"\bIN\s*\(\s*:\w+\s*\)"),
        "IN (:values) matches nothing for an array parameter; write IN :values",
        "query-sync",
        "Filtering by Membership",
        "`IN (:values)` (matches nothing)",
    ),
    LineRule(
        "any-every-satisfies-over-array",
        "CRITICAL",
        rx(r"\b(ANY|EVERY)\s+\w+\s+IN\s+(:\w+|\[|\()"),
        "ANY/EVERY ... SATISFIES over a parameter or literal array returns no rows in "
        "local queries and observers (SDK 5.1.0 and 5.2.0); use field IN :values",
        "query-sync",
        "Filtering by Membership",
        "`ANY` or `EVERY ... SATISFIES ... END` over a parameter or literal array",
    ),
    LineRule(
        "flag-not-equal-true",
        "CRITICAL",
        rx(r"\b(WHERE|AND|OR)\s+[\w.]+\s*!=\s*true\b|\b(WHERE|AND|OR)\s+NOT\s+is[A-Z]\w*"),
        "Comparison drops documents where the flag is missing or null; "
        "use coalesce(flag, false) = false",
        "storage-lifecycle",
        "MISSING and NULL",
        'Filters that mean "false or not set"',
    ),
    LineRule(
        "delete-evict-use-ids",
        "CRITICAL",
        rx(r"\b(DELETE|EVICT)\s+FROM\s+\S+\s+USE\s+IDS\b"),
        "DELETE/EVICT with USE IDS and no WHERE predicate removes nothing in SDK 5.1.0 "
        "(fixed in 5.2.0); use WHERE _id IN :ids while any device runs 5.1.0",
        "storage-lifecycle",
        "Known Issues in SDK 5.1.0",
        "`DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate",
        unless=rx(r"\bWHERE\s+(?!true\b)"),
    ),
    LineRule(
        "composite-index-mixed-direction",
        "CRITICAL",
        rx(r"\bCREATE\s+INDEX\b[^(]*\((?=[^)]*\bDESC\b)(?=[^)]*(?<!DESC)(?<=[\w\x60\"])\s*[,)])"),
        "Composite index that mixes ASC and DESC keys returns results in the wrong order "
        "in SDK 5.1.0 (fixed in 5.2.0); keep all keys in one direction while any device "
        "runs 5.1.0",
        "performance-observability",
        "Known Issues in SDK 5.1.0",
        "composite indexes that mix `ASC` and `DESC` keys",
    ),
    LineRule(
        "unquoted-object-literal-key",
        "CRITICAL",
        rx(r"DOCUMENTS\s*\(\s*\{\s*[A-Za-z_]\w*\s*:"),
        "Unquoted key in an inline DQL object literal (rejected in INSERT, {} in SELECT); "
        "quote keys or pass the document as a parameter",
        "query-sync",
        "Quote every key in inline object literals",
        "Unquoted keys in inline DQL object literals",
    ),
    LineRule(
        "read-modify-write-counter",
        "CRITICAL",
        rx(r"\bSET\s+([\w.]+)\s*=\s*\1\s*[-+]"),
        "Read-modify-write of a number loses concurrent changes; use a COUNTER with APPLY",
        "data-modeling",
        "Counters",
        "on values that several devices change instead of a `COUNTER`",
    ),
    LineRule(
        "zone-less-timestamp",
        "CRITICAL",
        {
            "dart": rx(r"DateTime\.now\(\)\.toIso8601String\(\)", 0),
            "kotlin": rx(r"LocalDateTime\.now\(\)\.toString\(\)", 0),
            # A property value: Date's local or non-ISO strings, or Date() without new.
            "js": rx(r"[\w$]\s*:\s*(?:new\s+Date\((?:[^()]|\([^()]*\))*\)\.to(?:UTC|Locale(?:Date|Time)?|Date|Time)?"
                     r"String\([^)]*\)|(?<![\w$.])Date\(\))", 0),
        },
        "Timestamp string that DQL date functions cannot read (local time without a zone "
        "designator, or not ISO 8601), so they return MISSING; store UTC ISO 8601 from one "
        "fixed-precision helper",
        "data-modeling",
        "Timestamps",
        "Timestamps without a zone designator",
    ),
    LineRule(
        "fresh-transport-config",
        "CRITICAL",
        rx(r"\b(Ditto)?TransportConfig\(\s*\)", 0),
        "A new TransportConfig() or DittoTransportConfig() disables every transport; change "
        "the current one with updateTransportConfig",
        "sdk-setup",
        "Transport Configuration",
        "A `TransportConfig()` built from scratch",
    ),
    LineRule(
        "development-authentication",
        "CRITICAL",
        rx(r"developmentProvider|Authenticator\.development|Authenticator\.DEVELOPMENT_PROVIDER\b"
           r"|OnlinePlayground|AuthenticationProvider\.development\b|provider:\s*\.development\b", 0),
        "Development provider or token; never ship it in a production build",
        "sdk-setup",
        "Authentication in Production",
        "The development provider or development token in a production build",
    ),
    LineRule(
        "small-peers-without-key",
        "CRITICAL",
        rx(r"DittoConfigConnectSmallPeersOnly\(\s*\)|Connect\.SmallPeersOnly\(\s*\)"
           r"|\.smallPeersOnly\(\s*(privateKey:\s*nil\s*)?\)"
           r"|\bmode:\s*['\"]smallPeersOnly['\"]\s*(?:,\s*privateKey:\s*(?:null|undefined)\s*)?\}", 0),
        "Small-peers-only mode without a privateKey does not authenticate peers; "
        "acceptable only in tests and development",
        "sdk-setup",
        "Small-Peers-Only Deployments",
        "`DittoConfigConnectSmallPeersOnly()` without a `privateKey`",
    ),
    LineRule(
        "hardcoded-private-key",
        "CRITICAL",
        rx(r"privateKey\s*[:=]\s*['\"]", 0),
        "Shared key hardcoded in source; load it from secure provisioning",
        "sdk-setup",
        "Small-Peers-Only Deployments",
        "Shared keys, tokens, or API keys hardcoded in the app",
    ),
    LineRule(
        "revocation-check-disabled",
        "CRITICAL",
        rx(r"PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED" + SETS + r"false"),
        "Certificate revocation checking disabled",
        "sdk-setup",
        "Certificate Revocation (SDK 5.1+)",
        "Revocation checking (`PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED`) disabled",
    ),
    LineRule(
        "counter-upsert",
        "CRITICAL",
        rx(r"\bCOUNTER\b.*\bON\s+ID\s+CONFLICT\s+DO\s+UPDATE"),
        "An upsert that writes a COUNTER field restarts the counter and discards "
        "increments not yet received (SDK 5.1.0 and 5.2.0); leave counters out of "
        "upserted documents and use APPLY ... INCREMENT BY",
        "data-modeling",
        "Writing documents that contain counters",
        "of documents that contain a counter field",
    ),
    LineRule(
        "strict-mode-enabled",
        "CRITICAL",
        rx(r"DQL_STRICT_MODE" + SETS + r"true"),
        "Strict mode hides undeclared MAP/COUNTER/ATTACHMENT fields and disables "
        "secondary index use (SDK 5.1.0 and 5.2.0); confirm it is intended and set on "
        "every open (DittoConfig.systemParameters in SDK 5.2+)",
        "data-modeling",
        "Strict Mode",
        "`DQL_STRICT_MODE = true` without understanding the consequences",
    ),
    LineRule(
        "subscription-query-arguments",
        "CRITICAL",
        rx(r"\bqueryArguments(JsonString|CborBytes)?\b", 0),
        "Reading the arguments of an element of ditto.sync.subscriptions that was registered "
        "without arguments ends a Flutter app (SDK 5.1.0 and 5.2.0); read only queryString "
        "there, and keep your own references for the arguments",
        "query-sync",
        "Sync stop, close, and inspection",
        "Reading `queryArguments`, `queryArgumentsJsonString`, or `queryArgumentsCborBytes`",
        languages=("dart",),
    ),
    LineRule(
        "is-not-null-existence",
        "CRITICAL",
        rx(r"\bIS\s+NOT\s+NULL\b"),
        "IS NOT NULL is also true for a missing field; to test existence use IS NOT MISSING",
        "query-sync",
        "MISSING and NULL",
        "`IS NOT NULL` used to test that a field exists",
        requires_dql=True,
    ),
    LineRule(
        "type-equals-number",
        "CRITICAL",
        rx(r"\btype\(\s*[\w.]+\s*\)\s*=\s*['\"]number['\"]"),
        "type(x) = 'number' never matches",
        "guide",
        "Type Checking",
        "`type(x) = 'number'` (never matches)",
    ),
    LineRule(
        "variable-precision-timestamp",
        "CRITICAL",
        {
            "dart": rx(r"\.toUtc\(\)\.toIso8601String\(\)", 0),
            "kotlin": rx(r"\bInstant\.now\(\)\.toString\(\)", 0),
        },
        "This format writes as many fraction digits as needed, so the strings do not sort "
        "chronologically; produce timestamps with one fixed-precision UTC helper",
        "data-modeling",
        "Timestamps",
        "ISO timestamp strings with different fractional precision",
    ),
    LineRule(
        "float-read-as-double",
        "CRITICAL",
        {
            "kotlin": rx(r"\]\s*\??\.(double|doubleOrNull)\b", 0),
            "swift": rx(r"\bas[?!]\s*Double\b", 0),
        },
        "A decimal that a 32-bit float holds exactly, such as 7.5, comes back as a float "
        "(Kotlin FloatValue, Swift Float), so reading it as a Double gives null or nil; read "
        "numbers with a helper that accepts every number type (Swift: NSNumber)",
        "query-sync",
        {"kotlin": "Query results in Kotlin", "swift": "Query results in Swift"},
        {
            "kotlin": "or `doubleOrNull` for decimal numbers",
            "swift": "`as? Double` on numbers read from `item.value`",
        },
    ),
    # --- HIGH: sync cost, memory, performance ---
    LineRule(
        "upsert-do-update",
        "HIGH",
        rx(r"ON\s+ID\s+CONFLICT\s+DO\s+UPDATE\b(?!_LOCAL_DIFF)"),
        "DO UPDATE rewrites unchanged fields, which overwrites earlier concurrent edits "
        "of them and wakes observers; prefer DO UPDATE_LOCAL_DIFF, and never write back "
        "a stale whole document",
        "query-sync",
        "ON ID CONFLICT",
        "`ON ID CONFLICT DO UPDATE` for periodic re-upserts of unchanged data",
    ),
    LineRule(
        "restrict-subscriptions-disabled",
        "HIGH",
        rx(r"DQL_RESTRICT_SUBSCRIPTIONS" + SETS + r"false"),
        "Stateful LIMIT/ORDER BY subscriptions degrade sync; LIMIT bounds only the "
        "initial download",
        "query-sync",
        "Subscription Rules",
        "disabling `DQL_RESTRICT_SUBSCRIPTIONS`",
    ),
    LineRule(
        "verbose-logging",
        "HIGH",
        rx(r"LogLevel\.[vV]erbose\b|minimumLogLevel\s*=\s*\.verbose\b"
           r"|\bminimumLogLevel\s*=\s*['\"]Verbose['\"]", 0),
        "Verbose logging can significantly slow replication; never in production",
        "performance-observability",
        "Log levels",
        "`LogLevel.verbose` in production",
    ),
    LineRule(
        "use-index-empty",
        "HIGH",
        rx(r"USE\s+INDEX\s+(''|\"\")"),
        "USE INDEX '' makes every outer row scan the inner collection; create the "
        "index instead",
        "query-sync",
        "Performance tips",
        "`USE INDEX ''` on a large inner collection",
    ),
    LineRule(
        "tombstone-ttl-change",
        "HIGH",
        rx(r"TOMBSTONE_TTL_HOURS" + SETS),
        "Tombstone TTL on a device must not exceed the Ditto Server TTL, and must be "
        "set on every open (DittoConfig.systemParameters in SDK 5.2+)",
        "storage-lifecycle",
        "Tombstone TTL and reaping",
        "A Small Peer tombstone TTL (`TOMBSTONE_TTL_HOURS`) above the Ditto Server tombstone TTL",
    ),
    LineRule(
        "unconvertible-argument",
        "HIGH",
        {
            "dart": rx(r"double\.(nan|infinity|negativeInfinity)\b|\bBigInt\.(parse|from|one|two|zero)\b"
                       r"|['\"][\w.]+['\"]\s*:\s*DateTime\.(now|utc|parse|fromMillisecondsSinceEpoch)\([^)]*\)"
                       r"(?!(?:\.\w+\([^)]*\))*\.(?:millisecondsSinceEpoch|microsecondsSinceEpoch|toIso8601String)\b)", 0),
            "kotlin": rx(r"\bto\s+(?:Instant\.now\(\)|Date\(\)|UUID\.randomUUID\(\)"
                         r"|Big(?:Decimal|Integer)\([^)]*\))(?!\s*\.)", 0),
            # A dictionary value on a line that passes arguments.
            "swift": rx(r"^(?=.*\barguments\s*:).*[:\[,]\s*(Date\(\)|Decimal\(|URL\(string:"
                        r"|[\w.]*\.(nan|infinity)\b)", 0),
        },
        "An argument value that is not plain JSON (a date, a big number, a UUID, NaN, or "
        "infinity) fails or is stored as something else; pass UTC strings, epoch "
        "milliseconds, or strings",
        "query-sync",
        {
            "dart": "Arguments and value types in Flutter",
            "kotlin": "Arguments and value types in Kotlin",
            "swift": "Arguments and value types in Swift",
        },
        {
            "dart": "`DateTime` values passed as arguments",
            "kotlin": "`java.util.Date`, `Instant`, `UUID`, `BigDecimal`, or `BigInteger` values in arguments",
            "swift": "`Date`, `Decimal`, or `URL` values in arguments",
        },
    ),
    LineRule(
        "date-description-timestamp",
        "HIGH",
        rx(r"\\\(Date\(\)\)|\bDate\(\)\.description\b", 0),
        "A Date's description is not ISO 8601 (a space instead of T, no fractional seconds, "
        "+0000 instead of Z); format UTC with ISO8601FormatStyle and fractional seconds",
        "data-modeling",
        "IDs and Timestamps in Swift",
        "`Date().description` as timestamps",
        languages=("swift",),
    ),
    # --- MEDIUM: maintainability and SDK-specific mistakes ---
    LineRule(
        "advise-and-provision",
        "MEDIUM",
        rx(r"\bADVISE\s+AND\s+PROVISION\b"),
        "ADVISE AND PROVISION creates indexes as a side effect; keep it out of production code",
        "performance-observability",
        "ADVISE (SDK 5.1+)",
        "`ADVISE AND PROVISION` in production code",
    ),
    LineRule(
        "transaction-without-hint",
        "MEDIUM",
        {
            # The callback without a hint: before it on the same line.
            "dart": rx(r"\.transaction(?:<[^>]*>)?\((?:\s*isReadOnly:\s*\w+\s*,)?\s*\(\w*\)\s*"
                       r"(?:async\s*)?(?:\{|=>)", 0),
            # A trailing closure without hint in the parentheses before it.
            "kotlin": rx(r"\.transaction\s*(\((?![^)]*\bhint\b)[^)]*\))?\s*\{", 0),
            "swift": rx(r"\.transaction\s*(\((?![^)]*\bhint\b)[^)]*\))?\s*\{", 0),
        },
        "Transaction without a hint; long transactions are logged by hint",
        "transactions-attachments",
        "Transaction Rules",
        "Transactions without a `hint`",
    ),
    LineRule(
        "all-peer-to-peer-enabled",
        "MEDIUM",
        rx(r"\.setAllPeerToPeerEnabled\(\s*true\s*\)", 0),
        "setAllPeerToPeerEnabled(true) also enables Wi-Fi Aware, which makes "
        "updateTransportConfig() throw on Node.js on macOS; use setAvailablePeerToPeerEnabled(true)",
        "sdk-setup",
        "Transports and Presence in JavaScript",
        "`setAllPeerToPeerEnabled(true)` on Node.js on macOS",
        languages=("js",),
    ),
    LineRule(
        "mutated-document-ids-without-v2",
        "MEDIUM",
        rx(r"\.mutatedDocumentIDs\(\)", 0),
        "JavaScript has no mutatedDocumentIDs(), so the call throws a TypeError; call "
        "mutatedDocumentIDsV2() once and keep the array it returns",
        "query-sync",
        "Query results in JavaScript",
        "`result.mutatedDocumentIDs()` (it does not exist in JavaScript",
        languages=("js",),
    ),
    LineRule(
        "logout-cleanup-not-awaited",
        "MEDIUM",
        rx(r"\.auth\.logout\(\s*(?:async\b|function\b|\(?\s*[\w$]*\s*\)?\s*=>)", 0),
        "logout() calls its cleanup function without awaiting it, so async work in it finishes "
        "after logout() resolves and a rejection in it is unhandled; await ditto.auth.logout(), "
        "then remove local data",
        "sdk-setup",
        "Authentication in JavaScript",
        "An `async` cleanup passed to `ditto.auth.logout(cleanup)`",
        languages=("js",),
    ),
    LineRule(
        "observer-is-stopped-inverted",
        "MEDIUM",
        rx(r"\.isStopped\b", 0),
        "Observer.isStopped is inverted in SDK 5.0.3 to 5.2.0 (true while the observer is "
        "active, false after stop()); keep your own flag instead",
        "sdk-setup",
        "Closing Ditto in JavaScript",
        "`isStopped` of the observers that `presence.observe()`",
        languages=("js",),
    ),
    LineRule(
        "version-string-compare",
        "MEDIUM",
        rx(r"Ditto\.version\s*(==|!=)|Ditto\.version\.(startsWith|compareTo|split)\(", 0),
        "Ditto.version in Flutter is a string such as iOSF5.2.0_f6bdf023fa, also on macOS; "
        "extract the x.y.z part before you compare it",
        "sdk-setup",
        "Behavior Specific to the Flutter SDK",
        "`Ditto.version` compared as a string",
        languages=("dart",),
    ),
    LineRule(
        "open-sync",
        "MEDIUM",
        rx(r"\bDitto\.openSync\(", 0),
        "Ditto.openSync blocks the calling thread until the store is open; prefer "
        "await Ditto.open, and never call openSync on the main thread",
        "sdk-setup",
        "Opening Ditto in Swift",
        "`Ditto.openSync` on the main thread",
        languages=("swift",),
    ),
    LineRule(
        "uppercase-uuid",
        "MEDIUM",
        rx(r"\bUUID\(\)\.uuidString\b(?!\.lowercased\(\))", 0),
        "UUID().uuidString is uppercase, while other platforms produce lowercase UUIDs; "
        "lowercase IDs in one helper",
        "data-modeling",
        "IDs and Timestamps in Swift",
        "`UUID().uuidString` as a document ID without `lowercased()`",
        languages=("swift",),
    ),
]


def is_comment(line: str) -> bool:
    stripped = line.lstrip()
    return stripped.startswith(("//", "/*", "*", "#!"))


def code_part(line: str) -> str:
    """The line without a trailing // or /* */ comment (one that follows whitespace, so
    that a URL in a string survives)."""
    return re.sub(r"\s//.*$|\s/\*.*\*/\s*$", "", line).rstrip()


# A statement split across lines is joined into one logical statement when it is a run of
# string literals: adjacent literals (Dart), literals joined by + at a line break, or a
# multi-line string (triple quotes, or a JavaScript template literal), whose text starts
# with a DQL statement.
# A string whose text starts with one of these is a DQL statement.
STATEMENT_START = re.compile(
    r"\s*(?:(?:EXPLAIN|PROFILE|ADVISE)\s+)?(?:SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|EVICT\s+FROM"
    r"|ALTER\s+SYSTEM|CREATE\s+INDEX|DROP\s+INDEX)\b")
MAX_STATEMENT_LINES = 30
ENDS_WITH_LITERAL = re.compile(r"['\"`]\s*(?:(?<!\+)\+)?$")
STARTS_WITH_LITERAL = re.compile(r"^\+?\s*['\"`]")
LITERAL_JOINER = re.compile(r"\s*\+?\s*")


def opens_string(line: str, language: str) -> Optional[str]:
    """The delimiter of a multi-line string that the line opens and does not close."""
    if language == "js":
        return "`" if (line.count("`") - line.count("\\`")) % 2 else None
    for delimiter in ('"""', "'''"):
        if line.count(delimiter) % 2:
            return delimiter
    return None


def continues_literal(previous: str, following: str, language: str) -> bool:
    """Whether a string literal run goes on from the code of one line to the next line."""
    following = following.strip()
    plus = (previous.endswith("+") and not previous.endswith("++")) or following.startswith("+")
    previous_literal = bool(ENDS_WITH_LITERAL.search(previous))
    following_literal = bool(STARTS_WITH_LITERAL.search(following))
    if plus:
        return previous_literal or following_literal
    return language == "dart" and previous_literal and following_literal


def string_spans(lines: List[str], language: str) -> Dict[int, int]:
    """The first and last line index of each multi-line string, paired in one pass over the
    file so that a closing delimiter is never taken for an opening one."""
    spans = {}
    index = 0
    while index < len(lines):
        delimiter = None if is_comment(lines[index]) else opens_string(lines[index], language)
        if delimiter:
            closing = next((number for number in range(index + 1, len(lines))
                            if opens_string(lines[number], language) == delimiter), None)
            if closing is None:
                break
            spans[index] = closing
            index = closing
        index += 1
    return spans


def statement_end_line(lines: List[str], start: int, language: str, spans: Dict[int, int]) -> int:
    """The last line of the logical statement that starts on lines[start]."""
    end = start
    while end - start < MAX_STATEMENT_LINES:
        if end in spans:
            if spans[end] - start >= MAX_STATEMENT_LINES:
                break
            end = spans[end]
        if (end + 1 < len(lines) and not is_comment(lines[end + 1])
                and continues_literal(code_part(lines[end]), lines[end + 1], language)):
            end += 1
            continue
        break
    return end


def merge_literals(text: str) -> str:
    """The text with each run of adjacent string literals, or literals joined by +, as one
    literal, so that a statement split into several literals reads as one."""
    runs: List[List[re.Match]] = []
    for match in LITERAL.finditer(text):
        if runs and LITERAL_JOINER.fullmatch(text, runs[-1][-1].end(), match.start()):
            runs[-1].append(match)
        else:
            runs.append([match])
    pieces = []
    position = 0
    for run in runs:
        quote = run[0].group()[0]
        pieces.append(text[position:run[0].start()])
        pieces.append(quote + "".join(match.group()[1:-1] for match in run) + quote)
        position = run[-1].end()
    pieces.append(text[position:])
    return "".join(pieces)


def logical_statements(lines: List[str], language: str) -> Iterable[Tuple[int, str, str]]:
    """(line index, text to match, code to show) for each line, or for each statement whose
    string literals span several lines."""
    spans = string_spans(lines, language)
    # The lines inside or closing a multi-line string never start a statement.
    inside = {number for first, last in spans.items() for number in range(first + 1, last + 1)}
    index = 0
    while index < len(lines):
        line = lines[index]
        end = index
        if not is_comment(line) and index not in inside:
            end = statement_end_line(lines, index, language, spans)
        if end > index:
            joined = " ".join(code_part(text).strip() for text in lines[index:end + 1])
            merged = merge_literals(joined)
            if any(STATEMENT_START.match(literal.group(), 1) for literal in LITERAL.finditer(merged)):
                yield index, merged, joined[:200]
                index = end + 1
                continue
        yield index, line, line.strip()
        index += 1


def scan_lines(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    for index, text, code in logical_statements(lines, language):
        if is_comment(lines[index]):
            continue
        for rule in LINE_RULES:
            pattern = rule.pattern_for(language)
            if pattern is None:
                continue
            if rule.requires_dql and not DQL_KEYWORDS.search(text):
                continue
            if not pattern.search(text):
                continue
            if rule.unless and rule.unless.search(text):
                continue
            if rule.refine and not rule.refine(text):
                continue
            yield Finding(path, index + 1, rule.severity, rule.rule, rule.message,
                          rule.skill, rule.guide_for(language), code)


def window(lines: List[str], start: int, size: int) -> str:
    return "\n".join(lines[start:start + size])


def block(lines: List[str], start: int, limit: int = 80) -> List[str]:
    """The lines from `start` through the one that closes the first brace opened there or later."""
    depth = 0
    opened = False
    body = []
    for line in lines[start:start + limit]:
        body.append(line)
        depth += line.count("{") - line.count("}")
        opened = opened or "{" in line
        if opened and depth <= 0:
            break
    return body


SUBSCRIPTION_CALL = re.compile(r"registerSubscription\s*\(")
SUBSCRIPTION_REJECTED = re.compile(
    r"\b(ORDER\s+BY|LIMIT|JOIN|GROUP\s+BY|DISTINCT|USE\s+IDS)\b|SELECT\s+(?!\*)",
    re.IGNORECASE,
)
# Filters that keep documents from reaching the device: != and NOT IN skip documents
# without the field, and clock() is evaluated by the sending device only when it writes.
SUBSCRIPTION_MISSES = re.compile(r"!=|\bNOT\s+IN\b|\bclock\s*\(")
STRING_LITERAL = re.compile(r"'([^'\\]*(?:\\.[^'\\]*)*)'|\"([^\"\\]*(?:\\.[^\"\\]*)*)\"|`([^`]*)`")


def scan_subscriptions(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Subscriptions accept only SELECT * FROM c [WHERE ...]."""
    for index, line in enumerate(lines):
        if is_comment(line) or not SUBSCRIPTION_CALL.search(line):
            continue
        # Collect the string literals of the query argument: from the call up to
        # the arguments parameter or the closing parenthesis (at most 5 lines).
        text = []
        depth = 0
        for offset, candidate in enumerate(lines[index:index + 5]):
            if offset == 0:
                candidate = candidate[SUBSCRIPTION_CALL.search(candidate).start():]
            arguments = re.search(r"arguments\s*:", candidate)
            if arguments:
                candidate = candidate[:arguments.start()]
            for match in STRING_LITERAL.finditer(candidate):
                text.append(next(group for group in match.groups() if group is not None))
            depth += candidate.count("(") - candidate.count(")")
            if arguments or depth <= 0:
                break
        query = " ".join(text)
        if query and SUBSCRIPTION_REJECTED.search(query):
            yield report("subscription-rejected-feature", language, path, index + 1,
                         "Subscriptions accept only SELECT * FROM c [WHERE ...]; projections, "
                         "ORDER BY, LIMIT, JOIN, GROUP BY, DISTINCT, and USE IDS are rejected "
                         "or degrade sync", query.strip()[:160])
        if SUBSCRIPTION_MISSES.search(query):
            yield report("subscription-filter-misses-documents", language, path, index + 1,
                         "A subscription filter with != or NOT IN never brings the documents that "
                         "lack the field, and one with clock() does not send documents that enter "
                         "the time window later; filter by fields that every document has, and "
                         "pass a time boundary as a parameter", query.strip()[:160])


OBSERVER_CALL = re.compile(r"registerObserver(V2|WithSignalNext)?\s*\(")


def scan_observers(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Flutter: onChange without consuming the changes stream retains every result."""
    if language != "dart":
        return
    for index, line in enumerate(lines):
        if is_comment(line) or not OBSERVER_CALL.search(line):
            continue
        has_on_change = re.search(r"\bonChange\s*:", window(lines, index, 8))
        # Look for `.changes` until the enclosing top-level declaration ends.
        scope = []
        for following in lines[index:index + 40]:
            if scope and re.match(r"[^\s}/)]", following):
                break
            scope.append(following)
        consumes_changes = re.search(r"\.changes\b", "\n".join(scope))
        if has_on_change and not consumes_changes:
            yield report("observer-onchange-only", language, path, index + 1,
                         "Observer registered with onChange and no `changes` stream consumed "
                         "nearby; unconsumed results stay in memory (SDK 5.1.0 and 5.2.0, also "
                         "with registerObserverV2 and registerObserverWithSignalNext)", line.strip())


# A transaction callback (Dart, JavaScript) or trailing closure (Kotlin, Swift).
TRANSACTION_CALL = re.compile(r"\.transaction\s*[({]")
INSIDE_TRANSACTION = re.compile(r"\.store\.execute\s*\(|\.transaction\s*[({]")


def scan_transactions(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """store.execute or a nested transaction inside a transaction callback."""
    for index, line in enumerate(lines):
        if is_comment(line) or not TRANSACTION_CALL.search(line):
            continue
        for offset, body in enumerate(block(lines, index)[1:], start=1):
            if not is_comment(body) and INSIDE_TRANSACTION.search(body):
                yield report("execute-inside-transaction", language, path, index + offset + 1,
                             "ditto.store.execute inside a transaction (throws in Flutter; its "
                             "writes never complete in JavaScript, Kotlin, and Swift) or a nested "
                             "read-write transaction (waits for the outer one forever); use the "
                             "transaction's own execute", body.strip())


KOTLIN_QUERY_CALL = re.compile(r"\.(execute|observe)\s*\(")
# A mapping function that returns the result or its items unchanged.
RESULT_RETURNED = re.compile(r"\{\s*(?:(\w+)\s*->\s*\1|it)(?:\.items)?\s*\}")


def scan_kotlin_results(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Kotlin: a query result that leaves the mapping function of execute or observe."""
    if language != "kotlin":
        return
    for index, line in enumerate(lines):
        if is_comment(line) or not KOTLIN_QUERY_CALL.search(line):
            continue
        text = "\n".join(block(lines, index, 12))
        if RESULT_RETURNED.search(text[KOTLIN_QUERY_CALL.search(text).start():]):
            yield report("result-leaves-handler", language, path, index + 1,
                         "The query result leaves the mapping function, which closes it; reading "
                         "its items afterwards throws. Convert the items inside the function", line.strip())


REGISTRATION = re.compile(
    r"^\s*(?P<discard>_\s*=\s*)?(try[?!]?\s+)?(await\s+)?[\w.?!]*\b"
    r"(?P<call>store\.registerObserver\w*|sync\.registerSubscription)\s*\(")
# A block whose last expression is its value: a lambda passed to map, let, and the like,
# and in Swift, a function with a return type or a computed property (implicit return).
VALUE_LAMBDA = re.compile(
    r"(\.(map\w*|flatMap\w*|compactMap|associate\w*|let|run|also|apply|with)|\blazy|=)\s*\{"
    r"\s*(?:\[[^\]]*\]\s*)?(?:[\w\s,:()<>?]*(?:->|\bin))?\s*$"
    r"|->\s*[^{}]+\{\s*$|\bvar\s+\w+\s*:\s*[^={}]+\{\s*$")
# The opening of a lambda with parameters: `{ id ->` (Kotlin) or `{ [weak self] id in` (Swift).
LAMBDA_OPENING = re.compile(r"\{\s*(?:\[[^\]]*\]\s*)?[\w\s,:()<>?]*(?:->|\bin)\s*$")
# The end of a line after which the expression goes on: an operator, an opening bracket,
# a separator, or a keyword that takes an expression.
CONTINUATION = re.compile(
    r"(?:[-+*/%=&|^~:,.(\[]|\s[?<>]|=>|->|\b(?:return|try|await|throw|in|yield)[?!]?)\s*$")


def starts_statement(lines: List[str], index: int) -> bool:
    """Whether lines[index] starts a statement whose value nothing keeps: a line break is a
    statement boundary unless the previous line ends with a continuation or the line
    continues a call chain."""
    if lines[index].lstrip().startswith((".", "?.")):
        return False
    previous = previous_code_line(lines, index)
    if previous is None:
        return True
    previous = code_part(previous)
    if VALUE_LAMBDA.search(previous):
        return False
    if previous.endswith((";", "{", "}")) or LAMBDA_OPENING.search(previous):
        return True
    return not CONTINUATION.search(previous)


# A call chained to the registration that keeps the handle.
KEEPING_CHAIN = re.compile(r"\.(also|let|apply|run|store|addTo|disposed)\b")


def previous_code_line(lines: List[str], index: int) -> Optional[str]:
    for line in reversed(lines[:index]):
        stripped = line.strip()
        if stripped and not is_comment(stripped):
            return stripped
    return None


def statement_end(lines: List[str], index: int) -> str:
    """What follows the call that starts on lines[index], once its parentheses close."""
    depth = 0
    started = False
    for line in lines[index:index + 40]:
        for position, character in enumerate(line):
            if character == "(":
                depth += 1
                started = True
            elif character == ")":
                depth -= 1
                if started and depth == 0:
                    return line[position + 1:].strip()
    return ""


def scan_registrations(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """An observer or subscription whose handle the code does not keep."""
    for index, line in enumerate(lines):
        match = REGISTRATION.match(line)
        if not match:
            continue
        if not match.group("discard"):
            if not starts_statement(lines, index):
                continue
            rest = statement_end(lines, index)
            if rest.startswith((",", ")", "]")) or KEEPING_CHAIN.match(rest):
                continue
        if match.group("call").startswith("store"):
            yield report("discarded-observer", language, path, index + 1,
                         "The observer that registerObserver returns is discarded, so nothing "
                         "can release it; it keeps running until Ditto shuts down", line.strip())
        else:
            yield report("discarded-subscription", language, path, index + 1,
                         "The subscription that registerSubscription returns is discarded, so "
                         "nothing can cancel it; it keeps syncing until Ditto shuts down", line.strip())


SWIFT_TASK = re.compile(r"\bTask(\.detached)?\s*(\([^)]*\))?\s*\{")


def scan_swift_observer_tasks(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Swift: an observer handler that starts a Task and never calls signalNext."""
    if language != "swift":
        return
    for index, line in enumerate(lines):
        if is_comment(line) or not OBSERVER_CALL.search(line):
            continue
        handler = block(lines, index, 60)
        if "signalNext" in "\n".join(handler):
            continue
        # A Task that awaits work; one that only hands values to the main actor is fine.
        awaits = any(re.search(r"\bawait\b", "\n".join(block(handler, offset, 40)))
                     for offset, candidate in enumerate(handler) if SWIFT_TASK.search(candidate))
        if awaits:
            yield report("observer-task-without-backpressure", language, path, index + 1,
                         "The observer handler starts a Task and returns, so the next result does "
                         "not wait for the work; use handlerWithSignalNext and call signalNext "
                         "when the Task is done", line.strip())


LOOP = re.compile(r"^\s*for\b|\.(forEach|forEachIndexed|map|mapIndexed)\s*\{|\brepeat\s*\(")
CONCURRENT_TASK = re.compile(
    r"\b(launch|async|addTask)\s*(\([^)]*\))?\s*\{|\bTask(\.detached)?\s*(\([^)]*\))?\s*\{")
STORE_EXECUTE = re.compile(r"\.store\.execute\s*\(")


def scan_concurrent_writes(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Kotlin and Swift: a coroutine or Task per write, started in a loop."""
    if language not in ("kotlin", "swift"):
        return
    for index, line in enumerate(lines):
        if is_comment(line) or not LOOP.search(line):
            continue
        loop = block(lines, index)
        for offset, body in enumerate(loop[1:], start=1):
            if is_comment(body) or not CONCURRENT_TASK.search(body):
                continue
            if STORE_EXECUTE.search("\n".join(block(lines, index + offset, 40))):
                yield report("concurrent-writes-in-loop", language, path, index + offset + 1,
                             "A coroutine or Task per write: while a transaction is open, each "
                             "waiting write can hold a thread, and enough of them stop the app; "
                             "write in one statement, one transaction, or one after another", body.strip())


def scan_lifecycle(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """ditto.close() when the app moves to the background."""
    if language != "dart":
        return
    for index, line in enumerate(lines):
        if is_comment(line) or "AppLifecycleState.paused" not in line:
            continue
        if re.search(r"\.close\(\)", window(lines, index, 8)):
            yield report("close-on-background", language, path, index + 1,
                         "ditto.close() on AppLifecycleState.paused makes every later call "
                         "throw; stop sync instead and keep the instance open", line.strip())


UI_CLASS = {
    "kotlin": re.compile(
        r"^\s*(?:(?:open|abstract|internal|private|public)\s+)*class\s+\w+[^{]*:\s*"
        r"(?:AppCompatActivity|ComponentActivity|FragmentActivity|Activity|Fragment|DialogFragment)"
        r"\s*\(|@Composable\b"),
    "dart": re.compile(r"\bextends\s+(?:State<|StatelessWidget\b|StatefulWidget\b)"),
    "swift": re.compile(r"\b(?:struct|class)\s+\w+\s*:[^{]*\b(?:View|UIViewController)\b"),
}
OPEN_CALL = {
    "js": re.compile(r"\bDitto\.open(?:Sync)?\("),
    "kotlin": re.compile(r"\bDittoFactory\.create\("),
    "dart": re.compile(r"\bDitto\.open(?:Sync)?\("),
    "swift": re.compile(r"\bDitto\.open(?:Sync)?\("),
}


def scan_ditto_in_ui(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Ditto opened in a file that defines a screen (Activity, composable, widget, view)."""
    if language not in UI_CLASS:
        return
    code = [line for line in lines if not is_comment(line)]
    if not any(UI_CLASS[language].search(line) for line in code):
        return
    for index, line in enumerate(lines):
        if not is_comment(line) and OPEN_CALL[language].search(line):
            yield report("ditto-in-ui", language, path, index + 1,
                         "Ditto opened in a file that defines a screen: the screen can be created "
                         "again, and a second open of the same directory fails or never completes; "
                         "open one instance at app start and share it", line.strip())


EXPIRATION_HANDLER = re.compile(r"\bexpirationHandler\s*=\s*\{")
CAUGHT = re.compile(r"\btry\b|\brunCatching\b")
THROWS = re.compile(r"!!|\bthrow\b|\berror\(|\b(?:require|check)(?:NotNull)?\(")
MAIN_LAUNCH = re.compile(
    r"\b(?:lifecycleScope|viewModelScope|MainScope\(\))\.launch\s*(?:\(\s*\))?\s*\{"
    r"|\blaunch\s*\(\s*Dispatchers\.Main(?:\.immediate)?\s*\)\s*\{"
    r"|withContext\(\s*Dispatchers\.Main(?:\.immediate)?\s*\)\s*\{")
OFF_MAIN = re.compile(r"withContext\(\s*Dispatchers\.(?:IO|Default)\b")
EXECUTE = re.compile(r"\.store\.execute(?:Raw)?\s*\(")


def scan_kotlin_handlers(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Kotlin: login without try in the expiration handler, throwing observer handlers,
    and execute on the main dispatcher."""
    if language != "kotlin":
        return
    for index, line in enumerate(lines):
        if is_comment(line):
            continue
        if EXPIRATION_HANDLER.search(line):
            text = "\n".join(block(lines, index))
            if ".login(" in text and not CAUGHT.search(text):
                yield report("login-error-unreported", language, path, index + 1,
                             "login() throws when the token is rejected or the server is "
                             "unreachable, and an exception that leaves the expiration handler is "
                             "only logged; catch it inside the handler and report it", line.strip())
        if re.search(r"\.registerObserver\s*\(", line):
            body = block(lines, index)
            if not CAUGHT.search("\n".join(body)):
                for offset, candidate in enumerate(body):
                    if not is_comment(candidate) and THROWS.search(candidate):
                        yield report("throwing-observer-handler", language, path, index + offset + 1,
                                     "An exception that leaves a registerObserver handler closes the "
                                     "observer, and the SDK only logs it; catch errors inside the handler",
                                     candidate.strip())
                        break
        match = MAIN_LAUNCH.search(line)
        if match:
            body = block(lines, index)
            body[0] = line[match.end():]
            for offset, candidate in enumerate(body):
                if is_comment(candidate) or OFF_MAIN.search(candidate):
                    if OFF_MAIN.search(candidate):
                        break
                    continue
                if EXECUTE.search(candidate):
                    yield report("execute-on-main", language, path, index + offset + 1,
                                 "store.execute blocks the thread of the coroutine that calls it, so "
                                 "on the main dispatcher it freezes the UI; call it inside "
                                 "withContext(Dispatchers.IO)",
                                 lines[index + offset].strip())
                    break


DART_TRANSACTION = re.compile(r"\.transaction(?:<[^>]*>)?\(")
DITTO_CLOSE = re.compile(r"\b\w*[dD]itto\w*[!?]?\.close\(\)")
STARTED_WORK = re.compile(
    r"\.registerObserver(?:V2|WithSignalNext)?\(|\.changes\.listen\(|\bTimer(?:\.periodic)?\("
    r"|Future(?:<[^>]*>)?\.delayed\(|\bunawaited\(|\bscheduleMicrotask\(")


def scan_dart_transactions(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Dart: close() or work that outlives the callback, inside a transaction callback."""
    if language != "dart":
        return
    for index, line in enumerate(lines):
        if is_comment(line) or not DART_TRANSACTION.search(line):
            continue
        body = block(lines, index)
        for offset, candidate in enumerate(body[1:], start=1):
            if not is_comment(candidate) and DITTO_CLOSE.search(candidate):
                yield report("close-inside-transaction", language, path, index + offset + 1,
                             "close() while a transaction is open stops the Dart isolate (the UI "
                             "isolate in an app); let the transaction end first", candidate.strip())
                break
        for offset, candidate in enumerate(body[1:], start=1):
            if not is_comment(candidate) and STARTED_WORK.search(candidate):
                yield report("work-started-in-transaction", language, path, index + offset + 1,
                             "Timers, listeners, and other work started inside a transaction "
                             "callback keep its zone, so their later ditto.store.execute calls throw "
                             "after the commit; start them outside the callback", candidate.strip())
                break


SIGNAL_NEXT_HANDLER = {
    "dart": re.compile(r"\.changes\.listen\(\s*\(\w*\)\s*async|onChange:\s*\(\w+,\s*\w+\)\s*async"),
    "swift": re.compile(r"\{\s*\w+\s*,\s*signalNext\s+in\b"),
}
MAY_THROW = {"dart": re.compile(r"\bawait\b"), "swift": re.compile(r"\btry\b(?![?!])")}
HANDLES_ERRORS = {
    "dart": re.compile(r"\bfinally\b|\bcatch\b|\bcatchError\b"),
    "swift": re.compile(r"\bdefer\b|\bcatch\b"),
}


def scan_signal_next(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """signalNext() after work that can throw, without finally or defer."""
    if language not in SIGNAL_NEXT_HANDLER:
        return
    for index, line in enumerate(lines):
        if is_comment(line) or not SIGNAL_NEXT_HANDLER[language].search(line):
            continue
        body = block(lines, index)
        text = "\n".join(body)
        if not MAY_THROW[language].search(text) or HANDLES_ERRORS[language].search(text):
            continue
        for offset, candidate in enumerate(body):
            if not is_comment(candidate) and re.search(r"signalNext\(\)", candidate):
                yield report("signal-next-skipped-on-error", language, path, index + offset + 1,
                             "signalNext() is skipped when the work before it throws, and the "
                             "observer then stops delivering results; call it in finally (Dart) or "
                             "defer (Swift)", candidate.strip())
                break


PLAIN_OBSERVER = re.compile(r"(\w+)\s*=\s*[\w.!]*\.registerObserver\(")
AWAIT_FOR_CHANGES = re.compile(r"await\s+for\s*\(.*\bin\s+(\w+)\.changes\)")


def scan_await_for(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """Dart: await for over the changes of a registerObserver observer."""
    if language != "dart":
        return
    observers = {match.group(1) for line in lines if not is_comment(line)
                 for match in [PLAIN_OBSERVER.search(line)] if match}
    for index, line in enumerate(lines):
        match = AWAIT_FOR_CHANGES.search(line)
        if match and not is_comment(line) and match.group(1) in observers:
            yield report("await-for-without-backpressure", language, path, index + 1,
                         "await for over the changes of a registerObserver observer handles every "
                         "queued result in turn, so the latest state arrives late; use "
                         "registerObserverV2 or registerObserverWithSignalNext", line.strip())


def call_span(lines: List[str], index: int, position: int, limit: int = 80) -> List[Tuple[int, str]]:
    """The (line index, text) pieces of the call whose "(" is at lines[index][position]."""
    depth = 0
    pieces = []
    for number in range(index, min(len(lines), index + limit)):
        line = lines[number]
        start = position if number == index else 0
        for column in range(start, len(line)):
            if line[column] == "(":
                depth += 1
            elif line[column] == ")":
                depth -= 1
                if depth == 0:
                    pieces.append((number, line[start:column + 1]))
                    return pieces
        pieces.append((number, line[start:]))
    return pieces


def span_text(pieces: List[Tuple[int, str]]) -> str:
    return "\n".join(text for _, text in pieces)


def span_code(pieces: List[Tuple[int, str]], lines: List[str]) -> str:
    """The span without comment lines and trailing // comments."""
    return "\n".join(re.sub(r"\s//.*$", "", text) for number, text in pieces
                     if not is_comment(lines[number]))


# The first function expression in a call: its async keyword, its parameters, and the
# position where its body starts.
JS_FUNCTION = re.compile(
    r"(?P<async>async\s+)?(?:function\b\s*[\w$]*\s*\((?P<a>[^)]*)\)|\((?P<b>[^)]*)\)\s*=>|(?P<c>[\w$]+)\s*=>)")


def js_handler(call: str) -> Optional[Tuple[bool, List[str], str]]:
    """(is async, parameter names, body) of the first function passed in a call's text."""
    match = JS_FUNCTION.search(call, 1)
    if not match:
        return None
    parameters = match.group("a") or match.group("b") or match.group("c") or ""
    names = [name.strip() for name in parameters.split(",") if name.strip()]
    return bool(match.group("async")), names, call[match.end():]


JS_REGISTRATION = re.compile(
    r"\.(registerObserver(?:WithSignalNext)?|registerSubscription|fetchAttachment)\s*\(|"
    r"\.presence\.observe\s*\(|\.auth\.observeStatus\s*\(")
JS_EFFECT = re.compile(r"\buse(?:Layout|Insertion)?Effect\s*\(")
JS_COMPONENT = re.compile(
    r"^\s*(?:export\s+)?(?:default\s+)?function\s+[A-Z]\w*\s*\("
    r"|^\s*(?:export\s+)?const\s+[A-Z]\w*\s*=\s*(?:\([^)]*\)|[\w$]+)\s*=>")
RETURNS_JSX = re.compile(r"return\s*\(?\s*<|=>\s*\(?\s*<")
JS_VALUE = re.compile(
    r"[\w$]\s*:\s*(?:new\s+(?:Date|Set)\s*\((?:[^()]|\([^()]*\))*\)(?!\s*\.)|new\s+(?:Date|Set)\b(?!\s*\()"
    r"|NaN\b|-?Infinity\b|Number\.(?:NaN|POSITIVE_INFINITY|NEGATIVE_INFINITY)\b)")
# What a file needs for its reads to have a deadline. In Kotlin, a timeout around
# store.execute does not end a stuck read (the call blocks its thread), so the read has to
# run in its own coroutine that the timeout awaits.
DEADLINE = {
    "js": [re.compile(r"\bPromise\.race\(")],
    "kotlin": [re.compile(r"\bwithTimeout\w*\("), re.compile(r"\.async\s*(?:\([^)]*\))?\s*\{")],
    "swift": [re.compile(r"\bwithDeadline\b|\bwithThrowingTaskGroup\b")],
}


def calls(lines: List[str], pattern: re.Pattern) -> Iterable[Tuple[int, List[Tuple[int, str]]]]:
    """Each call that pattern finds, ending in "(", with its span."""
    for index, line in enumerate(lines):
        if is_comment(line):
            continue
        for match in pattern.finditer(line):
            yield index, call_span(lines, index, match.end() - 1)


def js_components(lines: List[str]) -> Iterable[Tuple[int, int]]:
    """(first, last) line indexes of each function component that returns JSX."""
    for index, line in enumerate(lines):
        if is_comment(line) or not JS_COMPONENT.search(line):
            continue
        body = block(lines, index)
        if len(body) == 1 and "(" in line and not line.rstrip().endswith(("}", ");", ")")):
            body = [text for _, text in call_span(lines, index, line.rindex("("))]
        if any(RETURNS_JSX.search(text) for text in body):
            yield index, index + len(body) - 1


def scan_javascript(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """JavaScript rules that need the span of a call, a handler, or a component."""
    if language != "js":
        return
    for index, span in calls(lines, re.compile(r"\.transaction\s*\(")):
        if not re.search(r"\bhint\s*:", span_text(span)):
            yield report("transaction-without-hint", language, path, index + 1,
                         "Transaction without a hint in its options; long transactions are "
                         "logged by hint", lines[index].strip())
    for index, span in calls(lines, re.compile(
            r"\.(?:execute|registerObserver(?:WithSignalNext)?|registerSubscription)\s*\(")):
        for number, text in span:
            if not is_comment(lines[number]) and JS_VALUE.search(text):
                yield report("unconvertible-argument", language, path, number + 1,
                             "A Date or a Set is stored as an empty object {} without an error, "
                             "and NaN and Infinity are rejected; pass an ISO 8601 UTC string or "
                             "epoch milliseconds, an array, and finite numbers",
                             lines[number].strip())
                break
    for index, span in calls(lines, re.compile(r"\.registerObserver\s*\(")):
        handler = js_handler(span_text(span))
        if handler and handler[0]:
            yield report("observer-task-without-backpressure", language, path, index + 1,
                         "An async registerObserver handler returns at its first await, so calls "
                         "overlap, an older call can finish last, and a rejection is unhandled (it "
                         "ends a Node.js process); keep the handler synchronous, or use "
                         "registerObserverWithSignalNext and call signalNext() in finally",
                         lines[index].strip())
    for index, span in calls(lines, re.compile(r"\.registerObserverWithSignalNext\s*\(")):
        handler = js_handler(span_text(span))
        if not handler:
            continue
        _, names, body = handler
        if len(names) < 2 or not re.search(rf"\b{re.escape(names[1])}\b", body):
            yield report("missing-signal-next", language, path, index + 1,
                         "registerObserverWithSignalNext delivers the next result only after "
                         "signalNext() is called, and this handler never calls it, so the observer "
                         "stops after the first result; call signalNext() when the work is done",
                         lines[index].strip())
        elif (re.search(r"\bawait\b", body) and re.search(rf"\b{re.escape(names[1])}\s*\(\s*\)", body)
              and not re.search(r"\bfinally\b|\bcatch\b", body)):
            yield report("signal-next-skipped-on-error", language, path, index + 1,
                         "signalNext() is skipped when the work before it throws, and the "
                         "observer then stops delivering results; call it in finally", lines[index].strip())
    for index, line in enumerate(lines):
        match = re.search(r"\.forEach\(\s*async\b", line)
        if match and not is_comment(line):
            if re.search(r"\.execute\s*\(", span_text(call_span(lines, index, line.index("(", match.start())))):
                yield report("concurrent-writes-in-loop", language, path, index + 1,
                             "forEach does not wait for an async callback, so its statements run "
                             "unawaited: inside a transaction they are not applied, their rejections "
                             "are unhandled, and the commit can fail; await each statement in a "
                             "for...of loop, or use Promise.all", line.strip())
    for index, span in calls(lines, re.compile(r"\.setExpirationHandler\s*\(")):
        text = span_code(span, lines)
        throws = re.search(r"\bthrow\s+(?:new\b|[\w$])", text)
        if ".login(" in text and (throws or not re.search(r"\.error\b", text)):
            yield report("login-error-unreported", language, path, index + 1,
                         "login() reports a rejected token or an unreachable server in "
                         "result.error instead of throwing, and an error thrown from the "
                         "expiration handler is only logged; check result.error and report it "
                         "inside the handler", lines[index].strip(),
                         variant="throws" if throws else "")
    for index, span in calls(lines, JS_EFFECT):
        text = span_text(span)
        if JS_REGISTRATION.search(text) and not re.search(r"\breturn\b", text):
            yield report("effect-without-cleanup", language, path, index + 1,
                         "The effect registers an observer, subscription, or fetch but returns no "
                         "cleanup, so it keeps running after unmount (and twice under Strict "
                         "Mode); return a cleanup that cancels or stops it", lines[index].strip())
    for first, last in js_components(lines):
        in_effects = set()
        for index, span in calls(lines[:last + 1], JS_EFFECT):
            if index >= first:
                in_effects.update(number for number, _ in span)
        for number in range(first + 1, last + 1):
            line = lines[number]
            if is_comment(line):
                continue
            if JS_REGISTRATION.search(line) and number not in in_effects:
                yield report("register-in-render", language, path, number + 1,
                             "A component body runs on every render, so this registers a new "
                             "observer, subscription, or attachment fetch each time and never "
                             "releases it; register in useEffect and release it in its cleanup", line.strip())
            if OPEN_CALL["js"].search(line):
                yield report("ditto-in-ui", language, path, number + 1,
                             "Ditto opened in a component: it opens again whenever the component "
                             "mounts, and a second open of the same directory fails; open one "
                             "instance at app start and share it", line.strip())


def scan_data_sync_info_reads(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """A read of system:data_sync_info in a file without a deadline helper."""
    if language not in DEADLINE:
        return
    text = "\n".join(line for line in lines if not is_comment(line))
    if all(pattern.search(text) for pattern in DEADLINE[language]):
        return
    for index, span in calls(lines, re.compile(r"\.execute\s*\(")):
        if "system:data_sync_info" in span_text(span):
            yield report("unbounded-data-sync-info-read", language, path, index + 1,
                         "A read of system:data_sync_info can stop responding on a device "
                         "connected to another peer (in testing: JavaScript and Swift on 5.1.0 and "
                         "5.2.0, Kotlin on 5.1.0); give every read a deadline and treat a missed "
                         "one as not confirmed", lines[index].strip())


FILE_SCANNERS: List[Callable[[str, str, List[str]], Iterable[Finding]]] = [
    scan_lines,
    scan_subscriptions,
    scan_observers,
    scan_transactions,
    scan_lifecycle,
    scan_registrations,
    scan_ditto_in_ui,
    scan_kotlin_handlers,
    scan_dart_transactions,
    scan_signal_next,
    scan_await_for,
    scan_javascript,
    scan_data_sync_info_reads,
    scan_kotlin_results,
    scan_swift_observer_tasks,
    scan_concurrent_writes,
]


def excluded(name: str, relative: str, patterns: Sequence[str]) -> bool:
    """Whether a file or directory name, or its path relative to the scanned directory,
    matches one of the globs."""
    return any(fnmatch.fnmatchcase(name, pattern) or fnmatch.fnmatchcase(relative, pattern)
               for pattern in patterns)


def iter_files(paths: Sequence[str], excludes: Sequence[str] = ()) -> Iterable[str]:
    """The source files under the paths; a path given here is never excluded itself."""
    patterns = [pattern.rstrip("/") for pattern in excludes]
    for root in paths:
        if os.path.isfile(root):
            yield root
            continue
        for directory, subdirectories, files in os.walk(root):
            base = os.path.relpath(directory, root).replace(os.sep, "/")
            base = "" if base == "." else base + "/"
            subdirectories[:] = sorted(
                name for name in subdirectories
                if name not in SKIPPED_DIRS and not excluded(name, base + name, patterns))
            for name in sorted(files):
                if (os.path.splitext(name)[1] in EXTENSIONS
                        and not excluded(name, base + name, SKIPPED_FILES)
                        and not excluded(name, base + name, patterns)):
                    yield os.path.join(directory, name)


SUPPRESSION = re.compile(r"ditto-scan:\s*ignore(?:\[([^\]]*)\])?")


def suppressed(finding: Finding, lines: List[str]) -> bool:
    """Whether a `ditto-scan: ignore` comment on the finding's line, or on a comment line
    directly above it, names the finding's rule or no rule."""
    candidates = [lines[finding.line - 1]]
    if finding.line >= 2 and is_comment(lines[finding.line - 2]):
        candidates.append(lines[finding.line - 2])
    for line in candidates:
        for match in SUPPRESSION.finditer(line):
            if match.group(1) is None:
                return True
            if finding.rule in (name.strip() for name in match.group(1).split(",")):
                return True
    return False


@dataclass
class ScanResult:
    findings: List[Finding]
    # Hits silenced by a `ditto-scan: ignore` comment.
    suppressed: int
    # Source files read.
    files: int


def scan_paths(paths: Sequence[str], excludes: Sequence[str] = ()) -> ScanResult:
    findings: List[Finding] = []
    silenced = 0
    files = 0
    for path in iter_files(paths, excludes):
        language = EXTENSIONS.get(os.path.splitext(path)[1])
        if language is None:
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
        except OSError as error:
            print(f"warning: cannot read {path}: {error}", file=sys.stderr)
            continue
        files += 1
        unique = {}
        for scanner in FILE_SCANNERS:
            for finding in scanner(path, language, lines):
                unique.setdefault((finding.line, finding.rule), finding)
        for finding in unique.values():
            if suppressed(finding, lines):
                silenced += 1
            else:
                findings.append(finding)
    findings.sort(key=lambda f: (SEVERITIES.index(f.severity), f.path, f.line))
    return ScanResult(findings, silenced, files)


def scan(paths: Sequence[str], excludes: Sequence[str] = ()) -> List[Finding]:
    """The findings that no suppression comment silences."""
    return scan_paths(paths, excludes).findings


NOT_JS = ("dart", "kotlin", "swift")

CONTEXT_RULES: List[ContextRule] = [
    # --- CRITICAL ---
    ContextRule("subscription-filter-misses-documents", "CRITICAL",
                "`!=`, `NOT IN`, or `clock(` in the query of a `registerSubscription(` call",
                "query-sync", "Subscription Rules",
                "Subscription filters with `!=` or `NOT IN`"),
    ContextRule("execute-inside-transaction", "CRITICAL",
                "`.store.execute(`, `.transaction(`, or `.transaction {` inside the braces of a "
                "`.transaction(` callback or a `.transaction {` trailing closure",
                "transactions-attachments", "Transaction Rules",
                "`ditto.store.execute` inside a transaction callback"),
    ContextRule("concurrent-writes-in-loop", "CRITICAL",
                "`launch {`, `async {`, `Task {`, or `addTask {` inside a `for`, `repeat`, or "
                "`forEach`/`map` loop, with `.store.execute(` in its braces (Kotlin, Swift)",
                "transactions-attachments", "Transaction Rules",
                "Many writes started in parallel, such as a coroutine or `Task` per document",
                languages=("kotlin", "swift")),
    ContextRule("concurrent-writes-in-loop", "CRITICAL",
                "`.forEach(async` with `.execute(` in its callback (JavaScript)",
                "transactions-attachments", "Transaction Rules",
                "for example with a missing `await` or `forEach(async ...)`",
                languages=("js",)),
    ContextRule("close-on-background", "CRITICAL",
                "`.close()` within 8 lines after `AppLifecycleState.paused` (Dart)",
                "sdk-setup", "Starting and Stopping Sync",
                "`ditto.close()` on `AppLifecycleState.paused`",
                languages=("dart",)),
    ContextRule("close-inside-transaction", "CRITICAL",
                "`<ditto>.close()` inside the braces of a `.transaction(` callback (Dart)",
                "transactions-attachments", "Closing Ditto in Flutter",
                "`ditto.close()` while a transaction, also a read-only one, is open",
                languages=("dart",)),
    ContextRule("result-leaves-handler", "CRITICAL",
                "An `.execute(` or `.observe(` whose mapping function returns the result or its "
                "`items` unchanged, such as `{ result -> result }` or `{ it.items }` (Kotlin)",
                "query-sync", "Query results in Kotlin",
                "A `DittoQueryResult` or its items returned from an `execute` handler",
                languages=("kotlin",)),
    ContextRule("login-error-unreported", "CRITICAL",
                "`.login(` inside an `expirationHandler = {` lambda without `try` or `runCatching` "
                "(Kotlin)",
                "sdk-setup", "Authentication in Kotlin",
                "`login()` inside the expiration handler without `try`",
                languages=("kotlin",)),
    ContextRule("login-error-unreported", "CRITICAL",
                "`.login(` inside a `setExpirationHandler(` call that throws (JavaScript)",
                "sdk-setup", "Authentication in JavaScript",
                "Throwing inside the authentication expiration handler",
                languages=("js",), variant="throws"),
    ContextRule("unconvertible-argument", "CRITICAL",
                "A property value `new Date(...)`, `new Set(...)`, `NaN`, or `Infinity` inside an "
                "`execute(`, `registerObserver(`, or `registerSubscription(` call (JavaScript)",
                "query-sync", "Arguments and value types in JavaScript",
                "`Date`, `Set`, function, or `Symbol` values in arguments",
                languages=("js",)),
    # --- HIGH ---
    ContextRule("subscription-rejected-feature", "HIGH",
                "A `registerSubscription(` call whose query uses a projection, ORDER BY, LIMIT, "
                "JOIN, GROUP BY, DISTINCT, or USE IDS",
                "query-sync", "Subscription Rules",
                "`DISTINCT`, `GROUP BY`, `JOIN`, or `USE IDS` in subscriptions"),
    ContextRule("discarded-observer", "HIGH",
                "A statement that starts with `store.registerObserver*(` (or `_ =` before it) and "
                "does not keep the returned observer: not assigned, returned, or collected",
                "query-sync", "Observer Lifecycle",
                "whose handles are dropped"),
    ContextRule("discarded-subscription", "HIGH",
                "A statement that starts with `sync.registerSubscription(` (or `_ =` before it) "
                "and does not keep the returned subscription",
                "query-sync", "Subscription Lifecycle",
                "whose handles are dropped"),
    ContextRule("signal-next-skipped-on-error", "HIGH",
                "`signalNext()` in an async `changes.listen` or `onChange` callback with `await` "
                "and no `catch`/`finally` (Dart), in a `{ result, signalNext in` handler with "
                "`try` and no `catch`/`defer` (Swift), or in a `registerObserverWithSignalNext(` "
                "handler with `await` and no `catch`/`finally` (JavaScript)",
                "performance-observability", "Backpressure (SDK 5.1+)",
                "or that call `signalNext()` only when the work succeeds",
                languages=("dart", "js", "swift")),
    ContextRule("unbounded-data-sync-info-read", "HIGH",
                "An `.execute(` of `system:data_sync_info` in a file without `Promise.race(` "
                "(JavaScript), both `withTimeout` and `.async {` (Kotlin), or `withDeadline` or a "
                "task group (Swift)",
                "query-sync", "Monitoring Sync Status",
                "Reads of `system:data_sync_info` without a deadline",
                languages=("js", "kotlin", "swift")),
    ContextRule("ditto-in-ui", "HIGH",
                "`DittoFactory.create(` (Kotlin) or `Ditto.open(` (Dart, Swift) in a file that "
                "defines an Activity, Fragment, composable, widget, SwiftUI view, or view controller",
                "sdk-setup", "One instance per persistence directory",
                None,
                languages=NOT_JS),
    ContextRule("ditto-in-ui", "HIGH",
                "`Ditto.open(` inside a component that returns JSX (JavaScript)",
                "sdk-setup", "One instance per persistence directory",
                "`Ditto.open()` in a component",
                languages=("js",)),
    ContextRule("observer-onchange-only", "HIGH",
                "`registerObserver*(` with `onChange:` and no `.changes` in the same declaration "
                "(Dart)",
                "query-sync", "Store Observers in Flutter",
                "Observers registered with `onChange` while the `changes` stream is never listened to",
                languages=("dart",)),
    ContextRule("work-started-in-transaction", "HIGH",
                "An observer, a `changes.listen(`, a `Timer`, `Future.delayed`, `unawaited(`, or "
                "`scheduleMicrotask(` inside a `.transaction(` callback (Dart)",
                "transactions-attachments", "Transactions in Flutter",
                "or other work started inside a transaction callback that calls "
                "`ditto.store.execute` later",
                languages=("dart",)),
    ContextRule("throwing-observer-handler", "HIGH",
                "`!!`, `throw`, `error(`, `require(`, or `check(` in a `registerObserver(` handler "
                "without `try` or `runCatching` (Kotlin)",
                "query-sync", "Observer lifecycle in Kotlin",
                "A `registerObserver` handler that can throw",
                languages=("kotlin",)),
    ContextRule("execute-on-main", "HIGH",
                "`.store.execute(` in a `lifecycleScope`/`viewModelScope`/`MainScope()` launch or a "
                "`Dispatchers.Main` block, before any `withContext(Dispatchers.IO)` (Kotlin)",
                "performance-observability", "Executing DQL in Kotlin",
                "`store.execute` called on the main thread",
                languages=("kotlin",)),
    ContextRule("observer-task-without-backpressure", "HIGH",
                "An `async` handler passed to `registerObserver(` (JavaScript)",
                "performance-observability", "Backpressure in JavaScript",
                "An `async` handler passed to `registerObserver` for slow work",
                languages=("js",)),
    ContextRule("observer-task-without-backpressure", "HIGH",
                "`Task {` inside the braces of a `registerObserver*(` handler that never mentions "
                "`signalNext` (Swift)",
                "performance-observability", "Backpressure in Swift",
                "or a `Task` started in the handler for every update",
                languages=("swift",)),
    ContextRule("missing-signal-next", "HIGH",
                "A `registerObserverWithSignalNext(` handler without a second parameter, or that "
                "never uses it (JavaScript)",
                "performance-observability", "Backpressure in JavaScript",
                "A `registerObserverWithSignalNext` handler that does not call `signalNext` on "
                "every path",
                languages=("js",)),
    ContextRule("effect-without-cleanup", "HIGH",
                "A `useEffect(` that registers an observer, a subscription, or a fetch and has no "
                "`return` (JavaScript)",
                "query-sync", "Observer lifecycle in JavaScript",
                "A React `useEffect` that registers an observer",
                languages=("js",)),
    ContextRule("register-in-render", "HIGH",
                "A registration in the body of a component that returns JSX, outside its effects "
                "(JavaScript)",
                "query-sync", "Store Observers in JavaScript",
                "a registration in a component body outside its effects",
                languages=("js",)),
    # --- MEDIUM ---
    ContextRule("login-error-unreported", "MEDIUM",
                "`.login(` inside a `setExpirationHandler(` call that never reads `.error` "
                "(JavaScript)",
                "sdk-setup", "Authentication in JavaScript",
                "An expiration handler that never reads the `error`",
                languages=("js",)),
    ContextRule("await-for-without-backpressure", "MEDIUM",
                "`await for (... in x.changes)` where `x` was assigned from `registerObserver(` "
                "(Dart)",
                "performance-observability", "Backpressure in Flutter",
                "`await for` over the `changes` of a `registerObserver` observer",
                languages=("dart",)),
    ContextRule("transaction-without-hint", "MEDIUM",
                "A `.transaction(` call without `hint:` in its arguments (JavaScript)",
                "transactions-attachments", "Transaction Rules",
                "Transactions without a `hint`",
                languages=("js",)),
]
CONTEXT_INDEX: Dict[Tuple[str, str, str], ContextRule] = {
    (row.rule, language, row.variant): row for row in CONTEXT_RULES for language in row.languages
}


def report(rule: str, language: str, path: str, line: int, message: str, code: str,
           variant: str = "") -> Finding:
    """A finding of a context rule, with the severity, skill, and guide of its CONTEXT_RULES row."""
    row = CONTEXT_INDEX[(rule, language, variant)]
    return Finding(path, line, row.severity, rule, message, row.skill, row.guide, code)


def print_rules() -> None:
    """Print the rules as Markdown (the source of reference/scanner-rules.md)."""
    def cell(text: str) -> str:
        return text.replace("|", "\\|")

    print("# Scanner Rules\n")
    print("Generated with `python3 scripts/scan.py --list-rules`; do not edit by hand.")
    print("Each rule has the severity of the item of the anti-pattern checklist that it detects.")
    print("Lines that start with a comment marker are skipped, and a statement whose string")
    print("literals span several lines is matched as one line. Without Python, search for the")
    print("patterns below with Grep, which does not support lookaheads such as `(?!...)`, so drop them\n"
          "and filter the matches by eye.\n")
    print("Skipped below a directory being scanned: the directories "
          + ", ".join(f"`{name}`" for name in sorted(SKIPPED_DIRS, key=str.lower))
          + ", and the files " + ", ".join(f"`{name}`" for name in SKIPPED_FILES) + ".\n")
    print("## Line Rules\n")
    print("| Rule | Severity | Pattern | Condition | Skill | Guide |")
    print("|---|---|---|---|---|---|")
    for rule in LINE_RULES:
        if isinstance(rule.pattern, dict):
            rows = [(pattern, [language]) for language, pattern in rule.pattern.items()]
        else:
            rows = [(rule.pattern, list(rule.languages or []))]
        for pattern, languages in rows:
            guide = rule.guide_for(languages[0]) if isinstance(rule.guide, dict) else rule.guide
            conditions = []
            if pattern.flags & re.IGNORECASE:
                conditions.append("case-insensitive")
            if rule.requires_dql:
                conditions.append("line also contains a DQL keyword")
            if rule.unless:
                conditions.append(f"not if `{cell(rule.unless.pattern)}` matches")
            if rule.refine_note:
                conditions.append(rule.refine_note)
            if languages:
                conditions.append("only " + ", ".join(languages))
            print(f"| `{rule.rule}` | {rule.severity} | `{cell(pattern.pattern)}` | "
                  f"{'; '.join(conditions) or '-'} | {rule.skill} | § {guide} |")
    print("\n## Context Rules\n")
    print("| Rule | Severity | Detects | Skill | Guide |")
    print("|---|---|---|---|---|")
    for row in CONTEXT_RULES:
        print(f"| `{row.rule}` | {row.severity} | {row.detects} | {row.skill} | § {row.guide} |")


def count(number: int, noun: str) -> str:
    return f"{number} {noun}{'' if number == 1 else 's'}"


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", default=["."])
    parser.add_argument("--json", action="store_true", help="print findings as a JSON array")
    parser.add_argument("--min-severity", choices=SEVERITIES, default="MEDIUM",
                        help="hide findings below this severity")
    parser.add_argument("--fail-on", choices=SEVERITIES,
                        help="exit with 1 when a reported finding is at this severity or above")
    parser.add_argument("--exclude", action="append", default=[], metavar="GLOB",
                        help="skip files and directories whose name or relative path matches "
                             "GLOB (repeatable)")
    parser.add_argument("--list-rules", action="store_true",
                        help="print the rules as a Markdown reference and exit")
    args = parser.parse_args(argv)

    if args.list_rules:
        print_rules()
        return 0

    # A path that does not exist yields no findings, which would read as a clean scan.
    missing = [path for path in args.paths if not os.path.exists(path)]
    for path in missing:
        print(f"error: {path} does not exist and was not scanned", file=sys.stderr)

    result = scan_paths([path for path in args.paths if path not in missing], args.exclude)
    limit = SEVERITIES.index(args.min_severity)
    findings = [f for f in result.findings if SEVERITIES.index(f.severity) <= limit]
    hidden = len(result.findings) - len(findings)

    if args.json:
        json.dump([asdict(f) for f in findings], sys.stdout, indent=2)
        print()
    elif not findings and result.files:
        print("No candidate anti-patterns found. This does not mean the code is correct; "
              "continue with the inventory, the cross-device review, and the manual review.")
    elif findings:
        for f in findings:
            print(f"{f.path}:{f.line}: {f.severity} {f.rule}: {f.message} "
                  f"[skill: {f.skill}; guide: § {f.guide}]")
            print(f"    {f.code}")
        counts = {s: sum(1 for f in findings if f.severity == s) for s in SEVERITIES}
        print(f"\n{len(findings)} candidates ({', '.join(f'{v} {k}' for k, v in counts.items())}). "
              "Confirm each one in context before reporting it.")

    by_severity = ", ".join(f"{sum(1 for f in findings if f.severity == s)} {s}" for s in SEVERITIES)
    print(f"ditto-scan: {count(result.files, 'file')} scanned; "
          f"{count(len(findings), 'hit')} reported ({by_severity}); "
          f"{hidden} hidden by --min-severity; "
          f"{result.suppressed} suppressed by ditto-scan: ignore", file=sys.stderr)

    if missing:
        return 2
    if result.files == 0:
        print("error: no source file was scanned; check the paths and --exclude", file=sys.stderr)
        return 2
    if args.fail_on and any(SEVERITIES.index(f.severity) <= SEVERITIES.index(args.fail_on)
                            for f in findings):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
