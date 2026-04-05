#!/usr/bin/env bash
# Explore schema of an attached external database.
# Requires: EXTENSION, CONN_STRING, DB_TYPE, ALIAS
set -euo pipefail
: "${EXTENSION:?ERROR: EXTENSION not set.}"
: "${CONN_STRING:?ERROR: CONN_STRING not set.}"
: "${DB_TYPE:?ERROR: DB_TYPE not set.}"
: "${ALIAS:?ERROR: ALIAS not set.}"

duckdb -init /dev/null :memory: -markdown -c "
LOAD $EXTENSION;
ATTACH '$CONN_STRING' AS $ALIAS (TYPE $DB_TYPE);
SELECT table_name, column_name, data_type
FROM duckdb_columns()
WHERE database_name = '$ALIAS'
ORDER BY table_name, column_index;
"
EXIT_CODE=$?
[ $EXIT_CODE -ne 0 ] && { echo "===FAILED===" >&2; exit $EXIT_CODE; }
echo "===DONE==="
