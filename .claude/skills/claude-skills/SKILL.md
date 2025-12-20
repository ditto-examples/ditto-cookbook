---
name: authoring-claude-skills
description: |
  Guides effective authoring, structuring, and maintenance of Claude Code Skills. Use when creating new Skills, iterating on existing Skills, organizing Skill content, or helping users understand Skills best practices.

  CRITICAL ISSUES PREVENTED:
  - Bloated SKILL.md files exceeding 500 lines
  - Poorly written metadata preventing Skill discovery
  - Deeply nested file references causing incomplete reads
  - Inconsistent terminology confusing Claude
  - Missing workflows for complex multi-step tasks
  - Time-sensitive information becoming outdated
  - Over-engineering with excessive abstraction

  TRIGGERS:
  - User asks to create a new Skill
  - User wants to improve or refactor existing Skills
  - Working with files in .claude/skills/ directory
  - User asks about Skills best practices
  - Helping organize Skill content or structure
  - User mentions "progressive disclosure" or "Skill metadata"
  - Reviewing or debugging Skill effectiveness

  PLATFORMS: All (Skills are platform-agnostic)
---

# Authoring Claude Code Skills

**Last Updated**: 2025-12-20

## Purpose

This Skill provides comprehensive guidance for creating, structuring, and maintaining effective Claude Code Skills. It consolidates best practices from official documentation into actionable patterns that ensure Skills are discoverable, maintainable, and effective.

## When This Skill Applies

Use this Skill when:
- Creating new Skills from scratch
- Iterating on existing Skills based on usage feedback
- Organizing Skill content and file structure
- Writing Skill metadata (name/description)
- Designing workflows for complex tasks
- Troubleshooting Skill discovery or effectiveness issues
- Helping users understand Skills architecture

## Platform Detection

This Skill applies when working with:
- Files in `.claude/skills/` directory structure
- SKILL.md files with YAML frontmatter
- Skills-related documentation or guides
- User requests mentioning "Skill" or "skill authoring"

## Core Principles

### 1. Conciseness is Key

**Context window is a public good**. Every token in your Skill competes with conversation history and other context. Only include information Claude doesn't already have.

**Default assumption**: Claude is already very smart. Challenge each piece of information:
- "Does Claude really need this explanation?"
- "Can I assume Claude knows this?"
- "Does this paragraph justify its token cost?"

**Target**: Keep SKILL.md under 500 lines. Use progressive disclosure for additional content.

### 2. Progressive Disclosure Architecture

Organize content in three tiers:
- **Tier 1**: SKILL.md (core guidance, loaded when triggered)
- **Tier 2**: examples/ (concrete demonstrations, loaded as needed)
- **Tier 3**: reference/ (deep-dive documentation, loaded as needed)

**Key principle**: Claude reads SKILL.md first, then navigates to specific files based on task needs.

### 3. Set Appropriate Degrees of Freedom

Match specificity to task fragility:
- **High freedom**: Multiple approaches valid, context-dependent decisions
- **Medium freedom**: Preferred patterns exist, some variation acceptable
- **Low freedom**: Operations are fragile, specific sequence required

## Common Workflows

### Workflow 1: Creating a New Skill

Copy this checklist and track your progress:

```
New Skill Creation:
- [ ] Step 1: Identify the reusable pattern from completed task
- [ ] Step 2: Draft YAML frontmatter with name and description
- [ ] Step 3: Write core content in SKILL.md (<500 lines)
- [ ] Step 4: Create example files for key patterns
- [ ] Step 5: Add reference files for detailed topics
- [ ] Step 6: Test with real usage scenarios
- [ ] Step 7: Iterate based on observation
```

**Step 1: Identify the reusable pattern**

After completing a task with Claude, identify:
- What context was repeatedly provided
- What procedural knowledge would benefit similar tasks
- What rules or conventions should be consistently applied

**Step 2: Draft YAML frontmatter**

Create name and description following these rules:
- **name**: lowercase, hyphens, max 64 chars, gerund form preferred
- **description**: third person, includes triggers, max 1024 chars

See [examples/skill-metadata-good.md](examples/skill-metadata-good.md) for examples.

**Step 3: Write core content**

Organize SKILL.md with these sections:
- Purpose
- When This Skill Applies
- Platform Detection
- Core Principles (3-5 key concepts)
- Common Workflows (with checklists)
- Critical Patterns (15-20 prioritized patterns)
- Quick Reference Checklist
- See Also

