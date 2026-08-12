---
title: clinote
---

[← all tools](../)

A personal lab notebook for shell commands, in your browser. One Markdown file is
one notebook; a persistent shell runs the cells and results are written back into
the same `.md` — plain CommonMark, readable and correct on GitHub.

**New here?** [clinote in five minutes](demo/) walks one real investigation from an
empty notebook to a file you could commit.

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
| `-allow-local-files` | off | Serve files from the notebook's directory, confined to it. |

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

```output {format=csv, run="2026-08-11T09:41:07Z", tool="clinote/2.2"}
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

Declare a result kind with `{format=csv}`, `{format=tsv}` or `{format=jsonl}`, or
pick one from the dropdown in each cell's header: tables render sortable in the
browser and stay plain text on disk.

Picking a kind rewrites the cell's `{format=…}` **and relabels the result already on
the page**, so output you have just realised was a table becomes one without
re-running the command. That is what the control is for — re-running is fine when it
is cheap. Relabelling changes no data: a result body is the bytes the command
produced, and `format` says how to read them. An `error` block is left alone, a
failure not being a table however the cell is labelled.

`tsv` is not `csv` with a different delimiter and is not parsed as one. It has no
quoting at all, so a field cannot contain a tab or a newline and nothing is
unescaped — a cell reading `he said "hi", ok` is exactly those characters, quotes
and comma included. That is what makes it the easy thing to emit from a shell
(`cut`, `awk -F'\t'`, `psql -A -F$'\t'`) for data that would need quoting as CSV.

## Front-matter options

| Key | Effect |
|---|---|
| `width: full` | Use the whole window rather than a reading column. |
| `editable: false` | Withhold editing — the source, prose, and adding, deleting or moving cells. |
| `local-files: true` | Declare that the notebook displays files from its own directory. |
| `requires: [NAME, …]` | Name the environment variables the notebook needs. |

**`editable: false` never gates running.** It suits a notebook written *for*
someone rather than by them — a teaching exercise, or a vetted runbook whose steps
should be run as written. A notebook nobody can run is a document; handing one out
is precisely so the reader executes it, and running still writes results. It is a
guard rail against the accidental edit, not a control: anyone can edit the file in
their editor, and should be able to.

**`local-files: true` declares a need and grants nothing.** A notebook that
generates a figure links to it the ordinary way, and that file sits beside the
notebook. Serving it needs the notebook's own directory — which may be a home
directory or a repository root — so the grant comes from the command line:

```sh
clinote -allow-local-files notebooks/figures.md
```

The reason is worth stating plainly: a notebook is exactly the part someone else
may have written, and a file that could authorise reading its neighbours would be
authorising itself. Reading `width` from a notebook is safe because honouring it
only picks a layout; reading a capability is not. Without the flag the page says
what is missing rather than showing a broken image.

Serving is confined to that directory. Paths escaping it — lexically,
percent-encoded, or through a symlink — are refused, as are dot-prefixed
components, so `.git/` and `.env` stay out of reach when a notebook sits in a
repository root. Served files carry a sandboxing `Content-Security-Policy` and
`nosniff`, because an SVG can carry script.

**`requires:` names what the notebook needs and never blocks.** Handing someone a
notebook that says what it depends on beats handing them one that fails on cell
four:

```yaml
requires: [NEO4J_PW, NEO4J_URL]
```

The page reports which are unset. Only names are read, and only whether each is
non-empty, so no value ever reaches the notebook. It does not refuse to open: a
notebook should be readable without your credentials to hand, and a cell that needs
one fails on its own terms with a better message than a refusal at the front door.

Write it **inline**, as above. A YAML block list is invisible here — notekit parses
front matter without a YAML marshaller, deliberately, so that notebooks round-trip
byte for byte. clinote reports the empty result as a mistake and names the inline
form rather than silently reporting nothing.

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
- **Run below** runs this cell and every cell after it, for a pipeline whose first
  stage is too expensive to repeat.
- **Run all and Run below do not stop at the first failure.** The cells are
  submitted to a scheduler that serialises them, so the rest are queued by the time
  one fails. clinote v1 halted the batch on a non-zero exit; if a later stage would
  run against stale inputs, watch it rather than assuming a red block stopped
  things.
- **Interrupt** sends SIGINT to a running command — the way to recover a hung cell
  without stopping the server.
- **Works without JavaScript**, and cell bodies are editable in the browser.

## Progress bars and spinners

Cells run under a pty — which is what makes `cd` and shell state persist, and what
lets tools needing a terminal work at all. The cost is that **every tool thinks it is
talking to a person**: `[ -t 1 ]` is true in a cell, so anything with a progress
display draws one. `-term dumb` does not prevent it, because most such tools test
whether stdout is a terminal rather than what `TERM` says.

A display that redraws one line — a spinner, a percentage — is replayed, so the
result holds the line as it finally read rather than every frame concatenated. Colour
is unaffected: a line that did not redraw itself keeps its bytes, and only redrawn
lines are flattened.

Two things that follow:

- **Overwriting is column by column, as in a terminal.** A tool that omits an
  erase-to-end-of-line leaves the tail of a longer frame behind — `Downloading 100%`
  then a carriage return and `Done` reads `Doneloading 100%`. Your terminal shows the
  same thing, which is why well-behaved tools emit the erase.
- **Multi-line redraws are not replayed.** `docker pull` with its per-layer bars,
  `cargo` and `bazel` move the cursor *up* between lines. Replaying that needs a whole
  screen modelled rather than a line, and a screen is a different artifact from the
  stream a notebook records.

To stop a tool drawing progress at all:

```sh
export CI=1                  # honoured widely; the shell persists, so set it once
some-tool --progress=plain   # or --quiet, --no-progress
some-tool | cat              # stdout becomes a pipe, so `[ -t 1 ]` is false
```

`| cat` reports `cat`'s exit status, so a failing command writes an `output` block
rather than an `error` one. Add `set -o pipefail` in a setup cell if that matters —
being one shell, it carries to every cell below.

Full-screen programs — `vim`, `less`, `htop` — still hang the cell, and that is a
boundary rather than a gap. Such a program produces a *screen*; a notebook records a
*stream*, and the cell never exits, so there would be nothing to write down even if
the screen were captured. Use Interrupt.

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
- Multi-line progress displays are not replayed — see [Progress bars and spinners](#progress-bars-and-spinners).
- Output is capped per cell; the excess is dropped and marked `truncated`.
- `exit N` terminates the persistent shell — use `false` or a subshell.
- Files beside the notebook are served only with `-allow-local-files`.

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
