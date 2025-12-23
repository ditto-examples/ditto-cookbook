# Claude Code Rules

This directory contains enforcement rules and workflow guidance for Claude Code to optimize context usage while maintaining comprehensive documentation in CLAUDE.md.

## Purpose

Rules are specialized instructions that:
- **Enforce critical workflows** requiring multi-step coordination
- **Apply conditionally** based on file paths when possible
- **Complement CLAUDE.md** which remains the comprehensive reference
- **Optimize context usage** by loading only relevant rules for the current task

## Rules vs Guides vs Skills

### When to Use Each

| Type | Purpose | Example | Loading |
|------|---------|---------|---------|
| **CLAUDE.md** | Comprehensive reference, foundational guidelines | Language Policy, Security Guidelines | Always loaded |
| **rules/** | Enforcement workflows, conditional requirements | Ditto sync workflow, Architecture maintenance | Conditionally loaded (path-specific) or always loaded |
| **guides/** | Detailed documentation, comprehensive explanations | Git Hooks guide, Dependency Management guide | Referenced by link, not always loaded |
| **skills/** | Actionable patterns for Claude to use autonomously | DQL query patterns, CRDT data modeling | Auto-discovered by Claude based on code context |

### Relationship Diagram

```
CLAUDE.md (comprehensive reference, always loaded)
    ↓ references
rules/ (conditionally loaded based on paths)
    ↓ references for details
guides/ (comprehensive docs, referenced by link)
    ↓ extracts patterns to
skills/ (auto-discovered by Claude)
```

## Directory Structure

```
rules/
├── README.md                       # This file
├── workflows/                      # Multi-step coordination workflows
│   ├── ditto-best-practices-sync.md
│   └── architecture-documentation.md    # (future)
├── enforcement/                    # Always-on enforcement rules
│   ├── security.md                # (future: if expanded beyond CLAUDE.md)
│   ├── language.md                # (future: if expanded beyond CLAUDE.md)
│   └── documentation.md           # (future)
└── project-specific/               # Project-unique requirements
    └── showcase-standards.md      # (future)
```

## Rule File Structure

### Path-Specific Rule (Conditional Loading)

Rules with YAML frontmatter containing `paths:` field are loaded only when working on matching files:

```markdown
---
paths:
  - .claude/guides/best-practices/ditto.md
  - .claude/skills/ditto/**
version: 1.0
last_updated: 2025-12-23
priority: CRITICAL
---

# Rule Content...
```

**Path Patterns**:
- Exact paths: `.claude/guides/best-practices/ditto.md`
- Glob patterns: `.claude/skills/ditto/**` (all files under ditto/)
- Wildcard patterns: `apps/**/ARCHITECTURE.md` (all ARCHITECTURE.md in apps/)

### Unconditional Rule (Always Loaded)

Rules without `paths:` field (or with empty `paths:`) are always loaded:

```markdown
---
version: 1.0
last_updated: 2025-12-23
priority: CRITICAL
---

