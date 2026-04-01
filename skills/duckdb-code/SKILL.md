---
name: duckdb-code
description: >
  Analyze source code at the AST level to understand codebases, trace execution flow,
  find where to make changes, and spot complexity. Uses DuckDB's sitting_duck extension
  to parse source files into SQL-queryable AST nodes with universal semantic types.
  USE THIS SKILL when: the user asks to understand unfamiliar code, find relevant functions
  before reading files, trace how a feature works end-to-end, locate where to implement
  a change, find callers/callees of a function, resolve interface implementations,
  map method sets by receiver type, map type hierarchies, or audit code quality.
  Also use when: the user asks about code structure, architecture, or dependencies;
  before implementing changes to find the right location and understand impact;
  to build a structural overview of unfamiliar code before reading files;
  to find test coverage gaps or code quality issues; to validate generated code structure.
  DO NOT USE when: you already know exactly which file and line to read or edit,
  or the user is asking a general programming question not about their codebase.
argument-hint: <question or task about the codebase> [--path directory_or_glob]
allowed-tools:
  - Bash
  - run_in_terminal
---

You are helping the user understand and navigate source code using DuckDB and the `sitting_duck`
community extension. This extension parses source files into AST nodes queryable via SQL, with
universal semantic types that work identically across 27 languages.

**Key insight**: AST queries let you answer structural questions across an entire codebase in
seconds — "what calls this function?", "where are errors handled?", "what's the public API?" —
without reading every file. Use this to build a mental model fast, then read specific files only
when you need implementation details.

Input: `$@`

## Step 1 — Setup

```bash
DUCKDB=$(command -v duckdb)
```

If not found, delegate to `/duckdb-skills:install-duckdb` first.

```bash
duckdb :memory: -c "INSTALL sitting_duck FROM community; LOAD sitting_duck; SELECT 'ok';" 2>&1
```

## Step 2 — Determine scope

From the user's request, determine:

1. **Target path**: directory, file, or glob. Default to cwd if unspecified.
2. **Language filter**: use language-specific globs (e.g. `**/*.go`, `**/*.py`). For mixed codebases use pattern arrays: `['**/*.go', '**/*.py']`.
3. **Exclusions**: always exclude generated code, vendor dirs, and test files unless the user asks about them. Use `WHERE file_path NOT LIKE` filters.

If `--path` is provided, `cd` to that directory before running queries.

### Caching strategy: per-project and/or central cache

Parsing is expensive (~5-7s for a medium project). Caching gives **7000x faster queries** (0.001s).
Two caching approaches — both are valid and can be used together:

#### Option A: Per-project cache (`code_ast.duckdb` in project root)

Best for: fast local queries, ephemeral analysis, keeping cache near the code.

```bash
# Create/refresh the project cache
cd "<PROJECT_DIR>" && duckdb <<'SQL'
LOAD sitting_duck;
ATTACH 'code_ast.duckdb' AS cache;
CREATE OR REPLACE TABLE cache.ast AS 
SELECT * FROM read_ast('**/*.go', ignore_errors := true, peek := 200);
CREATE OR REPLACE TABLE cache.meta AS
SELECT current_timestamp AS cached_at,
  (SELECT count(DISTINCT file_path) FROM cache.ast) AS file_count,
  (SELECT count(*) FROM cache.ast) AS node_count;
SELECT * FROM cache.meta;
SQL
```

**Add to `.gitignore`** if the project is version-controlled:

```bash
echo 'code_ast.duckdb' >> .gitignore
```

**Query the cache** (subsequent queries are instant):

```bash
duckdb <<'SQL'
LOAD sitting_duck;
ATTACH 'code_ast.duckdb' AS cache (READ_ONLY);
-- Query directly from cache.ast
SELECT count(*) FROM cache.ast WHERE semantic_type = 'DEFINITION_FUNCTION';
SQL
```

**Auto-load with `-init`** — create a `.duckdb-ast-init.sql` in the project:

```sql
-- .duckdb-ast-init.sql
LOAD sitting_duck;
ATTACH 'code_ast.duckdb' AS cache (READ_ONLY);
CREATE OR REPLACE VIEW ast AS SELECT * FROM cache.ast;
```

Then all queries can use `ast` directly:

```bash
duckdb :memory: -init .duckdb-ast-init.sql -c "SELECT count(*) FROM ast WHERE semantic_type = 'DEFINITION_FUNCTION';"
```

#### Option B: Central cache (`~/.cache/sitting-duck/code_ast.duckdb`)

Best for: cross-project queries, comparing patterns between projects, finding shared types.

```bash
mkdir -p ~/.cache/sitting-duck && duckdb ~/.cache/sitting-duck/code_ast.duckdb <<'SQL'
LOAD sitting_duck;
-- Add/refresh a project (uses project column for isolation)
DELETE FROM ast WHERE project = '<PROJECT_NAME>';  -- no-op first time
INSERT INTO ast SELECT '<PROJECT_NAME>' AS project, * 
FROM read_ast('<ABSOLUTE_PATH>/**/*.go', ignore_errors := true, peek := 200);
-- If the table doesn't exist yet (first project):
-- CREATE TABLE ast AS SELECT '<PROJECT_NAME>' AS project, * FROM read_ast(...)
CREATE OR REPLACE TABLE projects AS
SELECT project, count(DISTINCT file_path) AS files, count(*) AS nodes, 
  current_timestamp AS cached_at
FROM ast GROUP BY project;
SELECT * FROM projects;
SQL
```

