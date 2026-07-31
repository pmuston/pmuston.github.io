---
title: csvpub User Guide
---

[← csvpub](../)

# csvpub user guide

How to get a recorded CSV onto a broker as a live-looking stream, and how to
tell when the result is not what you meant.

`man csvpub` is the flag-by-flag reference; this is the part that reference
material makes no room for — what to check first, which knobs interact, and
which failures are the tool telling you something rather than getting in your
way.

## Before the first run

`csvpub` publishes and exits. It has no state, no config file and no
subscription of its own, so the only lasting effects of a run are the messages
it sends — with one exception, `-retain` under MQTT, covered below.

Two habits are worth forming immediately.

**Namespace the replay.** If the broker also carries real data, publish under a
prefix so nothing downstream mistakes a replay for the plant:

```sh
csvpub -prefix replay export.csv
```

**Look at the plan before you send anything.** `-dry-run` prints what the run
would do and exits without connecting:

```sh
csvpub -dry-run -prefix replay -rate 10 export.csv
```

```
files          export.csv (3 cols)
transport      nats  ->  nats://127.0.0.1:4222
rows           3   2026-03-01 08:00:00 .. 2026-03-01 08:00:10  (10s)
timestamp col  timestamp   layout 2006-01-02 15:04:05 (detected)
interval       5s nominal, uniform over 2 gaps
topics         4    (3 columns + the timestamp topic)
rate           10x
demand         8.0 msg/s   (cap 1000)
headroom       largest lossless rate 1250.00x
wall duration  1s
ts topic       replay._ts  (first in each row)
prefix         replay.
sample         replay.plant.reactor.TIC101.pv
               replay.plant.reactor.TIC101.mode
               replay.plant.reactor.FIC102.pv
```

None of those numbers are derivable from the flags you typed. The three worth
reading every time:

- **`timestamp col`** — which column was treated as time, and which layout was
  detected. `03/01/2026` is 3 January under one reading and 1 March under
  another, and the only cheap moment to notice is here.
- **`wall duration`** — how long the run will take. A file you thought was ten
  minutes may be twelve hours.
- **`sample`** — the actual topics. If these are not what a subscriber expects,
  nothing else matters.

To see the messages rather than the plan, `-dump` writes JSON Lines to stdout
and connects to nothing. With `-dry-run` it emits as fast as it can:

```sh
csvpub -dump -dry-run export.csv | head
```

```json
{"topic":"_ts","payload":"2026-03-01T08:00:00"}
{"topic":"plant.reactor.FIC102.pv","payload":"15.02"}
{"topic":"plant.reactor.TIC101.mode","payload":"AUTO"}
{"topic":"plant.reactor.TIC101.pv","payload":"72.4137"}
```

This is the fastest way to answer "what will a subscriber actually see?", and it
needs no broker at all.

## Getting the topics right

The column header is the whole naming authority. There is no mapping file: a
subscriber that knows the column names knows the topics.

A header is treated as a path. It is split on `-path-sep` (default `/`) and
re-joined with the separator the transport uses:

| header | NATS | MQTT |
|---|---|---|
| `plant/reactor/TIC101/pv` | `plant.reactor.TIC101.pv` | `plant/reactor/TIC101/pv` |

### When a header contains the transport's separator

This is the most common startup failure with real exports:

```
column "DW_MASTER_VOLUME/CALC1/OUT2.CV": segment "OUT2.CV" contains the nats
separator ".", which would create a topic level that was not written
```

DCS exports often name tags `MODULE/BLOCK/PARAM.FIELD`. Under NATS the `.` in
`OUT2.CV` cannot survive as a literal — NATS subjects have no escape mechanism,
so a token simply cannot contain a dot. The same is true of `/` in MQTT topics.
`csvpub` refuses rather than silently emitting a level you did not write.

The fix is to say that the character *is* a level boundary. `-path-sep` takes a
set of characters, any one of which ends a segment:

```sh
csvpub -path-sep '/.' -prefix rt export.csv
```

```
rt.DW_MASTER_VOLUME.CALC1.OUT2.CV
```

That is usually what you wanted anyway: the parameter field becomes its own
token, so a subscriber can wildcard it — `rt.DW_MASTER_VOLUME.CALC1.*.CV` for
every block's CV, or `rt.DW_MASTER_VOLUME.>` for the whole module.

