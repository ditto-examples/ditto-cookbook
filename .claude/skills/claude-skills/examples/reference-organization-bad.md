# Bad Reference Organization Examples

> **Last Updated**: 2025-12-20

This file demonstrates common mistakes in organizing reference files within Skills, including poor naming, lack of structure, and ineffective content organization.

## Bad Example 1: Vague File Names

### Problem: Unclear File Names

```
reference/
├── doc1.md
├── doc2.md
├── guide.md
├── reference.md
├── stuff.md
└── notes.md
```

**Problems**:
- ❌ "doc1" - what's in it?
- ❌ "stuff" - completely uninformative
- ❌ "guide" - guide to what?
- ❌ "reference" - reference about what?
- ❌ Numbers indicate poor organization
- ❌ Can't find content without opening files

**Fixed version**: Descriptive names:

```
reference/
├── api-reference.md
├── troubleshooting.md
├── forms-guide.md
├── security-patterns.md
├── performance-optimization.md
└── migration-guide.md
```

## Bad Example 2: No Table of Contents for Long Files

### Problem: Long File Without Navigation

```markdown
# Complete API Documentation

(2,347 lines of content with no table of contents or navigation)

## Authentication Methods
[Content at line 134]

## Database Queries
[Content at line 589]

## Real-time Sync
[Content at line 1,234]

## Error Handling
[Content at line 1,987]
```

**Problems**:
- ❌ Claude may preview with `head -100`
- ❌ Can't see full scope
- ❌ Doesn't know what sections exist
- ❌ May miss relevant content

**Fixed version**: Add table of contents:

```markdown
# Complete API Documentation

> **Last Updated**: 2025-12-20

## Contents
- Authentication Methods (line 134)
- Database Queries (line 589)
- Real-time Sync (line 1,234)
- Error Handling (line 1,987)

## Authentication Methods

[Content...]

## Database Queries

[Content...]

## Real-time Sync

[Content...]

## Error Handling

[Content...]
```

## Bad Example 3: No Code Examples

### Problem: Theory Without Practice

```markdown
# Database Query Optimization Guide

## Indexing Strategies

Indexes improve query performance by creating data structures that allow
faster lookups. There are several types of indexes including B-tree indexes,
hash indexes, and bitmap indexes. Each has different performance
characteristics and is suited for different use cases.

B-tree indexes are good for range queries. Hash indexes are good for equality
comparisons. Bitmap indexes are good for low-cardinality columns.

When choosing an index type, consider the query patterns, data distribution,
and update frequency.

[Continues for 50 pages without a single code example...]
```

**Problems**:
- ❌ No code examples
- ❌ All theory, no practice
- ❌ Hard to apply knowledge
- ❌ No copy-paste templates

**Fixed version**: Include code examples:

```markdown
# Database Query Optimization Guide

## Indexing Strategies

### B-Tree Indexes

Best for range queries and sorted access.

**Create B-tree index**:
```sql
CREATE INDEX idx_users_created_at
ON users(created_at);
```

**Use case example**:
```sql
-- Efficiently queries date ranges
SELECT * FROM users
WHERE created_at BETWEEN '2025-01-01' AND '2025-12-31';
```

**Performance**: O(log n) lookup time

### Hash Indexes

Best for exact equality comparisons.

**Create hash index**:
```sql
CREATE INDEX idx_users_email USING HASH
ON users(email);
```

**Use case example**:
```sql
-- Efficiently finds exact matches
SELECT * FROM users
WHERE email = 'user@example.com';
```

**Performance**: O(1) lookup time for exact matches

[Continue with examples for each concept...]
```

## Bad Example 4: No Timestamps

### Problem: Unknown Freshness

```markdown
# API Reference

## Authentication

Use the authentication API to authenticate users...

[No indication when this was written or last updated]
```

**Problems**:
- ❌ Can't tell if information is current
- ❌ May be outdated
- ❌ No maintenance tracking

**Fixed version**: Include timestamp:

```markdown
# API Reference

> **Last Updated**: 2025-12-20
> **SDK Version**: 4.12.0+

## Authentication

Use the authentication API to authenticate users...
```

## Bad Example 5: Wall of Text

### Problem: No Structure or Formatting

```markdown
# Configuration Guide

To configure the application you need to create a config file and set various parameters. The config file should be in JSON format and located in the config directory. You need to set the database connection parameters including host port and credentials. You also need to configure the API endpoints and authentication settings. For production deployments make sure to enable HTTPS and set appropriate CORS policies. Logging should be configured to write to files and you can set the log level to debug info warn or error depending on your needs. Cache settings should be tuned based on your memory availability and you might want to enable Redis for distributed caching. Rate limiting is important to prevent abuse so configure appropriate limits for your API endpoints. You should also set up monitoring and alerting to track application health and performance metrics. Error handling should be configured to catch and log exceptions appropriately and you might want to set up error tracking with a service like Sentry. For security make sure to set strong session secrets and use secure hashing with bcrypt using appropriate cost factors...

[Continues as one giant paragraph for pages...]
```

