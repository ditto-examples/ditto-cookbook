#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["Pygments>=2.18"]
# ///
"""
Build the Ditto SDK Implementation Checklist HTML.

This script:
1. Parses ditto-implementation-checklist.md (content source, English)
2. Loads translations.json (UI strings and Japanese text) and
   code-translations.json (code examples with Japanese comments)
3. Validates that the translations line up with the Markdown source
4. Injects pre-rendered HTML and the translation data into template.html
5. Writes the self-contained ditto-sdk-checklist.html

Usage:
    uv run build-checklist.py      # with syntax highlighting (Pygments)
    python3 build-checklist.py     # without Pygments: no syntax highlighting
"""

import html
import json
import re
import sys
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, List, Optional

# Syntax highlighting support
try:
    from pygments import highlight
    from pygments.formatters import HtmlFormatter
    from pygments.lexers import DartLexer, get_lexer_by_name
    PYGMENTS_AVAILABLE = True
except ImportError:
    PYGMENTS_AVAILABLE = False


class BuildError(Exception):
    """Raised when the sources are inconsistent and the build must stop."""


@dataclass
class CodeExample:
    """A code example block."""
    language: str
    code: str


@dataclass
class ChecklistItem:
    """A single checklist item."""
    title: str
    what_this_means: str
    why_this_matters: str
    guide_reference: str = ''
    code_example: Optional[CodeExample] = None


@dataclass
class Section:
    """A section containing multiple checklist items."""
    number: int
    title: str
    items: List[ChecklistItem] = field(default_factory=list)


@dataclass
class Metadata:
    """Document metadata from the blockquote at the top of the Markdown file."""
    version: str
    last_updated: str
    applies_to: str


# ==========================================================================
# Markdown parsing
# ==========================================================================

def inline_markdown_to_html(text: str) -> str:
    """Convert inline Markdown (code spans, bold, links) to escaped HTML."""
    # Code spans: `code`, or `` code with `backticks` `` (one padding space is stripped).
    parts = re.split(r'(``.+?``|`[^`]+`)', text)
    rendered = []
    for part in parts:
        span = re.fullmatch(r'``\s?(.+?)\s?``|`([^`]+)`', part)
        if span:
            code = span.group(1) if span.group(1) is not None else span.group(2)
            rendered.append(f'<code>{html.escape(code, quote=False)}</code>')
            continue
        part = html.escape(part, quote=False)
        part = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', part)
        part = re.sub(
            r'\[([^\]]+)\]\((https?://[^)\s]+)\)',
            r'<a href="\2" target="_blank" rel="noopener noreferrer">\1</a>',
            part,
        )
        rendered.append(part)
    return ''.join(rendered)


def block_markdown_to_html(text: str) -> str:
    """Convert paragraphs and bullet lists to HTML."""
    html_lines = []
    in_list = False
    for line in text.split('\n'):
        bullet = re.match(r'^[-*]\s+(.*)$', line)
        if bullet:
            if not in_list:
                html_lines.append('<ul>')
                in_list = True
            html_lines.append(f'<li>{inline_markdown_to_html(bullet.group(1))}</li>')
            continue
        if in_list:
            html_lines.append('</ul>')
            in_list = False
        if line.strip():
            html_lines.append(f'<p>{inline_markdown_to_html(line)}</p>')
    if in_list:
        html_lines.append('</ul>')
    return '\n'.join(html_lines)


