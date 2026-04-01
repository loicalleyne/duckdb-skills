---
name: duckdb-cli
description: >
  Best practices for using DuckDB's CLI in non-interactive (scripted) mode.
  USE THIS SKILL when: writing bash scripts, building POSIX pipelines, chaining
  shell commands with DuckDB, or optimizing DuckDB performance/memory settings
  for the CLI.
  DO NOT USE THIS SKILL when: writing standard SQL queries (use the query skill
  instead) or asking about DuckDB's internal architecture.
argument-hint: <question about DuckDB CLI usage>
allowed-tools:
  - Bash
  - run_in_terminal
---

You are helping Copilot (and the user) use the DuckDB CLI efficiently in
non-interactive, scripted contexts — from shell scripts, pipelines, and
tool-call terminals.

## Guiding Principles

1. **Signal success or failure explicitly** — always append `&& echo "===DONE===" || echo "===FAILED==="` to every `duckdb` invocation so the caller can unambiguously detect the outcome.
2. **Prefer non-interactive flags over dot commands** — use command-line arguments (`-csv`, `-json`, `-line`, etc.) instead of `.mode` when running one-shot commands.
3. **Minimize output size** — choose the smallest output format that satisfies the need, add `LIMIT`, and pipe through POSIX tools rather than returning unbounded results.
4. **Use heredocs for multi-line SQL** — avoids shell quoting issues and keeps SQL readable.
5. **Fail fast** — use `-bail` when running a sequence of statements so the first error stops execution.
6. **Leverage CLI features** — use `-init /dev/null` to avoid load configuration, `-readonly` for safety, and `-noheader` when downstream tools supply their own headers.

---

## Guardrails & Common Pitfalls (What NOT to do)

* **DO NOT use interactive dot commands** (like `.mode` or `.once`) in `-c` one-liners. Use command-line flags (like `-csv` or `-json`) instead.
* **DO NOT use unquoted heredocs (`<<SQL`)** unless you explicitly want the shell to evaluate `$VARIABLES` inside your SQL. Always default to single-quoted `<<'SQL'`.
* **DO NOT use `-json` for large datasets.** It wraps output in a single array and can break if truncated. Always use `-jsonlines` for large queries.
* **DO NOT run multi-statement scripts without `-bail`.** Always use `-bail` in scripts so execution stops on the first error.
* **DO NOT use `SELECT *` on remote files** (HTTP/S3). Minimize downloaded data with explicit column lists and filters.

---

## Step 1 — Verify DuckDB is available

```bash
command -v duckdb && echo "===DONE===" || echo "===FAILED==="
```

If not found, use the included helper script to locate the latest installed version:

```bash
source ./scripts/get_duckdb_path.sh
```

If still not found, delegate to `/duckdb-skills:install-duckdb`.

---

## Step 2 — Choose the right invocation pattern

### One-liner with `-c`

Best for short, single-statement queries:

```bash
duckdb :memory: -csv -c "SELECT 42 AS answer" && echo "===DONE===" || echo "===FAILED==="
```

### Heredoc for multi-line SQL

Best for complex queries — avoids nested quoting and keeps SQL readable:

```bash
duckdb :memory: -json <<'SQL' && echo "===DONE===" || echo "===FAILED==="
SELECT
    table_name,
    estimated_size,
    column_count
FROM duckdb_tables()
ORDER BY estimated_size DESC
LIMIT 10;
SQL
```

Single-quote the heredoc delimiter (`<<'SQL'`) to prevent shell variable
expansion inside the SQL. Use `<<SQL` (unquoted) only when you intentionally
need shell interpolation.

### Script file with `-f`

For reusable SQL scripts:

```bash
duckdb mydb.duckdb -f setup.sql && echo "===DONE===" || echo "===FAILED==="
```

Note: `-f` still reads `~/.duckdbrc` first. Use `-init /dev/null -f script.sql`
to skip the rc file.

### Init file with `-init`

For loading configuration or state before an interactive or scripted session:

```bash
duckdb -init state.sql -csv -c "FROM my_table LIMIT 5;" && echo "===DONE===" || echo "===FAILED==="
```

### Sequential argument processing

CLI arguments are processed left-to-right, so you can chain format changes:

```bash
duckdb :memory: \
    -csv  -c 'SELECT 1 AS a, 2 AS b' \
    -json -c 'SELECT 3 AS c, 4 AS d' \
    && echo "===DONE===" || echo "===FAILED==="
```

This outputs CSV for the first query and JSON for the second.

---

## Step 3 — Select the right output format

Choose the format that best suits how the output will be consumed.