**Problems**:
- ❌ Wall of text - no breaks
- ❌ No headings or sections
- ❌ No code examples
- ❌ Overwhelming to read
- ❌ Hard to find specific information

**Fixed version**: Structured with headings and examples:

```markdown
# Configuration Guide

## Database Configuration

Set database connection parameters in `config/database.json`:

```json
{
  "host": "localhost",
  "port": 5432,
  "username": "app_user",
  "password": "<REDACTED>",
  "database": "app_db"
}
```

## API Configuration

Configure API endpoints in `config/api.json`:

```json
{
  "baseUrl": "https://api.example.com",
  "timeout": 30000,
  "retries": 3
}
```

## Authentication

Set authentication parameters in `config/auth.json`:

```json
{
  "jwtSecret": "your-secret-key",
  "tokenExpiry": "24h",
  "refreshTokenExpiry": "7d"
}
```

[Continue with structured sections...]
```

## Bad Example 6: No Error Handling Examples

### Problem: Missing Failure Scenarios

```markdown
# HTTP Client Guide

## Making Requests

Use the fetch API to make HTTP requests:

```javascript
const response = await fetch('https://api.example.com/data')
const data = await response.json()
return data
```

[No error handling shown]
```

**Problems**:
- ❌ No error handling
- ❌ Assumes perfect execution
- ❌ No guidance for failures
- ❌ Missing common error scenarios

**Fixed version**: Include error handling:

```markdown
# HTTP Client Guide

## Making Requests

### Basic Request with Error Handling

```javascript
try {
  const response = await fetch('https://api.example.com/data')

  // Check HTTP status
  if (!response.ok) {
    throw new Error(`HTTP error: ${response.status}`)
  }

  const data = await response.json()
  return data

} catch (error) {
  // Handle different error types
  if (error.name === 'TypeError') {
    console.error('Network error:', error.message)
  } else {
    console.error('Request failed:', error.message)
  }
  throw error
}
```

### Common Error Scenarios

**Network timeout**:
```javascript
const controller = new AbortController()
const timeout = setTimeout(() => controller.abort(), 5000)

try {
  const response = await fetch(url, { signal: controller.signal })
  // ...
} catch (error) {
  if (error.name === 'AbortError') {
    console.error('Request timed out')
  }
} finally {
  clearTimeout(timeout)
}
```

**JSON parsing errors**:
```javascript
try {
  const data = await response.json()
} catch (error) {
  console.error('Invalid JSON response:', error.message)
  // Fallback to text
  const text = await response.text()
  console.log('Response body:', text)
}
```

[Continue with more error scenarios...]
```

## Bad Example 7: Missing Parameter Documentation

### Problem: Undocumented Parameters

```markdown
# API Reference

## sendMessage()

Sends a message.

```javascript
sendMessage(text, options)
```
```

**Problems**:
- ❌ What type is `text`?
- ❌ What's in `options`?
- ❌ What does it return?
- ❌ No example usage

**Fixed version**: Complete documentation:

```markdown
# API Reference

## sendMessage()

Sends a message to the specified channel.

**Signature**:
```typescript
sendMessage(
  text: string,
  options?: {
    channel?: string
    priority?: 'low' | 'normal' | 'high'
    metadata?: Record<string, any>
  }
): Promise<Message>
```

**Parameters**:
- `text` (string, required): Message content to send
- `options` (object, optional): Additional options
  - `channel` (string): Target channel ID. Defaults to current channel
  - `priority` ('low' | 'normal' | 'high'): Message priority. Defaults to 'normal'
  - `metadata` (object): Custom metadata to attach to message

**Returns**: Promise that resolves to Message object

**Example**:
```javascript
const message = await sendMessage('Hello world', {
  channel: 'general',
  priority: 'high',
  metadata: { userId: '123' }
})

console.log('Message sent:', message.id)
```

**Errors**:
- `InvalidChannelError`: Channel does not exist
- `RateLimitError`: Too many messages sent
- `NetworkError`: Connection failed
```

## Bad Example 8: Inconsistent Formatting

### Problem: Mixed Format Styles

```markdown
# Troubleshooting Guide

## Problem 1

Error message: FileNotFoundError

Solution: check the file path

## Problem Two

**Error**: Permission denied

*Solution*: Fix the permissions

## Third problem

ERROR MESSAGE: Connection refused

SOLUTION
-------
Check if the server is running
```

**Problems**:
- ❌ Inconsistent heading style
- ❌ Mixed formatting (bold, italic, all caps)
- ❌ Different section structure
- ❌ Hard to scan

**Fixed version**: Consistent formatting:

