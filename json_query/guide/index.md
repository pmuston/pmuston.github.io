---
title: json_query User Guide
---

[← json_query](../)

# json_query User Guide

`json_query` is a command-line tool for extracting data from collections of JSON files. It supports a native dot-path query syntax and SQL SELECT statements, with output in CSV or JSONL format.

## Installation

```bash
go build -o json_query .
```

## Quick Start

Query JSON files by passing them as trailing arguments:

```bash
json_query -q "employees,name,role" data/*.json
```

This navigates to the `employees` key in each file and extracts the `name` and `role` fields from every matched object. Results are written to stdout by default (use `--output/-o` to write to a file instead).

If your JSON files are organised in subdirectories by element type, use `--jf` (json-folder mode) to discover them automatically:

```
data/
  departments/
    engineering.json
    marketing.json
  projects/
    config.json
```

```bash
json_query --jf ./data -q "departments.employees,name,role"
```

In `--jf` mode the first path segment (`departments`) names a subdirectory under the given parent directory; all `*.json` files in that subdirectory are queried.

## Command-Line Flags

| Flag | Short | Description |
|---|---|---|
| `--query` | `-q` | Native query string (repeatable) |
| `--queryfile` | `-f` | File containing native queries, one per line |
| `--sql` | `-s` | SQL SELECT statement (repeatable) |
| `--sqlf` | | File containing SQL statements, one per line |
| `--where` | `-w` | WHERE filter applied to all native queries |
| `--format` | `-F` | Output format: `csv` (default) or `jsonl` |
| `--minimum` | `-m` | JSONL only: omit keys with empty string values |
| `--output` | `-o` | Output file path (default: stdout) |
| `--jf` | | JSON-folder mode: parent directory whose subdirectories contain .json files |
| `--verbose` | | Print progress/diagnostics to stderr (silent otherwise) |

At least one of `--query`, `--queryfile`, `--sql`, or `--sqlf` is required.

### Output destination

By default, query results are written to **stdout**, so you can pipe or redirect them:

```
json_query -q "..." *.json > results.csv
json_query -q "..." *.json | column -t -s,
```

Supplying `--output/-o` writes to a file instead:

```
json_query -q "..." *.json -o results.csv
```

## Native Query Syntax

A query is a comma-separated string:

```
PATH,field1,field2,...
```

### Path

The first segment (before the first comma) is a dot-separated path that navigates into the JSON structure.

```bash
# Navigate into each employees object
json_query -q "employees,name" data/*.json
```

In `--jf` mode, the first path segment names a subdirectory instead:

```bash
# departments is a subdirectory; employees is the JSON path
json_query --jf ./data -q "departments.employees,name"
```

### Field Expressions

Each remaining segment extracts a value from the matched object.

**Direct field** — read a key from the matched object:

```
name
role
```

**Child navigation** — descend into nested objects using dots:

```
address.city       # read city from the address child object
CHILD.GRAND.KEY    # two levels deep
```

**Ancestor access** — climb up the JSON tree using leading dots:

```
..dept             # parent's dept field (1 level up)
...dept            # grandparent's dept field (2 levels up)
....dept           # 3 levels up
```

The number of levels up equals the number of leading dots minus one.

**Combined ancestor + child** — climb up, then navigate down:

```
..SIBLING.KEY      # go to parent, descend into SIBLING, read KEY
```

**Source filename** — the special key `_FILE` returns the basename of the JSON file:

```
_FILE
```

### Column Aliases

Append `:ALIAS` to any field expression to rename the output column:

```
..dept:DEPARTMENT      # column header becomes DEPARTMENT
address.city:CITY      # column header becomes CITY
_FILE:SOURCE           # column header becomes SOURCE
```

Without an alias, the column header is the expression as written (e.g. `..dept`, `address.city`).

### Full Example

```bash
json_query -q "employees,..dept:DEPT,name,address.city:CITY,_FILE:SOURCE" data/departments/*.json
```

Produces a CSV like:

```
DEPT,name,CITY,SOURCE
Engineering,Alice,London,engineering.json
Engineering,Bob,Paris,engineering.json
Marketing,Charlie,Berlin,marketing.json
```

## SQL Query Syntax

As an alternative to native syntax, you can write SQL SELECT statements:

```sql
SELECT column [AS alias], ... FROM element.sub.path [WHERE expr]
```

- `SELECT`, `FROM`, and `WHERE` are case-insensitive.
- Column expressions use the same syntax as native key expressions.
- `AS` provides a column alias (same as `:ALIAS` in native syntax).
- A trailing semicolon is optional and ignored.

### Examples

```bash
# Basic SQL query
json_query -s "SELECT name, role FROM employees" data/*.json

# With aliases and WHERE
json_query -s "SELECT ..dept AS DEPT, name, salary AS SALARY \
  FROM employees WHERE SALARY > 50000" data/*.json

# Case-insensitive keywords
json_query -s "select name from employees where role = 'engineer'" data/*.json

# Using --jf mode (first path segment names a subdirectory)
json_query --jf ./data -s "SELECT name, role FROM departments.employees"
```

