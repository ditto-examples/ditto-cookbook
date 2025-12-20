# Bad Progressive Disclosure Examples

> **Last Updated**: 2025-12-20

This file demonstrates common mistakes in organizing Skills, including poor file structure, deeply nested references, and ineffective content organization.

## Bad Example 1: Everything in SKILL.md (No Progressive Disclosure)

### Problem: Monolithic File

```
pdf-processing/
└── SKILL.md    # 2,847 lines - everything included
```

### SKILL.md Contents (Too Large)

```markdown
---
name: processing-pdfs
description: PDF processing skill
---

# PDF Processing

## Text Extraction

[200 lines of detailed instructions]

## Complete pdfplumber API Reference

[450 lines of API documentation]

### pdfplumber.open()
[Complete documentation with all parameters]

### pdfplumber.Page
[Complete documentation]

### page.extract_text()
[Complete documentation with all options]

[... continues for 450 lines ...]

## Complete PyPDF2 API Reference

[380 lines of API documentation]

## Complete pdf2image Documentation

[320 lines of documentation]

## Form Filling Complete Guide

[295 lines of step-by-step instructions]

### Analyzing Form Structure
[85 lines]

### Creating Field Mappings
[94 lines]

### Validation Process
[116 lines]

## Troubleshooting Every Possible Issue

[467 lines of troubleshooting]

### Installation Issues
[94 lines]

### File Opening Errors
[112 lines]

### Text Extraction Problems
[156 lines]

[... continues to line 2,847 ...]
```

**Problems**:
- ❌ SKILL.md is 2,847 lines (target: under 500)
- ❌ Loads entire API reference every time
- ❌ No progressive disclosure
- ❌ Wastes context window
- ❌ Difficult to maintain
- ❌ Hard to navigate

**Fixed version**: Split into progressive tiers:

```
pdf-processing/
├── SKILL.md                    # 430 lines - core guidance
├── examples/
│   ├── extract-text-good.py
│   └── fill-form-good.py
├── reference/
│   ├── pdfplumber-api.md      # 450 lines
│   ├── pypdf2-api.md          # 380 lines
│   ├── forms-guide.md         # 295 lines
│   └── troubleshooting.md     # 467 lines
└── scripts/
    ├── analyze_form.py
    └── fill_form.py
```

SKILL.md references detailed docs:
```markdown
## Text Extraction

Basic usage:
```python
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

**Complete API**: See [reference/pdfplumber-api.md](reference/pdfplumber-api.md)
**Troubleshooting**: See [reference/troubleshooting.md](reference/troubleshooting.md)
```

## Bad Example 2: Deeply Nested References

### Problem: Three Levels Deep

```
bigquery-analysis/
├── SKILL.md                # References advanced.md
└── reference/
    ├── advanced.md         # References details.md
    └── details.md          # References specific-patterns.md
        └── specific-patterns.md  # Actual content
```

### Navigation Path

```markdown
# SKILL.md
For advanced patterns, see [reference/advanced.md](reference/advanced.md)

# advanced.md
For detailed implementation, see [details.md](details.md)

# details.md
For specific patterns, see [specific-patterns.md](specific-patterns.md)

# specific-patterns.md
Here's the actual information you need...
```

**Problems**:
- ❌ Three levels of nesting
- ❌ Claude may partially read nested files (head -100)
- ❌ Incomplete information delivery
- ❌ User has to follow multiple links
- ❌ Poor discoverability

**Fixed version**: One level deep from SKILL.md:

```
bigquery-analysis/
├── SKILL.md
└── reference/
    ├── basic-patterns.md       # Direct from SKILL.md
    ├── advanced-patterns.md    # Direct from SKILL.md
    └── specific-patterns.md    # Direct from SKILL.md
```

```markdown
# SKILL.md

**Basic patterns**: See [reference/basic-patterns.md](reference/basic-patterns.md)
**Advanced patterns**: See [reference/advanced-patterns.md](reference/advanced-patterns.md)
**Specific scenarios**: See [reference/specific-patterns.md](reference/specific-patterns.md)
```

## Bad Example 3: Flat Structure (No Organization)

### Problem: No Reference Organization

```
react-testing/
├── SKILL.md
└── reference/
    ├── guide.md            # All content in one file (1,834 lines)
    └── more-guide.md       # More content (1,245 lines)
```

### guide.md Contents

```markdown
# Testing Guide

## Unit Testing
[345 lines]

## Integration Testing
[267 lines]

## E2E Testing
[198 lines]

## Performance Testing
[234 lines]

## Accessibility Testing
[178 lines]

## Visual Regression Testing
[156 lines]

