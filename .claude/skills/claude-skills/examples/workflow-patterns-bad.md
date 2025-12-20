# Bad Workflow Pattern Examples

> **Last Updated**: 2025-12-20

This file demonstrates common mistakes in workflow patterns for Skills, including missing checklists, unclear steps, and ineffective guidance for multi-step tasks.

## Bad Example 1: No Checklist

### Problem: No Progress Tracking

```markdown
## PDF Form Filling Workflow

First, you need to analyze the form. Then create a field mapping. After that,
validate the mapping. Next, fill the form. Finally, verify the output.
```

**Problems**:
- ❌ No checklist to track progress
- ❌ Steps blend together in paragraph
- ❌ Hard to see what's completed
- ❌ No clear step numbers
- ❌ Vague action descriptions

**Fixed version**:

````markdown
## PDF Form Filling Workflow

Copy this checklist:

```
Task Progress:
- [ ] Step 1: Analyze form structure
- [ ] Step 2: Create field mapping
- [ ] Step 3: Validate mapping
- [ ] Step 4: Fill form
- [ ] Step 5: Verify output
```

**Step 1: Analyze Form Structure**
[Detailed instructions...]
````

## Bad Example 2: Vague Steps

### Problem: Unclear What To Do

```markdown
## Database Migration Workflow

1. Set things up
2. Do the migration
3. Check if it worked
4. Deploy
```

**Problems**:
- ❌ "Set things up" - what specifically?
- ❌ "Do the migration" - how?
- ❌ "Check if it worked" - what to check?
- ❌ No commands or tools specified
- ❌ No validation criteria

**Fixed version**:

````markdown
## Database Migration Workflow

Copy this checklist:

```
Migration Progress:
- [ ] Step 1: Create migration file (run migration:create)
- [ ] Step 2: Write up/down migrations
- [ ] Step 3: Test on dev database
- [ ] Step 4: Validate with schema check
- [ ] Step 5: Apply to production
```

**Step 1: Create Migration File**

Run the migration generator:
```bash
npm run migration:create -- AddUserRolesTable
```

Creates: `migrations/20251220_add_user_roles_table.js`

**Step 2: Write Up/Down Migrations**

Write forward migration:
```javascript
exports.up = async (knex) => {
  await knex.schema.createTable('user_roles', (table) => {
    table.increments('id').primary()
    table.integer('user_id').notNullable()
    table.string('role').notNullable()
  })
}
```

Write rollback migration:
```javascript
exports.down = async (knex) => {
  await knex.schema.dropTable('user_roles')
}
```

[Continue with specific details for each step...]
````

## Bad Example 3: No Validation Loop

### Problem: Missing Error Prevention

```markdown
## Document Editing Workflow

1. Edit the document
2. Save the document
3. Done
```

**Problems**:
- ❌ No validation before saving
- ❌ Errors discovered too late
- ❌ No feedback loop to fix issues
- ❌ Assumes everything works first try

**Fixed version**:

````markdown
## Document Editing Workflow

Copy this checklist:

```
Edit Progress:
- [ ] Step 1: Make edits
- [ ] Step 2: Validate edits
- [ ] Step 3: Save document
- [ ] Step 4: Verify saved file
```

**Step 1: Make Edits**

Edit `word/document.xml`:
[Instructions...]

**Step 2: Validate Edits**

CRITICAL: Validate before saving:

```bash
python scripts/validate.py unpacked_dir/
```

If validation fails:
1. Review error messages
2. Fix issues in XML
3. Run validation again

**Only proceed when validation passes.**

**Step 3: Save Document**

```bash
python scripts/pack.py unpacked_dir/ output.docx
```

**Step 4: Verify Saved File**

Open the file and check:
- [ ] Document opens without errors
- [ ] Edits are present
- [ ] Formatting preserved

If issues found, return to Step 1.
````

## Bad Example 4: No Conditional Guidance

### Problem: One-Size-Fits-All Approach

