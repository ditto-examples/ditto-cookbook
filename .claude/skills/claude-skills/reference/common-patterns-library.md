# Common Patterns Library

> **Last Updated**: 2025-12-20

Reusable patterns for Skills. Copy and adapt these templates for your own Skills to ensure consistency and effectiveness.

## Contents
- Template patterns
- Example patterns
- Workflow patterns
- Validation patterns
- Feedback loop patterns
- Conditional patterns
- Error handling patterns

## Template Patterns

### Strict Template Pattern

Use when output must follow exact structure (API responses, data formats).

````markdown
## [Operation Name]

ALWAYS use this exact template:

```[format]
[template structure with placeholders]
```

Do not deviate from this structure.

**Example**:
```[format]
[filled example showing exact usage]
```
````

**Copy-paste template**:

````markdown
## Report Generation

ALWAYS use this exact template:

```markdown
# [Report Title]

## Executive Summary
[One paragraph overview of key findings]

## Key Findings
- Finding 1 with supporting data
- Finding 2 with supporting data
- Finding 3 with supporting data

## Recommendations
1. Specific actionable recommendation
2. Specific actionable recommendation

## Appendix
[Supporting data tables or charts]
```

**Example**:
```markdown
# Q4 Sales Analysis

## Executive Summary
Sales increased 23% in Q4 compared to Q3, driven primarily by enterprise customer growth and successful holiday promotions.

## Key Findings
- Enterprise revenue grew 45% quarter-over-quarter
- SMB segment remained flat at $2.3M
- Customer churn decreased from 4.1% to 3.2%

## Recommendations
1. Expand enterprise sales team by 3 people in Q1
2. Launch SMB retention program targeting at-risk accounts

## Appendix
[Revenue table by segment]
[Customer acquisition funnel]
```
````

### Flexible Template Pattern

Use when adaptation is useful but structure helps.

````markdown
## [Operation Name]

Here is a sensible default format:

```[format]
[template structure]
```

Adjust sections as needed based on [specific context].

**Common variations**:
- [Variation 1]: [When to use]
- [Variation 2]: [When to use]

**Example** ([variation type]):
```[format]
[filled example]
```
````

## Example Patterns

### Single Example Pattern

Use when one example sufficiently demonstrates the pattern.

````markdown
## [Operation Name]

Generate [output] following this example:

**Example**:
Input: [input example]
Output:
```
[output example with annotations]
```

Key points:
- [Important aspect 1]
- [Important aspect 2]

Follow this [style/format/approach].
````

### Multiple Examples Pattern

Use when output quality depends on seeing variations.

````markdown
## [Operation Name]

Generate [output] following these examples:

**Example 1**: [Scenario type]
Input: [input]
Output:
```
[output]
```
Why this works: [explanation]

**Example 2**: [Scenario type]
Input: [input]
Output:
```
[output]
```
Why this works: [explanation]

**Example 3**: [Scenario type]
Input: [input]
Output:
```
[output]
```
Why this works: [explanation]

**Pattern to follow**: [description of common elements]
````

### Good vs Bad Example Pattern

Use to clearly demonstrate what to avoid.

````markdown
## [Pattern Name]

❌ **Bad Example** (what to avoid):
```
[code or text showing anti-pattern]
```
Problems:
- [Issue 1]
- [Issue 2]

✅ **Good Example** (correct approach):
```
[code or text showing best practice]
```
Benefits:
- [Advantage 1]
- [Advantage 2]
````

## Workflow Patterns

### Basic Workflow Pattern

Use for sequential tasks with clear steps.

````markdown
## [Workflow Name]

Copy this checklist:

```
[Workflow] Progress:
- [ ] Step 1: [Action description]
- [ ] Step 2: [Action description]
- [ ] Step 3: [Action description]
- [ ] Step 4: [Action description]
```

**Step 1: [Title]**

[Detailed instructions with commands or code]

**Step 2: [Title]**

[Detailed instructions]

**Step 3: [Title]**

[Detailed instructions]

**Step 4: [Title]**

[Detailed instructions]
````

### Workflow with Validation Pattern

Use when intermediate validation prevents costly errors.

````markdown
## [Workflow Name]

Copy this checklist:

```
[Workflow] Progress:
- [ ] Step 1: [Action]
- [ ] Step 2: [Action]
- [ ] Step 3: Validate [aspect]
- [ ] Step 4: [Action]
```