## API Mocking
[234 lines]

## Test Data Management
[222 lines]

[... continues to 1,834 lines ...]
```

**Problems**:
- ❌ Single large reference file
- ❌ Claude loads entire file even if only needing unit testing section
- ❌ No domain organization
- ❌ Wastes context

**Fixed version**: Split by testing domain:

```
react-testing/
├── SKILL.md
└── reference/
    ├── unit-testing.md            # 345 lines
    ├── integration-testing.md     # 267 lines
    ├── e2e-testing.md             # 198 lines
    ├── performance-testing.md     # 234 lines
    ├── accessibility-testing.md   # 178 lines
    ├── visual-regression.md       # 156 lines
    ├── api-mocking.md             # 234 lines
    └── test-data.md               # 222 lines
```

SKILL.md provides navigation:
```markdown
## Testing Domains

**Unit Testing**: See [reference/unit-testing.md](reference/unit-testing.md)
**Integration Testing**: See [reference/integration-testing.md](reference/integration-testing.md)
**E2E Testing**: See [reference/e2e-testing.md](reference/e2e-testing.md)
[... etc ...]
```

## Bad Example 4: Unclear Navigation

### Problem: Vague References

```markdown
# SKILL.md

## Advanced Features

For more information, see the other documentation.

Some advanced topics are covered in various files in the reference directory.

Check the examples folder for samples.
```

**Problems**:
- ❌ "other documentation" - which file?
- ❌ "various files" - no specific references
- ❌ "examples folder" - which examples?
- ❌ Claude doesn't know where to look

**Fixed version**: Explicit navigation:

```markdown
# SKILL.md

## Advanced Features

**Form Filling**: See [reference/forms-guide.md](reference/forms-guide.md)
**API Reference**: See [reference/api-reference.md](reference/api-reference.md)
**Examples**: See [examples/fill-form-good.py](examples/fill-form-good.py)
```

## Bad Example 5: Scripts Loaded into Context

### Problem: Reading Instead of Executing

```markdown
# SKILL.md

## Form Validation

Here's the complete validation script you can reference:

```python
# validation.py (534 lines)
import sys
import json
from typing import Dict, List, Any

def validate_field_types(fields: Dict[str, Any]) -> List[str]:
    """Validate field types are correct"""
    errors = []
    valid_types = ['text', 'number', 'date', 'signature']

    for field_name, field_data in fields.items():
        if 'type' not in field_data:
            errors.append(f"Field {field_name} missing type")
            continue

        if field_data['type'] not in valid_types:
            errors.append(
                f"Field {field_name} has invalid type: {field_data['type']}"
            )

    return errors

[... continues for 534 lines ...]
```

Use this script to validate your form fields.
```

**Problems**:
- ❌ 534 lines of script loaded into context
- ❌ Wastes tokens on implementation details
- ❌ Should execute, not read
- ❌ Script is reference, not guidance

**Fixed version**: Execute script, show only usage:

```markdown
# SKILL.md

## Form Validation

Run the validation script:

```bash
python scripts/validate_fields.py fields.json
```

Output format:
- "OK" if all validations pass
- Error messages listing specific issues

Common errors:
- "Field X missing type"
- "Field Y has invalid type"
- "Field Z missing required value"
```

## Bad Example 6: No Table of Contents for Long Files

### Problem: Long Reference Without Navigation

```markdown
# reference/api-complete.md

(1,456 lines of API documentation with no table of contents)

## Authentication
[Content at line 45]

## Database Queries
[Content at line 234]

## Data Modeling
[Content at line 567]

## Subscriptions
[Content at line 892]

## Error Handling
[Content at line 1,198]
```

**Problems**:
- ❌ Claude may preview with `head -100`
- ❌ Can't see full scope of content
- ❌ Doesn't know what sections exist
- ❌ May miss relevant information

**Fixed version**: Add table of contents:

```markdown
# reference/api-complete.md

## Contents
- Authentication (line 45)
- Database Queries (line 234)
- Data Modeling (line 567)
- Subscriptions (line 892)
- Error Handling (line 1,198)

## Authentication
[Content...]

## Database Queries
[Content...]
```

## Bad Example 7: Mixed Concerns in Single File

### Problem: Unrelated Content Together

```
docker-deployment/
├── SKILL.md
└── reference/
    └── everything.md    # 2,134 lines mixing all topics
```

### everything.md Contents

```markdown
# Docker Everything Guide

## Writing Dockerfiles
[284 lines]

## Security Hardening
[467 lines]

## Kubernetes Deployment
[523 lines]

## CI/CD Integration
[378 lines]

