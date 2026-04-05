#!/usr/bin/env bash
# Read a Jupyter notebook (.ipynb) and display cell contents.
#
# Required env vars:
#   FILE_PATH — path to the .ipynb file

set -euo pipefail
: "${FILE_PATH:?ERROR: FILE_PATH not set.}"

export FILE_PATH

duckdb -init /dev/null :memory: -markdown <<'SQL'
WITH nb AS (FROM read_json_auto(getenv('FILE_PATH')))
SELECT cell_idx, cell.cell_type,
       array_to_string(cell.source, '') AS source,
       cell.execution_count
FROM nb, UNNEST(cells) WITH ORDINALITY AS t(cell, cell_idx)
ORDER BY cell_idx
LIMIT 30;
SQL
EXIT_CODE=$?
[ $EXIT_CODE -ne 0 ] && { echo "===FAILED===" >&2; exit $EXIT_CODE; }
echo "===DONE==="
