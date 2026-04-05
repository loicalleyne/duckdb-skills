#!/usr/bin/env bash
# Read a data file using DuckDB — schema, row count, and sample rows.
#
# Required env vars:
#   FILE_PATH — resolved absolute path or URL to the data file
#
# Optional env vars:
#   READER    — explicit reader function (read_csv, read_parquet, etc.)
#               If unset, auto-dispatches via read_any macro.
#   REMOTE_PREFIX — SQL to prepend for remote files (LOAD httpfs; etc.)
#   SAMPLE_LIMIT  — number of sample rows (default: 20)
#   EXTRA_INSTALL — extension install SQL (e.g. "INSTALL spatial; LOAD spatial;")

set -euo pipefail
: "${FILE_PATH:?ERROR: FILE_PATH not set.}"

SAMPLE_LIMIT="${SAMPLE_LIMIT:-20}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export FILE_PATH

if [ -n "${READER:-}" ]; then
    # Direct reader path — fastest, no unused CTE branches
    duckdb -init /dev/null :memory: -markdown <<SQL
${EXTRA_INSTALL:-}
${REMOTE_PREFIX:-}
SET max_memory = '4GB';
DESCRIBE FROM ${READER}(getenv('FILE_PATH'));
SELECT count() AS row_count FROM ${READER}(getenv('FILE_PATH'));
FROM ${READER}(getenv('FILE_PATH')) LIMIT ${SAMPLE_LIMIT};
SQL
    EXIT_CODE=$?
    [ $EXIT_CODE -ne 0 ] && { echo "===FAILED===" >&2; exit $EXIT_CODE; }
    echo "===DONE==="
else
    # Auto-dispatch via read_any macro
    duckdb -init /dev/null :memory: -markdown <<SQL
${EXTRA_INSTALL:-}
${REMOTE_PREFIX:-}
SET max_memory = '4GB';
.read ${SCRIPT_DIR}/read_any.sql
DESCRIBE FROM read_any(getenv('FILE_PATH'));
SELECT count() AS row_count FROM read_any(getenv('FILE_PATH'));
FROM read_any(getenv('FILE_PATH')) LIMIT ${SAMPLE_LIMIT};
SQL
    EXIT_CODE=$?
    [ $EXIT_CODE -ne 0 ] && { echo "===FAILED===" >&2; exit $EXIT_CODE; }
    echo "===DONE==="
fi
