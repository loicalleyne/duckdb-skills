#!/usr/bin/env bash
# Refresh the local DuckDB/DuckLake docs FTS cache.
# Requires: DOCS_TARGET (duckdb|ducklake)
set -euo pipefail
: "${DOCS_TARGET:=duckdb}"

mkdir -p "$HOME/.duckdb/docs"
if [ "$DOCS_TARGET" = "ducklake" ]; then
    CACHE_FILE="$HOME/.duckdb/docs/ducklake-docs.duckdb"
    REMOTE_URL="https://ducklake.select/data/docs-search.duckdb"
else
    CACHE_FILE="$HOME/.duckdb/docs/duckdb-docs.duckdb"
    REMOTE_URL="https://duckdb.org/data/docs-search.duckdb"
fi

command -v duckdb || { echo "DuckDB not found — delegate to /duckdb-skills:install-duckdb"; echo "===FAILED==="; exit 1; }

if [ ! -f "$CACHE_FILE" ] || [ -n "$(find "$CACHE_FILE" -mmin +2880 2>/dev/null)" ]; then
    echo "Updating cache from $REMOTE_URL..."
    duckdb :memory: -c "
        INSTALL httpfs; LOAD httpfs;
        INSTALL fts; LOAD fts;
        ATTACH '$REMOTE_URL' AS remote (READ_ONLY);
        ATTACH '${CACHE_FILE}.tmp' AS tmp;
        COPY FROM DATABASE remote TO tmp;
    " && mv "${CACHE_FILE}.tmp" "$CACHE_FILE" \
      && echo "===CACHE_UPDATED===" \
      || { echo "===FAILED==="; exit 1; }
else
    echo "===CACHE_FRESH==="
fi

export CACHE_FILE
echo "===DONE==="
