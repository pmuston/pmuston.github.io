---
title: jsondb User Guide
---

[← jsondb](../)

# jsondb User Guide

A practical, end-to-end guide to using **jsondb** — a MongoDB-lite JSON document
store on SQLite (pure Go, no CGo). For a quick overview see
`about.md`; for the gory grammar details see
[`native-query.md`](../native-query/), [`where-filtering.md`](../where/),
and [`sql-select-syntax.md`](../sql/).

## Contents

1. [Concepts](#1-concepts)
2. [Install & build](#2-install--build)
3. [Using the library](#3-using-the-library-embedding)
4. [Running the server](#4-running-the-server)
5. [The CLI](#5-the-cli)
6. [Querying](#6-querying)
7. [The remote client](#7-the-remote-client)
8. [The web UI](#8-the-web-ui)
9. [Tips & limits](#9-tips--limits)

---

## 1. Concepts

- **Document** — a JSON object (`map[string]any`). Every document gets a
  server-generated, sortable **UUIDv7** `_id`, mirrored into the body on every
  write. You never set `_id` yourself.
- **Collection** — a named bucket of documents (think "table"). Names are
  restricted to `[A-Za-z0-9_-]+`. There is no schema; documents in a collection
  need not share any fields.
- **Store / database** — one SQLite file holding all collections in a single
  table. Use `:memory:` for an ephemeral store.
- **Schema-on-read** — you query whatever shape the documents happen to have;
  nothing is enforced on write beyond "valid JSON object".

Three ways to use it, sharing the same model:

| Layer | Package / binary | Use it when |
|---|---|---|
| Library | `github.com/pmuston/jsondb` | You're writing Go and want to embed the store in-process. |
| Server + CLI | `cmd/jsondb` (binary `jsondb`) | You want an HTTP API, an admin UI, or shell-level data tools. |
| Driver | [`github.com/pmuston/jsondb-go`](https://github.com/pmuston/jsondb-go) | A Go program needs to talk to a running server with the same API. |

---

## 2. Install & build

The quickest route to the binary is Homebrew — the tap carries pre-built
binaries for macOS and Linux, on both Intel and ARM:

```sh
brew tap pmuston/jsondb
brew trust pmuston/jsondb   # required for third-party taps
brew install jsondb
```

To build from source instead, you need **Go 1.25+** (`go.mod` declares 1.25.4).

```sh
go build ./...                    # build everything
go test ./...                     # run the test suite
go build -o jsondb ./cmd/jsondb   # build the CLI/server binary
```

> **Note:** the module root is the *library* package (no `main`). To run the
> command, target the command package, not `.`:
>
> ```sh
> go run ./cmd/jsondb version      # NOT: go run .
> ```

---

## 3. Using the library (embedding)

```go
package main

import (
	"context"
	"fmt"

	"github.com/pmuston/jsondb"
)

func main() {
	db, err := jsondb.Open("./app.sqlite") // or ":memory:"
	if err != nil {
		panic(err)
	}
	defer db.Close()

	ctx := context.Background()
	users := db.Collection("users")

	// Insert returns the generated _id.
	res, _ := users.InsertOne(ctx, jsondb.Document{
		"name": "Paul", "email": "paul@example.com", "age": 60, "tier": "gold",
	})
	fmt.Println("inserted", res.InsertedID)

	// Query.
	gold, _ := users.Find(ctx, jsondb.Filter{"tier": "gold"},
		jsondb.WithSort("age", true), jsondb.WithLimit(10))
	fmt.Println("gold members:", len(gold))

	// Index a hot path; unique enforces it across the collection.
	_ = users.CreateIndex(ctx, jsondb.IndexSpec{Paths: []string{"email"}, Unique: true})
}
```

### CRUD methods (on a `*Collection`)

The names follow the MongoDB driver, so code written against one reads the same
against the other.

| Method | Purpose |
|---|---|
| `InsertOne(ctx, doc) (*InsertOneResult, err)` | Store one document; `res.InsertedID` is its new `_id`. |
| `InsertMany(ctx, docs) (*InsertManyResult, err)` | Store many in one transaction; `res.InsertedIDs`. |
| `Find(ctx, filter, opts...) ([]doc, err)` | Query (see below). |
| `FindOne(ctx, filter, opts...) (doc, err)` | First match, or `ErrNotFound`. |
| `CountDocuments(ctx, filter) (int64, err)` | Count matches. |
| `CreateIndex(ctx, spec) error` | Create an index (see [Indexing](#indexing)). |
| `ListIndexes(ctx) ([]IndexInfo, err)` | List this collection's indexes. |
| `DropIndex(ctx, name) error` | Remove one by name; `ErrNotFound` if absent. |

**Writes by filter** (see [Updating](#updating) for the operators):

| Method | Purpose |
|---|---|
| `UpdateOne(ctx, filter, update, opts...) (*UpdateResult, err)` | Apply operators to at most one match. |
| `UpdateMany(ctx, filter, update, opts...) (*UpdateResult, err)` | Apply operators to every match. |
| `ReplaceOne(ctx, filter, doc, opts...) (*UpdateResult, err)` | Swap one whole document. |
| `DeleteOne(ctx, filter) (*DeleteResult, err)` | Remove at most one match. |
| `DeleteMany(ctx, filter) (*DeleteResult, err)` | Remove every match. |

Pass `WithUpsert()` to any of the update methods to insert when nothing matches.

**By-id conveniences.** MongoDB has no by-id methods — it writes `{"_id": …}`
filters. jsondb offers both: the filter form works and is equally fast (`_id`
resolves to the primary key), and these are shorthand for it.

| Method | Purpose |
|---|---|
| `GetByID(ctx, id) (doc, err)` | Fetch by id; `ErrNotFound` if absent. |
| `ReplaceByID(ctx, id, doc) error` | **Full replace** of the document body. |
| `PatchByID(ctx, id, fields) error` | **Shallow merge** (RFC 7396); a `null` value deletes that field. |
| `DeleteByID(ctx, id) error` | Remove by id. |

`PatchByID` is a jsondb extension with no MongoDB equivalent. `$set` covers
much of it, but whole-object merge semantics are useful in their own right.

**Collection management:**

| Method | Purpose |
|---|---|
| `Drop(ctx) error` | Delete every document and the collection's indexes. |
| `Rename(ctx, newName) error` | Move documents and indexes under a new name. |
| `Stats(ctx) (*CollectionStats, err)` | Count, stored size, index count. |

On the `*DB`: `Collection(name)` returns a handle, `ListCollections(ctx)` lists
names + counts, `Close()` closes the store.

Because a collection is a *column* rather than a table, dropping and renaming
are ordinary row operations — and "empty" and "does not exist" are the same
state, so dropping a collection that was never created is not an error.
Renaming onto a name that already holds documents is refused with
`ErrDuplicateKey` rather than silently merging the two.

### Find options

- `WithLimit(n int)` — cap the number of results.
- `WithSkip(n int)` — skip the first *n* matches (paging).
- `WithSort(path string, asc bool)` — order by a JSON path (`true` = ascending).

### Updating

An update document is made of operators, as in MongoDB. Mixing operators with
plain fields is rejected — to swap a whole document, use `ReplaceOne`.

```go
users.UpdateOne(ctx, jsondb.M{"email": "paul@example.com"}, jsondb.Document{
    "$set":  jsondb.M{"tier": "plat"},
    "$inc":  jsondb.M{"logins": 1},
    "$push": jsondb.M{"tags": "vip"},
})

// Insert when nothing matches.
users.UpdateOne(ctx, jsondb.M{"email": "new@example.com"},
    jsondb.Document{"$set": jsondb.M{"tier": "gold"}}, jsondb.WithUpsert())
```

| Operator | Effect |
|---|---|
| `$set` / `$unset` | Set a field (any JSON value) / remove it. |
| `$inc` / `$mul` | Add to / multiply a number. A missing field starts at 0, so `$inc` creates it and `$mul` yields 0. |
| `$min` / `$max` | Write only if the new value is lower / higher, or the field is absent. |
| `$rename` | Move a value to another path; a no-op if the source is missing. |
| `$currentDate` | Set to the current time. |
| `$push` / `$pop` | Append to an array (creating it if absent) / remove its last (`1`) or first (`-1`) element. |
| `$addToSet` | Append only if the value is not already present. |
| `$pull` | Remove every element equal to a value. |
| `$setOnInsert` | Apply only when an upsert creates the document. |

`UpdateResult` carries `MatchedCount`, `ModifiedCount` and `UpsertedID`.
Matched counts documents the filter selected; modified counts those whose
stored body actually changed, so rewriting a document with the values it
already holds reports `1` matched and `0` modified — the same distinction
MongoDB draws.

**Where this differs from MongoDB, deliberately:**

- **`$currentDate` writes unix epoch seconds**, an integer, because there is no
  BSON `Date` here. The `{$type: "timestamp"}` form is rejected rather than
  silently treated as something else.
- **`UpdateOne` picks the lowest `_id`** among matches. MongoDB picks an
  arbitrary one; a defined choice makes repeated calls reproducible.
- **Type conflicts are errors.** `$inc` on a string, or `$push` onto a number,
  returns `ErrInvalidUpdate` naming the path and how many documents conflict,
  rather than letting SQLite coerce. Nothing is written when it does.
- **Operators are applied to the document as it was**, not to each other's
  output, so order never matters. Two operators touching the same path are
  rejected as a conflict.
- **Upserts seed from equality conditions only.** `{"tier": "gold"}` contributes
  `tier`, but `{"age": {"$gt": 18}}` contributes nothing — there is no single
  value it implies. `$setOnInsert` fields are added, then the update's own
  operators are applied to the new document, so `$inc` and `$push` behave the
  same on an insert as on an existing document.
- **`_id` is immutable.** Any operator targeting it is rejected, and a
  replacement document's `_id` is ignored rather than honoured.

These are available from the remote client too — see
[The remote client](#7-the-remote-client).

### Indexing

Create indexes from the embedding program, the remote client, or the
`jsondb index` CLI commands — all three reach the same operations.

```go
// Single field, unique across the collection.
users.CreateIndex(ctx, jsondb.IndexSpec{Paths: []string{"email"}, Unique: true})

// Compound.
users.CreateIndex(ctx, jsondb.IndexSpec{Paths: []string{"tier", "age"}})

list, _ := users.ListIndexes(ctx)          // []IndexInfo{Name, Coll, Paths, Unique}
_ = users.DropIndex(ctx, list[0].Name) // ErrNotFound if it isn't there
```

`IndexSpec` fields: `Paths` (one or more JSON paths, in order), `Unique`, and
an optional `Name` (defaults to a derived, collision-free one). `CreateIndex`
is idempotent.

**Compound indexes are led by their first path.** An index on
`["tier", "age"]` serves filters and sorts on `tier`, and on `tier` + `age`.
Order the paths by what you filter on most.

Unlike MongoDB, whose left-prefix rule is absolute, SQLite may *also* use a
compound index for a **trailing** path alone, by skip-scanning: iterating the
distinct leading values and seeking within each. It only chooses this when the
leading path has few distinct values, so treat it as a bonus rather than
something to design around — `--explain` tells you what actually happened.

**Unique indexes are scoped to the collection**, and their NULL handling
matches MongoDB's *sparse* unique index rather than its default: a document
missing the path indexes as NULL, NULLs are all distinct, so any number of
documents may omit the path without colliding. Only documents that actually
carry the path are constrained. A violating write returns `ErrDuplicateKey`, as
does creating a unique index over data that already contains duplicates.

**Not every filter can use an index:**

| Filter | Uses an index? |
|---|---|
| implicit `=`, `$eq`, `$gt`/`$gte`/`$lt`/`$lte`, `$in` | yes |
| `WithSort` on an indexed path | yes (avoids a temp sort) |
| `$like` | only with a prefix pattern *and* matching collation |
| `$ne`, `$nin` | no — negation |
| `$exists` | no — it tests `json_type`, a different expression |

Since implicit array matching landed, an indexed path is filtered through the
multikey table rather than the expression index — that is what lets one lookup
answer both a scalar and an array element. Two consequences: indexed equality
is roughly twice the cost of the plain expression-index lookup it replaced
(19µs against 10µs on 50,000 documents, versus 18.6ms unindexed), and a
compound index no longer serves a *filter* as a single compound seek — each
path is sought separately. Compound indexes still order results without a sort,
and still enforce uniqueness.

`_id` needs no index: filters and sorts on it are rewritten to the primary key,
and `CreateIndex` on it alone is a no-op.

### Checking that an index is used

An unused index produces exactly the same results as a used one, only slower —
so verify rather than assume. `Explain` returns the plan without running the
query, and the CLI exposes it as `query --explain`:

```go
plan, _ := users.Explain(ctx, jsondb.Filter{"email": "paul@example.com"})
fmt.Println(plan)              // SEARCH docs USING INDEX ... (coll=? AND <expr>=?)
fmt.Println(plan.SeeksIndex()) // true
```

```sh
jsondb --db app.sqlite query users '{"tier":"gold"}' --explain
```

- `SeeksIndex()` — the plan narrows the search with an indexed expression or
  the primary key, rather than examining every document in the collection.
- `SortsInMemory()` — SQLite has to collect and sort results itself; an index
  covering the sort path removes it. A sorted query can read in index order
  *without* reporting a constraint, so this is a separate question from
  `SeeksIndex()`, not a rephrasing of it.

Two things that legitimately show "no index used": collections small enough
that a scan is genuinely cheaper (SQLite is right to ignore the index), and the
operators in the table above that cannot use one.

### Error sentinels

`ErrNotFound`, `ErrInvalidFilter`, `ErrInvalidJSON`, `ErrInvalidName`,
`ErrDuplicateKey`, `ErrInvalidUpdate`. Check with `errors.Is`.

---

## 4. Running the server

```sh
./jsondb serve --db ./jsondb.sqlite --addr :8080
# the bare binary defaults to "serve":
./jsondb --db ./jsondb.sqlite --addr :8080
```

| Flag | Default | Meaning |
|---|---|---|
| `--db`, `-d` | `./jsondb.sqlite` | SQLite file (`:memory:` for ephemeral). |
| `--addr`, `-a` | `:8080` | Listen address (`serve` only). |

`--db` is a **persistent flag** shared by every subcommand. The server shuts
down gracefully on SIGINT/SIGTERM. Once running:

- Admin UI — <http://localhost:8080/>
- Native query page — <http://localhost:8080/query>
- SQL query page — <http://localhost:8080/sql>
- REST API — under `/api/v1`

### Admin UI

The collection page (`/c/<name>`) browses documents and manages the collection.

**Browsing.** The filter box takes a JSON filter — the same one the library and
the REST API take, operators included. Alongside it are a **sort path** and a
direction; the pager reports the range, the filtered total and how long the
query took. Filter, sort, view and page are all held in the URL, so a view can
be bookmarked or shared and the back button works.

**Three ways to look at the results**, switched with the tree/table/json
buttons:

| View | What it is |
|---|---|
| **tree** | One collapsed line per document (`{ 7 fields }`); expand to walk the structure. Every value carries its type, and arrays and objects show their size. |
| **table** | A column per field, taken from the union of the keys on the page. Nested values collapse to `{ 2 fields }` / `[ 3 elements ]`, and a field a document does not have shows a `·`. |
| **json** | The stored document, pretty-printed. |

The types shown in the tree are **JSON's**, not MongoDB's BSON: `string`,
`number`, `boolean`, `object`, `array`, `null`. There is no `ObjectId` or
`Date` here — a date is whatever string you stored — and the tree says so
rather than implying a type the query engine would not honour.

The table's columns come from the documents on screen, not from the whole
collection. With schema-on-read there is no collection-wide answer, so paging
to a set of documents with different fields legitimately changes the columns.

**Explain.** The *Explain* button reports the plan for the query currently in
the boxes, led by a verdict: whether it **seeks an index** or **scans the
collection**, and — when sorting by something other than `_id` — whether it
sorts in memory or reads in index order. This is the only way to tell: an
unused index returns exactly the same documents as a used one.

**Manage** (collapsed until opened, since it reads statistics over the whole
collection) shows document count, stored size and average document size, and
lists the indexes with their paths. From there you can add an index — comma
separate the paths for a compound one, tick *unique* — drop one, or rename or
drop the collection.

Documents are inserted, edited and deleted from the same page; editing loads
the document into a textarea and saves a full replacement. Saving or deleting
redraws the whole result panel rather than the single row, because an edit can
add a field the table has no column for, move a document out of the current
sort order, or stop it matching the filter.

### REST API

| Method & Path | Action |
|---|---|
| `GET /api/v1/collections` | List collection names + counts. |
| `POST /api/v1/{coll}` | Insert a document → `{"id": "..."}`. |
| `POST /api/v1/{coll}/_batch` | Insert a JSON array → `{"ids": [...]}`. |
| `GET /api/v1/{coll}` | Find: `?q=<JSON filter>`, `?limit=`, `?skip=`, `?sort=path:asc\|desc`, `?count=true`. |
| `GET /api/v1/{coll}/{id}` | Get one. |
| `PUT /api/v1/{coll}/{id}` | Full replace. |
| `PATCH /api/v1/{coll}/{id}` | Shallow merge. |
| `DELETE /api/v1/{coll}/{id}` | Delete. |

**Command endpoints.** Everything the library can do by *filter* is reachable
too. These take their arguments as a JSON body rather than a query string,
because a filter is not reliably expressible in a URL — they exist to carry the
library API to the remote client, not to be used by hand.

| Method & Path | Body → Result |
|---|---|
| `POST /api/v1/{coll}/_updateOne` | `{"filter":…, "update":…, "upsert":bool}` → `UpdateResult` |
| `POST /api/v1/{coll}/_updateMany` | same → `UpdateResult` |
| `POST /api/v1/{coll}/_replaceOne` | `{"filter":…, "replacement":…, "upsert":bool}` → `UpdateResult` |
| `POST /api/v1/{coll}/_deleteOne` | `{"filter":…}` → `DeleteResult` |
| `POST /api/v1/{coll}/_deleteMany` | same → `DeleteResult` |
| `GET /api/v1/{coll}/_indexes` | → `[]IndexInfo` |
| `POST /api/v1/{coll}/_indexes` | `IndexSpec` → 204 |
| `DELETE /api/v1/{coll}/_indexes/{name}` | → 204, 404 if absent |
| `GET /api/v1/{coll}/_stats` | → `CollectionStats` |
| `POST /api/v1/{coll}/_rename` | `{"to":"newName"}` → 204 |
| `POST /api/v1/{coll}/_explain` | `{"filter":…, "limit":…, "skip":…, "sort":…}` → plan + `seeksIndex` / `sortsInMemory` |
| `GET /api/v1/_version` | → `{"apiVersion":1, "version":…}` — the intended connect check |
| `DELETE /api/v1/{coll}` | Drop the collection → 204 |

The literal `_`-prefixed segments take precedence over the `{id}` wildcard, so
only a document whose id were literally `_stats` could be shadowed — ids are
UUIDv7, so that cannot happen.

Errors return the appropriate status (400 invalid filter/JSON/update, 404 not
found, 409 duplicate key, 500 internal) with a
`{"error": "...", "code": "..."}` body. The `code` is stable — `not_found`,
`invalid_filter`, `invalid_json`, `invalid_name`, `invalid_update`,
`duplicate_key` — and is what the client maps back to its error sentinels,
rather than matching on the message text.

> **No authentication.** Everything above is available to anyone who can reach
> the port, including `DeleteMany`, `Drop` and `DropIndex`. Run it on localhost
> or a trusted network. Authentication — SCRAM with collection-scoped roles,
> in the shape MongoDB uses — is designed but not built.

```sh
# Insert, then find.
curl -s -X POST localhost:8080/api/v1/users \
  -d '{"name":"Ada","tier":"plat"}'
curl -s 'localhost:8080/api/v1/users?q=%7B%22tier%22%3A%22plat%22%7D'   # q = {"tier":"plat"} url-encoded
```

---

## 5. The CLI

Beyond `serve`, the binary works directly on a database file. All data
subcommands share `--db`.

```sh
# Import a JSON array (or single object) into a collection.
jsondb --db app.sqlite import users users.json
cat users.json | jsondb --db app.sqlite import users      # or from stdin

# Bulk-import a directory tree (see below).
jsondb --db app.sqlite importdb ./seed

# Mongo-ish query, pretty-printed (filter is optional JSON).
jsondb --db app.sqlite query users '{"tier":"gold"}' --sort=-age
jsondb --db app.sqlite query users --count

# Export a collection as a JSON array.
jsondb --db app.sqlite export users --q '{"tier":"gold"}' --limit 100 --pretty

# Native query → JSONL, with optional WHERE.
jsondb --db app.sqlite nquery "users,name,tier,_FILE:src" --where "tier = 'gold'"

# SQL SELECT → JSONL (WHERE inline).
jsondb --db app.sqlite sql "SELECT name, tier FROM users WHERE tier = 'gold'"

# Indexes and collections (also available over HTTP and from the client).
jsondb --db app.sqlite index create users email --unique
jsondb --db app.sqlite index list users
jsondb --db app.sqlite collection list
jsondb --db app.sqlite collection stats users
jsondb --db app.sqlite collection rename users people
jsondb --db app.sqlite collection drop people

# Query plan instead of results.
jsondb --db app.sqlite query users '{"tier":"gold"}' --explain

# Version.
jsondb version
```

Subcommands: `serve`, `import`, `importdb`, `export`, `query`, `nquery`, `sql`,
`index`, `collection`, `version`.

| Subcommand | Key flags / args |
|---|---|
| `import <coll> [file]` | Reads file or stdin (`-`); JSON array or single object. |
| `importdb <dir>` | Directory tree (below). |
| `query <coll> [filter]` | `--count`, `--limit`, `--skip`, `--sort`, `--explain`. Docs to stdout, summary to stderr. |
| `index list\|create\|drop` | Manage indexes on a collection (see [Indexing](#indexing)). |
| `collection list\|drop\|rename\|stats` | Manage collections. |
| `export <coll>` | `--q`, `--limit`, `--skip`, `--sort`, `--pretty`. JSON array to stdout. |
| `nquery <query>` | `--where/-w`. JSONL to stdout, `N row(s)` to stderr. |
| `sql <statement>` | WHERE is inline. JSONL to stdout. |

`--sort` is a JSON path, optionally prefixed `-` for descending (e.g.
`--sort=-createdAt`). `query`/`nquery`/`sql` write data to **stdout** and the
count summary to **stderr**, so stdout stays clean for piping (e.g. into `jq`).

### `importdb` directory layout

`importdb <directory>` walks a tree where each immediate subdirectory is a
collection and each `*.json` file in it (one level deep) is one document:

```
seed/
  users/
    alice.json     -> one document in "users"
    bob.json       -> one document in "users"
  orders/
    1001.json      -> one document in "orders"
```

Each document gets a generated `_id`, and the source file's base name (without
`.json`) is recorded in a **`_filename`** field — which is what the `_FILE`
key expression reads back. Non-`.json` files, dotfiles, and deeper nesting are
skipped.

---

## 6. Querying

jsondb offers **three** query styles, for different jobs.

### 6a. Mongo-ish filters (whole documents)

Used by `Find`/`Count`, the `query`/`export` CLI, and the REST API. A filter is
a JSON object translated into a parameterized SQL `WHERE` (values are always
bound, never interpolated).

```json
{ "email": "a@b.com", "age": { "$gte": 18, "$lte": 65 },
  "tier": { "$in": ["gold", "plat"] } }
```

| Operator | Meaning |
|---|---|
| (implicit) | Equality; multiple keys are AND-ed. |
| `$eq` / `$ne` | Equal / not equal (`$ne` is also true when the path is missing). |
| `$gt` `$gte` `$lt` `$lte` | Numeric/string comparison. |
| `$in` / `$nin` | Membership in an array. |
| `$like` | SQL `LIKE` (you supply `%` / `_`). |
| `$regex` | Go regular expression; `$options` accepts `i`, `m`, `s`. |
| `$exists` | `true` = present, `false` = absent. |
| `$type` | JSON type: `string`, `number`, `int`, `double`, `bool`, `object`, `array`, `null`. |
| `$size` | Array length. Matches arrays only, so `{"$size": 0}` finds empty arrays, not missing fields. |
| `$mod` | `[divisor, remainder]`. |
| `$all` | The array contains every listed value. |
| `$elemMatch` | A *single* array element satisfies all the criteria. |
| `$not` | Inverts an operator expression. |
| `$and` / `$or` / `$nor` | Array of sub-filters. |

Nested paths use dot notation (`"address.city"`). Returns full documents.

```go
// One element must match both criteria — not two elements matching one each.
c.Find(ctx, jsondb.M{"items": jsondb.M{
    "$elemMatch": jsondb.M{"sku": "p1", "qty": jsondb.M{"$gt": 5}},
}})

// Case-insensitive regex, either way round.
c.Find(ctx, jsondb.M{"name": jsondb.M{"$regex": "^pa", "$options": "i"}})
c.Find(ctx, jsondb.M{"name": jsondb.M{"$regex": "(?i)^pa"}})
```

### Arrays

A filter on a path matches when the value equals it **or**, if the value is an
array, when any element does — MongoDB's implicit array matching:

```go
// Matches {"tags": "x"} and {"tags": ["x", "y"]} alike.
c.Find(ctx, jsondb.M{"tags": "x"})

// Comparisons traverse too: any element over 8.
c.Find(ctx, jsondb.M{"vals": jsondb.M{"$gt": 8}})

// $ne and $nin mean *no* value matches, so an array containing "x" is excluded.
c.Find(ctx, jsondb.M{"tags": jsondb.M{"$ne": "x"}})
```

Objects are not arrays: a document with `{"tags": {"x": 1}}` is not matched by
`{"tags": 1}`. Only real arrays are traversed.

**Index the paths you match arrays on.** Without an index the traversal walks
every document; with one it is a single seek. On 50,000 documents:

| Filter | Unindexed | Indexed |
|---|---|---|
| scalar equality | 18.6ms | 19µs |
| array element match | 28.1ms | 1.7ms |

The cost is on writes, because each indexed path stores one row per array
element: inserting into a collection with two indexed paths (one an array of
three) measured ~74µs against ~45µs with no indexes. Index what you query.

**Worth knowing:**

- **`$not` and `$nor` match documents that lack the field**, as in MongoDB. A
  condition on a missing path is SQL NULL, and `NOT NULL` is NULL, so the
  negation collapses NULL to false first — otherwise these would silently drop
  exactly the documents they are meant to return.
- **`$regex` is Go's `regexp`**, registered with SQLite as the `REGEXP`
  operator, not PCRE. Patterns are compiled once and cached, an invalid one is
  rejected when the filter is built rather than part-way through a scan, and a
  non-string value simply does not match. It cannot use an index — every
  candidate row is matched in Go.
- **`$type` speaks JSON, not BSON.** `binData`, `objectId`, `date` and friends
  have no representation here and are rejected rather than silently matching
  nothing.
- **`$elemMatch`, `$all` and `$size` cannot use an index.** They walk the array
  with `json_each`.

### 6b. Native query (flat columnar rows → JSONL)

Extracts *tabular* rows from documents instead of returning whole objects. A
single comma-separated string: the first segment is `COLLECTION[.sub.path]`, the
rest are column key-expressions.

```
COLLECTION[.sub.path],keyExpr1,keyExpr2,...
```

- The path navigates into each document; **arrays are iterated** (one row per
  object element).
- Column expressions: bare `NAME` reads a field; `CHILD.KEY` descends into a
  child object; leading dots climb to ancestors (`..` = parent, `...` =
  grandparent); `_FILE` yields the document's `_filename` — set by `importdb`
  only, and always read from the document root; append `:ALIAS` to
  rename the column.

```sh
jsondb --db app.sqlite nquery \
  "modules.rects,..tag:module,name,RECT.H:height,_FILE:src" \
  --where "height >= 10 AND module LIKE 'M%'"
```

Output is **JSONL** — one JSON object per row, keys in column order:

```json
{"module":"M1","name":"a","height":"12","src":"m1"}
```

(All extracted values are strings; numbers are stringified.) Full grammar:
[`native-query.md`](../native-query/).

### 6c. SQL SELECT (JSONL)

A thin SQL front-end over the native engine — same extraction, familiar syntax:

```
SELECT col [AS alias], ... FROM collection[.sub.path] [WHERE expr]
```

```sh
jsondb --db app.sqlite sql \
  "SELECT ..tag AS module, name, RECT.H AS height, _FILE AS src
   FROM modules.rects WHERE height >= 10 AND module LIKE 'M%'"
```

The statement is rewritten to a native query (`path,col1,col2,…`) plus the
`WHERE` clause. `SELECT`/`FROM`/`AS`/`WHERE` are case-insensitive; a trailing
`;` is ignored. Columns use the same key-expression syntax as native queries.
Conversion rules: [`sql-select-syntax.md`](../sql/).

### 6d. WHERE filtering (for 6b and 6c)

The `--where` flag (native) and inline `WHERE` (SQL) share one row-filter
language applied **after** rows are extracted. Columns are referenced by their
**header/alias** name.

- Logical: `AND`, `OR`, `NOT`, parentheses.
- Comparison: `=` `!=` `<>` `<` `>` `<=` `>=`.
- `LIKE` with `%` (any run) and `_` (any char), case-insensitive.
- String literals are single-quoted: `tier = 'gold'`.
- Comparisons coerce to numbers when both sides parse as numbers, else compare
  as strings. A missing field makes the condition false.

```
height >= 10 AND (module LIKE 'M%' OR tier = 'gold')
```

Full grammar: [`where-filtering.md`](../where/).

### Choosing a query style

- **Whole documents back?** → Mongo-ish filters (6a).
- **Flat rows / spreadsheet-like extraction, piping to `jq`?** → native (6b) or
  SQL (6c).
- **Prefer SQL ergonomics?** → SQL SELECT (6c). It compiles to the native
  engine, so capabilities are identical.

---

## 7. The remote client

The driver lives in its own public repository,
[`github.com/pmuston/jsondb-go`](https://github.com/pmuston/jsondb-go). It
mirrors the library API but talks HTTP to a running server, depends only on the
standard library, and is the reference implementation of the
[wire protocol](../wire-protocol/) — the contract any other-language driver
would implement.

Its parity with the storage library is enforced from *this* repository, by
`internal/drivercompat`, which is the only place that can import both.

Use `Connect` rather than `New` when you want the version check:

```go
c, err := jsondb.Connect(ctx, "jsondb://localhost:8080")
```

Accepted schemes are `jsondb://`, `jsondbs://` (TLS), `http://` and `https://`.
A URI carrying credentials, a database path or query parameters is **rejected
with an explanation** — jsondb has one namespace, so there is no `authSource`
to honour, and silently dropping it would look like it had worked.

```go
package main

import (
	"context"
	"fmt"

	jsondb "github.com/pmuston/jsondb-go"
)

func main() {
	c := jsondb.New("http://localhost:8080")
	users := c.Collection("users")

	ctx := context.Background()
	res, _ := users.InsertOne(ctx, jsondb.Document{"name": "Ada", "tier": "plat"})
	fmt.Println("inserted", res.InsertedID)

	plat, _ := users.Find(ctx, jsondb.Filter{"tier": "plat"})
	fmt.Println("plat members:", len(plat))
}
```

**The client reaches everything the library does** — filter-based writes,
update operators, index management, collection drop/rename/stats:

```go
users.UpdateMany(ctx, jsondb.M{"tier": "gold"},
    jsondb.Document{"$inc": jsondb.M{"logins": 1}})
users.CreateIndex(ctx, jsondb.IndexSpec{Paths: []string{"email"}, Unique: true})
stats, _ := users.Stats(ctx)
```

`jsondb.Document`, `jsondb.Filter`, `jsondb.M`, the result types, the
`FindOption`s and the error sentinels deliberately mirror the `jsondb` package,
so a program can switch between embedding the library and talking to a remote
server by changing only the construction line.

That parity is enforced, not merely intended: `client/parity_test.go` compares
the two method sets by reflection and fails when they diverge. `Explain` is the
single recorded exception — a SQLite query plan is meaningless to a caller
whose planner lives on the server.

---

## 8. The web UI

With the server running, open <http://localhost:8080/>:

- **Collections** (`/`) — browse collections; open one to page through
  documents, create new ones, and edit or delete inline (HTMX, no page
  reloads).
- **Query** (`/query`) — two inputs (native query string + optional WHERE) and a
  **Run** button; results render as JSONL.
- **SQL** (`/sql`) — a single input for a full `SELECT … FROM … WHERE …`
  statement and a **Run** button; results render as JSONL.

Both query pages show parse/execution errors inline and pre-fill from URL query
params, so a query is shareable by link.

---

## 9. Tips & limits

- **Single-node, single-writer.** SQLite runs in WAL mode: concurrent reads are
  fine, but writes are serialized (the library pins one connection). There is no
  replication, sharding, or multi-master story — that's by design.
- **`_id` is yours-to-read, not yours-to-set.** It's generated on insert and
  mirrored into the body; `Patch` won't overwrite it. Filtering or sorting on
  `_id` uses the primary key directly, so it never needs an index —
  `CreateIndex("_id")` is a no-op.
- **Number precision.** Document bodies decode JSON numbers as `float64`, so
  integers beyond float64's exact range can lose precision in query/extraction
  output. Fine for typical data.
- **Index hot paths.** `CreateIndex(spec)` adds an expression index on fields
  you filter or sort on frequently — see [Indexing](#indexing) for which
  operators can actually use one. Paths are restricted to dot-separated
  `[A-Za-z0-9_]` segments (`address.city`), so `a..b` and `.a` are rejected
  rather than silently matching nothing.
- **Every index taxes every write.** Indexes live on the one shared `docs`
  table, so an index defined for one collection is still evaluated when any
  other collection is written. Add them for paths you actually query.
- **Keep stdout clean.** `query`/`nquery`/`sql` print data to stdout and the
  count to stderr, so `... | jq` and redirection just work.
- **Out of scope (v1):** aggregation pipelines, `$lookup`/joins, geo queries,
  and FTS.

---

The grammars referenced throughout have their own specifications:
[`native-query.md`](../native-query/), [`where-filtering.md`](../where/)
and [`sql-select-syntax.md`](../sql/). Writing a driver, or calling
the HTTP API directly, is covered by [`wire-protocol.md`](../wire-protocol/).
