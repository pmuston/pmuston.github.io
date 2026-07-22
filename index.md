---
title: Command-line tools
---

Small, focused Unix utilities. Each one does a single job well and installs via
[Homebrew](https://brew.sh).

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