| Flag / Mode    | Use when                                                     |
|----------------|--------------------------------------------------------------|
| `-csv`         | Piping to `awk`, `cut`, `sort`, spreadsheets, or other tools |
| `-json`        | Consuming in programs (jq, Python, JS)                       |
| `-jsonlines`   | Streaming large results (one JSON object per line)           |
| `-line`        | Human-readable single-row exploration or schema inspection   |
| `-list`        | Lightweight pipe-delimited output (default separator `\|`)   |
| `-tabs`        | TSV — simpler than CSV when data has no tabs                 |
| `-noheader`    | Suppress column headers (combine with any format)            |
| `-markdown`    | Embedding results in docs or READMEs                         |
| `-box`         | Pretty terminal display with Unicode box-drawing             |
| `-table`       | ASCII-art table (wider compatibility than box)               |

### Key tips

- **`-jsonlines`** is safer than `-json` for large results: each line is valid
  JSON even if output is truncated, whereas `-json` wraps everything in an array
  whose closing `]` may be lost.
- **`-line`** is ideal for `DESCRIBE`, `SUMMARIZE`, or single-row results —
  outputs `key = value` pairs that are easy to grep.
- **`-noheader`** is useful when piping into tools that supply their own headers
  or when extracting a single value.
- **`-csv -noheader`** combined with `LIMIT 1` extracts a single scalar cleanly:

  ```bash
  ROW_COUNT=$(duckdb mydb.duckdb -csv -noheader -c "SELECT count() FROM my_table;")
  echo "Rows: $ROW_COUNT"
  ```

- **`-separator`** overrides the column delimiter: `-separator '|'` converts
  CSV output to pipe-delimited without changing mode.

---

## Step 4 — POSIX pipe integration

DuckDB reads from `/dev/stdin` and writes to `/dev/stdout`, making it a
first-class participant in Unix pipelines.

### Read from stdin

```bash
cat data.csv | duckdb -c "SELECT * FROM read_csv('/dev/stdin') LIMIT 5" \
    && echo "===DONE===" || echo "===FAILED==="
```

### Write to stdout (COPY)

```bash
duckdb mydb.duckdb -c "COPY (SELECT * FROM t WHERE x > 100) TO '/dev/stdout' WITH (FORMAT csv, HEADER)" \
    | gzip > filtered.csv.gz \
    && echo "===DONE===" || echo "===FAILED==="
```

### Full pipeline: transform in-flight

```bash
curl -sL https://example.com/data.csv \
    | duckdb -c "
        COPY (
            SELECT col1, col2, col1 + col2 AS total
            FROM read_csv('/dev/stdin')
            WHERE col1 > 0
        ) TO '/dev/stdout' WITH (FORMAT parquet)
    " > output.parquet \
    && echo "===DONE===" || echo "===FAILED==="
```

### Post-process with POSIX tools

Choose the right format for the downstream tool:

```bash
# Count matching rows with wc
duckdb mydb.duckdb -csv -noheader -c "FROM big_table WHERE status = 'error'" | wc -l

# Extract a column with cut
duckdb mydb.duckdb -csv -noheader -c "SELECT name, score FROM users ORDER BY score DESC LIMIT 20" \
    | cut -d',' -f1

# Filter with grep, sort with sort
duckdb mydb.duckdb -tabs -noheader -c "FROM logs" | grep 'ERROR' | sort -k2

# Pretty-print JSON with jq
duckdb mydb.duckdb -json -c "FROM config LIMIT 5" | jq '.[0]'

# Stream NDJSON to jq for line-by-line processing
duckdb mydb.duckdb -c ".mode jsonlines" -c "FROM events LIMIT 1000" | jq -c '.event_type'
```

### Combine multiple DuckDB invocations

```bash
# Use process substitution to join two sources
duckdb :memory: -csv -c "
    SELECT a.*, b.label
    FROM read_csv('/dev/fd/3') a
    JOIN read_csv('/dev/fd/4') b ON a.id = b.id
" 3< <(duckdb db1.duckdb -csv -c "FROM users") \
  4< <(duckdb db2.duckdb -csv -c "FROM labels") \
  && echo "===DONE===" || echo "===FAILED==="
```

### Write multiple output formats from one query

Use `.once` in a heredoc to write different formats from a single session:

```bash
duckdb mydb.duckdb <<'SQL' && echo "===DONE===" || echo "===FAILED==="
.mode csv
.once results.csv
SELECT * FROM summary;
.mode json
.once results.json
SELECT * FROM summary;
SQL
```

---

## Step 5 — Performance and resource tuning

### Memory and threads

