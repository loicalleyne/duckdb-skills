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

## Step 1 — Resolve path and validate

```bash
DB_PATH="<insert_user_provided_path_here>"
RESOLVED_PATH="$(cd "$(dirname "$DB_PATH")" 2>/dev/null && pwd)/$(basename "$DB_PATH")"
echo "Resolved: $RESOLVED_PATH" && echo "===DONE===" || echo "===FAILED==="
```

Check DuckDB: `command -v duckdb || echo "===FAILED==="`.
If missing, delegate to `/duckdb-skills:install-duckdb`.

Validate: `duckdb -init /dev/null "$RESOLVED_PATH" -c "PRAGMA version;" && echo "===DONE===" || echo "===FAILED==="`
Failure → report error and stop.

## Step 2 — Explore schema

```bash
export RESOLVED_PATH
bash ./scripts/explore_schema.sh
```

If no rows returned, note the database is empty and proceed.

## Step 3 — Resolve state directory and append

```bash
export RESOLVED_PATH
CREATE_STATE_DIR=1 source ../../scripts/resolve_state_dir.sh
bash ./scripts/append_state.sh
```

## Step 4 — Verify and report

```bash
duckdb -init "$STATE_DIR/state.sql" -c "SHOW TABLES;" && echo "===DONE===" || echo "===FAILED==="
```

Summarize: database path, alias, state file path, tables (name, column count,
row count). Confirm the database is active for `/duckdb-skills:query`.
If empty, suggest creating tables or importing data.