```markdown
## API Endpoint Development

1. Create the endpoint
2. Add validation
3. Write tests
4. Deploy
```

**Problems**:
- ❌ Doesn't account for different endpoint types
- ❌ GET vs POST vs PUT handled identically
- ❌ No guidance on approach selection
- ❌ Misses context-specific needs

**Fixed version**:

````markdown
## API Endpoint Development

**Step 1: Determine Endpoint Type**

**Creating resource (POST)?** → Follow "Create Resource" workflow
**Reading data (GET)?** → Follow "Query Resource" workflow
**Updating (PUT/PATCH)?** → Follow "Update Resource" workflow
**Deleting (DELETE)?** → Follow "Delete Resource" workflow

### Create Resource Workflow

```
Create Progress:
- [ ] Step 1: Validate input schema
- [ ] Step 2: Check for duplicates
- [ ] Step 3: Create resource
- [ ] Step 4: Return 201 with resource
```

[Detailed steps for creation...]

### Query Resource Workflow

```
Query Progress:
- [ ] Step 1: Parse query parameters
- [ ] Step 2: Validate pagination/filters
- [ ] Step 3: Fetch data
- [ ] Step 4: Return 200 with results
```

[Detailed steps for queries...]

[Continue for each endpoint type...]
````

## Bad Example 5: No Expected Outputs

### Problem: No Success Criteria

```markdown
## Form Analysis Workflow

1. Run the analysis script
2. Look at the output
3. Continue with next step
```

**Problems**:
- ❌ What should the output look like?
- ❌ How to know if it worked?
- ❌ No example of success
- ❌ Unclear what to do with output

**Fixed version**:

```markdown
## Form Analysis Workflow

**Step 1: Run Analysis Script**

Execute the analyzer:
```bash
python scripts/analyze_form.py input.pdf
```

**Expected output format**:
```json
{
  "field_name": {
    "type": "text",
    "x": 100,
    "y": 200,
    "width": 150,
    "height": 20
  },
  "signature": {
    "type": "signature",
    "x": 150,
    "y": 500,
    "width": 200,
    "height": 50
  }
}
```

**Success indicators**:
- JSON is valid
- All visible fields detected
- Field types correctly identified
- Coordinates within page bounds

**If output seems incorrect**:
- Verify PDF is form-enabled
- Check for scanned vs digital form
- Try adjusting detection sensitivity
```

## Bad Example 6: Missing Error Handling

### Problem: No Guidance When Things Fail

```markdown
## Build and Deploy Workflow

1. Run build
2. Run tests
3. Deploy to production
```

**Problems**:
- ❌ What if build fails?
- ❌ What if tests fail?
- ❌ No error recovery guidance
- ❌ Assumes perfect execution

**Fixed version**:

````markdown
## Build and Deploy Workflow

Copy this checklist:

```
Deployment Progress:
- [ ] Step 1: Run build
- [ ] Step 2: Run tests
- [ ] Step 3: Review test results
- [ ] Step 4: Deploy to staging
- [ ] Step 5: Smoke test staging
- [ ] Step 6: Deploy to production
```

**Step 1: Run Build**

```bash
npm run build
```

**If build fails**:
1. Review error messages
2. Common issues:
   - TypeScript type errors: Fix type issues
   - Missing dependencies: Run `npm install`
   - Syntax errors: Check recent changes
3. Fix issues and rebuild

**Step 2: Run Tests**

```bash
npm test
```

**If tests fail**:
1. Review failure messages
2. Common issues:
   - Unit test failures: Fix implementation
   - Integration test failures: Check service dependencies
   - Timeout errors: Increase timeout or optimize
3. Fix issues and rerun tests

**Only proceed when all tests pass.**

**Step 3: Review Test Results**

Validation checklist:
- [ ] All tests passed
- [ ] Coverage meets threshold (80%+)
- [ ] No skipped tests
- [ ] No console errors or warnings

If any fail, return to appropriate step.

[Continue with staging and production steps...]
````

