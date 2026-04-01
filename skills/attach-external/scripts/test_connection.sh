#!/usr/bin/env bash
# Test a connection to an external database via DuckDB scanner extension.
# Requires: EXTENSION, CONN_STRING, DB_TYPE
set -euo pipefail
: "${EXTENSION:?ERROR: EXTENSION not set (postgres|sqlite|mysql).}"
: "${CONN_STRING:?ERROR: CONN_STRING not set.}"
: "${DB_TYPE:?ERROR: DB_TYPE not set (POSTGRES|SQLITE|MYSQL).}"

duckdb :memory: -markdown -c "
LOAD $EXTENSION;
ATTACH '$CONN_STRING' AS test_conn (TYPE $DB_TYPE);
SELECT table_name FROM duckdb_tables() WHERE database_name = 'test_conn';
DETACH test_conn;
" && echo "===DONE===" || echo "===FAILED==="
