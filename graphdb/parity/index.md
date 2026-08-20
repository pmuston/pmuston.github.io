---
title: graphdb vs Neo4j Cypher
---

[← graphdb](../)

# graphdb ↔ Neo4j Cypher — Feature Parity

A living comparison of graphdb's hand-written Cypher subset against Neo4j Cypher
(reference: Neo4j 5.x). Scope for now: **keywords/clauses**, **data types**, and
**functions**. It records what graphdb actually implements (verified against the
source, not aspirational) so client authors know what to generate and so we can
prioritise the gaps.

See also [cypher-spec.md](../cypher/), the normative language reference for
graphdb's dialect.

**graphdb server version at last review:** 0.28.0 — every ❌ row below was
executed against a running server of that version, not inferred from the source,
and the ✅ rows were sampled across every section with the projection and
ordering rows checked in full (0.27.0 and 0.28.0 changed how `ORDER BY` resolves
its sort keys).
**Neo4j reference:** 5.x

## Legend

| Mark | Meaning |
|------|---------|
| ✅ | Supported, behaves as Neo4j does |
| ⚠️ | Partial — supported with a documented divergence or narrower shape |
| ❌ | Not supported (parse or evaluation error) |
| 🔜 | Not supported, but flagged as a high-value near-term candidate |

graphdb is **not** Neo4j and never runs Bolt; it implements a read-heavy Cypher
subset over HTTP/JSON. "Parity" here means *source-compatibility of queries*, not
protocol or storage compatibility.

