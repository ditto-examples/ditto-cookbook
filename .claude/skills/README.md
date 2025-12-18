# Agent Skills

This directory contains Agent Skills that extend Claude Code's capabilities for the Ditto Cookbook project.

## What are Agent Skills?

Agent Skills are modular capabilities that Claude Code uses autonomously during development. Each Skill provides specialized guidance for specific patterns, frameworks, or best practices.

**Key characteristics**:
- **Model-invoked**: Claude autonomously decides when to use Skills based on your code and questions
- **Context-aware**: Skills are triggered by file patterns, API usage, and developer concerns
- **Progressive disclosure**: Main instructions (SKILL.md) with optional detailed examples and reference docs

## Available Skills

### Ditto SDK Skills

Located in `ditto/`, these Skills help you write high-quality Ditto SDK code across multiple platforms (Flutter, JavaScript, Swift, Kotlin).

| Skill | Purpose | Priority |
|-------|---------|----------|
| [**query-sync**](ditto/query-sync/) | DQL queries, subscriptions, observers | CRITICAL |
| [**data-modeling**](ditto/data-modeling/) | CRDT-safe data structures | CRITICAL |
| [**storage-lifecycle**](ditto/storage-lifecycle/) | DELETE, EVICT, storage optimization | HIGH |
| [**transactions-attachments**](ditto/transactions-attachments/) | Transactions and attachments | CRITICAL |
| [**performance-observability**](ditto/performance-observability/) | Performance and monitoring | HIGH |

**See**: [ditto/README.md](ditto/README.md) for detailed overview of Ditto Skills.

## How Skills Work

### Automatic Invocation

Claude Code automatically discovers and uses Skills based on:
- **File patterns**: e.g., `*.dart` files with `import 'package:ditto/ditto.dart'`
- **Code patterns**: e.g., DQL queries, subscription creation, data model design
- **Your questions**: e.g., "How should I structure this Ditto document?"

You don't need to explicitly invoke Skills - Claude uses them when relevant.

### Platform Detection

Ditto Skills automatically detect your platform:
- **Flutter/Dart**: `*.dart` files with Ditto imports
- **JavaScript**: `*.js` files with `@dittolive/ditto` imports
- **Swift**: `*.swift` files with `import DittoSwift`
- **Kotlin**: `*.kt` files with `import live.ditto.*`

Skills provide platform-specific guidance based on your code.

## Skill Structure

Each Skill directory contains:

```
skill-name/
├── SKILL.md              # Main instructions (500-800 lines)
├── examples/             # Runnable code examples (50-150 lines each)
│   ├── pattern-good.dart
│   ├── pattern-bad.dart
│   └── ...
└── reference/            # Deep dives (200-500 lines each)
    ├── topic-details.md
    └── ...
```

**Progressive disclosure**:
1. **SKILL.md**: Core patterns with DO/DON'T examples - Claude reads this first
2. **examples/**: Copy-paste-ready code - Referenced by link when needed
3. **reference/**: Comprehensive explanations - For complex scenarios

## When Skills Are Used

### During Code Implementation

Claude invokes Skills while you're writing code:
- **Creating Ditto subscriptions** → query-sync Skill
- **Designing document schemas** → data-modeling Skill
- **Implementing DELETE operations** → storage-lifecycle Skill

### During Code Review

Ask Claude to review your code:
```
"Review my Ditto code for best practices"
```

Claude will use relevant Skills to provide feedback.

### When You Have Questions

Ask questions about Ditto patterns:
```
"What's the best way to handle arrays in Ditto documents?"
```

Claude will use the data-modeling Skill to answer.

## Maintenance

### Source of Truth

Skills extract critical patterns from:
- **Main guide**: `.claude/guides/best-practices/ditto.md` (comprehensive reference)

The main guide is the authoritative source. Skills focus on automatable, common patterns.

### Update Strategy

**When to update Skills**:
1. **SDK version updates**: New API features, deprecated patterns (e.g., SDK v5 removes legacy API)
2. **Repeated issues**: Patterns that Skills miss
3. **Quarterly reviews**: Sync with main guide changes
4. **Team feedback**: False positives, missing patterns

**Update process**:
1. Update main guide first (`.claude/guides/best-practices/ditto.md`)
2. Extract new critical patterns into Skills
3. Update examples and references as needed

## Troubleshooting

### Claude doesn't use my Skill

**Check**:
- **File location**: Skills must be in `.claude/skills/[skill-name]/SKILL.md`
- **YAML syntax**: Verify frontmatter is valid (opening/closing `---`)
- **Description**: Is it specific enough? Include trigger keywords.

**Debug**:
```bash
# Verify Skill file exists
ls -la .claude/skills/ditto/query-sync/SKILL.md

# Check for YAML errors
cat .claude/skills/ditto/query-sync/SKILL.md | head -n 10
```

### Skill triggers too often

**Refine description**: Make it more specific with clear "when to use" criteria.

### Need help?

Ask Claude Code:
```
"List all available Skills"
"How do Agent Skills work?"
```

## Learn More

- [Claude Code Agent Skills documentation](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/quickstart)
- [Ditto Skills overview](ditto/README.md)
- [Ditto Best Practices guide](../guides/best-practices/ditto.md)