**Cross-project queries** — find shared patterns:

```sql
-- Functions with same name across projects
SELECT name, list(DISTINCT project) AS projects, count(*) AS occurrences
FROM ast WHERE semantic_type = 'DEFINITION_FUNCTION' AND name NOT LIKE 'Test%'
GROUP BY name HAVING count(DISTINCT project) > 1
ORDER BY occurrences DESC LIMIT 20;
```

**Alternative**: ATTACH separate per-project caches for ad-hoc cross-project queries:

```sql
LOAD sitting_duck;
ATTACH '/path/to/projectA/code_ast.duckdb' AS projA (READ_ONLY);
ATTACH '/path/to/projectB/code_ast.duckdb' AS projB (READ_ONLY);
-- Compare function counts
SELECT 'projectA' AS proj, count(*) FROM projA.ast WHERE semantic_type = 'DEFINITION_FUNCTION'
UNION ALL
SELECT 'projectB', count(*) FROM projB.ast WHERE semantic_type = 'DEFINITION_FUNCTION';
```

#### Incremental refresh

Full re-parse is usually fast enough (<10s), but for surgical updates:

```sql
-- Refresh specific files after editing
DELETE FROM cache.ast WHERE file_path IN ('db.go', 'config.go');
INSERT INTO cache.ast SELECT * FROM read_ast('db.go', ignore_errors := true, peek := 200);
INSERT INTO cache.ast SELECT * FROM read_ast('config.go', ignore_errors := true, peek := 200);
```

For central cache, scope the DELETE to the project: `WHERE project = 'X' AND file_path IN (...)`.

#### Important: predicate syntax on cached tables

When querying cached tables (`cache.ast`), you must pass the column explicitly to predicate functions:

```sql
-- From read_ast(): no-arg predicates may work (binds implicit column)
WHERE is_definition() AND is_function()          -- on read_ast() output

-- From cached table: ALWAYS use one of these approaches
WHERE semantic_type = 'DEFINITION_FUNCTION'       -- string comparison (recommended)
WHERE is_function_definition(semantic_type)        -- explicit column arg
```

**Recommendation**: Always use `semantic_type = 'VALUE'` string comparison — it works everywhere
(fresh parse, cached tables, views) and is more readable.

### In-memory cache for single-session analysis

For quick exploratory work within one `duckdb` session (no persistent file):

```sql
LOAD sitting_duck;
CREATE TABLE ast AS
SELECT * FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200);
-- Then query `ast` instead of `read_ast(...)` for all subsequent queries
```

### Performance tip: context levels

Use lighter context levels for faster processing when you don't need full extraction:

```sql
-- Fast: only semantic types (no names, no signatures)
read_ast('**/*.go', context := 'node_types_only', ignore_errors := true)
-- Medium: adds names (no signatures, no parameters)
read_ast('**/*.go', context := 'normalized', ignore_errors := true)
-- Full (default): all extraction including signatures, parameters, modifiers
read_ast('**/*.go', context := 'native', ignore_errors := true)
```

Use `context := 'normalized'` for large codebases when you only need names.
Use `context := 'node_types_only'` for pure counting/classification queries.

### Pattern arrays for multi-language or multi-directory analysis

```sql
-- Analyze multiple languages in one query
read_ast(['**/*.go', '**/*.py', '**/*.ts'], ignore_errors := true)
-- Target specific directories
read_ast(['cmd/**/*.go', 'internal/**/*.go', 'pkg/**/*.go'], ignore_errors := true)
```

### `parse_ast()`: parse code from strings

Parse code directly from a string without writing to a file. Useful for:
- Validating structure of generated code
- Analyzing code snippets from context
- Comparing patterns between generated and existing code

```sql
SELECT name, type, semantic_type, peek
FROM parse_ast('<CODE_STRING>', '<LANGUAGE>')
WHERE is_definition(semantic_type);
```

### `peek := 'full'`: extract complete source

Use `peek := 'full'` to get the entire source text of a node — including complete function bodies.
This lets you extract a specific function's source to read without opening the whole file:

```sql
SELECT name, peek as source
FROM read_ast('<FILE>', peek := 'full')
WHERE type IN ('function_declaration','method_declaration') AND name = '<FUNC>';
```

### `flags` column: declaration vs implementation

Use `has_body(flags)` to distinguish implemented functions from forward declarations/interfaces:

```sql
-- Find functions with implementations (not just declared)
WHERE is_function_definition(semantic_type) AND has_body(flags)
-- Find forward declarations only (C/C++ headers)
WHERE is_function_definition(semantic_type) AND is_declaration_only(flags)
```

### `semantic_type` supports string comparison

`semantic_type` is a custom DuckDB type that displays as a string:

