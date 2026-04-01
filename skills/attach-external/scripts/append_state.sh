#!/usr/bin/env bash
# Append an external ATTACH statement to the shared state.sql file.
# Requires: EXTENSION, CONN_STRING, DB_TYPE, ALIAS, STATE_DIR
# Optional: SECURE_ATTACH (full SQL ATTACH expression using getenv() for creds)
set -euo pipefail
: "${EXTENSION:?ERROR: EXTENSION not set.}"
: "${DB_TYPE:?ERROR: DB_TYPE not set.}"
: "${ALIAS:?ERROR: ALIAS not set.}"
: "${STATE_DIR:?ERROR: STATE_DIR not set. Source resolve_state_dir.sh first.}"

ATTACH_LINE="${SECURE_ATTACH:-ATTACH '$CONN_STRING' AS $ALIAS (TYPE $DB_TYPE);}"

grep -q "ATTACH.*AS $ALIAS" "$STATE_DIR/state.sql" 2>/dev/null || \
cat >> "$STATE_DIR/state.sql" <<EOF
LOAD $EXTENSION;
$ATTACH_LINE
EOF

echo "Alias: $ALIAS"
echo "===DONE==="