# Rule Content...
```

## Available Rules

### Phase 1: Initial Implementation (2025-12-23)

#### workflows/ditto-best-practices-sync.md

**Purpose**: Ensures synchronization between Ditto best practices guide and Agent Skills

**Loading**: Path-specific (`.claude/guides/best-practices/ditto.md`, `.claude/skills/ditto/**`)

**Priority**: CRITICAL

**Triggers**: After editing ditto.md or ditto skills

**Key Workflow**:
1. After editing ditto.md, review `.claude/skills/ditto/`
2. Check relevance (query-sync, data-modeling, storage-lifecycle, etc.)
3. Update affected SKILL.md files and examples
4. Skip if purely conceptual changes

[View Rule →](workflows/ditto-best-practices-sync.md)

### Phase 2: Planned (Future)

#### workflows/architecture-documentation.md

**Purpose**: Enforces ARCHITECTURE.md maintenance for all apps/tools

**Loading**: Path-specific (`**/ARCHITECTURE.md`, `apps/**`, `tools/**`)

**Priority**: HIGH

#### enforcement/security.md

**Purpose**: Expanded security enforcement with examples

**Loading**: Unconditional (always loaded)

**Priority**: CRITICAL

## Design Principles

### 1. Progressive Disclosure

Load only what's needed for the current context:
- **Working on ditto.md?** → Load ditto-best-practices-sync.md
- **Working on app code?** → Load architecture-documentation.md
- **General development?** → Load only CLAUDE.md

### 2. Single Source of Truth

- **CLAUDE.md**: Authoritative for foundational guidelines
- **guides/**: Comprehensive documentation (reference by link)
- **rules/**: Enforcement workflows (conditionally loaded)
- **skills/**: Actionable patterns (auto-discovered)

### 3. Minimize Duplication

- Rules reference guides for details, don't duplicate content
- Keep rules focused on workflow/enforcement
- Use links instead of repeating information

### 4. Version Tracking

All rules include:
```yaml
version: 1.0
last_updated: 2025-12-23
```

**When to increment version**:
- **Major (X.0)**: Breaking changes, significant restructuring
- **Minor (X.Y)**: New sections, substantial additions

## When to Create a New Rule

Create a rule in `rules/` when:

✅ **Good candidates**:
- Complex multi-step workflows (3+ steps)
- Path-specific requirements (only relevant to certain files)
- Enforcement rules requiring detailed validation
- Workflows that could distract from general development context

❌ **Keep in CLAUDE.md instead**:
- Foundational guidelines affecting all development
- Short, universal requirements (< 15 lines)
- Security-critical rules that must always be visible
- Language or tone policies

## Testing Rules

### Verify Path-Specific Loading

1. Open a file matching the `paths:` pattern
2. Verify rule is loaded in context (check Claude's behavior)
3. Open a file NOT matching the pattern
4. Verify rule is NOT loaded

### Verify Rule Content

1. Follow the workflow described in the rule
2. Verify all referenced files exist
3. Verify all links are valid
4. Check that validation steps are executable

## Troubleshooting

### Rule Not Loading When Expected

**Check**:
1. YAML frontmatter is valid (opening/closing `---`)
2. `paths:` field uses correct glob patterns
3. File location is correct (`.claude/rules/...`)
4. File has `.md` extension

### Rule Loading When Not Expected

**Check**:
1. `paths:` field is not too broad (e.g., `**` matches everything)
2. Rule should be unconditional? Remove `paths:` field.

### Rule Content Not Being Followed

**Check**:
1. Rule is clear and actionable
2. Validation steps are specific
3. Examples are concrete
4. Priority is appropriate (CRITICAL for must-follow)

## Maintenance

### Regular Reviews

- **Monthly**: Review path-specific patterns (are they still correct?)
- **Quarterly**: Review rule content (is it still accurate?)
- **After SDK updates**: Review Ditto-related rules
- **After major refactors**: Review path patterns

### Adding New Rules

1. Determine if rule should be path-specific or unconditional
2. Choose appropriate subdirectory (`workflows/`, `enforcement/`, `project-specific/`)
3. Use appropriate template (see "Rule File Structure" above)
4. Update this README with new rule information
5. Update CLAUDE.md if replacing existing content

### Deprecating Rules

1. Move to `deprecated/` subdirectory (create if needed)
2. Update CLAUDE.md if rule was referenced
3. Add deprecation notice to rule file
4. Remove after 1 quarter with no usage

## References

- [CLAUDE.md](../../CLAUDE.md) - Authoritative development guidelines
- [Guides](../guides/) - Comprehensive documentation
- [Skills](../skills/) - Actionable patterns for Claude
- [Hooks](../hooks.json) - Automated quality checks

---

**Summary**: Rules optimize context usage by extracting complex workflows from CLAUDE.md and loading them conditionally based on file paths. CLAUDE.md remains the comprehensive reference, while rules provide targeted enforcement when needed.
