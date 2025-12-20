# Good Workflow Pattern Examples

> **Last Updated**: 2025-12-20

This file demonstrates effective workflow patterns for Skills that guide Claude through complex, multi-step tasks using clear checklists and structured processes.

## Example 1: PDF Form Filling Workflow

### Workflow with Checklist

````markdown
## PDF Form Filling Workflow

Copy this checklist and check off items as you complete them:

```
Task Progress:
- [ ] Step 1: Analyze the form (run analyze_form.py)
- [ ] Step 2: Create field mapping (edit fields.json)
- [ ] Step 3: Validate mapping (run validate_fields.py)
- [ ] Step 4: Fill the form (run fill_form.py)
- [ ] Step 5: Verify output (run verify_output.py)
```

**Step 1: Analyze the Form**

Run the analysis script to extract form field information:

```bash
python scripts/analyze_form.py input.pdf
```

This creates `fields.json` containing:
- Field names and types
- Coordinates (x, y positions)
- Size information
- Required vs optional fields

**Step 2: Create Field Mapping**

Edit `fields.json` to add values for each field:

```json
{
  "customer_name": {
    "type": "text",
    "value": "John Doe",
    "required": true
  },
  "signature_date": {
    "type": "date",
    "value": "2025-12-20",
    "required": true
  }
}
```

**Step 3: Validate Mapping**

CRITICAL: Run validation before filling:

```bash
python scripts/validate_fields.py fields.json
```

If validation fails:
- Review error messages carefully
- Check field names match form exactly
- Verify required fields have values
- Fix issues and run validation again

**Only proceed when validation passes.**

**Step 4: Fill the Form**

Apply the field mapping to the PDF:

```bash
python scripts/fill_form.py input.pdf fields.json output.pdf
```

**Step 5: Verify Output**

Run verification to check the filled form:

```bash
python scripts/verify_output.py output.pdf
```

If verification fails, return to Step 2 and revise the mapping.
````

**Why this works**:
- ✅ Copy-paste checklist for progress tracking
- ✅ Clear step numbering with descriptive titles
- ✅ Validation loop prevents errors
- ✅ Specific commands with expected outputs
- ✅ Conditional flow (if validation fails, return to earlier step)
- ✅ "CRITICAL" marker emphasizes key steps

## Example 2: Database Migration Workflow

### Workflow with Feedback Loop

````markdown
## Database Migration Workflow

Copy this checklist:

```
Migration Progress:
- [ ] Step 1: Create migration file
- [ ] Step 2: Write up migration
- [ ] Step 3: Write down migration (rollback)
- [ ] Step 4: Test migration on dev database
- [ ] Step 5: Review and validate
- [ ] Step 6: Apply to production
```

**Step 1: Create Migration File**

Generate new migration:

```bash
npm run migration:create -- AddUserRolesTable
```

This creates: `migrations/20251220_add_user_roles_table.js`

**Step 2: Write Up Migration**

Define the forward migration:

```javascript
exports.up = async (knex) => {
  await knex.schema.createTable('user_roles', (table) => {
    table.increments('id').primary()
    table.integer('user_id').notNullable()
    table.string('role').notNullable()
    table.timestamps(true, true)
  })
}
```

**Step 3: Write Down Migration**

CRITICAL: Always provide rollback capability:

```javascript
exports.down = async (knex) => {
  await knex.schema.dropTable('user_roles')
}
```

**Step 4: Test on Dev Database**

Run migration on development:

```bash
npm run migrate:up
```

If errors occur:
1. Review error message
2. Fix migration code
3. Rollback: `npm run migrate:down`
4. Test again

**Step 5: Review and Validate**

Validation checklist:
- [ ] Up migration creates expected schema
- [ ] Down migration successfully reverts changes
- [ ] No data loss in down migration
- [ ] Tested on dev database
- [ ] Migration is idempotent (can run multiple times safely)

If any checks fail, return to Step 2.

**Step 6: Apply to Production**

Only after all validation passes:

```bash
npm run migrate:up --env production
```

Monitor for errors and have rollback plan ready.
````

