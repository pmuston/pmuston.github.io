---
title: minillm
---

[← all tools](../)

A Mac mini (or any Apple Silicon Mac) as a **private LLM server** for your
network, plus two small clients for using it. The server keeps one model loaded
and speaks the standard OpenAI chat-completions API behind an API key; the
clients are single static binaries with no dependencies.

| Formula | Install it on | What you get |
| --- | --- | --- |
| `minillm-server` | the Apple Silicon Mac | vllm-mlx as a Homebrew service, with a built-in watchdog, and a `minillm-server` setup/status command |
| `minillm` | every client machine | `ask` (one prompt, streamed) and `llmbatch` (a template over many documents, JSON Lines out, resumable) |

## Install

### The server (Apple Silicon Mac, macOS 14+)

```sh
brew tap pmuston/minillm
brew trust pmuston/minillm   # required for third-party taps
brew install minillm-server
minillm-server setup
brew services start minillm-server
```

Read the [server guide](server/) first: the Mac needs a little one-time
preparation (GPU memory limit, no sleep) that Homebrew doesn't do.

### The clients, with Homebrew (macOS & Linux)

```sh
brew tap pmuston/minillm
brew trust pmuston/minillm
brew install minillm
```

### The clients on Linux / no package manager

```sh
curl -fsSL https://pmuston.github.io/install.sh | sh -s minillm
```

Installs `ask` and `llmbatch` to `~/.local/bin` and the example templates to
`~/.local/share/minillm/` — no root. Re-run to upgrade; pin with
`VERSION=v0.1.0`.

## Guides

- [Server: getting started](server/) — prerequisites, install, settings, day to day, troubleshooting
- [Clients: getting started](clients/) — install, connecting, `ask`, `llmbatch`, your own code