## Monitoring and Logging
[482 lines]
```

**Problems**:
- ❌ Unrelated concerns mixed together
- ❌ Security hardening loaded when user needs Kubernetes
- ❌ No clear separation of topics
- ❌ Difficult to maintain

**Fixed version**: Separate by concern:

```
docker-deployment/
├── SKILL.md
└── reference/
    ├── dockerfile-guide.md        # 284 lines
    ├── security-hardening.md      # 467 lines
    ├── kubernetes-deployment.md   # 523 lines
    ├── ci-cd-integration.md       # 378 lines
    └── monitoring-logging.md      # 482 lines
```

## Bad Example 8: Windows-Style Paths

### Problem: Backslashes in References

```markdown
# SKILL.md

For advanced patterns, see [reference\advanced.md](reference\advanced.md)

For examples, see [examples\good-pattern.py](examples\good-pattern.py)

Run the script: `python scripts\validate.py`
```

**Problems**:
- ❌ Backslashes fail on Unix systems
- ❌ Links won't work
- ❌ Scripts won't execute
- ❌ Cross-platform compatibility broken

**Fixed version**: Forward slashes always:

```markdown
# SKILL.md

For advanced patterns, see [reference/advanced.md](reference/advanced.md)

For examples, see [examples/good-pattern.py](examples/good-pattern.py)

Run the script: `python scripts/validate.py`
```

## Bad Example 9: Duplicate Content Across Files

### Problem: Same Content in Multiple Places

```
pdf-processing/
├── SKILL.md
│   [Contains complete form filling guide - 295 lines]
└── reference/
    └── forms-guide.md
        [Contains same form filling guide - 295 lines]
```

**Problems**:
- ❌ Duplicate content
- ❌ Wastes space
- ❌ Hard to maintain (update in two places)
- ❌ Inconsistency risk

**Fixed version**: Content in one place, reference from another:

```markdown
# SKILL.md

## Form Filling

Quick overview:
1. Analyze form structure
2. Create field mapping
3. Validate mapping
4. Fill form
5. Verify output

**Complete guide**: See [reference/forms-guide.md](reference/forms-guide.md)
```

## Bad Example 10: No Examples, Only Documentation

### Problem: Documentation Without Demonstrations

```
react-testing/
├── SKILL.md
└── reference/
    ├── unit-testing-theory.md    # Theory only, no code
    ├── integration-theory.md     # Concepts only
    └── best-practices.md         # Principles only
```

**Problems**:
- ❌ No concrete examples
- ❌ Hard to apply theoretical knowledge
- ❌ Missing copy-paste templates
- ❌ No good vs bad demonstrations

**Fixed version**: Add examples directory:

```
react-testing/
├── SKILL.md
├── examples/
│   ├── unit-test-good.tsx       # Concrete demonstration
│   ├── unit-test-bad.tsx        # Common mistakes
│   ├── integration-good.tsx     # Best practices
│   └── integration-bad.tsx      # Anti-patterns
└── reference/
    ├── unit-testing-guide.md    # Theory + references examples
    ├── integration-guide.md     # Theory + references examples
    └── best-practices.md        # Principles + references examples
```

## Progressive Disclosure Anti-Patterns Summary

### Structure Issues
- ❌ Everything in SKILL.md (>500 lines)
- ❌ Deeply nested references (3+ levels)
- ❌ Flat structure with huge files
- ❌ No organization by domain
- ❌ Mixed concerns in single file

### Navigation Issues
- ❌ Vague references ("see other docs")
- ❌ No table of contents for long files
- ❌ Unclear file names
- ❌ Windows-style paths (backslashes)

### Content Issues
- ❌ Duplicate content across files
- ❌ Scripts loaded into context instead of executed
- ❌ No examples, only documentation
- ❌ Related content in separate skills

### Maintenance Issues
- ❌ Difficult to update
- ❌ Risk of inconsistency
- ❌ Hard to find specific information
- ❌ No clear ownership of topics

## Quick Fix Checklist

Before finalizing structure:
- [ ] SKILL.md under 500 lines
- [ ] References one level deep
- [ ] Long files have table of contents
- [ ] Domain organization for large Skills
- [ ] Clear navigation with specific links
- [ ] Scripts executed, not loaded
- [ ] Examples directory exists
- [ ] Forward slashes in all paths
- [ ] No duplicate content
- [ ] Related concerns grouped together

## See Also

- [progressive-disclosure-good.md](progressive-disclosure-good.md) - Effective organization patterns
- [../SKILL.md](../SKILL.md) - Full Skill authoring guidance
- [../reference/skill-structure-guide.md](../reference/skill-structure-guide.md) - Structure details
