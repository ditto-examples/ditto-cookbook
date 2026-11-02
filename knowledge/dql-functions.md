# DQL Functions and Operators

This page summarizes the functions in the [DQL operators and expressions](https://docs.ditto.live/dql/operator-expressions) reference and how they behave in practice. Two rules apply to all of them:

- **Wrong argument types give MISSING, not an error.** `concat('a', 1)`, `'a' || 1`, `lower(1)`, a date string without a time zone, or swapped arguments to `date_add` all evaluate to MISSING silently. In a projection the alias disappears from the row; in `WHERE` the row is excluded. Test new expressions against real data.
- **Functions applied to a field usually prevent index use.** Compare the stored field directly where possible. See [Index Usage Rules](../best-practices/indexing-and-performance.md#index-usage-rules).

## Date and Time

Date functions accept either **ISO-8601 strings with a time zone** (`2026-03-15T10:30:45.123Z` or `...+09:00`) or **epoch milliseconds** (integers). `date_add`, `date_sub`, `date_trunc`, and `date_range` return strings for string input and epoch milliseconds for numeric input.

> **Note:** An ISO-8601 string **without** a zone designator, such as the output of Dart's `DateTime.now().toIso8601String()` for a local time, is not accepted by date functions unless you pass an explicit format to `date_cast`: the result is MISSING. Store timestamps in UTC, where `DateTime.now().toUtc().toIso8601String()` ends in `Z` (use the `utcTimestamp()` helper from [Timestamps](../best-practices/data-modeling.md#timestamps) for values that are sorted or compared), or as `millisecondsSinceEpoch`. <!-- lint-ignore -->

| Function | Description | Example → result |
|---|---|---|
| `clock([format[, tz]])` | Current time on **this device**: epoch ms, or a string when a format is given (`''` = ISO-8601) | `clock()` → `1791454108090`; `clock('')` → `'2026-10-08T10:08:28.090+00:00'` |
| `date_add(date, part, count[, format[, tz]])` | Add `count` parts (negative to subtract) | `date_add('2026-03-15T10:30:45.123Z', 'day', 7)` → `'2026-03-22T10:30:45.123+00:00'` |
| `date_sub(date, part, count[, format[, tz]])` | Subtract `count` parts | `date_sub('2026-03-15T10:30:45.123Z', 'hour', 2)` → `'2026-03-15T08:30:45.123+00:00'` |
| `date_diff(date1, date2, part)` | Whole `part`s from `date2` to `date1` (`date1 - date2`) | `date_diff('2026-03-20T00:00:00Z', '2026-03-15T10:30:45Z', 'day')` → `4` |
| `date_part(date, part)` | One component | `date_part('2026-03-15T10:30:45Z', 'weekday')` → `7` (Sunday) |
| `date_trunc(date, part)` | Truncate to `part` | `date_trunc('2026-03-15T10:30:45Z', 'day')` → `'2026-03-15T00:00:00+00:00'` |
| `date_format(date, format[, tz])` | Format, optionally converting to a time zone | `date_format('2026-03-15T10:30:45Z', 'YYYY-MM-DD hh:mm', 'Asia/Tokyo')` → `'2026-03-15 19:30'` |
| `date_cast(string[, format])` | Parse to epoch ms; date-only strings need a format | `date_cast('15/03/2026', '%d/%m/%Y')` → `1773532800000` |
| `date_range(start, end, part, count[, format[, tz]])` | Array of dates from `start` (inclusive) to `end` (exclusive) | `date_range('2026-03-01T00:00:00Z', '2026-03-04T00:00:00Z', 'day', 1)` → 3 dates |
| `tz_offset(string[, format])` | The time zone offset **in minutes** of a date string, or of a zone name when the format `'TZN'` is passed (it does not convert dates) | `tz_offset('2026-03-15T10:30:45+09:00')` → `540`; `tz_offset('Asia/Tokyo', 'TZN')` → `540`. With `'TZN'`, the result is the offset in force on **1970-01-01**, not today's: `tz_offset('America/New_York', 'TZN')` → `-300` even during daylight saving time, and `tz_offset('Asia/Kathmandu', 'TZN')` → `330` (the current offset is +345) |

**Parts** for `date_add`, `date_sub`, `date_diff`, and `date_trunc`: `year`, `mon`/`month`, `day`, `hour`, `min`/`minute`, `sec`/`second`, `ms`/`millis`/`millisecond`. `date_part` additionally accepts `weekday` (ISO-8601: Monday = 1, Sunday = 7), `monthname`, and `tz`/`timezone`. Other part names (`week`, `quarter`, `dow`, `doy`) return MISSING.

**Formats** use either SQL-like sequences (`YYYY-MM-DD hh:mm:ss.sss TZD`) or `%`-style specifiers (`%Y-%m-%d`); an empty string means ISO-8601.

**✅ DO:**
- Keep the argument order `date_add(date, part, count)`. Swapped arguments return MISSING without an error.
- Compare stored timestamps against parameters of the same type: ISO strings against ISO strings in the same format and precision (produce both with one helper, see [Timestamps](../best-practices/data-modeling.md#timestamps)), epoch ms against numbers.
- Compute time windows such as "last 7 days" in Dart and pass the boundary as a parameter. The comparison stays index-friendly and does not depend on `clock()`.

**❌ DON'T:**
- Compare an ISO string field with `clock()` (a number); values of different types are never equal or ordered against each other.
- Mix ISO strings with different fractional precision in one field. String comparison then does not match chronological order (`'...45Z' < '...45.123Z'` is false). Dart's `toIso8601String()` alone produces such mixed values on native platforms (see [Timestamps](../best-practices/data-modeling.md#timestamps) for why); produce compared values with the fixed-precision helper `utcTimestamp()` from that section. <!-- lint-ignore -->
- Expect `clock()` to give a trusted time: it is the clock of the device running the query.
- Use `clock()` in subscriptions. **Note (SDK 5.1.0 and 5.2.0):** each device that sends documents evaluates the condition with its own clock, and only when a document is written and when a new subscription arrives. In our testing, a device whose clock was ahead did not send documents inside the window, and a document that entered the window as time passed was not sent after 30 seconds, after a reconnect, or after the receiving app restarted and registered the same subscription; it arrived only when it was written again or when the receiver registered a subscription with a different text or arguments. Pass a boundary computed on the receiving device as a parameter, and move it rarely (see [Subscription Lifecycle](../best-practices/sync-and-subscriptions.md#subscription-lifecycle)).
- Expect an observer with `clock()` in its query to update as time passes. In our testing with SDK 5.1.0 and 5.2.0, a document that left a one-minute window stayed in the observer's result until something else was written to the same collection. For "last N minutes" views, filter by time in your code or query again on a timer.

```dart
// ✅ GOOD: Boundary computed in Dart and formatted with the same fixed-precision
// helper that writes createdAt (utcTimestamp() from the Timestamps section)
Future<List<Map<String, dynamic>>> recentOrders(Ditto ditto) async {
  final since = DateTime.now().toUtc().subtract(const Duration(days: 7));
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE createdAt >= :since ORDER BY createdAt DESC',
    arguments: {'since': utcTimestamp(since)},
  );
  return result.items.map((item) => item.value).toList();
}

// ✅ GOOD: Daily totals since a boundary. Format since with utcTimestamp(), as in
// recentOrders. GROUP BY repeats the date_format() expression.
Future<List<Map<String, dynamic>>> dailyRevenue(Ditto ditto, String since) async {
  final result = await ditto.store.execute(
    "SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue "
    'FROM orders WHERE createdAt >= :since '
    "GROUP BY date_format(createdAt, 'YYYY-MM-DD') "
    'ORDER BY day',
    arguments: {'since': since},
  );
  return result.items.map((item) => item.value).toList();
}
```

```sql
-- ❌ BAD: Arguments in the wrong order return MISSING without an error
SELECT date_add(createdAt, 7, 'day') AS dueAt FROM orders

-- ✅ GOOD
SELECT date_add(createdAt, 'day', 7) AS dueAt FROM orders
```

Durations are handled by `duration_cast(str[, unit])` (`duration_cast('1h30m')` → `5400000` ms) and `duration_format(value[, unit])` (`duration_format(5400000)` → `'1h30m0s'`).

## Conditional Functions

| Function | Returns | Example → result |
|---|---|---|
| `coalesce(v1, v2, ...)` | First value that is neither `null` nor missing (same as `ifmissingornull`) | `coalesce(nickname, name, 'Guest')` |
| `nvl(v, r)` | `v` if it is not `null`, otherwise `r` (a missing `v` is also replaced) | `nvl(discount, 0)` |
| `nvl(v, r1, r2)` | `r1` if `v` is not `null`, otherwise `r2` | `nvl(paidAt, 'paid', 'unpaid')` |
| `ifmissing(v, ...)` / `ifnull(v, ...)` | `ifmissing` returns the first value that is not missing, which can be `null` (`ifmissing(null, 0)` is `null`). `ifnull` returns the first value that is not `null`, but returns MISSING when it reaches a missing value first (`ifnull(missingField, 0)` is MISSING). `coalesce` skips both | `ifmissing(SUM(total), 0)` |
| `ismissing(v)` / `isnull(v)` / `ismissingornull(v)` | Boolean tests | `ismissingornull(email)` |
| `nullif(v1, v2)` / `missingif(v1, v2)` | `null` / MISSING when `v1 = v2`, otherwise `v1` | `nullif(status, '')` |
| `decode(input, c1, r1, [c2, r2, ...] [, default])` | `r` of the first `c` matching `input` without type conversion (a string never matches a number; integers and floats compare numerically); `default` (or `null`) otherwise | `decode(level, 1, 'low', 2, 'high', 'other')` |
| `CASE WHEN cond THEN r ... [ELSE d] END` | Result of the first true condition; `null` without `ELSE` | see below |
| `CASE expr WHEN v THEN r ... [ELSE d] END` | Result of the first matching value; `null` without `ELSE` | see below |

```sql
SELECT _id,
  coalesce(nickname, name, 'Guest') AS displayName,
  CASE
    WHEN total >= 1000 THEN 'large'
    WHEN total >= 100 THEN 'medium'
    ELSE 'small'
  END AS sizeClass,
  CASE status WHEN 'open' THEN 1 WHEN 'packed' THEN 2 ELSE 3 END AS statusRank
FROM orders
ORDER BY statusRank, _id
```

**✅ DO:**
- Use `coalesce` for defaults; it handles both `null` and missing fields.
- Always add `ELSE` to `CASE` when `null` is not an acceptable result.
- Remember that `decode` compares types: `decode('2', 1, 'one', 2, 'two', 'other')` returns `'other'` because `'2'` is a string.

## Type Checking

| Function | Returns |
|---|---|
| `type(x)` | `'boolean'`, `'string'`, `'integer'`, `'float'`, `'object'`, `'array'`, `'binary'`, `'null'`, `'missing'` |
| `json_type(x)` | `'boolean'`, `'string'`, `'number'`, `'object'`, `'array'`, `'binary'`, `'null'` (also `'null'` for missing) |
| `is_number(x)` / `is_string(x)` / `is_boolean(x)` | `true` or `false` for non-null values; `null` for `null` and MISSING for a missing `x` |

**✅ DO:**
- Use `is_number(x)` or `json_type(x) = 'number'` to accept both integers and floats.
- Use `type(x) = 'missing'` or `x IS MISSING` to find absent fields; `json_type` reports them as `'null'`.

**❌ DON'T:**
- Compare `type(x)` with `'number'`. `type()` never returns `'number'`, so `type(x) = 'number'` matches nothing and `type(x) != 'number'` matches everything.

```sql
-- Find documents whose price was stored with the wrong type
SELECT _id, price, type(price) AS storedAs
FROM products
WHERE price IS NOT MISSING AND NOT is_number(price)
```

Numbers keep their integer or float type: `type(1)` is `'integer'`, `type(1.5)` is `'float'`, and arithmetic between integers stays integer (`5 / 2` is `2`). Integers and floats compare as equal in `WHERE`, but `GROUP BY` and `DISTINCT` treat them as different values: in our testing with SDK 5.1.0 and 5.2.0, a field holding `1` and `1.0` formed two groups, which look identical in JavaScript and in Dart's `jsonDecode` output. Store such values in one type (amounts in integer minor units), or group by `cast(n AS float)`. Cast when you need a different type: `cast(x AS float)`, `cast(x AS string)`, `cast(x AS integer)`. A cast that cannot convert returns MISSING.

## String Functions

| Function / operator | Description | Example → result |
|---|---|---|
| `a \|\| b`, `concat(a, b, ...)` | Concatenation (strings only; other types give MISSING, and `null` gives `null`) | `'n' \|\| cast(1 AS string)` → `'n1'`; `'a' \|\| null` → `null` |
| `starts_with(s, prefix)` / `ends_with(s, suffix)` | Prefix / suffix test | `ends_with(email, '@example.com')` |
| `contains(s, sub)` | Substring test | `contains(title, 'urgent')` |
| `s LIKE pattern` / `s ILIKE pattern` | `%` matches any sequence, `_` one character; `LIKE` is case-sensitive, `ILIKE` ignores case | `sku LIKE 'AB-%'` |
| `s SIMILAR TO pattern` | `LIKE` wildcards plus `\|` alternatives, `[chars]` lists, grouping, and the repetition operators `*`, `+`, `?`, `{n}` | `code SIMILAR TO '(A\|B)%'` |
| `regexp_like(s, pattern[, flags])` | Regular expression match; `'i'` for case-insensitive | `regexp_like(code, '^[a-z]-[0-9]{3}$', 'i')` |
| `char_length(s)` / `character_length(s)` | Number of Unicode code points, which is neither the UTF-16 length that Dart and JavaScript report nor the number of characters a user sees | `char_length('café')` → `4`, `char_length('👍')` → `1` |
| `byte_length(s)` | Number of UTF-8 bytes | `byte_length('café')` → `5` |
| `lower(s)` / `upper(s)` | Case conversion; the length can change | `lower(email) = :email`, `upper('straße')` → `'STRASSE'` |
| `substr(s, start[, len])` | Substring; `start` is zero-based and counts code points | `substr('abcdef', 1, 3)` → `'bcd'` |
| `pos(s, sub)` / `POSITION(sub IN s)` | Zero-based index, `-1` if not found | `pos('abc', 'c')` → `2` |
| `split(s, delim)` / `joinstr(sep, values...)` | Split into an array / join with a separator (separator first) | `joinstr(', ', tags)` |
| `ltrim`, `rtrim`, `` `trim` ``, `TRIM(BOTH x FROM s)`, `lpad`, `rpad`, `repeat` | Trimming and padding (call `trim` with backticks) | `lpad(code, 6, '0')` |

**✅ DO:**
- Use `LIKE 'prefix%'` for prefix searches. It is the form that can use an index; see [Index Usage Rules](../best-practices/indexing-and-performance.md#index-usage-rules).
- Use `byte_length` (not `char_length`) when checking against byte-based limits.
- Escape `%` or `_` in `LIKE` with an `ESCAPE` character such as `'!'`: `discount LIKE '50!%' ESCAPE '!'`. A backslash works too, but must be written `'\\'` because backslashes are escape characters in DQL strings.
- Normalize case when writing (for example store `emailLower`) instead of calling `lower()` on the field in every query.

**❌ DON'T:**
- Concatenate numbers without `cast(... AS string)`.
- Store strings cut in the middle of a character. **Note (SDK 5.1.0 and 5.2.0):** in the JavaScript SDK, a string with an unpaired surrogate, such as one cut in the middle of an emoji with `slice`, is stored as a different character without an error. In our testing, `'hello👍'.slice(0, 6)` was stored as `'hello🐀'`, and in `'a\ud800b'` the unpaired surrogate swallowed the `b`. Document IDs and query arguments change the same way. Cut strings at code point or grapheme boundaries (`Array.from(s)`, `Intl.Segmenter`), or check `s.isWellFormed()` before you write.
- Use `SIMILAR TO` like a full regular expression: `.` matches only a literal dot there (`'abc' SIMILAR TO 'a.c'` is `false`), and the pattern must match the whole string. Use `regexp_like` for full regular expressions.

```dart
// ✅ GOOD: Prefix search with a parameter
// If prefix comes from user input, escape % and _ first (see below).
Future<List<Map<String, dynamic>>> productsBySkuPrefix(Ditto ditto, String prefix) async {
  final result = await ditto.store.execute(
    'SELECT _id, sku, name FROM products WHERE sku LIKE :pattern ORDER BY sku LIMIT 20',
    arguments: {'pattern': '$prefix%'},
  );
  return result.items.map((item) => item.value).toList();
}
```

If user input can contain `%` or `_`, escape them before building the pattern, or use `starts_with(sku, :prefix)`, which treats the prefix literally but cannot use an index.

## Object Functions

| Function | Returns | Example → result |
|---|---|---|
| `object_keys(o)` / `object_values(o)` | Top-level keys / values as an array | `object_keys({'a': 1, 'b': 2})` → `['a', 'b']` |
| `object_length(o)` | Number of top-level keys (`0` for `{}`) | `object_length(items) = 0` finds empty maps |
| `object_set(o, key, value[, replace])` | Copy with a key added; pass `true` to overwrite an existing key (without it, an existing key gives MISSING) | `object_set(o, 'b', 2)` |
| `object_unset(o, key[, ignoreMissing])` | Copy without a key; pass `true` to ignore a key that does not exist (without it, the result is MISSING) | `object_unset(o, 'b')` |
| `object_concat(o1, o2, ...)` | Shallow merge; the last object wins | `object_concat({'a': 1}, {'a': 3, 'b': 2})` → `{'a': 3, 'b': 2}` |
| `object_rename(o, old, new)` | Copy with a key renamed | `object_rename(o, 'a', 'z')` |
| `object_size(o)` (SDK 5.1+) | Approximate size in bytes, for comparisons | `object_size(orders) > 200000` |

These functions shape query **results**; they do not modify stored documents. Use `UPDATE ... SET` / `UNSET` to change data.

```sql
-- Documents whose items map is empty, and documents that are getting large
SELECT _id, object_length(items) AS itemCount, object_size(orders) AS approxBytes
FROM orders
WHERE object_length(items) = 0 OR object_size(orders) > 200000
```

Passing the collection name or alias to `object_size` (as in `object_size(orders)` above) measures the whole document and helps you find documents approaching the size limits described in [Document Size Limits](../best-practices/data-modeling.md#document-size-limits) (soft limit 256 KiB). An empty object `{}` is not `null`: test it with `object_length(o) = 0`, not `IS NULL`.

## Arrays and Collection Operators

| Operator / function | Description | Example → result |
|---|---|---|
| `x IN :values` / `x IN (a, b, ...)` | Membership in a parameter array or a literal list | `status IN :statuses` |
| `x NOT IN :values` | Non-membership; missing `x` never matches | `status NOT IN ('archived')` |
| `v IN arrayField` | Array field contains `v` | `:tag IN tags` |
| `array_contains(array, v)` | Same test as a function | `array_contains(tags, 'red')` |
| `array_contains_null(array)` | Array contains a `null` element | `array_contains_null(scores)` |
| `array_length(array)` | Number of elements | `array_length(tags) > 0` |
| `x BETWEEN low AND high` | `x >= low AND x <= high` (inclusive) | `10 BETWEEN 1 AND 10` → `true` |
| `x NOT BETWEEN low AND high` | Outside the inclusive range | `5 NOT BETWEEN 1 AND 3` → `true` |

**✅ DO:**
- Write `BETWEEN` bounds in ascending order. `x BETWEEN 10 AND 1` is always false; the bounds are not swapped for you.
- Use `IN :values` with an array parameter for "one of" filters.

**❌ DON'T:**
- Expect an index to speed up element lookups such as `:tag IN tags` or `array_contains(tags, :tag)`. An index on an array field only matches the whole array value.

```dart
// ✅ GOOD: Inclusive range with parameters
Future<List<Map<String, dynamic>>> ordersInPriceRange(
  Ditto ditto,
  num min,
  num max,
) async {
  final result = await ditto.store.execute(
    'SELECT _id, total FROM orders WHERE total BETWEEN :min AND :max ORDER BY total',
    arguments: {'min': min, 'max': max},
  );
  return result.items.map((item) => item.value).toList();
}
```

## ANY and EVERY

`ANY` and `EVERY` test the elements of an array (or the values of an object):

```text
ANY [index:]value IN|WITHIN source SATISFIES condition END
EVERY [index:]value IN|WITHIN source SATISFIES condition END
ANY AND EVERY [index:]value IN|WITHIN source SATISFIES condition END
```

`IN` looks at direct elements; `WITHIN` searches nested arrays and objects recursively. `EVERY` is `true` for an empty array, `ANY AND EVERY` is `false` for an empty array.

Use them in projections to compute flags over embedded arrays:

```sql
SELECT _id,
  ANY line IN lines SATISFIES line.quantity = 0 END AS hasEmptyLine,
  EVERY line IN lines SATISFIES line.picked = true END AS fullyPicked
FROM orders
WHERE status = 'open'
```

> **Note (SDK 5.1.0 and 5.2.0):** Do not use `ANY` or `EVERY` over a parameter or literal array in a `WHERE` clause, such as `WHERE ANY s IN :statuses SATISFIES s = status END`: it returns no rows. Use `status IN :statuses` instead. `ANY` and `EVERY` over a document's own array field work in `WHERE` (on SDK 5.1.0, only when the condition checks a single property; see [Known Issues in SDK 5.1.0](upgrading.md#known-issues-in-sdk-510)); for a plain element test, `:value IN arrayField` or `array_contains(arrayField, :value)` is the simpler choice. This affects only local queries and observers: a subscription with the same predicate syncs correctly, so the data arrives but an observer with the same statement stays empty. SDK 5.0.x is not affected. <!-- lint-ignore -->

## ARRAY and OBJECT Transformations

Build new arrays or objects from an array or object in the result:

```text
ARRAY valueExpr FOR [index:]value IN|WITHIN source [WHEN condition] END
OBJECT nameExpr : valueExpr FOR [name:]value IN|WITHIN source [WHEN condition] END
```

```sql
SELECT _id,
  ARRAY line.sku FOR line IN lines WHEN line.quantity > 0 END AS skusToPick,
  OBJECT line.sku : line.quantity FOR line IN lines END AS quantityBySku,
  ARRAY price * 1.1 FOR price IN unitPrices END AS grossPrices
FROM orders
WHERE _id = :id
```

- Elements whose `valueExpr` evaluates to MISSING are skipped.
- In `OBJECT`, `nameExpr` must be a string; when two elements produce the same name, the later one wins.
- A missing `source` yields MISSING; a `source` that is neither an array nor an object yields `null`.

Use transformations to shape data for the UI in the query instead of post-processing in Dart, particularly in observers where the work repeats on every change.

## Arithmetic, Conversion, and Other Functions

| Function / operator | Description | Example → result |
|---|---|---|
| `+ - * / %` | Arithmetic; integer operands give integer results, and division or modulo by zero gives MISSING | `7 % 3` → `1`; `5 / 2` → `2` |
| `abs(x)`, `ceil(x)`, `floor(x)` | Absolute value, round up, round down | `ceil(1.2)` → `2.0` (a float) |
| `cast(v AS type)` / `cast(v, 'type')` | Convert to `string`, `integer`, `float`, `boolean`, or `binary`; MISSING if not possible | `cast('42' AS integer)` → `42` |
| `serialize_json(v)` (SDK 5.1+) | JSON text of a value | `serialize_json({'a': [1]})` → `'{"a":[1]}'` |
| `deserialize_json(s)` | Parse JSON text (also usable in `INSERT` and `UPDATE`) | `deserialize_json(:json)` |
| `request_info()` | Metadata about the running request (`app_id`, `request_id`, `start_time`) | `SELECT request_info() FROM system:dual` |

`deserialize_json` lets you insert a JSON payload received from a backend without decoding it in Dart first. In app code, pass the text as a parameter, `DOCUMENTS (deserialize_json(:json))`; with a literal it looks like this:

```sql
INSERT INTO products
DOCUMENTS (deserialize_json('{"_id": "p1", "name": "Pen", "price": 2}'))
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

`system:dual` is a built-in collection with a single document. Use it to try out expressions: `SELECT date_add(:now, 'day', 1) AS tomorrow FROM system:dual`.
