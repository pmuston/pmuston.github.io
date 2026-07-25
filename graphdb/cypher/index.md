---
title: graphdb Cypher Reference
---

[← graphdb](../)

# graphdb Cypher — Language Specification

**Applies to graphdb 0.24.0.** This is a normative description of the Cypher
dialect graphdb implements, derived from the implementation (lexer, parser,
planner, executor), not from openCypher. Anything not described here is not
supported; see [neo4j-parity.md](../parity/) for the comparison matrix
against Neo4j.

Notation: `[x]` optional, `{x}` zero-or-more, `a | b` alternatives, `'x'`
literal text. Keywords are case-insensitive.

---

## 1. Lexical structure

### 1.1 Whitespace and comments

Whitespace (space, tab, CR, LF) separates tokens and is otherwise insignificant.
Two comment forms are supported and treated as whitespace:

```cypher
// line comment to end of line
/* block comment,
   may span lines */
```

### 1.2 Identifiers and keywords

An identifier starts with a letter or `_` and continues with letters, digits, or
`_`. Identifiers are **case-sensitive**; keywords are **case-insensitive**.

Reserved words:

```
MATCH  OPTIONAL  WHERE   RETURN  WITH    UNWIND  UNION
ORDER  BY        SKIP    LIMIT   AS      DISTINCT
AND    OR        XOR     NOT     IN      IS      NULL   TRUE  FALSE
STARTS ENDS      CONTAINS
ASC    ASCENDING DESC    DESCENDING
CREATE MERGE     SET     REMOVE  DELETE  DETACH  ON
CASE   WHEN      THEN    ELSE    END
```

`ALL` is **not** reserved (it would shadow the `all()` quantifier); it is
recognised contextually in `UNION ALL`.

A reserved word **is** accepted where a name is unambiguous: property keys,
labels, relationship types, property access after `.`, and `AS` aliases. It is
**not** accepted, unquoted, as a variable, path variable, or function name.

```cypher
CREATE (n:Set {End: 1, Order: 2})    -- legal: labels and property keys
MATCH (n) RETURN n.Delete AS With     -- legal: property key and alias
MATCH (return) RETURN return          -- ERROR: variable named with a keyword
```

**Backtick-quoted identifiers** (feature `quoted-identifiers`) lift both
restrictions. A name enclosed in backticks is valid anywhere a name is valid —
alias, variable, property key, label, relationship type — and its contents are
taken **literally**: it may contain any character (a colon, space, hyphen, dot,
leading digit) and is **never** interpreted as a keyword. This matches Neo4j and
keeps queries portable in both directions. A doubled backtick is a literal
backtick; backslash is **not** an escape (unlike a string); an unterminated
backtick is a syntax error.

```cypher
RETURN a.tag AS `prop:mode`           -- a column literally named prop:mode
MATCH (`return`:Node) RETURN `return` -- a variable named with a keyword: now legal
RETURN {`a:b`: 1}                      -- a property key that isn't a plain identifier
RETURN 1 AS `a``b`                     -- the column name a`b
```

### 1.3 Literals

| Kind | Form |
|---|---|
| Integer | `42`, `-7` (64-bit signed) |
| Float | `3.14`, `1e10`, `2.5E-3`, `.5` |
| String | `'text'` or `"text"` |
| Boolean | `TRUE`, `FALSE` |
| Null | `NULL` |

String escapes: `\n \t \r \\ \' \" \0`; any other escaped character is taken
literally. An unterminated string is a lexical error.

### 1.4 Parameters

`$name` — bound at execution, **never** string-interpolated (this is the
injection defence). A parameter may be a **scalar, list, or map**, nested
arbitrarily. See §7.3.

### 1.5 Operators and punctuation

```
( ) [ ] { }   : , . ; |
+ - * / %
= <> < <= > >=
..            (range, in slices and variable-length)
$             (parameter)
```

`=~` is **not** a token (`~` is an illegal character).

---

## 2. Statement structure

A request carries exactly **one** statement. A trailing `;` is permitted;
multiple statements are rejected.

```
query   := branch { 'UNION' ['ALL'] branch }
branch  := part { part }
part    := { reading } { update } [ projection ]
reading := match | unwind
update  := create | merge | set | remove | delete
```

Within a branch, every part except the last ends in a `WITH` projection; the
last ends in `RETURN`, or has no projection if it only performs updates.
Branches combine left-associatively; each branch has an independent variable
scope and all branches must project the **same column names in the same order**.

---

## 3. Reading clauses

### 3.1 MATCH / OPTIONAL MATCH

```
match := ['OPTIONAL'] 'MATCH' patternPart { ',' patternPart } ['WHERE' expr]
```