```sql
-- String comparison (readable)
WHERE semantic_type = 'DEFINITION_FUNCTION'
-- Equivalent to predicate function
WHERE is_function_definition(semantic_type)
```

Common values: `DEFINITION_FUNCTION`, `DEFINITION_CLASS`, `DEFINITION_VARIABLE`,
`DEFINITION_MODULE`, `EXECUTION_INVOCATION`, `FLOW_CONDITIONAL`, `FLOW_LOOP`,
`TYPE_REFERENCE`, `NAME_IDENTIFIER`, `LITERAL_STRING`, `OPERATOR_ASSIGNMENT`.

### Multi-step chaining pattern

For complex analysis, chain multiple SQL statements in a single `duckdb` invocation.
DuckDB processes statements sequentially and preserves intermediate tables:

```bash
duckdb :memory: -markdown <<'SQL' && echo "===DONE===" || echo "===FAILED==="
LOAD sitting_duck;
-- Step 1: Cache the AST
CREATE TABLE ast AS SELECT * FROM read_ast('**/*.go', ignore_errors := true, peek := 300);
-- Step 2: Build derived tables
CREATE TABLE call_graph AS SELECT ... FROM ast ...;
-- Step 3: Query against both
SELECT ... FROM call_graph JOIN ast ...;
SQL
```

Always use heredocs (`<<'SQL'`) with single-quoted delimiters to prevent shell expansion.
Append `&& echo "===DONE===" || echo "===FAILED==="` for reliable success/failure detection.

### Critical: `node_id` is per-file, not globally unique

**All JOINs using `node_id`, `parent_id`, or `descendant_count` MUST also match on `file_path`.**
Without `file_path` scoping, tree traversal queries return wrong results from unrelated files.

```sql
-- WRONG: joins across files
JOIN ast child ON child.parent_id = parent.node_id
-- CORRECT: scoped to same file
JOIN ast child ON child.parent_id = parent.node_id AND child.file_path = parent.file_path
```

## Step 3 — Choose a workflow based on the user's goal

Match the user's intent to one of these workflows. Most real tasks need 2-3 chained queries.

---

### Workflow A: "Help me understand this codebase" (Orientation)

Run these in sequence to build a mental model:

**A1. Inventory** — What languages, how big, how many files?

```sql
LOAD sitting_duck;
SELECT language, COUNT(DISTINCT file_path) as files, COUNT(*) as nodes,
       COUNT(CASE WHEN is_function_definition(semantic_type) THEN 1 END) as functions,
       COUNT(CASE WHEN is_class_definition(semantic_type) THEN 1 END) as types
FROM read_ast('<PATTERN>', ignore_errors := true)
GROUP BY language ORDER BY nodes DESC;
```

**A2. File map** — Which files have the most logic?

```sql
SELECT file_path, COUNT(CASE WHEN is_function_definition(semantic_type) THEN 1 END) as functions,
       COUNT(CASE WHEN is_function_call(semantic_type) THEN 1 END) as calls,
       MAX(depth) as max_depth
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE file_path NOT LIKE '%_test.go' AND file_path NOT LIKE '%test_%'
GROUP BY file_path ORDER BY functions DESC;
```

**A3. Public API** — What are the entry points / exported functions?

For Go (exported = capitalized name):
```sql
SELECT name, signature_type as returns, parameters, file_path, start_line,
       (end_line - start_line) as lines
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE is_function_definition(semantic_type) AND name IS NOT NULL
  AND SUBSTRING(name, 1, 1) = UPPER(SUBSTRING(name, 1, 1))
  AND file_path NOT LIKE '%_test.go'
ORDER BY file_path, start_line;
```

For Python/JS, look at module-level definitions or `__all__`/`export` statements.

**A4. Types and structures** — What are the key data types?

```sql
-- Go: named types (struct, interface)
SELECT name, type, file_path, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE type = 'type_spec' AND name IS NOT NULL
  AND file_path NOT LIKE '%_test.go'
ORDER BY file_path, start_line;
```

**A5. Dependencies** — What external packages are used?

```sql
SELECT file_path, name as import_path
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE is_import(semantic_type) AND name IS NOT NULL
  AND name LIKE '%/%'
ORDER BY file_path;
```

After these queries, summarize: "This is a [size] [language] project with [N] files.
The core logic lives in [files]. Key types are [X, Y, Z]. It depends on [packages]."

---

### Workflow B: "How does X work?" (Execution flow tracing)

To trace how a feature/function works, chain these queries:

**B1. Find the function definition**

```sql
LOAD sitting_duck;
SELECT name, file_path, start_line, end_line, parameters, signature_type, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200)
WHERE is_function_definition(semantic_type) AND name = '<FUNCTION_NAME>'
  AND file_path NOT LIKE '%_test.go';
```

**B2. What does it call?** (outgoing calls from a function)

Uses `node_id` + `descendant_count` to scope calls within a function body:

```sql
WITH func AS (
    SELECT node_id, descendant_count, file_path
    FROM read_ast('<PATTERN>', ignore_errors := true)
    WHERE is_function_definition(semantic_type) AND name = '<FUNCTION_NAME>'
      AND file_path NOT LIKE '%_test.go'
    LIMIT 1
),
base AS (FROM read_ast('<FILE>'))  -- parse same file
SELECT b.name, b.signature_type, b.start_line, b.peek
FROM base b, func f
WHERE b.node_id > f.node_id
  AND b.node_id <= f.node_id + f.descendant_count
  AND is_function_call(b.semantic_type) AND b.name IS NOT NULL
ORDER BY b.start_line;
```

**B3. What calls it?** (incoming calls — find all callers across the codebase)

```sql
SELECT file_path, name as call_site, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE is_function_call(semantic_type) AND name = '<FUNCTION_NAME>'
  AND file_path NOT LIKE '%_test.go'
ORDER BY file_path, start_line;
```

**B4. Build a call graph and trace N-level execution flow** (multi-step chain)

This uses DuckDB's multi-statement chaining: cache → build edges → recursive trace.

```sql
LOAD sitting_duck;
CREATE TABLE ast AS SELECT * FROM read_ast('<PATTERN>', ignore_errors := true, peek := 300);

-- Build caller→callee edges using line-range scoping
CREATE TABLE call_graph AS 
WITH func_scopes AS (
    SELECT name as func_name, 
        regexp_extract(parameters[1].name, '\*?(\w+)$', 1) as receiver,
        file_path, start_line, end_line
    FROM ast
    WHERE type IN ('function_declaration', 'method_declaration')
    AND file_path NOT LIKE '%_test.go'
)
SELECT DISTINCT
    COALESCE(f.receiver || '.', '') || f.func_name as caller,
    f.func_name as caller_short,  -- for matching calls without receiver
    c.name as callee,
    f.file_path
FROM func_scopes f
JOIN ast c ON c.file_path = f.file_path 
    AND c.start_line BETWEEN f.start_line AND f.end_line
    AND c.type = 'call_expression'
    AND c.name != '' AND c.name != f.func_name;

-- Recursive call chain from a starting function
WITH RECURSIVE call_chain AS (
    SELECT '<Receiver.Function>' as func, 0 as depth, '<Receiver.Function>' as path
    UNION ALL
    SELECT cg.callee, cc.depth + 1, cc.path || ' → ' || cg.callee
    FROM call_chain cc
    JOIN call_graph cg ON (cg.caller = cc.func OR cg.caller_short = cc.func)
    WHERE cc.depth < 3  -- adjust depth as needed
    AND cg.callee NOT IN ('Errorf','Error','Sprintf','Fprintf','Printf','Wrap')  -- skip noise
)
SELECT DISTINCT depth, func, path FROM call_chain ORDER BY depth, func;
```

After tracing, summarize the call chain: "X is called by [A, B, C]. X itself calls [D, E, F].
The execution flow is: A → X → D → E."

---

### Workflow C: "Where do I make this change?" (Change location)

**C1. Search by concept** — Find definitions related to a concept using name + peek:

```sql
LOAD sitting_duck;
SELECT file_path, name, type, start_line, end_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE is_definition(semantic_type) AND name IS NOT NULL
  AND file_path NOT LIKE '%_test.go'
  AND (name ILIKE '%<CONCEPT>%' OR peek ILIKE '%<CONCEPT>%')
ORDER BY file_path, start_line;
```

**C2. Find error handling for a subsystem** — Locate where errors are created/wrapped:

```sql
SELECT file_path, name, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200)
WHERE is_function_call(semantic_type)
  AND name IN ('Errorf', 'Wrap', 'Wrapf', 'New', 'Error')
  AND peek ILIKE '%<KEYWORD>%'
ORDER BY file_path, start_line;
```

**C3. Find methods on a type** — What operations does type T support?

```sql
SELECT name as method, signature_type as returns, parameters, file_path, start_line,
       (end_line - start_line) as lines
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE type = 'method_declaration' AND name IS NOT NULL
  AND parameters[1].name LIKE '%<TYPE_NAME>%'
ORDER BY file_path, start_line;
```

**C4. Find similar patterns** — Look for code that does something similar to what you want:

```sql
SELECT file_path, name, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200)
WHERE is_function_definition(semantic_type) AND name IS NOT NULL
  AND peek ILIKE '%<PATTERN_TEXT>%'
  AND file_path NOT LIKE '%_test.go'
ORDER BY file_path, start_line;
```

After finding the location, tell the user: "The change should go in [file] near [function].
Here's the relevant code and what it currently does."

---

### Workflow C2: "What implements this interface?" (Go interface resolution)

AST analysis can map method sets and match interfaces to types. It works best for **interfaces
defined in the same codebase**. For external interfaces (e.g. `io.Reader`, `driver.Conn`), you
already know their required methods — use that knowledge to find implementors by method name.

**Limitation**: sitting_duck parses syntax, not types. It cannot resolve cross-package interfaces
automatically. But it *can* find all the evidence you need to answer the question.

**C2a. Find all local interfaces and their required methods**

