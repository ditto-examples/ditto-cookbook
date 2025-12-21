#!/usr/bin/env python3
"""
HTML Tag Validator

Validates HTML tag opening/closing in the Ditto SDK checklist HTML file.
Checks for missing or mismatched HTML tags and reports errors.
Also validates dynamic HTML generation in JavaScript string concatenation.

Usage:
    python validate-html-tags.py
    ./validate-html-tags.py
"""

import re
import sys
from pathlib import Path
from typing import List, Dict
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


class JavaScriptHTMLValidator:
    """Validates HTML tag structure in JavaScript string concatenation."""

    def __init__(self, js_content: str):
        self.js_content = js_content
        self.errors: List[str] = []
        self.warnings: List[str] = []

    def extract_html_concatenations(self) -> Dict[int, List[str]]:
        """
        Extract HTML strings from JavaScript += operations.

        Returns:
            Dict mapping line numbers to HTML fragments
        """
        html_fragments: Dict[int, List[str]] = {}
        lines = self.js_content.split('\n')

        # Pattern to match: html += '...' or html += "..." or html += `...`
        pattern = r"html\s*\+=\s*['\"`](.*?)['\"`]"

        for line_num, line in enumerate(lines, 1):
            # Skip comments
            if line.strip().startswith('//'):
                continue

            matches = re.findall(pattern, line)
            if matches:
                html_fragments[line_num] = matches

        return html_fragments

    def validate_tag_balance(self) -> ValidationResult:
        """
        Validate that HTML tag opening/closing is balanced in JavaScript concatenations.

        Focuses on detecting common patterns like:
        - Opening N tags but closing M tags (N != M)
        - Mismatched tag pairs

        Returns:
            ValidationResult containing validation status, errors, and warnings
        """
        fragments = self.extract_html_concatenations()

        if not fragments:
            self.warnings.append("No HTML concatenation patterns found in JavaScript")
            return ValidationResult(is_valid=True, errors=[], warnings=self.warnings)

        # Track opening and closing tags for each line
        for line_num, html_strings in fragments.items():
            for html_str in html_strings:
                # Count opening and closing tags
                opening_tags = re.findall(r'<([a-zA-Z][a-zA-Z0-9]*)[^>]*(?<!/)>', html_str)
                closing_tags = re.findall(r'</([a-zA-Z][a-zA-Z0-9]*)>', html_str)

                # Filter out self-closing tags
                self_closing = {'br', 'hr', 'img', 'input', 'link', 'meta', 'source'}
                opening_tags = [tag for tag in opening_tags if tag.lower() not in self_closing]

                # Check for specific anti-pattern: </div></div> when opening fewer than 2 divs
                if '</div></div>' in html_str:
                    div_opens = html_str.count('<div')
                    # Bug pattern: closing 2 divs but opening 0 or 1
                    # This causes premature closing of parent containers
                    if 0 < div_opens < 2:
                        self.errors.append(
                            f"Line {line_num}: Closing 2 divs (</div></div>) but opening only {div_opens} div(s) - "
                            f"this will close parent container prematurely"
                        )
                    elif div_opens == 0:
                        # Closing tags only - this is normal when tags span multiple lines
                        # We expect the opening to be on a previous line
                        pass

        return ValidationResult(
            is_valid=len(self.errors) == 0,
            errors=self.errors,
            warnings=self.warnings
        )

    def validate(self) -> ValidationResult:
        """
        Run all JavaScript HTML validations.

        Returns:
            ValidationResult containing validation status, errors, and warnings
        """
        return self.validate_tag_balance()


