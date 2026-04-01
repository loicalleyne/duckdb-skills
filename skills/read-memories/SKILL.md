---
name: read-memories
description: >
  Search past chat sessions to recover your own context.
  Invoke this proactively when you need to recall past decisions, patterns,
  or unresolved work — either across all projects or scoped to the current one.
  Works with both VS Code Copilot (JSON) and Claude Code (JSONL) session logs.
argument-hint: <keyword> [--here]
allowed-tools:
  - Bash
  - run_in_terminal
---

Use this to recover your own context from past sessions. Do NOT narrate the
process to the user — silently run the query, absorb the results, and continue
with enriched context.

`$0` is the keyword to search for.
Pass `--here` as a second argument (`$1`) to scope the search to the current project only.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command to
clearly indicate success or failure in the terminal output.

## Data layout

This skill auto-detects the environment and handles two session formats:

### Claude Code (JSONL)

```
$HOME/.claude/projects/<project-slug>/*.jsonl
```

Each line is a JSON object with `timestamp`, `message.role`, `message.content`.

> **Claude Code schema reference:** See [claude-code-sessions-schema.md](claude-code-sessions-schema.md)
> for the complete JSONL structure (all record types, content blocks, token usage,
> subagent/team metadata, tasks, plans, and DuckDB query tips).

### VS Code Copilot (JSON)

```
<APPDATA>/Code/User/workspaceStorage/<workspace-id>/chatSessions/<session-id>.json
```

Each JSON file has `sessionId`, `creationDate`/`lastMessageDate` (epoch ms), and
a `requests` array of conversation turns. Each turn has `message.text` (user prompt),
`response` (array of chunks whose `value` fields concatenate to the assistant reply),
`timestamp` (epoch ms), `modelId`, and `agent`.

Each `workspaceStorage/<workspace-id>/` folder contains a `workspace.json` with
either a `folder` field (single-folder workspace) or a `workspace` field
(multi-root `.code-workspace` file), both URIs mapping the workspace ID to the project path.

> **VS Code schema reference:** See [copilot-chat-sessions-schema.md](copilot-chat-sessions-schema.md)
> for the complete JSON structure (all keys, types, response element kinds, and DuckDB query tips).

## Step 1 — Detect environment and set the search path

```bash
# --- Detect environment ---
if [ -d "$HOME/.claude/projects" ]; then
  ENV_TYPE="claude"
  ALL_SESSIONS="$HOME/.claude/projects/*/*.jsonl"
  CURRENT_PROJECT="$HOME/.claude/projects/$(echo "$PWD" | sed 's|[/_]|-|g')/*.jsonl"
  if [ "$1" = "--here" ] 2>/dev/null || [ "${ARGS[1]}" = "--here" ] 2>/dev/null; then
    SEARCH_PATH="$CURRENT_PROJECT"
  else
    SEARCH_PATH="$ALL_SESSIONS"
  fi
elif [ -d "/mnt/c/Users/$USER/AppData/Roaming/Code/User/workspaceStorage" ]; then
  ENV_TYPE="vscode"
  BASE="/mnt/c/Users/$USER/AppData/Roaming/Code/User/workspaceStorage"
  ALL_SESSIONS="$BASE/**/chatSessions/*.json"
  SEARCH_PATH="$ALL_SESSIONS"
elif [ -d "$APPDATA/Code/User/workspaceStorage" ]; then
  ENV_TYPE="vscode"
  BASE="$APPDATA/Code/User/workspaceStorage"
  ALL_SESSIONS="$BASE/**/chatSessions/*.json"
  SEARCH_PATH="$ALL_SESSIONS"
elif [ -d "$HOME/.config/Code/User/workspaceStorage" ]; then
  ENV_TYPE="vscode"
  BASE="$HOME/.config/Code/User/workspaceStorage"
  ALL_SESSIONS="$BASE/**/chatSessions/*.json"
  SEARCH_PATH="$ALL_SESSIONS"
else
  echo "ERROR: Could not detect Claude Code or VS Code Copilot session storage."
  echo "===FAILED==="
  exit 1
fi
echo "Detected environment: $ENV_TYPE"
echo "===DONE==="
```

### VS Code `--here` scoping

If `--here` was passed and `ENV_TYPE` is `vscode`, resolve the workspace ID:

```bash
WORKSPACE_IDS=$(duckdb -noheader -csv -c "
  SELECT regexp_extract(filename, 'workspaceStorage/([^/]+)/', 1)
  FROM read_json('$BASE/*/workspace.json', filename=true, columns={workspace: 'VARCHAR', folder: 'VARCHAR'})
  WHERE coalesce(workspace, folder) ILIKE '%$(basename "$PWD")%';
" 2>/dev/null)
if [ -n "$WORKSPACE_IDS" ]; then
  CURRENT_SESSIONS=""
  for WID in $WORKSPACE_IDS; do
    CURRENT_SESSIONS="$CURRENT_SESSIONS,$BASE/$WID/chatSessions/*.json"
  done
  SEARCH_PATH="${CURRENT_SESSIONS#,}"
fi
echo "===DONE==="
```

