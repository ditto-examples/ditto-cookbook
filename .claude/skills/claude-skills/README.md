# Claude Code Skills Authoring Skill

> **Last Updated**: 2025-12-20

A comprehensive meta-skill that teaches Claude Code how to effectively discover, author, structure, and maintain Claude Code Skills. This Skill consolidates best practices from official documentation into actionable patterns.

## Overview

This Skill provides guidance for creating, structuring, and maintaining effective Skills. It covers:
- **Core principles**: Conciseness, progressive disclosure, appropriate degrees of freedom
- **Metadata authoring**: Writing effective names and descriptions with clear triggers
- **File organization**: Three-tier progressive disclosure architecture
- **Workflows**: Step-by-step patterns with checklists for complex tasks
- **Critical patterns**: 15+ prioritized patterns for common scenarios
- **Examples**: Good vs bad demonstrations for key concepts
- **Reference materials**: Deep-dive guides on structure, evaluation, and iteration

## Quick Start

### Creating a New Skill

1. **Complete a task** with Claude using normal prompting
2. **Identify reusable patterns** from the interaction
3. **Ask Claude to create a Skill** capturing those patterns
4. **Review and refine** with focus on conciseness
5. **Test with fresh Claude instance** on similar tasks
6. **Iterate based on observations**

See [SKILL.md](SKILL.md#workflow-1-creating-a-new-skill) for detailed workflow.

### Improving an Existing Skill

1. **Use the Skill** on real tasks
2. **Observe behavior** and document issues
3. **Refine with Claude** (the "A/B pattern")
4. **Apply changes** and retest
5. **Verify improvements**

See [SKILL.md](SKILL.md#workflow-2-iterating-on-existing-skills) for detailed workflow.

## File Structure

```
claude-skills/
├── README.md                           # This file
├── SKILL.md                            # Main skill file (600+ lines)
├── examples/                           # Concrete demonstrations
│   ├── skill-metadata-good.md         # Well-written frontmatter
│   ├── skill-metadata-bad.md          # Common metadata mistakes
│   ├── progressive-disclosure-good.md # Effective file organization
│   ├── progressive-disclosure-bad.md  # Structure issues
│   ├── workflow-patterns-good.md      # Clear workflow with checklists
│   ├── workflow-patterns-bad.md       # Unclear or missing workflows
│   ├── reference-organization-good.md # Well-organized reference files
│   └── reference-organization-bad.md  # Poor file naming/structure
└── reference/                          # Deep-dive guides
    ├── skill-structure-guide.md       # Complete file structure breakdown
    ├── evaluation-patterns.md         # Testing and evaluation strategies
    ├── iterative-development.md       # Claude A/B development workflow
    └── common-patterns-library.md     # Reusable template patterns
```

## Key Topics

### Core Principles (in SKILL.md)

1. **Conciseness is Key**: Keep SKILL.md under 500 lines, use progressive disclosure
2. **Progressive Disclosure**: Three-tier architecture (SKILL.md → examples → reference)
3. **Set Appropriate Degrees of Freedom**: Match specificity to task fragility

### Critical Patterns (Priority: CRITICAL)

1. Keep SKILL.md under 500 lines
2. Write descriptions in third person with clear triggers
3. Avoid deeply nested references (one level deep)
4. Use forward slashes in all file paths
5. Test with all target models (Haiku, Sonnet, Opus)

See [SKILL.md](SKILL.md#critical-patterns) for complete list with examples.

### Common Workflows

**Creating New Skills**: [SKILL.md](SKILL.md#workflow-1-creating-a-new-skill)
- 7-step process from identifying pattern to iterating

**Iterating on Existing Skills**: [SKILL.md](SKILL.md#workflow-2-iterating-on-existing-skills)
- Claude A/B pattern for refinement based on real usage

## Examples Directory

Demonstrates good vs bad patterns for key concepts:

### Metadata Examples
- [skill-metadata-good.md](examples/skill-metadata-good.md) - Effective YAML frontmatter with 5 complete examples
- [skill-metadata-bad.md](examples/skill-metadata-bad.md) - Common mistakes and how to fix them

### Structure Examples
- [progressive-disclosure-good.md](examples/progressive-disclosure-good.md) - Effective three-tier organization (4 complete examples)
- [progressive-disclosure-bad.md](examples/progressive-disclosure-bad.md) - Common structure mistakes (10 anti-patterns)

### Workflow Examples
- [workflow-patterns-good.md](examples/workflow-patterns-good.md) - Clear workflows with checklists (4 comprehensive examples)
- [workflow-patterns-bad.md](examples/workflow-patterns-bad.md) - Workflow anti-patterns (10 common mistakes)

### Reference Organization Examples
- [reference-organization-good.md](examples/reference-organization-good.md) - Well-organized reference files (4 patterns)
- [reference-organization-bad.md](examples/reference-organization-bad.md) - Poor organization patterns (10 anti-patterns)

## Reference Materials

Deep-dive documentation on specific topics:

### Skill Structure Guide
[reference/skill-structure-guide.md](reference/skill-structure-guide.md)

Complete breakdown of:
- Directory structure patterns (basic, standard, complex, multi-domain)
- SKILL.md anatomy with section sizing guidelines
- YAML frontmatter requirements and field specifications
- Progressive disclosure architecture
- File naming conventions
- Platform-specific organization
- Size guidelines and limits

### Evaluation Patterns
[reference/evaluation-patterns.md](reference/evaluation-patterns.md)

Testing and evaluation strategies:
- Evaluation-driven development workflow
- Evaluation structure and format
- Testing with different models
- Measuring effectiveness (quantitative and qualitative)
- Iteration based on results

### Iterative Development
[reference/iterative-development.md](reference/iterative-development.md)

Claude A/B pattern for Skill development:
- Overview of Claude A (expert) and Claude B (user)
- Creating new Skills iteratively (7 phases)
- Refining existing Skills (6-step loop)
- Observation techniques
- Feedback incorporation

### Common Patterns Library
[reference/common-patterns-library.md](reference/common-patterns-library.md)

Reusable templates for:
- Template patterns (strict and flexible)
- Example patterns (single, multiple, good vs bad)
- Workflow patterns (basic, with validation, nested checklist)
- Validation patterns (pre, inline, final)
- Feedback loop patterns (validate-fix-repeat, test-debug-retest)
- Conditional patterns (basic, decision tree)
- Error handling patterns (graceful degradation, rollback)

## When to Use This Skill

This Skill triggers when:
- User asks to create a new Skill
- User wants to improve or refactor existing Skills
- Working with files in `.claude/skills/` directory
- User asks about Skills best practices
- Helping organize Skill content or structure
- User mentions "progressive disclosure" or "Skill metadata"
- Reviewing or debugging Skill effectiveness

## Critical Issues Prevented

This Skill helps prevent:
- Bloated SKILL.md files exceeding 500 lines
- Poorly written metadata preventing Skill discovery
- Deeply nested file references causing incomplete reads
- Inconsistent terminology confusing Claude
- Missing workflows for complex multi-step tasks
- Time-sensitive information becoming outdated
- Over-engineering with excessive abstraction

## Quick Reference Checklist

Before finalizing a Skill:

**Core Quality**:
- [ ] Description is specific and includes key terms
- [ ] Description written in third person
- [ ] SKILL.md body under 500 lines
- [ ] Additional details in separate files
- [ ] No time-sensitive information
- [ ] Consistent terminology throughout
- [ ] Examples are concrete
- [ ] File references one level deep
- [ ] Workflows have clear steps with checklists

**Testing**:
- [ ] Tested with real usage scenarios
- [ ] Tested with Haiku, Sonnet, Opus (if targeting all)
- [ ] Team feedback incorporated (if applicable)
- [ ] Observed Claude's navigation patterns
- [ ] Verified Skill triggers appropriately

See [SKILL.md](SKILL.md#quick-reference-checklist) for complete checklist.

## Related Skills

This meta-skill complements:
- Ditto SDK Skills (`.claude/skills/ditto/`) - Domain-specific Skills for Ditto development
- Custom user Skills - Any Skills you create using these patterns

## Official Documentation

This Skill consolidates patterns from:
- [Claude Code Skills Documentation](https://docs.anthropic.com/en/agents-and-tools/agent-skills/overview)
- [Skills Best Practices Guide](https://docs.anthropic.com/en/agents-and-tools/agent-skills/best-practices)

## Contributing

When improving this Skill:
1. Follow the patterns documented here
2. Test changes with real usage
3. Use the Claude A/B pattern for refinement
4. Update timestamps in modified files
5. Maintain consistency with existing structure

## Navigation Tips

- **Start with SKILL.md** for core guidance
- **Check examples/** for concrete demonstrations when learning a concept
- **Consult reference/** for deep-dive information on specific topics
- **Use Quick Reference Checklist** when finalizing Skills

## Version Information

- **Created**: 2025-12-20
- **Based on**: Official Claude Code Skills Best Practices (2025)
- **Scope**: Platform-agnostic Skill authoring guidance