Widening the separator set can make two headers collide (`a/b` and `a.b` both
become `a.b`). That is caught before anything connects, naming both headers.

### The timestamp topic

A bare payload carries no time of its own, so each row is preceded by its
timestamp on `_ts`:

```
_ts                        2026-03-01T08:00:05
plant.reactor.TIC101.pv    72.5012
plant.reactor.TIC101.mode  AUTO
```

Hold the last `_ts` you saw and stamp arriving values with it. Three things
follow that are easy to get wrong:

- **It is a heartbeat.** A tag may not change for minutes, so silence on a tag
  proves nothing. Silence on `_ts` proves something. It is published even on a
  row where every cell is empty, for exactly that reason.
- **The association rests on ordering**, which no broker guarantees *across*
  topics. One publisher connection writes one ordered stream, so in practice you
  see the timestamp then its row — but if you need that guaranteed rather than
  reliable, do not build on this.
- **An empty cell publishes nothing.** There is no null and no placeholder, so a
  topic being silent at a given `_ts` means the source had no value there.

## Choosing a rate

`-rate` is a plain multiplier on the source's own timing. `-rate 60` replays an
hour in a minute; `-rate 0.5` takes twice as long as the recording did.

Deadlines are absolute, computed from the file's own timestamps rather than by
sleeping between rows, so a long file does not drift and a gap in the source
needs no special handling. If the tool falls behind — a slow broker, a
contended machine — it publishes immediately and **does not** speed up to catch
up. You will see a warning on stderr and a count in the closing summary.

### When it refuses to start

```
csvpub: demanded rate 2440.0 msg/s exceeds the cap of 1000 msg/s;
        the largest rate that fits is -rate 40.98
```

Message rate is columns × rows-per-second. A wide file at a high rate reaches
thousands of messages a second quickly, and the choices are to drop rows, flood
the broker, or refuse. `csvpub` refuses, and the number it prints is a rate that
will be accepted — it is truncated, not rounded, so you can paste it straight
back:

```sh
csvpub -rate 40.98 export.csv
```

If you need it faster, raise `-max-rate` deliberately once you know your broker
can take it. The ceiling exists so that the run either fits or says so, never
half-works.

### Long holes in the data

An overnight gap in a recording becomes an overnight stall in the replay. Clamp
it:

```sh
csvpub -max-gap 30s export.csv
```

This is a wall-clock clamp applied *after* `-rate` has divided, which is the
part people trip on: at `-rate 60` a ten-minute hole is already only ten seconds
of wall time, so `-max-gap 30s` leaves it alone.

One interaction to know: a `-max-gap` shorter than the nominal sample interval
shortens *every* gap, not just the holes, which raises the message rate. That is
accounted for in the ceiling, so it will be refused rather than flooding the
broker, and the message says `-max-gap` rather than `-rate` is what binds.

## Making it look live

By default the emitted timestamps are the ones in the file, which is right for
testing a calculation and wrong for feeding a display that expects today's data.

```sh
csvpub -retime -loop export.csv
```

`-retime` shifts the whole series so the first sample lands at now, preserving
the source intervals. `-loop` restarts on completion. Together they make an
endless live-looking feed from a finite recording.

Two things to expect:

- Above `-rate 1`, only the *first* sample lands on now. Source intervals are
  preserved, so at `-rate 3` the emitted timestamps advance three times faster
  than the wall clock. This is deliberate — the alternative would compress the
  data's own timing.
- Across a loop seam the timestamps continue increasing at the source interval
  rather than jumping back, so a consumer that assumes monotonic time stays
  happy. Without `-retime`, timestamps simply repeat each pass.

### Zones

Source timestamps are naive and files record no zone, so `csvpub` does not
guess. By default it emits what it read, `T`-separated and without an offset.

`-tz` interprets them in a named zone and emits RFC 3339 with a real offset:

```sh
csvpub -tz Europe/London -retime export.csv
```

```
2026-07-15T08:00:00+01:00
```

Two daylight-saving cases are worth knowing. A local time inside a
spring-forward gap does not exist, and is a **fatal startup error** naming the
row — normalising it silently would move the sample by an hour, so its timestamp
would no longer denote the instant the schedule places it at. A repeated
fall-back hour cannot be detected from naive text and is not an error; under
`-tz` the schedule correctly spends the real 3600 seconds there.

