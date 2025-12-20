# Evaluation Patterns for Skills

> **Last Updated**: 2025-12-20

Strategies for testing and evaluating Skill effectiveness, including evaluation-driven development, testing approaches, and iteration patterns.

## Contents
- Evaluation-driven development
- Evaluation structure
- Testing strategies
- Measuring effectiveness
- Iteration based on results

## Evaluation-Driven Development

### Philosophy

**Create evaluations BEFORE writing extensive documentation.** This ensures your Skill solves real problems rather than documenting imagined ones.

### Development Flow

```
1. Identify gaps
   ↓
2. Create evaluations
   ↓
3. Establish baseline
   ↓
4. Write minimal instructions
   ↓
5. Execute evaluations
   ↓
6. Compare against baseline
   ↓
7. Iterate and refine
```

### Step 1: Identify Gaps

**Process**:
1. Run Claude on representative tasks without a Skill
2. Document specific failures or missing context
3. Note what information you repeatedly provide
4. Identify patterns in the assistance required

**Example**:
```
Task: Extract form fields from PDF

Without Skill:
- Claude uses wrong PDF library (pypdf instead of pdfplumber)
- Misses form field validation step
- Doesn't handle form field coordinates correctly
- No error handling for corrupted PDFs

Gaps identified:
- Library selection guidance
- Validation workflow
- Coordinate handling patterns
- Error handling examples
```

### Step 2: Create Evaluations

Write three scenarios that test these gaps:

**Evaluation 1**: Basic form extraction
**Evaluation 2**: Complex form with nested fields
**Evaluation 3**: Corrupted or malformed PDF

### Step 3: Establish Baseline

**Run evaluations without Skill**:
- Measure success rate
- Document specific failures
- Note time to completion
- Identify consistent mistakes

**Example baseline results**:
```
Test without Skill:
- Evaluation 1: Failed (used wrong library)
- Evaluation 2: Partial success (missed nested fields)
- Evaluation 3: Failed (no error handling)

Success rate: 1/3 (33%)
```

### Step 4: Write Minimal Instructions

Create just enough content to address the gaps:
- Library selection guidance
- Field extraction workflow
- Validation patterns
- Error handling examples

**Don't** write everything you think might be useful. Focus on solving documented gaps.

### Step 5: Execute Evaluations

Run the same evaluations with the Skill loaded.

### Step 6: Compare Against Baseline

Measure improvement:
- Success rate improvement
- Specific gaps resolved
- New issues introduced
- Consistency of results

**Example with Skill**:
```
Test with Skill:
- Evaluation 1: Success (used pdfplumber correctly)
- Evaluation 2: Success (validated nested fields)
- Evaluation 3: Success (handled errors gracefully)

Success rate: 3/3 (100%)
Improvement: +200%
```

### Step 7: Iterate

Based on results:
- Address remaining failures
- Refine unclear guidance
- Add missing patterns
- Remove unnecessary content

## Evaluation Structure

### Basic Evaluation Format

```json
{
  "skills": ["skill-name"],
  "query": "Task description",
  "files": ["path/to/test-file"],
  "expected_behavior": [
    "Specific outcome 1",
    "Specific outcome 2",
    "Specific outcome 3"
  ]
}
```

### Complete Evaluation Example

```json
{
  "skills": ["processing-pdfs"],
  "query": "Extract all text from this PDF file and save it to output.txt",
  "files": ["test-files/document.pdf"],
  "expected_behavior": [
    "Successfully reads the PDF file using pdfplumber library",
    "Extracts text content from all pages without missing any",
    "Saves the extracted text to output.txt in readable format",
    "Handles errors gracefully if PDF is corrupted or encrypted"
  ],
  "success_criteria": {
    "must_have": [
      "Uses pdfplumber (not pypdf or other libraries)",
      "Processes all pages in document",
      "Creates output.txt file"
    ],
    "should_have": [
      "Includes error handling",
      "Preserves text structure"
    ],
    "nice_to_have": [
      "Logs progress",
      "Validates output"
    ]
  }
}
```

### Evaluation Categories

**Category 1: Happy Path**
```json
{
  "type": "happy_path",
  "description": "Test basic functionality with ideal inputs",
  "query": "Extract text from this simple PDF",
  "files": ["simple-text.pdf"],
  "expected": "Clean extraction with correct library"
}
```

**Category 2: Edge Cases**
```json
{
  "type": "edge_case",
  "description": "Test handling of unusual inputs",
  "query": "Extract text from PDF with mixed content types",
  "files": ["complex-mixed.pdf"],
  "expected": "Handles images, tables, and text correctly"
}
```

**Category 3: Error Scenarios**
```json
{
  "type": "error_scenario",
  "description": "Test error handling",
  "query": "Extract text from corrupted PDF",
  "files": ["corrupted.pdf"],
  "expected": "Graceful error handling with helpful message"
}
```

## Testing Strategies

### Test Suite Composition

**Minimum viable test suite**: 3 evaluations
- 1 happy path
- 1 edge case
- 1 error scenario

**Comprehensive test suite**: 5-10 evaluations
- 2-3 happy path variations
- 2-3 edge cases
- 2-3 error scenarios
- 1 integration test

### Testing with Different Models

**Test with all target models**:
```
Evaluation 1 with Haiku → Result
Evaluation 1 with Sonnet → Result
Evaluation 1 with Opus → Result

Compare results across models
```

