---
title: json_find User Guide
---

[← json_find](../)

# json_find — user guide

**`json_find` finds where things are in JSON. `json_query` extracts them once you know.**

Every example below can be run from the repository root against the fixtures in
`testdata/`, and the output shown is exactly what you will get.

---

## When to reach for it

You have a pile of JSON — one file or ten thousand — and a fragment: half a key
name, a value you saw in a log once, a term from a spec. You do not know the
path, the nesting depth, or which file. Often you do not know whether the thing
is there at all.

Every query tool presupposes you are past this point. `jq`, JSONPath, SQL and
`json_query` all need you to know the shape already, which is exactly what you
cannot supply when the data is unfamiliar.

`json_find` answers two questions and then gets out of the way:

- **Where is it?**
- **Is it even there?**

It finishes by printing a `json_query` command you can paste. It does not
extract, reshape, or compute — if you want the data rather than its location,
you are past `json_find` and into `json_query`.

---

## Install

```bash
go build -o json_find .
```

Put the binary anywhere on your `PATH`. `json_query` is a separate tool; you
only need it when you act on a handoff.

---

## Quick start

```bash
json_find PLANT_AREA testdata/plant.json
```

```
json_find "PLANT_AREA" — 5 shapes · 6 hits · 1 file

sites[].PLANT_AREA              key    exact       2 hits · 1 file
  values   "SiteA", "SiteB"
  files    testdata/plant.json (2)
  → json_query -q "sites,PLANT_AREA,_FILE" -- testdata/plant.json

PLANT_AREA                      key    exact       1 hit · 1 file
  values   "TopLevelArea"
  files    testdata/plant.json
  ⚠ not expressible as a json_query path
    root-level: json_query cannot address the document root in file mode; use --jf mode…

equipment.area.PLANT_AREA_NAME  key    substring   1 hit · 1 file
  values   "Main Reactor"
  files    testdata/plant.json
  → json_query -q "equipment.area,PLANT_AREA_NAME,_FILE" -- testdata/plant.json

Searched 1 file (345 B) in 0ms. Skipped 0.
Surfaces: key, value, filename. Roots: testdata/plant.json. Tiers active: exact, iexact, substring, normalized, fuzzy(distance 2, keys only).
```

The pattern is **never** a path. There is no invocation in which you have to
know where to look — not knowing is the reason you are here.

If you give no path at all, the current directory is searched recursively.

---

## Reading the output

Results are grouped by **shape**, not listed one per hit.

```
sites[].PLANT_AREA              key    exact       2 hits · 1 file
└──────┬───────────┘            └─┬─┘  └──┬──┘     └───┬───┘
   the shape                   surface   tier       counts
  values   "SiteA", "SiteB"        ← sample values found there
  files    testdata/plant.json (2) ← which documents, and how many hits in each
  → json_query …                   ← paste this
```

