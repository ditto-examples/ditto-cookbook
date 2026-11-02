#!/usr/bin/env python3
"""Check the Ditto guide, the plugin Skills, the checklist, and Markdown links.

Checks:
- every heading of the guide (knowledge/*.md and best-practices/*.md) is
  unique across its pages, so that a `§ Heading` citation names one section
- every plugins/ditto/skills/*/SKILL.md: frontmatter with only `name`
  (matching the directory) and `description`, the description length (error
  above 1,024 characters, warning above 450), and the size (error above
  20,000 characters or 500 lines)
- every `§ Heading` citation in the Skills' Markdown and code files names a
  heading of the guide
- every section that a checklist item names under "Best-practices guide" is
  a heading of the guide
- every relative link in the repository's Markdown files points to an
  existing file, and every #anchor to an existing heading (GitHub anchors)
- audit/reference/scanner-rules.md matches `scan.py --list-rules`

Usage: python3 scripts/check.py
Exit code 1 when an error is found. Standard library only.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterator
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
GUIDE_DIRS = ("knowledge", "best-practices")
SKILLS = ROOT / "plugins" / "ditto" / "skills"
CHECKLIST = ROOT / "checklist" / "ditto-implementation-checklist.md"

MAX_DESCRIPTION = 1024
TARGET_DESCRIPTION = 450
MAX_CHARS = 20_000
MAX_LINES = 500

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
HEADING = re.compile(r"^ {0,3}#{1,6}[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$")
INLINE_CODE = re.compile(r"(`+)(.+?)\1")
# Inline links and images. Reference-style links and targets with spaces are
# not recognized; the repository uses neither.
LINK = re.compile(r"!?\[(?:[^\]\\]|\\.)*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
SCHEME = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*:")
# A heading may be cited without its trailing label, such as "(SDK 5.1+)".
LABEL = re.compile(r" \([^)]*\)$")

# `§ Heading` in backticks, or § Heading up to a delimiter in plain text.
CITATION_DOUBLE = re.compile(r"``§ (.+?)``")
CITATION_CODE = re.compile(r"(?<!`)`§ ([^`]+)`(?!`)")
# Plain-text citations end at punctuation that headings may also contain, so
# they are checked as a prefix of a heading.
CITATION_TEXT = re.compile(r"(?<![`{])§ ([A-Za-z][^`|\]\n,;(){}]*)")

CHECKLIST_FIELD = "**Best-practices guide:**"


# --- Markdown -----------------------------------------------------------------


def prose_lines(text: str) -> Iterator[tuple[int, str]]:
    """Yields (line number, line) for the lines outside fenced code blocks."""
    fence = ""
    for number, line in enumerate(text.splitlines(), 1):
        match = FENCE.match(line)
        if fence:
            if (match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence)
                    and not line[match.end():].strip()):
                fence = ""
            continue
        if match:
            fence = match.group(1)
            continue
        yield number, line


def parse_headings(text: str) -> list[tuple[int, str]]:
    return [(number, match.group(1)) for number, line in prose_lines(text)
            if (match := HEADING.match(line))]


def slugify(heading: str) -> str:
    """The anchor that GitHub generates for a heading."""
    return "".join("-" if ch == " " else ch for ch in heading.lower()
                   if ch.isalnum() or ch in " -_")


def anchors(text: str) -> set[str]:
    seen: set[str] = set()
    for _, heading in parse_headings(text):
        base = slug = slugify(heading)
        count = 0
        while slug in seen:
            count += 1
            slug = f"{base}-{count}"
        seen.add(slug)
    return seen


def parse_links(text: str) -> list[tuple[int, str]]:
    """Inline link and image targets outside code, as (line number, target)."""
    links = []
    for number, line in prose_lines(text):
        for match in LINK.finditer(INLINE_CODE.sub("code", line)):
            links.append((number, match.group(1)))
    return links


def check_links(files: list[Path], root: Path) -> list[str]:
    errors = []
    anchor_cache: dict[Path, set[str]] = {}
    for path in files:
        for number, target in parse_links(path.read_text(encoding="utf-8")):
            if SCHEME.match(target):
                continue
            file_part, _, anchor = target.partition("#")
            destination = path.parent / unquote(file_part) if file_part else path
            where = f"{path.relative_to(root)}:{number}"
            if not destination.exists():
                errors.append(f"{where}: link target {target} does not exist")
                continue
            if anchor and destination.is_file() and destination.suffix == ".md":
                key = destination.resolve()
                if key not in anchor_cache:
                    anchor_cache[key] = anchors(destination.read_text(encoding="utf-8"))
                if anchor not in anchor_cache[key]:
                    errors.append(f"{where}: link target {target} names no heading")
    return errors


def markdown_files(root: Path) -> list[Path]:
    """Tracked and untracked, not ignored Markdown files; symbolic links are left out."""
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.md"],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout
    paths = {root / name for name in listed.split("\0") if name}
    return sorted(path for path in paths if path.is_file() and not path.is_symlink())


# --- The guide ----------------------------------------------------------------


def guide_pages(root: Path) -> list[Path]:
    return [page for directory in GUIDE_DIRS for page in sorted((root / directory).glob("*.md"))]


def guide_headings(pages: list[Path]) -> set[str]:
    headings = set()
    for page in pages:
        for _, heading in parse_headings(page.read_text(encoding="utf-8")):
            headings.update({heading, heading.replace("`", "")})
    return headings


def check_unique_headings(pages: list[Path], root: Path) -> list[str]:
    locations: dict[str, list[str]] = {}
    for page in pages:
        for number, heading in parse_headings(page.read_text(encoding="utf-8")):
            locations.setdefault(heading, []).append(f"{page.relative_to(root)}:{number}")
    return [f"heading {heading!r} appears more than once in the guide: {', '.join(places)}"
            for heading, places in locations.items() if len(places) > 1]


def unknown_citations(text: str, headings: set[str]) -> list[str]:
    messages = []
    exact = set(CITATION_DOUBLE.findall(text)) | set(CITATION_CODE.findall(text))
    for heading in sorted(exact):
        if heading not in headings and not heading.startswith("<"):
            messages.append(f"§ {heading} is not a heading of the guide")
    stripped = CITATION_CODE.sub("", CITATION_DOUBLE.sub("", text))
    for prefix in sorted({c.strip(" .") for c in CITATION_TEXT.findall(stripped)}):
        if prefix and not any(h.startswith(prefix) for h in headings):
            messages.append(f"§ {prefix} does not start a heading of the guide")
    return messages


def unknown_sections(names: str, headings: set[str]) -> list[str]:
    """The names in a comma-separated list that are not headings. Headings may contain commas."""
    candidates = sorted(headings | {LABEL.sub("", h) for h in headings}, key=len, reverse=True)
    unknown = []
    rest = names.replace("`", "").strip().rstrip(".")
    while rest:
        for heading in candidates:
            if rest == heading or rest.startswith(heading + ", "):
                rest = rest[len(heading):].removeprefix(", ")
                break
        else:
            name, _, rest = rest.partition(", ")
            unknown.append(name)
    return unknown


def check_checklist_sections(checklist: Path, headings: set[str], root: Path) -> list[str]:
    errors = []
    for number, line in prose_lines(checklist.read_text(encoding="utf-8")):
        if line.startswith(CHECKLIST_FIELD):
            for name in unknown_sections(line[len(CHECKLIST_FIELD):], headings):
                errors.append(f"{checklist.relative_to(root)}:{number}: section {name} "
                              "is not a heading of the guide")
    return errors


# --- Skills -------------------------------------------------------------------


def frontmatter(text: str) -> dict[str, str]:
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match:
        return {}
    fields: dict[str, str] = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        if key and not key.startswith(" "):
            fields[key.strip()] = value.strip().strip('"')
    return fields


def skill_files(skill: Path) -> Iterator[Path]:
    """The Skill's own files, without the guide pages that it links to."""
    for directory, subdirectories, files in os.walk(skill):
        subdirectories.sort()
        for name in sorted(files):
            path = Path(directory) / name
            if not path.is_symlink() and path.suffix in {".md", ".dart", ".js", ".py"}:
                yield path