**Step 4: Create example files**

For each key pattern, create paired examples:
- `pattern-name-good.md`: Demonstrates best practice
- `pattern-name-bad.md`: Shows common mistakes

**Step 5: Add reference files**

Extract detailed content into topic-focused files:
- Keep file names descriptive
- Use forward slashes in paths
- Structure long files with table of contents
- Keep references one level deep from SKILL.md

**Step 6: Test with real usage**

Test the Skill with:
- Fresh Claude instance (simulates real usage)
- Actual tasks, not test scenarios
- All target models (Haiku, Sonnet, Opus)

**Step 7: Iterate based on observation**

Watch for:
- Unexpected exploration paths
- Missed connections to referenced files
- Overreliance on certain sections
- Ignored content

### Workflow 2: Iterating on Existing Skills

Copy this checklist and track your progress:

```
Skill Iteration:
- [ ] Step 1: Use Skill in real workflow
- [ ] Step 2: Observe Claude's behavior
- [ ] Step 3: Identify specific issues
- [ ] Step 4: Draft improvements with Claude A
- [ ] Step 5: Apply changes
- [ ] Step 6: Test with Claude B
- [ ] Step 7: Repeat based on usage
```

**Claude A/B Pattern**: Work with one Claude instance (A) to refine the Skill, test with another instance (B) that uses the Skill for real work.

See [reference/iterative-development.md](reference/iterative-development.md) for detailed guidance.

## Critical Patterns

### CRITICAL Priority

#### Pattern 1: Keep SKILL.md Under 500 Lines

**Problem**: Large SKILL.md files consume excessive context when loaded.

**Solution**: Use progressive disclosure. Split content into referenced files.

**Good example**:
```markdown
## Advanced Features

**Form filling**: See [reference/forms-guide.md](reference/forms-guide.md)
**API reference**: See [reference/api-reference.md](reference/api-reference.md)
```

**When**: SKILL.md approaches 500 lines.

#### Pattern 2: Write Descriptions in Third Person with Clear Triggers

**Problem**: Inconsistent point-of-view confuses Skill discovery.

**Solution**: Always use third person and include specific trigger conditions.

**Good example**:
```yaml
description: |
  Processes Excel files and generates reports. Use when working with
  .xlsx files, spreadsheets, or tabular data analysis.
```

**Bad example**:
```yaml
description: I can help you process Excel files
```

**When**: Writing or updating YAML frontmatter.

See [examples/skill-metadata-good.md](examples/skill-metadata-good.md) and [examples/skill-metadata-bad.md](examples/skill-metadata-bad.md).

#### Pattern 3: Avoid Deeply Nested References

**Problem**: Claude may partially read nested references (using head -100), resulting in incomplete information.

**Solution**: Keep all references one level deep from SKILL.md.

**Good structure**:
```
SKILL.md
├─→ examples/pattern-good.md
├─→ examples/pattern-bad.md
└─→ reference/api-reference.md
```

**Bad structure** (too deep):
```
SKILL.md
└─→ advanced.md
    └─→ details.md  # Claude may incompletely read this
```

**When**: Organizing Skill file structure.

See [examples/progressive-disclosure-good.md](examples/progressive-disclosure-good.md).

#### Pattern 4: Use Forward Slashes in All File Paths

**Problem**: Backslashes cause errors on Unix systems.

**Solution**: Always use forward slashes, even on Windows.

**Good**: `reference/guide.md`, `scripts/helper.py`
**Bad**: `reference\guide.md`, `scripts\helper.py`

**When**: Writing any file path in Skills.

#### Pattern 5: Test with All Target Models

**Problem**: Skills may work well for Opus but lack detail for Haiku.

**Solution**: Test with Haiku, Sonnet, and Opus. Adjust detail level accordingly.

**Testing considerations**:
- **Haiku**: Does the Skill provide enough guidance?
- **Sonnet**: Is the Skill clear and efficient?
- **Opus**: Does the Skill avoid over-explaining?

**When**: Before finalizing a new or updated Skill.

### HIGH Priority

#### Pattern 6: Provide Utility Scripts for Complex Operations

**Problem**: Generated code is less reliable than pre-written scripts.

**Solution**: Include executable scripts for deterministic operations.

**Benefits**:
- More reliable than generated code
- Save tokens (no code in context)
- Ensure consistency