**Why this works**:
- ✅ Nested checklist for validation step
- ✅ Explicit rollback requirements
- ✅ Test-fix-retest feedback loop
- ✅ Safety emphasis with "CRITICAL" markers
- ✅ Step-by-step guidance prevents skipping validation

## Example 3: React Component Creation Workflow

### Workflow for Non-Code Tasks

````markdown
## React Component Creation Workflow

Copy this checklist:

```
Component Creation:
- [ ] Step 1: Define component requirements
- [ ] Step 2: Choose appropriate patterns
- [ ] Step 3: Write component implementation
- [ ] Step 4: Add TypeScript types
- [ ] Step 5: Write unit tests
- [ ] Step 6: Write Storybook stories
- [ ] Step 7: Review and refine
```

**Step 1: Define Component Requirements**

Document:
- Component purpose and responsibilities
- Props interface (inputs)
- Expected outputs or side effects
- Accessibility requirements
- Responsive behavior

**Step 2: Choose Appropriate Patterns**

Determine:
- Presentation vs container component
- State management approach (useState, useReducer, external store)
- Composition strategy
- Styling approach

Review project conventions in [reference/component-patterns.md](reference/component-patterns.md)

**Step 3: Write Component Implementation**

Create the component file:

```tsx
import React from 'react'

interface UserProfileProps {
  userId: string
  onUpdate?: (userData: UserData) => void
}

export const UserProfile: React.FC<UserProfileProps> = ({
  userId,
  onUpdate
}) => {
  // Implementation
}
```

**Step 4: Add TypeScript Types**

Ensure complete type coverage:
- Props interface defined
- State types explicit
- Event handler types specified
- Return type inferred correctly

Run type check:
```bash
npm run type-check
```

If errors occur:
- Review error messages
- Add missing types
- Fix type mismatches
- Run type-check again

**Step 5: Write Unit Tests**

Create test file `UserProfile.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import { UserProfile } from './UserProfile'

describe('UserProfile', () => {
  it('renders user information', () => {
    render(<UserProfile userId="123" />)
    // Assertions
  })
})
```

Run tests:
```bash
npm test UserProfile
```

Ensure:
- [ ] All props are tested
- [ ] User interactions are covered
- [ ] Error states are handled
- [ ] Edge cases are tested

**Step 6: Write Storybook Stories**

Create `UserProfile.stories.tsx`:

```tsx
import type { Meta, StoryObj } from '@storybook/react'
import { UserProfile } from './UserProfile'

const meta: Meta<typeof UserProfile> = {
  component: UserProfile,
}

export default meta
type Story = StoryObj<typeof UserProfile>

export const Default: Story = {
  args: {
    userId: '123',
  },
}
```

**Step 7: Review and Refine**

Review checklist:
- [ ] Component follows project conventions
- [ ] Code is readable and maintainable
- [ ] Types are complete
- [ ] Tests pass and provide good coverage
- [ ] Storybook stories demonstrate all variants
- [ ] Accessibility requirements met
- [ ] Performance is acceptable

If any issues found, return to appropriate step and refine.
````

**Why this works**:
- ✅ Workflow guides architectural decisions
- ✅ Validation loops at multiple stages
- ✅ Final comprehensive review checklist
- ✅ Clear references to project conventions
- ✅ Emphasis on testing and quality

## Example 4: API Endpoint Development Workflow

### Workflow with Conditional Paths

````markdown
## API Endpoint Development Workflow

Copy this checklist:

```
Endpoint Development:
- [ ] Step 1: Define API contract
- [ ] Step 2: Choose implementation approach
- [ ] Step 3: Implement endpoint handler
- [ ] Step 4: Add validation and error handling
- [ ] Step 5: Write integration tests
- [ ] Step 6: Document API
- [ ] Step 7: Security review
```

**Step 1: Define API Contract**

Document the endpoint:
- HTTP method (GET, POST, PUT, DELETE)
- URL path and parameters
- Request body schema
- Response schema
- Status codes