class MarkdownParser:
    """Parse the Markdown checklist into structured data."""

    SECTION_RE = re.compile(r'^## Section (\d+): (.+)$')
    ITEM_RE = re.compile(r'^### ☐ (.+)$')
    FIELD_RE = re.compile(r'^\*\*(What this means|Why this matters|Best-practices guide):\*\*\s*(.*)$')

    def __init__(self, markdown_path: Path):
        self.lines = markdown_path.read_text(encoding='utf-8').split('\n')

    def parse_metadata(self) -> Metadata:
        """Read Version, Last Updated, and Applies to from the header blockquote."""
        values: Dict[str, str] = {}
        for line in self.lines:
            match = re.match(r'^>\s*\*\*([^*]+)\*\*:\s*(.+)$', line)
            if match:
                values[match.group(1).strip()] = match.group(2).strip()
            if line.startswith('## '):
                break
        missing = [key for key in ('Version', 'Last Updated', 'Applies to') if key not in values]
        if missing:
            raise BuildError(f'Missing header field(s) in the Markdown source: {", ".join(missing)}')
        return Metadata(
            version=values['Version'],
            last_updated=values['Last Updated'],
            applies_to=values['Applies to'],
        )

    def parse(self) -> List[Section]:
        """Parse the Markdown file into Section objects."""
        sections: List[Section] = []
        i = 0
        while i < len(self.lines):
            line = self.lines[i]
            section_match = self.SECTION_RE.match(line)
            if section_match:
                sections.append(Section(int(section_match.group(1)), section_match.group(2).strip()))
            else:
                item_match = self.ITEM_RE.match(line)
                if item_match:
                    if not sections:
                        raise BuildError(f'Line {i + 1}: checklist item outside of a section')
                    item, i = self._parse_item(i + 1, item_match.group(1).strip())
                    sections[-1].items.append(item)
                    continue
            i += 1
        return sections

    def _parse_item(self, start: int, title: str):
        """Parse one item; return it and the index of the first line after it."""
        fields: Dict[str, List[str]] = {'what': [], 'why': [], 'guide': []}
        keys = {
            'What this means': 'what',
            'Why this matters': 'why',
            'Best-practices guide': 'guide',
        }
        current = None
        code_example = None
        i = start

        while i < len(self.lines):
            line = self.lines[i]
            if re.match(r'^##+ ', line):
                break

            field_match = self.FIELD_RE.match(line)
            if field_match:
                current = keys[field_match.group(1)]
                if field_match.group(2):
                    fields[current].append(field_match.group(2))
            elif line.startswith('**Code Example**'):
                current = None
            elif line.strip().startswith('```'):
                language = line.strip()[3:].strip() or 'dart'
                code_lines = []
                i += 1
                while i < len(self.lines) and not self.lines[i].strip().startswith('```'):
                    code_lines.append(self.lines[i])
                    i += 1
                if code_example is not None:
                    raise BuildError(f'"{title}": more than one code block per item is not supported')
                code_example = CodeExample(language=language, code='\n'.join(code_lines))
                current = None
            elif line.strip() == '---':
                pass
            elif current and line.strip():
                fields[current].append(line)
            i += 1

        if not fields['what'] or not fields['why']:
            raise BuildError(f'"{title}": "What this means" and "Why this matters" are required')

        item = ChecklistItem(
            title=title,
            what_this_means=block_markdown_to_html('\n'.join(fields['what'])),
            why_this_matters=block_markdown_to_html('\n'.join(fields['why'])),
            guide_reference=html.escape(' '.join(fields['guide']).strip(), quote=False),
            code_example=code_example,
        )
        return item, i


# ==========================================================================
# Validation
# ==========================================================================

class _TagBalanceChecker(HTMLParser):
    VOID = {'br', 'hr', 'img', 'input', 'wbr'}

    def __init__(self):
        super().__init__()
        self.stack: List[str] = []
        self.errors: List[str] = []

    def handle_starttag(self, tag, attrs):
        if tag not in self.VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1] != tag:
            self.errors.append(f'unexpected </{tag}>')
        else:
            self.stack.pop()


def fragment_errors(fragment: str) -> List[str]:
    """Return tag-balance errors for an HTML fragment."""
    checker = _TagBalanceChecker()
    checker.feed(fragment)
    checker.close()
    return checker.errors + [f'unclosed <{tag}>' for tag in checker.stack]


def strip_comments(code: str, language: str) -> List[str]:
    """Remove line comments (outside string literals) and blank lines."""
    marker = {'dart': '//', 'sql': '--', 'yaml': '#'}.get(language)
    result = []
    for line in code.split('\n'):
        if marker:
            quote = None
            j = 0
            while j < len(line):
                ch = line[j]
                if quote:
                    if ch == '\\':
                        j += 2
                        continue
                    if ch == quote:
                        quote = None
                elif ch in '\'"':
                    quote = ch
                elif line.startswith(marker, j):
                    line = line[:j]
                    break
                j += 1
        if line.strip():
            result.append(line.rstrip())
    return result


