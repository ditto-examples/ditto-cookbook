# Skill Structure Guide

> **Last Updated**: 2025-12-20

Complete breakdown of Skill file structure, organization patterns, and architectural decisions for creating maintainable, discoverable Skills.

## Contents
- Skill directory structure
- SKILL.md anatomy
- YAML frontmatter requirements
- Progressive disclosure architecture
- File naming conventions
- Platform-specific organization
- Size guidelines and limits

## Skill Directory Structure

### Basic Skill (Simple)

```
skill-name/
└── SKILL.md    # All content in one file (<500 lines)
```

**Use when**:
- Skill is focused and simple
- All guidance fits comfortably in one file
- No complex workflows or extensive reference material

**Example**: Simple utility skills like formatting code or generating boilerplate.

### Standard Skill (Moderate Complexity)

```
skill-name/
├── SKILL.md                    # Core guidance (350-500 lines)
├── examples/                   # Concrete demonstrations
│   ├── pattern-good.md        # Best practices
│   └── pattern-bad.md         # Common mistakes
└── reference/                  # Deep-dive documentation
    └── advanced-guide.md      # Detailed reference
```

**Use when**:
- Skill requires examples to demonstrate patterns
- Some advanced topics need detailed explanation
- Content would exceed 500 lines in single file

**Example**: Domain-specific skills like PDF processing or database migrations.

### Complex Skill (Comprehensive)

```
skill-name/
├── SKILL.md                    # Core guidance (400-500 lines)
├── examples/                   # Multiple example sets
│   ├── basic-good.md
│   ├── basic-bad.md
│   ├── advanced-good.md
│   └── advanced-bad.md
├── reference/                  # Multiple reference docs
│   ├── api-reference.md
│   ├── patterns-guide.md
│   ├── troubleshooting.md
│   └── migration-guide.md
├── templates/                  # Copy-paste templates
│   ├── basic-template.md
│   └── advanced-template.md
└── scripts/                    # Utility scripts
    ├── validate.py
    └── analyze.py
```

**Use when**:
- Skill covers multiple domains or workflows
- Requires executable utilities
- Extensive examples and reference material needed
- Templates help users get started quickly

**Example**: Comprehensive skills like API testing or React component development.

### Multi-Domain Skill (Large Scale)

```
skill-name/
├── SKILL.md                    # Overview and navigation
├── examples/
│   ├── domain1-good.md
│   ├── domain1-bad.md
│   ├── domain2-good.md
│   └── domain2-bad.md
└── reference/
    ├── domain1-schemas.md      # Domain 1 specifics
    ├── domain2-schemas.md      # Domain 2 specifics
    ├── domain3-schemas.md      # Domain 3 specifics
    └── common-patterns.md      # Shared patterns
```

**Use when**:
- Skill spans multiple distinct domains
- Each domain has substantial content
- Users typically work in one domain at a time

**Example**: BigQuery analysis skill with separate finance, sales, product domains.

## SKILL.md Anatomy

### Complete Structure

```markdown
---
[YAML Frontmatter]
---

# [Skill Title]

**Last Updated**: YYYY-MM-DD

## Purpose

[1-2 paragraphs explaining what this Skill does]

## When This Skill Applies

[Specific scenarios and conditions]

## Platform Detection

[How to detect when this Skill is relevant]

## [Optional: SDK Version Compatibility]

[Version-specific information if applicable]

## Core Principles

[3-5 fundamental concepts]

### [Principle 1]
[Explanation]

### [Principle 2]
[Explanation]

## Common Workflows

### Workflow 1: [Name]

[Checklist and step-by-step instructions]

### Workflow 2: [Name]

[Checklist and step-by-step instructions]

## Critical Patterns

### CRITICAL Priority

#### Pattern 1: [Name]

**Problem**: [What issue this addresses]
**Solution**: [How to solve it]
**Good example**: [Code/demonstration]
**Bad example**: [What to avoid]
**When**: [When to apply this pattern]

[Repeat for all CRITICAL patterns]

### HIGH Priority

[Similar structure for HIGH priority patterns]

### MEDIUM Priority

[Similar structure for MEDIUM priority patterns]

## [Optional: Common Anti-Patterns to Avoid]

[List of common mistakes]

## Quick Reference Checklist

[Comprehensive checklist covering all key points]

## See Also

[Links to examples and reference files]
```

### Section Sizing Guidelines

| Section | Target Lines | Max Lines | Notes |
|---------|--------------|-----------|-------|
| Frontmatter | 15-30 | 50 | Include triggers and issues |
| Purpose | 10-20 | 40 | Brief, focused explanation |
| Core Principles | 50-100 | 150 | 3-5 key concepts |
| Workflows | 100-150 | 250 | 2-4 workflows with checklists |
| Critical Patterns | 150-250 | 350 | 10-15 patterns total |
| Checklist | 20-40 | 60 | Comprehensive but scannable |
| **Total** | **350-450** | **500** | Hard limit for SKILL.md |

## YAML Frontmatter Requirements

### Required Fields

```yaml
---
name: skill-identifier
description: |
  Multi-line description...
---
```

