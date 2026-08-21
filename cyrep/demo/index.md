---
title: cyrep in 5 minutes
---

[← cyrep](../)

# cyrep in 5 minutes

Load a small graph, write a report, get Markdown. Every snippet below is real
output from the seed below — nothing is illustrative.

You need cyrep installed and a reachable backend:

```bash
brew tap pmuston/cyrep && brew trust pmuston/cyrep && brew install cyrep
```

Either backend works. Neo4j is assumed below; for graphdb, replace the
connection flags with `--uri http://localhost:8080` and skip the password.

---

## 0. Load the seed (30 seconds)

The seed builds a notional ISA-88 batch plant: one area, one process cell,
three reactor units, their equipment and control modules, and a recipe that
runs three phases. It is entirely invented and uses standard public S88
vocabulary.

```bash
curl -fsSLO https://pmuston.github.io/cyrep/examples/s88-seed.cypher
cypher-shell -u neo4j -p "$NEO4J_PASSWORD" -f s88-seed.cypher
```

Check it landed — 66 nodes, 78 relationships:

```bash
cypher-shell -u neo4j -p "$NEO4J_PASSWORD" "MATCH (n) RETURN count(n) AS nodes"
```

The three reactors are deliberately uneven. R101 is fully populated and has
alarms; R102 and R103 do not. That asymmetry is what makes the `empty:`
fallback visible in step 4.

For the rest of this walkthrough, set the connection once:

```bash
export NEO4J_URI=bolt://localhost:7687
export NEO4J_PASSWORD=...
```

---

## 1. The smallest useful report (1 minute)

A report is YAML with one `report:` key containing `blocks:`. Start with a
single table:

```yaml
# units.yaml
report:
  title: "Units"
  blocks:
    - type: table
      title: "All Units"
      query: |
        MATCH (u:Unit)
        RETURN u.name AS Name, u.class AS Class
        ORDER BY Name
```

```bash
cyrep run units.yaml --output units.md
```

```markdown
---
report: Units
generated: '2026-08-21T13:16:08+00:00'
source: units.yaml
---

**All Units**

| Name | Class |
| --- | --- |
| R101 | REACTOR |
| R102 | REACTOR |
| R103 | REACTOR |
```

Column headers are the `RETURN` aliases, in the order you declared them. The
front matter is on by default; `--no-frontmatter` turns it off.

Note the `ORDER BY`. It is not decoration: without it the rows come back in
whatever order storage happens to yield, and a report that is meant to be
regenerated and diffed stops being diffable. `Name` is unique across units, so
one column is a total order here.

---

## 2. One section per row with `forEach` (1 minute)

A `forEach` runs a driver query and renders its child blocks once per row,
binding the row to the name in `as:`.

```yaml
# reactors.yaml
report:
  title: "Reactor Reference"
  blocks:
    - type: forEach
      query: |
        MATCH (u:Unit)
        RETURN u.name AS name, u.class AS class
        ORDER BY name
      as: unit
      key: name
      blocks:
        - type: heading
          level: 1
          text: "{{ unit.name }} ({{ unit.class }})"

        - type: table
          title: "Control Loops"
          query: |
            MATCH (u:Unit {name: $unit.name})-[:CONTAINS]->(:EquipmentModule)
                  -[:CONTAINS]->(cm:ControlModule)
            RETURN cm.name AS Name, cm.class AS Class
            ORDER BY Name
```

Two things just happened. `{{ unit.name }}` interpolated the row into the
heading, and `$unit.name` passed it into the child query as a parameter.

```markdown
<!-- block: forEach unit, row 1 of 3 -->
<!-- unit: name=R101 -->

# R101 (REACTOR)

**Control Loops**

| Name | Class |
| --- | --- |
| R101_LIC01 | PID |
| R101_PIC01 | PID |
| R101_SIC01 | PID |
| R101_TIC01 | PID |

<!-- unit: name=R101 end -->
```

Write the dotted `$unit.name`. cyrep rewrites it to `$unit__name` before the
query is sent, because Neo4j has no dotted parameters. Note the **double**
underscore — a hand-written `$unit_name` binds nothing and fails at the driver.

`key: name` declares which column identifies a row. It is what puts
`name=R101` in the markers, and it earns its keep in step 5.

---