## Step 2 — Query

### Claude Code query

```bash
duckdb :memory: -c "
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  strftime(timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M') AS ts,
  message.role AS role,
  message.content::VARCHAR AS content
FROM read_ndjson('$SEARCH_PATH', auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE '%<KEYWORD>%'
  AND message.role IS NOT NULL
ORDER BY timestamp
LIMIT 40;
" && echo "===DONE===" || echo "===FAILED==="
```

### VS Code Copilot query

Use `-line` output mode for schema exploration and `-jsonlines` for data queries
(each complete line is valid JSON even if output is truncated).

```bash
duckdb -line -c "
WITH sessions AS (
  SELECT *
  FROM read_json('$SEARCH_PATH',
       maximum_object_size=52428800,
       union_by_name=true,
       filename=true)
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
WHERE (json_extract_string(r, '\$.message.text') ILIKE '%<KEYWORD>%'
       OR json_extract_string(elem, '\$.value') ILIKE '%<KEYWORD>%')
GROUP BY ALL
ORDER BY turn_ts
LIMIT 40;
" && echo "===DONE===" || echo "===FAILED==="
```

Replace `<KEYWORD>` with the resolved search term before running.
Choose the query block matching the detected `ENV_TYPE`.

**Performance note (VS Code / WSL)**: Glob over `/mnt/c/` can be slow.
If it times out, pre-filter with `find` to build an explicit file list:

```bash
find "$BASE" -path '*/chatSessions/*.json' 2>/dev/null > /tmp/copilot_sessions.txt
```

## Step 3 — Handle large result sets

If Step 2 returns more than 40 rows or the output is very large, offload the
results to a temporary DuckDB file for interactive drill-down.

Resolve the state directory first:

```bash
STATE_DIR=""
test -d .duckdb-skills && STATE_DIR=".duckdb-skills"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
test -d "$HOME/.duckdb-skills/$PROJECT_ID" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
# Fall back to project-local if neither exists
test -z "$STATE_DIR" && STATE_DIR=".duckdb-skills" && mkdir -p "$STATE_DIR"
```

### Claude Code — materialize

```bash
duckdb "$STATE_DIR/memories.duckdb" -c "
CREATE OR REPLACE TABLE memories AS
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  timestamp::TIMESTAMPTZ AS ts,
  message.role AS role,
  message.content::VARCHAR AS content
FROM read_ndjson('$SEARCH_PATH', auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE '%<KEYWORD>%'
  AND message.role IS NOT NULL
ORDER BY timestamp;
" && echo "===DONE===" || echo "===FAILED==="
```

### VS Code Copilot — materialize

```bash
duckdb "$STATE_DIR/memories.duckdb" -c "
CREATE OR REPLACE TABLE memories AS
WITH sessions AS (
  SELECT *
  FROM read_json('$SEARCH_PATH',
       maximum_object_size=52428800,
       union_by_name=true,
       filename=true)
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
  session_created AS session_ts,
  to_timestamp(CAST(json_extract_string(r, '\$.timestamp') AS BIGINT) / 1000) AS turn_ts,
  json_extract_string(r, '\$.message.text') AS user_message,
  string_agg(json_extract_string(elem, '\$.value'), '' ORDER BY rowid) AS assistant_response
FROM turns, lateral (
  SELECT unnest(from_json(json_extract(r, '\$.response'), '[\"json\"]')) AS elem, rowid
) resp_elems
WHERE (json_extract_string(r, '\$.message.text') ILIKE '%<KEYWORD>%'
       OR json_extract_string(elem, '\$.value') ILIKE '%<KEYWORD>%')
GROUP BY ALL
ORDER BY turn_ts;
" && echo "===DONE===" || echo "===FAILED==="
```

### Drill down interactively

```bash
duckdb "$STATE_DIR/memories.duckdb" -c "SELECT count() FROM memories;" && echo "===DONE==="
duckdb "$STATE_DIR/memories.duckdb" -c "FROM memories WHERE content ILIKE '%<narrower term>%' LIMIT 20;" && echo "===DONE==="
```

(For VS Code, substitute `user_message` or `assistant_response` for `content`.)

Clean up when done:

```bash
rm -f "$STATE_DIR/memories.duckdb"
```

## Step 4 — Internalize

From the results, extract:
- Decisions made and their rationale
- Patterns and conventions established
- Unresolved items or open TODOs
- Any corrections the user made to your prior behavior

Use this to inform your current response. Do not repeat back the raw logs to the user.

## Cross-skill integration

- **Session state**: If a `state.sql` exists (in `.duckdb-skills/` or `$HOME/.duckdb-skills/<project-id>/`), you can add the memories table to the session temporarily by appending an ATTACH to it — useful if the user wants to cross-reference memories with their data.
- **Error troubleshooting**: If DuckDB returns errors when reading session files, use `/duckdb-skills:duckdb-docs <error keywords>` to search for guidance.
- **DuckDB CLI**: Use `-line` for schema exploration, `-jsonlines` for machine-readable output. See [CLI output formats](https://duckdb.org/docs/current/clients/cli/output_formats) for all options.
