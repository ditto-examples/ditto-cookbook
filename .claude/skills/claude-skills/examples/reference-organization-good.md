# Good Reference Organization Examples

> **Last Updated**: 2025-12-20

This file demonstrates effective organization of reference files within Skills, including naming conventions, structure, and content organization patterns.

## Example 1: API Reference File

### File: `reference/api-reference.md`

```markdown
# pdfplumber API Reference

> **Last Updated**: 2025-12-20

## Contents
- Opening PDFs
- Page navigation
- Text extraction
- Table extraction
- Form field extraction
- Image extraction
- Metadata access
- Closing PDFs

## Opening PDFs

### pdfplumber.open()

Opens a PDF file for processing.

**Signature**:
```python
pdfplumber.open(
    path: str | Path | BytesIO,
    password: str | None = None,
    **kwargs
) -> PDF
```

**Parameters**:
- `path`: File path or BytesIO object
- `password`: PDF password if encrypted
- `**kwargs`: Additional arguments passed to pdfminer

**Returns**: PDF object

**Example**:
```python
import pdfplumber

with pdfplumber.open("document.pdf") as pdf:
    print(f"Page count: {len(pdf.pages)}")
```

**Error handling**:
```python
try:
    with pdfplumber.open("document.pdf") as pdf:
        # Process PDF
        pass
except FileNotFoundError:
    print("PDF file not found")
except Exception as e:
    print(f"Error opening PDF: {e}")
```

## Page Navigation

### pdf.pages

List of Page objects, one per page.

**Type**: `list[Page]`

**Example**:
```python
with pdfplumber.open("document.pdf") as pdf:
    # Get first page
    first_page = pdf.pages[0]

    # Iterate all pages
    for page in pdf.pages:
        print(f"Page {page.page_number}")
```

### page.page_number

Zero-indexed page number.

**Type**: `int`

## Text Extraction

### page.extract_text()

Extracts all text from the page.

**Signature**:
```python
page.extract_text(
    x_tolerance: int = 3,
    y_tolerance: int = 3,
    layout: bool = False,
    **kwargs
) -> str | None
```

**Parameters**:
- `x_tolerance`: Horizontal tolerance for text grouping
- `y_tolerance`: Vertical tolerance for text grouping
- `layout`: Preserve layout with whitespace

**Returns**: Extracted text as string, or None if no text

**Example**:
```python
text = page.extract_text()
if text:
    print(text)
```

**Layout preservation**:
```python
# Preserve original layout
text = page.extract_text(layout=True)
```

[Additional sections continue...]
```

**Why this works**:
- ✅ Table of contents at the top
- ✅ Clear section headers
- ✅ Consistent signature format
- ✅ Parameter descriptions
- ✅ Return type documentation
- ✅ Code examples for each method
- ✅ Error handling examples
- ✅ Last Updated timestamp

## Example 2: Domain-Specific Schema Reference

### File: `reference/finance-schemas.md`

```markdown
# Finance Dataset Schemas

> **Last Updated**: 2025-12-20

## Contents
- Revenue metrics
- Billing data
- Customer financial data
- Subscription analytics
- Payment processing

## Revenue Metrics

### Table: `analytics.revenue_daily`

Daily revenue rollup across all sources.

**Schema**:
| Column | Type | Description | Notes |
|--------|------|-------------|-------|
| date | DATE | Transaction date | Primary key |
| revenue_total | DECIMAL(12,2) | Total revenue | Sum of all sources |
| revenue_mrr | DECIMAL(12,2) | Monthly recurring | Subscription only |
| revenue_one_time | DECIMAL(12,2) | One-time payments | Non-recurring |
| customer_count | INT | Unique customers | Distinct count |

**Filters**:
- Always exclude test accounts: `WHERE account_type != 'test'`
- Date range typically: last 90 days

**Example Query**:
```sql
SELECT
  date,
  revenue_total,
  revenue_mrr
FROM analytics.revenue_daily
WHERE date >= CURRENT_DATE - INTERVAL '90 days'
  AND account_type != 'test'
ORDER BY date DESC
```

**Common Aggregations**:

Monthly totals:
```sql
SELECT
  DATE_TRUNC('month', date) AS month,
  SUM(revenue_total) AS monthly_revenue
FROM analytics.revenue_daily
WHERE date >= CURRENT_DATE - INTERVAL '1 year'
  AND account_type != 'test'
