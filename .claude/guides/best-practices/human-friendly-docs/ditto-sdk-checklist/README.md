# Ditto SDK Implementation Checklist - Build System

This directory contains the build system for generating the Ditto SDK Implementation Checklist HTML file from maintainable source files.

## Overview

The checklist is distributed as a **single self-contained HTML file** (`ditto-sdk-checklist.html`) that users can open directly in their browser. However, during development, the content is maintained in separate source files for better maintainability.

### Architecture

```
Development (Source Files)              Distribution (Generated)
├── ditto-implementation-checklist.md   ────┐
├── translations.json                   ────┤
├── template.html                       ────┼─> ditto-sdk-checklist.html
└── build-checklist.py                  ────┘    (single HTML file)
```

**Key Insight**: Separation of concerns during development, single file for distribution.

## File Structure

```
.claude/guides/best-practices/
└── human-friendly-docs/
    └── ditto-sdk-checklist/
        ├── ditto-implementation-checklist.md  # Content source (Markdown)
        ├── translations.json                  # English/Japanese translations
        ├── template.html                      # HTML/CSS shell + UI logic
        ├── build-checklist.py                 # Build script (Python)
        ├── validate-html-tags.py              # HTML validation tool
        ├── extract_translations.py            # Helper script (one-time use)
        ├── ditto-sdk-checklist.html           # Generated output (distribution)
        └── README.md                          # This file
```

### Source Files

#### 1. `ditto-implementation-checklist.md` (Content Source)
- Location: Same directory as build script
- Single source of truth for checklist content
- Standard Markdown format with special structure:
  ```markdown
  ## Section N: Title

  ### ☐ Checklist Item Title

  **What this means:** Explanation...

  **Why this matters:** Rationale...

  **Code Example**:

  \`\`\`dart
  // Code here
  \`\`\`
  ```

#### 2. `translations.json` (Translation Data)
- English and Japanese UI translations
- Section titles, item titles, and explanations
- Extracted from original HTML file
- Format:
  ```json
  {
    "en": {
      "title": "Ditto SDK Implementation Checklist",
      "sections": [...],
      ...
    },
    "ja": {
      "title": "Ditto SDK実装チェックリスト",
      "sections": [...],
      "items": [...],
      "whatMeansSections": [...]
    }
  }
  ```

#### 3. `template.html` (HTML/CSS Shell)
- Complete HTML structure with CSS styling
- UI logic (JavaScript functions):
  - `toggleSection()` - Accordion expand/collapse
  - `toggleCode()` - Code example show/hide
  - `updateProgress()` - Progress bar updates
  - `switchLanguage()` - Language switching
- Placeholder comments for injection:
  - `/* INJECT_TRANSLATIONS_HERE */` - Translation data
  - `<!-- Pre-rendered sections will be injected here by build script -->` - HTML content

#### 4. `build-checklist.py` (Build Script)
- Parses Markdown into structured data
- Generates HTML sections from parsed data
- Injects translations and sections into template
- Outputs self-contained HTML file

### Generated File

#### `ditto-sdk-checklist.html` (Distribution Artifact)
- **Single self-contained HTML file** - no dependencies
- Pre-rendered content (no runtime parsing)
- Can be opened directly in any browser
- Can be shared as a single file

## Build Process

### Prerequisites

- Python 3.7 or later
- **Optional**: Pygments for syntax highlighting
  ```bash
  pip install -r requirements.txt
  # Or: pip install Pygments
  ```

**Note**: Build works without Pygments, but code examples won't be syntax highlighted.

### Building the HTML

```bash
# Navigate to the directory
cd .claude/guides/best-practices/human-friendly-docs/ditto-sdk-checklist

# Run the build script
python3 build-checklist.py
```

**Output**:
```
🔨 Building Ditto SDK Checklist HTML...
  📄 Markdown source: ditto-implementation-checklist.md
  🌐 Translations: translations.json
  📋 Template: template.html

1️⃣  Parsing Markdown...
   ✓ Parsed 11 sections with 68 items
2️⃣  Loading translations...
   ✓ Loaded translations for 2 languages
3️⃣  Generating HTML sections...
   ✓ Generated 128,242 characters of HTML
4️⃣  Loading template...
   ✓ Loaded template (19,614 characters)
5️⃣  Injecting translations and sections...
   ✓ Injection complete
6️⃣  Writing output file...
   ✓ Written to: ditto-sdk-checklist.html

✅ Build complete!
   📊 Output size: 161,624 characters
   📦 Output file: ditto-sdk-checklist.html
```

### Validating the Output

After building, validate the generated HTML:

```bash
python3 validate-html-tags.py
```

This checks for:
- Unclosed or mismatched HTML tags
- Tag nesting errors
- Proper HTML structure

### Testing in Browser

```bash
# macOS
open ditto-sdk-checklist.html

# Linux
xdg-open ditto-sdk-checklist.html

# Windows
start ditto-sdk-checklist.html
```