**Model-specific considerations**:
- **Haiku**: Does Skill provide enough detail?
- **Sonnet**: Is Skill clear and efficient?
- **Opus**: Does Skill avoid over-explaining?

### Real-World Testing

**Beyond evaluations**:
1. Use Skill on actual tasks (not test scenarios)
2. Observe Claude's behavior in practice
3. Note unexpected patterns
4. Identify missed edge cases

**Observational testing**:
```
Observation Log:
- Claude navigated to reference file correctly
- Skipped validation step (needs emphasis)
- Used correct library
- Missed error handling for edge case X
```

## Measuring Effectiveness

### Quantitative Metrics

**Success Rate**:
```
Success Rate = (Passed Evaluations / Total Evaluations) × 100%

Target: 90%+ success rate
```

**Improvement Over Baseline**:
```
Improvement = ((With Skill - Without Skill) / Without Skill) × 100%

Example: (100% - 33%) / 33% = 203% improvement
```

**Consistency**:
```
Run each evaluation 3 times
Consistency = (Identical Results / Total Runs) × 100%

Target: 90%+ consistency
```

### Qualitative Assessment

**Rubric for evaluation**:

| Criterion | Poor | Acceptable | Excellent |
|-----------|------|------------|-----------|
| Library selection | Wrong library | Correct but verbose | Optimal choice |
| Error handling | None | Basic try/catch | Comprehensive |
| Code quality | Messy, unclear | Functional | Clean, maintainable |
| Completeness | Missing steps | All steps present | + validation |

### Discovery Testing

**Test if Skill triggers appropriately**:
```
Test queries without explicit Skill mention:
- "I need to extract text from a PDF"
- "How do I fill out this PDF form?"
- "This PDF file won't open correctly"

Does Skill activate? Yes/No
Is activation appropriate? Yes/No
```

### Navigation Testing

**Test progressive disclosure**:
```
Does Claude:
- Find referenced files correctly?
- Read complete files (not just preview)?
- Follow navigation links?
- Load only necessary content?
```

## Iteration Based on Results

### Failure Analysis

**When evaluation fails**:

1. **Identify failure category**:
   - Wrong approach chosen
   - Missing information
   - Unclear guidance
   - Skill not discovered

2. **Determine root cause**:
   - Is trigger condition missing?
   - Is critical pattern not emphasized?
   - Is workflow unclear?
   - Is reference content too deep?

3. **Plan fix**:
   - Add missing trigger
   - Elevate pattern to CRITICAL
   - Clarify workflow steps
   - Flatten reference structure

### Refinement Pattern

```
Failure identified
   ↓
Root cause analysis
   ↓
Minimal change to address
   ↓
Re-run evaluation
   ↓
Verify fix
   ↓
Check for regressions
```

### Regression Testing

**After each change**:
1. Re-run all existing evaluations
2. Verify no new failures introduced
3. Confirm original issues resolved

**Regression tracking**:
```
Change: Added emphasis to validation step
Impact:
- Evaluation 1: Still passing ✓
- Evaluation 2: Still passing ✓
- Evaluation 3: Now passing ✓ (was failing)
- Evaluation 4: Still passing ✓

No regressions detected
```

### A/B Testing Pattern

**Compare versions**:
```
Version A (current):
- Success rate: 80%
- Average time: 5 minutes

Version B (with change):
- Success rate: 95%
- Average time: 4 minutes

Conclusion: Version B is improvement
```

## Continuous Evaluation

### Ongoing Testing Schedule

**Initial development**:
- Run evaluations after each significant change
- Target: 90%+ success rate before shipping

**Maintenance**:
- Monthly evaluation runs
- After any Skill updates
- When underlying tools/libraries update

### Evaluation Maintenance

**Keep evaluations current**:
- Update when patterns change
- Add new scenarios as discovered
- Remove obsolete tests
- Adjust success criteria as needed

### Feedback Loop

```
Real-world usage
   ↓
Observe failures
   ↓
Create new evaluations
   ↓
Update Skill
   ↓
Verify improvement
   ↓
Deploy updates
```

## Evaluation Anti-Patterns

❌ **Writing Skill without evaluations**
- Risk: Solving imagined problems

❌ **Only testing happy path**
- Risk: Missing edge cases and errors

❌ **Not testing with all target models**
- Risk: Works for Opus, fails for Haiku

❌ **Ignoring failed evaluations**
- Risk: Shipping ineffective Skill

❌ **Over-optimizing for evaluations**
- Risk: Skill passes tests but fails real usage

❌ **Not updating evaluations**
- Risk: Tests become obsolete

## Quick Evaluation Checklist

Before finalizing Skill:
- [ ] Minimum 3 evaluations created
- [ ] Happy path tested
- [ ] Edge cases tested
- [ ] Error scenarios tested
- [ ] Tested with Haiku, Sonnet, Opus
- [ ] 90%+ success rate achieved
- [ ] No regressions detected
- [ ] Discovery triggers work
- [ ] Navigation paths verified

## See Also

- [../SKILL.md](../SKILL.md) - Complete Skill authoring guidance
- [iterative-development.md](iterative-development.md) - Claude A/B workflow
- [skill-structure-guide.md](skill-structure-guide.md) - File organization
