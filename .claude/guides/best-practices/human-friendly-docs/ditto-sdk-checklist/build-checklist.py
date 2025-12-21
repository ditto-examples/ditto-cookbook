#!/usr/bin/env python3
"""
Build Ditto SDK Implementation Checklist HTML

This script:
1. Parses ditto-implementation-checklist.md (Markdown source)
2. Loads translations.json (English/Japanese translations)
3. Injects pre-rendered HTML sections into template.html
4. Outputs self-contained ditto-sdk-checklist.html

Usage:
    python build-checklist.py
    ./build-checklist.py
"""

import json
import re
from pathlib import Path
from typing import List, Dict, Optional
from dataclasses import dataclass

# Syntax highlighting support
try:
    from pygments import highlight
    from pygments.lexers import DartLexer, get_lexer_by_name
    from pygments.formatters import HtmlFormatter
    PYGMENTS_AVAILABLE = True
except ImportError:
    PYGMENTS_AVAILABLE = False
    print("⚠️  Warning: Pygments not installed. Code examples will not be syntax highlighted.")
    print("   Install with: pip install Pygments")


@dataclass
class CodeExample:
    """Represents a code example block."""
    language: str
    code: str


@dataclass
class ChecklistItem:
    """Represents a single checklist item."""
    title: str
    what_this_means: str
    why_this_matters: str
    code_example: Optional[CodeExample] = None


@dataclass
class Section:
    """Represents a section containing multiple checklist items."""
    number: int
    title: str
    items: List[ChecklistItem]


class MarkdownParser:
    """Parse Markdown checklist into structured data."""

    def __init__(self, markdown_path: Path):
        self.markdown_path = markdown_path
        self.content = markdown_path.read_text(encoding='utf-8')

    def parse(self) -> List[Section]:
        """Parse Markdown file into Section objects."""
        sections = []
        lines = self.content.split('\n')
        i = 0

        while i < len(lines):
            line = lines[i]

            # Match section header: ## Section N: Title
            section_match = re.match(r'^## Section (\d+): (.+)$', line)
            if section_match:
                section_num = int(section_match.group(1))
                section_title = section_match.group(2).strip()
                i += 1

                # Parse items in this section
                items = []
                while i < len(lines):
                    # Check if we've hit the next section
                    if re.match(r'^## Section \d+:', lines[i]):
                        break

                    # Match checklist item: ### ☐ Title
                    item_match = re.match(r'^### ☐ (.+)$', lines[i])
                    if item_match:
                        item_title = item_match.group(1).strip()
                        i += 1

                        # Parse item details
                        item = self._parse_item_details(lines, i, item_title)
                        items.append(item)

                        # Skip to next item/section (already advanced by _parse_item_details)
                        continue

                    i += 1

                sections.append(Section(number=section_num, title=section_title, items=items))
                continue

            i += 1

        return sections

    def _parse_item_details(self, lines: List[str], start_index: int, title: str) -> ChecklistItem:
        """Parse the details of a checklist item."""
        what_this_means = []
        why_this_matters = []
        code_example = None
        current_section = None
        i = start_index

        while i < len(lines):
            line = lines[i]

            # Stop at next item or section
            if re.match(r'^###? ', line):
                break

            # Match "What this means:" heading
            if re.match(r'^\*\*What this means:\*\*', line):
                current_section = 'what'
                # Extract content after the heading
                content_after = re.sub(r'^\*\*What this means:\*\* ', '', line)
                if content_after:
                    what_this_means.append(content_after)
                i += 1
                continue

            # Match "Why this matters:" heading
            if re.match(r'^\*\*Why this matters:\*\*', line):
                current_section = 'why'
                # Extract content after the heading
                content_after = re.sub(r'^\*\*Why this matters:\*\* ', '', line)
                if content_after:
                    why_this_matters.append(content_after)
                i += 1
                continue

            # Match "Code Example:" heading
            if re.match(r'^\*\*Code Example\*\*:', line):
                current_section = 'code'
                i += 1
                continue

            # Match code block start
            if line.strip().startswith('```'):
                language = line.strip()[3:].strip() or 'dart'
                code_lines = []
                i += 1

                # Collect code lines until closing ```
                while i < len(lines) and not lines[i].strip().startswith('```'):
                    code_lines.append(lines[i])
                    i += 1

                code_example = CodeExample(language=language, code='\n'.join(code_lines))
                i += 1  # Skip closing ```
                continue

            # Skip horizontal rules (Markdown: ---)
            if line.strip() == '---':
                i += 1
                continue

            # Add content to appropriate section
            if current_section == 'what' and line.strip():
                what_this_means.append(line)
            elif current_section == 'why' and line.strip():
                why_this_matters.append(line)

            i += 1

        # Convert lists to formatted HTML
        what_html = self._markdown_to_html('\n'.join(what_this_means))
        why_html = self._markdown_to_html('\n'.join(why_this_matters))

        return ChecklistItem(
            title=title,
            what_this_means=what_html,
            why_this_matters=why_html,
            code_example=code_example
        )

    def _markdown_to_html(self, text: str) -> str:
        """Convert simple Markdown to HTML."""
        if not text.strip():
            return ''

        # Convert horizontal rules (---) to <hr> tags
        # This is a defensive measure; horizontal rules should already be filtered out
        text = re.sub(r'^\s*---\s*$', '<hr>', text, flags=re.MULTILINE)

        # Convert **bold** to <strong>
        text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)

        # Convert `code` to <code> with HTML escaping
        def escape_code(match):
            code_content = match.group(1)
            # Escape HTML characters inside code
            escaped = (code_content
                      .replace('&', '&amp;')
                      .replace('<', '&lt;')
                      .replace('>', '&gt;'))
            return f'<code>{escaped}</code>'

        text = re.sub(r'`([^`]+)`', escape_code, text)

        # Convert bullet lists
        lines = text.split('\n')
        html_lines = []
        in_list = False

        for line in lines:
            # Check for bullet point
            if re.match(r'^[-*]\s+', line):
                if not in_list:
                    html_lines.append('<ul>')
                    in_list = True
                # Remove bullet marker and wrap in <li>
                content = re.sub(r'^[-*]\s+', '', line)
                html_lines.append(f'<li>{content}</li>')
            else:
                if in_list:
                    html_lines.append('</ul>')
                    in_list = False
                if line.strip():
                    html_lines.append(f'<p>{line}</p>')

        if in_list:
            html_lines.append('</ul>')

        return '\n'.join(html_lines)


