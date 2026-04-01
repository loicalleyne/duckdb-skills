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
Query data hosted on remote URLs (HTTPS, S3, GCS, Azure, HuggingFace) using
DuckDB's httpfs extension. Handles secret configuration, extension loading,
and performance tuning for remote IO.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Triggers & Prerequisites
- **When to use:** User references a URL (`http://`, `https://`, `s3://`, `gs://`, `az://`, `hf://`) in their query or file path.
- **Prerequisites:** DuckDB installed, network access available.

## Step 1 — Detect protocol and install extensions

Determine the protocol from the URL and ensure the required extension is loaded:

| Protocol | Extension | Secret type |
|----------|-----------|-------------|
| `https://` | `httpfs` | None (public) or `BEARER` |
| `s3://` | `httpfs` | `S3` |
| `gs://` | `httpfs` | `GCS` |
| `az://` | `azure` | `AZURE` |
| `hf://` | `httpfs` | None (public HuggingFace datasets) |

```bash
duckdb :memory: -c "INSTALL httpfs; LOAD httpfs;" && echo "===DONE===" || echo "===FAILED==="
```

For Azure, also: `INSTALL azure; LOAD azure;`

If extensions fail to install, delegate to `/duckdb-skills:install-duckdb httpfs`.

## Step 2 — Configure secrets (if needed)

Only configure secrets when the user provides credentials or the URL requires
authentication. Do NOT prompt for credentials unprompted.

**S3:**
```sql
CREATE SECRET (TYPE S3, KEY_ID getenv('AWS_ACCESS_KEY_ID'), SECRET getenv('AWS_SECRET_ACCESS_KEY'), REGION getenv('AWS_DEFAULT_REGION'));
```

**GCS:**
```sql
CREATE SECRET (TYPE GCS, KEY_ID getenv('GCS_ACCESS_KEY_ID'), SECRET getenv('GCS_SECRET'));
```

**Azure:**
```sql
CREATE SECRET (TYPE AZURE, CONNECTION_STRING getenv('AZURE_STORAGE_CONNECTION_STRING'));
```

If env vars are not set and access fails with 403/401, tell the user which
environment variables to export and retry.

## Step 3 — Level 1: Discovery (schema & size)

For remote Parquet files, DuckDB reads only metadata for schema discovery:

```bash
duckdb :memory: -markdown -c "
LOAD httpfs;
DESCRIBE SELECT * FROM '<URL>';
" && echo "===DONE===" || echo "===FAILED==="
```

For remote CSV, schema detection requires downloading a sample. Use `LIMIT 0`
with `DESCRIBE` to minimize download.

## Step 4 — Level 2: Profiling (optional)

If the user asks a vague question about the remote data, preview first:

```bash
duckdb :memory: -markdown -c "
LOAD httpfs;
SELECT * FROM '<URL>' LIMIT 10;
" && echo "===DONE===" || echo "===FAILED==="
```

For large remote datasets, always use `LIMIT` on exploratory queries.

## Step 5 — Level 3: Execution

### Performance tuning for remote IO

DuckDB uses synchronous IO per thread for HTTP. Increase threads beyond CPU
core count (2-5x) to improve download parallelism:

```sql
SET threads = 16;  -- e.g., on an 8-core machine
```

Minimize downloaded data:
- Avoid `SELECT *` — select only needed columns so DuckDB fetches fewer row groups.
- Apply filters on columns used for partitioning or sorting to trigger predicate pushdown.
- Prefer partitioned or sorted Parquet files for maximum filter effectiveness.
- Use `EXPLAIN ANALYZE` to inspect the number of HTTP requests and total bytes transferred.

### Caching with cache_httpfs (recommended for repeated queries)

The `cache_httpfs` community extension adds transparent on-disk and in-memory
caching on top of `httpfs`. It caches data blocks, file metadata, glob results,
and file handles — dramatically reducing egress and latency on repeated access.

**Platform support:** macOS and Linux only.

Install and load (replaces `LOAD httpfs` — it loads httpfs automatically):

```bash
duckdb :memory: -c "INSTALL cache_httpfs FROM community; LOAD cache_httpfs;" && echo "===DONE===" || echo "===FAILED==="
```

