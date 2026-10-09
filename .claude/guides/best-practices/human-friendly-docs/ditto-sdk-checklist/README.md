# Ditto SDK Implementation Checklist

This directory contains the sources and the build script for the Ditto SDK Implementation Checklist, an interactive review checklist for Flutter apps that use the Ditto SDK. The checklist is derived from the [Ditto SDK Best Practices guide](../../ditto.md) and is distributed as one self-contained HTML file.

## Overview

`ditto-sdk-checklist.html` can be opened directly in a browser or shared as a single file. It has no external dependencies and works offline. It provides:

- 12 sections of checklist items, each with "What this means", "Why this matters", the related sections of the best-practices guide, and an optional code example
- English and Japanese, switchable at any time
- Progress tracking per section and overall, saved in the browser's `localStorage`
- Expand all / Collapse all, Reset progress, and a print layout with all code examples expanded

The HTML file is generated. Edit the source files and rebuild; do not edit `ditto-sdk-checklist.html` by hand.

```
Source files                              Generated file
├── ditto-implementation-checklist.md  ─┐
├── translations.json                  ─┤
├── code-translations.json             ─┼─>  ditto-sdk-checklist.html
├── template.html                      ─┤
└── build-checklist.py                 ─┘
```

## Files

| File | Purpose |
|------|---------|
| `ditto-implementation-checklist.md` | Content source (English) and single source of truth for items, code examples, version, and date |
| `translations.json` | UI strings (English and Japanese) and the Japanese section titles, item titles, and "What this means" / "Why this matters" text |
| `code-translations.json` | Code examples with Japanese comments |
| `template.html` | HTML, CSS, and JavaScript shell with injection placeholders |
| `build-checklist.py` | Parses the Markdown, validates the translations, and writes the HTML |
| `validate-html-tags.py` | Checks the tag structure of the generated HTML |
| `ditto-sdk-checklist.html` | Generated output for distribution |

### Markdown format

The header blockquote must contain `Version`, `Last Updated`, and `Applies to`; the build copies them into the page header. Each item follows this structure:

````markdown
## Section N: Title

### ☐ Checklist item title

**What this means:** Explanation. Bullet lists are supported:
- First point
- Second point

**Why this matters:** Rationale.

**Best-practices guide:** Heading in ditto.md, Another heading

**Code Example**:

```dart
// Optional. One code block per item (dart, sql, or yaml).
```
````

Supported inline formatting: `` `code` ``, ``` `` code with `backticks` `` ```, `**bold**`, and `[links](https://...)`. Text is HTML-escaped by the build.

The "Best-practices guide" line names headings of [ditto.md](../../ditto.md) exactly as written there. It is shown in both languages without translation.

### Translations

- `translations.json` → `ja.sections`, `ja.items`, `ja.whatMeansSections`, and `ja.whyMattersSections` are arrays aligned by position with the sections and items in the Markdown file. Entries are HTML fragments (`<p>`, `<ul>`, `<li>`, `<code>`, `<strong>`).
- `code-translations.json` → one entry per code example, in Markdown order (`index` 0, 1, 2, ...). `originalCode` must equal the Markdown code block exactly, and `translatedCode` may differ from it only in comments.
- English text in the HTML always comes from the Markdown file.

Conventions for the Japanese text: keep product and DQL terms such as Ditto Server, Small Peer, CRDT, REGISTER, MISSING, attachment, sync scope, and tombstone in English; write "in our testing" as 「テストでは」 and keep "(SDK 5.1.0)" markers; label code comments 「良い例」 / 「悪い例」.

## Building

The build uses Python 3.9 or later. [Pygments](https://pygments.org/) provides syntax highlighting and is declared as inline script metadata (PEP 723), so `uv` installs it automatically:

```bash
cd .claude/guides/best-practices/human-friendly-docs/ditto-sdk-checklist
uv run build-checklist.py
python3 validate-html-tags.py
```

`python3 build-checklist.py` also works without Pygments, but the code examples are then not highlighted. Commit HTML built with highlighting.

The build stops with an error, and writes nothing, when:

- the header fields are missing, or an item lacks "What this means" or "Why this matters"
- a Japanese array does not have one entry per section or item, or a Japanese fragment has unbalanced HTML tags
- a code translation's `originalCode` differs from the Markdown code block, or its `translatedCode` differs outside of comments

These checks catch the most common maintenance error: changing the English content without updating the Japanese.

## Testing in a browser

Open `ditto-sdk-checklist.html` and check:

- Checkboxes update the overall and per-section progress, and survive a reload
- ENG / JPN switches every title, text block, heading, button, and code comment
- Section headers and Show Code buttons expand and collapse (also with the keyboard)
- Expand all, Collapse all, and Reset progress work
- The print preview shows all sections and code examples in black on white

## Maintenance workflows

### Updating content

Keep the checklist synchronized with [ditto.md](../../ditto.md). When a change to the guide affects a checklist item (see the [synchronization workflow](../../../../rules/workflows/ditto-best-practices-sync.md)):

1. Edit `ditto-implementation-checklist.md`, and update `Version` and `Last Updated` in its header.
2. Update the Japanese entries at the same positions in `translations.json`.
3. If a code example changed, update `originalCode` and `translatedCode` in `code-translations.json`.
4. Run `uv run build-checklist.py` and `python3 validate-html-tags.py`, and check the page in a browser.
5. Commit the sources together with `ditto-sdk-checklist.html`.

### Adding or removing an item

Insert or remove the item in the Markdown file, and insert or remove the entries at the same position in every `ja` array of `translations.json`. If the item has a code example, insert or remove its block in `code-translations.json` and renumber the `index` values of the following blocks.

Saved progress is keyed by each item's English title, so renaming an item resets only that item's checkbox.

### Changing the layout or behavior

Edit `template.html` and rebuild. The build replaces these placeholders: `{{VERSION}}`, `{{LAST_UPDATED}}`, `{{APPLIES_TO}}`, `<!-- INJECT_SECTIONS_HERE -->`, `/* INJECT_TRANSLATIONS_HERE */`, and `/* INJECT_PYGMENTS_CSS_HERE */`. UI strings belong in `translations.json` (elements with `data-i18n` or `data-i18n-html`), not in the template.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Translations are out of sync` | The English content changed without matching Japanese updates. The message lists each entry to update. |
| `Placeholder ... not found` | A placeholder was removed from `template.html`. Restore it. |
| Validation reports an unclosed tag | Check the line in the generated HTML; the source is usually `template.html`. Text from the Markdown file is escaped by the build. |
| Progress is not saved | The browser blocks `localStorage` for this page (for example, in a private window or with a strict policy for `file://` pages). The checklist still works, but progress is not remembered. |

## Browser storage

The page stores two `localStorage` entries: `ditto-checklist-state-v2` (the IDs of checked items) and `ditto-checklist-lang` (the selected language). Nothing is sent anywhere.

---

**Last Updated**: 2026-10-09