Example:
```
POST /api/users
Request: { name: string, email: string }
Response: { id: string, name: string, email: string }
Status: 201 Created, 400 Bad Request, 409 Conflict
```

**Step 2: Choose Implementation Approach**

Determine the implementation path:

**Creating a new resource?** → Follow "Create Resource" pattern
**Reading data?** → Follow "Query Resource" pattern
**Updating existing data?** → Follow "Update Resource" pattern
**Deleting data?** → Follow "Delete Resource" pattern

**Create Resource Pattern:**
1. Validate input
2. Check for duplicates
3. Create resource
4. Return 201 with resource data

**Query Resource Pattern:**
1. Parse query parameters
2. Validate pagination/filters
3. Fetch data
4. Return 200 with results

**Update Resource Pattern:**
1. Validate resource exists
2. Validate update permissions
3. Apply changes
4. Return 200 with updated resource

**Delete Resource Pattern:**
1. Validate resource exists
2. Validate delete permissions
3. Perform deletion
4. Return 204 No Content

**Step 3: Implement Endpoint Handler**

Create the handler following the chosen pattern:

```typescript
import { Request, Response } from 'express'
import { createUser } from '../services/users'

export async function createUserHandler(
  req: Request,
  res: Response
) {
  try {
    // Implementation
    const user = await createUser(req.body)
    res.status(201).json(user)
  } catch (error) {
    // Error handling
  }
}
```

**Step 4: Add Validation and Error Handling**

Add input validation:

```typescript
import { z } from 'zod'

const createUserSchema = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
})

export async function createUserHandler(
  req: Request,
  res: Response
) {
  // Validate input
  const result = createUserSchema.safeParse(req.body)
  if (!result.success) {
    return res.status(400).json({
      error: 'Validation failed',
      details: result.error.issues,
    })
  }

  // Implementation continues...
}
```

Add error handling for common cases:
- [ ] Input validation errors (400)
- [ ] Resource not found (404)
- [ ] Duplicate resource (409)
- [ ] Permission denied (403)
- [ ] Server errors (500)

**Step 5: Write Integration Tests**

Create test file:

```typescript
import request from 'supertest'
import { app } from '../app'

describe('POST /api/users', () => {
  it('creates a new user', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ name: 'John Doe', email: 'john@example.com' })
      .expect(201)

    expect(response.body).toMatchObject({
      name: 'John Doe',
      email: 'john@example.com',
    })
  })

  it('returns 400 for invalid email', async () => {
    await request(app)
      .post('/api/users')
      .send({ name: 'John Doe', email: 'invalid' })
      .expect(400)
  })
})
```

Test coverage checklist:
- [ ] Happy path (successful request)
- [ ] Invalid input (400 errors)
- [ ] Resource conflicts (409 errors)
- [ ] Edge cases

Run tests:
```bash
npm test -- api/users
```

If tests fail:
- Review failure messages
- Fix implementation issues
- Run tests again

**Step 6: Document API**

Add OpenAPI/Swagger documentation:

```yaml
paths:
  /api/users:
    post:
      summary: Create a new user
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                name:
                  type: string
                email:
                  type: string
                  format: email
      responses:
        '201':
          description: User created successfully
```

**Step 7: Security Review**

Security checklist:
- [ ] Input validation prevents injection attacks
- [ ] Authentication required (if applicable)
- [ ] Authorization checks implemented
- [ ] Rate limiting considered
- [ ] Sensitive data not logged
- [ ] CORS configured appropriately

If any security concerns, address them before merging.
````

**Why this works**:
- ✅ Conditional workflow based on operation type
- ✅ Pattern-based guidance for common scenarios
- ✅ Comprehensive error handling checklist
- ✅ Testing integrated into workflow
- ✅ Security review as final gate

## Key Workflow Patterns

### Pattern: Linear Workflow

Best for sequential tasks with clear dependencies:

```markdown
Step 1 → Step 2 → Step 3 → Step 4
```

Use when each step must complete before the next.

### Pattern: Workflow with Validation Loop

Best for tasks with quality gates:

```markdown
Step 1 → Step 2 → Validate
                    ↓ Pass → Continue
                    ↓ Fail → Return to Step 2
```