### Complete Frontmatter Template

```yaml
---
name: skill-identifier-name
description: |
  First paragraph: What the Skill does. Use when [scenarios].

  CRITICAL ISSUES PREVENTED:
  - Issue 1 description
  - Issue 2 description
  - Issue 3 description

  TRIGGERS:
  - Trigger condition 1
  - Trigger condition 2
  - Trigger condition 3

  PLATFORMS: Platform1, Platform2, or "All"
---
```

### Field Specifications

**name**:
- Required: Yes
- Format: Lowercase letters, numbers, hyphens only
- Length: Maximum 64 characters
- Pattern: Prefer gerund form (processing-, analyzing-, managing-)
- Restrictions:
  - No XML tags
  - No reserved words: "anthropic", "claude"
  - No spaces or underscores

**description**:
- Required: Yes
- Format: Multi-line text (use `|` for block scalar)
- Length: Maximum 1024 characters
- Content: Must include:
  1. What the Skill does
  2. When to use it
  3. CRITICAL ISSUES PREVENTED section
  4. TRIGGERS section
  5. PLATFORMS section
- Restrictions:
  - No XML tags
  - Must be third person perspective
  - Must be non-empty

### Description Structure

```
[What it does] + [When to use] (1-3 sentences)

CRITICAL ISSUES PREVENTED:
- [Specific issue 1]
- [Specific issue 2]
- [Specific issue 3]

TRIGGERS:
- [File pattern or condition 1]
- [User mention or keyword 2]
- [Context indicator 3]

PLATFORMS: [Comma-separated list or "All"]
```

## Progressive Disclosure Architecture

### Three-Tier Model

**Tier 1: SKILL.md** (Always loaded when Skill triggers)
- Core concepts and principles
- Common workflows
- Critical patterns
- Navigation to deeper content

