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

Query local data using DuckDB. Operates in three tiers: Discovery (metadata),
Profiling (preview), Execution (full query). Always use the lightest tier that
answers the question.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Step 1 — Routing and delegation

Check the user's input for external data references:
- If the input references URLs (`http://`, `https://`, `s3://`, `gs://`),
  immediately delegate to `/duckdb-skills:query-cloud` and exit.
- If the user asks to attach a `.duckdb` or `.db` file, delegate to
  `/duckdb-skills:attach-db` and exit.
- If the user asks to connect to PostgreSQL, SQLite, or MySQL, delegate to
  `/duckdb-skills:attach-external` and exit.

Otherwise, proceed with local execution.

## Step 2 — Level 1: Discovery (state & schema)

### Resolve state and determine mode

```bash
STATE_DIR=""
test -f .duckdb-skills/state.sql && STATE_DIR=".duckdb-skills"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
test -f "$HOME/.duckdb-skills/$PROJECT_ID/state.sql" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
```

- **Session mode** if: `STATE_DIR` is set and the input references table names,
  is natural language, or is SQL without file references.
- **Ad-hoc mode** if: `--file` flag present, SQL references file paths, or
  no state file found.

If the state file exists but any ATTACH fails, warn the user and fall back
to ad-hoc mode.

### Check DuckDB is installed

```bash
command -v duckdb && echo "===DONE===" || echo "===FAILED==="
```

If not found, delegate to `/duckdb-skills:install-duckdb`.

### Retrieve schema (lightweight — no data scanned)

**Session mode** — single-pass schema retrieval:

```bash
duckdb -init "$STATE_DIR/state.sql" -markdown -c "
SELECT table_name, column_name, data_type
FROM duckdb_columns()
ORDER BY table_name, column_index;
" && echo "===DONE===" || echo "===FAILED==="
```

**Ad-hoc mode** — check file size instantly with OS tools. Do NOT run
`SELECT count()` on raw files just to estimate size:

```bash
du -m "FILE_PATH" 2>/dev/null && echo "===DONE===" || echo "===FAILED==="
```

If a file is > 500 MB, enforce a `LIMIT` on all exploratory queries and warn
the user about potential query time.

## Step 3 — Level 2: Profiling (optional preview)

If the input is natural language (not valid SQL) and you are unsure of the
data's contents, run a lightweight profiling query before writing the final SQL:

```bash
duckdb -init "$STATE_DIR/state.sql" -markdown -c "
SUMMARIZE SELECT * FROM <table_or_file>;
" && echo "===DONE===" || echo "===FAILED==="
```

This provides min, max, unique counts, and null percentages — use these
statistics to write an accurate analytical query on the first try.

Skip this step if:
- The user provided exact SQL to run
- You already know the schema from Step 2
- The query is intrinsically bounded (`DESCRIBE`, `count()`, aggregations)

Use the schema context and the Friendly SQL reference below to generate the
most appropriate query.

## Step 4 — Level 3: Execution

Always use `-markdown` for LLM-readable output and set memory limits.

**Ad-hoc mode** (sandboxed — only referenced files accessible):

```bash
duckdb :memory: -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
SET max_memory='4GB';
SET enable_external_access=false;
SET allow_persistent_secrets=false;
SET allowed_paths=['FILE_DIR_OR_PATH'];
SET lock_configuration=true;
<QUERY>;
SQL
```

Replace `FILE_DIR_OR_PATH` with the actual path. For glob queries (`*.csv`),
use the parent directory path. If multiple files, include all paths in the list.

**Session mode** (user-trusted database):

```bash
duckdb -init "$STATE_DIR/state.sql" -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
SET max_memory='4GB';
<QUERY>;
SQL
```

Always use heredocs (`<<'SQL'`) for multi-line queries.

## Step 5 — Handle errors

