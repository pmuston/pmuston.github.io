---
title: Authoring cyrep reports
---

[← cyrep](../)

# Authoring cyrep reports

A report is a YAML document with one top-level key `report:` containing
`title:` (optional), `config:` (optional), and `blocks:` (required).
See ../cyrep-spec.md for the full reference; this
document is task-oriented.

## Iterating with `forEach`

`forEach` runs a driver Cypher query, binds each row to a name via `as:`,
and renders its `blocks:` once per row.

```yaml
- type: forEach
  query: |
    MATCH (m:Module) RETURN m.name AS name, m.tag AS tag
    ORDER BY m.tag
  as: module
  key: tag
  blocks:
    - type: heading
      level: 1
      text: "Module: {{ module.name }} ({{ module.tag }})"
```

Each child block can access the bound row through Jinja (`{{ module.name }}`)
and Cypher parameters (`$module.tag` — see below).

`key:` names the column that uniquely identifies a row. cyrep uses it for
section markers (`<!-- module: tag=PMP-101 -->`), split-mode filenames
(default `{{ module.tag }}.md`), and split-mode front matter. Omitting
`key:` falls back to row indices and logs a warning — prefer to declare
one.

`skipIfEmpty: true` silently emits nothing when the driver query returns
zero rows. The default is to render markers around an empty body.

## `$module.id` Cypher parameters

cyrep rewrites dotted parameters to flat underscore form before sending
to Neo4j (which doesn't support dotted params natively):

```
$module.id   →   $module__id
```

This is a textual transform. Both forms below produce the same query at
the driver:

```cypher
MATCH (m:Module {tag: $module.tag})  RETURN m   -- author-facing
MATCH (m:Module {tag: $module__tag}) RETURN m   -- the rewritten form, written out
```

Note the **double** underscore. A single-underscore `$module_tag` binds
nothing and fails at the driver with `ParameterMissing`.

Use the dotted form. It's clearer and matches the binding name.

## `properties`: Mode B beats Mode A

If the data you want already exists in an enclosing `forEach` row, use
Mode B — it avoids a second round trip to Neo4j.

```yaml
# Good — Mode B
- type: properties
  source: module
  fields: [description, tag]

# Avoid — Mode A re-queries the same node
- type: properties
  query: |
    MATCH (m:Module {tag: $module.tag})
    RETURN m.description AS description, m.tag AS tag
```

Omit `fields:` to use every field on the row in its declared order.

## When to set `empty:` vs rely on fail-loud

The default behaviour for `properties` Mode A and `table` when the query
returns zero rows is:

- `properties` Mode A: **fail loud** unless `empty:` is set.
- `table`: emit `_No rows._` (or `empty:` if set).

Use `empty: "(none)"` when zero rows is a legitimate state. Leave it
unset when zero rows means something is broken — fail-loud will surface
the misconfiguration immediately.

## Make every `ORDER BY` a total order

cyrep's output is meant to be diffable, so a report must produce the same
bytes from the same data. That guarantee is yours to uphold, not the
engine's: if an `ORDER BY` leaves ties, the tied rows come back in whatever
order storage happens to yield, and that varies between engines, between
versions, and after a reload.

```cypher
-- Fragile: a phase can acquire several equipment modules, so `Phase`
-- alone leaves ties and the tied rows can swap between runs.
RETURN ph.name AS Phase, em.name AS EquipmentModule
ORDER BY Phase

-- Deterministic: the key is unique across the result set.
RETURN ph.name AS Phase, em.name AS EquipmentModule
ORDER BY Phase, EquipmentModule
```

Sorting on a single column is fine **when that column is unique in the
result set** — `ORDER BY Name` over control modules is a total order
because each name appears once. The test is not "how many columns did I
sort on" but "can two rows share this sort key". Where they can, add
columns until they can't.

This bites hardest on traversals that fan out (`(a)-->(b)-->(c)` returning
one row per leaf), where duplicate parent values are the normal case rather
than an edge case.

## Truncation

Tables truncate at the effective `maxRows`:

1. per-table `maxRows:` (highest priority)
2. `--max-rows` CLI flag
3. report `config.maxRows`
4. built-in default of 1000

When truncation triggers, a warning line is appended to the table and to
stderr.

## Output modes

- `--output PATH` writes one Markdown file with everything in sequence.
- `--output-dir DIR` writes one file per row of the **outer** `forEach`.
  The outer must be a single top-level `forEach` block; anything else is
  an error.

In split mode, `--filename-template` is a Jinja template with access to
`index`, `index1`, and the outer `forEach` binding's key field (e.g.
`{{ module.tag }}.md` when `key: tag` is declared). Default template is
`{{ <as>.<key> }}.md` if `key:` is set, else `{{ index1 }}.md` (with a
stderr warning).
