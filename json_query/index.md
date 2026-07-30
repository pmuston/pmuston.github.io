---
title: json_query
---

[← all tools](../)

Query JSON files using a native dot-path syntax or SQL SELECT statements, with
output as CSV or JSONL.

## Install

```sh
brew tap pmuston/json_query
brew install json_query
```

After installing, `man json_query` has the full reference offline.

## Usage

```sh
json_query [flags] file...
json_query --jf parent_dir [flags]
```

| Flag | Short | Meaning |
|---|---|---|
| `--query` | `-q` | Native query string (repeatable) |
| `--queryfile` | `-f` | File of native queries, one per line |
| `--sql` | `-s` | SQL SELECT statement (repeatable) |
| `--sqlf` | | File of SQL statements, one per line |
| `--where` | `-w` | WHERE filter for native queries |
| `--format` | `-F` | Output format: `csv` (default) or `jsonl` |
| `--minimum` | `-m` | JSONL: omit keys with empty values |
| `--output` | `-o` | Output file (default: stdout) |
| `--jf` | | JSON-folder mode: parent directory of subdirectories |
| `--verbose` | | Print progress to stderr |

At least one of `--query`, `--queryfile`, `--sql`, or `--sqlf` is required.

## Query syntax

A native query is a comma-separated string:

```
PATH,keyExpr1,keyExpr2,...
```

The first segment is a dot-separated traversal path into the JSON. The remaining
segments extract values from each matched object.

| Expression | Meaning |
|---|---|
| `name` | Field on the matched object |
| `stats.score` | Navigate into child, read field |
| `..dept` | Parent's field (1 level up) |
| `...dept` | Grandparent's field (2 levels up) |
| `_FILE` | Source filename (basename) |
| `expr:ALIAS` | Rename the output column |

In `--jf` mode, the first path segment names a subdirectory; without it, the
entire path navigates the JSON.

## SQL mode

SQL SELECT statements are converted to native queries:

```sql
SELECT name, role FROM employees WHERE role = 'engineer'
```

The WHERE clause is extracted and applied as a filter. `--where` does **not**
apply to SQL queries.

## Examples

```sh
# Query files directly
json_query -q "employees,name,role" data/*.json

# SQL with WHERE
json_query -s "SELECT name, role FROM employees WHERE role = 'engineer'" data/*.json

# JSON-folder mode with aliases
json_query --jf ./data -q "departments.employees,..dept:DEPT,name,stats.score:SCORE"

# JSONL output, omitting empties
json_query -q "employees,name,role" -F jsonl -m data/*.json

# Pipe from find
find . -name '*.json' | xargs json_query -q "items,name,value"

# Write to file
json_query -q "employees,name" -o results.csv data/*.json
```

## WHERE filtering

Supports `=`, `!=`, `<>`, `<`, `>`, `<=`, `>=`, `LIKE`, `AND`, `OR`, `NOT`, and
parentheses. Numeric coercion is attempted before string comparison. LIKE is
case-insensitive (`%` = any chars, `_` = one char).

## Behaviour

- Missing keys or unreachable ancestors produce empty strings, never errors.
- Malformed JSON files are skipped with a warning (visible with `--verbose`).
- Multiple queries from all flags are combined into one output.
- Output defaults to stdout; `--output` redirects to a file.
- Progress goes to stderr, only when `--verbose` is set.

## Exit status

| Code | Condition |
|---|---|
| `0` | Success (including no matches). |
| `1` | Runtime or usage error. |

## Links

- [Source & releases](https://github.com/pmuston/homebrew-json_query)
- [User guide →](guide/)
- `json_query version` prints the build revision for bug reports.
