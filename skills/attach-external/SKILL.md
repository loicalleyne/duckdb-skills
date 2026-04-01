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
using scanner extensions, enabling cross-database SQL queries. Writes the
ATTACH to the shared state file for persistent sessions.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Constraints
- **DO NOT** store passwords in plain text in `state.sql`. Use `getenv()` to
  read credentials from environment variables.
- **DO NOT** overwrite the shared `state.sql` — always check for duplicates
  and append.
- For full connection string formats and troubleshooting, read
  `references/external-db-extensions.md`.

## Step 1 — Identify the database type

Determine the target from the user's input:

| User mentions | DB type | Extension | Type keyword |
|---------------|---------|-----------|-------------|
| postgres, postgresql, pg | PostgreSQL | `postgres` | `POSTGRES` |
| sqlite, .sqlite, .sqlite3 | SQLite | `sqlite` | `SQLITE` |
| mysql, mariadb | MySQL | `mysql` | `MYSQL` |

If unclear, ask the user which database they want to connect to.

## Step 2 — Check DuckDB and install the extension

```bash
command -v duckdb && echo "===DONE===" || echo "===FAILED==="
```

If not found, delegate to `/duckdb-skills:install-duckdb`.

Install and load the required extension:

```bash
duckdb :memory: -c "INSTALL <extension>; LOAD <extension>;" && echo "===DONE===" || echo "===FAILED==="
```

If installation fails, delegate to `/duckdb-skills:install-duckdb <extension>`.

## Step 3 — Build the connection string

### PostgreSQL
Have the user export credentials as environment variables for security:

```bash
export PG_CONN="dbname=<db> user=<user> host=<host> port=5432"
```

If a password is needed, use `PGPASSWORD` env var or prompt the user to set it.

### SQLite
Resolve the file path to absolute:

```bash
SQLITE_PATH="$(cd "$(dirname "<path>")" 2>/dev/null && pwd)/$(basename "<path>")"
```

### MySQL
```bash
export MYSQL_CONN="host=<host> user=<user> port=3306 database=<db>"
```

## Step 4 — Test the connection

```bash
duckdb :memory: -markdown -c "
LOAD <extension>;
ATTACH '<connection_string>' AS test_conn (TYPE <TYPE>);
SELECT table_name FROM duckdb_tables() WHERE database_name = 'test_conn';
DETACH test_conn;
" && echo "===DONE===" || echo "===FAILED==="
```

If this fails, read `references/external-db-extensions.md` for troubleshooting,
or use `/duckdb-skills:duckdb-docs <error keywords>` to search for the fix.

## Step 5 — Explore the schema

```bash
duckdb :memory: -markdown -c "
LOAD <extension>;
ATTACH '<connection_string>' AS <alias> (TYPE <TYPE>);
SELECT table_name, column_name, data_type
FROM duckdb_columns()
WHERE database_name = '<alias>'
ORDER BY table_name, column_index;
" && echo "===DONE===" || echo "===FAILED==="
```

## Step 6 — Resolve state directory and append

Use the same state directory convention as all duckdb-skills:

```bash
STATE_DIR=""
test -f .duckdb-skills/state.sql && STATE_DIR=".duckdb-skills"

if [ -z "$STATE_DIR" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
    PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
    test -f "$HOME/.duckdb-skills/$PROJECT_ID/state.sql" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
fi

if [ -z "$STATE_DIR" ]; then
    STATE_DIR=".duckdb-skills"
    mkdir -p "$STATE_DIR"
    grep -qxF '.duckdb-skills/' .gitignore 2>/dev/null || echo '.duckdb-skills/' >> .gitignore
fi
echo "State dir: $STATE_DIR" && echo "===DONE===" || echo "===FAILED==="
```

Derive alias from the database name. Check for duplicates and append:

```bash
ALIAS="<derived_alias>"

grep -q "ATTACH.*<TYPE>.*AS $ALIAS" "$STATE_DIR/state.sql" 2>/dev/null || \
cat >> "$STATE_DIR/state.sql" <<EOF
LOAD <extension>;
ATTACH '<connection_string>' AS $ALIAS (TYPE <TYPE>);
EOF
echo "===DONE==="
```

**Security note for PostgreSQL/MySQL:** If the connection string contains a
password, use `getenv()` in the ATTACH instead:

```sql
LOAD postgres;
ATTACH format('dbname={} user={} host={} password={}',
    getenv('PG_DB'), getenv('PG_USER'), getenv('PG_HOST'), getenv('PG_PASS'))
    AS pg_data (TYPE POSTGRES);
```

## Step 7 — Verify

```bash
duckdb -init "$STATE_DIR/state.sql" -markdown -c "
SELECT database_name, table_name
FROM duckdb_tables()
WHERE database_name = '<alias>';
" && echo "===DONE===" || echo "===FAILED==="
```

## Step 8 — Report

Summarize:
- **Database type**: PostgreSQL / SQLite / MySQL
- **Alias**: the alias used in the state file
- **State file**: the resolved path
- **Tables**: table names and column counts
- Confirm the database is now available for `/duckdb-skills:query`

Suggest the user can now run queries like:
`SELECT * FROM <alias>.<table> LIMIT 10;`

## Cross-skill integration

- **Querying:** After attach, delegate to `/duckdb-skills:query` for SQL execution.
- **DuckDB files:** For `.duckdb` files, use `/duckdb-skills:attach-db` instead.
- **Remote files:** For URLs (http/s3/gs), use `/duckdb-skills:query-cloud`.
- **Error lookup:** Use `/duckdb-skills:duckdb-docs` for extension-specific errors.
- **Extension install:** Use `/duckdb-skills:install-duckdb <ext>` if missing.
