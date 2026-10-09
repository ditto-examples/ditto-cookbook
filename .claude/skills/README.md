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

These Skills help you write high-quality Ditto SDK code across multiple platforms (Flutter, JavaScript, Swift, Kotlin). Their source lives in the [`ditto` Claude Code plugin](../../plugins/ditto/), which this repository publishes so that anyone can install them. The entries below are symbolic links to the plugin's Skills, so Claude Code loads them as project Skills while you work in this repository.

| Skill | Purpose | Priority |
|-------|---------|----------|
| [**query-sync**](query-sync/) | DQL queries, subscriptions, observers | CRITICAL |
| [**data-modeling**](data-modeling/) | CRDT-safe data structures | CRITICAL |
| [**storage-lifecycle**](storage-lifecycle/) | DELETE, soft delete, EVICT, tombstones | CRITICAL |
| [**transactions-attachments**](transactions-attachments/) | Transactions and attachments | CRITICAL |
| [**performance-observability**](performance-observability/) | Performance and monitoring | HIGH |
| [**sdk-setup**](sdk-setup/) | Setup, lifecycle, authentication, transports, security | CRITICAL |
| [**testing**](testing/) | Testing code that uses Ditto | HIGH |
| [**audit**](audit/) | Reviewing a Ditto codebase with the anti-pattern scanner | HIGH |
| [**guide**](guide/) | Searching the complete best practices guide | - |

**Edit the Skills in `plugins/ditto/skills/`**, not through these links. Claude Code protects `.claude/skills/` from writes, and keeping the source outside it lets the Skills be maintained and published like any other file.

**See**: [plugins/ditto/README.md](../../plugins/ditto/README.md) for a detailed overview and installation instructions.

## How Skills Work

### Automatic Invocation

Claude Code automatically discovers and uses Skills based on:
- **File patterns**: e.g., `*.dart` files with `import 'package:ditto_live/ditto_live.dart'`
- **Code patterns**: e.g., DQL queries, subscription creation, data model design
- **Your questions**: e.g., "How should I structure this Ditto document?"

You don't need to explicitly invoke Skills - Claude uses them when relevant.

### Platform Detection

Each Ditto Skill starts with a "Before You Apply" step: Claude checks the project's platform and Ditto SDK version (`pubspec.lock`, `package-lock.json`, `Package.resolved`, Gradle files). The examples are Flutter (Dart); for JavaScript, Swift, and Kotlin, the Skills point to the platform differences in the guide. Behavior marked **Note (SDK 5.1.0)** is verified before it is applied to another SDK version.

## Skill Structure

Each Skill directory contains:

```
skill-name/
├── SKILL.md              # Main instructions (keep under 500 lines)
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
- **Main guide**: `best-practices/ditto.md` (comprehensive reference)

The main guide is the authoritative source. Skills focus on automatable, common patterns.

### Update Strategy

**When to update Skills**:
1. **SDK version updates**: New API features, deprecated patterns (e.g., SDK v5 removes legacy API)
2. **Repeated issues**: Patterns that Skills miss
3. **Quarterly reviews**: Sync with main guide changes
4. **Team feedback**: False positives, missing patterns

**Update process**:
1. Update main guide first (`best-practices/ditto.md`)
2. Extract new critical patterns into Skills (in `plugins/ditto/skills/`)
3. Update examples and references as needed
4. Run `python3 scripts/check-ditto-skills.py` (format, `§ Heading` citations, links)
5. Bump `version` in `plugins/ditto/.claude-plugin/plugin.json` and run `claude plugin validate . --strict`

## Troubleshooting

### Claude doesn't use my Skill

**Check**:
- **File location**: Skills must be in `.claude/skills/[skill-name]/SKILL.md`, exactly one level deep (`[skill-name]` may be a symbolic link to a Skill directory elsewhere)
- **YAML syntax**: Verify frontmatter is valid (opening/closing `---`)
- **Description**: Is it specific enough? Include trigger keywords.

**Debug**:
```bash
# Verify Skill file exists
ls -la .claude/skills/query-sync/SKILL.md

# Check for YAML errors
head -n 10 .claude/skills/query-sync/SKILL.md
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
- [Ditto plugin and Skills overview](../../plugins/ditto/README.md)
- [Ditto Best Practices guide](../../best-practices/ditto.md)
