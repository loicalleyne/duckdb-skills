---
name: read-memories
description: >
  Search past chat sessions to recover context, decisions, patterns, or open TODOs.
  USE THIS SKILL when: the user says "what did we do last time", "recall our
  previous decisions", "look at our past chats", or asks about established
  conventions from prior sessions.
  USE THIS SKILL to search your own memory, OR the memory of other AI assistants
  installed on this machine (Claude Code or VS Code Copilot).
  DO NOT USE THIS SKILL to read actual source code files; only use it to read
  conversation logs.
argument-hint: <keyword> [--here]
allowed-tools:
  - Bash
  - run_in_terminal
---

Search past AI chat sessions to recover your own context. Silently run the
queries, absorb the results, and continue with enriched context.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Guardrails & Warnings

* **SILENT EXECUTION:** Do NOT narrate this process to the user. Run the queries, absorb the results, and continue.
* **WSL/WINDOWS TIMEOUTS:** If operating in WSL (`/mnt/c/`), DuckDB globbing `**/*.json` is extremely slow and will time out. You MUST pre-filter the files using `find` before running DuckDB:
  ```bash
  find "$BASE" -path '*/chatSessions/*.json' 2>/dev/null > /tmp/copilot_sessions.txt
  ```
  Then query from the file list instead of using a glob.
* **CROSS-POLLINATION:** If the user explicitly asks what they discussed with "Claude" (and you are Copilot) or "Copilot" (and you are Claude), override `$ACTIVE_CLIENT` to target the requested assistant's history.

## Data layout

This skill handles two session formats. For full schema details, read the
bundled reference files only when you need to understand the JSON structure:

* **Claude Code (JSONL):** `$HOME/.claude/projects/<project-slug>/*.jsonl` —
  see [claude-code-sessions-schema.md](claude-code-sessions-schema.md)
* **VS Code Copilot (JSON):** `<workspaceStorage>/<id>/chatSessions/<session>.json` —
  see [copilot-chat-sessions-schema.md](copilot-chat-sessions-schema.md)

## Setup

Before executing any searches, determine which tool you are currently operating
in (Claude Code or VS Code Copilot) based on your system instructions.

Set your parameters in the terminal:

```bash
KEYWORD="<your_search_term>"
SCOPE="all"           # Set to "here" for current project, "all" for global
ACTIVE_CLIENT="vscode" # Set to "claude" if you are Claude Code, "vscode" if you are Copilot
```

Then substitute `$KEYWORD` into the SQL queries below wherever `<KEYWORD>` appears.

## Step 1 — Detect environment and set the search path

Run the bundled helper script to export `$ENV_TYPE` and `$SEARCH_PATH`:

```bash
source ./scripts/get_session_path.sh && echo "===DONE===" || echo "===FAILED==="
```

This exports `ENV_TYPE` (`claude` or `vscode`), `SEARCH_PATH`, and `BASE`
(VS Code only). Choose the matching query block in Step 2.

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
WHERE message::VARCHAR ILIKE '%$KEYWORD%'
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
WHERE (json_extract_string(r, '\$.message.text') ILIKE '%$KEYWORD%'
       OR json_extract_string(elem, '\$.value') ILIKE '%$KEYWORD%')
GROUP BY ALL
ORDER BY turn_ts
LIMIT 40;
" && echo "===DONE===" || echo "===FAILED==="
```

## Step 3 — Handle large result sets

If Step 2 returns more than 40 rows or the output is very large, materialize
the results to a temporary DuckDB file for interactive drill-down.

Resolve the state directory first:

```bash
STATE_DIR=""
test -d .duckdb-skills && STATE_DIR=".duckdb-skills"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
test -d "$HOME/.duckdb-skills/$PROJECT_ID" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
test -z "$STATE_DIR" && STATE_DIR=".duckdb-skills" && mkdir -p "$STATE_DIR"
```

### Materialize

Run the **exact same query** from your Step 2 block (Claude or VS Code), but:
1. Replace `duckdb :memory:` (or `duckdb -line`) with `duckdb "$STATE_DIR/memories.duckdb"`
2. Wrap the SELECT in `CREATE OR REPLACE TABLE memories AS`
3. Remove the `LIMIT 40` clause

Example (Claude Code):

```bash
duckdb "$STATE_DIR/memories.duckdb" -c "
CREATE OR REPLACE TABLE memories AS
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  timestamp::TIMESTAMPTZ AS ts,
  message.role AS role,
  message.content::VARCHAR AS content
FROM read_ndjson('$SEARCH_PATH', auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE '%$KEYWORD%'
  AND message.role IS NOT NULL
ORDER BY timestamp;
" && echo "===DONE===" || echo "===FAILED==="
```

For VS Code, apply the same three transformations to the VS Code query from Step 2.

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

Use this to inform your current response. Do not repeat back the raw logs.

## Cross-skill integration

- **Session state**: If a `state.sql` exists (in `.duckdb-skills/` or `$HOME/.duckdb-skills/<project-id>/`), you can ATTACH the memories table to it for cross-referencing.
- **Error troubleshooting**: Use `/duckdb-skills:duckdb-docs <error keywords>` to search for guidance.
- **DuckDB CLI**: Use `-line` for schema exploration, `-jsonlines` for machine-readable output.
