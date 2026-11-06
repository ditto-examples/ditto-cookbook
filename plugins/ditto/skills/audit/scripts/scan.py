#!/usr/bin/env python3
"""Scan source files for known Ditto SDK anti-patterns.

Every hit is a *candidate*: the scanner matches text, not program behavior.
Read the surrounding code and confirm each hit against the skill and guide
section it names before reporting it.

Usage:
    python3 scan.py [PATH ...] [--json] [--min-severity LEVEL]

PATH defaults to the current directory. Requires Python 3.8+ and no
third-party packages.
"""

from __future__ import annotations

import argparse
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

SKIPPED_DIRS = {
    ".git",
    ".dart_tool",
    ".gradle",
    ".idea",
    ".next",
    "build",
    "dist",
    "node_modules",
    "Pods",
    "DerivedData",
    ".build",
}

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
    ),
    LineRule(
        "any-every-satisfies-over-array",
        "CRITICAL",
        rx(r"\b(ANY|EVERY)\s+\w+\s+IN\s+(:\w+|\[|\()"),
        "ANY/EVERY ... SATISFIES over a parameter or literal array returns no rows in "
        "local queries and observers (SDK 5.1.0 and 5.2.0); use field IN :values",
        "query-sync",
        "Filtering by Membership",
    ),
    LineRule(
        "flag-not-equal-true",
        "CRITICAL",
        rx(r"\b(WHERE|AND|OR)\s+[\w.]+\s*!=\s*true\b|\b(WHERE|AND|OR)\s+NOT\s+is[A-Z]\w*"),
        "Comparison drops documents where the flag is missing or null; "
        "use coalesce(flag, false) = false",
        "storage-lifecycle",
        "MISSING and NULL",
    ),
    LineRule(
        "delete-evict-use-ids",
        "CRITICAL",
        rx(r"\b(DELETE|EVICT)\s+FROM\s+\S+\s+USE\s+IDS\b"),
        "DELETE/EVICT with USE IDS and no WHERE predicate removes nothing in SDK 5.1.0 "
        "(fixed in 5.2.0); use WHERE _id IN :ids while any device runs 5.1.0",
        "storage-lifecycle",
        "Known Issues in SDK 5.1.0",
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
    ),
    LineRule(
        "unquoted-object-literal-key",
        "CRITICAL",
        rx(r"DOCUMENTS\s*\(\s*\{\s*[A-Za-z_]\w*\s*:"),
        "Unquoted key in an inline DQL object literal (rejected in INSERT, {} in SELECT); "
        "quote keys or pass the document as a parameter",
        "query-sync",
        "Quote every key in inline object literals",
    ),
    LineRule(
        "read-modify-write-counter",
        "CRITICAL",
        rx(r"\bSET\s+([\w.]+)\s*=\s*\1\s*[-+]"),
        "Read-modify-write of a number loses concurrent changes; use a COUNTER with APPLY",
        "data-modeling",
        "Counters",
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
    ),
    LineRule(
        "fresh-transport-config",
        "CRITICAL",
        rx(r"\b(Ditto)?TransportConfig\(\s*\)", 0),
        "A new TransportConfig() or DittoTransportConfig() disables every transport; change "
        "the current one with updateTransportConfig",
        "sdk-setup",
        "Transport Configuration",
    ),
    LineRule(
        "development-authentication",
        "CRITICAL",
        rx(r"developmentProvider|Authenticator\.development|Authenticator\.DEVELOPMENT_PROVIDER\b"
           r"|OnlinePlayground|AuthenticationProvider\.development\b|provider:\s*\.development\b", 0),
        "Development provider or token; never ship it in a production build",
        "sdk-setup",
        "Authentication in Production",
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
    ),
    LineRule(
        "hardcoded-private-key",
        "CRITICAL",
        rx(r"privateKey\s*[:=]\s*['\"]", 0),
        "Shared key hardcoded in source; load it from secure provisioning",
        "sdk-setup",
        "Small-Peers-Only Deployments",
    ),
    LineRule(
        "revocation-check-disabled",
        "CRITICAL",
        rx(r"PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED" + SETS + r"false"),
        "Certificate revocation checking disabled",
        "sdk-setup",
        "Certificate Revocation (SDK 5.1+)",
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
    ),
    # --- HIGH: sync cost, memory, performance, risky settings ---
    LineRule(
        "upsert-do-update",
        "HIGH",
        rx(r"ON\s+ID\s+CONFLICT\s+DO\s+UPDATE\b(?!_LOCAL_DIFF)"),
        "DO UPDATE rewrites unchanged fields, which overwrites earlier concurrent edits "
        "of them and wakes observers; prefer DO UPDATE_LOCAL_DIFF, and never write back "
        "a stale whole document",
        "query-sync",
        "ON ID CONFLICT",
    ),
    LineRule(
        "strict-mode-enabled",
        "HIGH",
        rx(r"DQL_STRICT_MODE" + SETS + r"true"),
        "Strict mode hides undeclared MAP/COUNTER/ATTACHMENT fields and disables "
        "secondary index use (SDK 5.1.0 and 5.2.0); confirm it is intended and set on "
        "every open (DittoConfig.systemParameters in SDK 5.2+)",
        "data-modeling",
        "Strict Mode",
    ),
    LineRule(
        "restrict-subscriptions-disabled",
        "HIGH",
        rx(r"DQL_RESTRICT_SUBSCRIPTIONS" + SETS + r"false"),
        "Stateful LIMIT/ORDER BY subscriptions degrade sync; LIMIT bounds only the "
        "initial download",
        "query-sync",
        "Subscription Rules",
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
        languages=("dart",),
    ),
    LineRule(
        "verbose-logging",
        "HIGH",
        rx(r"LogLevel\.[vV]erbose\b|minimumLogLevel\s*=\s*\.verbose\b"
           r"|\bminimumLogLevel\s*=\s*['\"]Verbose['\"]", 0),
        "Verbose logging can significantly slow replication; never in production",
        "performance-observability",
        "Log levels",
    ),
    LineRule(
        "use-index-empty",
        "HIGH",
        rx(r"USE\s+INDEX\s+(''|\"\")"),
        "USE INDEX '' makes every outer row scan the inner collection; create the "
        "index instead",
        "query-sync",
        "Performance tips",
    ),
    LineRule(
        "tombstone-ttl-change",
        "HIGH",
        rx(r"TOMBSTONE_TTL_HOURS" + SETS),
        "Tombstone TTL on a device must not exceed the Ditto Server TTL, and must be "
        "set on every open (DittoConfig.systemParameters in SDK 5.2+)",
        "storage-lifecycle",
        "Tombstone TTL and reaping",
    ),
    # --- MEDIUM: likely mistakes worth a look ---
    LineRule(
        "is-not-null-existence",
        "MEDIUM",
        rx(r"\bIS\s+NOT\s+NULL\b"),
        "IS NOT NULL is also true for a missing field; to test existence use IS NOT MISSING",
        "query-sync",
        "MISSING and NULL",
        requires_dql=True,
    ),
    LineRule(
        "advise-and-provision",
        "MEDIUM",
        rx(r"\bADVISE\s+AND\s+PROVISION\b"),
        "ADVISE AND PROVISION creates indexes as a side effect; keep it out of production code",
        "performance-observability",
        "ADVISE (SDK 5.1+)",
    ),
    LineRule(
        "type-equals-number",
        "MEDIUM",
        rx(r"\btype\(\s*[\w.]+\s*\)\s*=\s*['\"]number['\"]"),
        "type(x) = 'number' never matches",
        "guide",
        "Type Checking",
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
    ),
    LineRule(
        "variable-precision-timestamp",
        "MEDIUM",
        {
            "dart": rx(r"\.toUtc\(\)\.toIso8601String\(\)", 0),
            "kotlin": rx(r"\bInstant\.now\(\)\.toString\(\)", 0),
        },
        "This format writes as many fraction digits as needed, so the strings do not sort "
        "chronologically; produce timestamps with one fixed-precision UTC helper",
        "data-modeling",
        "Timestamps",
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
        "Always pass values as parameters",
    ),
    LineRule(
        "all-peer-to-peer-enabled",
        "MEDIUM",
        rx(r"\.setAllPeerToPeerEnabled\(\s*true\s*\)", 0),
        "setAllPeerToPeerEnabled(true) also enables Wi-Fi Aware, which makes "
        "updateTransportConfig() throw on Node.js on macOS; use setAvailablePeerToPeerEnabled(true)",
        "sdk-setup",
        "Transports and Presence in JavaScript",
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
        languages=("dart",),
    ),
    # --- Kotlin ---
    LineRule(
        "float-read-as-double",
        "MEDIUM",
        {
            "kotlin": rx(r"\]\s*\??\.(double|doubleOrNull)\b", 0),
            "swift": rx(r"\bas\?\s*Double\b", 0),
        },
        "A decimal that a 32-bit float holds exactly, such as 7.5, comes back as a float "
        "(Kotlin FloatValue, Swift Float), so reading it as a Double gives null or nil; read "
        "numbers with a helper that accepts every number type (Swift: NSNumber)",
        "query-sync",
        {"kotlin": "Query results in Kotlin", "swift": "Query results in Swift"},
    ),
    # --- Swift ---
    LineRule(
        "date-description-timestamp",
        "HIGH",
        rx(r"\\\(Date\(\)\)|\bDate\(\)\.description\b", 0),
        "A Date's description is not ISO 8601 (a space instead of T, no fractional seconds, "
        "+0000 instead of Z); format UTC with ISO8601FormatStyle and fractional seconds",
        "data-modeling",
        "IDs and Timestamps in Swift",
        languages=("swift",),
    ),
    LineRule(
        "open-sync",
        "MEDIUM",
        rx(r"\bDitto\.openSync\(", 0),
        "Ditto.openSync blocks the calling thread until the store is open; prefer "
        "await Ditto.open, and never call openSync on the main thread",
        "sdk-setup",
        "Opening Ditto in Swift",
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
        languages=("swift",),
    ),
]


