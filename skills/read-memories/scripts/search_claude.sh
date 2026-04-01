#!/usr/bin/env bash
# Search Claude Code JSONL session files for a keyword.
#
# Required env vars:
#   SEARCH_PATH  — glob to .jsonl files (set by get_session_path.sh)
#   KEYWORD      — search term
#
# Optional:
#   MATERIALIZE  — set to "1" to write results to STATE_DIR/memories.duckdb
#   STATE_DIR    — directory for materialized output

set -euo pipefail
: "${SEARCH_PATH:?ERROR: SEARCH_PATH not set. Run get_session_path.sh first.}"
: "${KEYWORD:?ERROR: KEYWORD not set.}"

LIMIT_CLAUSE="LIMIT 40"
OUTPUT_TARGET=":memory:"
WRAP_CREATE=""

if [ "${MATERIALIZE:-}" = "1" ]; then
    : "${STATE_DIR:?ERROR: STATE_DIR required for materialization.}"
    mkdir -p "$STATE_DIR"
    OUTPUT_TARGET="$STATE_DIR/memories.duckdb"
    WRAP_CREATE="CREATE OR REPLACE TABLE memories AS"
    LIMIT_CLAUSE=""
fi

export KEYWORD
duckdb "$OUTPUT_TARGET" -c "
${WRAP_CREATE}
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  strftime(timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M') AS ts,
  message.role AS role,
  message.content::VARCHAR AS content
FROM read_ndjson('$SEARCH_PATH', auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE '%' || getenv('KEYWORD') || '%'
  AND message.role IS NOT NULL
ORDER BY timestamp
${LIMIT_CLAUSE};
" && echo "===DONE===" || echo "===FAILED==="
