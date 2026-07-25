---
title: graphdb User Guide
---

[← graphdb](../)

# User Guide

**Applies to graphdb 0.23.0.** Every example below was executed against a running
server of that version, not written from memory.

A practical, example-driven guide to running graphdb and querying it with the
Cypher subset. This guide is the tutorial; `man graphdb` is the offline CLI
reference. The repository additionally carries the normative language
specification, the client interface contract, the Neo4j parity matrix and
measured benchmarks.

> Check what you are actually talking to: `curl -s localhost:8080/ | jq .version`
> reports the server's version and a `features` list. This guide describes
> 0.23.0; an older instance will reject some of what follows.

- [Install and run](#install-and-run)
- [Configuration](#configuration)
- [The HTTP API](#the-http-api)
- [Querying: reads](#querying-reads)
- [Querying: writes](#querying-writes)
- [Property indexes](#property-indexes)
- [Importing .cypher files](#importing-cypher-files)
- [REST CRUD shortcuts](#rest-crud-shortcuts)
- [Response shapes](#response-shapes)
- [Limitations and tips](#limitations-and-tips)

---

## Install and run

```bash
go build -o graphdb ./cmd/graphdb
./graphdb                 # serves on :8080, database at ./graphdb.db
```

The server loads the entire graph from SQLite into memory on boot, then serves
reads from RAM and writes through to SQLite. `GET /health` reports `ready:false`
until the initial load finishes.

```bash
curl -s localhost:8080/health
# {"ready":true,"status":"ok"}
```

Throughout this guide, this helper keeps the examples short:

```bash
cy() { curl -s -XPOST localhost:8080/cypher -d "$1"; echo; }
```

---

## Configuration

Precedence is **defaults < config file < environment < command-line flags**.

| Flag | Env | Default | Meaning |
|---|---|---|---|
| `-config` | `GRAPHDB_CONFIG` | — | path to a JSON config file |
| `-listen` | `GRAPHDB_LISTEN` | `:8080` | HTTP listen address |
| `-db` | `GRAPHDB_DB` | `graphdb.db` | SQLite database path |
| `-auth-token` | `GRAPHDB_AUTH_TOKEN` | *(empty)* | bearer token required on requests (empty disables auth) |
| `-max-varlen-depth` | `GRAPHDB_MAX_VARLEN_DEPTH` | `15` | cap for variable-length path expansion |
| `-query-timeout` | — | `30s` | per-query execution timeout |
| `-body-limit` | — | `10M` | maximum request body size |

Config file (config/graphdb.example.json):

```json
{
  "listenAddr": ":8080",
  "dbPath": "graphdb.db",
  "authToken": "",
  "maxVarLenDepth": 15,
  "writeBehind": false,
  "queryTimeout": "30s",
  "bodyLimit": "10M"
}
```

```bash
./graphdb -config config/graphdb.example.json -listen :9090   # flag overrides file
```

If `auth-token` is set, send it on every request except `/health`:

```bash
curl -s -H "Authorization: Bearer <token>" localhost:8080/stats
```

---

## The HTTP API

| Method & path | Purpose |
|---|---|
| `POST /cypher` | Execute a statement (read or write — dispatched automatically). |
| `GET  /nodes/:id` | Fetch a node. |
| `POST /nodes` | Create a node. |
| `GET  /edges/:id` | Fetch an edge. |
| `POST /edges` | Create an edge. |
| `POST /indexes` | Declare a property index on `(label, prop)`. |
| `GET  /stats` | Counts, cardinalities, declared indexes. |
| `GET  /health` | Liveness/readiness. |

`POST /cypher` body is `{ "query": "...", "params": { } }`. Parameters are bound
at execution and never string-interpolated.

---

## Querying: reads

The examples below assume this small graph. Create it first:

The query must be a single JSON string — a raw newline inside a JSON string is
invalid, so keep each statement on one line (the examples below do). Cypher
itself is whitespace-insensitive; it's only the JSON encoding that matters.

```bash
cy '{"query":"CREATE (alice:Person {name:\"Alice\", city:\"Berlin\", age:34}), (bob:Person {name:\"Bob\", city:\"Berlin\", age:41}), (carol:Person {name:\"Carol\", city:\"Paris\", age:28}), (dave:Person {name:\"Dave\", city:\"Berlin\", age:50}), (acme:Company {name:\"Acme\"}), (globex:Company {name:\"Globex\"}), (alice)-[:KNOWS]->(bob), (alice)-[:KNOWS]->(carol), (bob)-[:KNOWS]->(dave), (alice)-[:WORKS_AT {since:2015}]->(acme), (bob)-[:WORKS_AT {since:2019}]->(acme), (carol)-[:WORKS_AT {since:2020}]->(globex), (dave)-[:WORKS_AT {since:2010}]->(acme)"}'
```

> If you prefer multi-line statements, put them in a file and escape the newlines
> in the JSON (`\n`), or use a client that encodes JSON for you rather than raw
> `curl -d`.

### Basic match and return

```bash
cy '{"query":"MATCH (p:Person) RETURN p.name AS name ORDER BY name"}'
# columns: [name]; rows: Alice, Bob, Carol, Dave
```

### Filtering with WHERE

```bash
cy '{"query":"MATCH (p:Person) WHERE p.age > 30 AND p.city = \"Berlin\" RETURN p.name"}'
# Alice, Bob, Dave
```

Supported predicates: `= <> < <= > >=`, `AND`/`OR`/`NOT`/`XOR`, `IN [ ... ]`,
`STARTS WITH` / `ENDS WITH` / `CONTAINS`, `IS NULL` / `IS NOT NULL`, and label
tests (`p:Person`).

Labels in a node pattern combine as **conjunction** with `:` (`(n:A:B)` = has
*both* A and B) or **disjunction** with `|` (`(n:A|B)` = has *either*). A
disjunction anchor is served by a fast bitmap union of the label sets:

```bash
cy '{"query":"MATCH (m:Person|Company) RETURN labels(m) AS label, count(*) AS n"}'
```

```bash
cy '{"query":"MATCH (p:Person) WHERE p.name STARTS WITH \"A\" OR p.age IN [28, 50] RETURN p.name"}'
# Alice, Carol, Dave
```

### Parameters

```bash
cy '{"query":"MATCH (p:Person) WHERE p.city = $city RETURN p.name","params":{"city":"Paris"}}'
# Carol
```

### Parameters: scalars, lists and maps

Parameters are bound, never interpolated. They may be scalars, arrays, or
objects, nested as deeply as you like:

```bash
# filter by a caller-supplied set
cy '{"query":"MATCH (p:Person) WHERE p.name IN $names RETURN p.name","params":{"names":["Alice","Carol"]}}'

# read fields off a map parameter
cy '{"query":"RETURN $props.name AS name","params":{"props":{"name":"Zoe","age":30}}}'

# the batch upsert: one request, idempotent
cy '{"query":"UNWIND $rows AS row MERGE (n:Thing {id: row.id}) SET n += row","params":{"rows":[{"id":1,"name":"one"},{"id":2,"name":"two"}]}}'
```

`SET n += map` merges the map's entries into the node's existing properties;
`SET n = map` replaces them wholesale (properties absent from the map are
removed). Maps are query values only — you cannot store one as a property.

### Naming things — backtick-quoted identifiers

A plain name is letters, digits and `_`, starting with a letter or `_`. Wrap a
name in backticks and those rules stop applying: it may contain any character,
and it is never read as a keyword. This is valid anywhere a name is — a column
alias, a variable, a property key, a label, a relationship type.

```bash
# A column name with a colon in it — impossible unquoted
cy '{"query":"MATCH (p:Person) RETURN p.name AS `person:name` LIMIT 1"}'

# A property key that isn't a plain identifier
cy '{"query":"MATCH (p:Person {name:\"Alice\"}) RETURN p {`display name`: p.name} AS m"}'
```

Two details worth knowing: a doubled backtick is a literal one
(`` `a``b` `` names the column ``a`b``), and backslash is **not** an escape here
as it is in a string — `` `a\tb` `` is the five-character name `a\tb`.

This is the escape hatch for exporters that need a specific column name, and the
only way to use a reserved word as a variable.

### Traversals (multi-hop, direction)

```bash
# One hop
cy '{"query":"MATCH (a:Person {name:\"Alice\"})-[:KNOWS]->(f) RETURN f.name"}'
# Bob, Carol

# Two hops: who do Alice's contacts work for?
cy '{"query":"MATCH (:Person {name:\"Alice\"})-[:KNOWS]->(f)-[:WORKS_AT]->(c) RETURN f.name, c.name"}'

# Undirected (either direction)
cy '{"query":"MATCH (b:Person {name:\"Bob\"})-[:KNOWS]-(x) RETURN x.name"}'
# Alice (incoming), Dave (outgoing)
```

Directions: `-[:T]->` outgoing, `<-[:T]-` incoming, `-[:T]-` undirected.

### Variable-length paths

```bash
# Everyone reachable from Alice via 1 to 3 KNOWS hops
cy '{"query":"MATCH (a:Person {name:\"Alice\"})-[:KNOWS*1..3]->(b) RETURN DISTINCT b.name"}'

# Exactly 2 hops
cy '{"query":"MATCH (a:Person {name:\"Alice\"})-[:KNOWS*2]->(b) RETURN b.name"}'

# Unbounded (capped by -max-varlen-depth); use DISTINCT to collapse paths to nodes
cy '{"query":"MATCH (a:Person {name:\"Alice\"})-[:KNOWS*]->(b) RETURN count(DISTINCT b) AS reachable"}'
```

Each path is enumerated with **relationship uniqueness** (no edge reused within a
path), so cyclic graphs terminate. The relationship variable is not bound for
variable-length patterns.

### OPTIONAL MATCH

Like `MATCH`, but keeps the incoming row even when the pattern doesn't match —
the pattern's new variables come back as `null` (a left-outer join).

```bash
# Every person, plus a post they wrote if any (people with none still appear)
cy '{"query":"MATCH (a:Person) OPTIONAL MATCH (a)-[:WROTE]->(p:Post) RETURN a.name, p.title"}'

# WHERE inside the OPTIONAL filters the optional match; the person is still kept
cy '{"query":"MATCH (a:Person) OPTIONAL MATCH (a)-[:WROTE]->(p) WHERE p.score > 5 RETURN a.name, p.title"}'

# Aggregates skip the nulls, so people with no posts count 0
cy '{"query":"MATCH (a:Person) OPTIONAL MATCH (a)-[:WROTE]->(p) RETURN a.name, count(p) AS posts"}'
```

Optionals can be chained; a later `OPTIONAL MATCH` that starts from a null
variable simply yields more nulls. A mandatory `MATCH` after an `OPTIONAL MATCH`
drops the null-padded rows (there's nothing to expand from).

### Ordering, paging, DISTINCT

```bash
cy '{"query":"MATCH (p:Person) RETURN p.name AS name, p.age AS age ORDER BY age DESC SKIP 1 LIMIT 2"}'
# Bob 41, Alice 34   (Dave 50 skipped)

cy '{"query":"MATCH (:Person)-[:WORKS_AT]->(c:Company) RETURN DISTINCT c.name"}'
# Acme, Globex
```

### Aggregation

Grouping is implicit: the non-aggregate return items are the grouping keys.

```bash
# Headcount per company
cy '{"query":"MATCH (:Person)-[:WORKS_AT]->(c:Company) RETURN c.name AS company, count(*) AS headcount ORDER BY headcount DESC"}'
# Acme 3, Globex 1

# Numeric aggregates
cy '{"query":"MATCH (p:Person) RETURN min(p.age) AS youngest, max(p.age) AS oldest, avg(p.age) AS mean"}'

# collect() gathers values into a list
cy '{"query":"MATCH (p:Person) WHERE p.city = \"Berlin\" RETURN collect(p.name) AS berliners"}'
# berliners: ["Alice","Bob","Dave"]
```

Aggregate functions: `count`, `count(*)`, `count(DISTINCT x)`, `sum`, `avg`,
`min`, `max`, `collect`.

### WITH — chaining query parts

`WITH` projects intermediate results forward, enabling post-aggregation filtering
and multi-stage queries.

```bash
# Companies with 2 or more employees
cy '{"query":"MATCH (:Person)-[:WORKS_AT]->(c:Company) WITH c, count(*) AS headcount WHERE headcount >= 2 RETURN c.name AS company, headcount"}'
# Acme 3

# Take the two oldest people, then traverse from them
cy '{"query":"MATCH (p:Person) WITH p ORDER BY p.age DESC LIMIT 2 MATCH (p)-[:WORKS_AT]->(c) RETURN p.name, c.name"}'
```

### UNWIND — expand a list into rows

`UNWIND list AS x` produces one row per element (a null list yields no rows). It
composes with `MATCH` (in either order) and with writes.

```bash
# expand the path segments into rows
cy '{"query":"UNWIND split(\"A/B/C\", \"/\") AS seg RETURN seg"}'

# for each name in a list, find the matching node
cy '{"query":"UNWIND [\"Alice\",\"Bob\"] AS nm MATCH (p:Person {name: nm}) RETURN p.name"}'

# create a node per element
cy '{"query":"UNWIND range(1, 3) AS i CREATE (:Seq {v: i})"}'
```

### Pattern predicates — "does this relationship exist?"

A pattern can be used directly as a condition. It's true when the pattern
matches at least once, so it's the clean way to filter on connectivity — and,
negated, to find things that are *missing* an edge.

```bash
# people who know someone
cy '{"query":"MATCH (a:Person) WHERE (a)-[:KNOWS]->() RETURN a.name"}'

# orphans: people who know nobody
cy '{"query":"MATCH (a:Person) WHERE NOT (a)-[:KNOWS]->() RETURN a.name"}'

# constrain the far end
cy '{"query":"MATCH (a:Person) WHERE (a)-[:WROTE]->(:Post) RETURN a.name"}'

# explicit EXISTS form, with its own WHERE
cy '{"query":"MATCH (a:Person) WHERE EXISTS { MATCH (a)-[:KNOWS]->(b) WHERE b.city = \"Paris\" } RETURN a.name"}'
```

Variables introduced inside the pattern (`b` above) are existential — they exist
only for the test and can't be returned. Pattern predicates work in `WHERE` and
`WITH … WHERE`, combine with `AND`/`OR`/`NOT`, but cannot be projected in
`RETURN`. `exists(n.prop)` is the scalar form and means `n.prop IS NOT NULL`.

### Maps — shaping the response

Maps are JSON objects you build in the query. They're **query values only** —
you can't store one as a property (same rule as Neo4j).

```bash
# Map literal, and access by .key or ["key"]
cy '{"query":"WITH {name: \"Alice\", age: 34} AS m RETURN m.name, m[\"age\"]"}'

# Map projection: pick properties off a node (.* takes them all)
cy '{"query":"MATCH (p:Person) RETURN p {.name, .age} AS person"}'

# All properties, dynamically
cy '{"query":"MATCH (p:Person) RETURN properties(p) AS props"}'

# Mix picked properties with computed entries
cy '{"query":"MATCH (p:Person)-[:WORKS_AT]->(c) RETURN p {.name, company: c.name, senior: p.age > 30} AS person"}'
```

The payoff is returning ready-made nested JSON instead of flat columns your
client has to regroup:

```bash
cy '{"query":"MATCH (c:Company)<-[:WORKS_AT]-(p:Person) RETURN c {.name, staff: collect(p {.name, .age})} AS company"}'
# → {"name":"Acme","staff":[{"name":"Alice","age":34},{"name":"Bob","age":41},{"name":"Dave","age":50}]}
```

An aggregate like `collect()` may sit directly inside the map projection.
Grouping is implicit — here by `c`, the aggregate-free part of the item. The
older two-step spelling still works and gives the same answer, if you find it
clearer:

```bash
cy '{"query":"MATCH (c:Company)<-[:WORKS_AT]-(p:Person) WITH c, collect(p {.name, .age}) AS staff RETURN c {.name, staff: staff} AS company"}'
```

### UNION — combine branches

`UNION` de-duplicates the combined result; `UNION ALL` keeps every row. Each
branch must return the **same column names in the same order**.

```bash
# Everything named, from two labels, duplicates collapsed
cy '{"query":"MATCH (p:Person) RETURN p.name AS name UNION MATCH (c:Company) RETURN c.name AS name"}'

# Keep duplicates, and tag which branch each row came from
cy '{"query":"MATCH (p:Person) RETURN p.name AS name, \"person\" AS kind UNION ALL MATCH (c:Company) RETURN c.name AS name, \"company\" AS kind"}'
```

Branches have independent variable scopes (reusing `n` in both is fine), combine
left-to-right, and may each carry their own `ORDER BY`/`SKIP`/`LIMIT`. Mismatched
column names are rejected with a clear error.

### Functions

`id(x)`, `elementId(x)`, `type(r)`, `toInteger(x)`, `toFloat(x)`, `toString(x)`,
`toBoolean(x)`, `coalesce(a, b, ...)`, `length(path)`, `isEmpty(list|string)`.

**Graph:** `labels(n)` → list of label names; `keys(n)` / `keys(r)` → sorted list
of property keys; `nodes(p)` / `relationships(p)` → a path's nodes / relationships;
`startNode(r)` / `endNode(r)` → a relationship's endpoints.

**Numeric:** `abs` (keeps int/float), `ceil`, `floor`, `round(x[, precision])`,
`sign` (returns int), `rand()` (float in [0, 1)).

**String:** `toLower`, `toUpper`, `trim`/`ltrim`/`rtrim`, `substring(s, start[, len])`,
`replace(s, search, repl)`, `left(s, n)`, `right(s, n)`, `reverse`.

**List:** `split(s, delim)`, `range(start, end[, step])`, `size`, `head`, `last`,
`tail`, `reverse`, plus list literals `[a, b, c]`, indexing `xs[i]` (negative from
the end; out-of-range → null), and slicing `xs[lo..hi]`.

```bash
# e.g. the plant-cell name is the last path segment
cy '{"query":"RETURN last(split(\"SITE/AREA/BOILER_PC\", \"/\")) AS pcName"}'
```

```bash
cy '{"query":"MATCH (p:Person {name:\"Alice\"})-[r:WORKS_AT]->(c) RETURN id(p), labels(p), type(r)"}'
```

### Conditionals and list expressions

`IN` accepts any list-valued right-hand side — not just a `[...]` literal, but a
variable or a function result too:

```bash
cy '{"query":"MATCH (a:RtAttribute) WHERE \"boiler\" IN split(a.Path, \"/\") RETURN a.Name"}'
```

`CASE` in both the searched and simple forms:

```bash
cy '{"query":"MATCH (p:Person) RETURN p.name, CASE WHEN p.age >= 18 THEN \"adult\" ELSE \"minor\" END AS band"}'
cy '{"query":"RETURN CASE 2 WHEN 1 THEN \"one\" WHEN 2 THEN \"two\" ELSE \"many\" END AS n"}'
```

`reduce(acc = init, x IN list | expr)` folds a list to one value; **list
comprehensions** `[x IN list WHERE pred | map]` build a new list (both `WHERE`
and the `| map` are optional); and the quantifiers `all`/`any`/`none`/`single`
test a predicate over a list:

```bash
# join all-but-the-first path segment back together with "/"
cy '{"query":"RETURN reduce(s = \"\", x IN split(\"a/b/c\", \"/\")[1..] | CASE WHEN s = \"\" THEN x ELSE s + \"/\" + x END) AS rest"}'

# even numbers 1..6, each doubled
cy '{"query":"RETURN [n IN range(1, 6) WHERE n % 2 = 0 | n * 10] AS xs"}'

# does every segment look non-empty?
cy '{"query":"RETURN all(seg IN split(\"a/b/c\", \"/\") WHERE size(seg) > 0) AS ok"}'
```

The iteration variable of `reduce`, a comprehension, or a quantifier is scoped to
that expression — it doesn't collide with or leak into the rest of the query.

### Paths

Bind a path with `p = (...)` and return it. A path renders as
`{"nodes":[...], "relationships":[...], "length":N}`, with relationships
carrying `from`/`to`/`type`/`props`; `length(p)` is the relationship count.

```bash
cy '{"query":"MATCH p=(a:Person {name:\"Alice\"})-[:KNOWS]->(b)-[:WORKS_AT]->(c) RETURN length(p) AS hops"}'
```

Path binding works over **variable-length** relationships too. The whole
traversal comes back as one path, so `nodes(p)` and `relationships(p)` are
complete and in traversal order:

```bash
cy '{"query":"MATCH p=(a:Person {name:\"Alice\"})-[:KNOWS*1..3]->(b) RETURN [n IN nodes(p) | n.name] AS chain, length(p) AS hops ORDER BY hops"}'
# → ["Alice","Bob"] 1 · ["Alice","Carol"] 1 · ["Alice","Bob","Dave"] 2
```

A path always holds one more node than relationships, and `length(p)` is the hop
count. A zero-length match (`*0..0`) is a path of the anchor alone.

You can also bind the **relationship variable** and skip the path — it holds the
list of relationships traversed, in order, which is often all you need:

```cypher
MATCH (a:Person {name:'Alice'})-[r:KNOWS*1..3]->(b)
RETURN b.name, size(r) AS hops, [e IN r | type(e)] AS types
```

`size(r)` is the hop count; a zero-length match binds the empty list. Note `r` is
a *list*, so `type(r)` is an error — use `type(r[0])` or the comprehension above.

---

## Querying: writes

Writes run under an exclusive lock and commit to SQLite atomically per statement.
The response includes write `stats`.

### CREATE

```bash
# Nodes and a relationship in one statement
cy '{"query":"CREATE (z:Person {name:\"Zoe\", age:22})-[:WORKS_AT {since:2023}]->(c:Company {name:\"Initech\"})"}'
# stats: nodesCreated 2, relationshipsCreated 1

# Relate already-matched nodes
cy '{"query":"MATCH (a:Person {name:\"Carol\"}),(b:Person {name:\"Dave\"}) CREATE (a)-[:KNOWS]->(b)"}'
```

### SET and REMOVE

```bash
cy '{"query":"MATCH (p:Person {name:\"Carol\"}) SET p.age = 29, p:Verified"}'   # set property + add label
cy '{"query":"MATCH (p:Person {name:\"Carol\"}) REMOVE p.age, p:Verified"}'      # remove property + label
```

Setting a property to `null` removes it.

### DELETE and DETACH DELETE

```bash
cy '{"query":"MATCH (c:Company {name:\"Initech\"}) DELETE c"}'          # errors if c still has relationships
cy '{"query":"MATCH (p:Person {name:\"Zoe\"}) DETACH DELETE p"}'         # removes p and its relationships
```

Plain `DELETE` on a node that still has relationships is an error — use
`DETACH DELETE`.

### MERGE (match-or-create)

`MERGE` finds the pattern or creates it, then applies `ON CREATE SET` /
`ON MATCH SET`. Any pattern works — a node, a relationship, or a longer path
with any mix of bound and unbound variables.

```bash
# Idempotent node: creates Acme only if absent
cy '{"query":"MERGE (c:Company {name:\"Acme\"}) ON CREATE SET c.founded = 1999 ON MATCH SET c.seen = true RETURN c.name"}'

# Idempotent relationship (run twice, still one edge)
cy '{"query":"MATCH (a:Person {name:\"Bob\"}),(b:Person {name:\"Carol\"}) MERGE (a)-[:KNOWS]->(b)"}'

# A whole path in one statement — and one transaction
cy '{"query":"MERGE (p:Person {name:\"Zoe\"})-[:WORKS_AT]->(c:Company {name:\"Initech\"}) RETURN p.name"}'
```

**The one rule that surprises people:** MERGE is all-or-nothing across the
*whole* pattern. If the pattern as a whole does not match, everything it
introduces is created — so an existing node does not, by itself, prevent a
create:

```cypher
MERGE (c:Company {name:'Acme'})-[:NEW_REL]->(x:Thing)
-- Acme exists, but no such relationship does, so the pattern did not match:
-- this creates a SECOND Acme, plus the Thing and the relationship.
```

Bind what you want to reuse first:

```cypher
MATCH (c:Company {name:'Acme'})
MERGE (c)-[:NEW_REL]->(x:Thing)     -- reuses Acme; creates only x and the edge
```

This is Neo4j's behaviour, so queries port both ways. A MERGE that fails
part-way through creating leaves nothing behind — one statement is one
transaction.

Patterns MERGE could match but could never *build* are rejected before anything
is written: an undirected or untyped relationship, a variable-length
relationship, or `:A|B` on a node that might need creating (it does not say
which label to create).

---

## Property indexes

Without an index, an equality/range anchor scans the whole label set. Declaring a
`(label, prop)` index turns that into an index seek (orders of magnitude faster —
see benchmarks.md). Indexes are declared once, backfilled from
existing nodes, maintained on every write, and persist across restarts.

```bash
curl -s -XPOST localhost:8080/indexes -d '{"label":"Person","prop":"name"}'

# Now this anchor is an index seek rather than a label scan:
cy '{"query":"MATCH (p:Person {name:\"Alice\"})-[:KNOWS]->(f) RETURN f.name"}'

curl -s localhost:8080/stats     # "indexes": ["Person.name"]
```

Declare indexes on properties you filter or match on by equality/range in hot
queries (e.g. a `Tag` or `Name` used to look up a specific entity).

---

## Importing .cypher files

`graphdb import` bulk-loads directories of exporter-generated `.cypher` files —
one statement per file, one atomic transaction per file.

```bash
# 1) Validate first: parse every file, write nothing, list what won't load
graphdb import --dry-run /path/to/exports

# 2) In-process bulk load (fastest; run with the server stopped). --reset clears first.
graphdb import --db graph.db --reset /path/to/exports

# 3) Or against a running server (changes visible immediately, slower)
graphdb import --server http://localhost:8080 /path/to/exports
```

Flags: `--db`, `--server`, `--dry-run`, `--reset`, `--fail-fast`. The run
continues past errors by default and prints a summary:

```
imported 2617 file(s): 177013 nodes, 174396 relationships created; 9 failed (6.39s)
```

Notes:
- Property keys that are reserved words (e.g. `Set`) are accepted.
- These exports are **not idempotent** (`CREATE` duplicates on re-run) — use
  `--reset`, or start from an empty database, when re-importing.
- Don't run an in-process import against a database a live server also has open;
  the server's in-memory copy won't see the new rows until it restarts.
- `--dry-run` is the fast way to find files that use unsupported features (e.g.
  list-valued properties) before committing to a load.

---

## REST CRUD shortcuts

Convenience endpoints for simple cases without writing Cypher:

```bash
# Create a node -> returns {id, labels, props}
curl -s -XPOST localhost:8080/nodes -d '{"labels":["Person"],"props":{"name":"Erin","age":37}}'

# Fetch it
curl -s localhost:8080/nodes/1

# Create an edge between existing node ids
curl -s -XPOST localhost:8080/edges -d '{"type":"KNOWS","from":1,"to":2,"props":{"since":2024}}'

# Fetch an edge
curl -s localhost:8080/edges/1
```

---

## Response shapes

**Read** (`POST /cypher`):

```json
{
  "columns": ["name", "age"],
  "rows": [["Alice", 34], ["Bob", 41]],
  "stats": { "rowsReturned": 2 },
  "tookMs": 0
}
```

Node/edge values (e.g. `RETURN n`) serialize as objects carrying a `kind`
discriminator, plus a string `elementId` (Neo4j-style stable identity) alongside
the integer `id`:

```json
{"kind":"node","id":1,"elementId":"n1","labels":["Person"],"props":{}}
{"kind":"relationship","id":1,"elementId":"e1","type":"KNOWS","from":1,"to":2,
 "startNodeElementId":"n1","endNodeElementId":"n2","props":{}}
```

`kind` is `"node"`, `"relationship"` or `"path"`, so a client dispatches on one
field instead of guessing from which keys are present. It appears at every
nesting depth — inside paths and inside lists — and **never** on a plain map, so
a map projection that happens to look like a node stays distinguishable. The
`elementId(x)` function returns that string.

Integers and floats stay distinct on the wire — a whole-valued float serialises
as `34.0`, an integer as `34`.

**Write** adds mutation counters to `stats`:

```json
{
  "columns": [], "rows": [],
  "stats": {
    "rowsReturned": 0, "nodesCreated": 2, "relationshipsCreated": 1,
    "nodesDeleted": 0, "relationshipsDeleted": 0,
    "propertiesSet": 0, "labelsAdded": 0, "labelsRemoved": 0
  },
  "tookMs": 0
}
```

Parse, planning, and evaluation errors return HTTP `400` with a Neo4j-style
status `code` and a `message`, e.g.
`{"code":"Neo.ClientError.Statement.SyntaxError","message":"parse error at line 1, column 12: …"}`.

`GET /` returns a discovery document (server name/version); `GET /health`
includes the version.

---

## Limitations and tips

- **Property values are scalars or lists** — `int64`, `float64`, `bool`,
  `string`, `null`, and **lists** of those (e.g. `RtBlock: []`, `tags: ["a","b"]`,
  nesting allowed). Lists persist as JSON arrays and read back as list values
  (use `size`/`head`/`last`/indexing/`IN`/comprehensions on them) but are **not
  indexable**. **Map** property values are still not supported; `--dry-run` flags
  files that use them.
- **`labels()` returns a list** of every label on the node — a node may carry
  several (`:Person:Staff`). Test membership with `'Person' IN labels(n)`, or
  better, put the label in the pattern: `MATCH (n:Person)`.
- **Not supported:** `CALL` / procedures, subqueries, `COUNT { }`, regex `=~`,
  `shortestPath`, temporal and spatial types. Maps are query values only — they
  cannot be stored as properties.
- **Reserved words** are allowed unquoted as property keys, labels, relationship
  types and aliases, but not as bare variable names. Backticks lift that and every
  other naming restriction — `` `return` `` is a variable named `return`, and
  `` `odd:name` `` is a perfectly good column name (see *Naming things* above).
- **Label expressions** support flat conjunction (`:A:B`) and disjunction
  (`:A|B`); the richer forms (`(A|B)&C`, negation `!A`, parentheses) are not
  supported.
- **One statement per request/file.** Multi-statement files are rejected; split
  them upstream.
- **Performance:** declare indexes on the properties you look entities up by;
  prefer starting a pattern from the most selective anchor; use `LIMIT` (without
  `ORDER BY`) to short-circuit early.