GROUP BY month
ORDER BY month DESC
```

### Table: `analytics.revenue_by_product`

Revenue breakdown by product line.

**Schema**:
| Column | Type | Description | Notes |
|--------|------|-------------|-------|
| date | DATE | Transaction date | |
| product_id | STRING | Product identifier | |
| product_name | STRING | Product display name | |
| revenue | DECIMAL(12,2) | Product revenue | |
| unit_count | INT | Units sold | |

**Joins**:
- `analytics.products` on `product_id`
- `analytics.customers` on `customer_id`

**Example Query**:
```sql
SELECT
  p.product_name,
  SUM(r.revenue) AS total_revenue,
  SUM(r.unit_count) AS total_units
FROM analytics.revenue_by_product r
JOIN analytics.products p
  ON r.product_id = p.product_id
WHERE r.date >= CURRENT_DATE - INTERVAL '30 days'
  AND p.status = 'active'
  AND r.account_type != 'test'
GROUP BY p.product_name
ORDER BY total_revenue DESC
```

[Additional tables continue...]
```

**Why this works**:
- ✅ Table-based schema documentation
- ✅ Always-include filters documented
- ✅ Common query patterns provided
- ✅ Join relationships specified
- ✅ Real-world examples

## Example 3: Troubleshooting Guide

### File: `reference/troubleshooting.md`

```markdown
# PDF Processing Troubleshooting Guide

> **Last Updated**: 2025-12-20

## Contents
- Installation issues
- File opening errors
- Text extraction problems
- Form filling errors
- Memory issues
- Performance problems

## Installation Issues

### Problem: pdfplumber not found

**Error message**:
```
ModuleNotFoundError: No module named 'pdfplumber'
```

**Solution**:
```bash
pip install pdfplumber
```

**Verify installation**:
```python
import pdfplumber
print(pdfplumber.__version__)
```

### Problem: Conflicting dependencies

**Error message**:
```
ERROR: pip's dependency resolver does not currently take into account
all the packages that are installed.
```

**Solution**:
1. Create clean virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install pdfplumber:
```bash
pip install pdfplumber
```

## File Opening Errors

### Problem: FileNotFoundError

**Error message**:
```
FileNotFoundError: [Errno 2] No such file or directory: 'document.pdf'
```

**Common causes**:
- Incorrect file path
- File in different directory
- Typo in filename

**Debugging steps**:
1. Check current directory:
```python
import os
print(os.getcwd())
```

2. List files:
```python
import os
print(os.listdir('.'))
```

3. Use absolute path:
```python
import pdfplumber
pdf_path = "/full/path/to/document.pdf"
with pdfplumber.open(pdf_path) as pdf:
    # Process
```

### Problem: Permission denied

**Error message**:
```
PermissionError: [Errno 13] Permission denied: 'document.pdf'
```

**Solutions**:
1. Check file permissions
2. Ensure file is not open in another program
3. Run with appropriate permissions

## Text Extraction Problems

### Problem: No text extracted (returns None)

**Possible causes**:
- PDF is image-based (scanned document)
- Text is embedded as images
- Font encoding issues

**Solution for scanned PDFs**:

Use OCR (Optical Character Recognition):
```python
from pdf2image import convert_from_path
import pytesseract

# Convert PDF to images
images = convert_from_path('scanned.pdf')

# Extract text using OCR
text = ""
for image in images:
    text += pytesseract.image_to_string(image)

print(text)
```

**Solution for font encoding issues**:
```python
# Try different extraction parameters
text = page.extract_text(
    x_tolerance=5,
    y_tolerance=5
)
```

### Problem: Garbled or incorrect characters

**Cause**: Font encoding issues

**Solution**:
1. Try increasing tolerance:
```python
text = page.extract_text(
    x_tolerance=10,
    y_tolerance=10
)
```

2. Use layout mode:
```python
text = page.extract_text(layout=True)
```

## Form Filling Errors

### Problem: Field not found

**Error message**:
```
KeyError: 'field_name'
```

**Debugging steps**:
1. Extract and list all fields:
```python
import PyPDF2

with open('form.pdf', 'rb') as f:
    reader = PyPDF2.PdfReader(f)
    fields = reader.get_fields()
    for field_name in fields:
        print(field_name)
```

2. Check exact field name (case-sensitive)
3. Verify field type matches expected type

### Problem: Form not saving changes

**Possible causes**:
- Form is read-only
- Incorrect save method
- Missing flatten operation

**Solution**:
```python
from PyPDF2 import PdfReader, PdfWriter

reader = PdfReader('form.pdf')
writer = PdfWriter()

# Fill form fields
writer.add_page(reader.pages[0])
writer.update_page_form_field_values(
    writer.pages[0],
    {'field_name': 'value'}
)

