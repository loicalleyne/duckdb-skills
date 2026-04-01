#!/usr/bin/env bash
# Resolve the shared duckdb-skills state directory.
#
# Checks two locations in order:
#   1. .duckdb-skills/state.sql  (project-local, preferred)
#   2. $HOME/.duckdb-skills/$PROJECT_ID/state.sql  (global per-project)
#
# If neither exists and CREATE_STATE_DIR=1, creates option 1 and adds
# .duckdb-skills/ to .gitignore.
#
# Usage:
#   source ./scripts/resolve_state_dir.sh                # read-only lookup
#   CREATE_STATE_DIR=1 source ./scripts/resolve_state_dir.sh  # create if missing
#
# Exports: STATE_DIR (empty string if not found and CREATE_STATE_DIR!=1)

set -euo pipefail

STATE_DIR=""
test -f .duckdb-skills/state.sql && STATE_DIR=".duckdb-skills"

if [ -z "$STATE_DIR" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
    PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
    test -f "$HOME/.duckdb-skills/$PROJECT_ID/state.sql" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
fi

if [ -z "$STATE_DIR" ] && [ "${CREATE_STATE_DIR:-}" = "1" ]; then
    STATE_DIR=".duckdb-skills"
    mkdir -p "$STATE_DIR"
    grep -qxF '.duckdb-skills/' .gitignore 2>/dev/null || echo '.duckdb-skills/' >> .gitignore
fi

export STATE_DIR
echo "State dir: ${STATE_DIR:-(none)}"
