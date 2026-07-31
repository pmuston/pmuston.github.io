---
title: rt-interest User Guide
---

[← rt-interest](../)

# rt-interest — user guide

rt-interest shows you the current value of a list of tags, live, in a browser.
It exists to answer one question: **is this arriving?** Confirming that a
publisher, bridge or simulator is producing the values you expect, for the tags
you expect, at the rate you expect.

It deliberately does not do history, trends, charts, alarms, or unit
conversion, and it never writes to NATS. If you need any of those, this is the
wrong tool.

---

## Install

```bash
brew tap pmuston/rt-interest
brew trust pmuston/rt-interest   # required for third-party taps
brew install rt-interest
```

`brew trust` is the step people get stuck on — recent Homebrew refuses to run a
third-party tap's formula without it, and the error does not make the fix
obvious.

macOS and Linux, arm64 and amd64. It is one static binary with no runtime
dependencies, so copying it to a machine works just as well as installing it.

## Quick start

```bash
rt-interest discover -prefix rt
```

Listens for a minute and writes `./lists/discovered.csv` — every subject it
heard, as a ready-to-use list. Then:

```bash
rt-interest -dir ./lists -prefix rt
```

Open <http://localhost:8080>. Click a list.

If you already know which tags you care about, skip `discover` and write the
CSV yourself — see [Interest lists](#interest-lists).

### The prefix

`-prefix rt` means your data is published under subjects starting `rt.`, and
that the prefix does **not** appear in your CSV files. A tag written
`FC100/PID1/PV/CV` in a list is the subject `rt.FC100.PID1.PV.CV` on the wire.
Slashes in the file, dots on the wire.

Get this wrong and everything shows as never-seen. `-prefix rt` and
`-prefix rt.` behave identically.

---

## Reading a list page

Three columns: **Path**, **Value**, **Age**.

### The three states

This is the whole point of the tool. A value that arrived three hours ago must
never look like one that arrived 200ms ago.

| Looks like | State | Means |
|---|---|---|
| `—` in grey, Age blank | **never** | This tag has not been seen once since the service started. Not "zero", not "empty" — *absent*. |
| Normal black value, Age blank | **live** | Arrived within the staleness window (default 10s). |
| Dimmed value, Age shows `12s`, `4m`, `2h` | **stale** | Last arrived that long ago and has not been updated since. |

A cell flashes yellow briefly each time a new value lands, so you can see
which tags are actually moving. If a whole column flashes together, your
publisher sends everything in one batch.

The distinction between **never** and **stale** is the one that matters. A
never-seen row means the tag is not being published *at all* under the name in
your list — a wrong prefix, a typo, or a publisher that has never sent it. A
stale row means it *was* arriving and stopped.

### The two badges

The header has two, and they mean different things:

| Badge | Meaning |
|---|---|
| **CONNECTED** / **RECONNECTING** | rt-interest's connection to NATS, **as of when the page loaded**. It does not update — reload the page, or use `/debug`, to see the current state. |
| **streaming** / **reconnecting** / **no stream** | Your browser's connection to rt-interest. This one is live. |

`no stream` means JavaScript did not run. The page still shows correct values —
it just won't update until you reload.

### Other things you might see

- A value ending `…` — the payload was over 256 bytes and was truncated.
- A value starting `0x` — the payload was not valid text, so it is shown as hex.
- A friendly name instead of the tag path — that's a label from the CSV. Hover
  to see the real path.

---

## Interest lists

A list is a plain `.csv` file in the `-dir` directory. Its **name** is the
filename without `.csv`, and that's what appears on the index page.

The simplest possible list is one tag path per line:

```csv
FC100/PID1/SP/CV
FC100/PID1/PV/CV
FC100/PID1/OUT/CV
```

Optionally add a display label as a second column:

```csv
FC100/PID1/SP/CV,Feed flow setpoint
FC100/PID1/PV/CV,Feed flow measured
FC100/PID1/OUT/CV,Feed valve demand
```

A third column is accepted and kept for future use, but does nothing today.
Extra columns are ignored.

### Rules worth knowing

**Order is preserved.** Rows appear in file order, not sorted. Put related tags
next to each other and they will display that way.

**Bad lines are skipped, not fatal.** The list page reports e.g. *"24 paths ·
1 line skipped"*. A line is skipped if the path contains a `.`, `*`, `>`, a
space, or a tab, or if it is empty. This is deliberate: it means a header row
from a database export — like the `a.Path` line Neo4j puts at the top — removes
itself without you having to strip it.

**If your count is lower than expected, the skip count tells you why.** The
commonest cause is a stray space before or after the path.

**Duplicates keep the first occurrence** and are counted separately.

**A dot in a tag name will not work.** Paths use `/` and the dot is reserved
for the NATS subject separator.

---

## Getting lists onto the server

Three ways, in order of least ceremony:

### Copy the file in

```bash
cp myloop.csv /path/to/lists/
```

The directory is re-read on every request, so it appears on the next page load.
No restart, no reload of the service.

### Let discover write one

```bash
rt-interest discover -prefix rt -for 5m
```

Listens and writes `lists/discovered.csv`, counting down while it works:

```
  38s left · 124 subjects · 2480 messages
```

Ctrl-C stops it early and still writes what it heard so far, so a long run is
never wasted. Useful flags: `-for` (default 1 minute — increase it if you have
slow tags that only publish occasionally), `-out` to choose the filename.

Start here on an unfamiliar system, then edit the result down to what you
actually care about.

### Drag and drop in the browser

Only if the service was started with `-upload`:

```bash
rt-interest -dir ./lists -prefix rt -upload
```

Then drag a `.csv` onto the **index page** (`/`, not a list page). It reports
what loaded — `myloop: 24 paths · 1 line skipped` — and the index refreshes.

`-upload` is off by default because this tool ends up on plant networks, and a
write endpoint should be a decision someone made on purpose. Without it there
is no drop target on the page at all.

A dropped file is rejected if it doesn't end `.csv`, is over 1MB, won't parse,
or has a filename containing `/`, `\`, `..`, or a leading dot. A rejection
leaves the directory exactly as it was. Dropping a file with the same name as
an existing list replaces it, and anyone with that list open gets their page
refreshed automatically.

---

## When a tag doesn't show up

Go to **`/debug`**. Two numbers on that page will tell you where the problem
is.

**Per list: "never seen".** How many of that list's paths have not arrived
once. If this is the whole list, suspect the prefix. If it's a handful,
suspect those specific tag names.

**Globally: "N of the M subjects received appear in no list".** Subjects that
*are* arriving but which no list asks for.

Read them together with **messages received**, which is the number that
separates "nothing is arriving" from "the wrong things are arriving":

| never seen | messages received | in no list | Diagnosis |
|---|---|---|---|
| all of them | **0** | 0 | Nothing is reaching you at all. Wrong `-prefix`, wrong NATS server, or nothing is publishing. Check the connection state and the subscription subject, both shown at the top of `/debug`. |
| all of them | lots | all of them | The prefix is right and data is flowing, but nothing in your list matches. The list is probably written for a different naming scheme. |
| a few | lots | most of what's on the wire | Your CSV and the publisher disagree about those particular names — a typo, or a renamed point. Diff against `discover` output to find the real spelling. |
| zero | lots | 0 | Everything is working. |

The subscription subject on `/debug` is worth a glance on its own: if it says
`WRONG.>` when your data is on `rt.>`, you have found the problem without
reading anything else.

`/debug` also shows uptime, a rolling messages/second, how many distinct
subjects are cached, and how many browsers are connected.

### The sample is a sample

The not-in-any-list **count** is exact. The tags listed beneath it are the
**first 20 in alphabetical order** — the same 20 every time you reload, so you
can read one, go and check it, and come back to find it still there.

It is still only 20. If the count is higher than that, the tag you are looking
for may simply be further down the alphabet, and refreshing will not bring it
into view. When you need the complete answer, capture what is really publishing
and compare it to your list:

```bash
rt-interest discover -prefix rt -for 30s -out /tmp/actual.csv
comm -23 <(cut -d, -f1 lists/yourlist.csv | sort) <(sort /tmp/actual.csv)
```

That prints exactly the paths your list asks for that nothing is publishing —
your typos, and nothing else. The `cut` matters: it strips the label column,
and without it every labelled row looks like a mismatch.

---

## Troubleshooting

**Values are shown but never change.** Check the second badge. `no stream`
means JavaScript didn't load. `reconnecting` means the browser can't reach
rt-interest — it retries by itself and will repaint when it succeeds.

**Every row went dim at once with ages climbing.** The feed stopped. The values
on screen are the last known ones and the Age column tells you how long ago.
Reload the page to see the current NATS state, or check `/debug`.

**The seventh browser tab just hangs, with no error.** HTTP/1.1 allows six
connections per host, and each open list holds one. Close a tab. Behind a proxy
that terminates TLS with HTTP/2 this stops happening.

**My list doesn't appear on the index.** The filename must end in `.csv`
(lowercase), and be directly in `-dir` — not a subdirectory. Check the service's
log output for a parse error.

**The list has fewer rows than my file has lines.** That's the skip count on
the page. Look for a leading or trailing space, or a `.` in a path.

**Dragging a file does nothing.** The service was not started with `-upload`;
there's no drop target. Copy the file into the lists directory instead.

**Everything says `never`.** Check `messages received` on `/debug` first. If
it's 0, nothing is arriving — usually the prefix, otherwise the server or the
publisher. If it's climbing, data is flowing but none of it matches your list;
compare your paths against the not-in-any-list sample. Either way
`rt-interest discover` writes out what is genuinely there, which you can diff
against what you expected.

**Values restart as `never` after I restart the service.** Expected — the cache
is in memory only. They repopulate as each tag next publishes, which for a slow
tag can be a while.

---

## Command reference

Three commands. `serve` is the default, so `rt-interest -dir ./lists` and
`rt-interest serve -dir ./lists` are the same thing.

### Which build am I running?

```bash
rt-interest version      # → rt-interest v0.1.0 (a0d10e72148c)
```

It reports the version and the exact commit it was built from. This matters
more than it looks: a diagnostic tool that is itself out of date will happily
show you a stale answer, and a binary copied onto a plant machine months ago is
otherwise indistinguishable from a current one.

If you ever see `, modified` after the commit, that binary was built from an
uncommitted working tree and corresponds to no commit in the repository. It is
not a release build; treat any conclusion drawn from it with suspicion.

### Serving

```
rt-interest [flags]

  -dir string        directory of interest-list CSV files (default "./lists")
  -nats string       NATS server URL (default "nats://127.0.0.1:4222")
  -prefix string     subject prefix, without trailing dot (default "")
  -addr string       HTTP listen address (default ":8080")
  -interval duration how often the browser is updated (default 200ms)
  -stale duration    age at which a value is shown as stale (default 10s)
  -upload            enable drag-and-drop upload of new lists (default false)
  -version           print version and exit (same as the version command)
```

`-interval` bounds how often your browser is updated, regardless of how fast
the data publishes. A tag changing 1000 times a second costs exactly what one
changing once a second costs. Lower it if 200ms feels laggy; there is rarely a
reason to.

`-stale` is a judgement about your process. If your slowest interesting tag
publishes every 30 seconds, `-stale 10s` will show it as stale most of the
time; set it above your normal publish interval.

### Discovering

```
rt-interest discover [flags]

  -dir string        directory to write the list into (default "./lists")
  -nats string       NATS server URL (default "nats://127.0.0.1:4222")
  -prefix string     subject prefix, without trailing dot
  -for duration      how long to listen (default 1m0s)
  -out string        output file (default <dir>/discovered.csv)
```

### Pages

| URL | What it is |
|---|---|
| `/` | Index of lists |
| `/l/<name>` | A list, live |
| `/debug` | Diagnostics |

---

## Things to know

- **Nothing is stored.** Close the browser and the values are gone. Restart the
  service and it starts cold. There is no history to go back to.
- **No login.** Anyone who can reach the port can see every list. Put it behind
  something if that matters.
- **NATS being down is not fatal.** The service starts anyway, shows the
  disconnected state, and recovers by itself. Values go stale and come back;
  they are not cleared.
- **It listens to everything under the prefix**, not just what's in your lists.
  That is what makes a newly added list show values immediately instead of
  waiting for each tag to next publish.
- **The page works with JavaScript disabled.** It just won't update — reload to
  see current values.
