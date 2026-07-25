---
title: graphdb
---

[← all tools](../)

An **in-memory graph database** with SQLite write-through persistence, serving a
subset of openCypher over HTTP/JSON. The whole graph lives in RAM; SQLite is the
durable store, loaded once at boot and written through on every mutation. Reads
never touch disk.

## Install

### Homebrew (macOS & Linux)

```sh
brew tap pmuston/graphdb
brew trust pmuston/graphdb   # required for third-party taps
brew install graphdb
```

### Linux / no package manager

```sh
curl -fsSL https://pmuston.github.io/install.sh | sh -s graphdb
```

Installs the binary to `~/.local/bin` and the man page alongside it — no root,
no package manager. The download is checksum-verified against the release.
Re-run to upgrade. Pin a version with `VERSION=v0.23.0`, or change the location
with `BIN_DIR=/usr/local/bin` (needs write access).

After installing either way, `man graphdb` has the full reference offline.

## Usage

```sh
graphdb [serve] [flags]        # start the HTTP server (default)
graphdb import [flags] PATH…   # bulk-load .cypher files
graphdb version                # print version and build revision
```

### Serve flags

| Flag | Meaning |
|---|---|
| `-listen ADDR` | HTTP listen address. Env `GRAPHDB_LISTEN`. Default `:8080`. |
| `-db PATH` | SQLite database, created if absent. Env `GRAPHDB_DB`. Default `graphdb.db`. |
| `-config PATH` | JSON config file. Env `GRAPHDB_CONFIG`. |
| `-auth-token TOKEN` | Bearer token required on every endpoint except `/health`. Empty disables auth. Env `GRAPHDB_AUTH_TOKEN`. |
| `-max-varlen-depth N` | Cap on variable-length path expansion. Env `GRAPHDB_MAX_VARLEN_DEPTH`. Default `15`. |
| `-query-timeout DUR` | Per-query deadline; on expiry the request fails with HTTP 504 and a write rolls back. Default `30s`. |
| `-body-limit SIZE` | Maximum request body size. Default `10M`. |

Precedence is **defaults < config file < environment < flags**.

### Import flags

| Flag | Meaning |
|---|---|
| `-db PATH` | Database to load into. Default `graphdb.db`. |
| `-dry-run` | Parse every file, write nothing — validate a batch first. |
| `-reset` | Clear the graph before importing (in-process only). |
| `-server URL` | Import via a running server's API instead of opening the database. Sends no auth header. |
| `-fail-fast` | Stop at the first error instead of reporting at the end. |

## Examples

Start a server and wait for it to finish loading:

```sh
graphdb -db plant.db -listen :8080 &
until curl -sf localhost:8080/health | grep -q '"ready":true'; do sleep 0.2; done
```

Validate a batch of Cypher files before committing to it, then load them:

```sh
graphdb import -dry-run ./seed/
graphdb import -reset -db plant.db ./seed/
```

Query it:

```sh
curl -s -XPOST localhost:8080/cypher \
  -d '{"query":"MATCH (p:Person) RETURN p.name AS name LIMIT 5"}'
```

Declare an index on a hot lookup property — the main runtime speed lever, since
it turns a label scan into a seek:

```sh
curl -s -XPOST localhost:8080/indexes -d '{"label":"Person","prop":"name"}'
```

## Endpoints

| Endpoint | Purpose |
|---|---|
| `POST /cypher` | Execute one statement. Reads and writes dispatched automatically. |
| `GET /` | Discovery: version, build provenance, and a `features` list. |
| `GET /health` | Liveness and readiness. Auth-exempt. |
| `GET /stats` | Counts, label and type histograms, declared indexes. |
| `POST /indexes` | Declare a `(label, property)` index. Idempotent. |
| `POST /nodes`, `GET /nodes/:id` | REST convenience CRUD. |
| `POST /edges`, `GET /edges/:id` | Likewise for relationships. |

There are no DELETE routes — deletion goes through `/cypher`.

## Behaviour

**One statement is one transaction.** A write either applies fully, in memory and
on disk, or not at all. There are no multi-statement transactions, so a retried
write is not idempotent unless expressed with `MERGE`.

**Feature-detect, don't infer from the version.** `GET /` returns a `features`
list; clients should check it rather than assume support from a version number.

```sh
curl -s localhost:8080/ | jq '{version, features}'
```

**Reads scale across cores** — they hold a shared lock and never touch disk. A
write takes an exclusive lock only for the duration of its SQLite commit, tens of
microseconds.

**Property values** are scalars (integer, float, boolean, string, null) or lists
of those. Maps exist only as query values and cannot be stored.

## Exit status

| Code | Meaning |
|---|---|
| `0` | Success — including `-h`, which prints usage and exits cleanly. |
| `1` | Startup failure (database unopenable, address in use), or an import in which at least one file failed. |

## Reference

The repository carries the detailed specifications: the Cypher language
reference, the client interface contract, the Neo4j parity matrix, and a
user guide whose examples are all verified against a running server.

[Source & releases](https://github.com/pmuston/homebrew-graphdb)
