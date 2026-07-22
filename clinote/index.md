---
title: clinote
---

[← all tools](../)

A personal lab notebook for shell commands, in your browser. One Markdown file
is one notebook; a persistent shell is bound to it, so state flows from cell to
cell. Run a cell and its output is spliced back into the same `.md` file — which
stays plain CommonMark, readable and grep-able and correct on GitHub.

## Install

```sh
brew tap pmuston/tap
brew trust pmuston/tap   # required for third-party taps
brew install pmuston/tap/clinote
```

After installing, `man clinote` has the full reference offline.

## Usage

```sh
clinote [--no-browser] [path/to/notebook.md]
clinote new [--no-browser] PATH
clinote version
```

| Command / flag | Meaning |
|---|---|
| `clinote PATH` | Open the notebook and serve it on `127.0.0.1`, opening a browser. |
| `clinote new PATH` | Scaffold a starter notebook (won't overwrite) and open it. |
| `clinote version` | Print version and build revision. Also `--version`, `-v`. |
| `clinote` | With no path, list the `.md` files in the current directory. |
| `--no-browser` | Print the URL but don't open a browser. Env `BROWSER=none` does the same. |

## Examples

```sh
# Open a notebook
clinote notebooks/disk-usage.md

# Create one and start editing
clinote new experiments/idea.md

# A notebook that needs a credential — export it first so it never
# lands in the file (cell bodies are written to disk verbatim)
export NEO4J_PW=…
clinote notebooks/graph.md
```

## The notebook format

Fenced ` ```sh ` blocks are command cells; running one appends a paired
` ```output ` block. Everything else is prose. Front matter is optional YAML:

| Field | Meaning |
|---|---|
| `title` | Shown in the header. |
| `shell` | `bash` or `zsh` (default `bash`). |
| `editable` | `true` unlocks in-browser editing, the format picker, and deletion. |
| `width` | `full` uses the whole window; otherwise a narrow column. |
| `requires` | List of env vars the notebook needs; a banner names any that are unset. |

An output block is paired to the command above it only when whitespace alone
separates them — pairing is positional, there are no cell IDs. Set `out=csv`,
`out=tsv`, or `out=jsonl` on a command to render its output as a sortable table.

## Behaviour

- **Persistent shell.** `cd`, environment variables, and functions set in one
  cell persist into later cells for the life of the server.
- **The file is the artifact.** Output is written back to the `.md` as plain,
  ANSI-stripped text. There is no database and no proprietary format.
- **Run the whole pipeline.** *Run all* runs every cell from the top; *run ↓*
  runs a cell and everything below it. Both stop at the first non-zero exit —
  use `cmd || true` for a step that should survive failure.
- **Images and files.** Files next to the notebook are served, so a Markdown
  image link renders in the browser as it does on GitHub. Only the notebook's
  own directory is reachable; traversal, symlink escape, and dotfiles are
  refused, and served files are sandboxed via CSP.
- **Credentials via the environment.** Export a secret before launching; the
  shell inherits it. Never `export` one in a cell — the value would be written
  to the file.
- **Recovering a hung cell.** The **Interrupt** button sends SIGINT to the
  running command. Ctrl-C in the terminal stops clinote itself.

## Limitations

- The in-memory notebook is authoritative during a session; external edits are
  overwritten on the next save.
- Interactive TUI commands (`vim`, `less`, `htop`) hang the cell.
- Output is capped at 1 MiB per cell.
- Single user, single notebook per server process — no CI/headless mode.

## Exit status

| Code | Condition |
|---|---|
| `0` | Success. |
| `1` | Runtime error (message on stderr). |
| `2` | Usage error. |

## Links

- [Source & releases](https://github.com/pmuston/clinote)
- [User guide](https://github.com/pmuston/clinote/blob/main/docs/user-guide.md)
- `clinote version` prints the build revision for bug reports.
