#!/usr/bin/env bash
# Search the local DuckDB docs FTS index.
# Requires: CACHE_FILE, SEARCH_QUERY
# Optional: VERSION_FILTER (stable|current|blog|"" for all)
set -euo pipefail
: "${CACHE_FILE:?ERROR: CACHE_FILE not set. Run refresh_cache.sh first.}"
: "${SEARCH_QUERY:?ERROR: SEARCH_QUERY not set.}"

export SEARCH_QUERY
export VERSION_FILTER="${VERSION_FILTER:-stable}"

duckdb "$CACHE_FILE" -readonly -json -c "
LOAD fts;
SELECT
    chunk_id, page_title, section, breadcrumb, url, version, text,
    fts_main_docs_chunks.match_bm25(chunk_id, getenv('SEARCH_QUERY')) AS score
FROM docs_chunks
WHERE score IS NOT NULL
  AND (getenv('VERSION_FILTER') = '' OR version = getenv('VERSION_FILTER'))
ORDER BY score DESC
LIMIT 5;
" && echo "===DONE===" || echo "===FAILED==="