class HTMLGenerator:
    """Generate HTML from parsed sections."""

    def __init__(self, sections: List[Section]):
        self.sections = sections

        # Configure Pygments formatter for syntax highlighting
        if PYGMENTS_AVAILABLE:
            self.code_formatter = HtmlFormatter(
                style='monokai',  # Dark theme compatible
                noclasses=False,  # Use CSS classes
                cssclass='highlight',
                prestyles='',
            )
            self.pygments_css = self.code_formatter.get_style_defs('.highlight')
        else:
            self.code_formatter = None
            self.pygments_css = None

    def generate_sections_html(self) -> str:
        """Generate HTML for all sections."""
        html_parts = []

        for section in self.sections:
            section_html = self._generate_section_html(section)
            html_parts.append(section_html)

        return '\n'.join(html_parts)

    def _generate_section_html(self, section: Section) -> str:
        """Generate HTML for a single section."""
        section_id = f"section-{section.number}"

        # Generate items HTML
        items_html = '\n'.join([
            self._generate_item_html(section.number, idx, item)
            for idx, item in enumerate(section.items)
        ])

        return f'''
    <div class="section" id="{section_id}">
      <div class="section-header" onclick="toggleSection('{section_id}')">
        <h2 class="section-title"><span class="section-number">Section {section.number}:</span> {section.title}</h2>
        <span class="section-toggle">▼</span>
      </div>
      <div class="section-content">
{items_html}
      </div>
    </div>'''

    def _highlight_code(self, code: str, language: str) -> str:
        """
        Apply syntax highlighting to code block.

        Args:
            code: The code string to highlight
            language: Language identifier (e.g., 'dart', 'python')

        Returns:
            HTML string with syntax highlighting markup
        """
        try:
            # Get appropriate lexer for language
            if language.lower() == 'dart':
                lexer = DartLexer()
            else:
                # Fallback for other languages
                lexer = get_lexer_by_name(language.lower(), stripall=False)

            # Apply highlighting
            highlighted = highlight(code, lexer, self.code_formatter)

            # Extract just the <pre> content (remove wrapper div)
            # Pygments wraps in <div class="highlight"><pre>...</pre></div>
            # We want only the inner content since we have our own <pre> wrapper
            match = re.search(r'<pre>(.*?)</pre>', highlighted, re.DOTALL)
            if match:
                return match.group(1)
            else:
                return highlighted

        except Exception as e:
            # Fallback on error: return HTML-escaped code
            print(f"⚠️  Warning: Syntax highlighting failed for {language}: {e}")
            return (code
                    .replace('&', '&amp;')
                    .replace('<', '&lt;')
                    .replace('>', '&gt;'))

    def _generate_item_html(self, section_num: int, item_idx: int, item: ChecklistItem) -> str:
        """Generate HTML for a single checklist item."""
        checkbox_id = f"item-{section_num}-{item_idx}"
        code_html = ''

        if item.code_example:
            code_id = f"code-{section_num}-{item_idx}"

            # Apply syntax highlighting if available
            if PYGMENTS_AVAILABLE and self.code_formatter:
                highlighted_code = self._highlight_code(
                    item.code_example.code,
                    item.code_example.language
                )
            else:
                # Fallback: HTML escape only
                highlighted_code = (item.code_example.code
                                   .replace('&', '&amp;')
                                   .replace('<', '&lt;')
                                   .replace('>', '&gt;'))

            code_html = f'''
        <div class="code-example">
          <div class="code-header">
            <span class="code-label">Code Example ({item.code_example.language})</span>
            <button class="code-toggle" onclick="toggleCode('{code_id}')">Show Code</button>
          </div>
          <div class="code-content hidden" id="{code_id}">
            <pre><code class="highlight">{highlighted_code}</code></pre>
          </div>
        </div>'''

        return f'''
        <div class="item">
          <div class="item-header">
            <div class="checkbox-wrapper">
              <input type="checkbox" class="item-checkbox" id="{checkbox_id}">
            </div>
            <div class="item-title">{item.title}</div>
          </div>
          <div class="item-details">
            <div class="detail-section">
              <div class="detail-heading">What this means:</div>
              <div class="detail-content">
{item.what_this_means}
              </div>
            </div>
            <div class="detail-section">
              <div class="detail-heading">Why this matters:</div>
              <div class="detail-content">
{item.why_this_matters}
              </div>
            </div>{code_html}
          </div>
        </div>'''


