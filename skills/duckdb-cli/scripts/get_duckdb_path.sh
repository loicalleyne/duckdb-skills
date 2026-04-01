#!/usr/bin/env bash
# Resolve the latest installed DuckDB CLI binary from ~/.duckdb/cli/
# Usage: source ./scripts/get_duckdb_path.sh

DUCKDB_BIN=$(ls -d ~/.duckdb/cli/[0-9]*/ 2>/dev/null \
    | sed 's|.*/\([0-9][^/]*\)/|\1|' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
if [[ -n "$DUCKDB_BIN" && -x "$HOME/.duckdb/cli/$DUCKDB_BIN/duckdb" ]]; then
    export PATH="$HOME/.duckdb/cli/$DUCKDB_BIN:$PATH"
    echo "Using DuckDB at ~/.duckdb/cli/$DUCKDB_BIN/duckdb"
else
    echo "DuckDB not found — delegate to /duckdb-skills:install-duckdb"
fi