def is_comment(line: str) -> bool:
    stripped = line.lstrip()
    return stripped.startswith(("//", "/*", "*", "#!"))


def scan_lines(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    for number, line in enumerate(lines, start=1):
        if is_comment(line):
            continue
        for rule in LINE_RULES:
            pattern = rule.pattern_for(language)
            if pattern is None:
                continue
            if rule.requires_dql and not DQL_KEYWORDS.search(line):
                continue
            if not pattern.search(line):
                continue
            if rule.unless and rule.unless.search(line):
                continue
            if rule.refine and not rule.refine(line):
                continue
            yield Finding(path, number, rule.severity, rule.rule, rule.message,
                          rule.skill, rule.guide_for(language), line.strip())


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
STRING_LITERAL = re.compile(r"'([^'\\]*(?:\\.[^'\\]*)*)'|\"([^\"\\]*(?:\\.[^\"\\]*)*)\"|`([^`]*)`")


def scan_subscriptions(path: str, lines: List[str]) -> Iterable[Finding]:
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
            elif re.search(r"arguments\s*:", candidate):
                break
            for match in STRING_LITERAL.finditer(candidate):
                text.append(next(group for group in match.groups() if group is not None))
            depth += candidate.count("(") - candidate.count(")")
            if depth <= 0:
                break
        query = " ".join(text)
        if query and SUBSCRIPTION_REJECTED.search(query):
            yield Finding(path, index + 1, "HIGH", "subscription-rejected-feature",
                          "Subscriptions accept only SELECT * FROM c [WHERE ...]; projections, "
                          "ORDER BY, LIMIT, JOIN, GROUP BY, DISTINCT, and USE IDS are rejected "
                          "or degrade sync",
                          "query-sync", "Subscription Rules", query.strip()[:160])


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
            yield Finding(path, index + 1, "HIGH", "observer-onchange-only",
                          "Observer registered with onChange and no `changes` stream consumed "
                          "nearby; unconsumed results stay in memory (SDK 5.1.0 and 5.2.0, also "
                          "with registerObserverV2 and registerObserverWithSignalNext)",
                          "query-sync", "Store Observers in Flutter", line.strip())


# A transaction callback (Dart, JavaScript) or trailing closure (Kotlin, Swift).
TRANSACTION_CALL = re.compile(r"\.transaction\s*[({]")
INSIDE_TRANSACTION = re.compile(r"\.store\.execute\s*\(|\.transaction\s*[({]")


def scan_transactions(path: str, lines: List[str]) -> Iterable[Finding]:
    """store.execute or a nested transaction inside a transaction callback."""
    for index, line in enumerate(lines):
        if is_comment(line) or not TRANSACTION_CALL.search(line):
            continue
        for offset, body in enumerate(block(lines, index)[1:], start=1):
            if not is_comment(body) and INSIDE_TRANSACTION.search(body):
                yield Finding(path, index + offset + 1, "CRITICAL", "execute-inside-transaction",
                              "ditto.store.execute inside a transaction (throws in Flutter; its "
                              "writes never complete in JavaScript, Kotlin, and Swift) or a nested "
                              "read-write transaction (waits for the outer one forever); use the "
                              "transaction's own execute",
                              "transactions-attachments", "Transaction Rules", body.strip())


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
            yield Finding(path, index + 1, "HIGH", "result-leaves-handler",
                          "The query result leaves the mapping function, which closes it; reading "
                          "its items afterwards throws. Convert the items inside the function",
                          "query-sync", "Query results in Kotlin", line.strip())


REGISTRATION = re.compile(
    r"^\s*(?P<discard>_\s*=\s*)?(try[?!]?\s+)?(await\s+)?[\w.?!]*\b"
    r"(?P<call>store\.registerObserver\w*|sync\.registerSubscription)\s*\(")
# A line after which a new statement starts: the end of a statement or of a block,
# or the opening of a block that is not a lambda whose value is kept.
STATEMENT_START = re.compile(r"(;|\}|\{)\s*$")
# A block whose last expression is its value: a lambda passed to map, let, and the like,
# and in Swift, a function with a return type or a computed property (implicit return).
VALUE_LAMBDA = re.compile(
    r"(\.(map\w*|flatMap\w*|compactMap|associate\w*|let|run|also|apply|with)|\blazy|=)\s*\{\s*$"
    r"|->\s*[^{}]+\{\s*$|\bvar\s+\w+\s*:\s*[^={}]+\{\s*$")


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
            previous = previous_code_line(lines, index)
            if previous is not None and (not STATEMENT_START.search(previous)
                                         or VALUE_LAMBDA.search(previous)):
                continue
            rest = statement_end(lines, index)
            if rest.startswith((",", ")", "]")) or KEEPING_CHAIN.match(rest):
                continue
        if match.group("call").startswith("store"):
            yield Finding(path, index + 1, "HIGH", "discarded-observer",
                          "The observer that registerObserver returns is discarded, so nothing "
                          "can release it; it keeps running until Ditto shuts down",
                          "query-sync", "Observer Lifecycle", line.strip())
        else:
            yield Finding(path, index + 1, "HIGH", "discarded-subscription",
                          "The subscription that registerSubscription returns is discarded, so "
                          "nothing can cancel it; it keeps syncing until Ditto shuts down",
                          "query-sync", "Subscription Lifecycle", line.strip())


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
            yield Finding(path, index + 1, "MEDIUM", "observer-task-without-backpressure",
                          "The observer handler starts a Task and returns, so the next result does "
                          "not wait for the work; use handlerWithSignalNext and call signalNext "
                          "when the Task is done",
                          "performance-observability", "Backpressure in Swift", line.strip())


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
                yield Finding(path, index + offset + 1, "HIGH", "concurrent-writes-in-loop",
                              "A coroutine or Task per write: while a transaction is open, each "
                              "waiting write can hold a thread, and enough of them stop the app; "
                              "write in one statement, one transaction, or one after another",
                              "transactions-attachments", "Transaction Rules", body.strip())


def scan_lifecycle(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """ditto.close() when the app moves to the background."""
    if language != "dart":
        return
    for index, line in enumerate(lines):
        if is_comment(line) or "AppLifecycleState.paused" not in line:
            continue
        if re.search(r"\.close\(\)", window(lines, index, 8)):
            yield Finding(path, index + 1, "CRITICAL", "close-on-background",
                          "ditto.close() on AppLifecycleState.paused makes every later call "
                          "throw; stop sync instead and keep the instance open",
                          "sdk-setup", "Starting and Stopping Sync", line.strip())


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
            yield Finding(path, index + 1, "HIGH", "ditto-in-ui",
                          "Ditto opened in a file that defines a screen: the screen can be created "
                          "again, and a second open of the same directory fails or never completes; "
                          "open one instance at app start and share it",
                          "sdk-setup", "One instance per persistence directory", line.strip())


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
                yield Finding(path, index + 1, "MEDIUM", "login-error-unreported",
                              "login() throws when the token is rejected or the server is "
                              "unreachable, and an exception that leaves the expiration handler is "
                              "only logged; catch it inside the handler and report it",
                              "sdk-setup", "Authentication in Kotlin", line.strip())
        if re.search(r"\.registerObserver\s*\(", line):
            body = block(lines, index)
            if not CAUGHT.search("\n".join(body)):
                for offset, candidate in enumerate(body):
                    if not is_comment(candidate) and THROWS.search(candidate):
                        yield Finding(path, index + offset + 1, "MEDIUM", "throwing-observer-handler",
                                      "An exception that leaves a registerObserver handler closes the "
                                      "observer, and the SDK only logs it; catch errors inside the handler",
                                      "query-sync", "Observer lifecycle in Kotlin", candidate.strip())
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
                    yield Finding(path, index + offset + 1, "MEDIUM", "execute-on-main",
                                  "store.execute blocks the thread of the coroutine that calls it, so "
                                  "on the main dispatcher it freezes the UI; call it inside "
                                  "withContext(Dispatchers.IO)",
                                  "performance-observability", "Executing DQL in Kotlin",
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
                yield Finding(path, index + offset + 1, "CRITICAL", "close-inside-transaction",
                              "close() while a transaction is open stops the Dart isolate (the UI "
                              "isolate in an app); let the transaction end first",
                              "transactions-attachments", "Closing Ditto in Flutter", candidate.strip())
                break
        for offset, candidate in enumerate(body[1:], start=1):
            if not is_comment(candidate) and STARTED_WORK.search(candidate):
                yield Finding(path, index + offset + 1, "HIGH", "work-started-in-transaction",
                              "Timers, listeners, and other work started inside a transaction "
                              "callback keep its zone, so their later ditto.store.execute calls throw "
                              "after the commit; start them outside the callback",
                              "transactions-attachments", "Transactions in Flutter", candidate.strip())
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
                yield Finding(path, index + offset + 1, "HIGH", "signal-next-skipped-on-error",
                              "signalNext() is skipped when the work before it throws, and the "
                              "observer then stops delivering results; call it in finally (Dart) or "
                              "defer (Swift)",
                              "performance-observability", "Backpressure (SDK 5.1+)", candidate.strip())
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
            yield Finding(path, index + 1, "MEDIUM", "await-for-without-backpressure",
                          "await for over the changes of a registerObserver observer handles every "
                          "queued result in turn, so the latest state arrives late; use "
                          "registerObserverV2 or registerObserverWithSignalNext",
                          "performance-observability", "Backpressure in Flutter", line.strip())


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
            yield Finding(path, index + 1, "MEDIUM", "transaction-without-hint",
                          "Transaction without a hint in its options; long transactions are "
                          "logged by hint",
                          "transactions-attachments", "Transaction Rules", lines[index].strip())
    for index, span in calls(lines, re.compile(
            r"\.(?:execute|registerObserver(?:WithSignalNext)?|registerSubscription)\s*\(")):
        for number, text in span:
            if not is_comment(lines[number]) and JS_VALUE.search(text):
                yield Finding(path, number + 1, "HIGH", "unconvertible-argument",
                              "A Date or a Set is stored as an empty object {} without an error, "
                              "and NaN and Infinity are rejected; pass an ISO 8601 UTC string or "
                              "epoch milliseconds, an array, and finite numbers",
                              "query-sync", "Arguments and value types in JavaScript",
                              lines[number].strip())
                break
    for index, span in calls(lines, re.compile(r"\.registerObserver\s*\(")):
        handler = js_handler(span_text(span))
        if handler and handler[0]:
            yield Finding(path, index + 1, "HIGH", "observer-task-without-backpressure",
                          "An async registerObserver handler returns at its first await, so calls "
                          "overlap, an older call can finish last, and a rejection is unhandled (it "
                          "ends a Node.js process); keep the handler synchronous, or use "
                          "registerObserverWithSignalNext and call signalNext() in finally",
                          "performance-observability", "Backpressure in JavaScript",
                          lines[index].strip())
    for index, span in calls(lines, re.compile(r"\.registerObserverWithSignalNext\s*\(")):
        handler = js_handler(span_text(span))
        if not handler:
            continue
        _, names, body = handler
        if len(names) < 2 or not re.search(rf"\b{re.escape(names[1])}\b", body):
            yield Finding(path, index + 1, "HIGH", "missing-signal-next",
                          "registerObserverWithSignalNext delivers the next result only after "
                          "signalNext() is called, and this handler never calls it, so the observer "
                          "stops after the first result; call signalNext() when the work is done",
                          "performance-observability", "Backpressure in JavaScript",
                          lines[index].strip())
        elif (re.search(r"\bawait\b", body) and re.search(rf"\b{re.escape(names[1])}\s*\(\s*\)", body)
              and not re.search(r"\bfinally\b|\bcatch\b", body)):
            yield Finding(path, index + 1, "HIGH", "signal-next-skipped-on-error",
                          "signalNext() is skipped when the work before it throws, and the "
                          "observer then stops delivering results; call it in finally",
                          "performance-observability", "Backpressure (SDK 5.1+)", lines[index].strip())
    for index, line in enumerate(lines):
        match = re.search(r"\.forEach\(\s*async\b", line)
        if match and not is_comment(line):
            if re.search(r"\.execute\s*\(", span_text(call_span(lines, index, line.index("(", match.start())))):
                yield Finding(path, index + 1, "HIGH", "concurrent-writes-in-loop",
                              "forEach does not wait for an async callback, so its statements run "
                              "unawaited: inside a transaction they are not applied, their rejections "
                              "are unhandled, and the commit can fail; await each statement in a "
                              "for...of loop, or use Promise.all",
                              "transactions-attachments", "Transaction Rules", line.strip())
    for index, span in calls(lines, re.compile(r"\.setExpirationHandler\s*\(")):
        text = span_code(span, lines)
        if ".login(" in text and (re.search(r"\bthrow\s+(?:new\b|[\w$])", text)
                                  or not re.search(r"\.error\b", text)):
            yield Finding(path, index + 1, "MEDIUM", "login-error-unreported",
                          "login() reports a rejected token or an unreachable server in "
                          "result.error instead of throwing, and an error thrown from the "
                          "expiration handler is only logged; check result.error and report it "
                          "inside the handler",
                          "sdk-setup", "Authentication in JavaScript", lines[index].strip())
    for index, span in calls(lines, JS_EFFECT):
        text = span_text(span)
        if JS_REGISTRATION.search(text) and not re.search(r"\breturn\b", text):
            yield Finding(path, index + 1, "HIGH", "effect-without-cleanup",
                          "The effect registers an observer, subscription, or fetch but returns no "
                          "cleanup, so it keeps running after unmount (and twice under Strict "
                          "Mode); return a cleanup that cancels or stops it",
                          "query-sync", "Observer lifecycle in JavaScript", lines[index].strip())
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
                yield Finding(path, number + 1, "HIGH", "register-in-render",
                              "A component body runs on every render, so this registers a new "
                              "observer, subscription, or attachment fetch each time and never "
                              "releases it; register in useEffect and release it in its cleanup",
                              "query-sync", "Store Observers in JavaScript", line.strip())
            if OPEN_CALL["js"].search(line):
                yield Finding(path, number + 1, "HIGH", "ditto-in-ui",
                              "Ditto opened in a component: it opens again whenever the component "
                              "mounts, and a second open of the same directory fails; open one "
                              "instance at app start and share it",
                              "sdk-setup", "One instance per persistence directory", line.strip())


def scan_data_sync_info_reads(path: str, language: str, lines: List[str]) -> Iterable[Finding]:
    """A read of system:data_sync_info in a file without a deadline helper."""
    if language not in DEADLINE:
        return
    text = "\n".join(line for line in lines if not is_comment(line))
    if all(pattern.search(text) for pattern in DEADLINE[language]):
        return
    for index, span in calls(lines, re.compile(r"\.execute\s*\(")):
        if "system:data_sync_info" in span_text(span):
            yield Finding(path, index + 1, "HIGH", "unbounded-data-sync-info-read",
                          "A read of system:data_sync_info can stop responding on a device "
                          "connected to another peer (in testing: JavaScript and Swift on 5.1.0 and "
                          "5.2.0, Kotlin on 5.1.0); give every read a deadline and treat a missed "
                          "one as not confirmed",
                          "query-sync", "Monitoring Sync Status", lines[index].strip())


FILE_SCANNERS: List[Callable[[str, str, List[str]], Iterable[Finding]]] = [
    scan_lines,
    lambda path, language, lines: scan_subscriptions(path, lines),
    scan_observers,
    lambda path, language, lines: scan_transactions(path, lines),
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


def iter_files(paths: Sequence[str]) -> Iterable[str]:
    for root in paths:
        if os.path.isfile(root):
            yield root
            continue
        for directory, subdirectories, files in os.walk(root):
            subdirectories[:] = sorted(d for d in subdirectories if d not in SKIPPED_DIRS)
            for name in sorted(files):
                if os.path.splitext(name)[1] in EXTENSIONS:
                    yield os.path.join(directory, name)


def scan(paths: Sequence[str]) -> List[Finding]:
    findings: List[Finding] = []
    for path in iter_files(paths):
        language = EXTENSIONS.get(os.path.splitext(path)[1])
        if language is None:
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
        except OSError as error:
            print(f"warning: cannot read {path}: {error}", file=sys.stderr)
            continue
        for scanner in FILE_SCANNERS:
            findings.extend(scanner(path, language, lines))
    unique = {(f.path, f.line, f.rule): f for f in findings}
    return sorted(unique.values(),
                  key=lambda f: (SEVERITIES.index(f.severity), f.path, f.line))


CONTEXT_RULES = [
    ("subscription-rejected-feature", "HIGH",
     "A `registerSubscription(` call whose query uses a projection, ORDER BY, LIMIT, JOIN, "
     "GROUP BY, DISTINCT, or USE IDS", "query-sync", "Subscription Rules"),
    ("execute-inside-transaction", "CRITICAL",
     "`.store.execute(`, `.transaction(`, or `.transaction {` inside the braces of a "
     "`.transaction(` callback or a `.transaction {` trailing closure",
     "transactions-attachments", "Transaction Rules"),
    ("close-on-background", "CRITICAL",
     "`.close()` within 8 lines after `AppLifecycleState.paused` (Dart)",
     "sdk-setup", "Starting and Stopping Sync"),
    ("observer-onchange-only", "HIGH",
     "`registerObserver*(` with `onChange:` and no `.changes` in the same declaration (Dart)",
     "query-sync", "Store Observers in Flutter"),
    ("discarded-observer", "HIGH",
     "A statement that starts with `store.registerObserver*(` (or `_ =` before it) and does "
     "not keep the returned observer: not assigned, returned, or collected",
     "query-sync", "Observer Lifecycle"),
    ("discarded-subscription", "HIGH",
     "A statement that starts with `sync.registerSubscription(` (or `_ =` before it) and does "
     "not keep the returned subscription",
     "query-sync", "Subscription Lifecycle"),
    ("result-leaves-handler", "HIGH",
     "An `.execute(` or `.observe(` whose mapping function returns the result or its "
     "`items` unchanged, such as `{ result -> result }` or `{ it.items }` (Kotlin)",
     "query-sync", "Query results in Kotlin"),
    ("concurrent-writes-in-loop", "HIGH",
     "`launch {`, `async {`, `Task {`, or `addTask {` inside a `for`, `repeat`, or `forEach`/`map` "
     "loop, with `.store.execute(` in its braces (Kotlin, Swift)",
     "transactions-attachments", "Transaction Rules"),
    ("ditto-in-ui", "HIGH",
     "`DittoFactory.create(` (Kotlin) or `Ditto.open(` (Dart, Swift) in a file that defines an "
     "Activity, Fragment, composable, widget, SwiftUI view, or view controller",
     "sdk-setup", "One instance per persistence directory"),
    ("login-error-unreported", "MEDIUM",
     "`.login(` inside an `expirationHandler = {` lambda without `try` or `runCatching` (Kotlin)",
     "sdk-setup", "Authentication in Kotlin"),
    ("login-error-unreported", "MEDIUM",
     "`.login(` inside a `setExpirationHandler(` call that throws or never reads `.error` "
     "(JavaScript)",
     "sdk-setup", "Authentication in JavaScript"),
    ("throwing-observer-handler", "MEDIUM",
     "`!!`, `throw`, `error(`, `require(`, or `check(` in a `registerObserver(` handler without "
     "`try` or `runCatching` (Kotlin)",
     "query-sync", "Observer lifecycle in Kotlin"),
    ("execute-on-main", "MEDIUM",
     "`.store.execute(` in a `lifecycleScope`/`viewModelScope`/`MainScope()` launch or a "
     "`Dispatchers.Main` block, before any `withContext(Dispatchers.IO)` (Kotlin)",
     "performance-observability", "Executing DQL in Kotlin"),
    ("close-inside-transaction", "CRITICAL",
     "`<ditto>.close()` inside the braces of a `.transaction(` callback (Dart)",
     "transactions-attachments", "Closing Ditto in Flutter"),
    ("work-started-in-transaction", "HIGH",
     "An observer, a `changes.listen(`, a `Timer`, `Future.delayed`, `unawaited(`, or "
     "`scheduleMicrotask(` inside a `.transaction(` callback (Dart)",
     "transactions-attachments", "Transactions in Flutter"),
    ("signal-next-skipped-on-error", "HIGH",
     "`signalNext()` in an async `changes.listen` or `onChange` callback with `await` and no "
     "`catch`/`finally` (Dart), in a `{ result, signalNext in` handler with `try` and no "
     "`catch`/`defer` (Swift), or in a `registerObserverWithSignalNext(` handler with `await` and "
     "no `catch`/`finally` (JavaScript)",
     "performance-observability", "Backpressure (SDK 5.1+)"),
    ("await-for-without-backpressure", "MEDIUM",
     "`await for (... in x.changes)` where `x` was assigned from `registerObserver(` (Dart)",
     "performance-observability", "Backpressure in Flutter"),
    ("transaction-without-hint", "MEDIUM",
     "A `.transaction(` call without `hint:` in its arguments (JavaScript)",
     "transactions-attachments", "Transaction Rules"),
    ("unconvertible-argument", "HIGH",
     "A property value `new Date(...)`, `new Set(...)`, `NaN`, or `Infinity` inside an `execute(`, "
     "`registerObserver(`, or `registerSubscription(` call (JavaScript)",
     "query-sync", "Arguments and value types in JavaScript"),
    ("observer-task-without-backpressure", "HIGH",
     "An `async` handler passed to `registerObserver(` (JavaScript)",
     "performance-observability", "Backpressure in JavaScript"),
    ("missing-signal-next", "HIGH",
     "A `registerObserverWithSignalNext(` handler without a second parameter, or that never uses "
     "it (JavaScript)",
     "performance-observability", "Backpressure in JavaScript"),
    ("concurrent-writes-in-loop", "HIGH",
     "`.forEach(async` with `.execute(` in its callback (JavaScript)",
     "transactions-attachments", "Transaction Rules"),
    ("effect-without-cleanup", "HIGH",
     "A `useEffect(` that registers an observer, a subscription, or a fetch and has no `return` "
     "(JavaScript)",
     "query-sync", "Observer lifecycle in JavaScript"),
    ("register-in-render", "HIGH",
     "A registration in the body of a component that returns JSX, outside its effects (JavaScript)",
     "query-sync", "Store Observers in JavaScript"),
    ("ditto-in-ui", "HIGH",
     "`Ditto.open(` inside a component that returns JSX (JavaScript)",
     "sdk-setup", "One instance per persistence directory"),
    ("unbounded-data-sync-info-read", "HIGH",
     "An `.execute(` of `system:data_sync_info` in a file without `Promise.race(` (JavaScript), "
     "both `withTimeout` and `.async {` (Kotlin), or `withDeadline` or a task group (Swift)",
     "query-sync", "Monitoring Sync Status"),
    ("observer-task-without-backpressure", "MEDIUM",
     "`Task {` inside the braces of a `registerObserver*(` handler that never mentions "
     "`signalNext` (Swift)",
     "performance-observability", "Backpressure in Swift"),
]


def print_rules() -> None:
    """Print the rules as Markdown (the source of reference/scanner-rules.md)."""
    def cell(text: str) -> str:
        return text.replace("|", "\\|")

    print("# Scanner Rules\n")
    print("Generated with `python3 scripts/scan.py --list-rules`; do not edit by hand.")
    print("Lines that start with a comment marker are skipped. Without Python, search for the")
    print("patterns below with Grep, which does not support lookaheads such as `(?!...)`, so drop them\n"
          "and filter the matches by eye.\n")
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
    for name, severity, detects, skill, guide in CONTEXT_RULES:
        print(f"| `{name}` | {severity} | {detects} | {skill} | § {guide} |")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", default=["."])
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    parser.add_argument("--min-severity", choices=SEVERITIES, default="MEDIUM",
                        help="hide findings below this severity")
    parser.add_argument("--list-rules", action="store_true",
                        help="print the rules as a Markdown reference and exit")
    args = parser.parse_args(argv)

    if args.list_rules:
        print_rules()
        return 0

    limit = SEVERITIES.index(args.min_severity)
    findings = [f for f in scan(args.paths) if SEVERITIES.index(f.severity) <= limit]

    if args.json:
        json.dump([asdict(f) for f in findings], sys.stdout, indent=2)
        print()
        return 0

    if not findings:
        print("No candidate anti-patterns found. This does not mean the code is correct; "
              "continue with the manual review checklist.")
        return 0
    for f in findings:
        print(f"{f.path}:{f.line}: {f.severity} {f.rule}: {f.message} "
              f"[skill: {f.skill}; guide: § {f.guide}]")
        print(f"    {f.code}")
    counts = {s: sum(1 for f in findings if f.severity == s) for s in SEVERITIES}
    print(f"\n{len(findings)} candidates ({', '.join(f'{v} {k}' for k, v in counts.items())}). "
          "Confirm each one in context before reporting it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