class ChecklistBuilder:
    """Main builder orchestrating parsing, generation, and output."""

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.markdown_path = base_dir / 'ditto-implementation-checklist.md'
        self.translations_path = base_dir / 'translations.json'
        self.template_path = base_dir / 'template.html'
        self.output_path = base_dir / 'ditto-sdk-checklist.html'

    def build(self):
        """Execute the full build process."""
        print(f"🔨 Building Ditto SDK Checklist HTML...")
        print(f"  📄 Markdown source: {self.markdown_path.name}")
        print(f"  🌐 Translations: {self.translations_path.name}")
        print(f"  📋 Template: {self.template_path.name}")
        print()

        # Step 1: Parse Markdown
        print("1️⃣  Parsing Markdown...")
        parser = MarkdownParser(self.markdown_path)
        sections = parser.parse()
        print(f"   ✓ Parsed {len(sections)} sections with {sum(len(s.items) for s in sections)} items")

        # Step 2: Load translations
        print("2️⃣  Loading translations...")
        with self.translations_path.open('r', encoding='utf-8') as f:
            translations = json.load(f)
        print(f"   ✓ Loaded translations for {len(translations)} languages")

        # Step 3: Generate HTML sections
        print("3️⃣  Generating HTML sections...")
        generator = HTMLGenerator(sections)
        sections_html = generator.generate_sections_html()
        print(f"   ✓ Generated {len(sections_html)} characters of HTML")

        # Step 4: Load template
        print("4️⃣  Loading template...")
        template_content = self.template_path.read_text(encoding='utf-8')
        print(f"   ✓ Loaded template ({len(template_content)} characters)")

        # Step 5: Inject translations and sections
        print("5️⃣  Injecting translations and sections...")

        # Add English content arrays to translations for language switching
        en_items = []
        en_what_means_sections = []
        en_why_matters_sections = []
        en_code_examples = []

        # Collect all code examples (only items with code)
        for section in sections:
            for item in section.items:
                en_items.append(item.title)
                en_what_means_sections.append(item.what_this_means)
                en_why_matters_sections.append(item.why_this_matters)
                if item.code_example:
                    # Store syntax-highlighted HTML for English code
                    highlighted = generator._highlight_code(item.code_example.code, item.code_example.language)
                    en_code_examples.append(highlighted)

        translations['en']['items'] = en_items
        translations['en']['whatMeansSections'] = en_what_means_sections
        translations['en']['whyMattersSections'] = en_why_matters_sections
        translations['en']['codeExamples'] = en_code_examples

        # Load Japanese code translations and apply syntax highlighting
        code_translations_path = self.base_dir / 'code-translations.json'
        if code_translations_path.exists():
            with open(code_translations_path, 'r', encoding='utf-8') as f:
                code_translations = json.load(f)
                ja_code_examples = []
                code_idx = 0

                for section in sections:
                    for item in section.items:
                        if item.code_example:
                            # Find matching translation by index
                            translated = next(
                                (block['translatedCode'] for block in code_translations['codeBlocks']
                                 if block['index'] == code_idx),
                                None
                            )
                            if translated:
                                # Apply syntax highlighting to translated code
                                highlighted = generator._highlight_code(translated, item.code_example.language)
                                ja_code_examples.append(highlighted)
                            else:
                                # Fallback to English code
                                highlighted = generator._highlight_code(item.code_example.code, item.code_example.language)
                                ja_code_examples.append(highlighted)
                            code_idx += 1

                if 'ja' in translations:
                    translations['ja']['codeExamples'] = ja_code_examples

        print(f"   ✓ Generated {len(en_code_examples)} English code examples")
        print(f"   ✓ Generated {len(translations.get('ja', {}).get('codeExamples', []))} Japanese code examples")

        translations_json = json.dumps(translations, ensure_ascii=False, indent=2)

        # Get Pygments CSS if available
        pygments_css = ''
        if generator.pygments_css:
            pygments_css = f'''
    /* ==========================================================================
       Syntax Highlighting (Pygments)
       ========================================================================== */
    {generator.pygments_css}

    /* Adjust Pygments colors to match our dark theme */
    .highlight {{
        background: transparent !important;
    }}
    .highlight pre {{
        margin: 0;
        font-family: inherit;
        line-height: inherit;
    }}
    '''

        output_html = template_content.replace(
            '/* INJECT_TRANSLATIONS_HERE */',
            translations_json
        )
        output_html = output_html.replace(
            '<!-- Pre-rendered sections will be injected here by build script -->',
            sections_html
        )

        # Inject Pygments CSS before closing </style>
        if pygments_css:
            output_html = output_html.replace(
                '</style>',
                f'{pygments_css}\n  </style>'
            )

        print("   ✓ Injection complete")

        # Step 6: Write output
        print("6️⃣  Writing output file...")
        self.output_path.write_text(output_html, encoding='utf-8')
        print(f"   ✓ Written to: {self.output_path}")

        # Summary
        print()
        print("✅ Build complete!")
        print(f"   📊 Output size: {len(output_html):,} characters")
        print(f"   📦 Output file: {self.output_path.name}")
        print()
        print("Next steps:")
        print("  1. Validate: python validate-html-tags.py")
        print("  2. Open in browser: open ditto-sdk-checklist.html")


def main():
    """Main entry point."""
    script_dir = Path(__file__).parent

    try:
        builder = ChecklistBuilder(script_dir)
        builder.build()
        return 0
    except Exception as e:
        print(f"\n❌ Build failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    exit(main())
