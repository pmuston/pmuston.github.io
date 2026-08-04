---
title: json_find
---

[← all tools](../)

Find where a fragment lives in a JSON corpus — half a key name, a value you saw
in a log once, a term from a spec — and whether it is there at all. Pairs with
[json_query](../json_query/): find it, then query it.

## Install

```sh
brew tap pmuston/json_find
brew trust pmuston/json_find
brew install json_find
```

After installing, `man json_find` has the full reference offline. The
[user guide](guide/) is the long-form introduction.

## Usage

```sh
json_find [flags] PATTERN [path...]
json_find [flags] PATTERN --jf parent_dir
```

`PATTERN` is never a path expression. There is no invocation in which you must
already know where to look — not knowing is why you are here. With no `path`,
the current directory is searched recursively.

```console
$ json_find ASSET_TAG data/
json_find "ASSET_TAG" — 3 shapes · 63 hits · 4 files

sites[].ASSET_TAG              key    exact       18 hits · 2 files
  values   "SiteA", "SiteB", "SiteC", … (18 distinct)
  files    plant.json (9), annex.json (9)
  → json_query -q "sites,ASSET_TAG,_FILE" -- data/plant.json data/annex.json

equipment.area.ASSET_TAG_NAME  key    substring   12 hits · 3 files
  values   "Main Reactor", "Boiler House 3", … (12 distinct)
  → json_query -q "equipment.area,ASSET_TAG_NAME,_FILE" -- data/plant.json

Searched 4 files (2.1 MB) in 41ms. Skipped 0.
```

## How to read a result

Results are grouped by **shape** — the location with array indices elided — so
`sites[0].tag` and `sites[1].tag` collapse into `sites[].tag` with a count. The
`[]` marker is the useful part: it says the structure *repeats*.

| Column | Meaning |
|---|---|
| shape | where it lives, indices elided |
| surface | what matched: a `key`, a `value`, or a `file` name |
| tier | how well it matched — see below |
| counts | hits, and how many files they span |

Each group ends in a `json_query` command. That is the point of the tool: its
terminal success state is a path expression you can paste.

## Match tiers

Matching is tiered, not boolean. Every tier is active at once and each result
reports the best it achieved, so near-misses are findings rather than noise.

| Tier | Pattern `ASSET_TAG` also finds |
|---|---|
| `exact` | `ASSET_TAG` |
| `iexact` | `asset_tag` |
| `substring` | `ASSET_TAG_NAME` |
| `normalized` | `assetTag`, `asset-tag` |
| `fuzzy` | `ASSET_TGA` |

Fuzzy applies to keys and filenames only unless `--fuzzy-values` is given, and
is off entirely for patterns of four characters or fewer. Cap the ladder with
`--exact` or `--max-tier`.

## Flags

| Flag | Short | Meaning |
|---|---|---|
| `--regex` | `-r` | Treat PATTERN as a Go RE2 regex |
| `--exact` | `-x` | Cap at the exact/iexact tiers |
| `--case-sensitive` | `-s` | Match case-sensitively |
| `--max-tier` | | Cap the tier ladder |
| `--fuzzy-values` | | Allow fuzzy matching on values too |
| `--keys` | `-k` | Narrow to the key surface |
| `--values` | | Narrow to the value surface |
| `--filenames` | | Narrow to the filename surface |
| `--under` | `-u` | Narrow to shapes containing this segment run |
| `--type` | `-t` | Narrow by JSON type: `string`, `number`, `bool`, `null` |
| `--file` | | Narrow to files whose basename matches a glob |
| `--limit` | `-n` | Show at most N groups |
| `--format` | `-F` | `text` (default), `json`, `jsonl`, `paths` |
| `--tree` | | Nest results under shared prefixes |
| `--siblings` | | List the other keys of each matched container |
| `--samples` | | Sample values per group (default 3) |
| `--color` | | `auto`, `always`, `never` |
| `--quiet` | | Suppress the coverage footer |
| `--jf` | | JSON-folder mode, as `json_query --jf` |
| `--collection` | | Read a jsondb collection export from stdin |
| `--db` | | jsondb path to name in the handoff command |
| `--with-ancestors` | | Include `..NAME` ancestor expressions in the handoff |
| `--max-depth` | | Nesting guard (default 512) |
| `--jobs` | `-j` | Worker count (0 = one per CPU) |
| `--strict` | | Treat any skipped file as fatal |
| `--verbose` | | Per-file progress on stderr |

Every narrowing flag is optional. They exist for the second and third pass, once
a wide search has revealed the shape.

## Trustworthy negatives

"It isn't there" is a deliverable, and it is only useful if you can trust it.
Nothing is silently skipped, a parse failure is never reported as absence, and
every run states what it searched and what it could not read.

```
Searched 13 files (1.8 KB) in 41ms. Skipped 1:
  data/legacy.json — invalid JSON: unexpected end of input at offset 8814
Coverage is incomplete — a nil or partial result here is not a trustworthy negative.
```

## Exit status

| Code | Meaning |
|---|---|
| `0` | At least one match |
| `1` | No matches, everything searched — **a trustworthy negative** |
| `2` | Usage error |
| `3` | No matches, but files were skipped — **do not believe this one** |
| `4` | Nothing could be searched at all, or `--strict` saw a skip |

`1` and `3` are deliberately distinct. A script that needs "definitely not
present" must test for `1` specifically, never merely non-zero.

## Scripting

```sh
json_find ASSET_TAG data/ -F paths     # bare query strings, one per line
json_find ASSET_TAG data/ -F jsonl     # one record per hit, plus coverage
json_find ASSET_TAG data/ -F json      # a single document
```

The machine formats carry per-hit array indices, which the text view elides, and
always end with a coverage record whose `complete` field is the one to test —
without it a consumer cannot distinguish a clean miss from a corpus that failed
to load.

## Document stores

If the JSON is in a [jsondb](../jsondb/) collection rather than in files, pipe an
export in and name the collection:

```sh
jsondb export sites | json_find ASSET_TAG --collection sites --db app.sqlite
→ jsondb -d app.sqlite nquery "sites.site,ASSET_TAG,_FILE"
```

A collection and a `--jf` subdirectory are the same idea — both supply the first
path segment, which is what makes a field at the document root addressable — and
jsondb's query grammar is identical to `json_query`'s, so the emitted query is
the same either way.

This ships every document; there is no server-side search. The footer says so,
and reports completeness as supplied by the producer rather than claiming a
coverage it could not verify.

## See also

[User guide →](guide/) &nbsp;·&nbsp; `man json_find` &nbsp;·&nbsp;
[json_query →](../json_query/)
