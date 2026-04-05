---
name: query-cloud
description: >
  Query remote data over HTTP, S3, GCS, or Azure using DuckDB with httpfs.
  USE THIS SKILL when: the user's SQL or file path references http://, https://,
  s3://, gs://, az://, or hf:// URLs, or they ask to query remote/cloud data.
  DO NOT USE THIS SKILL when: the data is a local file (use the query skill)
  or when attaching a remote database engine like Postgres (use attach-external).
argument-hint: <URL or SQL referencing remote data>
allowed-tools:
  - Bash
  - run_in_terminal
---

# Skill: Query Remote / Cloud Data

## Purpose
Query data on remote URLs (HTTPS, S3, GCS, Azure, HuggingFace) using DuckDB's
httpfs extension. Handles secrets, extension loading, and performance tuning.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Step 1 — Detect protocol and install extensions

| Protocol | Extension | Secret type |
|----------|-----------|-------------|
| `https://` | `httpfs` | None or `BEARER` |
| `s3://` | `httpfs` | `S3` |
| `gs://` | `httpfs` | `GCS` |
| `az://` | `azure` | `AZURE` |
| `hf://` | `httpfs` | None |

```bash
duckdb -init /dev/null :memory: -c "INSTALL httpfs; LOAD httpfs;" && echo "===DONE===" || echo "===FAILED==="
```

For Azure: also `INSTALL azure; LOAD azure;`. If fails, delegate to
`/duckdb-skills:install-duckdb httpfs`.

## Step 2 — Configure secrets (if needed)

Only when user provides credentials or URL requires auth:

- **S3:** `CREATE SECRET (TYPE S3, KEY_ID getenv('AWS_ACCESS_KEY_ID'), SECRET getenv('AWS_SECRET_ACCESS_KEY'), REGION getenv('AWS_DEFAULT_REGION'));`
- **GCS:** `CREATE SECRET (TYPE GCS, KEY_ID getenv('GCS_ACCESS_KEY_ID'), SECRET getenv('GCS_SECRET'));`
- **Azure:** `CREATE SECRET (TYPE AZURE, CONNECTION_STRING getenv('AZURE_STORAGE_CONNECTION_STRING'));`

If env vars unset and 403/401, tell user which vars to export.

## Step 3 — Discovery (schema)

```bash
duckdb -init /dev/null :memory: -markdown -c "LOAD httpfs; DESCRIBE SELECT * FROM '<URL>';" && echo "===DONE===" || echo "===FAILED==="
```

## Step 4 — Profiling (optional)

```bash
duckdb -init /dev/null :memory: -markdown -c "LOAD httpfs; SELECT * FROM '<URL>' LIMIT 10;" && echo "===DONE===" || echo "===FAILED==="
```

## Step 5 — Execution

### Performance tuning
- `SET threads = 16;` — increase beyond CPU count (2-5x) for remote IO.
- Avoid `SELECT *` — select only needed columns for predicate pushdown.
- Use `EXPLAIN ANALYZE` to inspect HTTP request count and bytes transferred.

### Caching (recommended for repeated queries)
For `cache_httpfs` settings and status queries, read `reference/cache_httpfs.md`.

Prefer `cache_httpfs` when available, fall back to `httpfs`:

```bash
duckdb -init /dev/null :memory: -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
INSTALL cache_httpfs FROM community;
LOAD cache_httpfs;
SET threads = 16;
SET max_memory = '4GB';
<QUERY>;
SQL
```

If `cache_httpfs` fails (e.g., Windows):
```bash
duckdb -init /dev/null :memory: -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
LOAD httpfs;
SET threads = 16;
SET max_memory = '4GB';
<QUERY>;
SQL
```

### Materialize locally
For repeated access to large remote data:
```bash
duckdb -init /dev/null :memory: -c "LOAD httpfs; COPY (FROM '<URL>') TO 'local_copy.parquet' (FORMAT PARQUET);" && echo "===DONE===" || echo "===FAILED==="
```
Then delegate to `/duckdb-skills:query` for local queries.

## Step 6 — Handle errors

- **Extension not loaded:** `INSTALL httpfs; LOAD httpfs;` and retry.
- **cache_httpfs fails:** fall back to plain `LOAD httpfs;`.
- **403/401:** tell user which env vars to set.
- **Network timeout:** retry or materialize with `COPY ... TO`.
- **Stale cache:** `SELECT cache_httpfs_clear_cache();`
- **SQL error:** `/duckdb-skills:duckdb-docs <error keywords>`.

## Step 7 — Present results

Show markdown table. For NL questions, add interpretation.
If > 100 rows, suggest `LIMIT`. Remind user they can materialize locally.

## Cross-skill integration
- `/duckdb-skills:query` — after materializing locally
- `/duckdb-skills:duckdb-docs` — httpfs syntax questions
- `/duckdb-skills:install-duckdb httpfs` — missing extension
- `/duckdb-skills:install-duckdb cache_httpfs@community` — caching extension
