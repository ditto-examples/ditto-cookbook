#!/usr/bin/env python3
"""
Extract translations from ditto-sdk-checklist.html to translations.json

This script parses the JavaScript object embedded in the HTML file
and converts it to a clean JSON structure.
"""

import json
import re
from pathlib import Path


def extract_translations(html_path: Path) -> dict:
    """Extract translations object from HTML file."""
    content = html_path.read_text(encoding='utf-8')

    # Find the translations object
    # Pattern: const translations = { ... };
    pattern = r'const translations = \{(.*?)\};'
    match = re.search(pattern, content, re.DOTALL)

    if not match:
        raise ValueError("Could not find translations object in HTML")

    translations_js = match.group(1)

    # Parse the JavaScript object structure manually
    # This is a simplified parser for the specific structure
    translations = {'en': {}, 'ja': {}}

    # Extract each language section
    for lang in ['en', 'ja']:
        lang_pattern = rf'{lang}: \{{(.*?)\n      \}}'
        lang_match = re.search(lang_pattern, translations_js, re.DOTALL)

        if not lang_match:
            continue

        lang_content = lang_match.group(1)

        # Extract simple string fields
        for field in ['title', 'completed', 'showCode', 'hideCode', 'officialDoc', 'whatMeans', 'whyMatters']:
            field_pattern = rf'{field}: "([^"]+)"'
            field_match = re.search(field_pattern, lang_content)
            if field_match:
                translations[lang][field] = field_match.group(1)

        # Extract sections array
        sections_pattern = r'sections: \[(.*?)\]'
        sections_match = re.search(sections_pattern, lang_content, re.DOTALL)
        if sections_match:
            sections_content = sections_match.group(1)
            sections = re.findall(r'"([^"]+)"', sections_content)
            translations[lang]['sections'] = sections

        # Extract items array (if exists for ja)
        if lang == 'ja':
            items_pattern = r'items: \[(.*?)\],'
            items_match = re.search(items_pattern, lang_content, re.DOTALL)
            if items_match:
                items_content = items_match.group(1)
                items = re.findall(r'"([^"]+)"', items_content)
                translations[lang]['items'] = items

            # Extract whatMeansSections array (template literals)
            whatmeans_pattern = r'whatMeansSections: \[(.*?)\n        \]'
            whatmeans_match = re.search(whatmeans_pattern, lang_content, re.DOTALL)
            if whatmeans_match:
                whatmeans_content = whatmeans_match.group(1)
                # Extract template literals
                whatmeans_sections = []
                template_literal_pattern = r'`([^`]+)`'
                for match in re.finditer(template_literal_pattern, whatmeans_content):
                    whatmeans_sections.append(match.group(1))
                translations[lang]['whatMeansSections'] = whatmeans_sections

    return translations


def main():
    """Main entry point."""
    script_dir = Path(__file__).parent
    html_file = script_dir / "ditto-sdk-checklist.html"
    output_file = script_dir / "translations.json"

    print(f"Extracting translations from: {html_file}")

    try:
        translations = extract_translations(html_file)

        # Write to JSON file
        with output_file.open('w', encoding='utf-8') as f:
            json.dump(translations, f, ensure_ascii=False, indent=2)

        print(f"✓ Translations extracted to: {output_file}")
        print(f"  English fields: {list(translations['en'].keys())}")
        print(f"  Japanese fields: {list(translations['ja'].keys())}")
        if 'items' in translations['ja']:
            print(f"  Japanese items: {len(translations['ja']['items'])}")
        if 'whatMeansSections' in translations['ja']:
            print(f"  Japanese whatMeansSections: {len(translations['ja']['whatMeansSections'])}")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

    return 0


if __name__ == '__main__':
    exit(main())
