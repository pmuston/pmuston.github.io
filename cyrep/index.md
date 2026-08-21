---
title: cyrep
---

[← all tools](../)

Turn graph data into **Markdown shaped for LLM context**, driven by a YAML
report definition. Output is deterministic and diffable, section boundaries are
machine-extractable, and the renderer favours token efficiency over typographic
polish.

A report is a tree of **blocks**. Some iterate — a driver query whose child
blocks render once per row — and others are leaf content: tables, property
lists, headings, text. Two backends sit behind one port, selected by the URI
scheme: **Neo4j** over Bolt, and **graphdb** over Cypher-on-HTTP/JSON.

## Install

```sh
brew tap pmuston/cyrep
brew trust pmuston/cyrep   # required for third-party taps
brew install cyrep
```

Linux without Homebrew:

```sh
curl -fsSL https://pmuston.github.io/install.sh | sh -s cyrep
```

After installing, `man cyrep` has the full reference offline.

## Usage

```sh
cyrep run REPORT_FILE (--output PATH | --output-dir DIR) [flags]
```

| Flag | Meaning |
|---|---|
| `--output PATH` | Write the whole report to one file. |
| `--output-dir DIR` | Split mode: one file per row of the outer `forEach`. |
| `--filename-template TPL` | Names split-mode files. Default `{{ <as>.<key> }}.md`. |
| `--frontmatter` / `--no-frontmatter` | Force YAML front matter on or off. |
| `--continue-on-error` | Downgrade block errors to an inline marker and carry on. |
| `--max-rows N` | Table truncation threshold. Default `1000`. |
| `--uri URI` | Backend URI; the scheme picks the backend. Env `NEO4J_URI` or `GQ_URL`. |
| `--neo4j-user NAME` | Env `NEO4J_USER`. Default `neo4j`. |
| `--neo4j-password PASS` | Env `NEO4J_PASSWORD`. Required for bolt. |
| `--neo4j-database DB` | Env `NEO4J_DATABASE`. Default `neo4j`. |
| `--token TOKEN` | graphdb bearer token. Env `GQ_TOKEN`. Optional. |
| `-v`, `--verbose` | Log each query and its parameters to stderr. |

`--neo4j-uri` remains as a deprecated alias for `--uri`; passing both is an
error.

## A report definition

```yaml
report:
  title: "Unit Reference"
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
          empty: "(none)"
```

Block types are `forEach`, `heading`, `properties`, `table` and `text`.

## Behaviour

**`key:` declares row identity.** It names the column that uniquely identifies a
row, and drives section markers, split-mode filenames and front matter. Omitting
it falls back to row indices and warns — prefer a natural key like a tag or a
path.

**Parameters use the dotted form.** Write `$unit.name`; it is rewritten to
`$unit__name` before the query is sent, because Neo4j has no dotted parameters.
Note the **double** underscore — a single-underscore `$unit_name` binds nothing
and fails at the driver.

**Templates are deliberately closed.** A dotted path, a bare variable, and the
filters `lower`, `upper` and `trim`. No loops or conditionals, because `forEach`
owns iteration. A missing binding or field is an error, never an empty string:
a typo fails loudly with a block path instead of producing a silently hollow
document.

**Every `ORDER BY` must be a total order.** Output is meant to be diffable, and
that guarantee is yours to uphold: tied rows come back in whatever order storage
yields, which varies between engines, between versions, and after a reload. The
test is not how many columns you sorted on, but whether two rows can share the
sort key.

**Truncation is layered.** A per-table `maxRows:` beats `--max-rows`, which
beats the report's `config.maxRows`, which beats the built-in default of 1000.
A truncated table carries a warning line naming both counts.

## Exit status

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Unexpected error |
| `2` | Load or validation failure, or a misinvocation |
| `3` | Config error — unsupported URI scheme, missing Neo4j password |
| `4` | Backend connection failure |
| `5` | Block-level runtime error |

`--continue-on-error` downgrades a block error to a warning plus an inline
`<!-- error: ... -->` marker. Connection failures stay fatal regardless: there
is nothing left to continue against.

## Links

- [Releases](https://github.com/pmuston/homebrew-cyrep/releases)
- [Tap](https://github.com/pmuston/homebrew-cyrep)