def validate_translations(sections: List[Section], translations: dict, code_translations: dict) -> None:
    """Fail the build when the Japanese data does not line up with the Markdown source."""
    errors: List[str] = []
    items = [item for section in sections for item in section.items]
    ja = translations.get('ja', {})

    expected_lengths = {
        'sections': len(sections),
        'items': len(items),
        'whatMeansSections': len(items),
        'whyMattersSections': len(items),
    }
    for key, expected in expected_lengths.items():
        actual = len(ja.get(key, []))
        if actual != expected:
            errors.append(f'translations.json ja.{key} has {actual} entries; expected {expected}')

    for key in ('whatMeansSections', 'whyMattersSections'):
        for index, fragment in enumerate(ja.get(key, [])):
            for problem in fragment_errors(fragment):
                errors.append(f'translations.json ja.{key}[{index}]: {problem}')

    code_items = [item for item in items if item.code_example]
    blocks = {block['index']: block for block in code_translations.get('codeBlocks', [])}
    if sorted(blocks) != list(range(len(code_items))):
        errors.append(
            f'code-translations.json has blocks {sorted(blocks)}; '
            f'expected indexes 0..{len(code_items) - 1}'
        )
    for index, item in enumerate(code_items):
        block = blocks.get(index)
        if block is None:
            continue
        example = item.code_example
        if block['originalCode'] != example.code:
            errors.append(
                f'code-translations.json block {index} ("{item.title}"): '
                'originalCode differs from the Markdown code block'
            )
        elif strip_comments(block['translatedCode'], example.language) != strip_comments(example.code, example.language):
            errors.append(
                f'code-translations.json block {index} ("{item.title}"): '
                'translatedCode differs from the original outside of comments'
            )

    if errors:
        raise BuildError('Translations are out of sync:\n  - ' + '\n  - '.join(errors))


# ==========================================================================
# HTML generation
# ==========================================================================

def slugify(text: str) -> str:
    """Stable identifier for an item, used to save its checkbox state."""
    return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')


class HTMLGenerator:
    """Generate HTML from parsed sections."""

    def __init__(self, sections: List[Section]):
        self.sections = sections
        if PYGMENTS_AVAILABLE:
            self.code_formatter = HtmlFormatter(style='monokai', cssclass='highlight')
            self.pygments_css = self.code_formatter.get_style_defs('.highlight')
        else:
            self.code_formatter = None
            self.pygments_css = None

    def highlight_code(self, code: str, language: str) -> str:
        """Return syntax-highlighted (or escaped) HTML for the inside of <pre><code>."""
        if self.code_formatter:
            try:
                if language.lower() == 'dart':
                    lexer = DartLexer()
                else:
                    lexer = get_lexer_by_name(language.lower(), stripall=False)
                highlighted = highlight(code, lexer, self.code_formatter)
                # Pygments wraps the output in <div class="highlight"><pre>...</pre></div>;
                # the template provides its own <pre><code> wrapper.
                match = re.search(r'<pre>(.*?)</pre>', highlighted, re.DOTALL)
                return match.group(1) if match else highlighted
            except Exception as error:
                print(f'⚠️  Warning: Syntax highlighting failed for {language}: {error}')
        return html.escape(code, quote=False)

    def generate_sections_html(self) -> str:
        """Generate HTML for all sections."""
        item_index = 0
        code_index = 0
        parts = []
        for section in self.sections:
            items_html = []
            for item in section.items:
                items_html.append(self._item_html(item, item_index, code_index))
                item_index += 1
                if item.code_example:
                    code_index += 1
            parts.append(self._section_html(section, '\n'.join(items_html)))
        return '\n'.join(parts)

    def _section_html(self, section: Section, items_html: str) -> str:
        section_id = f'section-{section.number}'
        title = html.escape(section.title, quote=False)
        return f'''
    <section class="section" id="{section_id}">
      <h2 class="section-heading">
        <button type="button" class="section-header" aria-expanded="true" aria-controls="{section_id}-content">
          <span class="section-title"><span class="section-number">Section {section.number}:</span> {title}</span>
          <span class="section-progress" aria-hidden="true"></span>
          <span class="section-toggle" aria-hidden="true">▼</span>
        </button>
      </h2>
      <div class="section-content" id="{section_id}-content">
{items_html}
      </div>
    </section>'''

    def _item_html(self, item: ChecklistItem, item_index: int, code_index: int) -> str:
        checkbox_id = f'item-{slugify(item.title)}'
        code_html = ''
        if item.code_example:
            code_id = f'code-{code_index}'
            language = html.escape(item.code_example.language)
            code_html = f'''
            <div class="code-example">
              <div class="code-header">
                <span class="code-label"><span class="code-label-text">Code example</span> ({language})</span>
                <button type="button" class="code-toggle" aria-expanded="false" aria-controls="{code_id}">Show code</button>
              </div>
              <div class="code-content" id="{code_id}" hidden>
                <pre><code class="highlight" data-code-index="{code_index}">{self.highlight_code(item.code_example.code, item.code_example.language)}</code></pre>
              </div>
            </div>'''

        guide_html = ''
        if item.guide_reference:
            guide_html = f'''
            <p class="guide-reference"><span class="guide-label">Best-practices guide:</span> {item.guide_reference}</p>'''

        return f'''
        <article class="item" data-item-index="{item_index}">
          <div class="item-header">
            <input type="checkbox" class="item-checkbox" id="{checkbox_id}">
            <label class="item-title" for="{checkbox_id}">{html.escape(item.title, quote=False)}</label>
          </div>
          <div class="item-details">
            <div class="detail-section">
              <div class="detail-heading what-heading">What this means</div>
              <div class="detail-content what-content">
{item.what_this_means}
              </div>
            </div>
            <div class="detail-section">
              <div class="detail-heading why-heading">Why this matters</div>
              <div class="detail-content why-content">
{item.why_this_matters}
              </div>
            </div>{guide_html}{code_html}
          </div>
        </article>'''


