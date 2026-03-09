---
name: read-file
description: >
  Read and explore any data file (CSV, JSON, Parquet, Avro, Excel, spatial, …)
  by filename only — resolves the path automatically. Uses DuckDB + the magic
  extension for format auto-detection. Installs magic if needed.
argument-hint: <filename> [question about the data]
allowed-tools: Bash
---

You are helping the user read and analyze a data file using DuckDB.

Filename given: `$0`
Question: `${1:-describe the data}`

Follow these steps in order, stopping and reporting clearly if any step fails.

## Step 1 — Locate DuckDB (requires ≥ v1.5.0)

```bash
DUCKDB=$(command -v duckdb)
```

- **Not found** → invoke `/duckdb-claude-skills:install-duckdb` (no arguments) to install DuckDB, then re-check.
- **Found but version < 1.5.0** → tell the user the installed version is too old, then invoke `/duckdb-claude-skills:install-duckdb --update` to upgrade.
- **Found and version ≥ 1.5.0** → continue.

```bash
CURRENT=$(duckdb --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
```

## Step 2 — Resolve the filename to a full path

```bash
find "$PWD" -name "$0" -not -path '*/.git/*' 2>/dev/null
```

- **Zero results** → tell the user the file was not found and stop.
- **More than one result** → list all matches, ask the user to re-run with a fuller path, and stop.
- **Exactly one result** → use that full path for all subsequent steps (`RESOLVED_PATH`).

## Step 3 — Attempt to read the file (optimistic)

Try a sandboxed read without loading any extra extensions — this succeeds immediately for
built-in formats (CSV, plain text):

```bash
"$DUCKDB" :memory: -csv -c "LOAD magic; SET allowed_paths=['RESOLVED_PATH']; SET enable_external_access=false; SET allow_persistent_secrets=false; SET lock_configuration=true; SELECT column_name FROM (DESCRIBE FROM read_any('RESOLVED_PATH')); SELECT count(*) AS row_count FROM read_any('RESOLVED_PATH'); FROM read_any('RESOLVED_PATH') LIMIT 10;"
```

**If this succeeds** → skip to Step 5 (Answer).

**If this fails** (missing extension, or magic not found) → continue to Step 4.

Notes:
- All `LOAD` statements must precede `SET enable_external_access=false`.
- **Spatial files**: `st_read` globs for sidecar files using the filename stem. For spatial
  formats add a stem-wildcard to `allowed_paths`:
  `SET allowed_paths=['RESOLVED_PATH', 'RESOLVED_PATH_WITHOUT_EXTENSION.*']`

## Step 4 — Install required extensions and retry

Detect which extensions are needed, install them, then re-run the read:

```bash
# 4a — detect (also installs magic if missing)
"$DUCKDB" :memory: -csv -c "INSTALL magic FROM community; LOAD magic; SELECT magic_required_extensions('RESOLVED_PATH') AS required_exts;"

# 4b — install all required extensions in one call (skip if list is empty)
"$DUCKDB" :memory: -c "INSTALL <ext1>; INSTALL <ext2>;"

# 4c — retry the sandboxed read with all extensions loaded
"$DUCKDB" :memory: -csv -c "LOAD magic; LOAD <ext1>; LOAD <ext2>; SET allowed_paths=['RESOLVED_PATH']; SET enable_external_access=false; SET allow_persistent_secrets=false; SET lock_configuration=true; SELECT column_name FROM (DESCRIBE FROM read_any('RESOLVED_PATH')); SELECT count(*) AS row_count FROM read_any('RESOLVED_PATH'); FROM read_any('RESOLVED_PATH') LIMIT 10;"
```

The three SELECT statements in 4c produce three result sets printed sequentially in CSV format.

## Step 5 — Answer the question

Using the schema, row count, and sample rows gathered above, answer:

`${1:-describe the data: summarize column types, row count, and any notable patterns.}`
