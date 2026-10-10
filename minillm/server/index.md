---
title: "minillm server: getting started"
---

[← minillm](../)

# minillm server: getting started

The server turns an Apple Silicon Mac into a private LLM service for your network. It keeps one model loaded in memory and serves it through the standard OpenAI chat-completions API on port 8000, behind an API key. Any machine on your LAN or Tailscale can then use it, with the `ask` and `llmbatch` clients (see the [client guide](../clients/)) or with any OpenAI-compatible code.

```
 client machines                         the Mac
 ┌─────────────────────┐   HTTP + key   ┌──────────────────────────────────────┐
 │ ask, llmbatch,      │ ─────────────► │ brew service: minillm-server         │
 │ curl, Python, Go    │  LAN/Tailscale │   vllm-mlx on :8000 (up to 4 at once)│
 └─────────────────────┘                │   watchdog: 1-token test every 5 min │
                                        │ model in unified memory (~20 GB)     │
                                        └──────────────────────────────────────┘
```

The server is a Homebrew service, so launchd starts it at login and restarts it if it exits. The service also runs a watchdog. Once the model has loaded, it asks for one real token every 5 minutes, because a server can still answer `/v1/models` after its generation thread has died. After two failed checks in a row it stops vllm-mlx, and launchd starts it again.

## Before you start

**Hardware.** You need an Apple Silicon Mac running macOS 14 (Sonoma) or later. 32 GB of memory is the comfortable minimum for the default model (about 20 GB at 4-bit). Allow 25 GB of free disk for the model download.