**Tooling parity.** The practical payoff of this source-compatibility is that
`graphdb + gq` is a drop-in analogue of `neo4j + cyq` for exporting query
results. [gq](https://pmuston.github.io/gq) is the graphdb-backed peer of
[cyq](https://pmuston.github.io/cyq): the same flag surface and output shaping
(CSV, or graph-row JSONL for `gfig map`), differing only at the connection layer
— gq speaks this HTTP/JSON API with a bearer token, where cyq speaks Bolt with a
user and password. An export query ports between the two pairs by changing the
binary name and the connection flags; the Cypher itself carries over wherever
the rows below are ✅. gq requires graphdb 0.18.0+ and feature-detects on
connect. The `varlen-path-binding` and `quoted-identifiers` rows here both began
as gq requirements.

---

## 1. Keywords & clauses

### Reading & projection

| Construct | graphdb | Notes |
|-----------|:-------:|-------|
| `MATCH` | ✅ | Node/rel patterns, multi-hop, undirected. |
| `OPTIONAL MATCH` | ✅ | Left-outer join; null-pads the pattern's new variables when it has no match. Anchored, all-new, and chained forms; inner `WHERE` filters the optional match. |
| `WHERE` (in MATCH and after WITH) | ✅ | |
| `RETURN` (+ `AS`, `DISTINCT`, `*`) | ✅ | |
| `WITH` (chaining, post-`WHERE`) | ✅ | |
| `UNWIND … AS` | ✅ | Null list → zero rows. |
| `ORDER BY … ASC\|DESC` | ✅ | Sort keys may name projection aliases or variables in scope before the projection. **After aggregation** a key must be a returned column, a grouping expression, or an aggregate the statement already returns (`ORDER BY count(*)`, 0.28.0+); an aggregate nested in a larger expression is rejected. Fixed in 0.27.0: a property-access sort key in `RETURN`/`WITH` was silently dropped, returning rows in insertion order. |
| `SKIP` / `LIMIT` | ✅ | |
| `UNION` / `UNION ALL` | ✅ | Branches must project the same column names; `UNION` dedupes, `UNION ALL` concatenates. Left-associative, independent scopes. |
| `CALL {…}` subquery | ❌ | |
| `CALL … YIELD` (procedures) | ❌ | No procedure system. |
| `CALL … IN TRANSACTIONS` | ❌ | |
| `USE` (composite/fabric) | ❌ | |
| `FOREACH` | ❌ | |
| `LOAD CSV` | ❌ | Bulk load is the `graphdb import` CLI instead. |
| `USING` (index/join hints) | ❌ | Planner chooses anchors itself. |
| `PROFILE` / `EXPLAIN` | ❌ | |

### Writing

| Construct | graphdb | Notes |
|-----------|:-------:|-------|
| `CREATE` (nodes, directed rels) | ✅ | |
| `MERGE` | ✅ | Any pattern, any mix of bound/unbound variables (feature `merge-patterns`). All-or-nothing over the whole pattern, as in Neo4j. Rejects patterns it could not construct: undirected/untyped/variable-length relationships, `:A\|B` on a creatable node. |
| `ON CREATE SET` / `ON MATCH SET` | ✅ | |
| `SET` (properties, labels) | ✅ | |
| `REMOVE` (properties, labels) | ✅ | |
| `DELETE` / `DETACH DELETE` | ✅ | Plain `DELETE` of a still-connected node errors, as in Neo4j. |
| `CREATE`/`DROP INDEX`/`CONSTRAINT` (Cypher DDL) | ❌ | Property indexes are declared via `POST /indexes`, not Cypher. |
| `SHOW …` (INDEXES/CONSTRAINTS/FUNCTIONS…) | ❌ | |

### Predicate & expression keywords

| Construct | graphdb | Notes |
|-----------|:-------:|-------|
| `AND` `OR` `XOR` `NOT` | ✅ | Three-valued logic. |
| `IN <list>` | ✅ | Any list-valued RHS (literal, variable, function result). |
| `IS NULL` / `IS NOT NULL` | ✅ | |
| `STARTS WITH` / `ENDS WITH` / `CONTAINS` | ✅ | |
| `=~` (regex match) | ❌ | |
| `CASE … WHEN … THEN … ELSE … END` | ✅ | Simple and searched forms. |
| `ALL` / `ANY` / `NONE` / `SINGLE` (`x IN list WHERE …`) | ✅ | |
| `reduce(acc = init, x IN list \| expr)` | ✅ | |
| List comprehension `[x IN list WHERE p \| map]` | ✅ | |
| Pattern comprehension `[(a)-->(b) \| b.x]` | ❌ | Operates on patterns, not list values. |
| `EXISTS { <pattern> }` / `exists(n.prop)` | ✅ | `EXISTS { [MATCH] pattern [WHERE …] }`; `exists(expr)` is `expr IS NOT NULL`. |
| Pattern predicate `WHERE (a)-->(b)` | ✅ | Existential semijoin; pattern-introduced variables do not leak. **WHERE only** (incl. `WITH … WHERE`), not in RETURN. |
| `COUNT { … }` subquery | ❌ | |
| Map projection `n { .name, .age }` | ✅ | Plus `.*` and `key: expr` entries. |
| `TRUE` / `FALSE` / `NULL` literals | ✅ | |
| Parameters `$name` | ✅ | Bound at execution, never interpolated. |
| Backtick-quoted identifiers `` `a b` `` | ✅ | Any characters, never a keyword (feature `quoted-identifiers`). Valid as alias, variable, property key, label, type. |

### Variable-length & paths

| Construct | graphdb | Notes |
|-----------|:-------:|-------|
| Variable-length `-[:T*min..max]->` | ✅ | Bounded, or unbounded `*` capped by config. `*0..0` is the zero-length match. |
| Var-length rel variable `-[r:T*]->` | ✅ | `r` binds to the list of traversed relationships, in order — Neo4j parity. |
| Path binding `p = (…)` | ✅ | Any pattern, including variable-length segments (feature `varlen-path-binding`). `nodes(p)`/`relationships(p)` are complete and in traversal order. |
| `shortestPath` / `allShortestPaths` | ❌ | |
| Quantified path patterns (`( … ){1,3}`) | ❌ | Neo4j 5.9+ syntax. |
| Label expressions `:A:B` (all), `:A\|B` (any) | ✅ | Rel-type disjunction `-[:A\|B]->` too. |
| Richer label expr `(A\|B)&C`, `!A`, parentheses | ❌ | |

---

## 2. Data types

Neo4j and graphdb agree on the core rule that **map values cannot be stored as
properties**. graphdb's stored-property set is a subset of Neo4j's.

### Stored property types

| Type | graphdb | Notes |
|------|:-------:|-------|
| Integer (`int64`) | ✅ | 64-bit. |
| Float (`float64`) | ✅ | Int/float distinction preserved on the wire and across reload. |
| Boolean | ✅ | |
| String | ✅ | UTF-8; string functions are rune-aware. |
| Null | ✅ | Setting a property to null removes it. |
| List | ⚠️ | Supported (feature `list-properties`), persisted as a JSON array. **More permissive than Neo4j**: graphdb allows heterogeneous and **nested** lists; Neo4j requires a homogeneous array of a single primitive. **Never indexed** — `POST /indexes` on a list-valued property is accepted but has no effect, so equality and range predicates over it fall back to a scan. |
| Point (spatial) | ❌ | |
| Date / Time / LocalTime / DateTime / LocalDateTime | ❌ | |
| Duration | ❌ | |
| ByteArray | ❌ | |

### Structural / query-only value types

| Type | graphdb | Notes |
|------|:-------:|-------|
| Node | ⚠️ | Serialised with `kind: "node"`, `id`, `elementId`, `labels`, and **`props`** — Neo4j's JSON calls that field `properties`. Client authors must map the name. |
| Relationship | ✅ | `kind: "relationship"`, with `startNodeElementId` / `endNodeElementId`. |
| Path | ✅ | `kind: "path"`; ordered nodes + relationships; `length(p)`. |
| Type discriminator on the above | ✅ | The `kind` field (feature `value-kind`) is the JSON analogue of Bolt's structure signatures (Node `0x4E`, Relationship `0x52`, Path `0x50`), which graphdb's JSON rendering previously dropped. Emitted at every nesting depth; **never** on user maps. |
| List (as an expression/result value) | ✅ | List literals, indexing, slicing, comprehensions. |
| Map (as an expression/result value) | ✅ | Map literals `{k: v}`, `m.key` / `m["key"]` access, map projection, `properties()`. **Query-only** — maps cannot be stored as properties (as in Neo4j). |

---

## 3. Functions

Grouped by Neo4j's function categories. Absent categories (temporal, spatial,
math) are listed so the gaps are explicit.

### Predicate functions

| Function | graphdb | Notes |
|----------|:-------:|-------|
| `all(x IN list WHERE p)` | ✅ | |
| `any(…)` `none(…)` `single(…)` | ✅ | |
| `exists(n.prop)` | ✅ | Equivalent to `n.prop IS NOT NULL`. |
| `isEmpty(list\|string)` | ✅ | Listed under scalar functions. |

### Scalar functions

| Function | graphdb | Notes |
|----------|:-------:|-------|
| `id(x)` | ✅ | Dense `uint64`; Neo4j deprecates `id()` but it exists. |
| `elementId(x)` | ✅ | Opaque `n<id>` / `e<id>`. |
| `type(rel)` | ✅ | |
| `coalesce(a, b, …)` | ✅ | |
| `head(list)` / `last(list)` | ✅ | |
| `size(list\|string)` | ✅ | |
| `length(path)` | ✅ | Path only (Neo4j `length` is path-only too). |
| `toInteger` / `toFloat` / `toString` | ✅ | |
| `toBoolean` | ✅ | Accepts bool, string (`"true"`/`"false"`), and integer (0 → false). |
| `isEmpty(list\|string)` | ⚠️ | List/string only; the map form is not wired up. |
| `*OrNull` variants (`toIntegerOrNull`, …) | ❌ | |
| `startNode(rel)` / `endNode(rel)` | ✅ | Return the relationship's source / target node. |
| `properties(x)` | ✅ | Property map of a node/relationship (or the map itself). |
| `valueType(x)` | ❌ | |
| `timestamp()` | ❌ | |
| `randomUUID()` | ❌ | |

### Aggregating functions

| Function | graphdb | Notes |
|----------|:-------:|-------|
| `count(x)` / `count(*)` / `count(DISTINCT x)` | ✅ | |
| `sum` `avg` `min` `max` | ✅ | |
| `collect(x)` (+ `DISTINCT`) | ✅ | Returns a list value. |
| `percentileCont` / `percentileDisc` | ❌ | |
| `stDev` / `stDevP` | ❌ | |

### List functions

| Function | graphdb | Notes |
|----------|:-------:|-------|
| `range(start, end[, step])` | ✅ | |
| `reverse(list)` | ✅ | Polymorphic (string or list). |
| `tail(list)` | ✅ | |
| `labels(node)` | ✅ | Returns the list of label names, in insertion order. |
| `keys(x)` | ✅ | List of property key names (node or relationship), sorted for determinism. |
| `nodes(path)` / `relationships(path)` | ✅ | Return the path's node / relationship list. |
| `toIntegerList` / `toFloatList` / `toStringList` / `toBooleanList` | ❌ | |

### String functions

| Function | graphdb | Notes |
|----------|:-------:|-------|
| `toLower` / `toUpper` | ✅ | |
| `trim` / `ltrim` / `rtrim` | ✅ | Unicode whitespace. |
| `substring(s, start[, len])` | ✅ | Rune-indexed. |
| `replace(s, search, repl)` | ✅ | |
| `left(s, n)` / `right(s, n)` | ✅ | |
| `split(s, delim)` | ✅ | |
| `reverse(s)` | ✅ | Shared with list `reverse`. |
| `normalize(s)` | ❌ | |
| `+` string concatenation | ✅ | Via the `+` operator, not a function. |

### Mathematical functions

| Group | graphdb | Notes |
|-------|:-------:|-------|
| Numeric: `abs` `ceil` `floor` `round` `sign` `rand` | ✅ | `abs` preserves numeric type; `ceil`/`floor`/`round` return floats; `round(x, p)` supports a precision; `sign` returns an integer; `rand()` is a float in [0, 1). |
| Logarithmic: `e` `exp` `log` `log10` `sqrt` | ❌ | |
| Trigonometric: `sin` `cos` `tan` `asin` … `pi` `degrees` `radians` | ❌ | |
| `^` power operator | ❌ | `+ - * / %` are supported. |

### Temporal & spatial functions

| Group | graphdb | Notes |
|-------|:-------:|-------|
| Temporal: `date` `datetime` `time` `duration` `localdatetime` … | ❌ | No temporal types. |
| Spatial: `point` `point.distance` | ❌ | No spatial types. |
| `shortestPath` / `allShortestPaths` | ❌ | Listed under paths above. |

---

## Notable divergences (same syntax, different behaviour)

- **List properties are more permissive**: graphdb stores heterogeneous/nested
  lists as JSON; Neo4j requires a homogeneous primitive array.
- **`id()`** returns graphdb's dense internal id and doubles as the user-facing
  id; there is no separate legacy-vs-element id distinction beyond `elementId()`.
- **Whole-valued floats** serialise with a decimal (`34.0`) to preserve the
  int/float distinction the wire would otherwise collapse.

## High-value gaps (suggested priority order)

1. **More math** — `sqrt`, `exp`, `log`/`log10`, `^` power, trig — if the
   workload needs them (none of the current workload does).
2. **`percentileCont` / `percentileDisc` / `stDev`** aggregates.
3. **Pattern predicates in RETURN** — supported in `WHERE`; projecting one as a
   boolean column still errors.
4. **Map parameters** — `$props` as a map, `SET n += $props`, `CREATE (n $props)`.

*Done in 0.7.0: `labels()` returns a list; `keys()`, `nodes()`,
`relationships()` (feature `graph-list-functions`). Done in 0.8.0: numeric
`abs`/`ceil`/`floor`/`round`/`sign`/`rand` (`math-functions`) and
`startNode`/`endNode`/`toBoolean`/`isEmpty` (`scalar-functions`). Done in
0.9.0: `OPTIONAL MATCH` (`optional-match`). Done in 0.10.0: `UNION` /
`UNION ALL` (`union`). Done in 0.13.0: pattern predicates and `EXISTS { }`
(`pattern-predicates`). Done in 0.11.0: query-only map values — literals,
access, map projection, `properties()` (`map-values`).*

---

*Maintenance: the "server version at last review" line claims the matrix was
checked, so do not bump it on its own — that turns the stamp into a false
assertion, which is worse than an obviously stale one. Re-derive the graphdb
columns when the Cypher surface changes (lexer keywords, `exec` function
dispatch, `plan` aggregate set, model property kinds), then confirm the ❌ rows
by executing them: a ❌ that has quietly started working understates the product
and is the failure mode nobody notices.*