`MATCH` finds all pattern matches. `OPTIONAL MATCH` is a left-outer join: for
each incoming row, if the pattern (including its `WHERE`) has no match, the row
is preserved once with the pattern's newly-introduced variables bound to `null`.
A clause's `WHERE` belongs to that clause; in an `OPTIONAL MATCH` it filters the
optional matches *before* the null-padding decision.

Consecutive non-optional `MATCH` clauses are planned together; each
`OPTIONAL MATCH` is a join boundary.

### 3.2 UNWIND

```
unwind := 'UNWIND' expr 'AS' identifier
```

Expands a list into one row per element. A `null` list yields **no** rows. Valid
before or after `MATCH`, and with updates.

---

## 4. Patterns

```
patternPart := [identifier '='] nodePattern { relPattern nodePattern }
nodePattern := '(' [identifier] [labels] [propMap] ')'
labels      := ':' name { ':' name }        -- conjunction: has ALL
             | ':' name { '|' name }        -- disjunction: has ANY
relPattern  := '-' [relDetail] '-'  ['>']   -- and the '<-...-' mirror
relDetail   := '[' [identifier] [':' type {'|' type}] [varLength] [propMap] ']'
varLength   := '*' [int] ['..' [int]]
propMap     := '{' [ name ':' expr { ',' name ':' expr } ] '}'
```

- **Direction:** `-->` outgoing, `<--` incoming, `--` undirected.
- **Inline properties** are equality predicates (or, in `CREATE`/`MERGE`, the
  properties to write).
- **Variable-length** `*min..max`; omitted bounds default to 1 and the
  configured `maxVarLenDepth`. Paths are enumerated with **relationship
  uniqueness** (no edge repeats within one path), so cycles terminate.
- **The variable-length relationship variable binds to a list** of the
  relationships traversed, in traversal order (`-[r:T*1..3]->` ⇒ `r` is a list
  of 1–3 relationships). Its length equals the hop count, and a zero-length
  match binds the **empty list**. `r` is never `null`.
  - `size(r)` gives the hop count. `length()` is for paths and rejects a list.
  - `type(r)` is an error — `r` is a list, not one relationship. Use `type(r[0])`,
    or `[e IN r | type(e)]`.
  - Because `r` is an ordinary list value, indexing, slicing, `IN`, `UNWIND` and
    list comprehensions all work over it.
- **Hop bounds.** `*n` is exactly *n*; `*m..n` is the inclusive range; `*`,
  `*m..` and `*..n` leave a bound open. An omitted lower bound is 1; an omitted
  upper bound is the configured `maxVarLenDepth`. An upper bound of `0`
  (`*0`, `*0..0`) means the **zero-length match only** — the source node itself,
  with an empty relationship list. A range whose upper bound is below its lower
  bound (`*3..1`) matches nothing.
- **Path binding** `p = (...)` works for any pattern, including one containing a
  variable-length relationship. A variable-length segment contributes every
  relationship it traversed and every node those reached, so `nodes(p)` and
  `relationships(p)` are complete and in traversal order, and `length(p)` is the
  hop count. As always a path has one more node than relationships; a
  zero-length match is a path of the anchor alone.
- **Relationship isomorphism:** within a single match, an edge already bound to
  another relationship variable cannot be reused.

---

## 5. Projection

```
projection := ('RETURN' | 'WITH') ['DISTINCT'] ( '*' | item { ',' item } )
              ['ORDER' 'BY' sortKey { ',' sortKey }]
              ['SKIP' expr] ['LIMIT' expr]
              ['WHERE' expr]        -- WITH only
item       := expr ['AS' name]
sortKey    := expr ['ASC' | 'DESC']
```

- An unaliased item's column name is its rendered expression text; complex
  expressions render as `expr`.
- `ORDER BY` and a `WITH ... WHERE` may reference the projection's own aliases;
  `RETURN`/`WITH` items may reference only variables already bound.
- Referencing an unbound variable is an error.
- `WITH` ends a scope: only projected names are visible downstream.

---

## 6. Writing clauses

| Clause | Form and notes |
|---|---|
| `CREATE` | `CREATE patternPart { ',' patternPart }` — relationships must be directed. |
| `MERGE` | `MERGE patternPart ['ON CREATE SET' items] ['ON MATCH SET' items]`. Any pattern (see below). |
| `SET` | `SET v.prop = expr` \| `SET v:Label` \| `SET v = map` (replace all properties) \| `SET v += map` (merge entries, leaving others). The map may be a map value, a parameter, or another node/relationship. Setting a property to `null` removes it. |
| `REMOVE` | `REMOVE v.prop` \| `REMOVE v:Label` |
| `DELETE` | `[DETACH] DELETE expr { ',' expr }`. Plain `DELETE` of a still-connected node is an error. |

A write statement may also return rows (`CREATE (n) RETURN n`).

### 6.1 MERGE semantics

