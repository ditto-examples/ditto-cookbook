# Good Progressive Disclosure Examples

> **Last Updated**: 2025-12-20

This file demonstrates effective organization of Skills using progressive disclosure, where content is structured in tiers and loaded only as needed.

## Example 1: PDF Processing Skill (Comprehensive)

### File Structure

```
pdf-processing/
├── SKILL.md                    # Core guidance (450 lines)
├── examples/
│   ├── extract-text-good.py   # Text extraction example
│   ├── extract-text-bad.py    # Common mistakes
│   ├── fill-form-good.py      # Form filling example
│   └── fill-form-bad.py       # Form filling mistakes
├── reference/
│   ├── forms-guide.md         # Complete form filling guide
│   ├── api-reference.md       # pdfplumber API reference
│   └── troubleshooting.md     # Common issues and solutions
└── scripts/
    ├── analyze_form.py        # Utility: Extract form fields
    ├── validate_boxes.py      # Utility: Check bounding boxes
    └── fill_form.py           # Utility: Apply field values
```

### SKILL.md Content Organization

```markdown
---
name: processing-pdfs
description: |
  Extracts text and tables from PDF files, fills forms, and merges documents...
---

# PDF Processing

## Quick Start

Extract text with pdfplumber:
```python
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

## Core Operations

### Text Extraction
[Basic instructions here, 20-30 lines]

### Table Extraction
[Basic instructions here, 20-30 lines]

### Form Filling
This is a complex workflow requiring multiple steps.

**See**: [reference/forms-guide.md](reference/forms-guide.md) for complete guide

Quick overview:
1. Analyze form structure
2. Create field mapping
3. Validate mapping
4. Fill form
5. Verify output

### Document Merging
[Basic instructions here, 20-30 lines]

## Utility Scripts

**analyze_form.py**: Extract all form fields
```bash
python scripts/analyze_form.py input.pdf > fields.json
```

**validate_boxes.py**: Check for overlapping fields
```bash
python scripts/validate_boxes.py fields.json
```

**fill_form.py**: Apply field values
```bash
python scripts/fill_form.py input.pdf fields.json output.pdf
```

## Common Issues

For troubleshooting, see [reference/troubleshooting.md](reference/troubleshooting.md)

## API Reference

For complete pdfplumber API, see [reference/api-reference.md](reference/api-reference.md)
```

**Why this works**:
- ✅ SKILL.md stays under 500 lines
- ✅ Basic operations included directly
- ✅ Complex workflows point to detailed guides
- ✅ One level of reference depth
- ✅ Clear navigation with "See" links
- ✅ Utility scripts for execution, not loading into context

## Example 2: BigQuery Analysis Skill (Domain-Organized)

### File Structure

```
bigquery-analysis/
├── SKILL.md                    # Core guidance (380 lines)
├── examples/
│   ├── basic-queries-good.sql
│   ├── basic-queries-bad.sql
│   ├── joins-good.sql
│   └── joins-bad.sql
└── reference/
    ├── finance-schemas.md     # Revenue, billing metrics
    ├── sales-schemas.md       # Pipeline, opportunities
    ├── product-schemas.md     # API usage, features
    └── marketing-schemas.md   # Campaigns, attribution
```

### SKILL.md Content Organization

```markdown
---
name: analyzing-bigquery-data
description: |
  Queries and analyzes data in BigQuery across finance, sales, product,
  and marketing datasets...
---

# BigQuery Data Analysis

## Available Datasets

### Finance
Revenue, ARR, billing metrics

**Full schemas**: [reference/finance-schemas.md](reference/finance-schemas.md)

Common queries:
- Monthly recurring revenue (MRR)
- Customer lifetime value (CLV)
- Churn rate

### Sales
Opportunities, pipeline, accounts

**Full schemas**: [reference/sales-schemas.md](reference/sales-schemas.md)

Common queries:
- Pipeline by stage
- Win rate analysis
- Sales cycle length

### Product
API usage, features, adoption

