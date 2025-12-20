# Bad Skill Metadata Examples

> **Last Updated**: 2025-12-20

This file demonstrates common mistakes in YAML frontmatter for Skills, showing ineffective naming conventions, poor descriptions, and unclear trigger conditions.

## Bad Example 1: Vague and First Person

```yaml
---
name: pdf-helper
description: I can help you work with PDF files. Just ask me about PDFs and I'll help!
---
```

**Problems**:
- ❌ Name is vague ("helper" doesn't indicate what it does)
- ❌ First person ("I can help you")
- ❌ No specific triggers listed
- ❌ No critical issues prevented
- ❌ Doesn't explain what operations are supported
- ❌ No platform information

**Fixed version**:
```yaml
---
name: processing-pdfs
description: |
  Extracts text and tables from PDF files, fills forms, and merges documents.
  Use when working with PDF files, when users mention PDFs, forms, or document extraction.

  CRITICAL ISSUES PREVENTED:
  - Incorrect PDF library selection
  - Missing validation of form fields
  - Corrupted PDFs from improper editing

  TRIGGERS:
  - Files with .pdf extension
  - User mentions "PDF", "form", "document"

  PLATFORMS: All (Python, Node.js)
---
```

## Bad Example 2: Second Person

```yaml
---
name: excel-tool
description: You can use this skill to analyze Excel files and create reports.
---
```

**Problems**:
- ❌ Second person ("You can use")
- ❌ Generic name ("tool")
- ❌ No specific triggers
- ❌ No critical issues listed
- ❌ Vague about capabilities

**Fixed version**:
```yaml
---
name: analyzing-spreadsheets
description: |
  Analyzes Excel spreadsheets, creates pivot tables, generates charts, and
  performs data transformations. Use when analyzing .xlsx files, working with
  tabular data, or performing spreadsheet operations.

  CRITICAL ISSUES PREVENTED:
  - Memory overflow on large spreadsheets
  - Data corruption during transformations
  - Lost formatting when writing files

  TRIGGERS:
  - Files with .xlsx, .xls, .csv extensions
  - User mentions "Excel", "spreadsheet", "pivot table"

  PLATFORMS: All (Python openpyxl, Node.js ExcelJS)
---
```

## Bad Example 3: Too Brief

```yaml
---
name: db-helper
description: Helps with databases
---
```

**Problems**:
- ❌ Extremely vague
- ❌ No triggers
- ❌ No platform information
- ❌ No critical issues
- ❌ Doesn't specify what kind of help
- ❌ Abbreviation in name ("db")

**Fixed version**:
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

  PLATFORMS: PostgreSQL, MySQL, SQLite, MongoDB
---
```

## Bad Example 4: No Triggers

```yaml
---
name: api-testing
description: Creates comprehensive API tests including request/response validation and error handling.
---
```

**Problems**:
- ❌ Missing triggers section
- ❌ No critical issues listed
- ❌ No platform information
- ❌ Claude won't know when to activate this skill

**Fixed version**:
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

  PLATFORMS: All (language-agnostic patterns)
---
```

## Bad Example 5: Reserved Words

```yaml
---
name: claude-anthropic-helper
description: Helper tool for various tasks
---
```

**Problems**:
- ❌ Uses reserved word "claude"
- ❌ Uses reserved word "anthropic"
- ❌ Name doesn't indicate purpose
- ❌ Description is completely vague
- ❌ No triggers, no issues, no platforms

**Fixed version**:
```yaml
---
name: generating-documentation
description: |
  Generates comprehensive documentation from code, including API references,
  usage examples, and architectural diagrams. Use when creating documentation,
  updating README files, or documenting APIs.

  CRITICAL ISSUES PREVENTED:
  - Incomplete API documentation
  - Outdated examples
  - Missing usage instructions
  - Inconsistent documentation format

  TRIGGERS:
  - Files matching README.md, DOCUMENTATION.md, API.md
  - User mentions "documentation", "docs", "API reference"
  - Working in docs/ directory

  PLATFORMS: All
---
```

## Bad Example 6: Name Too Long

```yaml
---
name: processing-and-analyzing-pdf-documents-and-extracting-text-tables-forms
description: Processes PDF documents
---
```

**Problems**:
- ❌ Name exceeds 64 character limit
- ❌ Name is overly descriptive
- ❌ Description is too brief given long name
- ❌ No triggers or issues

**Fixed version**:
```yaml
---
name: processing-pdfs
description: |
  Extracts text and tables from PDF files, fills forms, and merges documents.
  Use when working with PDF files or when users mention PDFs, forms, or
  document extraction.

  CRITICAL ISSUES PREVENTED:
  - Incorrect PDF library selection
  - Missing validation of form fields
  - Corrupted PDFs from improper editing

  TRIGGERS:
  - Files with .pdf extension
  - User mentions "PDF", "form", "document"

  PLATFORMS: All
---
```

## Bad Example 7: Inconsistent Naming Pattern

In a project with multiple skills:

```yaml
# Skill 1
name: process-pdfs

# Skill 2
name: excel-analyzer

# Skill 3
name: testing-api

# Skill 4
name: doc-generator
```

**Problems**:
- ❌ No consistent naming pattern
- ❌ Mix of verb forms (process-, analyzer, testing-, generator)
- ❌ Inconsistent level of detail

**Fixed version** (consistent gerund form):
```yaml
# Skill 1
name: processing-pdfs

# Skill 2
name: analyzing-spreadsheets

# Skill 3
name: testing-apis

# Skill 4
name: generating-documentation
```

## Bad Example 8: Too Many Options Without Guidance

```yaml
---
name: data-processing
description: |
  Processes data using pandas, or polars, or dask, or spark, or numpy, or you
  can also use plain Python, or maybe R, or Julia. Works with CSV, JSON, XML,
  Parquet, or any other format.
---
```

**Problems**:
- ❌ Offers too many options without guidance
- ❌ No indication of when to use which tool
- ❌ No default recommendation
- ❌ No triggers or critical issues
- ❌ Overwhelming and unhelpful

**Fixed version**:
```yaml
---
name: processing-tabular-data
description: |
  Processes tabular data using pandas for analysis, transformations, and
  aggregations. Use when working with CSV, Excel, or structured data files.
  Handles data cleaning, filtering, merging, and reshaping.

  CRITICAL ISSUES PREVENTED:
  - Memory overflow on large datasets
  - Data type errors in operations
  - Lost data in transformations
  - Incorrect aggregations

  TRIGGERS:
  - Files with .csv, .xlsx, .parquet extensions
  - User mentions "data processing", "pandas", "dataframe"
  - Data analysis or transformation tasks

  PLATFORMS: Python (pandas)

  NOTE: For datasets >1GB, see reference/large-datasets.md for alternatives
---
```

## Bad Example 9: XML Tags in Description

```yaml
---
name: processing-pdfs
description: |
  <important>Extracts text</important> from PDF files.
  Use when <user>asks about PDFs</user>.
---
```

**Problems**:
- ❌ Contains XML tags (forbidden)
- ❌ Tags will cause parsing errors
- ❌ Unclear formatting purpose

**Fixed version**:
```yaml
---
name: processing-pdfs
description: |
  Extracts text and tables from PDF files, fills forms, and merges documents.
  Use when working with PDF files or when users mention PDFs, forms, or
  document extraction.

  CRITICAL ISSUES PREVENTED:
  - Incorrect PDF library selection
  - Missing validation of form fields

  TRIGGERS:
  - Files with .pdf extension
  - User mentions "PDF", "form", "document"

  PLATFORMS: All
---
```

## Bad Example 10: Missing Critical Context

```yaml
---
name: syncing-data
description: Syncs data between systems
---
```

**Problems**:
- ❌ What kind of data?
- ❌ Which systems?
- ❌ What sync patterns?
- ❌ No triggers
- ❌ No critical issues
- ❌ Too vague to be useful

**Fixed version**:
```yaml
---
name: syncing-ditto-data
description: |
  Implements data synchronization patterns using Ditto SDK, including real-time
  sync, conflict resolution, and offline-first strategies. Use when implementing
  Ditto sync, setting up subscriptions, or handling sync conflicts.

  CRITICAL ISSUES PREVENTED:
  - Sync loops and conflicts
  - Memory leaks from unclosed subscriptions
  - Data inconsistency across devices
  - Poor offline experience

  TRIGGERS:
  - Files importing Ditto SDK
  - User mentions "Ditto", "sync", "offline-first", "subscription"
  - Working with distributed data

  PLATFORMS: Flutter, JavaScript, Swift, Kotlin
---
```

## Common Metadata Mistakes Summary

### Name Issues
- ❌ Too vague: `helper`, `tool`, `utils`
- ❌ Too long: Exceeding 64 characters
- ❌ Reserved words: `claude`, `anthropic`
- ❌ Uppercase or special characters
- ❌ Inconsistent patterns across skills

### Description Issues
- ❌ First person: "I can help you"
- ❌ Second person: "You can use this"
- ❌ Too brief: Single sentence without details
- ❌ Missing triggers
- ❌ Missing critical issues
- ❌ Missing platform information
- ❌ Contains XML tags
- ❌ Over 1024 characters

### Structure Issues
- ❌ No CRITICAL ISSUES PREVENTED section
- ❌ No TRIGGERS section
- ❌ No PLATFORMS section
- ❌ Single line description without structure

### Content Issues
- ❌ Too many options without guidance
- ❌ Vague about capabilities
- ❌ No specific examples
- ❌ Doesn't explain when to use
- ❌ Missing file pattern triggers

## Testing Your Metadata

Ask these questions:

1. **Would Claude discover this Skill?**
   - Are triggers specific enough?
   - Do triggers match user language?

2. **Is the scope clear?**
   - Can someone understand what this does?
   - Are boundaries clear (what it doesn't do)?

3. **Is it actionable?**
   - Do triggers reference concrete things (file patterns, keywords)?
   - Are critical issues specific?

4. **Is it consistent?**
   - Does naming match other Skills?
   - Is terminology consistent?

5. **Is it third person?**
   - No "I can help you"
   - No "You can use this"

## Quick Fix Checklist

Before finalizing metadata:
- [ ] Name uses gerund form (or consistent pattern)
- [ ] Name is under 64 characters
- [ ] No reserved words in name
- [ ] Description in third person
- [ ] Description under 1024 characters
- [ ] No XML tags in description
- [ ] CRITICAL ISSUES PREVENTED section included
- [ ] TRIGGERS section with specific conditions
- [ ] PLATFORMS section included
- [ ] Description explains both what and when

## See Also

- [skill-metadata-good.md](skill-metadata-good.md) - Well-written metadata examples
- [../SKILL.md](../SKILL.md) - Full Skill authoring guidance
- [../reference/skill-structure-guide.md](../reference/skill-structure-guide.md) - Complete structure details
