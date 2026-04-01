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

# Skill: Search Past Chat Sessions

## Purpose
Search conversation histories from Claude Code or VS Code Copilot to recover
prior decisions, patterns, and context. All queries run silently — absorb
results and inform your response without narrating the process.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Constraints
- **SILENT EXECUTION:** Do NOT narrate this process to the user.
- **CROSS-POLLINATION:** If user asks about a different assistant's history,
  override `ACTIVE_CLIENT` accordingly.
- For schema details, read `claude-code-sessions-schema.md` or
  `copilot-chat-sessions-schema.md` on demand.

## Step 1 — Setup and detect environment

Determine client from your own system instructions. Set env vars and run the
path resolver:

```bash
export KEYWORD="<search_term>"
export SCOPE="all"            # or "here" for current project
export ACTIVE_CLIENT="vscode" # or "claude"
source ./scripts/get_session_path.sh && echo "===DONE===" || echo "===FAILED==="
```

## Step 2 — Search

Run the script matching `ENV_TYPE`:

```bash
bash ./scripts/search_claude.sh  && echo "===DONE===" || echo "===FAILED==="
# or
bash ./scripts/search_copilot.sh && echo "===DONE===" || echo "===FAILED==="
```

## Step 3 — Materialize large results (optional)

If results exceed 40 rows, re-run with materialization:

```bash
export MATERIALIZE=1
export STATE_DIR=".duckdb-skills"
bash ./scripts/search_claude.sh   # or search_copilot.sh
bash ./scripts/drill.sh           # counts rows, drills with DRILL_TERM
```

Clean up: `ACTION=cleanup bash ./scripts/drill.sh`

## Step 4 — Internalize

Extract decisions, patterns, conventions, and open TODOs from results.
Use these to inform your current response. Do not echo raw logs.

## Cross-skill integration
- **Error lookup:** `/duckdb-skills:duckdb-docs <error keywords>`
- **Session state:** ATTACH `memories.duckdb` to an existing `state.sql`.
