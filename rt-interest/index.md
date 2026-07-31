---
title: rt-interest
---

[← all tools](../)

Subscribe to a NATS subject tree and watch the current value of a curated list
of tags in a browser, updating live. A diagnostic tool: it answers *is this
arriving?* rather than *what is the value?*.

## Install

```sh
brew tap pmuston/rt-interest
brew trust pmuston/rt-interest   # required for third-party taps
brew install rt-interest
```

After installing, `man rt-interest` has the full reference offline, and the
[user guide](guide/) covers reading the display and diagnosing a missing tag.

## Usage

```sh
rt-interest [flags]           # serve interest lists
rt-interest discover [flags]  # write what is publishing as a list
rt-interest version
```

| Flag | Meaning |
|---|---|
| `-dir PATH` | Directory of interest-list CSV files. Default `./lists`. |
| `-nats URL` | NATS server URL. Default `nats://127.0.0.1:4222`. |
| `-prefix STR` | Subject prefix, without a trailing dot. A trailing dot is ignored. |
| `-addr ADDR` | HTTP listen address. Default `:8080`. |
| `-interval DUR` | How often the browser is updated. Default `200ms`. |
| `-stale DUR` | Age at which a value is shown as stale. Default `10s`. |
| `-upload` | Enable drag-and-drop upload of lists. Off by default. |

`discover` additionally takes `-for DUR` (how long to listen, default `1m`) and
`-out FILE`.

## Examples

```sh
# find out what is publishing, then look at it
rt-interest discover -prefix rt
rt-interest -dir ./lists -prefix rt

# a process whose slowest interesting tag publishes every half minute
rt-interest -dir ./lists -prefix rt -stale 45s

# which paths in a list is nothing publishing?
rt-interest discover -prefix rt -for 30s -out /tmp/actual.csv
comm -23 <(cut -d, -f1 lists/mylist.csv | sort) <(sort /tmp/actual.csv)
```

An interest list is a CSV file, one tag path per line, with an optional display
label as a second field:

```csv
UNIT_A/FLOW/PV,Feed flow measured
UNIT_A/TEMP/PV,Column top temperature
UNIT_A/LEVEL/PV
```

Paths use `/`; the subject prefix never appears in the file. Under
`-prefix rt`, `UNIT_A/FLOW/PV` is the subject `rt.UNIT_A.FLOW.PV`.

## Behaviour

- **Three display states, never confusable.** A tag never seen shows an em dash,
  a stale one dims and grows an age, a live one is plain. A value from three
  hours ago must not look like one from 200ms ago — that distinction is the
  point of the tool.
- **Updates are coalesced onto `-interval`.** Bandwidth is bounded by list size
  times interval regardless of publish rate, so a tag changing 1000 times a
  second costs what one changing once a second costs, and the value shown is the
  latest rather than a lagging one.
- **`/debug` locates faults.** Two set differences — how many of a list's paths
  have never arrived, and how many arriving subjects appear in no list — say
  whether the publisher, the subject mapping or the CSV is wrong.
- **Lists are files.** The directory is re-read on every request, so a file
  copied in appears without a restart.
- **Nothing is written to NATS**, no history is kept, and there is no
  authentication.
- **Bad CSV lines are skipped and counted**, which is how a header row from a
  database export removes itself instead of needing to be stripped.
- **NATS being down is never fatal.** The service starts anyway, shows the
  disconnected state and recovers; cached values go stale and return.

## Exit status

| Code | Condition |
|---|---|
| `0` | Success. |
| `1` | Runtime error — NATS unreachable at startup for `discover`, an unwritable output path, a listen address in use. |
| `2` | Usage error. |

## Known gotcha

HTTP/1.1 allows six connections per origin and each open list holds one for its
event stream, so a seventh list tab hangs with no error at all. Behind a proxy
terminating TLS with HTTP/2 it does not happen.

## Links

- [User guide](guide/) — reading the display, writing lists, diagnosing a missing tag
- [Source & releases](https://github.com/pmuston/homebrew-rt-interest)
- `rt-interest version` prints the build revision for bug reports.
