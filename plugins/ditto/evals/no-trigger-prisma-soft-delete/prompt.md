---
description: A soft-delete request for a Prisma model on PostgreSQL must not invoke the Ditto skills, although it names an isDeleted flag.
tags: [negative]
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
---

I'm using Prisma with PostgreSQL. Add soft delete to this model with an `isDeleted` flag and a `deletedAt` timestamp, and show me how to exclude deleted posts in `findMany`. Just the schema change and the query.

```prisma
model Post {
  id        String   @id @default(uuid())
  title     String
  body      String
  createdAt DateTime @default(now())
}
```
