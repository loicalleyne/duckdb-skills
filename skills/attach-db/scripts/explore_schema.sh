#!/usr/bin/env bash
# Explore schema of an attached DuckDB database.
# Requires: RESOLVED_PATH
set -euo pipefail
: "${RESOLVED_PATH:?ERROR: RESOLVED_PATH not set.}"

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