**Software.** You need [Homebrew](https://brew.sh). The formula installs `uv` itself, and `uv` provides the Python that vllm-mlx runs on.

**One-time machine setup.** Homebrew doesn't do these, and shouldn't. Do them once:

1. **Let the GPU use more memory.** By default macOS limits how much unified memory the GPU can wire, and a 20 GB model needs more. On a 32 GB machine:

   ```bash
   sudo sysctl iogpu.wired_limit_mb=26000
   ```

   This setting resets at reboot. To make it permanent, add `iogpu.wired_limit_mb=26000` to `/etc/sysctl.conf`. `minillm-server setup` warns you if the limit is still low.

2. **Keep the Mac awake.** Run `sudo pmset -a sleep 0 disksleep 0`, and turn on automatic login, so the server comes back by itself after a power cut. Homebrew services are per-user LaunchAgents and only start once you log in.

3. **Stop any other model server.** Two models won't fit in 32 GB. If an Ollama service is running, stop it with `launchctl bootout gui/$(id -u)/local.ollama`. Quit LM Studio too.

4. **Optional:** turn on Remote Login (System Settings → General → Sharing) so you can manage the Mac over `ssh`.

## Install

```bash
brew tap pmuston/minillm
brew trust pmuston/minillm         # recent Homebrew requires this for third-party taps
brew install minillm-server
minillm-server setup
brew services start minillm-server
minillm-server logs                 # Ctrl-C to stop following
```

`minillm-server setup` is safe to run again. It does four things:

- installs the tested version of vllm-mlx with `uv` (into `~/.local/bin`);
- writes the default settings to `$(brew --prefix)/etc/minillm/config`;
- creates an API key in `$(brew --prefix)/etc/minillm/api-key` (mode 600);
- warns about anything it can't fix itself, such as the GPU memory limit or a running Ollama.

**The first start downloads the model** (about 20 GB, into `~/models/hf`), so allow 10–20 minutes. The log says `ready after …s` once the model answers.

The first time the server opens its port, macOS may ask whether to allow incoming connections. Allow it, or other machines can't reach the server.

## Check it

```bash
minillm-server status     # service state, settings and a one-token test
minillm-server test       # just the test; exits 0 if the server answers
```

Or by hand:

```bash
KEY=$(minillm-server key)
curl -s localhost:8000/v1/models -H "Authorization: Bearer $KEY"
curl -s localhost:8000/v1/chat/completions -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"mlx-community/Qwen3.6-35B-A3B-4bit","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":50,"chat_template_kwargs":{"enable_thinking":false}}'
```

## Connect the clients

`setup` ends by printing the three values each client machine needs:

```bash
export LLM_URL=http://macmini.local:8000/v1      # or the Mac's Tailscale name
export LLM_KEY=<the output of: minillm-server key>
export LLM_MODEL=mlx-community/Qwen3.6-35B-A3B-4bit
```

`LLM_MODEL` must match `MODEL` in the server's config. Installing the clients is covered in the [client guide](../clients/).

## Settings

The settings file is at `$(brew --prefix)/etc/minillm/config`; `minillm-server config` prints the path. Homebrew keeps it across upgrades. After editing it, run `brew services restart minillm-server`.

| Setting | Default | What it does |
| --- | --- | --- |
| `MODEL` | `mlx-community/Qwen3.6-35B-A3B-4bit` | The one model served. This MoE model runs at about 60 tok/s on a 32 GB M6 mini. `mlx-community/Qwen3.8-27B-4bit` is more accurate, but runs at about 9 tok/s |
| `HOST` | `0.0.0.0` | Listen on every interface. Use `127.0.0.1` to allow only local calls |
| `PORT` | `8000` | The port clients connect to |
| `MAX_SEQS` | `4` | Requests generated together. More raises total throughput, but each request gets slower and needs more memory for context |
| `MAX_TOKENS` | `16384` | Server-wide cap on one answer, thinking included |
| `TIMEOUT` | `900` | Seconds before a request is abandoned. Long thinking runs need the headroom |
| `REASONING` | `qwen3` | Moves `<think>` text into a separate `reasoning` field. Leave it empty for non-Qwen models |
| `TOOL_PARSER` | `qwen3_xml` | The model's tool-call format, needed for tool-using clients such as `agent`. Without it, multi-step tool use breaks down. Leave it empty for models that don't use Qwen's XML tool format |
| `WATCHDOG_INTERVAL` | `300` | Seconds between health checks once the model is up |
| `WATCHDOG_FAILS` | `2` | Failed checks in a row before a restart |
| `VLLM_MLX_VERSION` | the tested release | Pins a different vllm-mlx. Run `minillm-server setup` after changing it |

To change the API key, replace the contents of `api-key` and restart the service. Every client then needs the new key.

## Day to day

| To | Run |
| --- | --- |
| Follow the log, including watchdog restarts | `minillm-server logs` |
| Check health | `minillm-server status` |
| Restart | `brew services restart minillm-server` |
| Stop it (frees the memory) | `brew services stop minillm-server` |
| Change model | edit `MODEL` in the config, then restart. The first start downloads the new model |
| Upgrade minillm | `brew update && brew upgrade minillm-server && minillm-server setup && brew services restart minillm-server`. Run `brew update` first: without it Homebrew may not have seen a release from the last day |
| Check memory | `memory_pressure`, and `sysctl iogpu.wired_limit_mb` (should be 26000) |

`setup` after an upgrade is how a new pinned vllm-mlx version gets installed. If the pin hasn't changed, `setup` does nothing.

## Security

The API key travels over plain HTTP. That's fine on your home network or over Tailscale, which encrypts the link. Never forward port 8000 on your router. If anything outside your tailnet ever needs the server, put a TLS reverse proxy such as Caddy in front and keep the key. The service refuses to start without a key.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Log says `no API key` or `vllm-mlx not found` | `setup` hasn't been run | `minillm-server setup`, then restart |
| `test` fails just after a start | The model is still loading or downloading | Wait for `ready after …s` in the log |
| Connection refused from another machine | `HOST` is `127.0.0.1`, or the macOS firewall prompt was declined | Set `HOST=0.0.0.0`; allow the process in System Settings → Network → Firewall |
| 404 Not Found from a client | The client's `LLM_URL` doesn't end in `/v1` | Use `http://<host>:8000/v1` |
| 401 Unauthorized | The client's `LLM_KEY` doesn't match | Copy `minillm-server key` again; watch for a trailing newline |
| 422 Unprocessable Entity | The request has no `"model"` field, or the model name is wrong | Set `LLM_MODEL` to the config's `MODEL` |
| `health check failed` lines, then a restart | Generation stopped responding | The watchdog has already restarted it. If it happens often, lower `MAX_SEQS` |
| Model fails to load at start | vllm-mlx doesn't support that model's architecture | Try the `lmstudio-community` MLX build, or a text-only model |
| Metal out-of-memory errors | Too many long requests at once | Lower `MAX_SEQS`, or use `-j 1` / a lower `-maxchars` on the client |
| Slower than expected | The wired limit reset at reboot, or something else is using the GPU | Check `sysctl iogpu.wired_limit_mb`; stop Ollama and LM Studio |

## Moving from install.sh

If the Mac was set up with the old `server/install.sh`, `minillm-server setup` takes care of the move:

- It copies `~/llm-server/config` and `~/llm-server/api-key`, so clients keep working with the same key.
- It stops the `local.llm-server` and `local.llm-watchdog` LaunchAgents and moves their plists to `~/llm-server/retired-launchagents/`.

The old log stays at `~/Library/Logs/llm-server.log`. Once the brew service is running you can delete `~/llm-server`.

## Uninstall

```bash
brew services stop minillm-server
brew uninstall minillm-server
uv tool uninstall vllm-mlx
rm -rf "$(brew --prefix)/etc/minillm" ~/models/hf     # settings, key and the downloaded model
```
