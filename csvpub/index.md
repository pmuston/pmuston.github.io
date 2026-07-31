---
title: csvpub
---

[← all tools](../)

Replay a timestamped CSV onto **NATS** or **MQTT** on a scaled-time schedule,
one topic per column. Recorded process data — historian exports, logger dumps,
sensor captures — becomes the live stream it came from, so anything that expects
live data can be driven from an archive.

The column header is the whole naming authority: no mapping file, no translation
layer and no metadata on the wire. A subscriber that knows the column names
knows the topics.

## Install

```sh
brew tap pmuston/csvpub
brew trust pmuston/csvpub   # required for third-party taps
brew install csvpub
```

After installing, `man csvpub` has the full reference offline.

[User guide →](guide/)

## Usage

```sh
csvpub [flags] file.csv...
```

| Flag | Meaning |
|---|---|
| `-broker MODE` | `nats` (default) or `mqtt`. |
| `-url URL` | Broker address. Default `nats://127.0.0.1:4222` or `tcp://127.0.0.1:1883`. |
| `-prefix STR` | Topic prefix, e.g. `replay`. Recommended when the broker also carries real data. |
| `-path-sep STR` | Characters that separate levels in column headers; any one ends a segment. Default `/`. |
| `-ts-column NAME` | Timestamp column, by name or index. Default `timestamp`, else column 0. |
| `-ts-format LAYOUT` | Go reference layout. Detected from the first data row when omitted. |
| `-rate FLOAT` | Time multiplier. Default 1. |
| `-max-rate INT` | Message/second ceiling. Default 1000. |
| `-start TS` | First timestamp to publish. Full timestamp or bare `HH:MM:SS`. |
| `-stop TS` | Last timestamp to publish, inclusive. |
| `-loop` | Restart on completion. |
| `-retime` | Shift the first sample to now, preserving source intervals. |
| `-tz NAME` | Interpret source timestamps in an IANA zone; emit RFC 3339 with an offset. |
| `-max-gap DUR` | Clamp inter-row wall gaps, e.g. `30s`. Applied after `-rate` divides. |
| `-ts` | Publish the row timestamp on its own topic. Default true. |
| `-ts-topic S` | That topic's name. Default `_ts`. |
| `-qos N` | MQTT QoS, 0 or 1. Default 0. *(mqtt only)* |
| `-retain` | Publish retained, so late subscribers see current values. *(mqtt only)* |
| `-client-id STR` | MQTT client id. Default `csvpub-<pid>`. *(mqtt only)* |
| `-align MODE` | With several files: `strict` (default) or `carry`. |
| `-on-disconnect M` | `fail` (default) or `pause` to ride out an outage. |
| `-dump` | JSON Lines to stdout instead of publishing. |
| `-dry-run` | Print the plan and exit. |
| `-v` | Per-row progress to stderr. |

## Examples

```sh
# Print the plan without connecting to anything — worth doing first
csvpub -dry-run -prefix replay -rate 10 export.csv

# See the messages themselves, as fast as possible, no broker needed
csvpub -dump -dry-run export.csv | head

# Replay at ten times real time onto a local NATS
csvpub -prefix replay -rate 10 export.csv

# DCS-style tags where the parameter field is dot-separated
csvpub -path-sep '/.' -prefix rt export.csv

# Feed a dashboard that expects live data, indefinitely
csvpub -retime -loop -tz Europe/London export.csv

# One hour, to MQTT, retained so late subscribers see current values
csvpub -broker mqtt -retain -start 08:00:00 -stop 09:00:00 export.csv

# A fast analogue log and a slow status log as one stream
csvpub -align carry analogue.csv status.csv
```

A column header is a path: `plant/reactor/TIC101/pv` becomes the NATS subject
`plant.reactor.TIC101.pv`, or the MQTT topic `plant/reactor/TIC101/pv`.

## Behaviour

- **Payloads are the cell text, verbatim.** `-6.89454828e-05` is published as
  those exact bytes — never parsed and reprinted. An empty cell publishes
  nothing: no null, no placeholder, no quality flag.
- **Each row is preceded by its timestamp** on `_ts`, so a consumer can stamp
  arriving values with it. It is also a heartbeat — silence on a tag proves
  nothing, silence on `_ts` does — so it is published even on a row where every
  cell is empty.
- **Deadlines are absolute**, computed from the file's own timestamps rather
  than by sleeping between rows, so a long replay does not drift. A missed
  deadline publishes immediately and never compresses to catch up.
- **The rate ceiling refuses rather than degrades.** Above `-max-rate` the run
  exits 1 and prints the largest rate that fits, truncated so it can be pasted
  straight back in.
- **Validation runs before anything connects**, and reports every offending item
  rather than just the first. A replay that dies at second zero is far cheaper
  than one that quietly drops a column forty minutes in.
- **A flag that does not apply to the chosen transport is a startup error**, not
  an ignored no-op — `-retain` under NATS stops the run and says so.

## Exit status

| Code | Condition |
|---|---|
| `0` | Success, including a clean stop on `SIGINT`/`SIGTERM`. |
| `1` | Validation failure, including a refused rate. Nothing was published. |
| `2` | Runtime failure — connection lost, malformed row, write error. |

## Links

- [User guide](guide/)
- [Source & releases](https://github.com/pmuston/homebrew-csvpub)
- `csvpub version` prints the build revision for bug reports.