```markdown
# Troubleshooting Guide

## Problem: FileNotFoundError

**Error message**:
```
FileNotFoundError: [Errno 2] No such file or directory: 'file.pdf'
```

**Cause**: Incorrect file path or file doesn't exist

**Solution**:
1. Verify file path is correct
2. Check file exists: `ls -la file.pdf`
3. Use absolute path if needed

## Problem: Permission Denied

**Error message**:
```
PermissionError: [Errno 13] Permission denied: 'file.pdf'
```

**Cause**: Insufficient permissions to access file

**Solution**:
1. Check file permissions: `ls -la file.pdf`
2. Grant read permission: `chmod +r file.pdf`
3. Or run with appropriate permissions

## Problem: Connection Refused

**Error message**:
```
ConnectionRefusedError: [Errno 111] Connection refused
```

**Cause**: Server is not running or not reachable

**Solution**:
1. Verify server is running: `ps aux | grep server`
2. Check server port: `netstat -an | grep PORT`
3. Verify firewall settings
```

## Bad Example 9: No Cross-References

### Problem: Isolated Information

```markdown
# forms-guide.md

Information about form filling...

[No links to related content]

---

# api-reference.md

Information about form-related APIs...

[No links to forms-guide.md]

---

# troubleshooting.md

Form filling errors...

[No links to forms-guide.md or api-reference.md]
```

**Problems**:
- ❌ Related content not linked
- ❌ User must search manually
- ❌ Miss relevant information
- ❌ Duplicated explanations

**Fixed version**: Cross-reference related content:

```markdown
# forms-guide.md

Information about form filling...

**See also**:
- [API Reference](api-reference.md) - Form-related API methods
- [Troubleshooting](troubleshooting.md) - Common form filling errors
- [Examples](../examples/fill-form-good.py) - Working code example

---

# api-reference.md

## Form Methods

For complete form filling workflow, see [forms-guide.md](forms-guide.md)

**Methods**:
- `analyzeForm()` - Extract form fields
- `fillForm()` - Populate form fields

**Examples**: See [examples/fill-form-good.py](../examples/fill-form-good.py)

---

# troubleshooting.md

## Form Filling Errors

For form filling workflow, see [forms-guide.md](forms-guide.md)
For API documentation, see [api-reference.md](api-reference.md)

**Common errors**...
```

## Bad Example 10: Platform-Specific Without Labels

### Problem: Mixed Platform Examples

```markdown
# Database Connection Guide

## Connecting to Database

```python
import psycopg2
conn = psycopg2.connect("dbname=test user=postgres")
```

```javascript
const { Client } = require('pg')
const client = new Client({ database: 'test', user: 'postgres' })
```

```go
db, err := sql.Open("postgres", "dbname=test user=postgres")
```

[No indication which language each example is]
```

**Problems**:
- ❌ No platform labels
- ❌ Mixed without clear separation
- ❌ Hard to find relevant example
- ❌ Unclear which to use

**Fixed version**: Clear platform labels:

```markdown
# Database Connection Guide

## Connecting to Database

### Python

```python
import psycopg2

conn = psycopg2.connect(
    dbname="test",
    user="postgres",
    password="<REDACTED>",
    host="localhost"
)
```

### JavaScript/Node.js

```javascript
const { Client } = require('pg')

const client = new Client({
  database: 'test',
  user: 'postgres',
  password: '<REDACTED>',
  host: 'localhost'
})

await client.connect()
```

### Go

```go
import "database/sql"
import _ "github.com/lib/pq"

db, err := sql.Open("postgres",
    "dbname=test user=postgres password=<REDACTED> host=localhost")
if err != nil {
    log.Fatal(err)
}
```
```

## Reference Organization Anti-Patterns Summary

### Naming Issues
- ❌ Vague file names (doc1.md, stuff.md)
- ❌ Generic names (guide.md, reference.md)
- ❌ Numbered files (file1.md, file2.md)

### Structure Issues
- ❌ No table of contents for long files
- ❌ Wall of text without headings
- ❌ Inconsistent formatting
- ❌ Mixed platform examples without labels

### Content Issues
- ❌ No code examples
- ❌ No error handling examples
- ❌ Missing parameter documentation
- ❌ No timestamps

### Navigation Issues
- ❌ No cross-references to related content
- ❌ Isolated information
- ❌ Hard to find specific topics

## Quick Fix Checklist

Before finalizing reference files:
- [ ] Descriptive file names
- [ ] Table of contents for files >100 lines
- [ ] Code examples for every concept
- [ ] Error handling examples included
- [ ] Complete parameter documentation
- [ ] Timestamps on all files
- [ ] Structured with clear headings
- [ ] Consistent formatting throughout
- [ ] Cross-references to related content
- [ ] Platform-specific examples labeled

## See Also

- [reference-organization-good.md](reference-organization-good.md) - Effective organization patterns
- [../SKILL.md](../SKILL.md) - Full Skill authoring guidance
- [../reference/skill-structure-guide.md](../reference/skill-structure-guide.md) - Structure details