```sql
-- Limit memory usage (useful in constrained environments)
SET memory_limit = '4GB';

-- Limit threads (useful to avoid HyperThreading overhead)
SET threads = 4;
```

Rule of thumb: **1–4 GB per thread**. Minimum ~125 MB per thread.

### Prefer Parquet over CSV for repeated access

Parquet has columnar layout, zonemaps, and metadata that enable projection and
filter pushdown. If you query the same file more than once, convert to Parquet:

```bash
duckdb -c "COPY (FROM read_csv('big.csv')) TO 'big.parquet' (FORMAT parquet)" \
    && echo "===DONE===" || echo "===FAILED==="
```

### Enable compression for in-memory databases

In-memory databases are uncompressed by default. For large datasets this can be
8× slower than compressed:

```bash
duckdb -cmd "ATTACH ':memory:' AS db (COMPRESS); USE db;" -c "..."
```

### Larger-than-memory workloads

DuckDB spills to disk automatically. Ensure `temp_directory` is set to fast
storage (SSD/NVMe):

```sql
SET temp_directory = '/tmp/duckdb_spill.tmp/';
```

For large imports/exports that cause OOM, disable insertion order preservation:

```sql
SET preserve_insertion_order = false;
```

### Querying remote files

When reading over HTTP/S3, DuckDB uses synchronous IO per thread. Increase
threads beyond CPU core count (2–5×) to improve parallelism:

```sql
SET threads = 16;  -- e.g., on an 8-core machine
```

Minimize downloaded data: avoid `SELECT *`, apply filters, prefer partitioned
or sorted Parquet files.

### Profiling slow queries

```bash
duckdb mydb.duckdb -c "EXPLAIN ANALYZE SELECT ..." && echo "===DONE===" || echo "===FAILED==="
```

Look for:
- Nested loop joins (replace with hash joins)
- Missing filter pushdown
- Cardinality explosions in joins

---

## Step 6 — Robustness patterns

### Bail on first error

```bash
duckdb mydb.duckdb -bail <<'SQL' && echo "===DONE===" || echo "===FAILED==="
CREATE TABLE t1 AS SELECT 1 AS id;
CREATE TABLE t2 AS SELECT * FROM nonexistent_table;  -- stops here
INSERT INTO t1 VALUES (2);  -- never reached
SQL
```

### Timeout long-running commands

```bash
timeout 60 duckdb mydb.duckdb -c "SELECT * FROM huge_table" \
    && echo "===DONE===" || echo "===FAILED==="
```

### Read-only mode for safety

```bash
duckdb -readonly mydb.duckdb -csv -c "FROM analytics LIMIT 100" \
    && echo "===DONE===" || echo "===FAILED==="
```

### Skip ~/.duckdbrc for reproducible results

```bash
duckdb -init /dev/null :memory: -c "SELECT 1" && echo "===DONE===" || echo "===FAILED==="
```

### Capture exit code

```bash
if duckdb mydb.duckdb -c "SELECT count() FROM my_table;"; then
    echo "Query succeeded"
else
    echo "Query failed with exit code $?"
fi
```

### Probe before running large queries

```bash
ROW_COUNT=$(duckdb mydb.duckdb -csv -noheader -c "SELECT count() FROM big_table;")
if [[ "$ROW_COUNT" -gt 1000000 ]]; then
    echo "Large table ($ROW_COUNT rows) — adding LIMIT"
fi
```

---

## Step 7 — Sandboxing ad-hoc file queries

When querying untrusted files, restrict access:

```bash
duckdb :memory: -csv <<'SQL' && echo "===DONE===" || echo "===FAILED==="
SET allowed_paths = ['./data/input.csv'];
SET enable_external_access = false;
SET allow_persistent_secrets = false;
SET lock_configuration = true;
SELECT * FROM read_csv('./data/input.csv') LIMIT 10;
SQL
```

---

## Quick Reference & Shortcuts

For a list of exact CLI flags (like `-tabs`, `-box`, `-noheader`) or
DuckDB-specific SQL shortcuts (like `GROUP BY ALL`, `FROM 'file.csv'`),
read the reference file:

```bash
cat reference/cli_cheatsheet.md
```

---

## Cross-Skill Integration

- **Doc search**: Use `/duckdb-skills:duckdb-docs <keywords>` to search the
  DuckDB documentation for any CLI feature, function, or error message.
- **File reading**: Use `/duckdb-skills:read-file <path>` for quick file
  profiling without writing SQL.
- **Query sessions**: Use `/duckdb-skills:query <SQL>` for stateful querying
  with attached databases.
- **Extension install**: Use `/duckdb-skills:install-duckdb <ext>` to install
  missing extensions.
