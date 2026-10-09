#!/usr/bin/env python3
"""
HTML Tag Validator

Validates HTML tag opening/closing in the generated Ditto SDK checklist HTML
file and reports missing or mismatched tags. (The Japanese HTML fragments that
are swapped in at runtime are checked by build-checklist.py.)

Usage:
    python3 validate-html-tags.py
"""

import re
import sys
from pathlib import Path
from typing import List, Tuple
from dataclasses import dataclass


@dataclass
class ValidationResult:
    """Result of a validation check."""
    is_valid: bool
    errors: List[str]
    warnings: List[str]


class HTMLValidator:
    """Validates HTML tag structure in rendered HTML."""

    # Self-closing tags that don't need closing tags
    SELF_CLOSING_TAGS = {
        'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
        'link', 'meta', 'param', 'source', 'track', 'wbr'
    }

    # Tags that can be optionally self-closed or have implicit closing
    OPTIONAL_CLOSE_TAGS = {
        'li', 'dt', 'dd', 'p', 'rt', 'rp', 'optgroup', 'option',
        'colgroup', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th'
    }

    def __init__(self, html_content: str):
        self.html_content = html_content
        self.errors: List[str] = []
        self.warnings: List[str] = []

    def validate(self) -> ValidationResult:
        """
        Validate HTML tag structure.

        Returns:
            ValidationResult containing validation status, errors, and warnings
        """
        # Remove comments
        content = re.sub(r'<!--.*?-->', '', self.html_content, flags=re.DOTALL)

        # Remove script and style content (but keep tags)
        content = re.sub(r'<script[^>]*>.*?</script>', '<script></script>', content, flags=re.DOTALL | re.IGNORECASE)
        content = re.sub(r'<style[^>]*>.*?</style>', '<style></style>', content, flags=re.DOTALL | re.IGNORECASE)

        # Find all tags
        tag_pattern = r'<(/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*(/?)>'
        tags = re.finditer(tag_pattern, content)

        tag_stack: List[Tuple[str, int]] = []
        line_number = 1

        for match in tags:
            is_closing = match.group(1) == '/'
            tag_name = match.group(2).lower()
            is_self_closing = match.group(3) == '/' or tag_name in self.SELF_CLOSING_TAGS

            # Update line number
            line_number += content[:match.start()].count('\n') - (line_number - 1)

            if is_closing:
                # Closing tag
                if not tag_stack:
                    self.errors.append(
                        f"Line ~{line_number}: Closing tag </{tag_name}> without matching opening tag"
                    )
                elif tag_stack[-1][0] != tag_name:
                    # Check if there's a matching tag further up the stack (possible nesting error)
                    found_match = False
                    for i in range(len(tag_stack) - 1, -1, -1):
                        if tag_stack[i][0] == tag_name:
                            found_match = True
                            # Report all unclosed tags between current and matching tag
                            for j in range(len(tag_stack) - 1, i, -1):
                                self.errors.append(
                                    f"Line ~{tag_stack[j][1]}: Unclosed tag <{tag_stack[j][0]}> "
                                    f"(expected before </{tag_name}> on line ~{line_number})"
                                )
                            # Remove all tags from matching tag onwards
                            tag_stack = tag_stack[:i]
                            break

                    if not found_match:
                        self.errors.append(
                            f"Line ~{line_number}: Closing tag </{tag_name}> doesn't match "
                            f"opening tag <{tag_stack[-1][0]}> from line ~{tag_stack[-1][1]}"
                        )
                        tag_stack.pop()
                else:
                    tag_stack.pop()

            elif not is_self_closing:
                # Opening tag (not self-closing)
                tag_stack.append((tag_name, line_number))

        # Check for unclosed tags
        for tag_name, line_num in tag_stack:
            if tag_name not in self.OPTIONAL_CLOSE_TAGS:
                self.errors.append(
                    f"Line ~{line_num}: Unclosed tag <{tag_name}>"
                )
            else:
                self.warnings.append(
                    f"Line ~{line_num}: Tag <{tag_name}> not explicitly closed (optional)"
                )

        return ValidationResult(
            is_valid=len(self.errors) == 0,
            errors=self.errors,
            warnings=self.warnings
        )


def main():
    """Main entry point."""
    script_dir = Path(__file__).parent
    html_file = script_dir / "ditto-sdk-checklist.html"

    if not html_file.exists():
        print(f"❌ Error: HTML file not found: {html_file}")
        sys.exit(1)

    print(f"🔍 Validating HTML tags in: {html_file.name}")
    print("-" * 60)

    try:
        html_content = html_file.read_text(encoding='utf-8')
    except Exception as e:
        print(f"❌ Error reading file: {e}")
        sys.exit(1)

    # Validate rendered HTML
    print("\n📄 Validating rendered HTML structure...")
    html_validator = HTMLValidator(html_content)
    html_result = html_validator.validate()

    if html_result.errors:
        print(f"\n❌ Found {len(html_result.errors)} HTML error(s):\n")
        for error in html_result.errors:
            print(f"  • {error}")

    if html_result.warnings:
        print(f"\n⚠️  Found {len(html_result.warnings)} HTML warning(s):\n")
        for warning in html_result.warnings:
            print(f"  • {warning}")

    # Overall result
    all_valid = html_result.is_valid
    total_errors = len(html_result.errors)
    total_warnings = len(html_result.warnings)

    if all_valid and not total_warnings:
        print("\n✅ All HTML tags are properly opened and closed!")
        print("\n📊 Summary:")
        print(f"  • File size: {len(html_content):,} bytes")
        print(f"  • Lines: {html_content.count(chr(10)) + 1:,}")
        sys.exit(0)
    elif all_valid:
        print(f"\n✅ No critical errors found ({total_warnings} warning(s) only)")
        sys.exit(0)
    else:
        print(f"\n❌ Validation failed with {total_errors} error(s)")
        sys.exit(1)


if __name__ == "__main__":
    main()
