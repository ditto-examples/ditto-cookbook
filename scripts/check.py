#!/usr/bin/env python3
"""Check the Ditto guide, the plugin Skills, the checklist, and Markdown links.

Checks:
- every heading of the guide (knowledge/*.md, knowledge/observations/*.md,
  best-practices/*.md, and best-practices/platforms/*.md) is unique across
  its pages, so that a `§ Heading` citation names one section
- every plugins/ditto/skills/*/SKILL.md: frontmatter with only `name`
  (matching the directory) and `description`, the description length (error
  above 1,024 characters, warning above 450), and the size (error above
  20,000 characters or 500 lines)
- every `§ Heading` citation in the Skills' Markdown, DQL, and code files
  (Dart, JavaScript, TypeScript, Kotlin, Swift, Python) names a heading of
  the guide
- every section that a checklist item names under "Best-practices guide" is
  a heading of the guide
- every line of the guide that reports an observation ("in our testing")
  outside the knowledge entry that describes it links to that entry
- every knowledge entry of an observation (a section with an "Observed on"
  row) has a "Setup" row and a "Used in" line, and the "Used in" line lists
  exactly the sections of other pages that link to the entry
- every knowledge page with observation entries has an "In brief" list that
  links to each of them
- every relative link in the repository's Markdown files is well formed and points to an
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
GUIDE_DIRS = ("knowledge", "knowledge/observations", "best-practices", "best-practices/platforms")
SKILLS = ROOT / "plugins" / "ditto" / "skills"
CHECKLIST = ROOT / "checklist" / "ditto-implementation-checklist.md"

# The Skill files whose `§ Heading` citations are checked: Markdown, the
# examples of every SDK (Dart, JavaScript, TypeScript, Kotlin, Swift), DQL
# examples, and scripts.
SKILL_FILE_SUFFIXES = {".md", ".sql", ".dart", ".js", ".mjs", ".jsx", ".ts", ".tsx", ".kt", ".swift", ".py"}

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

# An observation from testing, as the best practices report it.
OBSERVATION = re.compile(r"\bin (?:our )?testing\b", re.IGNORECASE)
OBSERVED_ON = "| Observed on |"
# The phrase itself, quoted, as when a page explains what it means.
QUOTED_PHRASE = re.compile(r'"in (?:our )?testing"', re.IGNORECASE)
SETUP = "| Setup |"
USED_IN = "**Used in:**"


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
        text = path.read_text(encoding="utf-8")
        for number, line in prose_lines(text):
            prose = INLINE_CODE.sub("code", line)
            if prose.count("](") != len(LINK.findall(prose)):
                errors.append(f"{path.relative_to(root)}:{number}: a malformed link (a \"](\" that does not "
                              "start a link, such as a target without its closing parenthesis)")
        for number, target in parse_links(text):
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


def knowledge_pages(root: Path) -> list[Path]:
    """The pages of knowledge/: concepts and reference, and the observation pages below it."""
    return [page for page in guide_pages(root) if page.relative_to(root).parts[0] == "knowledge"]


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



def observation_sections(text: str) -> list[tuple[int, str, list[tuple[int, str]]]]:
    """The sections of a page that are observation entries: line number, anchor, and lines.

    A section runs from a heading to the next heading of any level. It is an
    observation entry when one of its lines is an "Observed on" table row.
    """
    sections: list[tuple[int, str, list[tuple[int, str]]]] = []
    seen: set[str] = set()
    current: tuple[int, str, list[tuple[int, str]]] | None = None
    for number, line in prose_lines(text):
        match = HEADING.match(line)
        if match:
            base = anchor = slugify(match.group(1))
            count = 0
            while anchor in seen:
                count += 1
                anchor = f"{base}-{count}"
            seen.add(anchor)
            current = (number, anchor, [])
            sections.append(current)
        elif current:
            current[2].append((number, line))
    return [section for section in sections
            if any(line.startswith(OBSERVED_ON) for _, line in section[2])]


def observation_anchors(text: str) -> set[str]:
    """Anchors of the knowledge headings whose section has an "Observed on" table row."""
    return {anchor for _, anchor, _ in observation_sections(text)}


def check_observation_links(pages: list[Path], knowledge_pages: list[Path], root: Path) -> list[str]:
    """Lines that report an observation ("in our testing") must link to its knowledge entry.

    The knowledge pages describe each observation in an entry with an
    "Observed on" table; every other line of the guide that reports one (in
    the best practices, and on the concept and reference pages of knowledge)
    summarizes it and links to the entry. A link qualifies when it names such
    an entry, or a knowledge page that has entries. Lines inside an entry are
    the observation itself. Paragraphs, list items, and table rows are single
    lines.
    """
    observations = {page.resolve(): observation_anchors(page.read_text(encoding="utf-8"))
                    for page in knowledge_pages}
    errors = []
    for page in pages:
        text = page.read_text(encoding="utf-8")
        inside = {number for _, _, lines in observation_sections(text) for number, _ in lines}
        for number, line in prose_lines(text):
            prose = QUOTED_PHRASE.sub("", INLINE_CODE.sub("code", line))
            if number in inside or not OBSERVATION.search(prose):
                continue
            if not any(links_to_observation(page, target, observations)
                       for _, target in parse_links(line)):
                errors.append(f"{page.relative_to(root)}:{number}: an observation without a link "
                              "to the knowledge entry that describes it")
    return errors


def links_to_observation(page: Path, target: str, observations: dict[Path, set[str]]) -> bool:
    path, _, anchor = unquote(target).partition("#")
    if SCHEME.match(path):
        return False
    anchors = observations.get((page.parent / path).resolve() if path else page.resolve())
    return bool(anchors) and (not anchor or anchor in anchors)


def check_observation_entries(knowledge_pages: list[Path], root: Path) -> list[str]:
    """Every observation entry has a "Setup" row and a "Used in" line ("none yet" if unused)."""
    errors = []
    for page in knowledge_pages:
        for number, _, lines in observation_sections(page.read_text(encoding="utf-8")):
            for mark, name in ((SETUP, "Setup row"), (USED_IN, "Used in line")):
                if not any(line.startswith(mark) for _, line in lines):
                    errors.append(f"{page.relative_to(root)}:{number}: the observation entry has no {name}")
    return errors


IN_BRIEF = "**In brief**"


def check_in_brief(knowledge_pages: list[Path], root: Path) -> list[str]:
    """A page with observation entries starts with an "In brief" list that links to every entry."""
    errors = []
    for page in knowledge_pages:
        text = page.read_text(encoding="utf-8")
        entries = observation_sections(text)
        if not entries:
            continue
        lines = list(prose_lines(text))
        start = next((number for number, line in lines if line.strip() == IN_BRIEF), None)
        if start is None:
            errors.append(f"{page.relative_to(root)}: a page with observation entries has no {IN_BRIEF} list")
            continue
        end = next((number for number, line in lines if number > start and line.startswith("## ")), len(text))
        named = {target.partition("#")[2] for number, line in lines if start < number < end
                 for _, target in parse_links(line) if target.startswith("#")}
        for number, anchor, _ in entries:
            if anchor not in named:
                errors.append(f"{page.relative_to(root)}:{number}: the entry #{anchor} is missing from "
                              f"the page's {IN_BRIEF} list")
    return errors


def check_used_in(pages: list[Path], knowledge_pages: list[Path], root: Path) -> list[str]:
    """An observation entry's "Used in" lists exactly the sections that link to it.

    Every section that links to an entry is listed, and every listed section
    links to it. A section is the text under one heading, without its
    subsections. Links from the entry's own page (its summary and other
    entries) and from inside other entries do not count. A "Used in" link
    without an anchor stands for every section of that page.
    """
    used_in: dict[tuple[Path, str], tuple[str, set[tuple[Path, str]]]] = {}
    used_in_lines: dict[tuple[Path, str], int] = {}
    for page in knowledge_pages:
        for _, anchor, lines in observation_sections(page.read_text(encoding="utf-8")):
            listed = set()
            for number, line in lines:
                if line.startswith(USED_IN):
                    used_in_lines[(page.resolve(), anchor)] = number
                    for _, target in parse_links(line):
                        path, _, section = unquote(target).partition("#")
                        listed.add(((page.parent / path).resolve() if path else page.resolve(), section))
            used_in[(page.resolve(), anchor)] = (f"{page.relative_to(root)}#{anchor}", listed)
    linked: dict[tuple[Path, str], set[tuple[Path, str]]] = {entry: set() for entry in used_in}
    errors = []
    for page in pages:
        text = page.read_text(encoding="utf-8")
        inside = {number for _, _, lines in observation_sections(text) for number, _ in lines}
        seen: set[str] = set()
        section = ""
        for number, line in prose_lines(text):
            match = HEADING.match(line)
            if match:
                base = section = slugify(match.group(1))
                count = 0
                while section in seen:
                    count += 1
                    section = f"{base}-{count}"
                seen.add(section)
                continue
            if number in inside:
                continue
            for _, target in parse_links(line):
                path, _, anchor = unquote(target).partition("#")
                if SCHEME.match(path):
                    continue
                entry = ((page.parent / path).resolve() if path else page.resolve(), anchor)
                if entry not in used_in or entry[0] == page.resolve():
                    continue
                name, listed = used_in[entry]
                linked[entry].update({(page.resolve(), section), (page.resolve(), "")})
                if (page.resolve(), section) not in listed and (page.resolve(), "") not in listed:
                    errors.append(f"{page.relative_to(root)}:{number}: links to the observation {name}, "
                                  f"whose Used in does not list the section #{section}")
    scanned = {page.resolve() for page in pages}
    for entry, (name, listed) in used_in.items():
        knowledge_page = entry[0]
        for target_page, section in sorted(listed):
            if target_page not in scanned or (target_page, section) in linked[entry]:
                continue
            target = Path(os.path.relpath(target_page, root.resolve())).as_posix() + (f"#{section}" if section else "")
            errors.append(f"{knowledge_page.relative_to(root.resolve())}:{used_in_lines[entry]}: "
                          f"the Used in of {name} lists {target}, which does not link to the entry")
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
            if not path.is_symlink() and path.suffix in SKILL_FILE_SUFFIXES:
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
    knowledge = knowledge_pages(ROOT)
    errors += check_observation_links(pages, knowledge, ROOT)
    errors += check_observation_entries(knowledge, ROOT)
    errors += check_used_in(pages, knowledge, ROOT)
    errors += check_in_brief(knowledge, ROOT)
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