# Save with flatten
with open('filled_form.pdf', 'wb') as f:
    writer.write(f)
```

## Memory Issues

### Problem: MemoryError with large PDFs

**Error message**:
```
MemoryError: Unable to allocate memory
```

**Solution**: Process pages one at a time:
```python
import pdfplumber

with pdfplumber.open('large.pdf') as pdf:
    for i, page in enumerate(pdf.pages):
        # Process one page
        text = page.extract_text()

        # Save to file immediately
        with open(f'page_{i}.txt', 'w') as f:
            f.write(text)

        # Free memory
        del text
```

## Performance Problems

### Problem: Slow extraction

**Optimization strategies**:

1. **Process only needed pages**:
```python
# Instead of all pages
with pdfplumber.open('document.pdf') as pdf:
    # Only process first 10 pages
    for page in pdf.pages[:10]:
        text = page.extract_text()
```

2. **Use multiprocessing for large batches**:
```python
from multiprocessing import Pool
import pdfplumber

def extract_page(args):
    pdf_path, page_num = args
    with pdfplumber.open(pdf_path) as pdf:
        return pdf.pages[page_num].extract_text()

pdf_path = 'document.pdf'
with pdfplumber.open(pdf_path) as pdf:
    page_count = len(pdf.pages)

with Pool() as pool:
    args = [(pdf_path, i) for i in range(page_count)]
    texts = pool.map(extract_page, args)
```

3. **Adjust extraction parameters**:
```python
# Reduce precision for faster extraction
text = page.extract_text(
    x_tolerance=10,  # Higher = faster but less precise
    y_tolerance=10
)
```

[Additional sections continue...]
```

**Why this works**:
- ✅ Problem-solution format
- ✅ Error messages included
- ✅ Debugging steps provided
- ✅ Multiple solutions when applicable
- ✅ Code examples for each solution
- ✅ Organized by problem category

## Example 4: Pattern Library Reference

### File: `reference/common-patterns-library.md`

```markdown
# Common Patterns Library

> **Last Updated**: 2025-12-20

Reusable patterns for Skills. Copy and adapt these templates for your Skills.

## Contents
- Template pattern
- Example pattern
- Conditional workflow pattern
- Validation loop pattern
- Checklist pattern

## Template Pattern

Use when output must follow a specific structure.

### Strict Template

For cases requiring exact structure (API responses, data formats):

````markdown
## [Operation Name]

ALWAYS use this exact template:

```[format]
[template structure]
```

**Example**:
```[format]
[filled example]
```
````

**Copy-paste template**:

````markdown
## Report Generation

ALWAYS use this exact template:

```markdown
# [Report Title]

## Executive Summary
[One paragraph overview]

## Key Findings
- Finding 1
- Finding 2
- Finding 3

## Recommendations
1. Recommendation 1
2. Recommendation 2
```

**Example**:
```markdown
# Q4 Sales Analysis

## Executive Summary
Sales increased 23% over Q3, driven by enterprise accounts.

## Key Findings
- Enterprise revenue up 45%
- SMB revenue flat
- Churn rate decreased to 3.2%

