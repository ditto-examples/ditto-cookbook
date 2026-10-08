# Data Modeling Common Patterns

Frequently needed patterns that complement [SKILL.md](../SKILL.md). Targets Ditto SDK 5.1.0 with the default `DQL_STRICT_MODE = false`. The source of truth is the [Data Modeling](../../../../guides/best-practices/ditto.md#data-modeling) section of the guide.

## Table of Contents

- [Pattern 1: Field-Level Updates and Upserts](#pattern-1-field-level-updates-and-upserts)
- [Pattern 2: Event History and Audit Logs](#pattern-2-event-history-and-audit-logs)
- [Pattern 3: Document Structure](#pattern-3-document-structure)
- [Pattern 4: Keeping Documents Small](#pattern-4-keeping-documents-small)

---

## Pattern 1: Field-Level Updates and Upserts

Write only what changed. A field-level `UPDATE` touches only the named fields, so concurrent edits to other fields survive. When a user edits a document, update only the fields the user changed.

| Conflict policy | When the `_id` exists locally |
|---|---|
| `FAIL` (default) | The statement fails |
| `DO NOTHING` | Existing document unchanged; use for "create if absent" |
| `DO UPDATE` | Supplied fields are written and merged, **even identical values**: the document is reported as mutated and observers can fire again |
| `DO UPDATE_LOCAL_DIFF` | Same merge, but only differing fields are written; nothing is written when nothing changed. Use it for upserts and re-imports; it does not protect a stale in-memory copy |

No `INSERT` policy deletes fields: use `UNSET`.

```dart
// ✅ GOOD: Only status changes.
Future<void> markReady(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET status = :status, updatedAt = :updatedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      'status': 'ready',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

// ✅ GOOD: Re-importing reference data that your backend owns. Fields whose
// values equal the local document are skipped, and an unchanged document is
// not written at all.
Future<bool> importProduct(Ditto ditto, Map<String, dynamic> product) async {
  final result = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'product': product},
  );
  return result.mutatedDocumentIDs().isNotEmpty;
}
```

**❌ DON'T:**
- Save a stale in-memory copy with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF`. `DO UPDATE` gives every supplied field a new timestamp; `DO UPDATE_LOCAL_DIFF` writes back any old value that differs from the stored one. Both can override a concurrent change from another device.
- Use `DO UPDATE` for periodic re-upserts of unchanged data (for example, refreshing reference data from a backend).
- Expect `DO UPDATE` to replace a document or an object: it merges.

Guide: [INSERT and Conflict Handling](../../../../guides/best-practices/ditto.md#insert-and-conflict-handling), [Local write semantics you must know](../../../../guides/best-practices/ditto.md#local-write-semantics-you-must-know). Example: [field-level-updates.dart](../examples/field-level-updates.dart).

---

## Pattern 2: Event History and Audit Logs

When every change matters, record each change as a new fact instead of overwriting one field.

| | Audit-log map | Event documents | Current state + history |
|---|---|---|---|
| Shape | `statusLog: {"<UTC ms timestamp>": "shipped"}` in the record | One document per event, UUID `_id` | Bounded current-state document plus append-only history collection |
| Size | Grows the parent | Parent unaffected | Current state bounded; history grows |
| Atomic with the parent | Yes (one document) | Only with a transaction | Only with a transaction |
| Readable without the parent | No | Yes | Yes |
| Best for | Status and workflow history of one record | Unbounded logs, analytics, compliance trails | Live dashboards plus history |

**✅ DO:**
- Key audit-log entries by millisecond-precision ISO-8601 UTC timestamps, and append them with a partial-document upsert (`ON ID CONFLICT DO UPDATE_LOCAL_DIFF`). Two entries recorded in the same millisecond on different devices share a key and only one is kept; if that matters, append a device identifier to the key (`2026-10-08T10:05:12.437Z_t3`).
- Derive the current state when reading: latest timestamp, **most advanced state** (progressions that must not regress), earliest occurrence, or custom rules.
- Plan cleanup of event collections from the start with `EVICT`, using a subscription scope that is the complement of the eviction query.

**❌ DON'T:**
- Append events to an array: arrays are registers, so concurrent appends lose events.
- Rely on one overwritten `status` field when history matters: a late write from an offline device can move the record backwards.

```sql
SELECT * FROM orderEvents
WHERE orderId = :orderId
ORDER BY occurredAt ASC, _id ASC
```

A variant uses the status as the key and the timestamp as the value; it records whether and when a state happened, but keeps only the latest time for a state entered more than once.

Guide: [Event History and Audit Logs](../../../../guides/best-practices/ditto.md#event-history-and-audit-logs), [EVICT](../../../../guides/best-practices/ditto.md#evict). Examples: [event-history.dart](../examples/event-history.dart), [two-collection-pattern.dart](../examples/two-collection-pattern.dart).

---

## Pattern 3: Document Structure

### Flat or Nested

- **Group related fields in an object** when they belong together but may be edited separately (`customer.name`, `customer.phone`). Each nested field merges independently, and nesting has no special performance cost.
- **Keep fields at the top level** when that reads better; nested paths such as `customer.phone` are indexable too.
- **Use a REGISTER object** only when the parts must never mix (for example, a GPS `position`), declared in every statement.
- **Avoid unbounded growth** inside one document: a map that keeps receiving entries belongs in its own collection.

### Exclude Transient and Unnecessary Fields

Every stored field costs storage and memory on every device that holds the document and adds to initial replication and merge cost.

**❌ DON'T store in synced documents:** UI state (`isExpanded`, scroll positions), temporary flags (`isSaving`, `uploadProgress`), device-local data (file paths, cache locations), or derived values (totals, averages, "days until").

**✅ DO:** keep UI and device-local state in widget state or local preferences, and initialize flags you will filter on (`isDeleted: false`), or filter with `coalesce(isDeleted, false) = false`. A missing field is `MISSING`, not `false`.

### Field Names

- Use one convention (camelCase in the guide).
- Quote field names that collide with DQL keywords or contain special characters with backticks (`` `value` ``).
- Never name a collection `collection`; it is a DQL keyword.

Guide: [Document Structure](../../../../guides/best-practices/ditto.md#document-structure), [MISSING and NULL](../../../../guides/best-practices/ditto.md#missing-and-null).

---

## Pattern 4: Keeping Documents Small

| Threshold | Default | System parameter | Behavior |
|---|---|---|---|
| Soft limit | 256 KiB (262,144 bytes) | `DOCUMENT_SIZE_SOFT_LIMIT_BYTES` | Write succeeds; a warning is logged |
| Hard limit | 5 MiB (5,242,880 bytes) | `DOCUMENT_SIZE_HARD_LIMIT_BYTES` | `INSERT` / `UPDATE` fails; the stored document is unchanged |

The limits apply to the size of each stored document. Size affects storage and memory on every device, merge cost (which scales with document size, not change size), and initial replication: over Bluetooth LE (roughly 20 KB/s in practice) a 256 KiB document takes more than 10 seconds to replicate the first time.

| Cause of growth | Fix |
|---|---|
| A nested map that keeps receiving entries | Move entries to their own collection with a parent reference (`orderId`) |
| Binary data in a field | Store it as an `ATTACHMENT` |
| One document holding data for many users or locations | Split by owner or location (often simplifies permissions too) |
| Status history | A bounded audit-log map, or an event collection (see [Event History and Audit Logs](#pattern-2-event-history-and-audit-logs)) |

Estimate the size of a value with `object_size()`; it is approximate and can differ from the stored size, so leave headroom. To bring an oversized document back under the limits, move large values to attachments or to a separate collection and remove them from the document with `UNSET`:

```sql
SELECT _id, object_size(o) AS approxBytes
FROM orders AS o
WHERE _id = :id
```

**❌ DON'T:** embed base64-encoded files, append to a nested map forever, or raise the hard limit to make a large document fit. If you change either limit, change it on every peer in the same release.

Guide: [Document Size Limits](../../../../guides/best-practices/ditto.md#document-size-limits), [Attachments](../../../../guides/best-practices/ditto.md#attachments). Example: [document-size.dart](../examples/document-size.dart).