**Example**:
```markdown
## Validate Form Fields

Run: `python scripts/validate_fields.py fields.json`

This checks for:
- Missing required fields
- Invalid data types
- Overlapping bounding boxes
```

**When**: Tasks involve fragile operations or complex validation.

#### Pattern 7: Use Workflows with Checklists for Multi-Step Tasks

**Problem**: Claude may skip critical validation steps.

**Solution**: Provide clear workflows with copy-paste checklists.

**Good example**:
````markdown
## PDF Form Filling Workflow

Copy this checklist:

```
Task Progress:
- [ ] Step 1: Analyze form
- [ ] Step 2: Create field mapping
- [ ] Step 3: Validate mapping
- [ ] Step 4: Fill form
- [ ] Step 5: Verify output
```
````

**When**: Tasks require multiple sequential steps.

See [examples/workflow-patterns-good.md](examples/workflow-patterns-good.md).

#### Pattern 8: Implement Feedback Loops

**Problem**: Errors discovered late require extensive rework.

**Solution**: Use validate → fix → repeat pattern.

**Common pattern**:
```markdown
1. Make your edits
2. Validate immediately: `python validate.py`
3. If validation fails:
   - Review error message
   - Fix issues
   - Run validation again
4. Only proceed when validation passes
```

**When**: Output quality is critical or changes are complex.

#### Pattern 9: Organize Reference Files by Domain

**Problem**: Loading irrelevant reference content wastes tokens.

**Solution**: Split large reference content by domain or topic.

**Good structure**:
```
reference/
├── finance-schemas.md
├── sales-schemas.md
└── product-schemas.md
```

**When**: Skills cover multiple distinct domains or contexts.

See [examples/reference-organization-good.md](examples/reference-organization-good.md).

#### Pattern 10: Make Execution Intent Clear

**Problem**: Unclear whether Claude should execute or read scripts as reference.

**Solution**: Explicitly state "Run" or "See" for each script.

**Execute**: "Run `analyze_form.py` to extract fields"
**Reference**: "See `analyze_form.py` for the extraction algorithm"

**When**: Including any scripts in Skills.

### MEDIUM Priority

#### Pattern 11: Use Consistent Terminology

**Problem**: Mixing terms confuses Claude.

**Solution**: Choose one term and use it throughout.

**Good**: Always "API endpoint", always "field", always "extract"
**Bad**: Mix "endpoint", "URL", "route"; mix "field", "box", "element"

**When**: Writing all Skill content.

#### Pattern 12: Provide Templates for Structured Output

**Problem**: Output format varies without clear examples.

**Solution**: Include templates with appropriate strictness level.

**For strict requirements**:
````markdown
ALWAYS use this exact template:

```markdown
# [Title]
## Summary
[Content]
```
````

**For flexible guidance**:
````markdown
Here is a sensible default format:

```markdown
# [Title]
## Summary
[Content]
```

Adjust sections as needed.
````

**When**: Output format consistency matters.

See [reference/common-patterns-library.md](reference/common-patterns-library.md).

#### Pattern 13: Include Input/Output Examples

**Problem**: Desired style unclear from descriptions alone.

**Solution**: Provide concrete input/output pairs.

**Example**:
````markdown
## Commit Message Format

**Example 1:**
Input: Added user authentication
Output:
```
feat(auth): implement JWT authentication

Add login endpoint and token validation
```
````

**When**: Output quality depends on seeing examples.

#### Pattern 14: Structure Long Reference Files with Table of Contents

**Problem**: Claude may preview long files with partial reads (head -100).

**Solution**: Include table of contents at top of files over 100 lines.

**Example**:
```markdown
# API Reference

## Contents
- Authentication setup
- Core methods
- Advanced features
- Error handling
- Code examples

## Authentication setup
...
```

**When**: Reference files exceed 100 lines.

#### Pattern 15: Document Configuration Values

**Problem**: Unexplained constants ("voodoo constants") confuse Claude.

**Solution**: Document why each value is chosen.

**Good**:
```python
# HTTP requests typically complete within 30 seconds
# Longer timeout accounts for slow connections
REQUEST_TIMEOUT = 30
```

**Bad**:
```python
TIMEOUT = 47  # Why 47?
```

**When**: Scripts include configuration parameters.

## Content Guidelines

### Avoid Time-Sensitive Information

Don't include information that will become outdated.

**Bad**: "If you're doing this before August 2025, use the old API"