## Selecting part of a file

```sh
csvpub -start 08:00:00 -stop 09:00:00 export.csv
```

Both accept a full timestamp or a bare time of day resolved against the first
row's date, and `-stop` is inclusive. A bound that falls between rows moves
outward: `-start` to the first row at or after it, `-stop` to the last row at or
before it. The selection must leave at least two rows.

Under `-loop`, each pass restarts from `-start`.

## Several files at once

A fast analogue log and a slow status log often describe the same run. They
merge into one stream:

```sh
csvpub -align carry analogue.csv status.csv
```

- **`-align strict`** (the default) requires every file to present the same
  timestamp at each step. Any divergence is fatal and names both files and both
  timestamps. Use it when the files are supposed to be in lockstep and you want
  to know when they are not.
- **`-align carry`** lets the first file drive; the others contribute their last
  value at or before the current timestamp. This is right for state that
  persists between changes — a mode, a setpoint, an operator selection — and
  acceptable for slow analogue.

Under `carry`, a file that has not yet reached its first row contributes empty
cells, which publish nothing. So a status log starting ten minutes into the run
simply has no messages until then, rather than a placeholder.

A column header appearing in two files is an error: it would mean two sources
writing one topic.

## Brokers

NATS is the default. MQTT needs one flag:

```sh
csvpub -broker mqtt -url tcp://broker:1883 export.csv
```

The payloads are identical on both; only the topic separator differs.

MQTT adds `-qos 0|1`, `-client-id`, and `-retain`. Retained messages let a
subscriber joining mid-replay see the current value of every tag immediately —
useful for a demo, but they **outlive the run**, so a subscriber connecting the
next day is shown a value that is no longer being published. That is why it is
off by default.

A flag that does not apply to the chosen transport is a startup error rather
than an ignored no-op. `-retain` under NATS stops the run and says so, because
silently accepting it is how an afternoon disappears into wondering why late
subscribers see nothing.

### When the link drops

By default a dropped connection ends the run non-zero. That is deliberate: a
replay with a silent hole in it is worse than one that stopped and told you.

For a long unattended replay across a broker restart:

```sh
csvpub -on-disconnect pause -rate 5 export.csv
```

`pause` stops the clock, waits for the link, then resumes with the whole
schedule shifted by however long the outage lasted — rather than racing to catch
up, which would deliver a burst at the wrong times. It re-sends the row it was
publishing when the link dropped, which may duplicate the messages that got out
first. That trade is on purpose: the alternative is a gap.

## Reading the output

Everything except `-dump` goes to stderr, so `-dump` stays pipeable. A finished
run prints one summary line:

```
csvpub: 17281 messages over 4320 rows in 1h12m, 3 missed deadlines
```

Missed deadlines mean the schedule could not keep up at some point. A handful on
a busy machine is unremarkable; hundreds means the rate is too high for the
broker or the machine, and the replay's timing no longer resembles the source.

`SIGINT` and `SIGTERM` stop cleanly — flush, print the summary, exit 0.

## When something is wrong

Validation runs **before** anything connects, and reports every offending item
rather than stopping at the first. A broken export should cost one run, not an
afternoon of them, and a replay that dies at second zero is far cheaper than one
that quietly drops a column forty minutes in.

| Exit | Meaning |
|---|---|
| `0` | Success, including a clean stop on `SIGINT`/`SIGTERM`. |
| `1` | Validation failure, including a refused rate. **Nothing was published.** |
| `2` | Runtime failure — connection lost, malformed row, write error. |

Common startup failures and what they mean:

- *"segment … contains the nats separator"* — a header carries the transport's
  separator inside a level. Add it to `-path-sep`; see above.
- *"timestamp … does not parse with layout"* — the layout detected from row 1
  does not fit a later row. Pin it with `-ts-format`, or check for a mixed
  export.
- *"does not ascend"* — rows are out of order. `csvpub` will not sort them,
  because a file that is out of order is usually a sign of a bad export rather
  than a cosmetic problem.
- *"header … appears in both"* — two columns, or two files, resolve to one
  topic.
- *"demanded rate … exceeds the cap"* — see *When it refuses to start*.

For a bug report, `csvpub version` prints the exact build:

```
csvpub v0.2.0 (101058bc56a7)
```

A `, modified` suffix means the binary was built from a dirty tree and
corresponds to no commit.
