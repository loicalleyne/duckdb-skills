#!/usr/bin/env bash
# Resolve session search path based on the active AI client and scope.
#
# Usage:
#   export SCOPE="all"       # or "here" for current-project only
#   export ACTIVE_CLIENT="vscode"  # or "claude"
#   source ./scripts/get_session_path.sh
#
# Exports: ENV_TYPE, SEARCH_PATH, BASE (vscode only)

set -euo pipefail

: "${ACTIVE_CLIENT:?ERROR: ACTIVE_CLIENT must be set to 'claude' or 'vscode'}"
: "${SCOPE:=all}"

if [ "$ACTIVE_CLIENT" = "claude" ]; then
    export ENV_TYPE="claude"
    if [ "$SCOPE" = "here" ]; then
        export SEARCH_PATH="$HOME/.claude/projects/$(echo "$PWD" | sed 's|[/_]|-|g')/*.jsonl"
    else
        export SEARCH_PATH="$HOME/.claude/projects/*/*.jsonl"
    fi

elif [ "$ACTIVE_CLIENT" = "vscode" ]; then
    export ENV_TYPE="vscode"

    # Resolve base path: WSL → native Windows → Linux/macOS
    if [ -d "/mnt/c/Users/$USER/AppData/Roaming/Code/User/workspaceStorage" ]; then
        BASE="/mnt/c/Users/$USER/AppData/Roaming/Code/User/workspaceStorage"
    elif [ -n "${APPDATA:-}" ] && [ -d "$APPDATA/Code/User/workspaceStorage" ]; then
        BASE="$APPDATA/Code/User/workspaceStorage"
    elif [ -d "$HOME/.config/Code/User/workspaceStorage" ]; then
        BASE="$HOME/.config/Code/User/workspaceStorage"
    else
        echo "ERROR: Could not locate VS Code workspaceStorage directory."
        return 1 2>/dev/null || exit 1
    fi
    export BASE

    if [ "$SCOPE" = "here" ]; then
        # Resolve workspace IDs matching the current project name
        WORKSPACE_IDS=""
        if command -v duckdb >/dev/null 2>&1; then
            WORKSPACE_IDS=$(duckdb -noheader -csv -c "
              SELECT regexp_extract(filename, 'workspaceStorage/([^/]+)/', 1)
              FROM read_json('$BASE/*/workspace.json',
                   filename=true,
                   columns={workspace: 'VARCHAR', folder: 'VARCHAR'})
              WHERE coalesce(workspace, folder) ILIKE '%$(basename "$PWD")%';
            " 2>/dev/null || true)
        fi

        if [ -n "$WORKSPACE_IDS" ]; then
            CURRENT_SESSIONS=""
            for WID in $WORKSPACE_IDS; do
                CURRENT_SESSIONS="$CURRENT_SESSIONS,$BASE/$WID/chatSessions/*.json"
            done
            export SEARCH_PATH="${CURRENT_SESSIONS#,}"
        else
            echo "WARN: Could not resolve workspace ID for '$PWD'. Falling back to all sessions."
            export SEARCH_PATH="$BASE/**/chatSessions/*.json"
        fi
    else
        export SEARCH_PATH="$BASE/**/chatSessions/*.json"
    fi
else
    echo "ERROR: Unknown ACTIVE_CLIENT='$ACTIVE_CLIENT'. Must be 'claude' or 'vscode'."
    return 1 2>/dev/null || exit 1
fi

echo "Environment: $ENV_TYPE | Scope: $SCOPE | Path: $SEARCH_PATH"
