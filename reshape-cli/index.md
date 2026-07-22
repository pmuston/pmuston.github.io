---
title: reshape-cli
---

[← all tools](../)

Convert tabular record data between **JSON**, **JSONL**, and **CSV**. A Unix
filter: read one format, write another, stdin to stdout by default.

## Install

```sh
brew tap pmuston/reshape
brew trust pmuston/reshape   # required for third-party taps
brew install reshape-cli
```

> The installed binary is `reshape-cli`: homebrew/core already ships an
> unrelated `reshape` (a Postgres migration tool), so this one takes the `-cli`
> suffix to keep the install name unambiguous.

After installing, `man reshape-cli` has the full reference offline.

## Usage

```sh
reshape-cli [-from FMT] -to FMT [-infer] [FILE]
```

| Flag | Meaning |
|---|---|
| `-from FMT` | Input format: `json`, `jsonl`, `csv`. Optional with `FILE` (defaults to the file extension). `ndjson` aliases `jsonl`. |
| `-to FMT` | Output format (required). Same values as `-from`. |
| `-infer` | CSV input only: parse cells as numbers, `true`, `false`, and `null` where they match; otherwise keep them as strings. |
| `FILE` | Input file. Absent means stdin. Output is always stdout. |

## Examples

```sh
# JSON array → CSV
reshape-cli -from json -to csv < in.json > out.csv

# Infer input format from the file extension
reshape-cli -to jsonl data.csv > out.jsonl

# JSONL from a pipe → pretty-printed JSON
cat log.jsonl | reshape-cli -from jsonl -to json

# Parse CSV numbers/booleans instead of keeping them as strings
reshape-cli -from csv -infer -to jsonl < data.csv
```

## Behaviour

- **Numbers round-trip verbatim.** `42.5` stays `42.5`, never `42.500000` or
  `4.25e1`.
- **Record order is preserved** end to end.
- **CSV output flattens** nested objects to dotted columns (`meta.area`),
  JSON-encodes arrays into a single cell, and renders `null` as an empty cell.
  The header is the union of all flattened keys, in first-seen order.
- **CSV flattening is one-way**: converting CSV back to JSON yields literal
  dotted keys, not re-nested objects. Round trips between JSON and JSONL are
  lossless; round trips through CSV are lossy for structure.

## Exit status

| Code | Condition |
|---|---|
| `0` | Success. |
| `1` | Runtime error (unreadable file, parse error, unknown format). |
| `2` | Usage error (missing `-to`, or missing `-from` with stdin input). |

## Links

- [Source & releases](https://github.com/pmuston/homebrew-reshape)
- `reshape-cli version` prints the build revision for bug reports.