def check_skill(skill: Path, headings: set[str]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    text = (skill / "SKILL.md").read_text(encoding="utf-8")
    fields = frontmatter(text)
    name = skill.name
    if set(fields) != {"name", "description"}:
        errors.append(f"{name}: frontmatter keys {sorted(fields)}; expected name and description")
    if fields.get("name") != name:
        errors.append(f"{name}: frontmatter name {fields.get('name')!r} does not match the directory")
    description = fields.get("description", "")
    if len(description) > MAX_DESCRIPTION:
        errors.append(f"{name}: description has {len(description)} characters (max {MAX_DESCRIPTION})")
    elif len(description) > TARGET_DESCRIPTION:
        warnings.append(f"{name}: description has {len(description)} characters (target {TARGET_DESCRIPTION})")
    if len(text) > MAX_CHARS or text.count("\n") > MAX_LINES:
        errors.append(f"{name}: SKILL.md has {len(text)} characters and {text.count(chr(10))} lines "
                      f"(max {MAX_CHARS} and {MAX_LINES})")
    for path in skill_files(skill):
        relative = path.relative_to(skill.parent)
        for message in unknown_citations(path.read_text(encoding="utf-8"), headings):
            errors.append(f"{relative}: {message}")
    return errors, warnings


def check_scanner_rules(skills: Path) -> list[str]:
    audit = skills / "audit"
    if not (audit / "scripts" / "scan.py").exists():
        return []
    generated = subprocess.run(
        [sys.executable, str(audit / "scripts" / "scan.py"), "--list-rules"],
        capture_output=True, text=True, check=True,
    ).stdout
    if generated != (audit / "reference" / "scanner-rules.md").read_text(encoding="utf-8"):
        return ["audit/reference/scanner-rules.md is out of date; regenerate it with "
                "python3 scripts/scan.py --list-rules > reference/scanner-rules.md"]
    return []


# --- Main ---------------------------------------------------------------------


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    pages = guide_pages(ROOT)
    headings = guide_headings(pages)
    errors += check_unique_headings(pages, ROOT)
    for skill in sorted(p.parent for p in SKILLS.glob("*/SKILL.md")):
        skill_errors, skill_warnings = check_skill(skill, headings)
        errors += skill_errors
        warnings += skill_warnings
    errors += check_checklist_sections(CHECKLIST, headings, ROOT)
    errors += check_links(markdown_files(ROOT), ROOT)
    errors += check_scanner_rules(SKILLS)
    for message in warnings:
        print(f"warning: {message}")
    for message in errors:
        print(f"error: {message}")
    print(f"{len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