**Tier 2: examples/** (Loaded when Claude needs demonstration)
- Concrete code examples
- Good vs bad pattern comparisons
- Platform-specific implementations

**Tier 3: reference/** (Loaded when Claude needs detailed information)
- Complete API documentation
- Comprehensive guides
- Troubleshooting resources
- Advanced patterns

### Loading Behavior

```
User triggers Skill
    ↓
Claude reads SKILL.md (Tier 1)
    ↓
Determines if more context needed
    ↓
    ├─→ Reads specific example file (Tier 2)
    │
    └─→ Reads specific reference file (Tier 3)
```

### Navigation Pattern

**In SKILL.md**:
```markdown
**Basic usage**: [Instructions here in SKILL.md]

**Advanced features**: See [reference/advanced.md](reference/advanced.md)
**Examples**: See [examples/pattern-good.md](examples/pattern-good.md)
```

**Important**: Keep references one level deep from SKILL.md. Avoid:
```markdown
# SKILL.md
See [advanced.md](reference/advanced.md)

# advanced.md
See [details.md](details.md)  # ❌ Too deep, Claude may incompletely read
```

## File Naming Conventions

### SKILL.md

- **Name**: Always exactly `SKILL.md` (uppercase)
- **Location**: Root of skill directory
- **Purpose**: Main skill file with metadata and core content

### Example Files

**Pattern**: `<topic>-<quality>.md` or `<topic>-<quality>.<ext>`

**Quality indicators**:
- `good` - Best practices demonstration
- `bad` - Common mistakes to avoid

**Examples**:
- `api-queries-good.md`
- `api-queries-bad.md`
- `error-handling-good.py`
- `error-handling-bad.py`

### Reference Files

**Pattern**: `<topic>-<type>.md`

**Type indicators**:
- `guide` - Comprehensive how-to
- `reference` - API or technical reference
- `patterns` - Pattern library
- `troubleshooting` - Problem-solution pairs

**Examples**:
- `api-reference.md`
- `forms-guide.md`
- `common-patterns.md`
- `troubleshooting.md`

### Template Files

**Pattern**: `<purpose>-template.<ext>`

**Examples**:
- `component-test-template.tsx`
- `api-endpoint-template.js`
- `migration-template.sql`

### Script Files

**Pattern**: `<action>_<target>.<ext>`

**Examples**:
- `analyze_form.py`
- `validate_fields.py`
- `fill_form.py`

### Directory Names

**Standard directories**:
- `examples/` - Code examples and demonstrations
- `reference/` - Detailed documentation
- `templates/` - Copy-paste starting points
- `scripts/` - Utility scripts for execution

**Domain-organized** (for large skills):
- `reference/finance/`
- `reference/sales/`
- `reference/product/`

## Platform-Specific Organization

### Single Platform Skill

```
skill-name/
├── SKILL.md                    # Platform clearly specified
└── examples/
    ├── pattern-good.py        # Python examples
    └── pattern-bad.py
```

### Multi-Platform Skill (Small)

```
skill-name/
├── SKILL.md                    # Includes platform detection logic
└── examples/
    ├── python-pattern-good.py
    ├── python-pattern-bad.py
    ├── javascript-pattern-good.js
    └── javascript-pattern-bad.js
```

### Multi-Platform Skill (Large)

```
skill-name/
├── SKILL.md                    # Platform-agnostic guidance
├── examples/
│   ├── python/
│   │   ├── basic-good.py
│   │   └── basic-bad.py
│   ├── javascript/
│   │   ├── basic-good.js
│   │   └── basic-bad.js
│   └── go/
│       ├── basic-good.go
│       └── basic-bad.go
└── reference/
    ├── python-specifics.md
    ├── javascript-specifics.md
    └── go-specifics.md
```

### Platform Detection in SKILL.md

```markdown
## Platform Detection

This Skill applies when working with:
- **Python**: Files with .py extension, imports `pdfplumber`
- **JavaScript**: Files with .js extension, imports `pdf-lib`
- **Go**: Files with .go extension, imports `pdfcpu`

Choose examples based on detected platform:
- Python examples: [examples/python/](examples/python/)
- JavaScript examples: [examples/javascript/](examples/javascript/)
- Go examples: [examples/go/](examples/go/)
```

## Size Guidelines and Limits

### Hard Limits

| File/Section | Hard Limit | Reason |
|--------------|------------|--------|
| SKILL.md total | 500 lines | Context window efficiency |
| Frontmatter | No limit | But stay under 1024 chars for description |
| name field | 64 characters | System requirement |
| description field | 1024 characters | System requirement |

### Recommended Targets

| File/Section | Target Size | Range |
|--------------|-------------|-------|
| SKILL.md | 400-450 lines | 350-500 lines |
| Example file | 250-400 lines | 200-500 lines |
| Reference file | 400-600 lines | 300-1000 lines |
| Template file | 100-200 lines | 50-300 lines |
| Script file | 100-300 lines | Varies by complexity |

### When Files Grow Too Large

**SKILL.md approaching 500 lines**:
1. Extract detailed examples to `examples/` directory
2. Move API reference to `reference/api-reference.md`
3. Move troubleshooting to `reference/troubleshooting.md`
4. Keep only core patterns and navigation in SKILL.md

**Reference file exceeding 1000 lines**:
1. Consider splitting by domain or topic
2. Add table of contents if keeping as single file
3. Example: Split `api-reference.md` into `api-core.md` and `api-advanced.md`

**Example file exceeding 500 lines**:
1. Split into separate good/bad files
2. Separate by complexity level (basic, intermediate, advanced)
3. Platform-specific organization

## Metadata Best Practices

### Timestamps

Add timestamps to all files:

```markdown
> **Last Updated**: 2025-12-20
```

Place at beginning of file, after title.

### Version Information

For SDK-specific skills:

```markdown
> **Last Updated**: 2025-12-20
> **SDK Version**: 4.12.0+
> **Platform**: Flutter/Dart
```

### File Headers in Examples

```python
# Example: API Query Patterns (Good)
# SDK Version: 4.12.0+
# Platform: Python
# Last Updated: 2025-12-20
```

## Path Conventions

### Always Use Forward Slashes

✅ **Correct**:
```markdown
See [reference/guide.md](reference/guide.md)
Run: `python scripts/validate.py`
```

❌ **Incorrect**:
```markdown
See [reference\guide.md](reference\guide.md)
Run: `python scripts\validate.py`
```

### Relative Paths from SKILL.md

All paths in SKILL.md are relative to skill directory:

```markdown
# In .claude/skills/pdf-processing/SKILL.md

[examples/good.py](examples/good.py)
[reference/api.md](reference/api.md)
[scripts/validate.py](scripts/validate.py)
```

### Cross-References Between Files

```markdown
# In examples/pattern-good.md

Back to main skill: [../SKILL.md](../SKILL.md)
Related reference: [../reference/api.md](../reference/api.md)
Related example: [pattern-bad.md](pattern-bad.md)
```

## Validation Checklist

Before finalizing skill structure:

**Directory Structure**:
- [ ] SKILL.md exists at root
- [ ] examples/ directory if needed
- [ ] reference/ directory if needed
- [ ] No deeply nested directories (max 2 levels)

**File Naming**:
- [ ] SKILL.md is capitalized
- [ ] Descriptive file names
- [ ] Consistent naming patterns
- [ ] Forward slashes in all paths

**Size Compliance**:
- [ ] SKILL.md under 500 lines
- [ ] Example files under 500 lines each
- [ ] Reference files have table of contents if >100 lines
- [ ] name field under 64 characters
- [ ] description field under 1024 characters

**Content Organization**:
- [ ] Progressive disclosure implemented
- [ ] References one level deep
- [ ] Platform-specific content organized
- [ ] Timestamps on all files
- [ ] Cross-references included

**Navigation**:
- [ ] Clear links from SKILL.md to reference files
- [ ] See Also section at end of SKILL.md
- [ ] Related content cross-referenced
- [ ] Table of contents for long files

## See Also

- [../SKILL.md](../SKILL.md) - Complete Skill authoring guidance
- [evaluation-patterns.md](evaluation-patterns.md) - Testing strategies
- [common-patterns-library.md](common-patterns-library.md) - Reusable templates
- [../examples/progressive-disclosure-good.md](../examples/progressive-disclosure-good.md) - Organization examples
