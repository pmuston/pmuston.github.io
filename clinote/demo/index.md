---
title: clinote in five minutes
---

[← clinote](../)

# clinote in five minutes

One notebook, one investigation, and a file you could still read next year.

Every output on this page was produced by running the notebook below with clinote 2.2.1
on macOS. It was rendered with `ROOT=/usr/share` so that nothing from a personal home
directory appears here — the notebook itself defaults to `$HOME`, which is slower and
more interesting.

## 0. What you need

clinote, and a shell. No service, no database, nothing to start.

```bash
brew tap pmuston/tap
brew trust pmuston/tap   # required for third-party taps
brew install pmuston/tap/clinote
clinote version
```

## 1. Get the notebook

```bash
curl -O https://raw.githubusercontent.com/pmuston/clinote/main/examples/where-did-the-space-go.md
ROOT=/usr/share clinote where-did-the-space-go.md
```

`ROOT` is read by the first cell. Setting it in the environment rather than in the file
is the same mechanism you would use for a credential: clinote's shell inherits its
environment, so the value is available to every cell and never written to disk.

clinote prints a URL and waits. It does not open a browser.

## 2. What you are looking at

Seven cells, in the shape most investigations actually take:

| | |
|---|---|
| 1 | pick a target |
| 2 | **walk it once** — the slow cell |
| 3–7 | read the snapshot cell 2 wrote, and report on it |

That split is the whole design. The expensive step happens once and writes a file;
everything after it is cheap and re-runnable. Against `/usr/share` the walk takes about
a tenth of a second. Against a home directory it took **81 seconds** on the machine this
was written on, which is why it is a cell of its own.

## 3. Run it

Press **Run all**. Each result appears under its cell and is written into the file at
the same moment.

**The shell is one shell.** Cell 1 sets `ROOT`:

```
looking at /usr/share
```

Cell 2 uses it, and so could cell 7. Nothing was passed between them — it is one
`bash` process for as long as clinote is running, so variables, `cd`, functions and
`set` options all carry. That is the difference between this and seven separate
commands.

**stdout and stderr interleave, as in a terminal.** `time` writes to stderr and `printf`
to stdout; both land in one result body, in the order they were produced:

```

real	0m0.094s
user	0m0.004s
sys	0m0.091s
41 directories
```

(The leading blank line is the shell's, not clinote's — nothing is tidied on the way in.)

There is no `dur=` key in the format, so `time` is how a cell records how long it took.

**A table is a table.** Cell 3 is tagged `{format=csv}`, so the browser sorts it by any
column while the file keeps plain CSV:

```
mib,path
65,/usr/share/tokenizer
45,/usr/share/firmware
27,/usr/share/morphun
23,/usr/share/vim
20,/usr/share/man
16,/usr/share/icu
13,/usr/share/langid
6,/usr/share/terminfo
5,/usr/share/zsh
4,/usr/share/cups
```

**And `du` already speaks TSV**, so cell 6 does no reformatting at all — no `awk`, just
the tool's own output with a header on it:

```
kib	path
66512	/usr/share/tokenizer
45756	/usr/share/firmware
27660	/usr/share/morphun
24036	/usr/share/vim
20840	/usr/share/man
```

That is what `tsv` is for. It is not CSV with a different delimiter — it has no quoting
at all, so nothing is escaped on the way in and a field is exactly the bytes between the
tabs.

**A failure is a first-class block.** Cell 7 counts paths matching `cache`, and `grep`
exits 1 when it finds none:

````markdown
```error {status=1, run="2026-08-12T07:44:59Z", tool="clinote/2.2"}
0
```
````

That is worth dwelling on, because it will catch you out: `grep`, `diff` and friends
exit non-zero to mean *"no"*, not *"something went wrong"*. clinote records the exit
status faithfully, so a perfectly successful command lands in a red `error` block with
the answer inside it. The alternative — deciding which non-zero exits are really
failures — is guesswork the tool has no business doing.

## 4. The file is the artifact

That is the claim worth testing. Stop clinote and read what it wrote:

```bash
cat where-did-the-space-go.md
```

Each cell is now followed by an ordinary fenced block:

````markdown
## 4. How much of the total is that?

```sh
awk 'NR==1 { t=$1 } NR>1 && NR<=11 { s+=$1 }
     END { printf "top ten = %.0f%% of %.1f GiB\n", 100*s/t, t/1048576 }' du-snapshot.tsv
```

```output {run="2026-08-12T07:42:07Z", tool="clinote/2.2"}
top ten = 89% of 0.2 GiB
```
````

Plain CommonMark. It greps, it diffs, it renders on GitHub, and it says which tool wrote
each result and when. Nothing here needs clinote to be readable — clinote is only needed
to run it again.

## 5. Change something, without paying twice

This is the part a shell script cannot do.

Edit cell 3 — click the source fence — to report twenty directories instead of ten, by
changing `NR<=11` to `NR<=21`. Then press **Run below** on that cell.

Cells 3 to 7 all re-run. Cell 2 does not: the snapshot file's timestamp is unchanged,
so the walk was not repeated. On a home directory that is 81 seconds you keep, every
time you adjust the reporting.

It is worth knowing what Run all and Run below do *not* do: they do not stop at the
first failure. The cells are handed to a scheduler that serialises them, so by the time
one fails the rest are already queued. Cell 7 fails on every run of this notebook, and
everything after it still runs.

The corollary, learned the hard way while writing this page: **do not put a destructive
cell in a notebook you will Run All.** An earlier draft ended with a cell that deleted
the snapshot, which meant every full run threw away the thing the notebook exists to
produce. Cleanup belongs in your shell, not in the notebook — see section 7.

## 6. What the front matter can say

```yaml
---
notekit: 1
title: Where did the space go?
notekit-tool: clinote
width: full
---
```

`width: full` uses the whole window rather than a reading column, which a notebook full
of long paths wants. Three more keys are available — `editable: false` to withhold editing
without ever preventing a run, `local-files: true` to display a figure sitting beside
the notebook, and `requires: [NAME, …]` to say which environment variables a notebook
needs so the page can report the missing ones before you run anything.

If you had wanted `ROOT` declared rather than assumed, that last one is how:

```yaml
requires: [ROOT]
```

Only names are read, and only whether each is set — no value ever reaches the file.

## 7. Check it, then clean up

The notebook's conformance is not a matter of opinion. notekit's own linter is the
authority, and it exits 0 for clean, 1 for a finding, 2 for a usage failure — so it
works as a commit gate:

```bash
go run github.com/pmuston/notekit/cmd/notefmt@latest -strict check where-did-the-space-go.md
```

```
where-did-the-space-go.md: 7 cells, 7 cells with results
```

Then:

```bash
rm -f du-snapshot.tsv where-did-the-space-go.md
```

## What to try next

Point it at something real. `ROOT=$HOME clinote where-did-the-space-go.md`, press Run
all, go and make coffee, and come back to a file you can commit.

The [user guide](https://github.com/pmuston/clinote/blob/main/docs/user-guide.md) covers
the rest: defining shell functions once and using them all session, keeping credentials
out of the file, what happens to progress bars and spinners, and migrating a clinote v1
notebook.
