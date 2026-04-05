---
name: attach-external
description: >
  Attach an external database (PostgreSQL, SQLite, MySQL) to DuckDB for
  cross-database queries using DuckDB's scanner extensions.
  USE THIS SKILL when: the user asks to connect, attach, query, or federate
  data from PostgreSQL, Postgres, SQLite, MySQL, or MariaDB via DuckDB.
  DO NOT USE THIS SKILL when: the user wants to attach a DuckDB .duckdb file
  (use attach-db). DO NOT USE when querying remote files over HTTP/S3 (use
  query-cloud).
argument-hint: <database-type> <connection-string-or-path>
allowed-tools:
  - Bash
  - run_in_terminal
---

# Skill: Attach External Database

## Purpose
Connect an external database engine (PostgreSQL, SQLite, MySQL) to DuckDB
using scanner extensions. Writes the ATTACH to the shared state file.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Constraints
- **DO NOT** store passwords in plain text in `state.sql`. Use `getenv()`.
- **DO NOT** overwrite `state.sql` — check for duplicates and append.
- For connection string formats and troubleshooting, read
  `references/external-db-extensions.md`.

## Step 1 — Identify database type

| User mentions | EXTENSION | DB_TYPE |
|---------------|-----------|---------|
| postgres, postgresql, pg | `postgres` | `POSTGRES` |
| sqlite, .sqlite, .sqlite3 | `sqlite` | `SQLITE` |
| mysql, mariadb | `mysql` | `MYSQL` |

If unclear, ask the user.

## Step 2 — Install extension

```bash
command -v duckdb || echo "===FAILED==="
duckdb -init /dev/null :memory: -c "INSTALL <extension>; LOAD <extension>;" && echo "===DONE===" || echo "===FAILED==="
```

If missing, delegate to `/duckdb-skills:install-duckdb`.

## Step 3 — Build connection string

- **PostgreSQL:** `export PG_CONN="dbname=<db> user=<user> host=<host> port=5432"`
  Use `PGPASSWORD` env var for passwords.
- **SQLite:** Resolve to absolute path.
- **MySQL:** `export MYSQL_CONN="host=<host> user=<user> port=3306 database=<db>"`

## Step 4 — Test connection and explore schema

```bash
export EXTENSION="<ext>" CONN_STRING="<conn>" DB_TYPE="<TYPE>"
bash ./scripts/test_connection.sh
```

If it fails, read `references/external-db-extensions.md` for troubleshooting,
or use `/duckdb-skills:duckdb-docs <error keywords>`.

```bash
export ALIAS="<derived_alias>"
bash ./scripts/explore_schema.sh
```

## Step 5 — Resolve state directory and append

```bash
CREATE_STATE_DIR=1 source ../../scripts/resolve_state_dir.sh
export ALIAS STATE_DIR EXTENSION CONN_STRING DB_TYPE
bash ./scripts/append_state.sh
```

**Security for PostgreSQL/MySQL:** Set `SECURE_ATTACH` with `getenv()`:

```bash
export SECURE_ATTACH="ATTACH format('dbname={} user={} host={} password={}',
    getenv('PG_DB'), getenv('PG_USER'), getenv('PG_HOST'), getenv('PG_PASS'))
    AS $ALIAS (TYPE POSTGRES);"
bash ./scripts/append_state.sh
```

## Step 6 — Verify and report

```bash
duckdb -init "$STATE_DIR/state.sql" -markdown -c "
SELECT database_name, table_name
FROM duckdb_tables() WHERE database_name = '<alias>';
" && echo "===DONE===" || echo "===FAILED==="
```

Summarize: database type, alias, state file path, tables. Confirm available
for `/duckdb-skills:query`. Suggest: `SELECT * FROM <alias>.<table> LIMIT 10;`

## Cross-skill integration
- `/duckdb-skills:query` — SQL execution after attach
- `/duckdb-skills:attach-db` — for `.duckdb` files
- `/duckdb-skills:query-cloud` — for URLs (http/s3/gs)
- `/duckdb-skills:duckdb-docs` — extension error lookup
- `/duckdb-skills:install-duckdb <ext>` — missing extensions
