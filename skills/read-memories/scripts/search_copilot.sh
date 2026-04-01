#!/usr/bin/env bash
# Search VS Code Copilot Chat session files for a keyword.
#
# Required env vars:
#   SEARCH_PATH  — glob/file-list for session JSON files (set by get_session_path.sh)
#   KEYWORD      — search term
#   BASE         — workspaceStorage base directory
#
# Optional:
#   MATERIALIZE  — set to "1" to write results to STATE_DIR/memories.duckdb
#   STATE_DIR    — directory for materialized output
#
# WSL SAFETY: If BASE is under /mnt/c/, pre-filter with find to avoid glob timeout.

set -euo pipefail
: "${SEARCH_PATH:?ERROR: SEARCH_PATH not set. Run get_session_path.sh first.}"
: "${KEYWORD:?ERROR: KEYWORD not set.}"
: "${BASE:?ERROR: BASE not set.}"

# WSL glob mitigation: pre-filter with find if on /mnt/c/
EFFECTIVE_PATH="$SEARCH_PATH"
if [[ "$BASE" == /mnt/c/* ]]; then
    find "$BASE" -path '*/chatSessions/*.json' 2>/dev/null > /tmp/copilot_sessions.txt
    EFFECTIVE_PATH="/tmp/copilot_sessions.txt"
    READ_EXPR="read_json(list_transform(
        str_split(trim(content, chr(10)), chr(10)),
        x -> x
    ), maximum_object_size=52428800, union_by_name=true, filename=true)"
    # Override: read from file list
    READ_EXPR="read_json(
        list_apply(
            string_split(rtrim(read_text('/tmp/copilot_sessions.txt'), chr(10)), chr(10)),
            x -> x),
        maximum_object_size=52428800, union_by_name=true, filename=true)"
else
    READ_EXPR="read_json('$EFFECTIVE_PATH', maximum_object_size=52428800, union_by_name=true, filename=true)"
fi

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
duckdb "$OUTPUT_TARGET" -line -c "
${WRAP_CREATE}
WITH sessions AS (
  SELECT * FROM $READ_EXPR
),
turns AS (
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
  left(string_agg(json_extract_string(elem, '\$.value'), '' ORDER BY rowid), 2000) AS assistant_response
FROM turns, lateral (
  SELECT unnest(from_json(json_extract(r, '\$.response'), '[\"json\"]')) AS elem, rowid
) resp_elems
WHERE (json_extract_string(r, '\$.message.text') ILIKE '%' || getenv('KEYWORD') || '%'
       OR json_extract_string(elem, '\$.value') ILIKE '%' || getenv('KEYWORD') || '%')
GROUP BY ALL
ORDER BY turn_ts
${LIMIT_CLAUSE};
" && echo "===DONE===" || echo "===FAILED==="