**Shape** is the location with array indices elided. `sites[0].PLANT_AREA` and
`sites[1].PLANT_AREA` collapse into `sites[].PLANT_AREA ×2`. The `[]` marker is
the useful part: it tells you the structure *repeats*, which is usually what you
needed to learn. Indices are not shown because `json_query` has no index syntax
— there is nothing you could do with them downstream. If you want exact
per-hit locations, use `--format jsonl` (see [Scripting](#scripting)).

**Surface** says *what kind of thing* matched — a key name, a value, or a
filename. You never declare this up front; all three are searched by default and
each result tells you which one it was.

**Tier** says *how well* it matched. See [Matching](#matching).

Groups are ranked by tier, then by hit count. The strongest, most widespread
matches come first.

---

## The discovery loop

Discovery is iterative: cast wide, read the shape, tighten, hand off.

### 1. Cast wide

```bash
json_find PLANT_AREA data/
```

Give it the fragment and nothing else. Over-inclusion is deliberate — see
[Matching](#matching).

### 2. Read the shape

```bash
json_find PLANT_AREA testdata/plant.json --tree --siblings
```

```
equipment   (3 hits below)
  PLANT_AREA   key    exact       1 hit · 1 file
    values   "EquipmentLevel"
    siblings area
  area   (2 hits below)
    PLANT_AREA   key    exact       1 hit · 1 file
      values   "Reactor1"
      siblings PLANT_AREA_NAME, type, capacity_mw
    PLANT_AREA_NAME   key    substring   1 hit · 1 file
      values   "Main Reactor"
sites[]   (2 hits below)
  PLANT_AREA   key    exact       2 hits · 1 file
    values   "SiteA", "SiteB"
    siblings name
```

`--tree` nests results under shared prefixes and orders them by name rather than
by rank — it answers *how is this corpus shaped*, where the default view answers
*what matched best*.

`--siblings` is the one to remember. It lists the **other** keys of each matched
container, so you learn what else is queryable at a path you now know is real.
Above, having found `PLANT_AREA` you also discover `type` and `capacity_mw` live
beside it.

### 3. Narrow

```bash
json_find PLANT_AREA testdata/corpus --under equipment
```

Narrowing is always optional and always comes *after* you know the shape. See
[Narrowing](#narrowing).

### 4. Hand off

Copy the `→` line. That is the whole point of the tool.

```bash
json_query -q "equipment.area,PLANT_AREA,_FILE" -- testdata/plant.json
```

---

## Matching

Matching is **tiered, not boolean**. Every tier is active at once and each hit
records the best it achieved. Near-misses are findings, not noise.

| Tier | Matches | Example: pattern `PLANT_AREA` finds |
|---|---|---|
| `exact` | identical | `PLANT_AREA` |
| `iexact` | identical, ignoring case | `plant_area` |
| `substring` | contained anywhere | `PLANT_AREA_NAME` |
| `normalized` | ignoring `_ - . space` and case | `plantArea`, `plant-area` |
| `fuzzy` | within an edit or two | `PLANT_AERA` (transposed) |

```bash
json_find plantarea testdata/plant.json     # → normalized
json_find PLANT_AERA testdata/plant.json    # → fuzzy
```

Both find `sites[].PLANT_AREA`. Searching for what you half-remember is the
intended use.

**Fuzzy applies to keys and filenames, not values**, unless you pass
`--fuzzy-values`. Keys are a small closed vocabulary where a near-miss is almost
always meaningful; values are unbounded text where a distance-2 match is usually
noise. Patterns of four characters or fewer get no fuzzy budget at all. Whatever
is active is stated in the footer, so the restriction is never silent.

To tighten:

```bash
json_find PLANT_AREA data/ --exact             # exact/iexact only
json_find PLANT_AREA data/ --max-tier substring
json_find PLANT_AREA data/ --case-sensitive
json_find 'PLANT_.*_NAME' data/ --regex
```

`--case-sensitive` also switches off the tiers that fold case (`iexact`,
`normalized`, `fuzzy`), leaving `exact` and a case-sensitive `substring`.

---

## Surfaces

Three things are searched, always together by default:

| Surface | What matched |
|---|---|
| `key` | an object member name |
| `value` | a scalar value — string, number, bool, or null |
| `file` | the source file's name |

You are never asked to choose in advance, because "is `MODULE_ATTRIBUTE` a key
or a value?" is usually part of what you came to find out. If you already know,
narrow with `--keys`, `--values`, or `--filenames`. These are **additive**:
passing two searches both.

One rule worth knowing: a key match is recorded **once, at the object that owns
it** — never once per descendant. Matching a container name like `equipment`
gives you one result, not one per leaf beneath it.

---

## The handoff

Each group ends in a line you can paste.

```
→ json_query -q "sites,PLANT_AREA,_FILE" -- testdata/plant.json
```

Note the shape was `sites[].PLANT_AREA` but the query path is `sites`. They are
deliberately different strings: `json_query` iterates arrays transparently, so
the path never contains `[]` or an index. `_FILE` is added so you can tell which
file each row came from.

The `--` before the filenames is required — without it `json_query` reads the
first filename as a subcommand name.

### When the marker is ⚠

A `⚠` means the hit is real but `json_query` cannot express it faithfully. This
matters more than it sounds: **`json_query` answers a wrong path with empty
columns and exit 0.** It cannot tell you a path is wrong, so anything doubtful
has to be flagged here or not at all.

```
equipment.tags[]  value  exact       1 hit · 1 file
  values   "PLANT_AREA"
  ⚠ json_query -q "equipment,tags,_FILE" -- testdata/scalar_array.json
    whole-array: this column returns the whole array, not the matched element
```

The four caveats:

| Caveat | What it means |
|---|---|
| `root-level` | The match sits at the document root, which `json_query` cannot address in file mode. Use `--jf` (see [Folder mode](#folder-mode)). |
| `whole-array` | The match is an element of an array of scalars, which has no name of its own. The column returns the entire array. |
| `multi-root` | The match is in the 2nd or later record of a `.jsonl` stream. `json_query` reads only the first. |
| `duplicate-key` | The key occurs more than once in its object. `json_query` decodes into a map and returns the last one. |

Inexpressible hits are still reported. Hiding one would be a false negative,
which is the thing this tool exists not to produce.

### A note on row counts

`json_find` counts *matches*; `json_query` returns *every* value at the path.
Searching `ALARM` may report 142 hits at a shape, while the handoff returns 1103
rows of which 167 are populated — because the path holds 1103 objects, 167 have
that field, and 142 of those contain "ALARM". Nothing is wrong. Reconnaissance
narrows to a location; extraction takes everything there.

---

## Trusting "not found"

"It isn't there" is a deliverable, and it is only useful if you can trust it.

```bash
json_find MODULE_ATTRIBUTE testdata/corpus
```

```
json_find "MODULE_ATTRIBUTE" — 0 shapes · 0 hits · 0 files

Searched 5 files (307 B) in 0ms. Skipped 0.
Surfaces: key, value, filename. Roots: testdata/corpus. Tiers active: …
```

Five files searched, none skipped, every surface covered. That negative is
trustworthy, and the exit code says so.

Compare a corpus containing an unparseable file:

```
Searched 13 files (1.8 KB) in 0ms. Skipped 1:
  testdata/broken.json — invalid JSON: unexpected end of input at offset 75
Coverage is incomplete — a nil or partial result here is not a trustworthy negative.
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | at least one match |
| `1` | no matches, and every file was searched — **a trustworthy negative** |
| `2` | usage error |
| `3` | no matches, but files were skipped — the negative is **not** trustworthy |
| `4` | nothing could be searched at all, or `--strict` saw a skip |

**Codes 1 and 3 are deliberately distinct.** A script that needs "definitely not
present" must test for `1` specifically, never merely non-zero. Its predecessor
reported an entirely unparseable corpus as "no matches", and anyone reading that
would have concluded the data was absent.

Use `--strict` to make any skip fatal.

---

## Narrowing

Every flag here is optional and none is ever required to get results. They exist
for the second and third pass, once the wide search has taught you the shape.

```bash
json_find PLANT_AREA data/ --under equipment          # by location
json_find PLANT_AREA data/ --under sites[].equipment[] # shapes paste in as-is
json_find 800 data/ --type number                      # by JSON type
json_find PLANT_AREA data/ --file 'reactor*.json'      # by filename
json_find PLANT_AREA data/ --keys                      # by surface
json_find PLANT_AREA data/ --limit 10                  # by count
```

`--under` matches a **contiguous run** of path segments anywhere in the shape,
so `--under sites` and `--under sites.equipment` both match
`sites[].equipment[].tag`, but `--under sites.tag` does not. Trailing `[]`
markers are stripped, so you can paste a shape straight out of the output.

All of these are repeatable and combine as OR within a flag, AND across flags.

Whatever narrowing is in effect is echoed in the footer:

```
Narrowed by: --under nowhere --type number.
```

so a surprisingly empty result is always attributable to what you asked for
rather than to the corpus.

`--limit` always reports what it held back, even under `--quiet`:

```
Showing 1 of 5 groups (4 withheld by --limit).
```

---

## Folder mode

If your corpus is organised as one subdirectory per element type — the layout
`json_query --jf` expects — use the same flag here:

```bash
json_find PLANT_AREA --jf testdata/corpus
```

```
equipment[].PLANT_AREA  key    exact       2 hits · 1 file
  files    sites/legacy.json (2)
  → json_query --jf testdata/corpus -q "sites.equipment,PLANT_AREA,_FILE"

PLANT_AREA              key    exact       1 hit · 1 file
  files    sites/reactor.json
  → json_query --jf testdata/corpus -q "sites,PLANT_AREA,_FILE"
```

The subdirectory name (`sites`) becomes the first path segment. This is worth
knowing for a second reason: **root-level matches are inexpressible in file mode
but expressible under `--jf`**, because the element name supplies the segment
`json_query` needs.

You do not have to spot this yourself. If you search such a corpus in file mode
and lose handoffs to `root-level`, `json_find` says so on stderr and gives you
the command to re-run:

```
json_find: 2 groups (87 hits) at the document root have no file-mode handoff.
           This corpus looks like a JSON-folder layout, so --jf would express them:
             json_find DISTILLATION_2 --jf data/
```

It only appears when both things are true — handoffs were actually lost, and
every file really does sit inside a subdirectory — so it stays quiet on an
ordinary directory that merely happens to have subfolders.

`--jf` searches exactly what `json_query` would read: `*.json` directly inside
each immediate subdirectory. Anything else under the parent is reported as a
skip with a reason rather than silently searched, because a hit found somewhere
`json_query` will not look would produce a handoff that silently returns nothing.

---

## Scripting

```bash
json_find PLANT_AREA data/ -F paths     # bare query strings, one per line
json_find PLANT_AREA data/ -F jsonl     # one record per hit, plus coverage
json_find PLANT_AREA data/ -F json      # a single document
```

`--format paths` is the pipe-friendly one:

```
sites.equipment,PLANT_AREA,_FILE
sites,PLANT_AREA,_FILE
json_find: 1 group(s) omitted — not expressible as a json_query path
```

Queries go to stdout; anything you need to know about what was dropped goes to
stderr, so the stream stays clean.

`--format jsonl` is where **per-hit array indices reappear**, alongside both
json_query-ready forms:

```json
{"type":"hit","file":"data/plant.json","display_path":"sites[0].PLANT_AREA",
 "shape":"sites[].PLANT_AREA","container_path":"sites","key_expr":"PLANT_AREA",
 "query":"sites,PLANT_AREA,_FILE","surface":"key","tier":"exact",
 "value":"SiteA","expressible":true,"caveats":[]}
```

Every machine format ends with a coverage record, even on zero hits and even
under `--quiet`:

```json
{"type":"coverage","files_searched":4,"files_skipped":1,"complete":false, …}
```

`complete` is the field to test. Without it you cannot distinguish a clean miss
from a corpus that failed to load — which is the same trap the exit codes exist
to avoid.

---

## Flag reference

Run `json_find --help` for the grouped list. In brief:

**Matching** — `--regex/-r`, `--exact/-x`, `--case-sensitive/-s`, `--max-tier`,
`--fuzzy-values`

**Narrowing** — `--keys/-k`, `--values`, `--filenames`, `--under/-u`,
`--type/-t`, `--file`, `--limit/-n`

**Output** — `--format/-F`, `--tree`, `--siblings`, `--samples`, `--color`,
`--quiet`

**Corpus** — `--jf`, `--with-ancestors`, `--max-depth`

**Diagnostics** — `--jobs/-j`, `--strict`, `--verbose`

---

## Gotchas

**"Why is this in my results?"** — check the tier column. `substring`,
`normalized` and `fuzzy` hits are near-misses, kept on purpose. With colour on,
the matched span inside the shape is highlighted so you can see exactly which
part matched. `--exact` removes them.

**"The same command appears twice."** Two different structures can share one
`json_query` path — a root-level key and an element of a root-level array are
addressed identically, because arrays are iterated transparently. Both handoffs
are correct.

**"Most of my results were omitted from `-F paths`."** Almost always a corpus
laid out one directory per type, searched in file mode. Root-level matches have
no file-mode handoff; `--jf` gives them one, and `json_find` will tell you so.

**"I got no results and I expected some."** Read the footer. It names the
surfaces searched, the tiers active, and any narrowing in effect. If a tier you
needed was capped, or `--type` excluded your hit, it says so.

**"Exit code 3."** Something could not be read. The negative is not
trustworthy — the footer names the file and the reason.

**`--jobs` makes no difference to output.** By design. Worker count is never
observable in results; it only affects wall-clock.

---

## Not goals

`json_find` will not extract, transform, aggregate, or acquire a query language.
Counting occurrences to reveal structure is in scope; computing over your data
is not. When you find yourself wanting those, you have finished with
`json_find` — paste the handoff and carry on in `json_query`.
