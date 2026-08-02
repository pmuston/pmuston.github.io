---
title: WHERE Filtering
---

[← jsondb](../)

## WHERE filtering

WHERE filtering is applied to the list of extracted rows after all JSON files
have been processed, before writing output.

Each row is represented as a `map[string]string` keyed by the column header
names (aliases where provided).

The WHERE clause is evaluated against the original column names (not aliases)
**as they appear in the query key expressions**. In practice the column names
in the row dict are the header names (aliases), so WHERE must use those same
names. This mirrors the Python implementation.

### Tokeniser

Tokens (case-insensitive for keywords):

- Single-quoted string: `'...'`
- Keywords: `AND`, `OR`, `NOT`, `LIKE`
- Parentheses: `(`, `)`
- Comparison operators: `!=`, `<>`, `<=`, `>=`, `<`, `>`, `=`
- Everything else (field names, unquoted values): contiguous non-whitespace

### Grammar

```
expr    := or_expr
or_expr := and_expr ( OR and_expr )*
and_expr:= factor ( AND factor )*
factor  := NOT factor
         | '(' expr ')'
         | condition
condition := field op value
```

The parser is recursive-descent.

### Condition evaluation

1. If the field is not present in the row, the condition is `false`.
2. For `LIKE`: convert the pattern (`%` → `.*`, `_` → `.`, other chars
   regex-escaped) and match case-insensitively against the field value as a
   string.
3. For all other operators: attempt numeric coercion on both sides (parse as
   float; if the float equals its integer truncation, use the integer value).
   Fall back to string comparison if either side is not numeric.
4. Operators: `=`, `!=`, `<>` (same as `!=`), `<`, `>`, `<=`, `>=`.
5. Any evaluation error silently returns `false` (row excluded).