## Bad Example 7: No Time Indicators

### Problem: Unrealistic Expectations

```markdown
## Machine Learning Training Workflow

1. Prepare data
2. Train model
3. Evaluate results
4. Deploy model
```

**Problems**:
- ❌ Training could take hours/days
- ❌ No indication of time investment
- ❌ Can't plan accordingly
- ❌ May start at wrong time

**Fixed version**:

```markdown
## Machine Learning Training Workflow

**Important**: Complete training can take 4-8 hours depending on dataset size.
Plan accordingly and don't start right before a deadline.

Copy this checklist:

```
Training Progress:
- [ ] Step 1: Prepare data (~30 minutes)
- [ ] Step 2: Train model (~4-6 hours)
- [ ] Step 3: Evaluate results (~15 minutes)
- [ ] Step 4: Deploy model (~20 minutes)
```

**Step 1: Prepare Data** (Estimated: 30 minutes)

[Instructions...]

**Step 2: Train Model** (Estimated: 4-6 hours)

Note: This is a long-running process. Consider:
- Running overnight
- Using a separate terminal session
- Monitoring with logging

[Instructions...]
```

## Bad Example 8: Linear Only (No Iterative)

### Problem: No Refinement Loop

```markdown
## Design Document Workflow

1. Write initial draft
2. Format document
3. Publish
```

**Problems**:
- ❌ No review cycle
- ❌ No refinement opportunity
- ❌ Quality may be poor
- ❌ Assumes first draft is final

**Fixed version**:

````markdown
## Design Document Workflow

Copy this checklist:

```
Document Progress:
- [ ] Step 1: Write initial draft
- [ ] Step 2: Review against checklist
- [ ] Step 3: Refine draft
- [ ] Step 4: Peer review
- [ ] Step 5: Incorporate feedback
- [ ] Step 6: Final review
- [ ] Step 7: Publish
```

**Step 1: Write Initial Draft**

Write complete draft including:
- Problem statement
- Proposed solution
- Alternatives considered
- Implementation plan

**Step 2: Review Against Checklist**

Self-review checklist:
- [ ] Problem clearly stated
- [ ] Solution addresses problem
- [ ] Alternatives documented
- [ ] Trade-offs explained
- [ ] Implementation realistic
- [ ] Timeline reasonable

**If any items fail, return to Step 1 and revise.**

**Step 3: Refine Draft**

Based on self-review:
- Strengthen weak sections
- Add missing details
- Clarify unclear parts
- Remove redundancy

**Step 4: Peer Review**

Share with team for feedback on:
- Technical approach
- Implementation feasibility
- Missing considerations
- Clarity and completeness

**Step 5: Incorporate Feedback**

Address peer review comments:
- Critical issues: Must address
- Suggestions: Evaluate and apply if helpful
- Questions: Clarify in document

**Step 6: Final Review**

Final checklist:
- [ ] All peer feedback addressed
- [ ] No open questions
- [ ] Document is complete
- [ ] Formatting is correct

**If any issues, return to Step 5.**

**Step 7: Publish**

[Publishing instructions...]
````

## Bad Example 9: No Prerequisites

### Problem: Assumes Everything Ready

```markdown
## Docker Deployment Workflow

1. Build Docker image
2. Push to registry
3. Deploy to Kubernetes
```

**Problems**:
- ❌ No prerequisite check
- ❌ May fail if Docker not installed
- ❌ No registry authentication check
- ❌ No cluster configuration verification

**Fixed version**:

````markdown
## Docker Deployment Workflow

**Prerequisites** (verify before starting):
- [ ] Docker installed and running
- [ ] Docker registry credentials configured
- [ ] kubectl installed and configured
- [ ] Access to target Kubernetes cluster
- [ ] Necessary permissions for deployment

**Verify prerequisites**:
```bash
# Check Docker
docker --version
docker info

# Check registry access
docker login registry.example.com

# Check kubectl
kubectl version
kubectl get nodes
```

