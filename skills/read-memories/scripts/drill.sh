#!/usr/bin/env bash
# Drill down into a materialized memories table or clean it up.
#
# Usage:
#   DRILL_TERM="<narrower keyword>" STATE_DIR=".duckdb-skills" bash drill.sh
#   ACTION=cleanup STATE_DIR=".duckdb-skills" bash drill.sh
#
# Required env vars:
#   STATE_DIR — directory containing memories.duckdb
#
# Optional:
#   DRILL_TERM — narrower keyword to filter results
#   ACTION     — set to "cleanup" to delete memories.duckdb

set -euo pipefail
: "${STATE_DIR:?ERROR: STATE_DIR not set.}"

DB="$STATE_DIR/memories.duckdb"

if [ "${ACTION:-}" = "cleanup" ]; then
    rm -f "$DB"
    echo "Cleaned up $DB"
    echo "===DONE==="
    exit 0
fi

if [ ! -f "$DB" ]; then
    echo "ERROR: $DB not found. Run a search with MATERIALIZE=1 first."
    echo "===FAILED==="
    exit 1
fi

duckdb "$DB" -c "SELECT count() AS total_rows FROM memories;" && echo "===DONE===" || echo "===FAILED==="

if [ -n "${DRILL_TERM:-}" ]; then
    export DRILL_TERM
    duckdb "$DB" -line -c "
    FROM memories
    WHERE columns(*) ILIKE '%' || getenv('DRILL_TERM') || '%'
    LIMIT 20;
    " && echo "===DONE===" || echo "===FAILED==="
fi
