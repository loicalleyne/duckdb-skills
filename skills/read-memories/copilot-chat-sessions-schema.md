# VS Code Copilot Chat Sessions — JSON Schema Reference

> Observed from VS Code Copilot Chat extension (`GitHub.copilot-chat`), session
> format **version 3**. Fields marked ○ are optional / not always present.

## File locations

| Path | Purpose |
|------|---------|
| `<STORAGE>/<workspace-id>/chatSessions/<session-id>.json` | One file per chat session |
| `<STORAGE>/<workspace-id>/workspace.json` | Maps workspace-id → project path |

Where `<STORAGE>` is:

| OS | Path |
|----|------|
| Windows | `%APPDATA%/Code/User/workspaceStorage` |
| macOS | `~/Library/Application Support/Code/User/workspaceStorage` |
| Linux | `~/.config/Code/User/workspaceStorage` |
| WSL accessing Windows | `/mnt/c/Users/$USER/AppData/Roaming/Code/User/workspaceStorage` |

---

## workspace.json

Maps a workspace-id directory to the project it belongs to.
One of the two keys is present (never both):

| Key | Type | When |
|-----|------|------|
| `folder` | `string` (URI) | Single-folder workspace. Example: `"file:///c%3A/Users/me/project"` or `"vscode-remote://ssh-remote%2Bhost/path"` |
| `workspace` | `string` (URI) | Multi-root workspace (`.code-workspace` file). Example: `"file:///c%3A/Users/me/my.code-workspace"` |

---

## Session (top-level object)

| Key | Type | Description |
|-----|------|-------------|
| `version` | `integer` | Schema version (currently `3`) |
| `sessionId` | `string` (UUID) | Unique session identifier |
| `creationDate` | `integer` | Session creation time (epoch **milliseconds**) |
| `lastMessageDate` | `integer` | Last activity time (epoch **milliseconds**) |
| `customTitle` | `string` | ○ Auto-generated or user-edited session title |
| `initialLocation` | `string` | Where the chat was opened: `"panel"`, `"editor"`, etc. |
| `requests` | `Request[]` | Array of conversation turns (see below) |
| `responderUsername` | `string` | Display name of the assistant (e.g. `"GitHub Copilot"`) |
| `responderAvatarIconUri` | `object` | ○ Avatar icon `{ id: string }` |
| `requesterUsername` | `string` | ○ Display name of the user |
| `requesterAvatarIconUri` | `object` | ○ Avatar icon for the user |
| `hasPendingEdits` | `boolean` | ○ Whether unsaved edits remain from this session |
| `isImported` | `boolean` | ○ Whether the session was imported |
| `inputState` | `InputState` | ○ Snapshot of the chat input bar when session was saved |

---

## Request (each conversation turn)

| Key | Type | Description |
|-----|------|-------------|
| `requestId` | `string` | Unique ID like `"request_<uuid>"` |
| `message` | `Message` | The user's input |
| `response` | `ResponseElement[]` | Ordered array of assistant response chunks |
| `timestamp` | `integer` | Turn start time (epoch **milliseconds**) |
| `modelId` | `string` | Model used, e.g. `"copilot/auto"`, `"claude-sonnet-4.6"` |
| `responseId` | `string` | ○ ID like `"response_<uuid>"` |
| `agent` | `Agent` | ○ Which agent handled the request |
| `result` | `Result` | ○ Completion metadata (timings, errors) |
| `variableData` | `VariableData` | ○ Context variables attached to the turn |
| `contentReferences` | `ContentReference[]` | ○ Files/URIs referenced in the turn |
| `codeCitations` | `array` | ○ Code citation records |
| `followups` | `Followup[]` | ○ Suggested follow-up prompts |
| `responseMarkdownInfo` | `array` | ○ Markdown rendering metadata |
| `modelState` | `ModelState` | ○ Model lifecycle state |
| `editedFileEvents` | `EditedFileEvent[]` | ○ Files modified during this turn |
| `isCanceled` | `boolean` | ○ Whether the user cancelled this turn |
| `shouldBeRemovedOnSend` | `boolean` | ○ Internal flag |
| `timeSpentWaiting` | `integer` | ○ Milliseconds spent queued before processing |

---

## Message

| Key | Type | Description |
|-----|------|-------------|
| `text` | `string` | Full text of the user's prompt (plain text, may include `/command` prefixes) |
| `parts` | `MessagePart[]` | Structured breakdown of the prompt |

