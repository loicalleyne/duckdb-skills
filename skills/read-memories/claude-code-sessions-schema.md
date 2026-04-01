# Claude Code Sessions — JSONL Schema Reference

> Documented from the [session file format article](https://databunny.medium.com/inside-claude-code-the-session-file-format-and-how-to-inspect-it-b9998e66d56b)
> by Yi Huang (Feb 2025). Format is append-only JSONL — one JSON object per line.

## File locations

```
~/.claude/
├── projects/
│   └── <url-encoded-project-path>/
│       └── sessions/
│           └── <session-uuid>.jsonl        ← conversation transcript
├── tasks/
│   └── <session-id>/
│       ├── 1.json                         ← individual task file
│       └── ...
├── plans/
│   └── <plan-name>.md                     ← plan markdown files
└── teams/
    └── <team-name>.json                   ← team configurations
```

The project path in the directory name is URL-encoded: `/home/user/myapp` becomes
`-home-user-myapp`. Each session gets its own JSONL file named by UUID.

---

## Record envelope (shared by all types)

Every line in a `.jsonl` file is a JSON object with this common structure:

| Key | Type | Description |
|-----|------|-------------|
| `type` | `string` | Message type — see **Message types** below |
| `uuid` | `string` (UUID) | Unique ID for this record |
| `parentUuid` | `string` (UUID) | UUID of the message this responds to — forms a DAG, not a linear list |
| `timestamp` | `string` (ISO 8601) | When the record was written, e.g. `"2025-02-20T09:14:32.441Z"` |
| `sessionId` | `string` | Session identifier |
| `cwd` | `string` | Working directory at time of record |
| `message` | `object` | Payload — structure depends on `type` |

---

## Message types

Seven core `type` values:

| `type` | What it contains |
|--------|-----------------|
| `user` | User prompts, hook injections, tool results fed back |
| `assistant` | Text responses, tool calls, extended thinking, token usage |
| `tool_result` | Output returned by a tool call |
| `system` | Full system prompt (tool definitions, CLAUDE.md, MCP config) — always the first record |
| `summary` | Compaction checkpoint — compressed conversation history when context window fills |
| `result` | Session completion marker (outcome, cost, structured output) |
| `file-history-snapshot` | Git working tree state at session start |

---

## `user` record

```json
{
  "type": "user",
  "uuid": "...",
  "parentUuid": "...",
  "timestamp": "2025-02-20T09:14:28.000Z",
  "message": {
    "role": "user",
    "content": "Add input validation to the createUser endpoint"
  }
}
```

| `message` key | Type | Description |
|---------------|------|-------------|
| `role` | `string` | Always `"user"` |
| `content` | `string` | The prompt text |

**Sub-types** (not a field — inferred from context):
- **user** — typed prompt
- **command** — slash commands (`/help`, `/model`)
- **command_output** — output injected from a command
- **hook_result** — context injected by `UserPromptSubmit` hook
- **system_caveat** — internal system notes

---

## `assistant` record

The most information-dense type. Contains everything Claude produced in a single turn.

```json
{
  "type": "assistant",
  "uuid": "...",
  "parentUuid": "...",
  "message": {
    "role": "assistant",
    "model": "claude-opus-4-5-20251101",
    "content": [ ...content blocks... ],
    "usage": { ... }
  }
}
```

| `message` key | Type | Description |
|---------------|------|-------------|
| `role` | `string` | Always `"assistant"` |
| `model` | `string` | Model identifier, e.g. `"claude-opus-4-5-20251101"` |
| `content` | `array` | Array of **content blocks** (see below) |
| `usage` | `object` | Token counts for this turn (see below) |

### Content block types

Three types appear inside the `content` array:

#### `text` — visible reply

```json
{ "type": "text", "text": "I'll add input validation using the existing zod schema..." }
```

| Key | Type | Description |
|-----|------|-------------|
| `type` | `string` | `"text"` |
| `text` | `string` | The assistant's written response |

#### `tool_use` — tool call

```json
{
  "type": "tool_use",
  "id": "toolu_01abc",
  "name": "Read",
  "input": { "file_path": "/home/user/myapp/src/routes/users.ts" }
}
```

| Key | Type | Description |
|-----|------|-------------|
| `type` | `string` | `"tool_use"` |
| `id` | `string` | Unique tool call ID — correlates with `tool_result.toolUseResult.tool_use_id` |
| `name` | `string` | Tool name: `Read`, `Bash`, `Glob`, `Grep`, `Write`, `Task`, MCP tools, etc. |
| `input` | `object` | Exact input Claude constructed — structure varies by tool |

#### `thinking` — extended thinking

```json
{ "type": "thinking", "thinking": "The user wants validation on createUser. I should check..." }
```

| Key | Type | Description |
|-----|------|-------------|
| `type` | `string` | `"thinking"` |
| `thinking` | `string` | Internal reasoning scratchpad — verbatim, not summarized |

### `usage` object

| Key | Type | Description |
|-----|------|-------------|
| `input_tokens` | `integer` | Input tokens consumed |
| `output_tokens` | `integer` | Output tokens produced |
| `cache_read_input_tokens` | `integer` | Tokens served from cache |
| `cache_creation` | `object` | Cache write breakdown (see below) |

#### `cache_creation` object

| Key | Type | Description |
|-----|------|-------------|
| `ephemeral_5m_input_tokens` | `integer` | Tokens written to 5-minute cache tier |
| `ephemeral_1h_input_tokens` | `integer` | Tokens written to 1-hour cache tier |

---

## `tool_result` record

Returned after each `tool_use` block. Correlated by `tool_use_id`.

```json
{
  "type": "tool_result",
  "uuid": "...",
  "parentUuid": "...",
  "toolUseResult": {
    "tool_use_id": "toolu_01abc",
    "content": "import { z } from 'zod';\n\nexport const createUserSchema = ...",
    "is_error": false
  }
}
```

| `toolUseResult` key | Type | Description |
|---------------------|------|-------------|
| `tool_use_id` | `string` | Matches `id` from the `tool_use` content block |
| `content` | `string` | Full tool output (file contents, stdout/stderr, search results) |
| `is_error` | `boolean` | `true` if the tool call failed |

---

## `system` record

Always the **first** record in a session file. Contains the complete system prompt:
tool definitions, permission modes, project context, injected CLAUDE.md content,
and MCP server instructions.

---

## `summary` record

Written when Claude Code compacts the conversation as the context window fills.
Contains a compressed representation of older turns. Marks where compaction happened.

---

## `result` record

The **last** record in a completed session. Contains session outcome (success/interrupted),
final cost summary, and any structured output.

---

## `file-history-snapshot` record

Recorded at session start. Captures the git state of the working directory:
staged changes, unstaged changes, untracked files.

---

## Subagent and team metadata

Sessions form a tree via cross-session references:

| Metadata field | Description |
|---------------|-------------|
| `parentToolUseId` | The `tool_use` ID that spawned this subagent session |
| `agentId` | Identifier for the agent instance |
| `agentType` | Agent specialization: `Explore`, `Bash`, etc. |
| `teamName` | Team name if part of a team session |

Team sessions produce multiple JSONL files — one per agent:

```
sessions/
├── team-lead-uuid.jsonl         ← orchestrator
├── teammate-explore-uuid.jsonl  ← file exploration specialist
├── teammate-search-uuid.jsonl   ← code search specialist
├── teammate-plan-uuid.jsonl     ← plan generation specialist
└── teammate-bash-uuid.jsonl     ← execution specialist
```

Coordination happens through `Task` tool calls in the lead session.
Team configuration is in `~/.claude/teams/<team-name>.json`.

---

## Task files — `~/.claude/tasks/{session-id}/{id}.json`

```json
{
  "id": "3",
  "subject": "Add input validation to createUser",
  "description": "Use zod schema to validate request body before database write",
  "status": "in_progress",
  "blocks": ["4", "5"],
  "blockedBy": ["1"],
  "metadata": {
    "type": "implementation",
    "priority": "high",
    "tags": ["validation", "api"]
  }
}
```

| Key | Type | Description |
|-----|------|-------------|
| `id` | `string` | Task identifier within the list |
| `subject` | `string` | Short task title |
| `description` | `string` | Detailed description |
| `status` | `string` | `"not_started"`, `"in_progress"`, `"completed"`, etc. |
| `blocks` | `string[]` | IDs of tasks this task blocks |
| `blockedBy` | `string[]` | IDs of tasks that must complete first |
| `metadata` | `object` | Arbitrary metadata (type, priority, tags) |

---

## Plan files — `~/.claude/plans/*.md`

Plain markdown files written when Claude enters plan mode (via `EnterPlanMode` tool).
Named by plan title. Contains goals, steps, approach, and constraints.

---

## DuckDB query tips

### Read all sessions across projects

```sql
SELECT *
FROM read_ndjson('~/.claude/projects/*/*.jsonl',
     auto_detect=true, ignore_errors=true, filename=true)
LIMIT 10;
```

### Search for a keyword across all sessions

```sql
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  strftime(timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M') AS ts,
  message.role AS role,
  left(message.content::VARCHAR, 200) AS content_preview
FROM read_ndjson('~/.claude/projects/*/*.jsonl',
     auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE '%search_term%'
  AND message.role IS NOT NULL
ORDER BY timestamp
LIMIT 40;
```

### Extract tool calls from assistant messages

```sql
SELECT
  timestamp,
  unnest(from_json(json_extract(message, '$.content'), '["json"]')) AS block
FROM read_ndjson('~/.claude/projects/*/*.jsonl',
     auto_detect=true, ignore_errors=true, filename=true)
WHERE type = 'assistant'
  AND message.content IS NOT NULL;
-- Then filter: WHERE json_extract_string(block, '$.type') = 'tool_use'
```

### Token usage per turn

```sql
SELECT
  timestamp,
  message.model AS model,
  CAST(json_extract(message, '$.usage.input_tokens') AS INTEGER) AS input_tok,
  CAST(json_extract(message, '$.usage.output_tokens') AS INTEGER) AS output_tok,
  CAST(json_extract(message, '$.usage.cache_read_input_tokens') AS INTEGER) AS cache_hit
FROM read_ndjson('~/.claude/projects/*/*.jsonl',
     auto_detect=true, ignore_errors=true, filename=true)
WHERE type = 'assistant'
  AND message.usage IS NOT NULL
ORDER BY timestamp;
```

### Session cost estimate

```sql
-- Approximate: Sonnet ≈ $3/$15 per 1M in/out, Opus ≈ $15/$75
SELECT
  regexp_extract(filename, 'sessions/([^.]+)', 1) AS session_id,
  sum(CAST(json_extract(message, '$.usage.input_tokens') AS INTEGER)) AS total_input,
  sum(CAST(json_extract(message, '$.usage.output_tokens') AS INTEGER)) AS total_output
FROM read_ndjson('~/.claude/projects/*/*.jsonl',
     auto_detect=true, ignore_errors=true, filename=true)
WHERE type = 'assistant'
  AND message.usage IS NOT NULL
GROUP BY ALL;
```