Key settings (all optional — defaults are sensible):

| Setting | Default | Description |
|---------|---------|-------------|
| `cache_httpfs_type` | `on_disk` | `on_disk`, `in_mem`, or `noop` (disables cache, behaves as plain httpfs) |
| `cache_httpfs_cache_directory` | platform default | Directory for on-disk cache files |
| `cache_httpfs_cache_block_size` | 1 MiB | Block size for cache — smaller reduces read amplification |
| `cache_httpfs_enable_metadata_cache` | `true` | Cache file metadata (size, mtime) |
| `cache_httpfs_enable_glob_cache` | `true` | Cache glob/list results |
| `cache_httpfs_profile_type` | `noop` | Set to `temp` to inspect IO with `SELECT cache_httpfs_get_profile()` |

Example with profiling enabled:

```sql
LOAD cache_httpfs;
SET cache_httpfs_type = 'on_disk';  -- default, explicit for clarity
SET cache_httpfs_profile_type = 'temp';
```

Inspect cache state and performance:

```sql
FROM cache_httpfs_cache_status_query();        -- cached entries
FROM cache_httpfs_cache_access_info_query();    -- hit/miss stats
SELECT cache_httpfs_get_profile();              -- IO latency profile
SELECT cache_httpfs_get_ondisk_data_cache_size(); -- disk usage
```

To clear the cache: `SELECT cache_httpfs_clear_cache();`

To disable caching and fall back to plain httpfs without unloading:
```sql
SET cache_httpfs_type = 'noop';
SET enable_external_file_cache = true;
```

If `cache_httpfs` is not available (Windows, or install fails), fall back to
plain `LOAD httpfs` and continue without caching.

### Execute the query

Prefer `cache_httpfs` when available, fall back to `httpfs`:

```bash
duckdb :memory: -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
INSTALL cache_httpfs FROM community;
LOAD cache_httpfs;
SET threads = 16;
SET max_memory = '4GB';
<QUERY>;
SQL
```

If `cache_httpfs` fails to load (e.g., Windows), retry with plain httpfs:

```bash
duckdb :memory: -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
LOAD httpfs;
SET threads = 16;
SET max_memory = '4GB';
<QUERY>;
SQL
```

### Materializing remote data locally

If the user will query the same remote data repeatedly and caching is
insufficient (very large datasets, cross-session persistence needed),
download it once:

```bash
duckdb :memory: -c "
LOAD httpfs;
COPY (FROM '<URL>') TO 'local_copy.parquet' (FORMAT PARQUET);
" && echo "===DONE===" || echo "===FAILED==="
```

Then delegate to `/duckdb-skills:query` for subsequent local queries.

## Step 6 — Handle errors

- **Extension not loaded:** `INSTALL httpfs; LOAD httpfs;` and retry.
- **cache_httpfs install fails:** Fall back to plain `LOAD httpfs;` — caching is optional.
- **403/401 Forbidden:** Credentials required — tell user which env vars to set.
- **Network timeout:** Suggest retrying, or materializing with `COPY ... TO` for large files.
- **Stale cached data:** `SELECT cache_httpfs_clear_cache();` or `SELECT cache_httpfs_clear_cache_for_file('<URL>');`
- **Syntax/SQL error:** Use `/duckdb-skills:duckdb-docs <error keywords>` to look up correct syntax.

## Step 7 — Present results

Show the markdown table output. For natural language questions, provide a brief
interpretation.

If the result exceeds 100 rows, note truncation and suggest `LIMIT`.

**Pro-tip:** Remind the user they can materialize remote data locally with
`COPY (SELECT ...) TO 'output.parquet'` for faster repeated access.

## Cross-skill integration

- **Local queries:** After materializing, delegate to `/duckdb-skills:query`.
- **Doc search:** Use `/duckdb-skills:duckdb-docs` for httpfs syntax questions.
- **Extension install:** Use `/duckdb-skills:install-duckdb httpfs` if missing.
- **Caching extension:** Use `/duckdb-skills:install-duckdb cache_httpfs@community` if missing.
