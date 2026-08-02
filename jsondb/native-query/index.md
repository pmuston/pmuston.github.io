---
title: Native Query Syntax
---

[← jsondb](../)

## Native query syntax

A query string is a single comma-separated line:

```
ELEMENT.SUB.PATH,keyExpr1,keyExpr2,...
```

### Path (first segment, before the first comma)

A dot-separated path. The first segment names the element subdirectory. All
subsequent segments navigate into the JSON structure to identify the objects
to match. Every matched object produces one output row.

### Key expressions (remaining segments)

Each key expression extracts one field value from a matched object or one of
its ancestors.

| Expression | Meaning |
|---|---|
| `NAME` | Field `NAME` on the matched object |
| `CHILD.KEY` | Field `KEY` inside child object `CHILD` of the matched object |
| `CHILD.GRAND.KEY` | Field `KEY` two child levels deep |
| `..NAME` | Field `NAME` on the immediate parent (one level up) |
| `...NAME` | Field `NAME` on the grandparent (two levels up) |
| `....NAME` | Three levels up, and so on |
| `_FILE` | The document's `_filename` field (see below) |

The number of ancestor levels to climb equals the number of leading dots minus
one: `..` = 1 level, `...` = 2 levels, `....` = 3 levels.

Ancestor climbing and sub-navigation may be combined: `..SIBLING.KEY` means
"navigate into child `SIBLING` of the parent, then extract `KEY`".

#### `_FILE`

`_FILE` reads the field `_filename` from the **document**, not from the matched
object — so it yields the same value however deep the query has navigated. That
is what distinguishes it from writing `_filename` as an ordinary key
expression, which reads the matched object and returns nothing when the match
is a nested element:

```
modules.rects,name,_FILE:src        ->  {"name":"a","src":"pump-101"}
modules.rects,name,_filename:src    ->  {"name":"a","src":""}
```

**Only `importdb` sets `_filename`.** It stamps each document with the base
name of the `.json` file it was read from. Documents inserted any other way —
the API, the driver, `import`, the admin UI — have no such field, and `_FILE`
yields an empty string for them. It is provenance for bulk-imported data, not
a property of every document.

### Aliases (AS clause)

Any key expression may be followed by `:ALIAS` to give the output column a
different name:

```
..TAG:MODULE_TAG
RECTANGLE.H:HEIGHT
_FILE:SOURCE
```

Without an alias the column name is the key expression as written (including
leading dots and dot-separated sub-path). With an alias the column name is the
alias. The alias has no effect on how the value is extracted.

---

---

## JSON traversal

### Finding matches

Starting from the root of the parsed JSON document, follow the path segments
(everything after the first element segment) recursively:

- If the current node is an **object** (`map`) and the segment is a key,
  descend into that key's value, pushing the current object onto the ancestor
  stack.
- If the current node is an **array** (`slice`), iterate every element and
  recurse with the same remaining path segments (do not push anything onto the
  ancestor stack for array iteration — the array itself is not an ancestor).
- When all path segments are consumed:
  - If the node is an object, it is a match.
  - If the node is an array, every object element is a match.
  - Scalar values produce no matches.

Each match is a `(object, ancestorStack)` pair where `ancestorStack[0]` is the
immediate parent object, `ancestorStack[1]` the grandparent, and so on.

### Extracting a value

Given `(levels_up, subPath, keyName)` and a `(object, ancestors)` match:

1. If `levels_up == 0`, the source is the matched object.
2. If `levels_up > 0` and `len(ancestors) >= levels_up`, the source is
   `ancestors[levels_up-1]`.
3. Otherwise return `""` (ancestor does not exist).
4. Descend through each segment in `subPath`: if the source is an object and
   the segment is a key, update the source. Otherwise return `""`.
5. If the source is not an object at this point, return `""`.
6. Return `source[keyName]` as a string, or `""` if missing or null.

All extracted values are strings. Numeric JSON values are converted to their
string representation (integers without decimal point, floats as needed).

### Missing keys

Any missing key or unreachable ancestor silently produces an empty string `""`
rather than an error. The row is still emitted.

