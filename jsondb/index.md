---
title: jsondb
---

[← all tools](../)

A **MongoDB-lite JSON document store** on SQLite. Schema-on-read documents,
Mongo-shaped filters and update operators, real indexes — in a single static
binary with no CGo, no server to provision and nothing else to install. Use it
embedded as a Go library, or run it as an HTTP server with a browser admin UI.

## Install

### Homebrew (macOS & Linux)

```sh
brew tap pmuston/jsondb
brew trust pmuston/jsondb   # required for third-party taps
brew install jsondb
```

After installing, `man jsondb` has the full reference offline. The
[user guide](guide/) is the example-driven tour of the library, the CLI and the
HTTP API. Writing a client is covered by the [wire protocol](wire-protocol/),
with [`openapi.yaml`](openapi.yaml) as its machine-readable companion. The two
extraction dialects have their own grammars:
[native query](native-query/), [WHERE filtering](where/) and
[SQL SELECT](sql/).

## Usage

```sh
jsondb [serve] [-a ADDR]              # start the HTTP server (the default)
jsondb import COLLECTION [FILE]       # load a JSON array or object
jsondb importdb DIRECTORY             # load a tree of per-file documents
jsondb export COLLECTION [flags]      # write a collection out as JSON
jsondb query COLLECTION [FILTER]      # find documents, or --count / --explain
jsondb nquery QUERY [-w WHERE]        # native path syntax, emits JSONL
jsondb sql "SELECT …"                 # SQL SELECT front end, emits JSONL
jsondb index   {create|list|drop} …   # manage indexes
jsondb collection {list|stats|rename|drop} …
jsondb version                        # print version and build revision
```

`--db PATH` (`-d`) is shared by every subcommand and defaults to
`./jsondb.sqlite`; `:memory:` gives an ephemeral store. `--addr` (`-a`) belongs
to `serve` and defaults to `:8080`.

### Query flags

| Flag | Meaning |
|---|---|
| `--sort PATH` | Sort by a JSON path; prefix `-` to descend. |
| `--limit N` / `--skip N` | Page the result. |
| `--count` | Print how many matched, not the documents. |
| `--explain` | Print the query plan instead of running the query. |
| `--pretty` | Pretty-print (`export` only). |
| `--q FILTER` | Filter (`export` only; `query` takes it positionally). |

Data goes to **stdout** and counts and status to **stderr**, so piping into
`jq` needs no filtering of status lines.

## Examples

```sh
# Load, then query with a Mongo-shaped filter
jsondb --db app.sqlite import users users.json
jsondb --db app.sqlite query users '{"tier": "gold"}'
jsondb --db app.sqlite query users '{"age": {"$gte": 18}}' --count

# Index a hot path, then confirm the planner actually uses it
jsondb --db app.sqlite index create users tier
jsondb --db app.sqlite query users '{"tier": "gold"}' --explain

# Flatten nested documents into rows, in either dialect
jsondb --db app.sqlite nquery "orders.lines,..id:order,sku,qty" -w "qty > 1"
jsondb --db app.sqlite sql "SELECT sku, qty FROM orders.lines WHERE qty > 1"

# Serve the REST API and admin UI
jsondb --db app.sqlite serve --addr 127.0.0.1:8080
```

## Behaviour

**Collections are free.** A collection is a column value, not a table, so
creating one costs nothing and "empty" and "does not exist" are the same state.
Every document gets a sortable UUIDv7 `_id`, mirrored into its body on write.

**Array matching is implicit**, as in MongoDB: `{"tags": "x"}` matches both the
value `"x"` and the array `["x", "y"]` — and it stays indexable, because a
shadow table holds one entry per array element.

**An index that is not used returns the same rows as one that is**, which is
why `--explain` exists. It reduces SQLite's plan to the two questions worth
asking: does this seek an index, and does it sort in memory.

**Unique indexes are sparse**, again matching MongoDB: documents missing the
indexed path never collide with each other.

**One writer.** SQLite in WAL mode with a single connection — concurrent reads,
serialised writes. Single-node by design: no replication, no sharding.

**There is no authentication.** Anything that can reach the port can read and
delete, `DeleteMany` and `Drop` included. Bind it to localhost or a trusted
network.

**The HTTP API is versioned** at `/api/v1`, and `GET /api/v1/_version` is the
intended connect check — it reports the API version, the build and the commit.
Branch on `apiVersion`, not the release number; the two move independently.

## Writing a client

Go programs use **[jsondb-go](https://github.com/pmuston/jsondb-go)**, the
driver — public, standard-library only, and mirroring the library's API so a
remote program gets the same surface as an embedder:

```go
c, err := jsondb.Connect(ctx, "jsondb://localhost:8080")
docs, err := c.Collection("users").Find(ctx, jsondb.Filter{"tier": "gold"})
```

For any other language, the [wire protocol](wire-protocol/) is the specification
and [`openapi.yaml`](openapi.yaml) the machine-readable shapes.

## Exit status

| Code | Meaning |
|---|---|
| `0` | Success — including `-h`, which prints usage and exits cleanly. |
| `1` | Runtime error; the message is on stderr. |

## Links

- [Source & releases](https://github.com/pmuston/homebrew-jsondb)
- [jsondb-go](https://github.com/pmuston/jsondb-go) — the Go driver
- `jsondb version` prints the build revision, for bug reports.
