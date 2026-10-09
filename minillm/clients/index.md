---
title: "minillm clients: getting started"
---

[← minillm](../)

# minillm clients: getting started

Two small command-line tools for a private LLM server, such as one set up with [minillm-server](../server/) or any other OpenAI-compatible endpoint:

- **`ask`**: one prompt in, one answer out. It streams, reads piped input, and can return checked JSON.
- **`llmbatch`**: one prompt template run over many documents, a few at a time, with JSON Lines out. An interrupted run can be resumed.

Both are single static binaries with no dependencies. They read stdin, write stdout and exit non-zero on failure, so they work with `jq`, `pdftotext`, `git` and shell scripts.

## Install

**macOS, or Linux with Homebrew:**

```bash
brew tap pmuston/minillm
brew trust pmuston/minillm     # recent Homebrew requires this for third-party taps
brew install minillm
```

**Linux, or any machine without Homebrew:**

```bash
curl -fsSL https://pmuston.github.io/install.sh | sh -s minillm
```

The script installs `ask` and `llmbatch` to `~/.local/bin` and the example templates to `~/.local/share/minillm/templates`, with no root needed. Run it again to upgrade. Use `VERSION=v0.1.1` to pin a version, or `BIN_DIR=/usr/local/bin` to install somewhere else.

Check the install with `ask -version` and `llmbatch -version`.

## Connect to the server

Add these to `~/.zshrc` or `~/.bashrc`:

```bash
export LLM_URL=http://macmini.local:8000/v1      # or the server's Tailscale name
export LLM_KEY=<the output of 'minillm-server key' on the server>
export LLM_MODEL=mlx-community/Qwen3.6-35B-A3B-4bit
```

`LLM_MODEL` must match the model the server runs. If it isn't set, the tools ask the server which model it has and use that. Check the connection with `ask -models`, then `ask "Say hello"`.

## `ask`: one prompt

Decide first whether the model should think. Leave thinking off (the default) for summaries, rewrites and extraction. Turn it on with `-think` for maths, logic and multi-step reasoning. Thinking is much slower: a hard problem can take several thousand thinking tokens.

```bash
ask "Explain PID integral windup in two sentences"
cat meeting-notes.md | ask "List the decisions and who owns each"   # stdin is appended to the prompt
pdftotext spec.pdf - | ask -s "You review functional specs" "What is missing?"
git diff | ask "Write a commit message for this change"
ask -think -show-thinking "How many primes are below 200?"   # reasoning goes to stderr
ask -json "Three Go HTTP routers as {\"routers\":[{\"name\":..,\"why\":..}]}" | jq .
ask -v "hello"          # adds token counts and tok/s
```

| Flag | Default | What it does |
| --- | --- | --- |
| `-s` | | System prompt |
| `-max` | 2048 | Maximum tokens to generate |
| `-t` | 0.3 | Temperature |
| `-think` | off | Let a thinking model reason first |
| `-show-thinking` | off | Print the reasoning to stderr |
| `-json` | off | Ask for a JSON object, and fail if the reply doesn't parse |
| `-no-stream` | off | Wait for the whole answer instead of streaming |
| `-v` | off | Print token counts and timing to stderr |
| `-model` | `$LLM_MODEL` | Use a different model |
| `-models` | | List the server's models |

`ask` warns on stderr when an answer was cut off at `-max`, and exits 1 if the answer is empty.

## `llmbatch`: a task over many documents

`llmbatch` fills a prompt template for each input, keeps a few requests in flight, and appends one JSON line per input to the output file. If a run is interrupted or some inputs fail, run the same command again: it skips everything that already succeeded.

### 1. Get the inputs into text

`llmbatch` reads `.txt` and `.md` files from directories (change this with `-ext`). Files named directly are read whatever their extension. Convert other formats first:

```bash
mkdir -p txt
for f in pdfs/*.pdf;  do pdftotext -layout "$f" "txt/$(basename "${f%.pdf}").txt"; done       # brew install poppler
for f in word/*.docx; do textutil -convert txt -output "txt/$(basename "${f%.docx}").txt" "$f"; done  # macOS; pandoc elsewhere
```

Inputs can also be JSON Lines with `id` and `text` fields on stdin. Pass `-` as the input:

```bash
jq -c '.[] | {id: .ticket, text: .body}' tickets.json | llmbatch -p triage.tmpl -o triage.jsonl -
```

### 2. Pick or write a template

Templates use Go `text/template` syntax with `{{.Text}}`, `{{.Name}}` and `{{.Path}}`. If a template doesn't mention `{{.Text}}`, the document is appended after it. Two examples come with the install:

