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
from typing import Callable, Iterable, List, Optional, Sequence

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
    pattern: re.Pattern
    message: str
    skill: str
    guide: str
    languages: Optional[Sequence[str]] = None
    # Only report the line if it also looks like DQL.
    requires_dql: bool = False
    # Do not report the line if this pattern also matches it.
    unless: Optional[re.Pattern] = None


def rx(pattern: str, flags: int = re.IGNORECASE) -> re.Pattern:
    return re.compile(pattern, flags)


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
        "local queries and observers (SDK 5.1.0); use field IN :values",
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
        "DELETE/EVICT with USE IDS and no WHERE predicate removes nothing (SDK 5.1.0); "
        "use WHERE _id IN :ids",
        "storage-lifecycle",
        "DELETE and EVICT",
        unless=rx(r"\bWHERE\s+(?!true\b)"),
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
        rx(r"DateTime\.now\(\)\.toIso8601String\(\)", 0),
        "Local timestamp without a zone designator (DQL date functions return MISSING); "
        "store UTC with one fixed-precision helper",
        "data-modeling",
        "Timestamps",
        languages=("dart",),
    ),
    LineRule(
        "fresh-transport-config",
        "CRITICAL",
        rx(r"\bTransportConfig\(\s*\)", 0),
        "A new TransportConfig() disables every transport; change the current one with "
        "updateTransportConfig()",
        "sdk-setup",
        "Transport Configuration",
    ),
    LineRule(
        "development-authentication",
        "CRITICAL",
        rx(r"developmentProvider|Authenticator\.development|OnlinePlayground", 0),
        "Development provider or token; never ship it in a production build",
        "sdk-setup",
        "Authentication in Production",
    ),
    LineRule(
        "small-peers-without-key",
        "CRITICAL",
        rx(r"DittoConfigConnectSmallPeersOnly\(\s*\)", 0),
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
        rx(r"PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED\s*=\s*false"),
        "Certificate revocation checking disabled",
        "sdk-setup",
        "Certificate Revocation (SDK 5.1+)",
    ),
    # --- HIGH: sync cost, memory, performance, risky settings ---
    LineRule(
        "upsert-do-update",
        "HIGH",
        rx(r"ON\s+ID\s+CONFLICT\s+DO\s+UPDATE\b(?!_LOCAL_DIFF)"),
        "DO UPDATE rewrites unchanged fields and wakes observers; prefer "
        "DO UPDATE_LOCAL_DIFF, and never write back a stale whole document",
        "query-sync",
        "ON ID CONFLICT",
    ),
    LineRule(
        "strict-mode-enabled",
        "HIGH",
        rx(r"DQL_STRICT_MODE\s*=\s*true"),
        "Strict mode hides undeclared MAP/COUNTER/ATTACHMENT fields and disables "
        "secondary index use in SDK 5.1.0; confirm it is intended and applied on every open",
        "data-modeling",
        "Strict Mode",
    ),
    LineRule(
        "restrict-subscriptions-disabled",
        "HIGH",
        rx(r"DQL_RESTRICT_SUBSCRIPTIONS\s*=\s*false"),
        "Stateful LIMIT/ORDER BY subscriptions degrade sync; LIMIT bounds only the "
        "initial download",
        "query-sync",
        "Subscription Rules",
    ),
    LineRule(
        "subscription-query-arguments",
        "CRITICAL",
        rx(r"\bqueryArguments(JsonString)?\b", 0),
        "Reading queryArguments from ditto.sync.subscriptions can terminate the app for "
        "subscriptions without arguments (SDK 5.1.0); keep your own references",
        "query-sync",
        "Sync stop, close, and inspection",
    ),
    LineRule(
        "verbose-logging",
        "HIGH",
        rx(r"LogLevel\.verbose", 0),
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
        rx(r"TOMBSTONE_TTL_HOURS\s*="),
        "Tombstone TTL on a device must not exceed the Ditto Server TTL, and must be "
        "applied after every open",
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
        "await-sync-start",
        "MEDIUM",
        rx(r"await\s+[\w.]*\.sync\.(start|stop)\(\)", 0),
        "sync.start()/stop() return void in Dart; do not await them",
        "sdk-setup",
        "Starting and Stopping Sync",
        languages=("dart",),
    ),
    LineRule(
        "transaction-without-hint",
        "MEDIUM",
        rx(r"\.transaction\(\s*\(", 0),
        "Transaction without a hint (check whether hint: follows the callback); long "
        "transactions are logged by hint",
        "transactions-attachments",
        "Transaction Rules",
        languages=("dart",),
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
            if rule.languages and language not in rule.languages:
                continue
            if rule.requires_dql and not DQL_KEYWORDS.search(line):
                continue
            if not rule.pattern.search(line):
                continue
            if rule.unless and rule.unless.search(line):
                continue
            yield Finding(path, number, rule.severity, rule.rule, rule.message,
                          rule.skill, rule.guide, line.strip())


def window(lines: List[str], start: int, size: int) -> str:
    return "\n".join(lines[start:start + size])


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
                          "nearby; unconsumed results stay in memory (SDK 5.1.0)",
                          "query-sync", "Store Observers in Flutter", line.strip())


