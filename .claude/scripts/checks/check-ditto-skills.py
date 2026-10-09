#!/usr/bin/env python3
"""Check the Ditto plugin Skills against the format rules and the guide.

Checks, for every plugins/ditto/skills/*/SKILL.md:
- frontmatter has only `name` (matching the directory) and `description`
- description length (error above 1,024 characters, warning above 450)
- SKILL.md size (error above 20,000 characters or 500 lines)
- every `§ Heading` citation in the skill's Markdown and code files names a
  heading of the guide
- every relative Markdown link points to an existing file
- audit/reference/scanner-rules.md matches `scan.py --list-rules`

Usage: python3 .claude/scripts/checks/check-ditto-skills.py
Exit code 1 when an error is found. Standard library only.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKILLS = ROOT / "plugins" / "ditto" / "skills"
GUIDE = ROOT / ".claude" / "guides" / "best-practices" / "ditto.md"

MAX_DESCRIPTION = 1024
TARGET_DESCRIPTION = 450
MAX_CHARS = 20_000
MAX_LINES = 500

# `§ Heading` in backticks, or § Heading up to a delimiter in plain text.
CITATION_DOUBLE = re.compile(r"``§ (.+?)``")
CITATION_CODE = re.compile(r"(?<!`)`§ ([^`]+)`(?!`)")
# Plain-text citations end at punctuation that headings may also contain, so
# they are checked as a prefix of a heading.
CITATION_TEXT = re.compile(r"(?<![`{])§ ([A-Za-z][^`|\]\n,;(){}]*)")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")

errors: list[str] = []
warnings: list[str] = []


def guide_headings() -> set[str]:
    headings = set()
    for line in GUIDE.read_text(encoding="utf-8").splitlines():
        match = re.match(r"#{1,6} (.+?)\s*$", line)
        if match:
            headings.add(match.group(1))
    return headings


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


def check_skill(skill: Path, headings: set[str]) -> None:
    skill_md = skill / "SKILL.md"
    text = skill_md.read_text(encoding="utf-8")
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

    for path in sorted(skill.rglob("*")):
        if path.is_symlink() or not path.is_file() or path.suffix not in {".md", ".dart", ".js", ".py"}:
            continue
        content = path.read_text(encoding="utf-8")
        relative = path.relative_to(SKILLS)
        exact = set(CITATION_DOUBLE.findall(content)) | set(CITATION_CODE.findall(content))
        for heading in sorted(exact):
            if heading not in headings and not heading.startswith("<"):
                errors.append(f"{relative}: § {heading} is not a heading of the guide")
        stripped = CITATION_CODE.sub("", CITATION_DOUBLE.sub("", content))
        for prefix in sorted({c.strip(" .") for c in CITATION_TEXT.findall(stripped)}):
            if prefix and not any(h.startswith(prefix) for h in headings):
                errors.append(f"{relative}: § {prefix} does not start a heading of the guide")
        if path.suffix != ".md":
            continue
        for target in LINK.findall(content):
            if re.match(r"[a-z]+:", target) or target.startswith("#"):
                continue
            file_part = target.split("#", 1)[0]
            if file_part and not (path.parent / file_part).exists():
                errors.append(f"{relative}: link target {target} does not exist")


def check_scanner_rules() -> None:
    audit = SKILLS / "audit"
    if not (audit / "scripts" / "scan.py").exists():
        return
    generated = subprocess.run(
        [sys.executable, str(audit / "scripts" / "scan.py"), "--list-rules"],
        capture_output=True, text=True, check=True,
    ).stdout
    if generated != (audit / "reference" / "scanner-rules.md").read_text(encoding="utf-8"):
        errors.append("audit/reference/scanner-rules.md is out of date; regenerate it with "
                      "python3 scripts/scan.py --list-rules > reference/scanner-rules.md")


def main() -> int:
    headings = guide_headings()
    for skill in sorted(p.parent for p in SKILLS.glob("*/SKILL.md")):
        check_skill(skill, headings)
    check_scanner_rules()
    for message in warnings:
        print(f"warning: {message}")
    for message in errors:
        print(f"error: {message}")
    print(f"{len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