- **Syntax error**: show the error, suggest a corrected query, and re-run.
- **Missing extension**: delegate to `/duckdb-skills:install-duckdb <ext>`, then retry.
- **Table not found** (session): list tables with `FROM duckdb_tables()` and suggest corrections.
- **File not found** (ad-hoc): use `find "$PWD" -name "<filename>" 2>/dev/null` to locate it.
- **Persistent or unclear DuckDB error**: use `/duckdb-skills:duckdb-docs <error keywords>` to search docs, apply fix, retry.

## Step 6 — Present results & data export

Show the markdown table output. For natural language questions, provide a brief
interpretation.

If the result exceeds 100 rows, note the truncation and suggest `LIMIT`.

**Data export**: If the user wants to save or convert data, write results to
disk:

```sql
COPY (<QUERY>) TO 'output.parquet' (FORMAT PARQUET);
```

Supported formats: `PARQUET`, `CSV`, `JSON`, `NDJSON`.

---

## DuckDB Friendly SQL Reference

When generating SQL, prefer these idiomatic DuckDB constructs:

### Compact clauses
- **FROM-first**: `FROM table WHERE x > 10` (implicit `SELECT *`)
- **GROUP BY ALL**: auto-groups by all non-aggregate columns
- **ORDER BY ALL**: orders by all columns for deterministic results
- **SELECT * EXCLUDE (col1, col2)**: drop columns from wildcard
- **SELECT * REPLACE (expr AS col)**: transform a column in-place
- **UNION ALL BY NAME**: combine tables with different column orders
- **Percentage LIMIT**: `LIMIT 10%` returns a percentage of rows
- **Prefix aliases**: `SELECT x: 42` instead of `SELECT 42 AS x`
- **Trailing commas** allowed in SELECT lists

### Query features
- **count()**: no need for `count(*)`
- **Reusable aliases**: use column aliases in WHERE / GROUP BY / HAVING
- **Lateral column aliases**: `SELECT i+1 AS j, j+2 AS k`
- **COLUMNS(*)**: apply expressions across columns; supports regex, EXCLUDE, REPLACE, lambdas
- **FILTER clause**: `count() FILTER (WHERE x > 10)` for conditional aggregation
- **GROUPING SETS / CUBE / ROLLUP**: advanced multi-level aggregation
- **Top-N per group**: `max(col, 3)` returns top 3 as a list; also `arg_max(arg, val, n)`, `min_by(arg, val, n)`
- **DESCRIBE table_name**: schema summary (column names and types)
- **SUMMARIZE table_name**: instant statistical profile
- **PIVOT / UNPIVOT**: reshape between wide and long formats
- **SET VARIABLE x = expr**: define SQL-level variables, reference with `getvariable('x')`

### Data import & export
- **Direct file queries**: `FROM 'file.csv'`, `FROM 'data.parquet'`
- **Globbing**: `FROM 'data/part-*.parquet'` reads multiple files
- **Auto-detection**: CSV headers and schemas are inferred automatically
- **COPY export**: `COPY (SELECT ...) TO 'output.parquet' (FORMAT PARQUET)` — also CSV, JSON, NDJSON

### Expressions and types
- **Dot operator chaining**: `'hello'.upper()` or `col.trim().lower()`
- **List comprehensions**: `[x*2 FOR x IN list_col]`
- **List/string slicing**: `col[1:3]`, negative indexing `col[-1]`
- **STRUCT.* notation**: `SELECT s.* FROM (SELECT {'a': 1, 'b': 2} AS s)`
- **Square bracket lists**: `[1, 2, 3]`
- **format()**: `format('{}->{}', a, b)` for string formatting

### Joins
- **ASOF joins**: approximate matching on ordered data (e.g. timestamps)
- **POSITIONAL joins**: match rows by position, not keys
- **LATERAL joins**: reference prior table expressions in subqueries

### Data modification
- **CREATE OR REPLACE TABLE**: no need for `DROP TABLE IF EXISTS` first
- **CREATE TABLE ... AS SELECT (CTAS)**: create tables from query results
- **INSERT INTO ... BY NAME**: match columns by name, not position
- **INSERT OR IGNORE INTO / INSERT OR REPLACE INTO**: upsert patterns
