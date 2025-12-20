# Good Skill Metadata Examples

> **Last Updated**: 2025-12-20

This file demonstrates well-written YAML frontmatter for Skills, showing effective naming conventions, comprehensive descriptions, and clear trigger conditions.

## Example 1: PDF Processing Skill

```yaml
---
name: processing-pdfs
description: |
  Extracts text and tables from PDF files, fills forms, and merges documents.
  Use when working with PDF files, when users mention PDFs, forms, document
  extraction, or need to manipulate PDF content.

  CRITICAL ISSUES PREVENTED:
  - Incorrect PDF library selection for the task
  - Missing validation of form field names
  - Corrupted PDFs from improper editing
  - Memory issues from loading large PDFs

  TRIGGERS:
  - Files with .pdf extension
  - User mentions "PDF", "form", "document extraction"
  - Tasks involving PDF manipulation or analysis

  PLATFORMS: All (Python, Node.js)
---
```

**Why this works**:
- ✅ Name uses gerund form (`processing-pdfs`)
- ✅ Description is specific about capabilities
- ✅ Clear trigger conditions listed
- ✅ Written in third person
- ✅ Includes critical issues prevented
- ✅ Under 1024 characters

## Example 2: Excel Analysis Skill

```yaml
---
name: analyzing-spreadsheets
description: |
  Analyzes Excel spreadsheets, creates pivot tables, generates charts, and
  performs data transformations. Use when analyzing Excel files, working with
  tabular data, .xlsx files, or performing spreadsheet operations.

  CRITICAL ISSUES PREVENTED:
  - Incorrect handling of Excel formulas
  - Memory overflow on large spreadsheets
  - Data corruption during transformations
  - Lost formatting when writing files

  TRIGGERS:
  - Files with .xlsx, .xls, .csv extensions
  - User mentions "Excel", "spreadsheet", "pivot table"
  - Tasks involving data analysis or reporting

  PLATFORMS: All (Python with openpyxl, Node.js with ExcelJS)
---
```

**Why this works**:
- ✅ Descriptive name indicating the activity
- ✅ Comprehensive trigger conditions
- ✅ Platform information included
- ✅ Lists specific issues the Skill prevents
- ✅ Clear about file extensions

## Example 3: Git Commit Helper Skill

```yaml
---
name: generating-commit-messages
description: |
  Generates descriptive commit messages by analyzing git diffs. Use when
  users ask for help writing commit messages, reviewing staged changes,
  or need assistance with git commit workflow.

  CRITICAL ISSUES PREVENTED:
  - Vague or uninformative commit messages
  - Inconsistent commit message format
  - Missing context about why changes were made
  - Commits that don't follow project conventions

  TRIGGERS:
  - User asks about commit messages
  - Working with git diff or staged changes
  - User mentions "commit", "git", "changelog"
  - Files in .git directory context

  PLATFORMS: All (git command-line)
---
```

**Why this works**:
- ✅ Gerund form name
- ✅ Specific about the analysis process
- ✅ Clear user intent triggers
- ✅ Platform-agnostic indication
- ✅ Prevents common quality issues

## Example 4: Database Migration Skill

```yaml
---
name: managing-database-migrations
description: |
  Handles database schema migrations, version control, and rollback procedures.
  Use when creating database migrations, modifying schemas, or managing database
  versions. Prevents migration conflicts and data loss.

  CRITICAL ISSUES PREVENTED:
  - Irreversible migrations without rollback
  - Schema conflicts in team environments
  - Data loss during migrations
  - Out-of-order migration execution

  TRIGGERS:
  - Files in migrations/ or db/ directories
  - User mentions "migration", "schema", "database version"
  - SQL files with version numbers
  - Tasks involving database structure changes

  PLATFORMS: PostgreSQL, MySQL, SQLite, MongoDB
---
```

**Why this works**:
- ✅ Clear scope (migrations, not all DB operations)
- ✅ Specific file path triggers
- ✅ Multiple platform support listed
- ✅ Emphasizes critical safety issues
- ✅ Comprehensive trigger conditions

## Example 5: API Testing Skill