**Full schemas**: [reference/product-schemas.md](reference/product-schemas.md)

Common queries:
- Feature adoption rates
- API usage patterns
- User engagement metrics

### Marketing
Campaigns, attribution, email

**Full schemas**: [reference/marketing-schemas.md](reference/marketing-schemas.md)

Common queries:
- Campaign performance
- Attribution models
- Email engagement

## Quick Search

Find specific metrics:

```bash
grep -i "revenue" reference/finance-schemas.md
grep -i "pipeline" reference/sales-schemas.md
grep -i "api usage" reference/product-schemas.md
```

## Common Patterns

[Basic query patterns here, 50-60 lines]
```

**Why this works**:
- ✅ Domain-organized references
- ✅ Claude loads only relevant schema file
- ✅ Quick overview of each domain in SKILL.md
- ✅ Grep pattern for quick lookup
- ✅ Scales well to many domains

## Example 3: React Component Testing Skill

### File Structure

```
testing-react-components/
├── SKILL.md                    # Core guidance (420 lines)
├── examples/
│   ├── unit-test-good.tsx
│   ├── unit-test-bad.tsx
│   ├── integration-test-good.tsx
│   ├── integration-test-bad.tsx
│   ├── hooks-test-good.tsx
│   └── hooks-test-bad.tsx
├── reference/
│   ├── testing-library-guide.md
│   ├── jest-patterns.md
│   └── common-pitfalls.md
└── templates/
    ├── component-test-template.tsx
    ├── hook-test-template.tsx
    └── integration-test-template.tsx
```

### SKILL.md Content Organization

```markdown
---
name: testing-react-components
description: |
  Creates comprehensive React component tests using Testing Library and Jest...
---

# React Component Testing

## Test Types

### Unit Tests
Test individual components in isolation.

**Template**: [templates/component-test-template.tsx](templates/component-test-template.tsx)
**Example**: [examples/unit-test-good.tsx](examples/unit-test-good.tsx)

Basic structure:
```tsx
import { render, screen } from '@testing-library/react'
import { UserProfile } from './UserProfile'

describe('UserProfile', () => {
  it('displays user information', () => {
    render(<UserProfile user={mockUser} />)
    expect(screen.getByText('John Doe')).toBeInTheDocument()
  })
})
```

### Integration Tests
Test component interactions.

**Template**: [templates/integration-test-template.tsx](templates/integration-test-template.tsx)
**Example**: [examples/integration-test-good.tsx](examples/integration-test-good.tsx)

### Hook Tests
Test custom React hooks.

**Template**: [templates/hook-test-template.tsx](templates/hook-test-template.tsx)
**Example**: [examples/hooks-test-good.tsx](examples/hooks-test-good.tsx)

## Testing Library Guide

For complete Testing Library patterns:
[reference/testing-library-guide.md](reference/testing-library-guide.md)

## Common Pitfalls

For troubleshooting and common mistakes:
[reference/common-pitfalls.md](reference/common-pitfalls.md)
```

**Why this works**:
- ✅ Templates for copy-paste usage
- ✅ Examples demonstrate patterns in practice
- ✅ Reference files for comprehensive guidance
- ✅ Clear separation of concerns
- ✅ Basic examples in SKILL.md, details in references

## Example 4: Docker Deployment Skill (Workflow-Focused)

### File Structure

```
deploying-docker/
├── SKILL.md                    # Core guidance (390 lines)
├── examples/
│   ├── dockerfile-good
│   ├── dockerfile-bad
│   ├── docker-compose-good.yml
│   └── docker-compose-bad.yml
├── reference/
│   ├── security-hardening.md
│   ├── multi-stage-builds.md
│   └── optimization-guide.md
└── scripts/
    ├── validate_dockerfile.sh
    └── security_scan.sh
```

### SKILL.md Content Organization

```markdown
---
name: deploying-docker
description: |
  Creates production-ready Docker containers with security hardening
  and optimization...
---

# Docker Deployment

## Deployment Workflow

Copy this checklist:

```
Deployment Progress:
- [ ] Step 1: Write Dockerfile
- [ ] Step 2: Validate Dockerfile
- [ ] Step 3: Run security scan
- [ ] Step 4: Build and test locally
- [ ] Step 5: Push to registry
```

### Step 1: Write Dockerfile

Use multi-stage build pattern:
```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine
COPY --from=builder /app/node_modules ./node_modules
COPY . .
CMD ["node", "server.js"]
```

**Complete guide**: [reference/multi-stage-builds.md](reference/multi-stage-builds.md)

### Step 2: Validate Dockerfile

Run validation:
```bash
./scripts/validate_dockerfile.sh Dockerfile
```

### Step 3: Run Security Scan

Run security checks:
```bash
./scripts/security_scan.sh
```

**Security hardening guide**: [reference/security-hardening.md](reference/security-hardening.md)

### Step 4: Build and Test

[Build and test instructions, 30-40 lines]

### Step 5: Push to Registry

[Push instructions, 20-30 lines]

## Optimization

For performance optimization:
[reference/optimization-guide.md](reference/optimization-guide.md)
```

**Why this works**:
- ✅ Workflow-focused structure
- ✅ Checklist for progress tracking
- ✅ Validation scripts for quality
- ✅ Basic examples inline
- ✅ Deep-dive topics in references

## Key Principles Demonstrated

### 1. Keep SKILL.md Focused
- Core operations included directly
- Complex topics reference external files
- Target: 350-500 lines

### 2. One Level of References
```
SKILL.md
├─→ examples/pattern-good.md     ✅ Direct reference
├─→ reference/guide.md           ✅ Direct reference
└─→ reference/advanced.md        ✅ Direct reference
    └─→ reference/details.md     ❌ Nested too deep
```

### 3. Domain Organization
For large Skills covering multiple domains:
- Split reference files by domain
- Quick overview of each domain in SKILL.md
- Claude loads only relevant domain file

### 4. Template + Example + Reference
- **Template**: Copy-paste starting point
- **Example**: Realistic usage demonstration
- **Reference**: Comprehensive documentation

### 5. Executable Scripts
- Validation and utility scripts in `scripts/`
- Claude executes, doesn't load into context
- Saves tokens and ensures consistency

## Table of Contents Pattern

For reference files over 100 lines, include TOC:

```markdown
# Multi-Stage Docker Builds Guide

## Contents
- Introduction to multi-stage builds
- Basic two-stage pattern
- Advanced multi-stage patterns
- Language-specific examples
- Optimization techniques
- Common mistakes

## Introduction to Multi-Stage Builds
[Content...]

## Basic Two-Stage Pattern
[Content...]
```

This ensures Claude can see full scope even with partial reads.

## Navigation Patterns

### Explicit Navigation
```markdown
**See**: [reference/guide.md](reference/guide.md) for complete guide
```

### Conditional Navigation
```markdown
**For simple cases**: Follow inline instructions
**For complex scenarios**: See [reference/advanced-guide.md](reference/advanced-guide.md)
```

### Search Navigation
```markdown
Find specific topics:
```bash
grep -i "topic" reference/guide.md
```
```

## Anti-Patterns (See progressive-disclosure-bad.md)

❌ Everything in SKILL.md (>800 lines)
❌ Deeply nested references (3+ levels)
❌ Unclear navigation ("see other docs")
❌ No domain organization for large Skills
❌ Loading scripts into context instead of executing

## Testing Progressive Disclosure

Verify effectiveness by observing:
1. Does Claude find referenced files?
2. Does Claude read complete files or preview them?
3. Does Claude load unnecessary content?
4. Are navigation paths intuitive?

## See Also

- [progressive-disclosure-bad.md](progressive-disclosure-bad.md) - Common structure mistakes
- [reference-organization-good.md](reference-organization-good.md) - Reference file organization
- [../SKILL.md](../SKILL.md) - Full Skill authoring guidance
- [../reference/skill-structure-guide.md](../reference/skill-structure-guide.md) - Structure details