```sql
LOAD sitting_duck;
CREATE TABLE ast AS SELECT * FROM read_ast('<PATTERN>', ignore_errors := true, peek := 400);

SELECT ts.name AS interface_name, ts.file_path,
       me.name AS method_name, me.peek AS method_sig
FROM ast ts
JOIN ast it ON it.file_path = ts.file_path AND it.parent_id = ts.node_id AND it.type = 'interface_type'
JOIN ast me ON me.file_path = it.file_path AND me.parent_id = it.node_id AND me.type = 'method_elem'
WHERE ts.type = 'type_spec' AND ts.name IS NOT NULL AND ts.name != ''
ORDER BY ts.name, me.name;
```

**C2b. Map all receiver types and their method sets**

This is the most powerful query for interface resolution — shows every type's complete method set:

```sql
SELECT
  regexp_extract(peek, '\(\w+ \*?(\w+)\)', 1) AS receiver_type,
  list(name ORDER BY name) AS methods,
  count(*) AS method_count
FROM ast
WHERE type = 'method_declaration' AND file_path NOT LIKE '%_test.go'
GROUP BY receiver_type
ORDER BY method_count DESC;
```

**C2c. Find types implementing a known interface** (external or local)

When you know the interface's method names (e.g. `io.Reader` needs `Read`, `database/sql/driver.Conn` needs `Prepare`, `Close`, `Begin`):

```sql
WITH needed_methods AS (
  SELECT unnest(['Prepare', 'Close', 'Begin']) AS method_name  -- replace with actual methods
),
receiver_methods AS (
  SELECT regexp_extract(peek, '\(\w+ \*?(\w+)\)', 1) AS receiver_type,
         name AS method_name, file_path
  FROM ast WHERE type = 'method_declaration'
),
matches AS (
  SELECT rm.receiver_type, rm.method_name, rm.file_path
  FROM receiver_methods rm
  JOIN needed_methods nm ON rm.method_name = nm.method_name
  WHERE rm.receiver_type != ''
),
counts AS (
  SELECT receiver_type, count(DISTINCT method_name) AS matched,
         any_value(file_path) AS impl_file
  FROM matches GROUP BY receiver_type
)
SELECT receiver_type, matched || '/' || (SELECT count(*) FROM needed_methods) AS coverage,
       impl_file
FROM counts
WHERE matched = (SELECT count(*) FROM needed_methods)
ORDER BY receiver_type;
```

**C2d. Find type assertions** — Where does code assert an interface?

```sql
SELECT file_path, name, start_line, peek
FROM ast
WHERE type = 'type_assertion_expression'
ORDER BY file_path, start_line;
```

After running these, summarize: "Type [X] implements [Interface] — it has methods [A, B, C]
defined in [file]. Type assertions for this interface appear at [locations]."

---

### Workflow F: "What types does this code use?" (Type analysis)

AST analysis captures rich type information: struct fields, function signatures, type references,
composition, and external dependency types. Use multi-step chaining to build a complete type picture.

**F1. Complete struct field type map** — What fields does each struct have and what types are they?

```sql
LOAD sitting_duck;
CREATE TABLE ast AS SELECT * FROM read_ast('<PATTERN>', ignore_errors := true, peek := 300);

-- Chain: type_spec → struct_type → field_declaration_list → field_declaration → type child
WITH struct_defs AS (
    SELECT ts.name as struct_name, st.node_id as struct_nid, ts.file_path
    FROM ast ts
    JOIN ast st ON st.parent_id = ts.node_id AND st.file_path = ts.file_path
        AND st.type = 'struct_type'
    WHERE ts.type = 'type_spec'
),
field_lists AS (
    SELECT s.struct_name, fl.node_id as fl_nid, s.file_path
    FROM struct_defs s
    JOIN ast fl ON fl.parent_id = s.struct_nid AND fl.file_path = s.file_path
        AND fl.type = 'field_declaration_list'
),
fields AS (
    SELECT fl.struct_name, fd.name, fd.node_id, fd.file_path, fd.peek
    FROM field_lists fl
    JOIN ast fd ON fd.parent_id = fl.fl_nid AND fd.file_path = fl.file_path
        AND fd.type = 'field_declaration'
),
field_types AS (
    SELECT f.struct_name, f.name as field_name, t.peek as field_type, t.type as type_kind
    FROM fields f
    JOIN ast t ON t.parent_id = f.node_id AND t.file_path = f.file_path
    AND t.type IN ('qualified_type','pointer_type','type_identifier','slice_type',
        'map_type','array_type','interface_type','function_type','channel_type')
)
SELECT struct_name, field_name, field_type, type_kind
FROM field_types
ORDER BY struct_name, field_name;
```

**F2. Full function signature database** — Every function with typed params and return types:

```sql
SELECT 
    name,
    CASE WHEN type = 'method_declaration' 
         THEN regexp_extract(parameters[1].name, '\*?(\w+)$', 1)
         ELSE NULL END as receiver,
    signature_type as returns,
    list_filter(parameters, x -> x.type != 'receiver') as params,
    file_path, start_line
FROM ast
WHERE type IN ('function_declaration', 'method_declaration')
AND file_path NOT LIKE '%_test.go'
ORDER BY COALESCE(receiver, ''), name;
```