- `summarise.tmpl`: a one-line description, key facts, and actions.
- `extract.tmpl`: title, type, date, people, organisations, summary and action items, as JSON.

They're in `$(brew --prefix)/share/minillm/templates` (Homebrew) or `~/.local/share/minillm/templates` (the curl install). Copy one and edit it. To see exactly what the model will get, run `llmbatch -p my.tmpl -dry-run txt/`.

### 3. Try a few, then run the lot

```bash
T=$(brew --prefix)/share/minillm/templates      # or ~/.local/share/minillm/templates
llmbatch -p $T/summarise.tmpl -n 3 -o trial.jsonl txt/          # the first 3 only
llmbatch -p $T/summarise.tmpl -j 3 -o summaries.jsonl txt/      # everything, 3 at a time
```

Progress goes to stderr, one line per document. The run ends with an overall tok/s figure, which is the number to compare when you tune `-j`. Each output line looks like this:

```
{"id":"txt/q3-report.txt","path":"txt/q3-report.txt","ok":true,"output":"…","finish_reason":"stop",
 "usage":{"prompt_tokens":2841,"completion_tokens":212,"total_tokens":3053},"seconds":4.1,"model":"…","at":"…"}
```

### 4. Extract structured data

With `-json`, the model must reply with a single JSON object. If the reply doesn't parse, the model is shown its reply and asked once more. The parsed object lands in a `json` field:

```bash
llmbatch -p $T/extract.tmpl -json -j 3 -o fields.jsonl txt/
jq -r 'select(.ok) | [.id, .json.title, .json.doc_type, .json.date] | @csv' fields.jsonl > fields.csv
```

Keep the temperature low for extraction (the default is 0.1). Name every field and its type in the template, and say what to use when a value is missing (`null` or `[]`). Otherwise the model tends to invent one.

### 5. Failures and resuming

- Network errors, 429s and 5xx responses are retried with backoff. Other errors are recorded with `"ok":false` and the reason.
- An empty answer, or one cut off at `-max` tokens, counts as a failure. Raise `-max` and run again.
- Running the same command again retries only the failures, and appends their new records. To get the latest record per input: `jq -s 'group_by(.id) | map(last)' summaries.jsonl`.
- Ctrl-C stops cleanly. Finished inputs are kept, and in-flight ones are left for the next run.
- `llmbatch` exits 1 if anything failed, so scripts and cron jobs can tell.

### 6. Long documents

Inputs longer than `-maxchars` (60,000 characters, roughly 15,000 tokens) are truncated and flagged `"truncated":true`. For longer documents, split them, summarise each piece, and combine the results:

```bash
mkdir -p parts && split -l 400 big-manual.txt parts/manual.
llmbatch -p $T/summarise.tmpl -o parts.jsonl parts/*
jq -r 'select(.ok) | .output' parts.jsonl | ask "Combine these section summaries into one summary of the whole manual"
```

Long prompts running together compete for the server's memory. Use `-j 1` for long documents if you see "empty answer" failures.

### 7. How many at once

The server generates up to `MAX_SEQS` requests together (4 by default). More at once raises total throughput, but each answer comes back more slowly. Run the same set of documents with `-j 1`, `-j 2` and `-j 4`, compare the final tok/s figures, and use the smallest `-j` beyond which the figure stops rising. Keeping `-j` at or below `MAX_SEQS` avoids requests just queuing on the server.

## From your own code

The server speaks the standard OpenAI API, so most libraries work once you change the base URL and key. For example, with Python's `openai` package:

```python
import os
from openai import OpenAI

client = OpenAI(base_url=os.environ["LLM_URL"], api_key=os.environ["LLM_KEY"])
r = client.chat.completions.create(
    model=os.environ["LLM_MODEL"], max_tokens=500, temperature=0.3,
    messages=[{"role": "user", "content": "Explain PID integral windup in two sentences."}],
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
print(r.choices[0].message.content)
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Connection refused | Check `LLM_URL`, and that `minillm-server status` on the server reports OK |
| 404 Not Found | `LLM_URL` must end in `/v1`, e.g. `http://macmini.local:8000/v1`. The tools print this hint when it's missing |
| 401 Unauthorized | `LLM_KEY` doesn't match the server's key |
| 422 Unprocessable Entity | `LLM_MODEL` doesn't match the server's model. Unset it to let the tools discover it |
| "empty answer" for long inputs run together | Lower `-j`, or lower `MAX_SEQS` on the server |
| `finish_reason: length` on thinking answers | The reasoning used the whole budget. Raise `-max`, or leave thinking off |
| `command not found` after the curl install | Add `~/.local/bin` to your PATH, as the installer suggests |
