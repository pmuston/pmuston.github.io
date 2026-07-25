---
title: gq
---

[← all tools](../)

Run a single Cypher statement against a **graphdb** server and stream the result
to stdout as **CSV** or **JSON Lines**. No UI, no config file — one invocation
runs one statement and emits one clean result stream.

`gq` is the graphdb-backed peer of [cyq](../cyq/): the same flag surface and the
same output shaping, so `graphdb + gq` is a drop-in analogue of `neo4j + cyq`.
The only difference is the connection layer — graphdb speaks HTTP with a bearer
token, where cyq speaks Bolt with a user and password.

## Install

```sh
brew tap pmuston/gq
brew trust pmuston/gq   # required for third-party taps
brew install gq
```

After installing, `man gq` has the full reference offline.

## Usage

```sh
gq [connection flags] (--query "..." | -f PATH | < stdin) [--format csv|jsonl]
```

| Flag | Meaning |
|---|---|
| `--url BASE` | Server base URL. Env `GQ_URL`. Default `http://localhost:8080`. |
| `--token T` | Bearer token, when graphdb has auth on. Env `GQ_TOKEN`; flag wins. |
| `--timeout DUR` | Client-side HTTP timeout (Go duration, e.g. `60s`). Default `60s`. |
| `--query, -q STR` | Cypher statement. Mutually exclusive with `--file`. |
| `--file, -f PATH` | Read the statement from a file. Neither given → read stdin. |
| `--param name=json` | Repeatable. JSON value, so a string needs quotes: `--param 'tag="U-100"'`. |
| `--params-json STR` | Whole parameter object as one JSON literal. |
| `--params-file PATH` | Whole parameter object from a JSON file. |
| `--format FMT` | `csv` (default) or `jsonl`. |
| `--cells MODE` | CSV only: `friendly` (labels, default) or `json` (full fragment per cell). |
| `--no-header` | Omit the CSV header row. |
| `--bom` | Prepend a UTF-8 BOM (CSV only; helps Excel detect the encoding). |
| `--out, -o PATH` | Write to a file instead of stdout. |
| `--eid-prefix S` | Prefix every element ID, for co-streaming with another source. |
| `--quiet` | Suppress the `rows=N elapsed=Xms` summary on stderr. |

`--params-json` and `--params-file` are mutually exclusive; `--param` entries
layer on top, overriding by key.

## Examples

```sh
# CSV to stdout (the default)
gq -q "MATCH (u:Unit)-[r:CONTAINS]->(a) RETURN u, r, a"

# A scalar aggregate, emitted like any other column
gq -q "MATCH ()-[r]->() RETURN count(r) AS rels"

# JSON Lines for gfig map, with a typed parameter
gq --format jsonl --param 'tag="U-100"' \
   -q 'MATCH (u:Unit {Tag: $tag})-[:CONTAINS*0..]->(a)-[r:CONTAINS]->(b)
       RETURN a, r, b ORDER BY id(a), id(r)'

# Excel-ready CSV to a file
gq --bom -o parts.csv -q "MATCH (p:Part) RETURN p ORDER BY p.Name"
```

## Behaviour

- **Shapes everything, filters nothing.** Every column of every row is emitted:
  nodes, edges and paths as fragments; scalars, nulls and non-graph objects
  pass through. A downstream consumer such as `gfig map` applies its own
  skip/error policy. JSONL output is byte-identical to cyq's modulo element-ID
  values.
- **Graph-aware rendering.** JSON Lines tags each graph value with a `kind`
  discriminator (`node`, `edge`, `path`) and gives nodes a `displayLabel`;
  friendly CSV collapses a node to that label, an edge to its type, a path to
  `A —TYPE→ B`, and `--cells json` emits the full fragment per cell.
- **Number fidelity.** Integers beyond 2⁵³ and the integer/float distinction
  (`34` vs `34.0`) survive verbatim — values are never routed through a float.
- **Clean stdout/stderr split.** Only result data goes to stdout; the
  `rows=N elapsed=Xms` summary goes to stderr, where it never pollutes a pipe.
  `--quiet` silences it.
- **Flag beats env beats default.** An explicit flag wins over `GQ_URL` /
  `GQ_TOKEN`, which win over the built-in defaults.
- **Requires graphdb 0.18.0+.** gq reads `GET /` on connect and refuses to run
  against an older server, which would silently mis-answer some queries.

## Exit status

| Code | Condition |
|---|---|
| `0` | Success. |
| `1` | Usage error (bad flags, an exclusive combo, an empty statement, malformed params JSON). |
| `2` | Cypher syntax or other statement error from graphdb. |
| `3` | Connection, authentication, or other server fault — including a server below 0.18.0. |
| `4` | The `--timeout` deadline ended the attempt. |
| `5` | I/O error reading input or writing output. |

## Links

- [Source & releases](https://github.com/pmuston/homebrew-gq)
- `gq version` prints the build revision for bug reports.
