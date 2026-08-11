---
title: clinote
---

[← all tools](../)

A personal lab notebook for shell commands, in your browser. One Markdown file is
one notebook; a persistent shell runs the cells and results are written back into
the same `.md` — plain CommonMark, readable and correct on GitHub.

## Install

```sh
brew tap pmuston/tap
brew trust pmuston/tap   # required for third-party taps
brew install pmuston/tap/clinote
```

After installing, `man clinote` has the full reference offline.

> **v2 is a breaking change.** Notebooks written by clinote v1 use a different
> format and must be converted with `clinote migrate` — see
> [Upgrading from v1](#upgrading-from-v1).

## Usage

```sh
clinote notebook.md                 # serve a notebook
clinote                             # use the notebook in this directory
clinote new notebook.md             # create one, then serve it
clinote migrate old.md              # convert a v1 notebook
clinote version
```

| Flag | Default | Meaning |
|---|---|---|
| `-addr` | `127.0.0.1:8080` | Address to listen on. |
| `-shell` | `$SHELL` if bash/zsh, else bash | Shell to run cells in. |
| `-term` | `dumb` | `TERM` for the shell; a real value enables colour auto-detection. |
| `-poll` | `500ms` | How often the browser polls a running cell. |
| `-list` | — | List candidate notebooks and exit. |

clinote prints its URL and waits — it does not open a browser. Ctrl-C stops it.

## A notebook

````markdown
---
notekit: 1
title: Disk usage
notekit-tool: clinote
---

## Largest directories

```sh {format=csv}
du -d1 -h | sort -hr | head -5
```

```output {format=csv, run="2026-08-11T09:41:07Z", tool="clinote/2.0"}
size,path
1.2G,./data
480M,./vendor
```
````

The format is [notekit](https://github.com/pmuston/notekit)'s, and its
specification is the authority. Two rules catch people out:

- **A cell needs its own heading**, level 2–6. A heading's section holds exactly
  one source fence; a second fence in the same section is prose and never runs.
- **Failures are `error` blocks** carrying the exit status, not output with a bad
  exit code.

Declare a result kind with `{format=csv}`, `{format=tsv}` or `{format=jsonl}`:
tables render sortable in the browser and stay plain text on disk.

## Examples

```sh
# Open a notebook on a chosen port
clinote -addr 127.0.0.1:9000 notebooks/disk-usage.md

# Create one and start work
clinote new experiments/idea.md

# A notebook needing a credential — export it first, so the value
# never reaches the file (cell bodies are saved verbatim)
export NEO4J_PW=…
clinote notebooks/graph.md
```

## Behaviour

- **One persistent shell.** `cd`, environment variables and functions carry from
  one cell to the next for the life of the server.
- **The file is the artifact.** Results are written back as ordinary fenced
  blocks, ANSI stripped. No database, no proprietary format.
- **stdout and stderr interleave**, as in a terminal. The exit status decides the
  block: zero writes `output`, non-zero writes `error`. Quieten a noisy command
  with `cmd 2>/dev/null`.
- **Interrupt** sends SIGINT to a running command — the way to recover a hung cell
  without stopping the server.
- **Works without JavaScript**, and cell bodies are editable in the browser.

## Upgrading from v1

Opening a v1 notebook names the fix:

```
clinote: s88.md is a clinote v1 notebook
         convert it with: clinote migrate s88.md
```

```sh
clinote migrate -dry-run notebooks/*.md   # report only
clinote migrate notebooks/s88.md          # writes notebooks/s88.v2.md
clinote migrate -in-place notes.md        # keeps notes.md.v1.bak
```

Every cell gains a heading — invented from the command's name where there is none.
Rename them freely afterwards: a cell's identity is its `id`, not its heading.
Failed results become `error` blocks, and `dur=` is dropped, having no key in the
format. Migrated results keep their original timestamp and are marked
`tool="clinote/1"`, because that is what produced them.

Migration **refuses to write if the cell count changed** — a stranded fence
becomes prose silently, so counting is the only guard against a quietly gutted
notebook.

## Limitations

- Single user, one notebook per server process; no headless or CI mode.
- The in-memory notebook is authoritative — external edits during a session are
  overwritten on save.
- Interactive TUI commands (`vim`, `less`, `htop`) hang the cell.
- Output is capped per cell; the excess is dropped and marked `truncated`.
- `exit N` terminates the persistent shell — use `false` or a subshell.
- Files beside the notebook are not served, so an image link will not render.

## Exit status

| Code | Condition |
|---|---|
| `0` | Clean shutdown. |
| `1` | The server failed, or a migration refused to write. |
| `2` | Usage or I/O failure. |

## Links

- [Source & releases](https://github.com/pmuston/clinote)
- [User guide](https://github.com/pmuston/clinote/blob/main/docs/user-guide.md)
- [notekit](https://github.com/pmuston/notekit) — the format and runtime clinote is built on
- `clinote version` prints the build revision for bug reports.
