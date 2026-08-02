---
title: SQL SELECT Syntax
---

[← jsondb](../)

## SQL SELECT syntax

SQL statements are converted to native query strings before execution. The
WHERE clause, if present, is extracted and stored separately as a filter.

```
SELECT col [AS alias], ... FROM element.sub.path [WHERE expr]
```

- `SELECT` and `FROM` are case-insensitive keywords.
- Column expressions follow the same syntax as native key expressions.
- `AS alias` is optional on any column.
- The `FROM` path uses the same dot-separated format as native queries.
- A trailing semicolon is ignored.
- The `WHERE` clause is everything after the `WHERE` keyword to end of
  statement. It is parsed and applied as a row filter after extraction.

**Conversion rules:**

1. Strip trailing `;`.
2. Extract and remove the `WHERE ...` suffix if present.
3. Extract the `FROM <path>`.
4. Extract the column list between `SELECT` and `FROM`.
5. For each column: if it matches `<expr> AS <alias>`, emit `expr:alias`;
   otherwise emit `expr` unchanged.
6. Join as: `path,col1,col2,...`

The WHERE clause (if any) is paired with this query string and applied after
rows are extracted.