**If any prerequisite fails, resolve before continuing.**

Copy deployment checklist:

```
Deployment Progress:
- [ ] Step 1: Build Docker image
- [ ] Step 2: Test image locally
- [ ] Step 3: Push to registry
- [ ] Step 4: Update Kubernetes manifests
- [ ] Step 5: Deploy to cluster
- [ ] Step 6: Verify deployment
```

[Detailed steps...]
````

## Bad Example 10: No Cleanup or Rollback

### Problem: No Recovery Plan

```markdown
## Database Schema Update

1. Apply migration
2. Restart services
3. Monitor logs
```

**Problems**:
- ❌ What if migration fails?
- ❌ No rollback plan
- ❌ No cleanup after failure
- ❌ May leave database in bad state

**Fixed version**:

````markdown
## Database Schema Update

**CRITICAL: Always have rollback plan ready**

Copy this checklist:

```
Update Progress:
- [ ] Step 1: Backup database
- [ ] Step 2: Test migration on staging
- [ ] Step 3: Apply migration to production
- [ ] Step 4: Verify schema changes
- [ ] Step 5: Restart services
- [ ] Step 6: Monitor for errors
- [ ] Step 7: Rollback if needed
```

**Step 1: Backup Database**

Create backup before any changes:
```bash
pg_dump -Fc production_db > backup_20251220.dump
```

Verify backup is complete:
```bash
pg_restore --list backup_20251220.dump
```

**Step 2: Test Migration on Staging**

Apply to staging first:
```bash
npm run migrate:up --env staging
```

Verify:
- [ ] Migration applied successfully
- [ ] Schema matches expectations
- [ ] Application works correctly
- [ ] No data issues

**If staging fails, DO NOT proceed to production.**

**Step 3: Apply Migration to Production**

```bash
npm run migrate:up --env production
```

**Step 4: Verify Schema Changes**

Check schema:
```sql
\d table_name  -- PostgreSQL
DESCRIBE table_name;  -- MySQL
```

Validation:
- [ ] New columns exist
- [ ] Constraints applied
- [ ] Indexes created
- [ ] No unexpected changes

**If verification fails, proceed to Step 7 (Rollback).**

[Continue with remaining steps...]

**Step 7: Rollback if Needed**

**If any issues occur**:

1. Run down migration:
```bash
npm run migrate:down --env production
```

2. Verify rollback:
```sql
\d table_name  -- Check schema reverted
```

3. Restart services with old schema

4. Restore from backup if needed:
```bash
pg_restore -d production_db backup_20251220.dump
```

5. Investigate issues before retrying
````

## Workflow Anti-Patterns Summary

### Structure Issues
- ❌ No checklist for progress tracking
- ❌ Vague step descriptions
- ❌ Steps in paragraph form
- ❌ No clear numbering

### Guidance Issues
- ❌ No validation loops
- ❌ No conditional paths
- ❌ No error handling
- ❌ Linear only (no iteration)

### Quality Issues
- ❌ No expected outputs shown
- ❌ No success criteria
- ❌ Missing prerequisites
- ❌ No rollback plan

### Planning Issues
- ❌ No time indicators
- ❌ No preparation steps
- ❌ No cleanup guidance
- ❌ Unrealistic expectations

## Quick Fix Checklist

Before finalizing workflow:
- [ ] Copy-paste checklist provided
- [ ] Steps clearly numbered
- [ ] Each step has detailed instructions
- [ ] Validation loops included
- [ ] Error handling specified
- [ ] Expected outputs shown
- [ ] Success criteria defined
- [ ] Prerequisites listed
- [ ] Rollback plan included (if applicable)
- [ ] Time estimates provided (if helpful)

## See Also

- [workflow-patterns-good.md](workflow-patterns-good.md) - Effective workflow patterns
- [../SKILL.md](../SKILL.md) - Full Skill authoring guidance
- [../reference/common-patterns-library.md](../reference/common-patterns-library.md) - Reusable patterns
