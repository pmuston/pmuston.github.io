---
title: cyq
---

[← all tools](../)

Run a single **read-only** Cypher query against a Neo4j database and stream the
result to stdout as **CSV** or **JSON Lines**. No UI, no config file — one
invocation runs one query and emits one clean result stream.

## Install

```sh
brew tap pmuston/cyq
brew trust pmuston/cyq   # required for third-party taps
brew install cyq
```

After installing, `man cyq` has the full reference offline.

## Usage

```sh
cyq [flags] [--query "..." | --file PATH | < stdin]
```

| Flag | Meaning |
|---|---|
| `--uri URI` | Neo4j bolt URI. Env `NEO4J_URI`. Default `bolt://localhost:7687`. |
| `--user NAME` | Neo4j username. Env `NEO4J_USER`. Default `neo4j`. |
| `--password SECRET` | Neo4j password. Env `NEO4J_PASSWORD`. Required — prefer the env var so it stays out of shell history. |
| `--database NAME` | Neo4j database. Env `NEO4J_DATABASE`. Default `neo4j`. |
| `--timeout DUR` | Per-query timeout (Go duration, e.g. `30s`). Default `30s`. |
| `--query, -q STR` | Cypher query string. Mutually exclusive with `--file`. |
| `--file, -f PATH` | Read Cypher from a file. Neither `-q` nor `-f` given → read from stdin. |
| `--params-json STR` | JSON object of Cypher parameters, preserving native types. |
| `--params-file PATH` | File holding the JSON parameters object. |
| `--format FMT` | `csv` (default) or `jsonl`. |
| `--cells MODE` | CSV only: `friendly` (display labels, default) or `json` (full JSON per cell). |
| `--no-header` | Omit the CSV header row. |
| `--bom` | Prepend a UTF-8 BOM (CSV only; helps Excel detect the encoding). |
| `--out, -o PATH` | Write to a file instead of stdout. |
| `--quiet` | Suppress the `rows=N elapsed=Xms` summary on stderr. |

## Examples

```sh
# CSV to stdout
cyq --password "$NEO4J_PASSWORD" -q "MATCH (p:Person) RETURN p.name, p.age LIMIT 10"

# Structured JSON Lines through jq
cyq --format jsonl -q "MATCH (n) RETURN n LIMIT 5" | jq .

# Query from a file, with typed parameters
cyq -f query.cypher --params-json '{"since": 2020}'

# Read from a pipe, Excel-ready CSV to a file
echo "MATCH (n) RETURN n LIMIT 100" | cyq --bom -o out.csv
```

## Behaviour

- **Streaming by design.** Rows emit one at a time, so memory stays flat on any
  result size. Cap large sets with `LIMIT` in the Cypher — there is no
  `--max-rows` flag.
- **Clean stdout/stderr split.** Only result data goes to stdout; the
  `rows=N elapsed=Xms` summary goes to stderr, where it never pollutes a pipe.
  `--quiet` silences it.
- **Graph-aware rendering.** Nodes, relationships, and paths render
  consistently. JSON Lines output tags each with a `kind` discriminator
  (`node`, `edge`, `path`); friendly CSV collapses them to a display label, and
  `--cells json` emits the full structure per cell.
- **Read-only at the driver.** The query runs in the driver's read access mode.
  `cyq` does not parse Cypher to reject writes — pair it with a read-only
  database user if that guarantee matters.
- **Flag beats env beats default.** An explicit flag always wins over the
  matching `NEO4J_*` variable, which wins over the built-in default.

## Exit status

| Code | Condition |
|---|---|
| `0` | Success. |
| `1` | Usage/input error (bad flags, exclusive combo, empty query, missing password, malformed params JSON). |
| `2` | Cypher syntax or other client error from the database. |
| `3` | Driver, connection, or authentication failure. |
| `4` | The `--timeout` deadline ended the attempt — a query that ran too long, or a host that never answered. A connection that actively fails (refused, reset) is `3`. |
| `5` | I/O error reading input or writing output. |

## Links

- [Source & releases](https://github.com/pmuston/homebrew-cyq)
- `cyq version` prints the build revision for bug reports.
