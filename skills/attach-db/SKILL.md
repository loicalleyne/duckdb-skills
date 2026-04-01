---
name: attach-db
description: >
  Attach a DuckDB database file and write a SQL state file for persistent sessions.
  USE THIS SKILL when: the user asks to "connect", "load", "attach", or "explore"
  a specific .duckdb or .db file for the first time.
  DO NOT USE THIS SKILL when: the user is asking to run standard SQL queries on
  an already-attached database (use the query skill instead).
argument-hint: <path-to-database.duckdb>
allowed-tools:
  - Bash
  - run_in_terminal
---

Attach a DuckDB database file for interactive querying. Execute all steps
autonomously — do not stop to ask the user setup questions. Report what you
did at the end.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

**State file convention**: All skills share a single `state.sql` file per
project. Once resolved, any skill can use it with
`duckdb -init "$STATE_DIR/state.sql" -c "<QUERY>"`.

## Step 1 — Resolve the database path

Set `DB_PATH` to the user-provided path and resolve it to an absolute path:

```bash
DB_PATH="<insert_user_provided_path_here>"
RESOLVED_PATH="$(cd "$(dirname "$DB_PATH")" 2>/dev/null && pwd)/$(basename "$DB_PATH")"
echo "Resolved: $RESOLVED_PATH" && echo "===DONE===" || echo "===FAILED==="
```

If the file does not exist, DuckDB will create it automatically on first write.
Proceed to Step 2.

## Step 2 — Check DuckDB is installed

```bash
command -v duckdb && echo "===DONE===" || echo "===FAILED==="
```

If not found, delegate to `/duckdb-skills:install-duckdb` and then continue.

## Step 3 — Validate the database

```bash
duckdb "$RESOLVED_PATH" -c "PRAGMA version;" && echo "===DONE===" || echo "===FAILED==="
```

- **Success** → continue.
- **Failure** → report the error (e.g. corrupt file, not a DuckDB database) and stop.

## Step 4 — Explore the schema

Run a single query to extract all tables, column counts, and estimated sizes:

```bash
duckdb "$RESOLVED_PATH" -box -c "
SELECT
    t.table_name,
    count(c.column_name) AS column_count,
    t.estimated_size AS approx_row_count
FROM duckdb_tables() t
LEFT JOIN duckdb_columns() c ON t.table_name = c.table_name
GROUP BY t.table_name, t.estimated_size
ORDER BY t.table_name;
" && echo "===DONE===" || echo "===FAILED==="
```

If the query returns no rows, note that the database is empty and proceed.

## Step 5 — Resolve the state directory

Check if a state file already exists in either location. Default to the
project directory (Option 1) — do NOT ask the user.

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

## Step 6 — Append to the state file

`state.sql` is a shared, accumulative init file used by all duckdb-skills.
It may already contain macros, LOAD statements, secrets, or other ATTACH
statements. **Never overwrite it** — always check for duplicates and append.

Derive a clean alias from the filename (e.g. `my_data.duckdb` → `my_data`):

```bash
ALIAS="$(basename "$RESOLVED_PATH" | sed 's/\.[^.]*$//')"

grep -q "ATTACH.*$RESOLVED_PATH" "$STATE_DIR/state.sql" 2>/dev/null || \
cat >> "$STATE_DIR/state.sql" <<EOF
ATTACH IF NOT EXISTS '$RESOLVED_PATH' AS $ALIAS;
USE $ALIAS;
EOF
echo "===DONE==="
```

If the alias conflicts with an existing one in the file, suffix it (e.g. `my_data_2`).

## Step 7 — Verify the state file works

```bash
duckdb -init "$STATE_DIR/state.sql" -c "SHOW TABLES;" && echo "===DONE===" || echo "===FAILED==="
```

If this fails, fix the state file and retry.

## Step 8 — Report

Summarize for the user:

- **Database path**: the resolved absolute path
- **Alias**: the database alias used in the state file
- **State file**: the resolved `STATE_DIR/state.sql` path
- **Tables**: name, column count, row count for each table (or note the DB is empty)
- Confirm the database is now active for `/duckdb-skills:query`

If the database is empty, suggest creating tables or importing data.