`MERGE` accepts any pattern — a single node, a relationship, or a multi-hop path
with any mix of bound and unbound variables. It is **all-or-nothing across the
whole pattern**:

1. The pattern is matched as a whole, with variables already bound by an earlier
   clause held fixed.
2. If it matches, **nothing is created**; `ON MATCH SET` is applied to *every*
   match, and every match is returned.
3. If it does not match at all, **everything the pattern introduces is created**
   — every unbound node and every relationship — and `ON CREATE SET` is applied
   to the single resulting row.

The consequence worth internalising is that a pre-existing node does not, on its
own, prevent a create:

```cypher
CREATE (:A {k: 1})
MERGE (a:A {k: 1})-[:R]->(b:B)   -- creates a SECOND :A, plus :B and the edge
```

The pattern as a whole did not match, so the whole pattern was created. To reuse
the existing node, bind it first:

```cypher
MATCH (a:A {k: 1}) MERGE (a)-[:R]->(b:B)   -- reuses a; creates only b and the edge
```

This is Neo4j's behaviour. Within one pattern a repeated variable is the same
node, so `MERGE (t:T)-[:E]->(u:U)-[:E]->(t)` creates two nodes and closes the
cycle.

Because MERGE must be able to *construct* what it describes, patterns that are
ambiguous about what to build are rejected while planning — before anything is
created: an undirected or untyped relationship, a variable-length relationship,
and a `:A|B` label disjunction on a node that may need creating.

A MERGE that fails part-way through creating leaves nothing behind: a statement
is one transaction, and its memory mutations are unwound on any error.

---

## 7. Expressions

### 7.1 Precedence (lowest to highest)

| Level | Operators |
|---|---|
| 1 | `OR` |
| 2 | `XOR` |
| 3 | `AND` |
| 4 | `NOT` (prefix) |
| 5 | `=` `<>` `<` `<=` `>` `>=`, `STARTS WITH`, `ENDS WITH`, `CONTAINS`, `IN`, `IS [NOT] NULL` |
| 6 | `+` `-` |
| 7 | `*` `/` `%` |
| 8 | `-` (unary) |
| 9 | postfix: `.name`, `:Label`, `[i]`, `[lo..hi]`, `{ … }` (map projection) |
| 10 | primary |

`+` concatenates when both operands are strings. There is no `^` operator.

### 7.1.1 Pattern predicates

A pattern in expression position is a boolean: true when it has at least one
match for the current row (an existential semijoin, short-circuiting on the
first match).

```cypher
MATCH (a:P) WHERE (a)-[:KNOWS]->()            RETURN a      -- has an outgoing KNOWS
MATCH (a:P) WHERE NOT (a)-[:KNOWS]->()        RETURN a      -- orphans
MATCH (a:P) WHERE EXISTS { (a)-[:KNOWS]->() } RETURN a      -- same, braces form
MATCH (a:P) WHERE EXISTS { MATCH (a)-[:R]->(b) WHERE b.x > 1 } RETURN a
```

- Variables already bound outside constrain the pattern; variables the pattern
  introduces are **existential** and do not leak into the surrounding scope.
- `EXISTS { [MATCH] pattern [, pattern…] [WHERE expr] }` is the explicit form.
  `exists(expr)` is the scalar form, equivalent to `expr IS NOT NULL`.
- Supported in `WHERE` (including `WITH … WHERE`) only; projecting a pattern
  predicate (`RETURN (a)-->(b)`) is an error.
- A parenthesised group is read as a pattern only when a relationship follows
  the closing `)`, so arithmetic such as `(a) - 1` is unaffected.

### 7.2 Primary expressions

Literal · parameter · variable · function call · `( expr )` · list literal ·
map literal · `CASE` · `reduce` · quantifier · list comprehension.

```cypher
[1, 2, 3]                              -- list literal
xs[0]   xs[-1]   xs[1..3]   xs[..2]    -- index (negative from end) / slice
{name: 'Alice', age: 34}               -- map literal
m.key   m["key"]                       -- map access
n {.name, .age, kind: 'person', .*}    -- map projection
CASE WHEN c THEN a ELSE b END          -- searched CASE
CASE x WHEN 1 THEN 'one' ELSE 'many' END
reduce(acc = 0, x IN xs | acc + x)
[x IN xs WHERE x > 1 | x * 2]          -- list comprehension
all(x IN xs WHERE p)                   -- also any / none / single
```

Out-of-range list index and missing map key both yield `null`. The iteration
variable of `reduce`, a comprehension, or a quantifier is scoped to that
expression only.

### 7.3 Types

**Stored property values:** `int64`, `float64`, `bool`, `string`, `null`, and
**lists** of those (nesting permitted). Lists are persisted as JSON arrays and
are **not indexable**. **Maps cannot be stored.**

**Query-only values:** node, relationship, path, list, map.