TRANSACTION_CALL = re.compile(r"\.transaction\s*\(")
INSIDE_TRANSACTION = re.compile(r"\.store\.execute\s*\(|\.transaction\s*\(")


def scan_transactions(path: str, lines: List[str]) -> Iterable[Finding]:
    """store.execute or a nested transaction inside a transaction callback."""
    for index, line in enumerate(lines):
        if is_comment(line) or not TRANSACTION_CALL.search(line):
            continue
        depth = 0
        opened = False
        for offset, body in enumerate(lines[index:index + 80]):
            if offset > 0 and not is_comment(body) and depth > 0 and INSIDE_TRANSACTION.search(body):
                yield Finding(path, index + offset + 1, "CRITICAL", "execute-inside-transaction",
                              "ditto.store.execute inside a transaction callback (throws in Flutter, "
                              "can deadlock elsewhere) or a nested read-write transaction (deadlocks; "
                              "Flutter has no guard); use tx.execute",
                              "transactions-attachments", "Transaction Rules", body.strip())
            depth += body.count("{") - body.count("}")
            opened = opened or depth > 0
            if opened and depth <= 0:
                break


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


FILE_SCANNERS: List[Callable[[str, str, List[str]], Iterable[Finding]]] = [
    scan_lines,
    lambda path, language, lines: scan_subscriptions(path, lines),
    scan_observers,
    lambda path, language, lines: scan_transactions(path, lines),
    scan_lifecycle,
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
     "`.store.execute(` or `.transaction(` inside the braces of a `.transaction(` callback",
     "transactions-attachments", "Transaction Rules"),
    ("close-on-background", "CRITICAL",
     "`.close()` within 8 lines after `AppLifecycleState.paused` (Dart)",
     "sdk-setup", "Starting and Stopping Sync"),
    ("observer-onchange-only", "HIGH",
     "`registerObserver*(` with `onChange:` and no `.changes` in the same declaration (Dart)",
     "query-sync", "Store Observers in Flutter"),
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
        conditions = []
        if rule.pattern.flags & re.IGNORECASE:
            conditions.append("case-insensitive")
        if rule.requires_dql:
            conditions.append("line also contains a DQL keyword")
        if rule.unless:
            conditions.append(f"not if `{cell(rule.unless.pattern)}` matches")
        if rule.languages:
            conditions.append("only " + ", ".join(rule.languages))
        print(f"| `{rule.rule}` | {rule.severity} | `{cell(rule.pattern.pattern)}` | "
              f"{'; '.join(conditions) or '-'} | {rule.skill} | § {rule.guide} |")
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