## Recommendations
1. Increase enterprise sales team
2. Develop SMB retention program
```
````

### Flexible Template

For cases where adaptation is useful:

````markdown
## [Operation Name]

Here is a sensible default format:

```[format]
[template structure]
```

Adjust sections as needed based on [specific context].

**Example variations**:
- [Variation 1]: [When to use]
- [Variation 2]: [When to use]
````

## Example Pattern

Use when output quality depends on seeing examples.

### Single Example

````markdown
## [Operation Name]

Generate [output] following this example:

**Example**:
Input: [input example]
Output:
```
[output example]
```

Follow this [style/format/approach].
````

### Multiple Examples

````markdown
## [Operation Name]

Generate [output] following these examples:

**Example 1**: [Scenario 1]
Input: [input]
Output:
```
[output]
```

**Example 2**: [Scenario 2]
Input: [input]
Output:
```
[output]
```

**Example 3**: [Scenario 3]
Input: [input]
Output:
```
[output]
```

Follow this [style/format/approach]: [description]
````

## Conditional Workflow Pattern

Use when multiple valid approaches exist.

**Copy-paste template**:

````markdown
## [Workflow Name]

**Step 1**: Determine the [decision criteria]

**Is it [Scenario A]?** → Follow "[Scenario A] workflow" below
**Is it [Scenario B]?** → Follow "[Scenario B] workflow" below
**Is it [Scenario C]?** → Follow "[Scenario C] workflow" below

### [Scenario A] Workflow

1. [Step 1]
2. [Step 2]
3. [Step 3]

### [Scenario B] Workflow

1. [Step 1]
2. [Step 2]
3. [Step 3]

### [Scenario C] Workflow

1. [Step 1]
2. [Step 2]
3. [Step 3]
````

**Example usage**:

````markdown
## Document Modification Workflow

**Step 1**: Determine the modification type

**Creating new content?** → Follow "Creation workflow" below
**Editing existing content?** → Follow "Editing workflow" below
**Merging documents?** → Follow "Merge workflow" below

### Creation Workflow

1. Use docx-js library
2. Build document from scratch
3. Export to .docx format

### Editing Workflow

1. Unpack existing document
2. Modify XML directly
3. Validate after each change
4. Repack when complete

### Merge Workflow

1. Load all documents
2. Combine content
3. Resolve style conflicts
4. Export merged document
````

## Validation Loop Pattern

Use when intermediate validation prevents errors.

**Copy-paste template**:

````markdown
## [Operation Name] Workflow

Copy this checklist:

```
[Operation] Progress:
- [ ] Step 1: [Action]
- [ ] Step 2: [Action]
- [ ] Step 3: Validate [aspect]
- [ ] Step 4: [Action]
- [ ] Step 5: Verify [result]
```

**Step 1**: [Description]

[Implementation details]

**Step 2**: [Description]

[Implementation details]

**Step 3**: Validate [aspect]

CRITICAL: Run validation before continuing:

```bash
[validation command]
```

If validation fails:
- [Fix step 1]
- [Fix step 2]
- Run validation again

**Only proceed when validation passes.**

**Step 4**: [Description]

[Implementation details]

**Step 5**: Verify [result]

```bash
[verification command]
```

If verification fails, return to Step [X].
````

## Checklist Pattern

Use for multi-step processes requiring progress tracking.

**Copy-paste template**:

````markdown
## [Task Name] Workflow

Copy this checklist and check off items as you complete them:

```
Task Progress:
- [ ] Step 1: [Action description]
- [ ] Step 2: [Action description]
- [ ] Step 3: [Action description]
- [ ] Step 4: [Action description]
- [ ] Step 5: [Action description]
```

**Step 1**: [Title]

[Detailed instructions]

**Step 2**: [Title]

[Detailed instructions]

[Continue for all steps...]
````

### Nested Checklist (for validation steps)

````markdown
**Step 3**: Review and Validate

Validation checklist:
- [ ] [Check 1]
- [ ] [Check 2]
- [ ] [Check 3]
- [ ] [Check 4]

If any checks fail, return to Step [X].
````

[Additional patterns continue...]
```

**Why this works**:
- ✅ Organized by pattern type
- ✅ Copy-paste templates provided
- ✅ Example usage for each pattern
- ✅ Clear use cases (when to use)
- ✅ Variations demonstrated

## Reference File Organization Principles

### 1. Start with Table of Contents

For files over 100 lines:
```markdown
## Contents
- Section 1
- Section 2
- Section 3
```

### 2. Use Consistent Header Hierarchy

```markdown
# File Title (H1)
## Major Section (H2)
### Subsection (H3)
#### Detail (H4)
```

### 3. Include Timestamps

```markdown
> **Last Updated**: 2025-12-20
```

### 4. Provide Code Examples

Every API method, pattern, or concept should have code example.

### 5. Document Common Pitfalls

Include troubleshooting for predictable issues.

### 6. Cross-Reference Related Content

```markdown
See also:
- [Related topic](related-file.md)
- [Advanced patterns](advanced.md)
```

## File Naming Conventions

### Descriptive Names

✅ Good:
- `api-reference.md`
- `troubleshooting.md`
- `finance-schemas.md`
- `common-patterns-library.md`

❌ Bad:
- `reference.md`
- `guide.md`
- `doc1.md`
- `stuff.md`

### Domain Organization

For large Skills:
```
reference/
├── domain1-guide.md
├── domain2-guide.md
└── domain3-guide.md
```

Example:
```
reference/
├── finance-schemas.md
├── sales-schemas.md
├── product-schemas.md
└── marketing-schemas.md
```

## Anti-Patterns

❌ No table of contents for long files
❌ Missing code examples
❌ Vague file names
❌ No timestamps
❌ Wall of text without structure
❌ Missing error handling examples
❌ No troubleshooting guidance

## See Also

- [reference-organization-bad.md](reference-organization-bad.md) - Common organization mistakes
- [../SKILL.md](../SKILL.md) - Full Skill authoring guidance
- [../reference/skill-structure-guide.md](../reference/skill-structure-guide.md) - Complete structure details
