---
name: query
description: >
  Run SQL queries against the attached DuckDB database or ad-hoc against local files.
  Accepts raw SQL or natural language questions. Uses DuckDB Friendly SQL idioms.
  USE THIS SKILL when: the user wants to query local files or an already-attached
  DuckDB database, run analytical SQL, convert file formats, or asks natural
  language questions about local data.
  DO NOT USE THIS SKILL when: the input references remote URLs (http/https/s3/gs)
  — delegate to /duckdb-skills:query-cloud. DO NOT USE when the user asks to
  attach a new DuckDB file — delegate to /duckdb-skills:attach-db. DO NOT USE
  when the user asks to connect to PostgreSQL, SQLite, or MySQL — delegate to
  /duckdb-skills:attach-external.
argument-hint: <SQL or question> [--file path]
allowed-tools:
  - Bash
  - run_in_terminal
---

Query local data using DuckDB. Three tiers: Discovery (metadata), Profiling
(preview), Execution (full query). Always use the lightest tier that answers
the question.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Step 1 — Routing

- URLs (`http://`, `s3://`, `gs://`) → delegate to `/duckdb-skills:query-cloud`.
- Attach `.duckdb`/`.db` → delegate to `/duckdb-skills:attach-db`.
- Connect PostgreSQL/SQLite/MySQL → delegate to `/duckdb-skills:attach-external`.

## Step 2 — Discovery (state & schema)

Resolve state directory:

```bash
source ../../scripts/resolve_state_dir.sh
```

- **Session mode** if `STATE_DIR` set and input references tables or is NL.
- **Ad-hoc mode** if `--file`, SQL references files, or no state.

Check DuckDB: `command -v duckdb || echo "===FAILED==="`.
If missing, delegate to `/duckdb-skills:install-duckdb`.

**Session schema:**
```bash
duckdb -init "$STATE_DIR/state.sql" -markdown -c "
SELECT table_name, column_name, data_type
FROM duckdb_columns() ORDER BY table_name, column_index;
" && echo "===DONE===" || echo "===FAILED==="
```

**Ad-hoc:** `du -m "FILE_PATH"` to check size. If > 500 MB, enforce `LIMIT`.

## Step 3 — Profiling (optional)

For NL questions where schema alone is insufficient:

```bash
duckdb -init "$STATE_DIR/state.sql" -markdown -c "SUMMARIZE SELECT * FROM <table>;" && echo "===DONE===" || echo "===FAILED==="
```

Skip if user provided exact SQL, schema is known, or query is bounded.

Before writing SQL, read `reference/friendly_sql.md` for idiomatic DuckDB
constructs (FROM-first, GROUP BY ALL, COLUMNS(*), etc.).

## Step 4 — Execution

**Ad-hoc (sandboxed):**
```bash
duckdb -init /dev/null :memory: -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
SET max_memory='4GB';
SET enable_external_access=false;
SET allow_persistent_secrets=false;
SET allowed_paths=['FILE_DIR_OR_PATH'];
SET lock_configuration=true;
<QUERY>;
SQL
```

**Session:**
```bash
duckdb -init "$STATE_DIR/state.sql" -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
SET max_memory='4GB';
<QUERY>;
SQL
```

## Step 5 — Handle errors

- **Syntax error:** show error, suggest fix, re-run.
- **Missing extension:** delegate to `/duckdb-skills:install-duckdb <ext>`, retry.
- **Table not found (session):** list with `FROM duckdb_tables()`, suggest fix.
- **File not found (ad-hoc):** `find "$PWD" -name "<filename>" 2>/dev/null`.
- **Unclear DuckDB error:** `/duckdb-skills:duckdb-docs <error keywords>`.

## Step 6 — Present & export

Show markdown table. For NL questions, add brief interpretation.
If > 100 rows, note truncation and suggest `LIMIT`.

Export: `COPY (<QUERY>) TO 'output.parquet' (FORMAT PARQUET);`
Formats: PARQUET, CSV, JSON, NDJSON.