**Parameters** may be **scalars, lists, or maps**, nested arbitrarily (features
`list-parameters`, `map-parameters`). Parameters are query-only values, so a map
parameter can be read and projected but still cannot be *stored* as a property.

### 7.4 Null semantics

Three-valued logic. `AND`/`OR`/`XOR` propagate `null`; comparisons with `null`
yield `null`; arithmetic with `null` yields `null`. `x IN []` is `false` even for
a null `x`; `null IN [1]` is `null`. Aggregates skip nulls (so `count(x)` over
no matches is `0`). Ordering places values by type rank: null < bool < number <
string < list.

---

## 8. Functions

**Graph:** `id`, `elementId`, `labels` (list), `keys` (sorted list), `type`,
`nodes(path)`, `relationships(path)`, `startNode`, `endNode`, `properties` (map).

**Scalar:** `coalesce`, `length(path)`, `size(list|string)`, `head`, `last`,
`toInteger`, `toFloat`, `toString`, `toBoolean`, `isEmpty(list|string)`.

**String:** `toLower`, `toUpper`, `trim`, `ltrim`, `rtrim`,
`substring(s, start[, len])`, `replace`, `left`, `right`, `reverse`, `split`.
All are rune-aware.

**List:** `range(start, end[, step])`, `size`, `head`, `last`, `tail`,
`reverse`, `split`.

**Numeric:** `abs` (preserves int/float), `ceil`, `floor`,
`round(x[, precision])`, `sign` (int), `rand()` (float in `[0,1)`).

**Aggregates:** `count(x)`, `count(*)`, `count(DISTINCT x)`, `sum`, `avg`,
`min`, `max`, `collect` (+ `DISTINCT`).

Unknown functions are a runtime error.

### 8.1 Aggregation and grouping

Grouping is **implicit**: the non-aggregated part of the projection forms the
grouping key.

An aggregate may be the whole projection item, or appear **anywhere inside** one
— a map projection, a map or list literal, arithmetic, a `CASE`:

```cypher
MATCH (c:Company)<-[:WORKS_AT]-(p:Person)
RETURN c {.name, staff: collect(p {.name, .age})} AS company
```

When an item contains an aggregate, the grouping key is each **maximal
aggregate-free subtree that reads a variable**. So `RETURN a.x + count(b)` groups
by `a.x` (not by `a`), and `RETURN c {.name, n: count(p)}` groups by `c`. A
constant is not a grouping key. Computing the aggregate in an earlier `WITH`
remains valid and gives identical results.

Three cases are rejected, because there is no coherent group to compute over:

- an aggregate inside a **list comprehension**, **`reduce`**, or a **quantifier**
  — each binds its own iteration variable, which does not exist at aggregation
  time;
- an aggregate nested **inside another aggregate** (`count(collect(x))`);
- an aggregate anywhere other than a projection item.

With no grouping key and no input rows, aggregation still yields one row
(`count(*)` over an empty match is `0`).

---

## 9. Execution semantics

- **One statement per request.** Reads and writes are dispatched automatically.
- **Reads** execute entirely against memory under a read lock; they never touch
  disk and observe a consistent snapshot for the statement's duration.
- **Writes** are **atomic per statement**: mutations are staged with an undo
  log, applied to memory, and committed to SQLite in one transaction. If the
  statement or the commit fails, memory is rolled back — memory and disk never
  diverge. There are no multi-statement transactions.
- **Row order is unspecified** without `ORDER BY`.
- Execution is pull-based, so `LIMIT` short-circuits.
- A per-query timeout and a variable-length depth cap are configurable.

---

## 10. Errors

Errors carry a Neo4j-style `code` and a `message`:

| Code | Meaning |
|---|---|
| `Neo.ClientError.Statement.SyntaxError` | lex/parse/planning error |
| `Neo.ClientError.Statement.ArgumentError` | evaluation error (bad types, unknown function) |
| `Neo.ClientError.Statement.EntityNotFound` | referenced entity missing |
| `Neo.ClientError.Security.Unauthorized` | auth failure |

Parse errors report **line and column**:

```
parse error at line 3, column 11: unexpected token * ("*")
```

---

## 11. Not supported

Procedures and `CALL` (including `CALL {}` subqueries), `FOREACH`, `LOAD CSV`,
`USING` hints, `PROFILE`/`EXPLAIN`, Cypher DDL for indexes/constraints,
`shortestPath`/`allShortestPaths`, `COUNT {}`, pattern comprehensions,
pattern predicates outside `WHERE`, regex `=~`, temporal and spatial types and
their functions, `percentileCont`/`percentileDisc`/`stDev`, `*OrNull`
conversions, map **properties**, `CREATE (n $props)`, richer label
expressions (`(A|B)&C`, `!A`), quantified path patterns, and multi-statement
transactions.