**F3. Type flow trace** — Where is a specific type defined, referenced, and used?

```sql
SELECT 
    CASE 
        WHEN type = 'type_spec' THEN 'DEFINED'
        WHEN type = 'method_elem' THEN 'INTERFACE_METHOD'
        WHEN type = 'parameter_declaration' THEN 'PARAM_TYPE'
        WHEN type = 'field_declaration' THEN 'STRUCT_FIELD'
        WHEN type = 'type_assertion_expression' THEN 'TYPE_ASSERT'
        WHEN type = 'type_conversion_expression' THEN 'TYPE_CONVERT'
        WHEN type IN ('type_identifier','qualified_type') THEN 'TYPE_REF'
        WHEN type = 'function_declaration' THEN 'FUNC_SIGNATURE'
        WHEN type = 'method_declaration' THEN 'METHOD_SIGNATURE'
        ELSE type
    END as usage_kind,
    file_path, start_line, peek
FROM ast
WHERE (name = '<TYPE_NAME>' OR peek ILIKE '%<TYPE_NAME>%')
AND type NOT IN ('identifier','comment','interpreted_string_literal','field_identifier')
ORDER BY file_path, start_line;
```

**F4. External dependency type map** — Which external packages/types are used where?

```sql
SELECT
    peek as external_type,
    COUNT(*) as usage_count,
    list(DISTINCT file_path) as files
FROM ast
WHERE type = 'qualified_type'
GROUP BY peek
ORDER BY usage_count DESC;
```

**F5. Type composition graph** — How types reference each other:

```sql
WITH struct_fields AS (
    -- (use F1 query as CTE here)
    SELECT struct_name, field_type FROM ... -- abbreviated, use F1
)
SELECT struct_name || ' → ' || field_type as edge,
       struct_name as from_type, field_type as to_type
FROM struct_fields
WHERE field_type NOT IN ('string','int','bool','int32','int64','float64','error','any')
ORDER BY from_type;
```

After type analysis, summarize: "Type [X] has [N] fields. Its key dependencies are
[pkg.TypeA, pkg.TypeB]. It's used as a parameter in [funcs] and as a field in [structs]."

---

### Workflow G: LLM-specific workflows (Accelerating coding tasks)

These workflows integrate AST analysis into the LLM's coding process — use them
*before*, *during*, and *after* writing code.

**G1. Context window priming** — Build a skeletal map to understand a codebase in minimal tokens:

Instead of reading many files, generate a compact signature map:

```sql
LOAD sitting_duck;
SELECT
    file_path,
    CASE WHEN type = 'method_declaration'
         THEN 'func (' || COALESCE(parameters[1].name, '') || ') ' || name
         ELSE 'func ' || name END
    || '(' ||
    array_to_string(list_transform(
        list_filter(parameters, (x) -> x.type != 'receiver'),
        (x) -> x.name || ' ' || COALESCE(x.type, '?')
    ), ', ') || ')' ||
    COALESCE(' ' || signature_type, '') as signature,
    start_line
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE type IN ('function_declaration', 'method_declaration')
AND file_path NOT LIKE '%_test.go' AND name IS NOT NULL
ORDER BY file_path, start_line;
```

Also generate a type map:
```sql
SELECT name, type, file_path, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE type = 'type_spec' AND name IS NOT NULL
AND file_path NOT LIKE '%_test.go'
ORDER BY file_path;
```

Use both together to prime your understanding, then read specific files with `read_file`.

**G2. Impact analysis** — Before editing a function or type, find everything that depends on it:

```sql
LOAD sitting_duck;
CREATE TABLE ast AS SELECT * FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200);

-- Find all references to a type/function name
SELECT
    CASE
        WHEN type = 'type_spec' THEN 'DEFINITION'
        WHEN type = 'method_declaration' THEN 'METHOD'
        WHEN type = 'parameter_declaration' THEN 'PARAM'
        WHEN type = 'field_declaration' THEN 'FIELD'
        WHEN semantic_type = 'TYPE_REFERENCE' THEN 'TYPE_REF'
        WHEN semantic_type = 'EXECUTION_INVOCATION' THEN 'CALL'
        ELSE type
    END as usage_kind,
    file_path, start_line, left(peek, 80) as context
FROM ast
WHERE name = '<NAME>' AND type NOT IN ('comment','interpreted_string_literal')
ORDER BY usage_kind, file_path, start_line;
```

This shows: where the type/function is defined, where it's referenced as a type, where it's
called, and where it appears in parameters or fields. Use this to gauge blast radius before editing.

**G3. Test coverage gap detection** — Find exported functions without corresponding tests:

```sql
LOAD sitting_duck;
CREATE TABLE ast AS SELECT * FROM read_ast('<PATTERN>', ignore_errors := true);

WITH exported_funcs AS (
    SELECT name, file_path, start_line
    FROM ast
    WHERE type IN ('function_declaration','method_declaration')
    AND name IS NOT NULL
    AND SUBSTRING(name, 1, 1) = UPPER(SUBSTRING(name, 1, 1))
    AND file_path NOT LIKE '%_test.go'
),
test_funcs AS (
    SELECT name FROM ast
    WHERE type = 'function_declaration'
    AND file_path LIKE '%_test.go' AND name LIKE 'Test%'
),
coverage AS (
    SELECT e.name, e.file_path, e.start_line,
        EXISTS(SELECT 1 FROM test_funcs t WHERE t.name LIKE '%' || e.name || '%') as has_test
    FROM exported_funcs e
)
SELECT name, file_path, start_line,
    CASE WHEN has_test THEN 'tested' ELSE 'UNTESTED' END as status
FROM coverage
ORDER BY has_test ASC, file_path, start_line;
```

**G4. Pre-write pattern discovery** — Before writing new code, find similar existing patterns:

```sql
-- Find how existing code does something similar
SELECT name, file_path, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 'full')
WHERE type IN ('function_declaration','method_declaration')
AND name IS NOT NULL
AND (name ILIKE '%<CONCEPT>%' OR peek ILIKE '%<CONCEPT>%')
AND file_path NOT LIKE '%_test.go'
ORDER BY file_path;
```

Use `peek := 'full'` here to get complete function source of matching patterns,
so you can follow the same style and conventions.

**G5. Targeted file reading** — Use AST results to decide exactly which files and lines to read:

After any query that returns `file_path` and `start_line`, use those results to call `read_file`
on exactly the relevant ranges instead of reading entire files or guessing.

```sql
-- Find the exact location, then read just those lines
SELECT file_path, start_line, end_line, name, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200)
WHERE is_function_definition(semantic_type) AND name = '<FUNC>'
AND file_path NOT LIKE '%_test.go';
```

Then: `read_file(file_path, start_line, end_line)` — read only what matters.

**G6. Error handling consistency** — Find how errors are created throughout the codebase:

```sql
SELECT file_path, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE semantic_type = 'EXECUTION_INVOCATION'
AND name IN ('Errorf', 'Wrapf', 'Wrap', 'New', 'Newf', 'WithStack')
ORDER BY file_path, start_line;
```

Use this to maintain consistent error handling style when writing new code.

**G7. Post-edit validation with `parse_ast()`** — After generating code, verify its structure:

```sql
LOAD sitting_duck;
-- Parse the generated code to verify it has the expected structure
SELECT
    COUNT(CASE WHEN semantic_type = 'DEFINITION_FUNCTION' THEN 1 END) as functions,
    COUNT(CASE WHEN semantic_type = 'DEFINITION_CLASS' THEN 1 END) as types,
    COUNT(CASE WHEN type = 'ERROR' THEN 1 END) as parse_errors,
    MAX(depth) as max_nesting
FROM parse_ast('<GENERATED_CODE>', '<LANGUAGE>');
```

If `parse_errors > 0`, the generated code has syntax issues.

---

### Workflow D: "What's wrong / what needs attention?" (Quality audit)

**D1. Most complex functions** (refactoring candidates)

```sql
LOAD sitting_duck;
SELECT name, file_path, cyclomatic, max_depth, lines
FROM ast_function_metrics('<PATTERN>')
WHERE name NOT LIKE 'Test%'
ORDER BY cyclomatic DESC LIMIT 20;
```

**D2. Deeply nested code**

```sql
SELECT file_path, name, max_depth, start_line
FROM ast_nesting_analysis('<PATTERN>')
ORDER BY max_depth DESC LIMIT 20;
```

**D3. Dead code** (unreferenced functions)

```sql
SELECT name, file_path, start_line, reason
FROM ast_dead_code('<PATTERN>')
WHERE name NOT LIKE 'Test%' AND name NOT LIKE 'Benchmark%'
  AND name NOT LIKE 'Example%'
LIMIT 30;
```

**D4. Control flow hotspots** — Files with high branching:

```sql
SELECT file_path,
    COUNT(CASE WHEN is_conditional(semantic_type) THEN 1 END) as conditionals,
    COUNT(CASE WHEN is_loop(semantic_type) THEN 1 END) as loops,
    COUNT(CASE WHEN is_jump(semantic_type) THEN 1 END) as jumps
FROM read_ast('<PATTERN>', ignore_errors := true)
GROUP BY file_path HAVING (conditionals + loops) > 10
ORDER BY (conditionals + loops) DESC;
```

**D5. Security audit** (most effective for Python, JS, Ruby, PHP)

```sql
SELECT * FROM ast_security_audit('<PATTERN>')
WHERE risk_level = 'high' ORDER BY file_path, start_line;
```

---

### Workflow E: Individual queries (Reference)

Use these standalone when you need a specific answer:

**E1. List all definitions**
```sql
LOAD sitting_duck;
SELECT name, definition_type, file_path, start_line, end_line
FROM ast_definitions('<PATTERN>') ORDER BY file_path, start_line;
```

**E2. Import analysis**
```sql
SELECT name, peek, file_path, start_line
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE is_import(semantic_type) ORDER BY file_path;
```

