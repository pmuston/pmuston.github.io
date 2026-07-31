---
title: Command-line tools
---

Small, focused command-line tools. Each one does a single job well and installs
via [Homebrew](https://brew.sh).

## clinote

A personal lab notebook for shell commands, in your browser. One Markdown file
is one notebook; a persistent shell runs the cells and outputs are spliced back
into the same `.md` — plain CommonMark, readable and correct on GitHub.

```sh
brew tap pmuston/tap
brew trust pmuston/tap
brew install pmuston/tap/clinote
```

[Documentation →](clinote/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/clinote)

---

## csvpub

Replay a timestamped CSV onto **NATS** or **MQTT** on a scaled-time schedule, one
topic per column. Turns a historian export or logger dump back into the live
stream it came from, so a dashboard, a balance calculation or an alarm rule can
be driven from an archive.

```sh
brew tap pmuston/csvpub
brew trust pmuston/csvpub
brew install csvpub
```

[Documentation →](csvpub/) &nbsp;·&nbsp;
[User guide →](csvpub/guide/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/homebrew-csvpub)

---

## cyq

Run a single **read-only** Cypher query against Neo4j and stream the result as
**CSV** or **JSON Lines** — a scriptable, pipe-friendly export, one query per
invocation.

```sh
brew tap pmuston/cyq
brew trust pmuston/cyq
brew install cyq
```

[Documentation →](cyq/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/homebrew-cyq)

---

## graphdb

An **in-memory graph database** with SQLite write-through persistence, serving a
subset of openCypher over HTTP/JSON. The whole graph lives in RAM and reads never
touch disk; SQLite is the durable store, written through on every mutation.

```sh
brew tap pmuston/graphdb
brew trust pmuston/graphdb
brew install graphdb
```

[Documentation →](graphdb/) &nbsp;·&nbsp;
[User guide →](graphdb/guide/) &nbsp;·&nbsp;
[Cypher reference →](graphdb/cypher/) &nbsp;·&nbsp;
[Neo4j parity →](graphdb/parity/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/homebrew-graphdb)

---

## gq

The graphdb-backed peer of **cyq**: run a single Cypher statement against a
[graphdb](https://github.com/pmuston/homebrew-graphdb) server and stream the
result as **CSV** or **JSON Lines**. Same flags as cyq, HTTP + bearer token
instead of Bolt + password.

```sh
brew tap pmuston/gq
brew trust pmuston/gq
brew install gq
```

[Documentation →](gq/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/homebrew-gq)

---

## json_query

Query JSON files using a native **dot-path syntax** or **SQL SELECT** statements
— a scriptable extract, one query per invocation, output as **CSV** or **JSONL**.

```sh
brew tap pmuston/json_query
brew install json_query
```

[Documentation →](json_query/) &nbsp;·&nbsp;
[User guide →](json_query/guide/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/homebrew-json_query)

---

## rednote

A **Redis notebook** in your browser. One Markdown file is one notebook; a
persistent connection is bound to it, so `SELECT`, `MULTI` and `WATCH` flow from
cell to cell. Replies are spliced back into the same `.md`, formatted the way
`redis-cli` prints them — so `(nil)` stays distinguishable from `""` and a value
holding arbitrary bytes survives exactly.

```sh
brew tap pmuston/rednote
brew trust pmuston/rednote
brew install rednote
```

[Documentation →](rednote/) &nbsp;·&nbsp;
[Five-minute demo →](rednote/demo/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/homebrew-rednote)

---

## reshape-cli

Convert tabular records between **JSON**, **JSONL**, and **CSV** — a Unix filter
that reads one format on stdin and writes another to stdout.

```sh
brew tap pmuston/reshape
brew trust pmuston/reshape
brew install reshape-cli
```

[Documentation →](reshape-cli/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/homebrew-reshape)

---

<sub>Each tool ships a man page (`man <tool>`) and a `--help` that links back
here.</sub>

---

## rt-interest

Subscribe to a NATS subject tree and watch the current value of a curated list
of tags in a browser, live. A diagnostic tool: it answers *is this arriving?*
rather than *what is the value?*, so a tag never seen, one last seen three hours
ago, and one seen 200ms ago all look different.

```sh
brew tap pmuston/rt-interest
brew trust pmuston/rt-interest
brew install rt-interest
```

[Documentation →](rt-interest/) &nbsp;·&nbsp;
[User guide →](rt-interest/guide/) &nbsp;·&nbsp;
[Source & releases](https://github.com/pmuston/homebrew-rt-interest)