```yaml
---
name: testing-api-endpoints
description: |
  Creates comprehensive API tests including request/response validation,
  error handling, and edge cases. Use when writing API tests, validating
  endpoints, or ensuring API reliability.

  CRITICAL ISSUES PREVENTED:
  - Missing error case coverage
  - Inadequate request validation
  - Untested edge cases
  - Flaky tests from timing issues

  TRIGGERS:
  - Files matching **/tests/api/** or **/*_test.{js,py,go}
  - User mentions "API test", "endpoint test", "integration test"
  - Working with HTTP client libraries
  - Testing REST or GraphQL APIs

  PLATFORMS: All (language-agnostic patterns)
---
```

**Why this works**:
- ✅ Focused on specific testing domain
- ✅ Glob patterns in triggers
- ✅ Multiple test file naming conventions
- ✅ Language-agnostic approach
- ✅ Addresses common testing pitfalls

## Key Takeaways

### Name Requirements
- Lowercase letters, numbers, hyphens only
- Maximum 64 characters
- Gerund form preferred: `processing-`, `analyzing-`, `managing-`
- No reserved words: "anthropic", "claude"

### Description Requirements
- Maximum 1024 characters
- Third person perspective always
- Include both what and when
- List critical issues prevented
- Specify clear triggers
- Platform information if applicable

### Trigger Patterns
- File extensions: `.pdf`, `.xlsx`, `.js`
- Directory patterns: `migrations/`, `tests/api/`
- User intent: "analyze spreadsheet", "write tests"
- Technical terms: "migration", "API endpoint"
- Glob patterns for file matching

### Structure Elements
1. **First paragraph**: What the Skill does
2. **CRITICAL ISSUES PREVENTED**: Bullet list of key problems
3. **TRIGGERS**: Bullet list of activation conditions
4. **PLATFORMS**: Supported platforms or "All"

## Common Description Patterns

### Pattern: Domain-Specific Tool
```yaml
description: |
  [Action] [specific artifacts] using [specific tool/approach].
  Use when [user intent] or [file patterns].

  CRITICAL ISSUES PREVENTED:
  - [Issue 1]
  - [Issue 2]

  TRIGGERS:
  - [File pattern]
  - [User mentions]
```

### Pattern: Multi-Step Workflow
```yaml
description: |
  Guides [specific workflow] including [step 1], [step 2], and [step 3].
  Use when [workflow scenario] or [user needs guidance on process].

  CRITICAL ISSUES PREVENTED:
  - [Workflow mistake 1]
  - [Workflow mistake 2]

  TRIGGERS:
  - [Workflow keywords]
  - [Related file types]
```

### Pattern: Quality Assurance
```yaml
description: |
  Ensures [quality aspect] by [validation approach]. Use when [quality
  concern] or [verification need].

  CRITICAL ISSUES PREVENTED:
  - [Quality issue 1]
  - [Quality issue 2]

  TRIGGERS:
  - [Quality keywords]
  - [Validation scenarios]
```

## Anti-Patterns (Avoid These)

❌ **First person**: "I can help you process PDFs"
❌ **Second person**: "You can use this to process PDFs"
❌ **Vague**: "Helps with documents"
❌ **Too brief**: "Processes files"
❌ **No triggers**: Missing specific activation conditions
❌ **Reserved words**: "claude-helper", "anthropic-tool"
❌ **Inconsistent naming**: Mix of patterns within organization

## Testing Your Metadata

To verify metadata quality, ask:

1. **Discoverability**: Would Claude choose this Skill for relevant tasks?
2. **Specificity**: Does the description include key terms users would mention?
3. **Clarity**: Is it immediately obvious what the Skill does?
4. **Completeness**: Are all trigger conditions covered?
5. **Consistency**: Does naming follow established patterns?

## See Also

- [skill-metadata-bad.md](skill-metadata-bad.md) - Common metadata mistakes
- [../SKILL.md](../SKILL.md) - Full Skill authoring guidance
- [../reference/skill-structure-guide.md](../reference/skill-structure-guide.md) - Complete structure breakdown