## 3. Stop re-querying what you already have (1 minute)

The driver query already returned `name` and `class`. A `properties` block can
read them straight from the row instead of going back to the database:

```yaml
        - type: properties
          source: unit
          fields: [name, class]
```

```markdown
# R101 (REACTOR)

- **name:** R101
- **class:** REACTOR

**Control Loops**
```

That is Mode B. Mode A — `query:` instead of `source:` — runs its own query and
is the right choice only when the data is not already in scope. Omit `fields:`
to take every column of the row, in the order the query declared them.

---

## 4. Empty results are a design decision (1 minute)

Add an alarms table. R101 has three; R102 and R103 have none:

```yaml
        - type: table
          title: "Alarms"
          query: |
            MATCH (u:Unit {name: $unit.name})-[:CONTAINS]->(:EquipmentModule)
                  -[:CONTAINS]->(:ControlModule)-[:HAS_ATTRIBUTE]->(a:Attribute)
            WHERE a.type = 'ALARM'
            RETURN a.name AS Alarm
            ORDER BY Alarm
```

R101 renders its three. R102 renders this:

```markdown
**Alarms**

_No rows._
```

`_No rows._` is the built-in. If zero alarms is a legitimate state rather than
a symptom, say so:

```yaml
          empty: "(no alarms configured)"
```

```markdown
**Alarms**

(no alarms configured)
```

The distinction matters more than it looks. A `table` never fails on zero rows,
but a `properties` block in Mode A **does** unless `empty:` is set — a block
that expects exactly one row and gets none usually means the report is wrong,
and failing loudly is the point. Set `empty:` when nothing is a valid answer;
leave it off when nothing means something is broken.

---

## 5. One file per entity (1 minute)

Swap `--output` for `--output-dir` and each row of the outer `forEach` becomes
its own file:

```bash
cyrep run reactors.yaml --output-dir units/
```

```
wrote 3 files to units/
```

```
units/R101.md  units/R102.md  units/R103.md
```

The filenames come from `key: name`. Each file gets its own front matter
identifying which row it is:

```markdown
---
report: Reactor Reference
generated: '2026-08-21T13:16:53+00:00'
source: reactors.yaml
row_index: 1
row_key: name
name: R102
---
```

Drop `key:` and cyrep has nothing to name files with, so it falls back to the
row index and says so:

```
WARNING: forEach has no 'key:' declared; using row index for filenames.
Consider adding 'key: <column>'.
```

```
units/1.md  units/2.md  units/3.md
```

Index-named files reshuffle the moment the driver query returns a different set,
so a natural key — a tag, a name, a path — is almost always worth declaring.
`--filename-template "{{ index1 }}-{{ unit.name | lower }}.md"` overrides both.

---

## Why the markers are there

The HTML comments are not decoration. The output is meant to be fed to an LLM,
and the markers make it possible to slice a document back into the rows it came
from without parsing Markdown:

```
<!-- block: forEach unit, row 2 of 3 -->
<!-- unit: name=R102 -->
...
<!-- unit: name=R102 end -->
```

A retrieval step can extract exactly one unit's section, and "row 2 of 3" tells
a reader — human or model — whether they are looking at everything or a
fragment. `sectionMarkers: false` in the report's `config:` turns them off if
you are rendering for people instead.

---

## Where next

- `man cyrep` — the full reference, offline.
- [Authoring guide](https://pmuston.github.io/cyrep/authoring/) — the rules that
  matter once reports get real.
- [More reports against this same seed](https://pmuston.github.io/cyrep/examples/):
  `s88_quickstart.yaml` is roughly this walkthrough's endpoint,
  `s88_physical_model.yaml` nests `forEach` three deep, and
  `s88_recipe_procedure.yaml` walks the recipe hierarchy.
- Blocks not covered here: `text` for free-form Markdown, and `heading` at any
  level 1–6.
- `--continue-on-error` when a long report should survive one bad block, and
  `--max-rows` when a table is larger than a context window.

Two things worth internalising before writing a real report. **Every `ORDER BY`
must be a total order** — the test is not how many columns you sorted on but
whether two rows can share the key. And **a missing binding is an error, never
an empty string**: `{{ unit.nmae }}` fails loudly with the block's path rather
than rendering a document with a hole in it.