**Step 1: [Title]**

[Instructions]

**Step 2: [Title]**

[Instructions]

**Step 3: Validate [Aspect]**

CRITICAL: Run validation before continuing:

```bash
[validation command]
```

If validation fails:
1. [Fix action 1]
2. [Fix action 2]
3. Run validation again

**Only proceed when validation passes.**

**Step 4: [Title]**

[Continue only after validation]
````

### Nested Checklist Pattern

Use when steps contain sub-validations.

````markdown
## [Workflow Name]

Copy this checklist:

```
Main Progress:
- [ ] Step 1: [Action]
- [ ] Step 2: [Action with sub-checks]
- [ ] Step 3: [Action]
```

**Step 2: [Title]**

[Instructions]

Sub-validation checklist:
- [ ] [Check 1]
- [ ] [Check 2]
- [ ] [Check 3]

If any sub-checks fail, return to Step [X].
````

## Validation Patterns

### Pre-Validation Pattern

Use to check prerequisites before starting.

````markdown
## [Operation Name]

**Prerequisites** (verify before starting):
- [ ] [Prerequisite 1]
- [ ] [Prerequisite 2]
- [ ] [Prerequisite 3]

**Verify prerequisites**:
```bash
[verification commands]
```

**If any prerequisite fails, resolve before continuing.**

[Main workflow begins after verification]
````

### Inline Validation Pattern

Use for validation at each step.

````markdown
## [Workflow Name]

**Step 1: [Action]**

[Instructions]

Validate:
```bash
[validation command]
```

Expected output: [description]

**Step 2: [Action]**

[Instructions]

Validate:
```bash
[validation command]
```

Expected output: [description]

[Continue pattern for each step]
````

### Final Validation Pattern

Use for comprehensive end-to-end check.

````markdown
## [Workflow Name]

[Main workflow steps]

**Final Validation**

Run complete validation:
```bash
[validation command]
```

Validation checklist:
- [ ] [Outcome 1 verified]
- [ ] [Outcome 2 verified]
- [ ] [Outcome 3 verified]
- [ ] [No errors logged]

**If any checks fail, review logs and address issues before proceeding.**
````

## Feedback Loop Patterns

### Validate-Fix-Repeat Pattern

Use when errors should be caught and fixed immediately.

````markdown
## [Operation Name]

1. [Make changes]
2. Run validation: `[command]`
3. If validation fails:
   - Review error messages
   - [Fix action 1]
   - [Fix action 2]
   - Return to Step 2
4. **Only proceed when validation passes**
5. [Next step]
````

### Test-Debug-Retest Pattern

Use for iterative testing and debugging.

````markdown
## [Testing Workflow]

1. Run tests: `[command]`
2. Review results
3. If tests fail:
   - Note which tests failed
   - Debug implementation:
     - [Debug step 1]
     - [Debug step 2]
   - Fix issues
   - Return to Step 1
4. **All tests must pass before continuing**
5. [Deployment or next step]
````

### Review-Refine-Re-review Pattern

Use for quality-critical content or code.

````markdown
## [Creation Workflow]

1. Complete initial [artifact]
2. Review against checklist:
   - [ ] [Criterion 1]
   - [ ] [Criterion 2]
   - [ ] [Criterion 3]
3. If any issues found:
   - Note specific problems
   - Refine [artifact]
   - Return to Step 2
4. **Only finalize when all checks pass**
````

## Conditional Patterns

### Basic Conditional Pattern

Use when multiple valid approaches exist.

````markdown
## [Operation Name]

**Step 1: Determine [decision criteria]**

**Is it [Scenario A]?** → Follow "Scenario A Workflow" below
**Is it [Scenario B]?** → Follow "Scenario B Workflow" below
**Is it [Scenario C]?** → Follow "Scenario C Workflow" below

### Scenario A Workflow

```
A Progress:
- [ ] Step 1: [Action]
- [ ] Step 2: [Action]
```

[Detailed steps]

### Scenario B Workflow

```
B Progress:
- [ ] Step 1: [Action]
- [ ] Step 2: [Action]
```

[Detailed steps]

[Continue for each scenario]
````

### Decision Tree Pattern

Use for complex decision-making.

````markdown
## [Operation Name]

**Decision Tree**:

```
Start
  ↓
[Question 1]?
  ├─ Yes → [Question 2]?
  │         ├─ Yes → Approach A
  │         └─ No → Approach B
  └─ No → [Question 3]?
            ├─ Yes → Approach C
            └─ No → Approach D
```

### Approach A

[When to use]: [Criteria]

[Steps...]

### Approach B

[When to use]: [Criteria]

[Steps...]

[Continue for each approach]
````

## Error Handling Patterns

### Graceful Degradation Pattern

Use when fallback options exist.

````markdown
## [Operation Name]

**Primary approach**:
```
[code or commands]
```

**If primary approach fails**:

1. Try alternative approach:
```
[alternative code or commands]
```

2. If alternative fails, use minimal fallback:
```
[fallback code or commands]
```

3. Log the issue for investigation
````

### Error-Specific Handling Pattern

Use when different errors require different responses.

````markdown
## [Operation Name]

```
[operation code or commands]
```

**Error handling**:

**If [Error Type 1]**:
- Cause: [Likely cause]
- Solution: [Specific fix]

**If [Error Type 2]**:
- Cause: [Likely cause]
- Solution: [Specific fix]

**If [Error Type 3]**:
- Cause: [Likely cause]
- Solution: [Specific fix]

**For other errors**:
- Log full error message
- [General troubleshooting steps]
````

### Rollback Pattern

Use for operations that may need reverting.

````markdown
## [Operation Name]

**CRITICAL: Always have rollback plan ready**

Copy this checklist:

```
[Operation] Progress:
- [ ] Step 1: Create backup
- [ ] Step 2: Verify backup
- [ ] Step 3: Perform operation
- [ ] Step 4: Validate results
- [ ] Step 5: Monitor for issues
- [ ] Step 6: Rollback if needed
```

**Step 1: Create Backup**

[Backup instructions]

**Step 2: Verify Backup**

[Verification steps]

[... main operation steps ...]

**Step 6: Rollback if Needed**

**If any issues occur**:

1. Stop operation
2. Restore from backup:
```
[rollback commands]
```
3. Verify restoration
4. Investigate issues before retrying
````

## Pattern Combinations

### Complete Workflow Template

Combines multiple patterns for robust workflow.

````markdown
## [Comprehensive Workflow Name]

**Prerequisites** (verify first):
- [ ] [Prerequisite 1]
- [ ] [Prerequisite 2]

Copy this checklist:

```
Main Progress:
- [ ] Step 1: Prepare [aspect]
- [ ] Step 2: Validate preparation
- [ ] Step 3: Execute [operation]
- [ ] Step 4: Validate results
- [ ] Step 5: Finalize
```

**Step 1: Prepare [Aspect]**

[Instructions]

**Step 2: Validate Preparation**

Run validation:
```bash
[command]
```

If validation fails:
- [Fix 1]
- [Fix 2]
- Return to Step 1

**Step 3: Execute [Operation]**

[Instructions]

**Error handling**:
- If [Error A]: [Solution A]
- If [Error B]: [Solution B]

**Step 4: Validate Results**

Validation checklist:
- [ ] [Check 1]
- [ ] [Check 2]
- [ ] [Check 3]

If checks fail, rollback:
```bash
[rollback commands]
```

**Step 5: Finalize**

[Final steps]
````

## Using These Patterns

### How to Adapt Patterns

1. **Copy pattern template**
2. **Replace placeholders** with your specific content
3. **Adjust detail level** for your use case
4. **Add domain-specific** examples or commands
5. **Test with real** usage

### Combining Patterns

**Common combinations**:
- Workflow + Validation + Error Handling
- Template + Examples
- Conditional + Feedback Loop
- Workflow + Rollback

### Pattern Selection Guide

| Use Case | Recommended Patterns |
|----------|---------------------|
| Step-by-step process | Basic Workflow + Validation |
| Quality-critical output | Template + Examples + Review Loop |
| Complex decision-making | Conditional + Decision Tree |
| Error-prone operations | Validation + Error Handling + Rollback |
| Multiple approaches | Conditional + Examples |

## See Also

- [../SKILL.md](../SKILL.md) - Complete Skill authoring guidance
- [../examples/workflow-patterns-good.md](../examples/workflow-patterns-good.md) - Workflow examples
- [skill-structure-guide.md](skill-structure-guide.md) - File organization
- [evaluation-patterns.md](evaluation-patterns.md) - Testing strategies
