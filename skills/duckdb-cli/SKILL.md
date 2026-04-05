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

DuckDB CLI best practices for non-interactive, scripted contexts.

## Guiding Principles

1. **Signal success/failure** — append `&& echo "===DONE===" || echo "===FAILED==="`.
2. **Prefer CLI flags over dot commands** — `-csv`, `-json`, `-line`, etc.
3. **Minimize output** — smallest format, add `LIMIT`, pipe through POSIX tools.
4. **Heredocs for multi-line SQL** — `<<'SQL'` (single-quoted) prevents shell expansion.
5. **Fail fast** — `-bail` stops on first error.
6. **CLI features** — `-init /dev/null` skips rc, `-readonly` for safety, `-noheader` for piping.

## Guardrails

- DO NOT use interactive dot commands (`.mode`, `.once`) in `-c` one-liners.
- DO NOT use unquoted heredocs (`<<SQL`) unless you want shell `$VARIABLE` expansion.
- DO NOT use `-json` for large datasets — use `-jsonlines` (one object per line, safe if truncated).
- DO NOT run multi-statement scripts without `-bail`.
- DO NOT use `SELECT *` on remote files — minimize downloaded data.

## Step 1 — Verify DuckDB is available

```bash
command -v duckdb && echo "===DONE===" || echo "===FAILED==="
```

If not found: `source ./scripts/get_duckdb_path.sh`.
Still missing → delegate to `/duckdb-skills:install-duckdb`.

## Step 2 — Invocation patterns

**One-liner:** `duckdb -init /dev/null :memory: -csv -c "SELECT 42 AS answer" && echo "===DONE===" || echo "===FAILED==="`

**Heredoc:**
```bash
duckdb -init /dev/null :memory: -json <<'SQL' && echo "===DONE===" || echo "===FAILED==="
SELECT table_name, estimated_size FROM duckdb_tables() ORDER BY estimated_size DESC LIMIT 10;
SQL
```

**Script file:** `duckdb mydb.duckdb -f setup.sql` (reads `~/.duckdbrc` first; use `-init /dev/null -f` to skip).

**Init file:** `duckdb -init state.sql -csv -c "FROM my_table LIMIT 5;"`

**Sequential format switching:** CLI args are processed left-to-right:
```bash
duckdb :memory: -csv -c 'SELECT 1 AS a' -json -c 'SELECT 2 AS b'
```

## Step 3 — Output format selection

For the full flag table, read `reference/cli_cheatsheet.md`.

Key tips:
- `-jsonlines` safer than `-json` for large output (survives truncation).
- `-line` ideal for single-row results or `DESCRIBE`.
- `-csv -noheader` with `LIMIT 1` extracts a scalar cleanly:
  `ROW_COUNT=$(duckdb -init /dev/null mydb.duckdb -csv -noheader -c "SELECT count() FROM t;")`
- `-separator '|'` overrides column delimiter without changing mode.

## Step 4 — Pipe integration

Read `reference/pipe_integration.md` for stdin/stdout patterns, POSIX tool
chaining, process substitution, and multi-format output examples.

## Step 5 — Performance tuning

Read `reference/performance_tuning.md` for memory limits, threads, Parquet
conversion, compression, spill-to-disk, and profiling patterns.

## Step 6 — Robustness & sandboxing

Read `reference/robustness_patterns.md` for `-bail`, timeouts, read-only mode,
rc skipping, exit code capture, large-query probing, and sandboxing.

## Cross-Skill Integration

- `/duckdb-skills:duckdb-docs <keywords>` — search docs for CLI features/errors
- `/duckdb-skills:read-file <path>` — quick file profiling
- `/duckdb-skills:query <SQL>` — stateful querying with attached databases
- `/duckdb-skills:install-duckdb <ext>` — install missing extensions