### MessagePart

Each part is an object with a `kind` discriminator:

| `kind` | Additional keys | Description |
|--------|----------------|-------------|
| `"text"` | `text`, `range`, `editorRange` | Plain text segment |
| `"prompt"` | `name`, `range`, `editorRange` | A slash-command or `@agent` reference (e.g. `name: "plugin"`) |

`range` and `editorRange` are `{ startColumn, startLineNumber, endColumn, endLineNumber }` objects.

---

## ResponseElement

The `response` array contains heterogeneous objects discriminated by `kind`.
The final element often **lacks a `kind`** and contains the rendered markdown.

| `kind` | Keys | Description |
|--------|------|-------------|
| `"thinking"` | `value`, `id`, `generatedTitle`, `metadata`○ | Model reasoning / chain-of-thought block |
| `"mcpServersStarting"` | `didStartServerIds` | MCP servers being initialized |
| `"prepareToolInvocation"` | `toolName` | Tool about to be called |
| `"toolInvocationSerialized"` | _(see below)_ | Complete tool call record |
| `"textEditGroup"` | `uri`, `edits`, `done` | File edits applied to a URI |
| `"codeblockUri"` | `uri`, `isEdit` | Code block linked to a file |
| `"inlineReference"` | `inlineReference`, `name`, `resolveId` | Inline file/symbol reference |
| `"progressTaskSerialized"` | `content`, `progress` | Progress indicator |
| `"undoStop"` | `id` | Undo checkpoint marker |
| _(none)_ | `value`, `baseUri`, `supportHtml`○, `supportThemeIcons`○, `supportAlertSyntax`○, `uris`○ | **Rendered markdown** — the main assistant text. Concatenate all `value` fields from these elements to reconstruct the full reply. |

### ToolInvocationSerialized

| Key | Type | Description |
|-----|------|-------------|
| `toolCallId` | `string` | Unique ID for this tool call |
| `toolId` | `string` | Tool identifier (e.g. `"run_in_terminal"`, `"read_file"`) |
| `invocationMessage` | `string` | Human-readable description of what the tool is doing |
| `pastTenseMessage` | `string` | ○ Past-tense summary (e.g. `"Ran terminal command"`) |
| `generatedTitle` | `string` | ○ Auto-generated title for the tool call |
| `isConfirmed` | `integer` | Confirmation state: `0` = pending, `1` = confirmed, `2` = denied |
| `isComplete` | `boolean` | Whether the tool call finished |
| `source` | `object` | ○ Source extension/provider info |
| `resultDetails` | `array` | ○ Detailed result data from the tool |
| `presentation` | `object` | ○ UI presentation hints |
| `toolSpecificData` | `object` | ○ Arbitrary tool-dependent payload |

### Thinking metadata

When a `thinking` element has a `metadata` field:

| Key | Type | Description |
|-----|------|-------------|
| `vscodeReasoningDone` | `boolean` | Whether reasoning phase completed |
| `stopReason` | `string` | Why reasoning stopped |

---

## Agent

| Key | Type | Description |
|-----|------|-------------|
| `id` | `string` | Agent identifier (e.g. `"github.copilot.editsAgent"`) |
| `name` | `string` | Short name (e.g. `"agent"`) |
| `fullName` | `string` | Display name (e.g. `"GitHub Copilot"`) |
| `description` | `string` | What the agent does |
| `extensionId` | `object` | Extension that provides this agent |
| `extensionVersion` | `string` | Extension version |
| `publisherDisplayName` | `string` | Publisher (e.g. `"GitHub"`) |
| `extensionPublisherId` | `string` | Publisher ID |
| `extensionDisplayName` | `string` | Extension display name |
| `isDefault` | `boolean` | Whether this is the default agent |
| `when` | `string` | ○ Activation condition |
| `metadata` | `object` | ○ Additional agent metadata |
| `locations` | `string[]` | ○ Where agent is available (e.g. `["panel"]`) |
| `modes` | `string[]` | ○ Supported modes |
| `slashCommands` | `array` | ○ Registered slash commands |
| `disambiguation` | `array` | ○ Disambiguation entries |

---

## Result

| Key | Type | Description |
|-----|------|-------------|
| `timings` | `Timings` | Performance data |
| `metadata` | `ResultMetadata` | Response metadata |
| `details` | `string` | ○ Model name and multiplier (e.g. `"Claude Sonnet 4.6 • 0.9x"`) |
| `errorDetails` | `ErrorDetails` | ○ Present when the turn failed |

