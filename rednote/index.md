---
title: rednote
---

[← all tools](../)

A Redis notebook, in your browser. One Markdown file is one notebook; a persistent
connection is bound to it, so `SELECT`, `MULTI` and `WATCH` flow from cell to cell. Run a
cell and the replies are spliced back into the same `.md` file — formatted exactly the way
`redis-cli` prints them, so the file stays plain CommonMark, readable and grep-able and
correct on GitHub.

## Install

```sh
brew tap pmuston/rednote
brew trust pmuston/rednote   # required for third-party taps
brew install rednote
```

After installing, `man rednote` has the full reference offline.

## Usage

```sh
rednote [flags] [path/to/notebook.md]
rednote new [flags] PATH
rednote version
```

| Command / flag | Meaning |
|---|---|
| `rednote PATH` | Open the notebook and serve it on `127.0.0.1:8080`. |
| `rednote` | With no path, open the one notebook here — or name them all if there are several. |
| `rednote new PATH` | Scaffold a starter notebook (won't overwrite) and serve it. |
| `rednote version` | Print version and build revision. Also `--version`, `-v`. |
| `-addr HOST:PORT` | Address to listen on. Default `127.0.0.1:8080`. |
| `-allow-flush` | Permit `FLUSHALL`, `FLUSHDB` and `SWAPDB`, which are otherwise refused. |
| `-list` | List the notebooks in this directory and exit. |
| `-max-output N` | Cap the rendered bytes one cell may produce. Default 4 MiB. |
| `-max-reply N` | Cap the wire bytes of a single reply. Default 32 MiB. |
| `-poll D` | How often the browser polls a running cell. Default `500ms`. |

## Examples

```sh
# Open a notebook
rednote notebooks/keyspace-audit.md

# Create one and start editing
rednote new experiments/cache-shape.md

# A scratch server you don't mind emptying
rednote -allow-flush scratch.md
```

## The notebook format

Fenced ` ```redis ` blocks are command cells; running one writes a paired ` ```output `
block beneath it. Everything else is prose. Front matter is YAML:

| Field | Meaning |
|---|---|
| `notekit` | Format version. Must be `1`. |
| `title` | Shown in the header. |
| `rednote-url` | Which server this notebook talks to. Default `redis://127.0.0.1:6379/0`. |

A cell is **one command per line**, the same shape as a script piped into `redis-cli`.
Lines are split into arguments by redis-cli's own rules, and nothing else about a line is
interpreted. Replies are matched positionally against the commands above them. There is no
comment syntax — prose belongs outside the fence, where it renders as prose.

The interactive prompt and echoed command that `redis-cli` prints are never written into a
result: the commands are already in the source fence directly above.

## Why the replies look like redis-cli

Because that formatter is a total function from arbitrary bytes to printable ASCII, which
answers two things a Redis notebook otherwise cannot:

```
DEL tour:empty
SET tour:empty ""
GET tour:empty
GET tour:missing
```

```
(integer) 0
OK
""
(nil)
```

- **Nothing is not the same as empty.** `(nil)` against `""`. For a key-value store that
  difference is most of the meaning, and a CSV table cannot express it.
- **Values are bytes.** A value holding a NUL or invalid UTF-8 is escaped as `\xNN`, so
  the notebook stays valid CommonMark and the value stays exact. `STRLEN` counts bytes,
  not characters.

rednote asks for **RESP3** on connect and falls back to RESP2 on servers older than Redis
6, which still work. RESP3 is what renders a hash as pairs (`1# "sku" => "PN-4471"`) rather
than a flat array you re-pair by eye, keeps a double distinct from a string, and marks
`INFO` verbatim so it prints raw instead of as one enormous quoted line.

## Behaviour

- **Always bound to a real server.** There is no in-memory mode and rednote does not
  pretend to have one — Redis is a network service. The startup line names the server;
  the password is never shown. A committed notebook records commands and one run's
  replies, **not data**: run it against a different server and the replies differ.
- **Persistent connection.** One connection is held for as long as the notebook is open,
  so `SELECT`, `MULTI` and `WATCH` carry between cells. Cancelling a running cell drops
  and reopens the connection, which loses that state; the error says so.
- **An error does not stop a cell.** Redis carries on, so the commands after a failure
  genuinely ran. The whole transcript is kept with `(error) …` inline where it happened,
  and persisted as an `error` block rather than an `output` one.
- **The file is the artifact.** Every write is a byte-range splice: prose, spacing and
  cells you did not run round-trip byte-identically. Results are volatile — a run
  replaces the whole of a cell's result.
- **Reordering does not re-run anything.** Document order is execution order, so moving a
  cell changes what *Run all* does. That is your call, not the tool's.

## What it refuses

| Refused | Why |
|---|---|
| `SUBSCRIBE`, `PSUBSCRIBE`, `SSUBSCRIBE`, `MONITOR`, `SYNC`, `PSYNC` | They put the connection into a mode that never returns, which a notebook can neither display nor leave. |
| `FLUSHALL`, `FLUSHDB`, `SWAPDB` | They destroy data that is not in git, unlike the notebook. Pass `-allow-flush` when you mean it. |

Blocking commands that *do* return — `BLPOP`, `WAIT`, a slow script — run normally and
honour the cancel button. A refusal never reaches the server and persists as an `error`
block, so the run still succeeds.

`SHUTDOWN` is deliberately **not** guarded: it stops a server rather than destroying a
keyspace, and extending the guard to everything that could ruin someone's day ends at a
denylist nobody can keep current.

## Limitations

- No pub/sub or `MONITOR` streaming — the refusal is the answer, not a placeholder.
- No cluster support, and no `MOVED`/`ASK` redirection.
- Single notebook per server process; no CI or headless mode.
- Results are text only. A Redis reply has no faithful table form, which is the whole
  reason the durable form is redis-cli's.

## Exit status

| Code | Condition |
|---|---|
| `0` | Success, including a clean shutdown on Ctrl-C. A cell whose commands errored is *not* a failure — that is a successful run that persisted an `error` block. |
| `1` | The server could not run, or failed while running. |
| `2` | Usage error, an unreadable notebook, or a Redis that could not be reached on open. |

## Links

- [Five-minute demo →](demo/)
- [Source & releases](https://github.com/pmuston/homebrew-rednote)
- Built on [notekit](https://github.com/pmuston/notekit), which owns the notebook format.
- `rednote version` prints the build revision for bug reports.
