---
name: read-file
description: >
  Read any data file (CSV, JSON, Parquet, Avro, Excel, spatial, SQLite) or
  remote URL (S3, HTTPS). Use when user references a data file, asks "what's
  in this file", or wants to preview/profile a dataset. Not for source code.
  DO NOT USE THIS SKILL when: the user wants to run analytical SQL queries,
  aggregations, joins, or transformations on remote data — delegate to
  /duckdb-skills:query-cloud. DO NOT USE when the file is a .duckdb database
  — delegate to /duckdb-skills:attach-db.
argument-hint: <filename or URL> [question about the data]
allowed-tools:
  - Bash
  - run_in_terminal
---

# Skill: Read Data File

## Purpose
Read, describe, and preview any data file using DuckDB. Returns schema, row
count, and sample rows via `scripts/read_file.sh`.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Step 1 — Route and resolve

- `.duckdb` files → delegate to `/duckdb-skills:attach-db`.
- Analytical SQL on remote URLs → delegate to `/duckdb-skills:query-cloud`.
- Verify DuckDB: `command -v duckdb || echo "===FAILED==="`.
  If missing, delegate to `/duckdb-skills:install-duckdb`.
- Bare filename (no `/`): resolve with `find "$PWD" -maxdepth 3 -name "<file>" -print -quit`.
- URL with protocol prefix: use as-is.

## Step 2 — Set env vars and run

Set `FILE_PATH` (required). Set `READER` for known extensions — leave unset
to auto-dispatch via `read_any` macro.

| Extension | READER | EXTRA_INSTALL |
|-----------|--------|---------------|
| `.csv .tsv .tab .txt` | `read_csv` | |
| `.json .jsonl .ndjson .geojson .har` | `read_json_auto` | |
| `.parquet .pq` | `read_parquet` | |
| `.avro` | `read_avro` | |
| `.xlsx .xls` | `read_xlsx` | |
| `.shp .gpkg .fgb .kml` | `st_read` | `INSTALL spatial; LOAD spatial;` |
| `.db .sqlite .sqlite3` | `sqlite_scan` | `INSTALL sqlite_scanner; LOAD sqlite_scanner;` |
| `.ipynb` | — use `scripts/read_notebook.sh` instead | |
| unknown | leave `READER` unset | |

For remote URLs, set `REMOTE_PREFIX`:

| Protocol | REMOTE_PREFIX |
|----------|---------------|
| `http(s)://` | `LOAD httpfs;` |
| `s3://` | `LOAD httpfs; CREATE SECRET (TYPE S3, PROVIDER credential_chain);` |
| `gs://` | `LOAD httpfs; CREATE SECRET (TYPE GCS, PROVIDER credential_chain);` |
| `az:// abfss://` | `LOAD httpfs; LOAD azure; CREATE SECRET (TYPE AZURE, PROVIDER credential_chain);` |

Run:

```bash
export FILE_PATH="<resolved_path>"
export READER="read_parquet"           # or leave unset for auto
export REMOTE_PREFIX="LOAD httpfs;"    # only for URLs
export EXTRA_INSTALL=""                # only for spatial/sqlite
bash ./scripts/read_file.sh
```

For notebooks: `export FILE_PATH="<path>" && bash ./scripts/read_notebook.sh`

## Step 3 — Handle errors

- **Missing extension** → set `EXTRA_INSTALL` and retry, or delegate to
  `/duckdb-skills:install-duckdb <ext>`.
- **Parse error** → try a different `READER`, or unset it for auto-dispatch.
- **Remote 403/401** → tell user which env vars to export, or delegate to
  `/duckdb-skills:query-cloud`.
- **File not found** → `find` the workspace and suggest the correct path.

## Step 4 — Present results

Synthesize schema, row count, and sample into a concise answer. Do NOT dump
raw output. Note patterns (nulls, cardinality, date ranges) visible in the
sample.

## Constraints
- ALWAYS use `getenv()` for paths in SQL — never interpolate directly.
- DO NOT run `SELECT *` without `LIMIT` on files > 100 MB.
- Prefer direct `READER` over `read_any` when extension is unambiguous.

## Cross-skill integration
- `/duckdb-skills:query-cloud` — analytical queries on remote data
- `/duckdb-skills:attach-db` — DuckDB database files
- `/duckdb-skills:query` — SQL on local data
- `/duckdb-skills:install-duckdb <ext>` — missing extensions
- `/duckdb-skills:duckdb-docs <error>` — error lookup
