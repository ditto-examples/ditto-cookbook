# DQL Behavior

How DQL statements behaved when we ran them: which tables and statements of the guide held on SDK 5.2.0, what statements without `WHERE` and mismatched arguments do, how values of different types compare and sort, how integers, floats, and strings behave, how document IDs and field names are compared, what mixed type declarations do to queries and indexes, which limits and crashes we found, where SDK 5.0.3 differs, and what happens to JavaScript values that are not plain JSON. How the tests were run, and what they did not cover, is described in [How We Tested](how-we-tested.md). The rules that follow from these observations are in [Parameters and Literals](../best-practices/dql.md#parameters-and-literals), [MISSING and NULL](../best-practices/dql.md#missing-and-null), [ORDER BY](../best-practices/dql.md#order-by), [Filtering by Membership](../best-practices/dql.md#filtering-by-membership), [UPDATE](../best-practices/dql.md#update), [Document IDs](../best-practices/data-modeling.md#document-ids), [Keep type declarations consistent](../best-practices/data-modeling.md#keep-type-declarations-consistent), and [Known Issues in SDK 5.1.0](upgrading.md#known-issues-in-sdk-510).

**In brief**

- The DQL tables of the guide held on SDK 5.2.0 as on 5.1.0: MISSING and NULL, conflict policies, `UPDATE` errors, map writes, strict mode, subscription errors, joins, `RETURNING`, and document IDs ([The single-store DQL tables held on SDK 5.2.0](#the-single-store-dql-tables-held-on-sdk-520), [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.2.0](#join-returning-document-id-and-timestamp-statements-held-on-sdk-520)).
- Mistakes in a statement often give no error: `UPDATE`, `DELETE`, and `EVICT` without `WHERE` change every document, and a single value passed to `IN :ids` matches nothing ([Statements without WHERE change every document](#statements-without-where-change-every-document), [Wrong argument types fail silently](#wrong-argument-types-fail-silently)).
- A comparison between values of different types is MISSING, strings sort by code point, and `DESC` puts missing and `null` values first ([Comparisons across types are MISSING, and strings sort by code point](#comparisons-across-types-are-missing-and-strings-sort-by-code-point), [Descending order puts missing and null first](#descending-order-puts-missing-and-null-first)).
- Since SDK 5.1, rows with equal sort keys come back in ascending `_id` order, also with `DESC`; on 5.0.3, `LIMIT` then did not return the first rows. `OFFSET` pages repeat a row after an insert, and keyset pages do not ([Rows with equal sort keys come back in _id order since SDK 5.1](#rows-with-equal-sort-keys-come-back-in-_id-order-since-sdk-51), [OFFSET pages repeat rows after inserts, and keyset pages do not](#offset-pages-repeat-rows-after-inserts-and-keyset-pages-do-not)).
- The integer `1` and the float `1.0` are equal in `WHERE` but form two groups in `GROUP BY` ([Integers and floats are equal in WHERE but separate in GROUP BY](#integers-and-floats-are-equal-in-where-but-separate-in-group-by)).
- Document IDs and field names are compared by type and exact code points, without Unicode normalization, and a string ID can have at most 254 bytes ([Document IDs compare by type and exact value](#document-ids-compare-by-type-and-exact-value), [Field names can contain dots and backticks, or be empty](#field-names-can-contain-dots-and-backticks-or-be-empty)).
- On SDK 5.1.0, long `OR` chains ended the process, and on 5.1.0 and 5.2.0, `ANY` over a parameter array returns no rows ([Long OR chains crashed SDK 5.1.0, and nested parentheses fail at 100 levels](#long-or-chains-crashed-sdk-510-and-nested-parentheses-fail-at-100-levels), [ANY over a parameter array broke in 5.1.0, and the multi-property issue was 5.1.0 only](#any-over-a-parameter-array-broke-in-510-and-the-multi-property-issue-was-510-only)).
- In JavaScript, a `Date` is stored as `{}`, `undefined` as `null`, and unpaired surrogates as other characters, all without an error ([JavaScript values that are not plain JSON change when stored](#javascript-values-that-are-not-plain-json-change-when-stored), [char_length counts code points, and JavaScript damages lone surrogates](#char_length-counts-code-points-and-javascript-damages-lone-surrogates)).

## DQL tables and statements that held on SDK 5.2.0

### The single-store DQL tables held on SDK 5.2.0

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each (deterministic) |
| Setup | Eleven checks on one device without sync. Each ran the statements behind the tables and statements listed below and compared every result with them |

On 5.1.0 and 5.2.0, every row of the following tables and statements held:

| Section | What was checked |
|---|---|
| [MISSING and NULL](../best-practices/dql.md#missing-and-null) | The `WHERE` table (11 expressions), and the related behavior: MISSING in projections, comparisons between different types, the position of `null` and missing values in `ORDER BY`, and aggregates over zero documents |
| [Indexing soft-delete filters](../best-practices/deletion-and-storage.md#indexing-soft-delete-filters) | The four plans |
| [ON ID CONFLICT](../best-practices/dql.md#on-id-conflict) | The four policies; that an `INSERT` of several documents is atomic; the syntax errors of [INITIAL DOCUMENTS](../best-practices/dql.md#initial-documents) and of [INSERT ... SELECT (SDK 5.1+)](../best-practices/dql.md#insert--select-sdk-51) |
| [UPDATE](../best-practices/dql.md#update) | The errors for `SET _id`, the same path set twice, an array element, `items[:key]`, clauses in the wrong order, a `COUNTER` declared without `COLLECTION`, and a fractional increment; and that a `SET` to the current value is recorded as a mutation |
| [Local write semantics you must know](crdt-types.md#local-write-semantics-you-must-know) | The seven rows. In addition, `UNSET obj` followed by `SET obj = 5` gives `5` |
| [Keep type declarations consistent](../best-practices/data-modeling.md#keep-type-declarations-consistent) | Three rows: a `REGISTER` object followed by an undeclared nested `SET`, an undeclared number followed by `INCREMENT`, and `PN_INCREMENT` followed by `INCREMENT`. Also an `INSERT` that declares a `COUNTER` |
| [What strict mode changes](../best-practices/data-modeling.md#what-strict-mode-changes) | The table |
| [Subscription Rules](../best-practices/sync-and-subscriptions.md#subscription-rules) | The error messages (12 cases), and what `DQL_RESTRICT_SUBSCRIPTIONS = false` allows ([LIMIT and ORDER BY in subscriptions](../best-practices/sync-and-subscriptions.md#limit-and-order-by-in-subscriptions)) |
| [Default Data with INITIAL Documents](../best-practices/data-modeling.md#default-data-with-initial-documents) | The table of the behavior on a device |
| [Working with arrays](../best-practices/data-modeling.md#working-with-arrays) | `:tag IN tags`; `array_contains` does not use an index, while a path inside a map does |

On 5.0.3, only two things differed: `INSERT ... SELECT` (SDK 5.1+) does not exist, and two subscription errors have other messages (a `JOIN` is a syntax error, and `USE IDS` fails with `Unsupported feature: use ids`).

**Used in:** the sections in the table above.

### JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.2.0

| | |
|---|---|
| Observed on | Joins and `RETURNING`: SDK 5.1.0 and 5.2.0, one run each. Document ID values and the order of timestamp strings: SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | Checks on one device without sync that ran the statements of the sections linked below and compared the results with them |

The results were the same on every release tested, and they matched these sections:

- **Joins** ([Joining Collections (SDK 5.1+)](../best-practices/dql.md#joining-collections-sdk-51)):
  - Without an index, a join failed with `Joining to "o" disallowed without appropriate index support` ([Index requirement](../best-practices/dql.md#index-requirement)). A join on `_id` and a join with `USE INDEX ''` worked without an index.
  - `INNER`, `LEFT` (also with a filter inside `ON`), and `RIGHT` joins, and `WHERE o._id IS MISSING`, returned the rows in [Join types](../best-practices/dql.md#join-types).
  - `SELECT *` returned one nested object per alias, `c.*, o.total` a flat row, and `SELECT _id` a composite ID; a field `name` present on both sides failed with `Ambiguous reference to field` ([Result shape](../best-practices/dql.md#result-shape)).
  - `FULL OUTER`, `CROSS`, and comma joins, and joins in `UPDATE`, were rejected, and a `RIGHT JOIN` after the first join failed with `RIGHT OUTER join that isn't the first join is not supported` ([Restrictions](../best-practices/dql.md#restrictions)).
  - An observer of a join was called when either collection changed ([Joins in observers](../best-practices/dql.md#joins-in-observers)). Whether its rows include `_id` is described in [On SDK 5.2.0, observer rows include _id only when it is projected](transactions-and-observers.md#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected).
- **`RETURNING`** ([RETURNING (SDK 5.1+)](../best-practices/dql.md#returning-sdk-51)): documents skipped by `DO NOTHING` and documents that `DO UPDATE_LOCAL_DIFF` left unchanged were not returned. `UPDATE` returned the documents after the update, and `DELETE` the documents before they were deleted. `EVICT ... RETURNING COUNT(*)` returned the number of documents. `mutatedDocumentIDs` and `commitID` were populated as well.
- **Document IDs** ([Allowed values](../best-practices/data-modeling.md#allowed-values)): strings, objects, integers, booleans, and arrays were accepted; a float failed with `Floats are not supported in document IDs`, and `null` with `Null document ID not allowed`. Two composite IDs whose keys differ only in order identify the same document: inserting the second failed with `Identifier conflict`, and a lookup with the keys in the other order found the document. Without `_id`, Ditto generated a string ID. More ID comparisons are in [Document IDs compare by type and exact value](#document-ids-compare-by-type-and-exact-value).
- **Timestamps** ([Store UTC with a zone designator](../best-practices/data-modeling.md#store-utc-with-a-zone-designator)): `'2026-10-08T10:30:45Z' < '2026-10-08T10:30:45.123Z'` is `false`. `ORDER BY` on strings with a mixed number of fractional digits is not chronological: three documents with `'2026-10-08T10:30:45Z'`, `'2026-10-08T10:30:45.000500Z'`, and `'2026-10-08T10:30:45.123Z'` (in chronological order) came back as `...45.000500Z`, `...45.123Z`, `...45Z`. `date_part` of a string without a time zone is MISSING.

**Used in:** the sections linked above.

### USE IDS LIST, ADVISE output, and descending index keys held

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0 (`USE IDS LIST` also on 5.0.3), one run each. Each case had also been checked once before with a separate script |
| Setup | One device without sync. `DELETE FROM orders USE IDS LIST :ids` and `EVICT FROM orders USE IDS LIST ['c']`; `ADVISE` for the two example statements of [ADVISE (SDK 5.1+)](../best-practices/indexing-and-performance.md#advise-sdk-51) and for an ID lookup; an index on `(customerId, createdAt DESC)` with a query that filtered on `createdAt >= :since` and sorted with `ORDER BY createdAt DESC` |

- **`USE IDS LIST` in `DELETE` and `EVICT`**: 5.2.0 removed the documents and listed them in `mutatedDocumentIDs`. 5.1.0 removed nothing, and `mutatedDocumentIDs` was empty. On 5.0.3, `USE IDS` in a `DELETE` is a syntax error.
- **`ADVISE`**: 5.1.0 and 5.2.0 returned the same JSON as the two example outputs in [ADVISE (SDK 5.1+)](../best-practices/indexing-and-performance.md#advise-sdk-51). For an ID lookup, the result was `outcome: "no advice available for statement"`.
- **An index with a descending key and a range condition**: 5.1.0 returned the oldest documents first, and with `LIMIT 2` the two oldest. 5.2.0 returned the correct order. On both releases, the plan was `indexScan`, `filter`, `fetch`, with no `sort` step. The 5.1.0 issue in [Composite indexes and key order (SDK 5.1+)](../best-practices/indexing-and-performance.md#composite-indexes-and-key-order-sdk-51) therefore also applies when the second key has a range condition.

**Used in:** [USE IDS](../best-practices/dql.md#use-ids), [DELETE and EVICT](../best-practices/dql.md#delete-and-evict), [DELETE and Tombstones](../best-practices/deletion-and-storage.md#delete-and-tombstones), [ADVISE (SDK 5.1+)](../best-practices/indexing-and-performance.md#advise-sdk-51), [Composite indexes and key order (SDK 5.1+)](../best-practices/indexing-and-performance.md#composite-indexes-and-key-order-sdk-51), [Known Issues in SDK 5.1.0](upgrading.md#known-issues-in-sdk-510).

## Writes and query arguments

### Statements without WHERE change every document

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each (deterministic); the results were the same on all three releases |
| Setup | One device without sync. `UPDATE`, `DELETE`, and `EVICT` without `WHERE` on a collection; `SET a.b = 1` on documents in which `a` held a string, an array, `null`, a number, or an object |

- `UPDATE items SET n = 1`, `DELETE FROM items`, and `EVICT FROM items` without `WHERE` were accepted and changed every document in the collection. Nothing asked for confirmation or logged a warning.
- `SET a.b = 1` replaced `a` with `{"b": 1}` when `a` was a string, an array, `null`, or a number, without an error, and the old value was lost. When `a` was an object, `b` was added to it.

**Used in:** [UPDATE](../best-practices/dql.md#update), [DELETE and EVICT](../best-practices/dql.md#delete-and-evict).

### Wrong argument types fail silently

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each (deterministic); the results were the same on all three releases |
| Setup | One device without sync. Statements with `:name` placeholders, run with arguments that are missing, unused, misnamed, or of the wrong shape |

| Mistake | Result |
|---|---|
| A placeholder without an argument | `Parameter id was not provided` |
| An argument that the statement does not use | No effect |
| An argument name with the colon (`{':id': 'a'}`) | Fails as if the argument were missing |
| `$id` instead of `:id` | Syntax error |
| `IN :ids` with a single string instead of an array | No error, no rows |
| `= :ids` with an array | No rows |
| `IN :ids` with an empty array | No error, no rows |

- Both cases of the wrong shape (a single value for `IN`, an array for `=`) are easy to miss, because nothing reports them.
- `=` between an array field and an array argument compares the elements.

**Used in:** [Always pass values as parameters](../best-practices/dql.md#always-pass-values-as-parameters), [Filtering by Membership](../best-practices/dql.md#filtering-by-membership).

## Comparisons, sort order, and paging

### Comparisons across types are MISSING, and strings sort by code point

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each (the 32 keywords: 5.1.0 and 5.2.0); deterministic, and the same on every release tested |
| Setup | One device without sync. Expressions evaluated in queries; `ORDER BY` on a field that held values of several types; collection and field names that differ only in case; 32 DQL keywords used as bare collection names and field names |

| Expression | Result |
|---|---|
| `5 / 2` | `2` |
| `1 / 0`, `1 % 0` | MISSING, without an error |
| `1 = '1'` | MISSING, not `false` |
| `'a' \|\| null` | `null` |
| `'a' \|\| missing` | MISSING |
| `'B' < 'a'`, `'é' > 'z'`, `'10' < '9'` | `true`: strings compare by Unicode code point |

- `LIKE` is case-sensitive.
- `ORDER BY ... ASC` on a field with mixed types returned `false`, `true`, numbers (`2`, `10`), strings (`'10'`, `'B'`, `'b'`), arrays, objects, `null`, and missing values, in that order.
- Collection names and field names are case-sensitive: `Orders` and `orders` are different collections.
- Of the 32 keywords used as bare names, only `collection` as a collection name was a syntax error. `order`, `select`, `from`, `where`, `value`, `key`, `count`, and `all` (as a collection name), among others, were accepted. `null`, `true`, and `missing` are probably read as literals rather than as fields, which changes the meaning of a statement without an error.

**Not tested:** whether the statements with keyword names returned the intended results; the test checked only whether they were syntax errors.

**Used in:** [Literals](../best-practices/dql.md#literals), [Reserved words](../best-practices/dql.md#reserved-words), [MISSING and NULL](../best-practices/dql.md#missing-and-null), [ORDER BY](../best-practices/dql.md#order-by), [Field names](../best-practices/data-modeling.md#field-names), [String Functions](dql-functions.md#string-functions), [Arithmetic, Conversion, and Other Functions](dql-functions.md#arithmetic-conversion-and-other-functions).

### Descending order puts missing and null first

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each |
| Setup | One device without sync. Four documents whose field `v` was `2`, `1`, `null`, and missing |

| Order | Result |
|---|---|
| `ORDER BY v ASC` | `1`, `2`, `null`, missing |
| `ORDER BY v DESC` | missing, `null`, `2`, `1` |

`DESC` reverses the whole sequence, including `null` and missing values. A newest-first list (`ORDER BY createdAt DESC`) therefore shows documents without `createdAt` at the top.

**Used in:** [ORDER BY](../best-practices/dql.md#order-by), [MISSING and NULL](../best-practices/dql.md#missing-and-null).

### Rows with equal sort keys come back in _id order since SDK 5.1

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, three runs each; all nine runs gave the same result. The details of 5.0.3 with `DESC` and with an index, and the single `{}` row, come from a separate reproduction on one store with the documents inserted in reverse `_id` order, one run on each release |
| Setup | Two devices. The writing device inserted 40 documents with `priority: 1` (`_id` `t00` to `t39`) one at a time, in an order different from their `_id` order, and the other device received them. On both devices, we compared `SELECT _id FROM tasks ORDER BY priority` (with `LIMIT 10`, with `DESC LIMIT 10`, and without a limit) and the order without `ORDER BY`: first as received, then after other fields of the first three rows had been updated on the writing device and on the receiving device, and then after an index on `priority` had been created. The same with 3,000 documents, inserted 100 at a time. An observer of `ORDER BY priority LIMIT 10` on the receiving device showed whether an update of a document outside its result called it |

| Query | 5.1.0 and 5.2.0 | 5.0.3 without an index | 5.0.3 with an index on `priority` |
|---|---|---|---|
| `ORDER BY priority` | Ascending `_id` | `t01`, `t02`, …, `t39`, `t00`: the smallest `_id` last (with 3,000 documents, also in the last place) | Ascending `_id` |
| `ORDER BY priority LIMIT 10` | The first 10 rows of the full result | `t01` to `t09`, `t00`, while the full result starts with `t01` to `t10` | The first 10 rows of the full result |
| `ORDER BY priority DESC LIMIT 10` | Ascending `_id`: the ties are not reversed | `t01` to `t09`, `t00` (the same order as `ASC`) | `t01` to `t09`, `t00` |
| No `ORDER BY` | Ascending `_id` | Ascending `_id` | `SELECT _id FROM tasks` without `WHERE` was not in `_id` order in any of the three runs, and in the separate reproduction it returned one row `{}` instead of 40 rows |

- **5.1.0 and 5.2.0**: the results were the same with 40 and with 3,000 documents. Rows with the same sort key stay in ascending `_id` order with `DESC` too, so `DESC` does not return the reverse of `ORDER BY priority`. The insertion order is not followed. The order was the same on the writing and on the receiving device, and it did not change after the first rows were updated on either device or after the index was created. The observer was not called for updates of documents outside its result (as described in [When an observer fires depends on its query](transactions-and-observers.md#when-an-observer-fires-depends-on-its-query)).
- **5.0.3**: without an index, the order was the same on both devices and did not change after the updates. The single `{}` row matches a separate 5.0.3 issue with `SELECT _id` on an indexed collection, described in [An index created on an empty collection breaks in the 5.1.0 migration](upgrading.md#an-index-created-on-an-empty-collection-breaks-in-the-510-migration).
- On every release, the order was fixed, and devices that held the same documents never showed different orders. On 5.0.3, however, the order of ties depends on whether an index exists. Indexes are created on each device, so we think that a device with the index and a device without it show the same documents in different orders on 5.0.3. On 5.1 and later, the order was the same either way. This order is not documented; in these tests, it never varied.

**Not tested:** more than one collection; `_id` values other than strings, including composite IDs; more than one tied value; `JOIN`; sorting after `GROUP BY`; an index on only one of the two devices.

**Used in:** [ORDER BY](../best-practices/dql.md#order-by), [Stable ordering](../best-practices/observers.md#stable-ordering).

### OFFSET pages repeat rows after inserts, and keyset pages do not

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each (deterministic) |
| Setup | One device without sync. Pages of four documents read with `LIMIT :limit OFFSET :offset` and with keyset pagination, with one document inserted at the top after the first page had been read; `EXPLAIN` and `PROFILE` with each kind of statement; the user input `nobody' OR '1'='1` embedded as a string literal in a `SELECT` and a `DELETE` on a collection of three documents, and passed as an argument |

- **Paging**: `LIMIT :limit OFFSET :offset` accepted parameters. After the insert, the second `OFFSET` page repeated the last row of the first page. Keyset pagination with `_id` as the tie-breaker (`WHERE createdAt < :at OR (createdAt = :at AND _id < :id)`) returned no duplicates and skipped nothing. The results were the same on all three releases.
- **`EXPLAIN`**: on 5.1.0 and 5.2.0, `EXPLAIN` accepted `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `EVICT`, `CREATE INDEX`, `DROP INDEX`, and `ADVISE`, and executed none of them. `SHOW` and `ALTER SYSTEM` were rejected with `Explain DML is not supported`, a message that does not match the kind of statement. On 5.0.3, `EXPLAIN` of a mutation was rejected with the same message, and `ADVISE` was a syntax error.
- **`PROFILE`**: `PROFILE SELECT` returned the two result rows followed by one row with `~request_profile`. `PROFILE UPDATE` executed the update and returned one row, the profile. `PROFILE SHOW` did not fail and returned only the result of `SHOW`, without a profile row.
- **Embedded input**: with the input embedded as a string literal, the `SELECT` returned all three documents, and the `DELETE` built the same way deleted all three. Passed as an argument, the same value matched no document. The results were the same on all three releases.

**Used in:** [LIMIT and OFFSET](../best-practices/dql.md#limit-and-offset), [EXPLAIN and PROFILE](../best-practices/indexing-and-performance.md#explain-and-profile), [Input Validation and Query Parameters](../best-practices/security.md#input-validation-and-query-parameters).

## Numbers and strings in DQL

### Integers and floats are equal in WHERE but separate in GROUP BY

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, six runs each (`GROUP BY cast(n AS float)`: three runs each; `cast(n AS integer)` and `n * 1.0`: one run); every run gave the same result, on all three releases |
| Setup | One device without sync. One field held three values: the DQL literal `1` (`type()` returns `integer`), the DQL literal `1.0` (`float`), and `1.0` passed from JavaScript, where it is the integer 1 (`integer`). Equality filters, `GROUP BY`, and `DISTINCT` on the field |

- `WHERE n = 1`, `WHERE n = 1.0`, and `WHERE n = :n` (with the JavaScript value 1) each returned all three documents. After an index on `n` was created, `WHERE n = 1` returned the same; it was the only form checked with the index.
- `GROUP BY n` returned two groups, `{n: 1, c: 2}` and `{n: 1, c: 1}`, `DISTINCT n` returned two rows, and `COUNT(DISTINCT n)` was 2. JavaScript reads both values as `1`, so the result looks like two groups with the same key.
- `GROUP BY cast(n AS float)` returned one group with all three documents (`c: 3`). `cast(n AS integer)` and `n * 1.0` also gave one group (one run).
- Arithmetic with a float gives a float: `UPDATE ... SET n = qty * 2.5`, with `qty` at 4, stored `n` as the float `10` (5.1.0 and 5.2.0; on 5.0.3, a `SET` value cannot refer to a field, see [Some features that are not marked SDK 5.1+ fail on 5.0.3](#some-features-that-are-not-marked-sdk-51-fail-on-503)). A float is rejected as a document ID even when it is `2.0`: `Floats are not supported in document IDs` (see [Document IDs compare by type and exact value](#document-ids-compare-by-type-and-exact-value)).
- Dart has separate `int` and `double` types, and values such as `jsonDecode('10.0')` and `price * 1.0` are doubles, so a Flutter app can probably store both types in one field in the same way.

**Used in:** [Type Checking](dql-functions.md#type-checking).

### char_length counts code points, and JavaScript damages lone surrogates

| | |
|---|---|
| Observed on | SDK 5.2.0 (four runs) and 5.1.0 (three runs); every run gave the same result, on both releases |
| Setup | One device without sync. String functions on strings with emoji, combining characters, NUL, and the byte order mark; strings with unpaired UTF-16 surrogates written from JavaScript as field values, as document IDs, and as query arguments |

- `char_length` counts Unicode code points: `'👍'` gives `1` (its JavaScript `length` is 2), a family emoji of five code points joined with zero-width joiners gives `5` (JavaScript: 8), and `'café'` in NFD (with a combining accent) gives `5`. This is neither the number of characters a user sees nor the number of UTF-16 code units. `substr` also counts code points.
- Case conversion can change the length: `upper('straße')` is `'STRASSE'`, and `lower('İstanbul')` is `'i̇stanbul'` (`i` followed by a combining dot).
- NUL (`\u0000`) and the byte order mark (U+FEFF) are stored unchanged.
- An unpaired surrogate is not replaced with U+FFFD, as Node.js's `Buffer.from(s, 'utf8')` does. Instead, it is combined with the next code unit into another character, and the next character disappears. None of these writes raised an error:

| String written from JavaScript | Stored as |
|---|---|
| `'hello👍'.slice(0, 6)` (the emoji cut in half) | `'hello🐀'` (U+1F400) |
| `'a\ud800b'` | `'a'` followed by U+10062; the `b` is lost |
| `'\udc4d'` (an unpaired low surrogate) | U+23400 |

- Document IDs change in the same way. Query arguments change in the same way too, so a lookup with the same string on the same device finds the document, but the `_id` it returns differs from the original string.

**Not tested:** what devices on other platforms receive (probably the changed characters); the Flutter SDK (Dart strings are UTF-16 as well and can hold the same unpaired surrogates).

**Used in:** [String Functions](dql-functions.md#string-functions).

## Document IDs and field names

### Document IDs compare by type and exact value

| | |
|---|---|
| Observed on | ID values: SDK 5.0.3, 5.1.0, and 5.2.0, one run each, and one more run each on 5.1.0 and 5.2.0 with a separate script; deterministic, and the same on 5.1.0 and 5.2.0. ID length: SDK 5.0.3, 5.1.0, and 5.2.0, one run each (deterministic). IDs across devices: SDK 5.0.3, 5.1.0, and 5.2.0, three runs each |
| Setup | One device without sync: 15 kinds of `_id` inserted with `ON ID CONFLICT DO NOTHING`, then looked up with `WHERE _id = ...`, and string IDs of increasing length. Two offline devices that each created a document with a composite ID, then synced |

| IDs | Result |
|---|---|
| `1` and `'1'` | Two documents |
| `true` and `'true'` | Two documents |
| `'A'` and `'a'` | Two documents |
| `'1'` and `' 1'` | Two documents |
| `'é'` as one code point (U+00E9) and as `e` followed by a combining accent (U+0065 U+0301) | Two documents: Unicode forms are not normalized |
| `''` (the empty string) | Accepted |
| `0` | Accepted |
| `-0` | Rejected with `Invalid document id`, as a float |
| A `BigInt` of 2^60 | Accepted |

- `WHERE _id = 1` returned only the document with the number, and `WHERE _id = '1'` only the one with the string.
- **Length**: a string ID can have up to 254 bytes in UTF-8 (254 ASCII characters, or 84 characters of 3 bytes each). From 255 bytes, the write fails with `Serialized document ID is too large. Limit is 256 bytes`: the limit of 256 bytes applies to the serialized form. IDs built from user input or e-mail addresses need a length check.
- **Across devices**: two offline devices created a document each, with IDs that differed as follows, and then synced:

| The two IDs differ in | After sync |
|---|---|
| The order of the keys only, also of nested keys | One document with the fields of both |
| The type of one value only (`n: 1` and `n: "1"`) | Two documents |
| The order of an array only (`["x", "y"]` and `["y", "x"]`) | Two documents |

- The `_id` of the merged document comes back with its keys in name order (`{"orderId": "o1", "storeId": "s1"}`). When each device builds an ID by a fixed rule, such as a composite of a store and a date, every device must produce the same value types and the same array order.

**Used in:** [Allowed values](../best-practices/data-modeling.md#allowed-values).

### Field names can contain dots and backticks, or be empty

| | |
|---|---|
| Observed on | SDK 5.2.0 (three runs) and 5.1.0 (two runs); deterministic, and the same on both releases |
| Setup | One device without sync. Documents passed as arguments with field names that contain special characters, then read and written with `SELECT`, `SET`, and `UNSET` |

- Field names in a document passed as an argument are stored unchanged, including `a.b`, `with space`, `item-1`, `$x`, `0`, the empty string, and `` tick`name ``. Quoted with backticks, each of them can be read and written.
- A backtick inside a name is written twice (`` `tick``name` ``). A single backtick is a syntax error. This is the same in `SELECT`, `SET`, and `UNSET`.
- A quoted `` `a.b` `` is one field whose name contains a dot, different from the unquoted `a.b`, which is the field `b` inside `a`. Both can exist in the same document, and each can be read and written on its own. A map key that contains a dot works the same way: `` items.`x.y`.q `` treats `x.y` as one key.
- `é` in NFC and `é` in NFD are two different field names, as with document IDs (see [Document IDs compare by type and exact value](#document-ids-compare-by-type-and-exact-value)).

**Used in:** [Adding, updating, and removing map entries](../best-practices/data-modeling.md#adding-updating-and-removing-map-entries), [Field names](../best-practices/data-modeling.md#field-names).

## Type declarations and indexes

### Mixed type declarations change what a query reads, not the index results

| | |
|---|---|
| Observed on | SDK 5.1.0 and 5.2.0, two runs each (the case with two devices: one run each); deterministic |
| Setup | One device without sync. Documents in which `price` was written as a `REGISTER`, as a `MAP`, first as a `REGISTER` and then as a `MAP`, and in the reverse order. With and without an index on `price.amount` (created before or after the writes), we compared `WHERE price.amount > 10 ORDER BY price.amount` without a declaration, with `COLLECTION t (price REGISTER)`, and with `COLLECTION t (price MAP)`. In a second case, two offline devices rewrote 20 documents, one with `MAP` and the other with `REGISTER` |
| Documentation | Ditto's [Indexing](https://docs.ditto.live/dql/indexing) documentation says that only the most recently written data-type variant of a field is indexed, so results can be incorrect or mis-ordered when a field has several variants and an index on it serves part of a query |

- With and without the index, the rows and their order were the same, whether the index was created before or after the writes, and also when two devices wrote. The incorrect or mis-ordered results that the documentation describes did not occur with this query.
- `EXPLAIN` showed that only the query without a declaration used the index. The queries that declared `price REGISTER` or `price MAP` did not use it.
- A document written with both declarations holds two values under one key, as in [Keep type declarations consistent](../best-practices/data-modeling.md#keep-type-declarations-consistent). For a document written first as a `REGISTER` and then as a `MAP`, the reads returned different values:

| Read | Value |
|---|---|
| Without a declaration | `25` (the newer value) |
| `COLLECTION t (price MAP)` | `25` |
| `COLLECTION t (price REGISTER)` | `1` (the earlier value) |

- The same happened with two devices. An app version that declares `REGISTER` when it reads does not see the updates that other devices write with `MAP`, and keeps showing the old value.

**Used in:** [Strict mode and data types](../best-practices/indexing-and-performance.md#strict-mode-and-data-types), [Keep type declarations consistent](../best-practices/data-modeling.md#keep-type-declarations-consistent).

## Query limits and SDK 5.1.0 regressions

### Long OR chains crashed SDK 5.1.0, and nested parentheses fail at 100 levels

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0 for chains of up to 5,000 terms, and 5.1.0 and 5.2.0 for longer chains, one run each; the results appear to be deterministic |
| Setup | One device without sync. `SELECT` statements whose `WHERE` was a chain of 100 to 5,000 `OR` or `AND` terms, and longer chains, each size in a separate process; conditions that wrapped each term in another pair of parentheses (`((a OR b) OR c) ...`) |
| Documentation | The 5.2.0 release notes say: "`SELECT` statements with long `AND` or `OR` chains in the `WHERE` clause no longer crash the app" (SDKS-4435) |

- Up to 5,000 terms, all three releases returned the correct number of documents. 5,000 `AND` terms took 155 ms on 5.1.0 and 110 ms on 5.2.0.
- **5.1.0**: `OR` chains worked up to 10,000 terms, and at 15,000 terms the Node.js process ended with exit code 132 (SIGILL). `AND` chains worked up to 10,000 terms and ended the process at 20,000. No exception was thrown: the whole app ends.
- **5.2.0**: 50,000 `OR` terms returned the correct result in 96 ms.
- **Nested parentheses**: on 5.1.0 and 5.2.0, conditions worked up to 99 levels, and at 100 levels they failed with `DQL parser error: recursion limit exceeded`, an error that did not end the process.
- Devices with smaller thread stacks, such as mobile devices, may crash with fewer terms on 5.1.0.

**Used in:** [Known Issues in SDK 5.1.0](upgrading.md#known-issues-in-sdk-510), [Filtering by Membership](../best-practices/dql.md#filtering-by-membership).

### ANY over a parameter array broke in 5.1.0, and the multi-property issue was 5.1.0 only

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each (deterministic) |
| Setup | One device without sync. `ANY ... SATISFIES` and `EVERY ... SATISFIES` in `WHERE`, over a parameter array, over a literal array, and over an array field of the documents |

| Condition in `WHERE` | 5.0.3 | 5.1.0 | 5.2.0 |
|---|---|---|---|
| `ANY s IN :statuses SATISFIES s = status END`, the same over a literal array, and `EVERY` | The matching documents (`["a", "b"]`; with `EVERY`, `["c"]`) | No rows | No rows |
| `ANY car IN cars SATISFIES car.color = 'blue' AND car.type = 'SUV' END` over the documents' arrays | One document (correct) | Every document | One document (correct) |

- `ANY` and `EVERY` over a parameter or literal array have returned no rows since 5.1.0, and 5.2.0 does not fix it.
- A condition on several properties over a document's array matched every document only on 5.1.0: an issue that came with 5.1.0 and was fixed in 5.2.0.
- A subscription is not affected: with `WHERE ANY s IN :statuses SATISFIES s = status END`, a subscription synced the two matching documents, while the same statement as a local query on the receiving device returned no rows (5.1.0 and 5.2.0, one run each). A screen that observes the subscription's own query therefore shows an empty list although the data has arrived.

**Used in:** [Filtering by Membership](../best-practices/dql.md#filtering-by-membership), [ANY and EVERY](dql-functions.md#any-and-every), [Known Issues in SDK 5.1.0](upgrading.md#known-issues-in-sdk-510).

## Statements that fail or differ on SDK 5.0.3

### Some features that are not marked SDK 5.1+ fail on 5.0.3

| | |
|---|---|
| Observed on | SDK 5.0.3, one run |
| Setup | Every DQL statement in the guide, run on 5.0.3 as described in [Checks of the guide itself](how-we-tested.md#checks-of-the-guide-itself) |

Some statements failed because they use features marked (SDK 5.1+) or (SDK 5.2+): `JOIN`, `INSERT ... SELECT`, `RETURNING`, composite indexes, `ADVISE`, `DQL_SLOW_REQUEST_WARN_SECONDS`, `DQL_REQUEST_TIMEOUT_SECONDS`, certificate revocation checks, and support bundles. Others failed because of the string escapes that changed in 5.1.0. Apart from these, the following failed:

| Statement | Where the guide uses it | Result on 5.0.3 |
|---|---|---|
| `SHOW ALL LIKE '...'` | [Applying System Parameters](../best-practices/setup-and-lifecycle.md#applying-system-parameters), [Tombstone TTL and reaping](../best-practices/deletion-and-storage.md#tombstone-ttl-and-reaping), [System Parameters Reference](system-reference.md#system-parameters-reference) | Syntax error |
| `object_size()` | [Object Functions](dql-functions.md#object-functions), [Monitoring size](../best-practices/data-modeling.md#monitoring-size) | `Function "object_size" not found` |
| `DELETE ... USE IDS LIST :ids` | [DELETE and Tombstones](../best-practices/deletion-and-storage.md#delete-and-tombstones) | Syntax error: `DELETE` does not accept `USE IDS` on 5.0.3 |
| `UPDATE inventory SET stockLevel = stockLevel - 1` | [When counters are appropriate](../best-practices/data-modeling.md#when-counters-are-appropriate) (the ❌ BAD example) | `Forbidden: Document references in mutation values`; the statement succeeds on 5.1.0 and later |
| `serialize_json()` | [Arithmetic, Conversion, and Other Functions](dql-functions.md#arithmetic-conversion-and-other-functions) | `Function "serialize_json" not found` (also found by the check of the expression examples) |

**Used in:** [How to Use This Guide](../best-practices/README.md#how-to-use-this-guide) (the SDK release marks), and the sections in the table above.

### SDK 5.0.3 differs in the size limit, constant comparisons, and defaults

| | |
|---|---|
| Observed on | SDK 5.0.3, one run |
| Setup | The 27 existing checks on one device without sync, run again on 5.0.3 and compared with their results on 5.1.0 and 5.2.0 |
| Documentation | The 5.2.0 release notes say: "The query planner now generates correct index span ranges for expressions of the form `constant operator field`, such as `1 < a`" (QE-1212) |

- **Hard size limit**: 5.0.3 stored a 6 MiB document, built by adding 3 MiB twice, without an error. The 5 MiB limit on writes is probably enforced only since 5.1. This is probably also why a 5.0.3 peer could update a 6 MiB document in [An oversized merge ends differently on each release](upgrading.md#an-oversized-merge-ends-differently-on-each-release).
- **Constant on the left**: like 5.1.0, 5.0.3 returned wrong results for `1 < a` through an index. The issue that 5.2.0 fixed existed since 5.0.
- **Observer on `system:system_info`**: 5.0.3 called it 5 times in 5 seconds (about once a second; from the second call on, the results barely changed). 5.1.0 called it every 500 ms, and 5.2.0 twice about every second.
- **`queryArguments`**: for a subscription registered without arguments, 5.0.3 also returned `null` and did not crash.
- **`DQL_REQUEST_HISTORY_SIZE`**: the default on 5.0.3 is 4096, as on 5.1.0; 5.2.0 changed it to 128.
- **`DELETE ... USE IDS`** is a syntax error, and a composite index fails with `The feature is not implemented yet : composite indexes`, as the (SDK 5.1+) mark says.

**Used in:** [Document Size Limits](../best-practices/data-modeling.md#document-size-limits), [Monitoring Storage](../best-practices/deletion-and-storage.md#monitoring-storage), [Known Issues in SDK 5.1.0](upgrading.md#known-issues-in-sdk-510).

## JavaScript values in DQL

### JavaScript values that are not plain JSON change when stored

| | |
|---|---|
| Observed on | SDK 5.0.3, 5.1.0, and 5.2.0, one run each (deterministic); the results were the same on all three releases |
| Setup | One device without sync. JavaScript values of each kind written as field values through arguments, then read back; large integers also written as DQL literals; the result of `SHOW ALL` |

| JavaScript value | Stored and read back as |
|---|---|
| `Date` | An empty object `{}`: the time is lost, without an error |
| A field whose value is `undefined` | `null`, so the field no longer matches `IS MISSING`; `undefined` inside arrays and objects also becomes `null` |
| `NaN`, `Infinity` | The write fails: `Unable to encode query arguments: Non-finite float values are not supported` |
| `-0` | `-0` |
| `BigInt` | An integer, read back as a `BigInt` |
| `Uint8Array` | Bytes, read back as a `Uint8Array` |
| `Map` | An object |
| An integer above 2^53 − 1, also when written as a DQL literal | Read back as a `BigInt` (`9007199254740993n`) |
| The largest int64 value plus 1 | No error; read back as `9223372036854775808n` |

- A row that contains a `BigInt` makes `JSON.stringify` fail with `Do not know how to serialize a BigInt`. The result of `SHOW ALL` contains two `BigInt` values.

**Not tested:** integers written as int64 values by the other SDKs (they probably come back as `BigInt` in JavaScript as well).

**Used in:** [Platform Differences](platform-differences.md), [MISSING and NULL](../best-practices/dql.md#missing-and-null), [Store UTC with a zone designator](../best-practices/data-modeling.md#store-utc-with-a-zone-designator).
