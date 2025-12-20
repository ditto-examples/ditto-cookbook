# Iterative Development with Claude A/B

> **Last Updated**: 2025-12-20

Guide to developing and refining Skills iteratively using the Claude A/B pattern, where one Claude instance (A) helps create/refine Skills while another instance (B) tests them in real usage.

## Contents
- Claude A/B pattern overview
- Creating new Skills iteratively
- Refining existing Skills
- Observation techniques
- Feedback incorporation

## Claude A/B Pattern Overview

### The Two Claudes

**Claude A**: The expert who helps refine the Skill
- Has full context of Skill development
- Helps with authoring and structure decisions
- Reviews and improves Skill content
- Suggests refinements based on feedback

**Claude B**: The agent using the Skill
- Fresh instance with Skill loaded
- Performs real work using the Skill
- Reveals gaps and issues through actual usage
- Demonstrates how Skills work in practice

### Why This Pattern Works

**Benefits**:
- Claude understands both agent needs and Skill structure
- Real usage reveals issues better than hypothetical scenarios
- Iterative refinement based on observed behavior
- Natural feedback loop for continuous improvement

**Key insight**: Claude models understand how to write effective agent instructions and what information agents need.

## Creating New Skills Iteratively

### Phase 1: Complete Task Without Skill

**Process**:
1. Work with Claude A to complete a task using normal prompting
2. As you work, provide context, explain preferences, share procedural knowledge
3. Notice what information you repeatedly provide
4. Document the assistance patterns

**Example conversation**:
```
You: "Let's analyze this BigQuery table for Q4 revenue"
Claude A: "I'll query the data. What table should I use?"
You: "Use analytics.revenue_daily, and always filter out test accounts"
Claude A: "Got it. Should I use specific date range?"
You: "Yes, Q4 is October through December. Also, make sure to aggregate by month"
[... continues with repeated guidance ...]
```

**After completion, identify reusable pattern**:
- Table name: `analytics.revenue_daily`
- Always filter: `account_type != 'test'`
- Common aggregations: monthly, quarterly
- Date range conventions: Q1-Q4 definitions

### Phase 2: Ask Claude A to Create Skill

**Instruction to Claude A**:
```
"Create a Skill that captures this BigQuery analysis pattern we just used.
Include:
- The table schemas we referenced
- The naming conventions we followed
- The rule about filtering test accounts
- Common query patterns for Q1-Q4"
```

**Claude A will generate**:
- Properly structured SKILL.md with frontmatter
- Appropriate sections and organization
- Initial content based on your session

**No special prompting needed**: Claude models understand Skill format natively.

### Phase 3: Review for Conciseness

**Check Claude A's output** for unnecessary explanations:

```
You: "Remove the explanation about what revenue means - Claude already knows that."
You: "The section on SQL basics isn't needed. Focus on our specific patterns."
```

**Claude A refines**: Removes common knowledge, keeps domain-specific information.

### Phase 4: Improve Information Architecture

**Optimize organization**:

```
You: "Organize this so the table schema is in a separate reference file.
We might add more tables later."
```

**Claude A restructures**:
- Moves schema to `reference/finance-schemas.md`
- Adds navigation in SKILL.md
- Sets up scalable structure

### Phase 5: Test with Claude B