Use when intermediate validation prevents costly errors.

### Pattern: Conditional Workflow

Best for tasks with multiple valid approaches:

```markdown
Step 1 → Decision Point → Path A → Step 3
                       → Path B → Step 3
                       → Path C → Step 3
```

Use when implementation varies based on requirements.

### Pattern: Iterative Workflow

Best for tasks requiring refinement:

```markdown
Step 1 → Step 2 → Step 3 → Review
                            ↓ Issues → Return to Step 1
                            ↓ Done → Complete
```

Use for quality-critical or creative tasks.

## Checklist Design Principles

### 1. Use Clear Step Numbering

```markdown
✅ Good:
- [ ] Step 1: Analyze form
- [ ] Step 2: Create mapping
- [ ] Step 3: Validate mapping

❌ Bad:
- [ ] Analyze
- [ ] Create
- [ ] Validate
```

### 2. Make Steps Action-Oriented

```markdown
✅ Good:
- [ ] Run validation script
- [ ] Fix reported errors
- [ ] Re-run validation

❌ Bad:
- [ ] Validation
- [ ] Errors
- [ ] Check again
```

### 3. Include Tool Commands

```markdown
✅ Good:
- [ ] Step 3: Validate (run `npm test`)

❌ Bad:
- [ ] Step 3: Run tests
```

### 4. Indicate Conditional Steps

```markdown
✅ Good:
- [ ] Step 4: Fill form
- [ ] Step 5: If validation fails, return to Step 2

❌ Bad:
- [ ] Step 4: Fill form
- [ ] Step 5: Verify
```

## Feedback Loop Patterns

### Pattern: Validate → Fix → Repeat

```markdown
1. Make changes
2. Run validation: `./validate.sh`
3. If validation fails:
   - Review errors
   - Fix issues
   - Return to Step 2
4. Only proceed when validation passes
```

### Pattern: Test → Debug → Retest

```markdown
1. Run test suite: `npm test`
2. If tests fail:
   - Review failure messages
   - Debug implementation
   - Fix issues
   - Return to Step 1
3. All tests must pass before continuing
```

### Pattern: Review → Refine → Re-review

```markdown
1. Complete initial implementation
2. Review against checklist
3. If issues found:
   - Note specific problems
   - Refine implementation
   - Return to Step 2
4. Only finalize when all checks pass
```

## Workflow Documentation Tips

### 1. Provide Expected Outputs

```markdown
✅ Good:
Run: `python analyze.py input.pdf`

Output format:
```json
{"field_name": {"type": "text", "x": 100, "y": 200}}
```

❌ Bad:
Run: `python analyze.py input.pdf`
```

### 2. Explain Validation Criteria

```markdown
✅ Good:
Validation checks:
- All required fields have values
- Email addresses are valid format
- Dates are in YYYY-MM-DD format

❌ Bad:
Run validation script
```

### 3. Indicate Time Estimates (Optional)

```markdown
Note: Analysis typically takes 2-5 seconds for a 10-page document
```

### 4. Mark Critical Steps

```markdown
✅ Use markers:
**CRITICAL**: Always validate before filling the form

⚠️ **WARNING**: This operation cannot be undone

💡 **TIP**: Use grep to quickly find specific fields
```

## Anti-Patterns (See workflow-patterns-bad.md)

❌ No checklist (hard to track progress)
❌ Vague step descriptions
❌ No validation loops
❌ No conditional guidance
❌ Missing error handling instructions
❌ No feedback on what success looks like

## Testing Workflows

Verify workflow effectiveness by:
1. Do users/Claude follow the steps in order?
2. Are validation loops preventing errors?
3. Do checklists help track progress?
4. Are conditional paths clear?
5. Does the workflow scale to different scenarios?

## See Also

- [workflow-patterns-bad.md](workflow-patterns-bad.md) - Common workflow mistakes
- [../SKILL.md](../SKILL.md) - Full Skill authoring guidance
- [../reference/common-patterns-library.md](../reference/common-patterns-library.md) - Reusable patterns
