---
name: duckdb-code
description: >
  Analyze codebase architecture, trace execution flows, and map types using DuckDB's sitting_duck AST parser. 
  USE THIS SKILL to answer structural questions without reading every file (e.g., "Where is this used?", "What calls this function?", "What implements this interface?", "Map the public API").
  USE THIS SKILL to find the right file to edit BEFORE making changes.
  DO NOT USE THIS SKILL if you already know the exact file/line to edit, or for general programming trivia.
argument-hint: <question or task about the codebase> [--path directory_or_glob]
allowed-tools:
  - Bash
  - run_in_terminal
---

You are helping the user understand and navigate source code using DuckDB and the `sitting_duck`
community extension. This extension parses source files into AST nodes queryable via SQL, with
universal semantic types that work identically across 27 languages (including Python, JS/TS, Go,
Rust, C/C++, Java, C#, Kotlin, Swift, Ruby, PHP, and more).

**Key insight**: AST queries let you answer structural questions across an entire codebase in
seconds without reading every file. Use this to build a mental model fast, then read specific
files only when you need implementation details.

Input: `$@`

## Guardrails & Critical Rules

**`node_id` is per-file, not globally unique.**
All JOINs using `node_id`, `parent_id`, or `descendant_count` MUST also match on `file_path`.

```sql
-- WRONG: joins across files
JOIN ast child ON child.parent_id = parent.node_id
-- CORRECT: scoped to same file
JOIN ast child ON child.parent_id = parent.node_id AND child.file_path = parent.file_path
```

**Predicate syntax on cached tables**: Always use `semantic_type = 'VALUE'` string comparison —
it works everywhere (fresh parse, cached tables, views). Example: `WHERE semantic_type = 'DEFINITION_FUNCTION'`.

**Heredocs**: Always use `<<'SQL'` with single-quoted delimiters to prevent shell expansion.
Append `&& echo "===DONE===" || echo "===FAILED==="` for reliable success/failure detection.

## Step 1 — Setup

```bash
DUCKDB=$(command -v duckdb)
```

If not found, delegate to `/duckdb-skills:install-duckdb` first.

```bash
duckdb :memory: -c "INSTALL sitting_duck FROM community; LOAD sitting_duck; SELECT 'ok';" 2>&1
```

## Step 2 — Determine scope & cache

From the user's request, determine:

1. **Target path**: directory, file, or glob. Default to cwd if unspecified.
2. **Language filter**: use language-specific globs (e.g. `**/*.go`, `**/*.py`). For mixed codebases use pattern arrays: `['**/*.go', '**/*.py']`.
3. **Exclusions**: always exclude generated code, vendor dirs, and test files unless the user asks about them.

If `--path` is provided, `cd` to that directory before running queries.

**Default caching strategy**: Always use in-memory cache for single-session analysis unless the
user specifically asks to analyze multiple projects or persist results.

```sql
LOAD sitting_duck;
CREATE TABLE ast AS
SELECT * FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200);
-- Then query `ast` instead of `read_ast(...)` for all subsequent queries
```

For persistent or cross-project caching strategies, read `reference/schema_and_macros.md`.

### Key features

- **`parse_ast()`**: parse code from strings (validate generated code, analyze snippets)
- **`peek := 'full'`**: extract complete function source without opening the file
- **`has_body(flags)`**: distinguish implementations from forward declarations
- **Context levels**: `'node_types_only'` (fast) → `'normalized'` (names) → `'native'` (full, default)
- **Pattern arrays**: `read_ast(['**/*.go', '**/*.py'], ignore_errors := true)` for multi-language

## Step 3 — Choose a workflow

Identify the user's goal. BEFORE writing any SQL, read the relevant workflow file to get the
exact SQL templates you need:

- **Workflow A (Orientation):** Read `workflows/A_orientation.md`
  Use for: "Help me understand this codebase", mapping APIs, finding dependencies.

- **Workflow B (Execution Flow):** Read `workflows/B_execution_flow.md`
  Use for: "How does X work?", call graphs, incoming/outgoing calls.

- **Workflow C (Change Location & Interfaces):** Read `workflows/C_change_impact.md`
  Use for: "Where do I make this change?", Go interface resolution.

- **Workflow D (Quality Audit):** Read `workflows/D_quality_audit.md`
  Use for: complexity analysis, dead code, nesting, security audit.

- **Workflow E (Individual Queries):** Read `workflows/E_individual_queries.md`
  Use for: standalone queries — list definitions, imports, pattern matching, tree navigation.

- **Workflow F (Type Analysis):** Read `workflows/F_type_analysis.md`
  Use for: struct fields, type references, function signatures, composition graphs.

- **Workflow G (LLM Workflows):** Read `workflows/G_llm_workflows.md`
  Use for: context priming, impact analysis, test gap detection, pre-write pattern discovery.

Use `cat` to read the specific workflow file, then adapt the SQL for your DuckDB query.
For column/predicate reference, read `reference/schema_and_macros.md`.

## Step 4 — Execute

Run via DuckDB CLI. Use heredoc for multi-line queries:

```bash
cd "<TARGET_DIR>" && duckdb :memory: -jsonlines <<'SQL' && echo "===DONE===" || echo "===FAILED==="
<GENERATED_SQL>
SQL
```

**Output format selection:**
- `-jsonlines` (default for this skill): structured, truncation-safe, handles wide AST tables with embedded commas/newlines in `peek`. Best for agent-consumed intermediate results.
- `-csv`: use when piping output to POSIX tools (`cut`, `awk`, `sort`).
- No flag (duckbox): use only when presenting final results to the user for readability.

## Step 5 — Interpret and act

After each query:

1. **Summarize findings** in plain language — don't just dump tables.
2. **Answer the actual question** — if the user asked "how does X work?", explain the flow.
3. **Chain to the next query** if needed — most real tasks need 2-3 queries.
4. **Suggest reading specific files** — use AST results to point to exact files and lines.
5. **Suggest follow-up** — "The most complex function is X (cyclomatic: 28) — want me to trace its calls?"

## Step 6 — Handle errors

- **Extension not found**: `INSTALL sitting_duck FROM community;` then retry.
- **Language not recognized**: `SELECT * FROM ast_supported_languages();`
- **File not found**: verify glob and cwd. Use `find` to locate files.
- **Parse errors**: handled by `ignore_errors := true`. Find them with `WHERE type = 'ERROR'`.
- **DuckDB error**: use `/duckdb-skills:duckdb-docs <error message>`.
| `is_string_literal(st)` | String literals |

### Analysis macros

| Macro | Returns |
|---|---|
| `ast_definitions(source)` | All named definitions with definition_type |
| `ast_function_metrics(source)` | Cyclomatic complexity, max_depth, lines per function |
| `ast_dead_code(source)` | Potentially unused functions with reason |
| `ast_nesting_analysis(source)` | Deeply nested code with max_depth |
| `ast_security_audit(source)` | Dangerous call patterns with risk_level |
| `ast_match(src, pattern, lang)` | Pattern matching with `__X__` wildcards |
| `ast_descendants(table, node_id)` | Subtree of a node |
| `ast_ancestors(table, node_id)` | Path from node to root |
| `ast_children(table, node_id)` | Immediate children |

### `read_ast()` parameters

| Parameter | Default | Purpose |
|---|---|---|
| `ignore_errors` | false | Continue on parse errors (**always use for multi-file**) |
| `peek` | 'smart' | Source snippet: integer (char limit), `'smart'`, `'full'` (complete source), `'none'` |
| `context` | 'native' | Detail level: `'none'` → `'node_types_only'` → `'normalized'` → `'native'` (each adds more columns) |
| `source` | 'lines' | `'none'`, `'path'`, `'lines'`, `'full'` (full adds start_column/end_column) |
| `structure` | 'full' | Tree info: `'none'`, `'minimal'`, `'full'` |
| `batch_size` | auto | Batch size for streaming large file sets |

### `parse_ast()` — parse code from a string

```sql
parse_ast('<CODE_STRING>', '<LANGUAGE>')
```

Same output schema as `read_ast()`. Use for validating generated code structure,
analyzing snippets, or comparing patterns without writing to disk.

### Go-specific notes

- **Named types**: `is_class_definition()` matches `struct_type` but name lives on parent `type_spec`. Use `WHERE type = 'type_spec' AND name IS NOT NULL`.
- **Methods vs functions**: `method_declaration` has receiver; `function_declaration` does not. Both match `is_function_definition()`.
- **Receiver access**: `parameters[1].name` gives the receiver (e.g. `q *DB`).
- **Exported = capitalized**: `SUBSTRING(name, 1, 1) = UPPER(SUBSTRING(name, 1, 1))`.
- **Test exclusions**: Filter `name NOT LIKE 'Test%' AND name NOT LIKE 'Benchmark%' AND name NOT LIKE 'Example%'`.
- **Generated code**: `file_path NOT LIKE '%.pb.go' AND file_path NOT LIKE '%_gen.go'`.
- **Tree traversal**: The AST tree is `type_spec → struct_type → field_declaration_list → field_declaration → type_child`. Always traverse via `parent_id + file_path` JOINs, not `node_id` ranges.
- **Struct field types**: Access through the chain: `type_spec` → `struct_type` → `field_declaration_list` → `field_declaration` → child `qualified_type`/`pointer_type`/`type_identifier`/etc.
- **Parameter types**: `parameters` is `STRUCT(name VARCHAR, type VARCHAR)[]`. Element `[1]` is the receiver for methods (`type='receiver'`). Use `list_filter(parameters, x -> x.type != 'receiver')` for non-receiver params.
- **Signature types**: `signature_type` gives return types (e.g. `error`, `*arrow.Schema`, `[]string`).