**Good**: Use "old patterns" section
```markdown
## Current Method

Use v2 API endpoint: `api.example.com/v2/messages`

## Old Patterns

<details>
<summary>Legacy v1 API (deprecated 2025-08)</summary>
The v1 API used: `api.example.com/v1/messages`
This endpoint is no longer supported.
</details>
```

### Use Visual Analysis When Applicable

When inputs can be rendered as images, have Claude analyze them visually.

### Create Verifiable Intermediate Outputs

For complex tasks, use plan-validate-execute pattern:
1. Claude creates structured plan file
2. Script validates plan
3. Claude fixes issues if validation fails
4. Execute only after validation passes

## Common Anti-Patterns to Avoid

### Anti-Pattern 1: Too Many Options

**Problem**: Offering multiple approaches without clear guidance.

**Instead**: Provide a default with escape hatch.

**Good**:
```markdown
Use pdfplumber for text extraction.

For scanned PDFs requiring OCR, use pdf2image with pytesseract instead.
```

**Bad**:
```markdown
You can use pypdf, or pdfplumber, or PyMuPDF, or pdf2image, or...
```

See [examples/skill-metadata-bad.md](examples/skill-metadata-bad.md).

### Anti-Pattern 2: Over-Explaining Common Knowledge

**Problem**: Wasting tokens on information Claude already knows.

**Good**: "Use pdfplumber for text extraction"
**Bad**: "PDF (Portable Document Format) files are a common format that contains text and images. To extract text..."

### Anti-Pattern 3: Vague Skill Names

**Problem**: Generic names don't indicate Skill purpose.

**Good**: `processing-pdfs`, `analyzing-spreadsheets`
**Bad**: `helper`, `utils`, `tools`

### Anti-Pattern 4: Scripts That Punt to Claude

**Problem**: Scripts fail and leave Claude to figure out solutions.

**Good**: Handle errors explicitly with fallbacks
**Bad**: Just fail and let Claude handle it

## Naming Conventions

Use **gerund form** (verb + -ing) for Skill names:
- `processing-pdfs`
- `analyzing-spreadsheets`
- `managing-databases`
- `testing-code`
- `writing-documentation`

**Acceptable alternatives**:
- Noun phrases: `pdf-processing`, `spreadsheet-analysis`
- Action-oriented: `process-pdfs`, `analyze-spreadsheets`

**Requirements**:
- Lowercase letters, numbers, hyphens only
- Maximum 64 characters
- No XML tags
- No reserved words: "anthropic", "claude"

## Quick Reference Checklist

Before finalizing a Skill, verify:

**Core Quality**:
- [ ] Description is specific and includes key terms
- [ ] Description includes what Skill does and when to use it
- [ ] Description written in third person
- [ ] SKILL.md body under 500 lines
- [ ] Additional details in separate files (if needed)
- [ ] No time-sensitive information (or in "old patterns" section)
- [ ] Consistent terminology throughout
- [ ] Examples are concrete, not abstract
- [ ] File references one level deep
- [ ] Progressive disclosure used appropriately
- [ ] Workflows have clear steps with checklists

**Code and Scripts** (if applicable):
- [ ] Scripts solve problems rather than punt to Claude
- [ ] Error handling is explicit and helpful
- [ ] No "voodoo constants" (all values justified)
- [ ] Required packages listed and verified available
- [ ] Scripts have clear documentation
- [ ] No Windows-style paths (all forward slashes)
- [ ] Validation steps for critical operations
- [ ] Feedback loops for quality-critical tasks
- [ ] Execution intent clear (run vs read as reference)

**Testing**:
- [ ] Tested with real usage scenarios
- [ ] Tested with Haiku, Sonnet, and Opus (if targeting all)
- [ ] Team feedback incorporated (if applicable)
- [ ] Observed Claude's navigation patterns
- [ ] Verified Skill triggers appropriately

**Structure**:
- [ ] Follows three-tier progressive disclosure
- [ ] Consistent file naming conventions
- [ ] Metadata includes timestamps
- [ ] README provides navigation guidance
- [ ] File organization matches established patterns

## See Also

- [reference/skill-structure-guide.md](reference/skill-structure-guide.md) - Complete file structure breakdown
- [reference/evaluation-patterns.md](reference/evaluation-patterns.md) - Testing strategies
- [reference/iterative-development.md](reference/iterative-development.md) - Claude A/B workflow
- [reference/common-patterns-library.md](reference/common-patterns-library.md) - Reusable templates
- [examples/](examples/) - Good vs bad pattern demonstrations