**Start fresh session with Claude B**:
1. Load the new Skill
2. Give Claude B similar tasks (but don't repeat all context)
3. Observe whether Claude B:
   - Finds the right information
   - Applies rules correctly (e.g., filters test accounts)
   - Handles the task successfully

**Example test**:
```
You: "Analyze Q3 revenue by product line"
Claude B: [Should use analytics.revenue_daily, filter test accounts, aggregate by month]
```

### Phase 6: Iterate Based on Observation

**If Claude B struggles or misses something**:

Return to Claude A with specifics:
```
You: "When Claude used this Skill, it forgot to filter test accounts for
date-based queries. Should we add a section about date filtering patterns?"
```

**Claude A suggests improvements**:
- Make test account filtering more prominent
- Add it to each query example
- Consider moving to "CRITICAL" patterns section

### Phase 7: Apply and Retest

1. Update Skill with Claude A's refinements
2. Test again with fresh Claude B instance
3. Verify improvements address the issues
4. Repeat until Skill works reliably

## Refining Existing Skills

### Iterative Refinement Loop

```
Use Skill (Claude B)
   ↓
Observe behavior
   ↓
Identify issues
   ↓
Refine with Claude A
   ↓
Apply changes
   ↓
Test with Claude B
   ↓
Repeat
```

### Step 1: Use Skill in Real Workflows

**Give Claude B actual tasks**, not test scenarios:
```
Real task: "Create a sales pipeline report for the last quarter"
Not: "Test if the Skill can query sales data"
```

**Why real tasks**: Reveals issues that synthetic tests miss.

### Step 2: Observe Claude B's Behavior

**Watch for**:
- **Success patterns**: What works well?
- **Struggles**: Where does Claude get stuck?
- **Unexpected choices**: Does Claude take surprising paths?
- **Missing information**: What does Claude seem to need?

**Example observations**:
```
Observation Log:
- Claude B successfully used finance-schemas.md reference
- Forgot to filter test accounts in regional sales query
- Took longer route to find product table (navigation unclear?)
- Successfully followed Q4 date range convention
```

### Step 3: Return to Claude A for Improvements

**Share current SKILL.md and observations**:

```
You: "Here's the current Skill. I noticed Claude B forgot to filter test
accounts when I asked for a regional report. The Skill mentions filtering,
but maybe it's not prominent enough?"
```

### Step 4: Review Claude A's Suggestions

**Claude A might suggest**:
- Reorganizing to make rules more prominent
- Using stronger language ("MUST filter" instead of "always filter")
- Adding validation checklist to workflows
- Moving critical rule to CRITICAL patterns section

**Evaluate suggestions**:
- Will this address the observed issue?
- Does it introduce complexity?
- Is it consistent with Skill style?

### Step 5: Apply and Test Changes

1. Update Skill with refinements
2. Test again with fresh Claude B
3. Observe if issue is resolved
4. Check for any regressions

### Step 6: Repeat Based on Usage

**Continue observe-refine-test cycle** as you encounter new scenarios:
- New edge cases discovered
- Different query patterns needed
- Additional domains added
- Tool or API changes

## Observation Techniques

### What to Observe

**Skill Discovery**:
- Does Skill activate when expected?
- False positives (activates inappropriately)?
- False negatives (doesn't activate when it should)?

**Navigation Patterns**:
- Which files does Claude read?
- In what order?
- Does Claude find referenced files?
- Any files consistently ignored?

**Pattern Application**:
- Are rules followed correctly?
- Are workflows completed in order?
- Is validation performed?
- Are examples consulted?

**Struggle Points**:
- Where does Claude hesitate?
- What information is unclear?
- Which steps are skipped?
- What errors occur?

### Observation Methods

**Method 1: Direct Usage**
```
Use Skill for actual work
Note what works and what doesn't
Document specific instances
```

**Method 2: Structured Testing**
```
Create specific test scenarios
Run with Claude B
Compare actual vs expected behavior
Note deviations
```

**Method 3: Log Analysis**
```
Review conversation logs
Identify patterns in Claude B's choices
Note where Skill guided correctly
Note where guidance was missed
```

### Recording Observations

**Template**:
```markdown
## Observation: [Date]

**Task**: [What was Claude B asked to do]

**Expected Behavior**: [What should happen based on Skill]

**Actual Behavior**: [What Claude B actually did]

**Issue Identified**: [Specific problem or gap]

**Hypothesis**: [Why this occurred]

**Suggested Fix**: [Potential improvement]
```

**Example**:
```markdown
## Observation: 2025-12-20

**Task**: "Generate monthly revenue report for Q4"

**Expected Behavior**: Query analytics.revenue_daily, filter test accounts,
aggregate by month for Oct-Dec

**Actual Behavior**: Correctly queried table and aggregated, but forgot to
filter test accounts

**Issue Identified**: Test account filtering not consistently applied

**Hypothesis**: Filtering rule mentioned in general section, not emphasized
in query examples

**Suggested Fix**: Add filtering to every query example, move to CRITICAL
patterns section
```

## Feedback Incorporation

### Gathering Team Feedback

**Share Skills with teammates**:
1. Have them use Skill on real tasks
2. Ask specific questions:
   - Did Skill activate when expected?
   - Were instructions clear?
   - What was confusing?
   - What's missing?
3. Collect observation logs
4. Identify patterns in feedback

### Prioritizing Feedback

**Categorize feedback**:
- **Critical**: Blocks usage or causes errors
- **High**: Significant friction or confusion
- **Medium**: Nice-to-have improvements
- **Low**: Minor refinements

**Address by priority**:
1. Fix critical issues immediately
2. Batch high-priority improvements
3. Consider medium-priority in next iteration
4. Low priority as time permits

### A/B Testing Refinements

**Test alternatives**:

**Version A**:
```markdown
## Query Patterns

Always filter test accounts in queries.
```

**Version B**:
```markdown
## Query Patterns

CRITICAL: MUST filter test accounts in every query:
`WHERE account_type != 'test'`
```

**Test both versions**:
- Split team uses different versions
- Measure which version better prevents forgetting filter
- Adopt more effective version

### Continuous Refinement

**Ongoing improvement cycle**:
```
Weekly:
- Review usage patterns
- Collect observations
- Identify pain points

Monthly:
- Batch improvements
- Update Skill
- Test changes
- Document improvements

Quarterly:
- Major review
- Restructure if needed
- Add new domains
- Remove obsolete content
```

## Common Iteration Patterns

### Pattern 1: Emphasis Adjustment

**Observation**: Important rule being missed

**Solution**: Elevate prominence
- Move to CRITICAL patterns
- Add to every workflow step
- Include in quick reference checklist
- Use stronger language (MUST, ALWAYS)

### Pattern 2: Structure Reorganization

**Observation**: Claude reads wrong section first

**Solution**: Improve navigation
- Reorder sections by frequency of use
- Add clearer section headers
- Improve table of contents
- Add quick-reference navigation

### Pattern 3: Example Addition

**Observation**: Concept clear in theory, unclear in practice

**Solution**: Add concrete examples
- Create example file showing pattern
- Include both good and bad versions
- Add code snippets to SKILL.md
- Reference examples in instructions

### Pattern 4: Content Extraction

**Observation**: SKILL.md approaching 500 lines

**Solution**: Extract to reference files
- Move detailed content to reference/
- Keep core patterns in SKILL.md
- Add navigation links
- Ensure one level of nesting

### Pattern 5: Domain Split

**Observation**: Single domain dominates usage

**Solution**: Create separate files per domain
- Split reference/ by domain
- Add domain navigation in SKILL.md
- Allow focused loading
- Scale to more domains

## Iteration Anti-Patterns

❌ **Making changes without testing**
- Always test with Claude B after changes

❌ **Batch too many changes at once**
- Hard to identify what worked
- Difficult to debug regressions

❌ **Ignore observation data**
- Trust real usage over assumptions

❌ **Over-optimize for one scenario**
- Balance across different use cases

❌ **Never finalize**
- Continuous improvement doesn't mean never shipping
- Ship at 90% and iterate

## Quick Iteration Checklist

For each iteration cycle:
- [ ] Real task tested with Claude B
- [ ] Observations documented
- [ ] Issues identified
- [ ] Hypotheses formed
- [ ] Improvements discussed with Claude A
- [ ] Changes applied
- [ ] Retested with Claude B
- [ ] No regressions detected
- [ ] Improvement verified

## See Also

- [../SKILL.md](../SKILL.md) - Complete Skill authoring guidance
- [evaluation-patterns.md](evaluation-patterns.md) - Testing strategies
- [skill-structure-guide.md](skill-structure-guide.md) - File organization
- [../examples/workflow-patterns-good.md](../examples/workflow-patterns-good.md) - Workflow patterns
