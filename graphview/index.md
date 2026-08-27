---
title: graphview
---

[← all tools](../)

A **web-based graph viewer for Neo4j**. Write Cypher, get a WebGL graph you can
pan, zoom and filter — plus table, tree and raw JSON views of the same result. A
single binary with the frontend embedded, so it runs on an isolated network with
no build step and no internet access.

## Install

### Homebrew (macOS & Linux)

```sh
brew tap pmuston/graphview
brew trust pmuston/graphview   # required for third-party taps
brew install graphview
```

### Linux / no package manager

```sh
curl -fsSL https://pmuston.github.io/install.sh | sh -s graphview
```

Installs the binary to `~/.local/bin` and the man page alongside it — no root,
no package manager. The download is checksum-verified against the release.
Re-run to upgrade. Pin a version with `VERSION=v0.1.1`, or change the location
with `BIN_DIR=/usr/local/bin` (needs write access).

After installing either way, `man graphview` has the full reference offline.

## Usage

```sh
graphview [flags]     # start the server
graphview version     # print version and build revision
```

Point a browser at <http://127.0.0.1:8080>. A Neo4j password is required — from
`graphview.yaml`, `NEO4J_PASSWORD`, or `--neo4j-pass` — and the binary exits at
startup without one.

| Flag | Meaning |
|---|---|
| `--addr HOST:PORT` | Bind address. Default `127.0.0.1:8080` |
| `--config FILE` | Config file, instead of searching the default locations |
| `--neo4j-uri URI` | Bolt URI. Default `bolt://localhost:7687` |
| `--neo4j-user NAME` | Username. Default `neo4j` |
| `--neo4j-pass PASSWORD` | Password. Better set via config or environment |
| `--neo4j-db NAME` | Database. Default `neo4j` |
| `--max-nodes N` | Node ceiling per result. Default `50000` |
| `--max-edges N` | Edge ceiling per result. Default `200000` |
| `--max-rows N` | Record ceiling for table/raw. Default `50000` |
| `--timeout DURATION` | Per-query timeout. Default `30s` |
| `--log-level LEVEL` | `debug`, `info`, `warn`, `error`. Default `info` |
| `--library-enabled` | Enable the saved-queries library. Off by default |
| `--library-dir DIR` | Saved-query directory. Default `./queries` |

Flags take two dashes — `-addr` will not parse.

## Examples

```sh
# local database, password from the environment
NEO4J_PASSWORD=secret graphview

# another port, with the saved-queries library on
graphview --addr 127.0.0.1:9000 --library-enabled --library-dir ~/queries

# explicit config file, larger result ceiling
graphview --config /etc/graphview/graphview.yaml --max-nodes 200000
```

## The four views

Every result is available four ways, from one response.

**Graph** renders with level-of-detail — labels and edges thin out as you zoom
out, so a large result stays responsive. Click a node to inspect its properties;
filter by category from the sidebar with OR/AND.

**Table** shows one row per record, with node cells clickable through to the
details panel. Exports CSV.

**Tree** builds an indented outline with search, expand/collapse, full keyboard
navigation, and a badge on nodes reachable by more than one path.

**Raw** is the JSON response as returned.

A **Schema** panel lists the database's labels, relationship types and property
keys; click one to write a starter query into the editor. An optional **Library**
panel keeps saved queries as one YAML file each on disk — taggable, and
importable or exportable as a zip.

## Making nodes readable

Labels are shaped server-side, so how nodes read is an operator decision rather
than something each user re-does. Four optional keys in `graphview.yaml`:

| Key | Effect |
|---|---|
| `display:` | Per-label templates — `RtAttribute: "{Name} ({Type})"` |
| `category:` | Group by a property's *value* instead of by label |
| `acronyms:` | Short type prefix shown before each node label |
| `superclass_labels:` | Demote base classes like `Node` so the specific label wins |

The installed `graphview.example.yaml` documents every key with examples.

## Security

**graphview has no authentication, no authorisation and no rate limiting.**
Anyone who can reach the port can read the whole database. It binds loopback by
default — keep it there and put a reverse proxy in front for TLS and auth. Every
release ships a `deploy/` directory with a working Caddy example.

It does not inspect Cypher to reject writes, which is unreliable. Instead every
query runs inside a Neo4j read transaction, so the database itself refuses
writes. A read-only database user is the intended second fence — but **Neo4j
Community Edition cannot provide one**, having no role-based access control, so
there every user is full-access and the read transaction is the only fence. The
shipped `deploy/README.md` covers what to do instead.

Query logging records parameter *keys* only, never values.

## Exit status

| Code | Condition |
|---|---|
| `0` | Clean shutdown, or `--help` / `version` |
| `1` | Startup failed (bad flags, missing password, driver error) or the server errored |

## Links

- [Source & releases](https://github.com/pmuston/homebrew-graphview)
- `graphview version` prints the build revision for bug reports.
