---
title: rednote in five minutes
---

[← rednote](../)

# rednote in five minutes

Every command below has been run against Redis 8.4. Nothing here needs a Redis you care
about — it uses database 15 and a `demo:` prefix, and cleans up at the end.

## 0. What you need

rednote, and a Redis you can reach.

```bash
brew tap pmuston/rednote
brew trust pmuston/rednote   # required for third-party taps
brew install rednote
rednote version
```

```bash
redis-cli ping
```

If that prints `PONG`, you are set. If not, `brew install redis && brew services start
redis` on a Mac, or `docker run -d -p 6379:6379 redis:8`.

## 1. Make a notebook

```bash
rednote new demo.md
```

That writes a notebook with front matter, a heading and one starter cell that runs as
written, then serves it. It will not overwrite an existing file.

It prints the address and, importantly, **which server it is about to write to**:

```
rednote: http://127.0.0.1:8080  (demo.md, redis://127.0.0.1:6379/0)
```

That second half matters more here than in a SQL notebook. A SQLite notebook can say "in
memory, self-contained"; rednote never can, because Redis is a network service. Every run
of every notebook writes to a real server somewhere, and you should not have to guess
which one.

Open the page and press **Run** on the starter cell. The replies appear beneath it — and
are written into `demo.md` at the same time. Results are volatile: every run overwrites
the whole of a cell's result.

Stop it with Ctrl-C. The connection is closed on the way out.

## 2. Point it somewhere harmless

Database 15 keeps everything below out of reach of anything you care about. Edit the front
matter:

```yaml
---
notekit: 1
title: Demo
notekit-tool: rednote
rednote-url: redis://127.0.0.1:6379/15
---
```

Restart rednote to pick it up — the connection is opened once, when the notebook opens.

```bash
rednote demo.md
```

## 3. The things worth seeing

Replace the starter cell's body with each of these in turn, and press Run.

**Nothing is not empty.** The distinction a table cannot express, and the reason the
durable form is redis-cli's rather than csv:

```
DEL demo:empty
SET demo:empty ""
GET demo:empty
GET demo:missing
```

```
(integer) 0
OK
""
(nil)
```

**Values are bytes.** A value holding a NUL or invalid UTF-8 still has an exact printable
form, so the notebook stays valid CommonMark whatever a key contains:

```
SET demo:blob "caf\xc3\xa9 \x00 \xff"
GET demo:blob
STRLEN demo:blob
```

```
OK
"caf\xc3\xa9 \x00 \xff"
(integer) 9
```

**A hash reads as pairs.** rednote speaks RESP3, so this arrives as a map rather than a
flat array you have to re-pair by eye:

```
DEL demo:part
HSET demo:part sku PN-4471 desc "Bearing, 40mm" qty 12
HGETALL demo:part
```

```
(integer) 0
(integer) 3
1# "sku" => "PN-4471"
2# "desc" => "Bearing, 40mm"
3# "qty" => "12"
```

**An error does not stop the cell.** Redis carries on, so the commands after the failure
genuinely ran and the whole transcript is kept — persisted as an `error` block, in red:

```
DEL demo:counter
SET demo:counter hello
INCR demo:counter
GET demo:counter
```

```
(integer) 0
OK
(error) ERR value is not an integer or out of range
"hello"
```

**State carries between cells.** The notebook holds one connection open for as long as it
is open, so this is still in force in the next cell:

```
SELECT 14
```

Run that, then in the next cell:

```
CLIENT INFO
```

and look for `db=14`. A connection pool would have lost it.

**`INFO` is readable.** Under RESP3 the server marks it a verbatim reply, so it prints
raw rather than as one enormous quoted line:

```
INFO server
```

## 4. What it refuses, and why

```
SUBSCRIBE demo:channel
```

```
(error) rednote refused SUBSCRIBE: it puts the connection into subscriber mode, which never returns
```

A subscription never returns, so it would wedge the session rather than run in it. The
same goes for `MONITOR` and `PSYNC`. Blocking commands that *do* return are fine —
`BLPOP demo:nothing 30` runs, and the cancel button cuts it short.

```
FLUSHDB
```

```
(error) rednote refused FLUSHDB: it destroys data that is not in git, unlike this notebook. Start rednote with -allow-flush to permit it
```

Different reason: the notebook is in git and the data is not, so a stray Run All against
the wrong URL is unrecoverable in a way nothing else here is. When you mean it:

```bash
rednote -allow-flush demo.md
```

## 5. Editing the notebook itself

Click any paragraph to edit it in place; click a source fence to edit the commands. The
↑/↓ buttons on a cell move it. All of that is notekit's, and all of it is a byte-range
splice: nothing outside the range you changed is rewritten, so the file round-trips
byte-identically.

Reordering does not re-run anything. Document order is execution order, so moving a cell
changes what Run All does — that is your call to make, not the tool's.

## 6. Check what it wrote

The notebook is a plain file. Read it:

```bash
cat demo.md
```

If you have Go, you can lint it with notekit's own linter, which is the authority on
whether the file conforms:

```bash
go run github.com/pmuston/notekit/cmd/notefmt@latest check demo.md
```

Exit 0 is clean, 1 is a finding, 2 is a usage or I/O failure — so it works as a commit
gate.

## 7. Clean up

The starter cell wrote to database 0 before you moved the notebook to 15, so both need
clearing:

```bash
redis-cli -n 0 DEL rednote:greeting
redis-cli -n 15 --scan --pattern 'demo:*' | xargs -r redis-cli -n 15 DEL
rm demo.md
```
