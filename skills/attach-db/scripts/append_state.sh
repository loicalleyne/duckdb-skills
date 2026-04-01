#!/usr/bin/env bash
# Append an ATTACH statement to the shared state.sql file.
# Requires: RESOLVED_PATH, STATE_DIR
set -euo pipefail
: "${RESOLVED_PATH:?ERROR: RESOLVED_PATH not set.}"
: "${STATE_DIR:?ERROR: STATE_DIR not set. Source resolve_state_dir.sh first.}"

ALIAS="$(basename "$RESOLVED_PATH" | sed 's/\.[^.]*$//')"

# Check for alias conflict and suffix if needed
if grep -q "AS $ALIAS" "$STATE_DIR/state.sql" 2>/dev/null; then
    SUFFIX=2
    while grep -q "AS ${ALIAS}_${SUFFIX}" "$STATE_DIR/state.sql" 2>/dev/null; do
        SUFFIX=$((SUFFIX + 1))
    done
    ALIAS="${ALIAS}_${SUFFIX}"
fi

grep -q "ATTACH.*$RESOLVED_PATH" "$STATE_DIR/state.sql" 2>/dev/null || \
cat >> "$STATE_DIR/state.sql" <<EOF
ATTACH IF NOT EXISTS '$RESOLVED_PATH' AS $ALIAS;
USE $ALIAS;
EOF

echo "Alias: $ALIAS"
echo "===DONE==="