SQL queries carry their own WHERE clause. The `--where` flag does **not** apply to SQL queries.

## WHERE Filtering

WHERE filters rows after extraction. They can be provided:

- Inline in SQL queries (`SELECT ... WHERE expr`)
- Globally via `--where` for native queries

### Operators

| Operator | Description |
|---|---|
| `=` | Equal |
| `!=` or `<>` | Not equal |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less than or equal |
| `>=` | Greater than or equal |
| `LIKE` | Pattern match (case-insensitive) |

### Logic

Combine conditions with `AND`, `OR`, `NOT`, and parentheses:

```bash
# Simple comparison
--where "role = 'engineer'"

# Numeric comparison
--where "SALARY > 50000"

# Combined
--where "role = 'engineer' AND SALARY > 50000"

# OR
--where "role = 'engineer' OR role = 'designer'"

# NOT
--where "NOT role = 'manager'"

# Parentheses
--where "(role = 'engineer' OR role = 'designer') AND SALARY > 50000"
```

### LIKE patterns

`%` matches any sequence of characters, `_` matches a single character:

```bash
--where "name LIKE 'A%'"       # matches Alice, etc.
--where "name LIKE '%li%'"     # matches Alice, Charlie
```

LIKE matching is case-insensitive.

### Numeric coercion

When both sides of a comparison can be parsed as numbers, the comparison is numeric. Otherwise it falls back to string comparison. Integer values are compared as integers (e.g. `100` not `100.0`).

### Column names in WHERE

WHERE expressions reference column names as they appear in the output headers. If you used an alias, use the alias name in WHERE:

```bash
# The alias SALARY is used in WHERE, not salary
json_query -s "SELECT salary AS SALARY FROM employees WHERE SALARY > 50000" data/*.json
```

## Query Files

For complex or reusable queries, put them in a file (one per line):

```
# queries.txt
# Lines starting with # are comments, blank lines are ignored

employees,..dept:DEPT,name,role
employees,name,address.city:CITY,address.country:COUNTRY
```

```bash
json_query -f queries.txt data/*.json
```

SQL queries work the same way with `--sqlf`:

```
# queries.sql
SELECT name, role FROM employees WHERE role = 'engineer';
SELECT ..dept AS DEPT, name FROM employees;
```

```bash
json_query --sqlf queries.sql data/*.json
```

## Combining Multiple Queries

All query flags can be used together in a single invocation. Queries are processed in order: `--query`/`--queryfile` first, then `--sql`/`--sqlf`. All results are combined into one output file.

```bash
json_query \
  -q "employees,name,role" \
  -s "SELECT name FROM employees WHERE role = 'engineer'" \
  -o combined.csv \
  data/*.json
```

The output header is taken from the first query. All subsequent rows are appended using those same columns.

## Output Formats

### CSV (default)

Standard CSV with a header row. Missing or null values produce empty strings.

```bash
json_query -q "employees,name,role" -F csv data/*.json
```

### JSONL

One JSON object per line. Each object's keys are the column headers.

```bash
json_query -q "employees,name,role" -F jsonl data/*.json
```

Output:

```json
{"name":"Alice","role":"engineer"}
{"name":"Bob","role":"designer"}
```

With `--minimum`, keys whose value is an empty string are omitted:

```bash
json_query -q "employees,name,role,MISSING_FIELD" -F jsonl -m data/*.json
```

## Progress Output

With `--verbose`, `json_query` prints progress information to stderr (without it, stderr stays silent so stdout carries only the query results):

```
Query : departments.employees,..dept:DEPT,name,address.city:CITY
Source: data/departments  (2 file(s))
  engineering.json: 2 match(es)
  marketing.json: 1 match(es)
  3 row(s)
```

The `Output written to: <path>  [csv]` line appears only when `--output/-o` directs results to a file.

When a WHERE filter is active, it shows how many rows were kept:

```
  WHERE 'SALARY > 50000': 2/3 row(s) kept
```

If no matches are found across all queries, it prints `No matches found.` and exits with code 0.

## Error Handling

| Situation | Behaviour |
|---|---|
| No query flags provided | Prints usage and exits with error |
| No files and no `--jf` | Prints error and exits |
| Both files and `--jf` given | Prints error and exits |
| `--jf` parent directory missing | Prints error and exits |
| `--jf` element subdirectory missing | Prints error and exits |
| `--jf` no JSON files in element dir | Prints error and exits |
| Malformed JSON file | Skips the file with a warning, continues |
| Invalid SQL syntax | Prints error and exits |
| Query/SQL file not found | Prints error and exits |
| Invalid WHERE expression | Prints error and exits |

## JSON-Folder Mode (`--jf`)

When JSON files are organised in subdirectories by element type, `--jf` discovers them automatically:

```
parent_dir/
  departments/
    file1.json
    file2.json
  projects/
    file1.json
```

```bash
json_query --jf parent_dir -q "departments.PATH,field1,field2"
```

The first segment of the query path names a subdirectory. All `*.json` files in that subdirectory are read and queried. Files are processed in alphabetical order. `--jf` and file arguments are mutually exclusive.