# ==========================================================================
# Build orchestration
# ==========================================================================

class ChecklistBuilder:
    """Parse, validate, generate, inject, and write."""

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.markdown_path = base_dir / 'ditto-implementation-checklist.md'
        self.translations_path = base_dir / 'translations.json'
        self.code_translations_path = base_dir / 'code-translations.json'
        self.template_path = base_dir / 'template.html'
        self.output_path = base_dir / 'ditto-sdk-checklist.html'

    def build(self) -> None:
        print('🔨 Building Ditto SDK Checklist HTML...')
        if not PYGMENTS_AVAILABLE:
            print('⚠️  Pygments is not installed: code examples will not be syntax highlighted.')
            print('   Run "uv run build-checklist.py" to build with highlighting.')

        print('1️⃣  Parsing Markdown...')
        parser = MarkdownParser(self.markdown_path)
        metadata = parser.parse_metadata()
        sections = parser.parse()
        items = [item for section in sections for item in section.items]
        print(f'   ✓ Version {metadata.version}: {len(sections)} sections, {len(items)} items')

        print('2️⃣  Loading and validating translations...')
        translations = json.loads(self.translations_path.read_text(encoding='utf-8'))
        code_translations = json.loads(self.code_translations_path.read_text(encoding='utf-8'))
        validate_translations(sections, translations, code_translations)
        print('   ✓ Japanese text and code comments line up with the Markdown source')

        print('3️⃣  Generating HTML...')
        generator = HTMLGenerator(sections)
        sections_html = generator.generate_sections_html()

        code_items = [item for item in items if item.code_example]
        blocks = {block['index']: block for block in code_translations['codeBlocks']}
        translations['en']['sections'] = [
            f'<span class="section-number">Section {s.number}:</span> {html.escape(s.title, quote=False)}'
            for s in sections
        ]
        translations['en']['items'] = [item.title for item in items]
        translations['en']['whatMeansSections'] = [item.what_this_means for item in items]
        translations['en']['whyMattersSections'] = [item.why_this_matters for item in items]
        translations['en']['codeExamples'] = [
            generator.highlight_code(item.code_example.code, item.code_example.language)
            for item in code_items
        ]
        translations['ja']['codeExamples'] = [
            generator.highlight_code(blocks[index]['translatedCode'], item.code_example.language)
            for index, item in enumerate(code_items)
        ]

        print('4️⃣  Injecting into the template...')
        template = self.template_path.read_text(encoding='utf-8')
        replacements = {
            '/* INJECT_TRANSLATIONS_HERE */': json.dumps(translations, ensure_ascii=False, indent=2),
            '<!-- INJECT_SECTIONS_HERE -->': sections_html,
            '{{VERSION}}': html.escape(metadata.version),
            '{{LAST_UPDATED}}': html.escape(metadata.last_updated),
            '{{APPLIES_TO}}': inline_markdown_to_html(metadata.applies_to),
            '/* INJECT_PYGMENTS_CSS_HERE */': generator.pygments_css or '',
        }
        output = template
        for placeholder, value in replacements.items():
            if placeholder not in output:
                raise BuildError(f'Placeholder {placeholder} not found in {self.template_path.name}')
            output = output.replace(placeholder, value)

        print('5️⃣  Writing output file...')
        self.output_path.write_text(output, encoding='utf-8')
        print(f'\n✅ Build complete: {self.output_path.name} ({len(output):,} characters)')
        print('Next steps:')
        print('  1. Validate: python3 validate-html-tags.py')
        print('  2. Open ditto-sdk-checklist.html in a browser')


def main() -> int:
    try:
        ChecklistBuilder(Path(__file__).resolve().parent).build()
        return 0
    except BuildError as error:
        print(f'\n❌ Build failed: {error}')
        return 1


if __name__ == '__main__':
    sys.exit(main())
