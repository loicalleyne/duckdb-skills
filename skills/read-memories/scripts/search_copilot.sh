#!/usr/bin/env bash
# Search VS Code Copilot Chat session files for a keyword.
#
# Strategy: use find + grep to identify only session files containing KEYWORD,
# then feed that small set to DuckDB for structured extraction. This avoids
# loading hundreds of large JSON files and prevents OOM / timeouts.
#
# Required env vars:
#   SEARCH_PATH  — glob/file-list for session JSON files (set by get_session_path.sh)
#   KEYWORD      — search term
#   BASE         — workspaceStorage base directory
#
# Optional:
#   MATERIALIZE  — set to "1" to write results to STATE_DIR/memories.duckdb
#   STATE_DIR    — directory for materialized output

set -euo pipefail
: "${SEARCH_PATH:?ERROR: SEARCH_PATH not set. Run get_session_path.sh first.}"
: "${KEYWORD:?ERROR: KEYWORD not set.}"
: "${BASE:?ERROR: BASE not set.}"

readonly FILTERED_LIST="/tmp/copilot_matched_$$.txt"
TEMP_DB="/tmp/copilot_search_$$.duckdb"
trap 'rm -f "$FILTERED_LIST" "$TEMP_DB" "${TEMP_DB}.wal"' EXIT

# ── Phase 0: POSIX pre-filter ─────────────────────────────────────────────
# grep -Fli: fixed-string, list-files-only, case-insensitive (matches ILIKE).
# find -print0 | xargs -0: safe with spaces in paths.
# -P4: parallel grep workers (GNU xargs; harmless no-op if unsupported).
echo "Pre-filtering session files for: $KEYWORD"
find "$BASE" -path '*/chatSessions/*.json' -type f -print0 2>/dev/null \
  | xargs -0 -P4 grep -Fli "$KEYWORD" 2>/dev/null \
  > "$FILTERED_LIST" || true

MATCH_COUNT=$(wc -l < "$FILTERED_LIST" | tr -d ' ')
if [ "$MATCH_COUNT" -eq 0 ]; then
    echo "No session files contain '$KEYWORD'."
    echo "===DONE==="
    exit 0
fi
echo "Matched $MATCH_COUNT / $(find "$BASE" -path '*/chatSessions/*.json' -type f 2>/dev/null | wc -l | tr -d ' ') session files."

# ── Build DuckDB file-list from filtered results ──────────────────────────
# SET VARIABLE + getvariable() avoids subquery-in-table-function errors.
SET_VARIABLE_STMT="SET VARIABLE file_list = (
    SELECT string_split(rtrim(content, chr(10)), chr(10))
    FROM read_text('$FILTERED_LIST')
);"
READ_EXPR="read_json(
    getvariable('file_list'),
    maximum_object_size=78643200, union_by_name=true, filename=true)"

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

# ── Phase 1: load only matched sessions into temp DB (spill-safe) ─────────
duckdb -init /dev/null "$TEMP_DB" -c "
PRAGMA temp_directory='/tmp';
${SET_VARIABLE_STMT}
CREATE TABLE sessions AS
  SELECT * FROM $READ_EXPR;
"
EXIT_CODE=$?
[ $EXIT_CODE -ne 0 ] && { echo "===FAILED===" >&2; exit $EXIT_CODE; }

# ── Phase 2: structured extraction from the smaller dataset ───────────────
duckdb -init /dev/null "$TEMP_DB" -line -c "
PRAGMA temp_directory='/tmp';
${WRAP_CREATE}
WITH turns AS (
  SELECT
    s.sessionId,
    regexp_extract(s.filename, 'workspaceStorage/([^/]+)/', 1) AS workspace_id,
    to_timestamp(s.creationDate / 1000) AS session_created,
    unnest(from_json(s.requests, '[\"json\"]')) AS r
  FROM sessions s
  WHERE json_array_length(s.requests) > 0
)
SELECT
  workspace_id,
  strftime(session_created, '%Y-%m-%d %H:%M') AS session_ts,
  strftime(to_timestamp(CAST(json_extract_string(r, '\$.timestamp') AS BIGINT) / 1000), '%Y-%m-%d %H:%M') AS turn_ts,
  json_extract_string(r, '\$.message.text') AS user_message,
  left(string_agg(json_extract_string(elem, '\$.value'), ''), 2000) AS assistant_response
FROM turns, lateral (
  SELECT unnest(from_json(json_extract(r, '\$.response'), '[\"json\"]')) AS elem
) resp_elems
WHERE (json_extract_string(r, '\$.message.text') ILIKE '%' || getenv('KEYWORD') || '%'
       OR json_extract_string(elem, '\$.value') ILIKE '%' || getenv('KEYWORD') || '%')
GROUP BY ALL
ORDER BY turn_ts
${LIMIT_CLAUSE};
"
EXIT_CODE=$?
[ $EXIT_CODE -ne 0 ] && { echo "===FAILED===" >&2; exit $EXIT_CODE; }
echo "===DONE==="

# ── Materialize to separate output if requested ──────────────────────────
if [ "${MATERIALIZE:-}" = "1" ] && [ "$OUTPUT_TARGET" != ":memory:" ]; then
    duckdb -init /dev/null "$OUTPUT_TARGET" -c "
      ATTACH '$TEMP_DB' AS src (READ_ONLY);
      CREATE OR REPLACE TABLE memories AS SELECT * FROM src.memories;
    " 2>/dev/null || true
fi
