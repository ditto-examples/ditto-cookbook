---
paths:
  - .claude/guides/best-practices/ditto.md
  - .claude/skills/ditto/**
version: 1.0
last_updated: 2025-12-23
priority: CRITICAL
---

# Ditto Best Practices Synchronization Workflow

## Purpose

Ensures synchronization between the authoritative Ditto best practices guide and derivative Agent Skills. This maintains accuracy and consistency of real-time guidance provided to developers.

## When This Rule Applies

**MANDATORY TRIGGER**: After editing `.claude/guides/best-practices/ditto.md`

**OPTIONAL SKIP**: If changes are purely conceptual content without actionable patterns (see "When to Update" below)

## Critical Files Relationship

- **Source of Truth**: `.claude/guides/best-practices/ditto.md` (comprehensive reference)
- **Derivative Content**: `.claude/skills/ditto/*` (actionable patterns extracted from main guide)
  - `query-sync/SKILL.md` + examples + reference
  - `data-modeling/SKILL.md` + examples + reference
  - `storage-lifecycle/SKILL.md` + examples + reference
  - `transactions-attachments/SKILL.md` + examples + reference
  - `performance-observability/SKILL.md` + examples + reference

## Documentation Format Requirements

The ditto.md file must include version and timestamp information at the **beginning** of the document (immediately after the title):

```markdown
> **Version**: X.Y
> **Last Updated**: YYYY-MM-DD
```

**Version Semantics** (Semantic Versioning - Major.Minor):
- **Major (X)**: Breaking changes, significant restructuring, or major paradigm shifts
- **Minor (Y)**: New sections, substantial additions, or non-breaking updates

**Update Requirement**: Update both version and date whenever making any changes to ditto.md.

## Synchronization Workflow

### Step 1: After Editing ditto.md

Always review `.claude/skills/ditto/` to identify which skills need updates.

### Step 2: Check Relevance

Review the edited sections and determine which skill files are affected:

| ditto.md Section | Affected Skill | Files to Update |
|------------------|----------------|-----------------|
| Query/subscription/observer changes | `query-sync/` | `SKILL.md`, `examples/*.dart`, `reference/*.md` |
| Data modeling/CRDT changes | `data-modeling/` | `SKILL.md`, `examples/*.dart`, `reference/*.md` |
| Deletion/EVICT/storage changes | `storage-lifecycle/` | `SKILL.md`, `examples/*.dart`, `reference/*.md` |
| Transaction/attachment changes | `transactions-attachments/` | `SKILL.md`, `examples/*.dart`, `reference/*.md` |
| Performance/logging/observer changes | `performance-observability/` | `SKILL.md`, `examples/*.dart`, `reference/*.md` |

### Step 3: Update Skills

Propagate the changes to relevant SKILL.md files and example files:
1. Update SKILL.md patterns (DO/DON'T examples)
2. Update or add examples in `examples/` directory
3. Update reference docs in `reference/` directory if needed
4. Verify consistency across all affected files

### Step 4: Skip if Unnecessary

If the changes are not relevant to any skills, you may skip the update.

**Valid skip reasons**:
- Pure conceptual content
- Non-actionable guidance
- Historical context or background information

## When to Update

✅ **Update Skills When**:
- New critical patterns added to ditto.md
- Existing patterns significantly revised
- Platform-specific changes (Flutter vs non-Flutter)
- SDK version updates (4.12+, v5)

❌ **Skip Updates When**:
- Minor wording improvements without semantic changes
- Purely conceptual content without actionable patterns

## Example Workflow Execution

```
# Scenario: You edited ditto.md lines 780-1008 (Data Deletion Strategies)

Step 1: Review `.claude/skills/ditto/storage-lifecycle/`
Step 2: Identify changes to tombstone TTL and logical deletion patterns
Step 3: Update files:
  - storage-lifecycle/SKILL.md (update patterns section)
  - storage-lifecycle/examples/logical-deletion-good.dart (add new pattern)
  - storage-lifecycle/examples/tombstone-management-good.dart (update TTL values)
Step 4: Verify consistency across all affected files
```

## Validation

After synchronization, verify:
1. Version and last_updated in ditto.md have been incremented
2. All affected SKILL.md files reference updated patterns
3. Examples compile and run (for code examples)
4. No orphaned references to old patterns
5. Cross-references between skills remain valid

## See Also

- [Source of Truth: Ditto Best Practices Guide](../../guides/best-practices/ditto.md)
- [Skills Overview](../../skills/ditto/README.md)
- [Agent Skills Documentation](../../skills/README.md)
