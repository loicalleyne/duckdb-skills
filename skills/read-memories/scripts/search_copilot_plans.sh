#!/usr/bin/env bash
# Search VS Code Copilot Chat memory-tool plan files for a keyword.
#
# Required env vars:
#   PLANS_SEARCH_PATH — glob for plan .md files (set by get_session_path.sh)
#   KEYWORD           — search term
#   BASE              — workspaceStorage base directory
#
# Optional:
#   DRILL_SECTION  — filter to specific section headings (e.g., "Decisions")
#   MATERIALIZE    — set to "1" to write results to STATE_DIR/memories.duckdb
#   STATE_DIR      — directory for materialized output
#
# Uses DuckDB markdown community extension (primary) with read_text() fallback.

set -euo pipefail
: "${PLANS_SEARCH_PATH:?ERROR: PLANS_SEARCH_PATH not set. Run get_session_path.sh first.}"
: "${KEYWORD:?ERROR: KEYWORD not set.}"
: "${BASE:?ERROR: BASE not set.}"

# Split comma-separated PLANS_SEARCH_PATH into array of globs
IFS=',' read -ra PLAN_GLOBS <<< "$PLANS_SEARCH_PATH"

# Build UNION ALL queries for each glob
MD_SOURCES=""
TXT_SOURCES=""
for pg in "${PLAN_GLOBS[@]}"; do
    [ -n "$MD_SOURCES" ] && MD_SOURCES="$MD_SOURCES UNION ALL "
    MD_SOURCES="${MD_SOURCES}SELECT * FROM read_markdown_sections('$pg', content_mode := 'full', include_filepath := true)"
    [ -n "$TXT_SOURCES" ] && TXT_SOURCES="$TXT_SOURCES UNION ALL "
    TXT_SOURCES="${TXT_SOURCES}SELECT * FROM read_text('$pg')"
done

LIMIT_CLAUSE="LIMIT 40"
OUTPUT_TARGET=":memory:"
WRAP_CREATE=""

if [ "${MATERIALIZE:-}" = "1" ]; then
    : "${STATE_DIR:?ERROR: STATE_DIR required for materialization.}"
    mkdir -p "$STATE_DIR"
    OUTPUT_TARGET="$STATE_DIR/memories.duckdb"
    WRAP_CREATE="CREATE OR REPLACE TABLE plans AS"
    LIMIT_CLAUSE=""
fi

SECTION_FILTER=""
if [ -n "${DRILL_SECTION:-}" ]; then
    export DRILL_SECTION
    SECTION_FILTER="AND title ILIKE '%' || getenv('DRILL_SECTION') || '%'"
fi

export KEYWORD

# Primary: markdown extension with section-level search
if duckdb -c "INSTALL markdown FROM community; LOAD markdown;" 2>/dev/null; then
    if duckdb "$OUTPUT_TARGET" -line -c "
LOAD markdown;
${WRAP_CREATE}
WITH sections AS (
    ${MD_SOURCES}
)
SELECT
    regexp_extract(file_path, 'workspaceStorage/([^/]+)/', 1) AS workspace_id,
    regexp_extract(file_path, 'memories/([^/]+)/', 1) AS session_id,
    split_part(file_path, '/', -1) AS plan_file,
    title,
    level,
    left(content, 2000) AS content
FROM sections
WHERE (content ILIKE '%' || getenv('KEYWORD') || '%'
       OR title ILIKE '%' || getenv('KEYWORD') || '%')
  ${SECTION_FILTER}
ORDER BY file_path, level
${LIMIT_CLAUSE};
"; then
        echo "===DONE==="
        exit 0
    fi
    echo "WARN: markdown extension query failed. Falling back to read_text()."
fi

# Fallback: read_text() — no section granularity
duckdb "$OUTPUT_TARGET" -line -c "
${WRAP_CREATE}
WITH contents AS (
    ${TXT_SOURCES}
)
SELECT
    regexp_extract(filename, 'workspaceStorage/([^/]+)/', 1) AS workspace_id,
    regexp_extract(filename, 'memories/([^/]+)/', 1) AS session_id,
    split_part(filename, '/', -1) AS plan_file,
    left(content, 2000) AS content
FROM contents
WHERE content ILIKE '%' || getenv('KEYWORD') || '%'
ORDER BY filename
${LIMIT_CLAUSE};
" && echo "===DONE===" || echo "===FAILED==="