### Timings

| Key | Type | Description |
|-----|------|-------------|
| `firstProgress` | `integer` | ms until first response chunk |
| `totalElapsed` | `integer` | Total ms for the turn |

### ResultMetadata

| Key | Type | Description |
|-----|------|-------------|
| `renderedUserMessage` | `string` | The fully rendered user prompt sent to the model |
| `renderedGlobalContext` | `string` | System prompt / global context sent |
| `codeBlocks` | `array` | Code blocks in the response |
| `toolCallRounds` | `integer` | Number of tool-call rounds |
| `toolCallResults` | `array` | Tool call result summaries |
| `modelMessageId` | `string` | Backend message ID |
| `responseId` | `string` | Response ID |
| `sessionId` | `string` | Session ID |
| `agentId` | `string` | Agent ID that handled the request |
| `cacheKey` | `string` | ○ Cache key for the response |
| `messages` | `array` | ○ Full message history sent to the model |
| `summary` | `string` | ○ Auto-generated summary of the turn |

### ErrorDetails

| Key | Type | Description |
|-----|------|-------------|
| `message` | `string` | Error message |

---

## VariableData

| Key | Type | Description |
|-----|------|-------------|
| `variables` | `Variable[]` | Context variables for this turn |

### Variable

| Key | Type | Description |
|-----|------|-------------|
| `id` | `string` | Variable identifier |
| `name` | `string` | Display name |
| `fullName` | `string` | ○ Full qualified name |
| `value` | `string` | Variable content / file path |
| `kind` | `string` | Variable kind |
| `modelDescription` | `string` | ○ Description sent to the model |
| `icon` | `object` | ○ UI icon |
| `isFile` | `boolean` | ○ Whether this references a file |
| `isTool` | `boolean` | ○ Whether this references a tool |
| `isOmitted` | `boolean` | ○ Whether the variable was omitted from context |
| `omittedState` | `string` | ○ Why it was omitted |
| `automaticallyAdded` | `boolean` | ○ Whether VS Code added it automatically |
| `toolReferences` | `array` | ○ Associated tool references |

---

## ContentReference

| Key | Type | Description |
|-----|------|-------------|
| `kind` | `string` | Always `"reference"` |
| `reference` | `object` | URI object with fields: `$mid`, `fsPath`, `_sep`, `external`, `path`, `scheme` |

---

## Followup

| Key | Type | Description |
|-----|------|-------------|
| `kind` | `string` | `"reply"` |
| `message` | `string` | Suggested follow-up text |
| `agentId` | `string` | Agent to handle the follow-up |

---

## EditedFileEvent

| Key | Type | Description |
|-----|------|-------------|
| `uri` | `object` | URI of the edited file |
| `eventKind` | `string` | Type of edit event |

---

## InputState

Snapshot of the chat input UI when the session was saved.

| Key | Type | Description |
|-----|------|-------------|
| `inputText` | `string` | Text in the input box |
| `selectedModel` | `object` | Currently selected model `{ identifier, metadata }` |
| `mode` | `object` | Active mode `{ id, kind }` — e.g. `{ id: "agent", kind: "agent" }` |
| `attachments` | `array` | Files/context attached to the input |
| `contrib` | `object` | Extension-contributed state (e.g. `chatDynamicVariableModel`) |
| `selections` | `array` | ○ Text selections in the editor |

---

## ModelState

| Key | Type | Description |
|-----|------|-------------|
| `value` | `integer` | State enum: `1` = completed |
| `completedAt` | `integer` | Completion timestamp (epoch ms) |

---

## DuckDB Query Tips

- All timestamps are **epoch milliseconds** — convert with `to_timestamp(field / 1000)`
- Use `read_json(glob, maximum_object_size=52428800, union_by_name=true, filename=true)` to load sessions
- Extract workspace ID from filename: `regexp_extract(filename, 'workspaceStorage/([^/]+)/', 1)`
- Unnest requests: `unnest(from_json(requests, '["json"]'))`
- Reconstruct assistant reply: concatenate `value` from response elements where `kind` is null or `kind = '(no-kind)'`
- Full-text search: `ILIKE '%keyword%'` on `json_extract_string(r, '$.message.text')` and response values
- WSL performance: pre-collect file list with `find` to avoid slow glob over `/mnt/c/`