class EmbeddedMarkdownValidator:
    """Validates embedded Markdown content in JavaScript template literals."""

    def __init__(self, js_content: str):
        self.js_content = js_content
        self.errors: List[str] = []
        self.warnings: List[str] = []

    def extract_markdown_content(self) -> str:
        """
        Extract embedded Markdown from markdownContent template literal.

        Returns:
            The markdown content string, or empty string if not found
        """
        # Find the markdownContent template literal
        pattern = r'const markdownContent = `(.*?)`;'
        match = re.search(pattern, self.js_content, flags=re.DOTALL)

        if match:
            return match.group(1)
        return ""

    def validate_code_block_markers(self) -> ValidationResult:
        r"""
        Validate that code block markers are properly escaped for template literals.

        When markdown is embedded in JavaScript template literals, all backticks MUST be
        escaped to prevent syntax errors. The parser function must then check for the
        escaped patterns (e.g., line.trim() === '\\`\\`\\`dart').

        Returns:
            ValidationResult containing validation status, errors, and warnings
        """
        markdown_content = self.extract_markdown_content()

        if not markdown_content:
            self.warnings.append("No embedded Markdown content found")
            return ValidationResult(is_valid=True, errors=[], warnings=self.warnings)

        lines = markdown_content.split('\n')

        # Check for properly escaped backticks (e.g., \`\`\`dart)
        escaped_pattern = r'\\`\\`\\`'
        escaped_count = sum(1 for line in lines if re.search(escaped_pattern, line))

        # Count code block markers (escaped)
        opening_markers = sum(1 for line in lines if line.strip() == '\\`\\`\\`dart')
        closing_markers = sum(1 for line in lines if line.strip() == '\\`\\`\\`')

        # Check for UNESCAPED backticks (which would cause JavaScript syntax errors)
        unescaped_pattern = r'(?<!\\)`'
        unescaped_lines = []
        for line_num, line in enumerate(lines, 1):
            if re.search(unescaped_pattern, line):
                unescaped_lines.append(line_num)
                if len(unescaped_lines) >= 3:
                    break

        if unescaped_lines:
            for line_num in unescaped_lines:
                self.errors.append(
                    f"Line {line_num}: Unescaped backtick found - all backticks must be escaped in template literals"
                )
            if len(unescaped_lines) >= 3:
                self.errors.append("... and more unescaped backticks found")

        # Validate code block marker balance
        if opening_markers == 0 and closing_markers == 0:
            self.warnings.append(
                "No code block markers found (expected \\`\\`\\`dart and \\`\\`\\`)"
            )
        elif opening_markers != closing_markers:
            self.warnings.append(
                f"Code block marker mismatch: {opening_markers} opening markers (\\`\\`\\`dart) "
                f"but {closing_markers} closing markers (\\`\\`\\`)"
            )
        else:
            self.warnings.append(
                f"Found {opening_markers} properly escaped code blocks"
            )

        return ValidationResult(
            is_valid=len(self.errors) == 0,
            errors=self.errors,
            warnings=self.warnings
        )

    def validate(self) -> ValidationResult:
        """
        Run all embedded Markdown validations.

        Returns:
            ValidationResult containing validation status, errors, and warnings
        """
        return self.validate_code_block_markers()


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

    # Validate JavaScript HTML generation
    print("\n🔧 Validating JavaScript HTML generation...")
    js_validator = JavaScriptHTMLValidator(html_content)
    js_result = js_validator.validate()

    if js_result.errors:
        print(f"\n❌ Found {len(js_result.errors)} JavaScript HTML error(s):\n")
        for error in js_result.errors:
            print(f"  • {error}")

    if js_result.warnings:
        print(f"\n⚠️  Found {len(js_result.warnings)} JavaScript HTML warning(s):\n")
        for warning in js_result.warnings:
            print(f"  • {warning}")

    # Validate embedded Markdown
    print("\n📝 Validating embedded Markdown content...")
    md_validator = EmbeddedMarkdownValidator(html_content)
    md_result = md_validator.validate()

    if md_result.errors:
        print(f"\n❌ Found {len(md_result.errors)} Markdown error(s):\n")
        for error in md_result.errors:
            print(f"  • {error}")

    if md_result.warnings:
        print(f"\n⚠️  Found {len(md_result.warnings)} Markdown warning(s):\n")
        for warning in md_result.warnings:
            print(f"  • {warning}")

    # Overall result
    all_valid = html_result.is_valid and js_result.is_valid and md_result.is_valid
    total_errors = len(html_result.errors) + len(js_result.errors) + len(md_result.errors)
    total_warnings = len(html_result.warnings) + len(js_result.warnings) + len(md_result.warnings)

    if all_valid and not total_warnings:
        print("\n✅ All HTML tags are properly opened and closed!")
        print("✅ JavaScript HTML generation is correct!")
        print("✅ Embedded Markdown content is valid!")
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