**E3. Pattern matching with wildcards** (find code structures by example)
```sql
-- __X__ captures a single node as "X"
-- __ matches any single node
-- %__<BODY*>__% matches zero or more children
SELECT captures, file_path, start_line
FROM ast_match('<PATTERN>', '<CODE_PATTERN>', '<LANGUAGE>') LIMIT 20;
```

**E4. Detailed single-file analysis**
```sql
SELECT name, type, semantic_type_to_string(semantic_type) as sem_type,
       signature_type, parameters, start_line, end_line, peek
FROM read_ast('<FILE>', peek := 200)
WHERE is_definition(semantic_type) AND name IS NOT NULL
ORDER BY start_line;
```

**E5. Tree navigation** (inspect a specific node's subtree)
```sql
WITH base AS (FROM read_ast('<FILE>'))
SELECT * FROM ast_descendants(base, <NODE_ID>);
-- Also: ast_ancestors(base, <NODE_ID>), ast_children(base, <NODE_ID>)
```

**E6. Cross-language analysis**
```sql
SELECT language, COUNT(*) as functions
FROM read_ast(['**/*.py', '**/*.js', '**/*.go'], ignore_errors := true)
WHERE is_function_definition(semantic_type)
GROUP BY language ORDER BY functions DESC;
```

## Step 4 — Execute

Run via DuckDB CLI. Use heredoc for multi-line queries:

```bash
cd "<TARGET_DIR>" && duckdb :memory: <<'SQL'
<GENERATED_SQL>
SQL
```

Use `-csv` for machine-readable output when piping to further processing.
Omit `-csv` for the default box format when readability matters.

## Step 5 — Interpret and act

After each query:

1. **Summarize findings** in plain language — don't just dump tables.
2. **Answer the actual question** — if the user asked "how does X work?", explain the flow.
3. **Chain to the next query** if needed — most real tasks need 2-3 queries.
4. **Suggest reading specific files** — use the AST results to point to exact files and lines worth reading with `read_file`, rather than reading everything.
5. **Suggest follow-up** — "The most complex function is X (cyclomatic: 28) — want me to trace its calls?"

## Step 6 — Handle errors

- **Extension not found**: `INSTALL sitting_duck FROM community;` then retry.
- **Language not recognized**: `SELECT * FROM ast_supported_languages();`
- **File not found**: verify glob and cwd. Use `find` to locate files.
- **Parse errors**: handled by `ignore_errors := true`. Find them with `WHERE type = 'ERROR'`.
- **DuckDB error**: use `/duckdb-skills:duckdb-docs <error message>`.

---

## Quick reference

### Supported languages (27)

| Category | Languages |
|---|---|
| Web | JavaScript, TypeScript, HTML, CSS |
| Systems | C, C++, Go, Rust, Zig |
| Scripting | Python, Ruby, PHP, Lua, R, Bash |
| Enterprise | Java, C#, Kotlin, Swift, Dart, Scala |
| Data/Query | SQL, DuckDB, GraphQL, JSON |
| Config | HCL (Terraform), TOML |
| Docs | Markdown |

### Key columns from `read_ast()`

| Column | Type | Use for |
|---|---|---|
| `name` | VARCHAR | Function/type/variable name |
| `type` | VARCHAR | Language-specific AST node type |
| `semantic_type` | SEMANTIC_TYPE | Universal category — supports string comparison: `= 'DEFINITION_FUNCTION'` |
| `signature_type` | VARCHAR | Return type for functions, class kind for types, full call expr for calls |
| `parameters` | STRUCT(name,type)[] | Function params with name and type; `[1]` is receiver for Go methods |
| `qualified_name` | VARCHAR | Scope path e.g. `C/User F/__init__` — disambiguates same-named methods |
| `modifiers` | VARCHAR[] | Access keywords: `public`, `static`, `async`, etc. |
| `annotations` | VARCHAR | Decorator/annotation text |
| `peek` | VARCHAR | Source snippet. Use `peek := 200` for previews, `peek := 'full'` for complete source |
| `node_id` | BIGINT | Per-file node ID; **always pair with `file_path` in JOINs** |
| `descendant_count` | UINTEGER | Total descendants; use as complexity proxy |
| `children_count` | UINTEGER | Direct child count |
| `depth` | UINTEGER | Tree depth (0 = root); use for nesting analysis |
| `parent_id` | BIGINT | Tree traversal — always pair with `file_path` |
| `flags` | UTINYINT | `has_body(flags)` = implemented; `is_declaration_only(flags)` = forward decl |

### Semantic type predicates (use in WHERE)

| Predicate | Matches |
|---|---|
| `is_function_definition(st)` | Function/method definitions |
| `is_class_definition(st)` | Classes, structs, interfaces |
| `is_variable_definition(st)` | Variable declarations |
| `is_function_call(st)` | Function/method calls |
| `is_definition(st)` | Any definition |
| `is_call(st)` | Any call expression |
| `is_control_flow(st)` | Any control flow |
| `is_conditional(st)` | if/switch/match |
| `is_loop(st)` | for/while/do |
| `is_jump(st)` | return/break/continue |
| `is_import(st)` | Import/require/use |
| `is_comment(st)` | Comments |
| `is_literal(st)` | Any literal value |
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