Test these features:
- ✅ Section accordion (expand/collapse)
- ✅ Checkbox state persistence (uses localStorage)
- ✅ Progress bar updates
- ✅ Language switching (ENG/JPN)
- ✅ Code example toggles

## Maintenance Workflows

### Adding a New Checklist Item

1. **Edit the Markdown file**:
   ```bash
   vim ditto-implementation-checklist.md
   ```

2. **Add the item following the structure**:
   ```markdown
   ### ☐ New Item Title

   **What this means:** Explanation...

   **Why this matters:** Rationale...

   **Code Example**:

   \`\`\`dart
   // Example code
   \`\`\`
   ```

3. **Update translations** (if adding Japanese translations):
   ```bash
   vim translations.json
   ```

   Add entries to:
   - `ja.items[]` - Japanese item title
   - `ja.whatMeansSections[]` - Japanese "What this means" content

4. **Rebuild**:
   ```bash
   python3 build-checklist.py
   ```

5. **Validate and test**:
   ```bash
   python3 validate-html-tags.py
   open ditto-sdk-checklist.html
   ```

6. **Commit changes**:
   ```bash
   git add ditto-implementation-checklist.md translations.json ditto-sdk-checklist.html
   git commit -m "Add checklist item: <description>"
   ```

### Updating Translations

1. **Edit translations**:
   ```bash
   vim translations.json
   ```

2. **Rebuild**:
   ```bash
   python3 build-checklist.py
   ```

3. **Test language switching** in browser

4. **Commit**:
   ```bash
   git add translations.json ditto-sdk-checklist.html
   git commit -m "Update translations: <description>"
   ```

### Modifying Styles or UI Logic

1. **Edit template**:
   ```bash
   vim template.html
   ```

2. **Modify CSS or JavaScript** as needed

3. **Rebuild**:
   ```bash
   python3 build-checklist.py
   ```

4. **Test in browser** (check responsive design, interactions)

5. **Commit**:
   ```bash
   git add template.html ditto-sdk-checklist.html
   git commit -m "Update styles: <description>"
   ```

## Benefits of This Architecture

### For End Users
- ✅ Single HTML file (no change from before)
- ✅ No build dependencies required
- ✅ Works offline
- ✅ Instant page load (pre-rendered)

### For Developers (Maintainability)
- ✅ Content in standard Markdown (easy editing)
- ✅ Translations in clean JSON format
- ✅ No content duplication (single source of truth)
- ✅ Separation of concerns (content, styling, logic)
- ✅ Standard Python libraries (no custom parser)
- ✅ Clear build process

## Comparison: Before vs After

| Aspect | Before | After |
|--------|--------|-------|
| **Content updates** | Edit embedded JS string | Edit Markdown file |
| **Translation updates** | Edit inline HTML in JS | Edit JSON file |
| **Parser** | 222-line custom parser | Standard library |
| **Content duplication** | Yes (Markdown in 2 places) | No (single source) |
| **File for development** | 1 file (2,636 lines) | 4 files (separated) |
| **File for distribution** | 1 HTML file ✅ | 1 HTML file ✅ |
| **Maintainability score** | 2/10 | 8/10 |

## Troubleshooting

### Build Fails with "Could not find translations object"

The build script expects `translations.json` to exist. If it's missing:

```bash
# Regenerate from current HTML (if needed)
python3 extract_translations.py
```

### Validation Errors: "Unclosed tag"

This usually means:
1. Missing closing tag in template.html
2. Improperly escaped content in Markdown

Check the line numbers in the error message and inspect the generated HTML.

### Language Switching Doesn't Work

Check:
1. Translations are properly injected (view source of generated HTML)
2. JavaScript console for errors
3. Translation keys match between template and translations.json

### Progress Bar Not Updating

Check:
1. Checkbox elements have correct class: `item-checkbox`
2. JavaScript `updateProgress()` function is present
3. Browser console for errors

## Future Enhancements

After this refactoring, these improvements become easier:

1. **Automated translation validation** in build script
2. **Git hook integration** for auto-build on commit
3. **CI/CD integration** for automated deployment
4. **Syntax highlighting** for code examples (using Pygments)
5. **Content sync** from main Ditto best practices guide

## Technical Details

### Build Script Architecture

```python
class MarkdownParser:
    # Parses .md file into structured data
    def parse() -> List[Section]

class HTMLGenerator:
    # Converts structured data to HTML
    def generate_sections_html() -> str

class ChecklistBuilder:
    # Orchestrates: parse → generate → inject → write
    def build()
```

### HTML Escaping

The build script properly escapes:
- `<`, `>`, `&` in code examples
- `<uuid>`, `<timestamp>` placeholders in inline code
- Special characters in Markdown content

### LocalStorage State

The generated HTML uses `localStorage` to persist:
- Checkbox states: `ditto-checklist-state`
- Language preference: `ditto-checklist-lang`

## Support

For issues or questions:
1. Check this README
2. Run `python3 build-checklist.py` and review output
3. Run `python3 validate-html-tags.py` to check HTML structure
4. Open an issue in the repository

---

**Last Updated**: 2025-12-21
**Architecture Version**: 1.0
