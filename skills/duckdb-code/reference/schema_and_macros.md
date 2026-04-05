# Schema & Macros Reference

## Caching strategies

### Default — single project (`code_ast.duckdb` in project root)

Cache file: `<PROJECT_ROOT>/code_ast.duckdb`

Build or rebuild:
```bash
cd "<PROJECT_ROOT>"
duckdb -init /dev/null code_ast.duckdb <<'SQL'
LOAD sitting_duck;
CREATE OR REPLACE TABLE ast AS
SELECT * FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200);
SQL
EXIT_CODE=$?
[ $EXIT_CODE -ne 0 ] && { echo "Cache build failed: $EXIT_CODE" >&2; exit $EXIT_CODE; }
echo "===DONE==="
```

Query (all subsequent steps):
```bash
duckdb -init /dev/null code_ast.duckdb -jsonlines -c "LOAD sitting_duck; <QUERY>;"
```

Invalidate: delete `code_ast.duckdb` and rebuild when source files change.

### Cross-project — `~/.duckdb/code_ast/` registry

Convention: one file per project at `~/.duckdb/code_ast/<project-slug>.duckdb`
where `<project-slug>` is `$(basename "$PROJECT_ROOT")`.

Build cache for a project:
```bash
PROJECT_SLUG="$(basename "$PROJECT_ROOT")"
CACHE_DIR="$HOME/.duckdb/code_ast"
mkdir -p "$CACHE_DIR"
duckdb -init /dev/null "$CACHE_DIR/$PROJECT_SLUG.duckdb" <<'SQL'
LOAD sitting_duck;
CREATE OR REPLACE TABLE ast AS
SELECT * FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200);
SQL
EXIT_CODE=$?
[ $EXIT_CODE -ne 0 ] && { echo "Cache build failed: $EXIT_CODE" >&2; exit $EXIT_CODE; }
echo "===DONE==="
```

List cached projects:
```bash
ls "$HOME/.duckdb/code_ast/"
```

### Cross-project ATTACH query template

```bash
duckdb -init /dev/null :memory: -jsonlines <<'SQL'
LOAD sitting_duck;
ATTACH '/home/<user>/.duckdb/code_ast/proj-a.duckdb' AS proj_a (READ_ONLY);
ATTACH '/home/<user>/.duckdb/code_ast/proj-b.duckdb' AS proj_b (READ_ONLY);

-- Example: find all exported functions across both projects
SELECT 'proj_a' AS project, name, file_path, start_line
FROM proj_a.ast
WHERE is_function_definition(semantic_type)
  AND SUBSTRING(name, 1, 1) = UPPER(SUBSTRING(name, 1, 1))
UNION ALL
SELECT 'proj_b' AS project, name, file_path, start_line
FROM proj_b.ast
WHERE is_function_definition(semantic_type)
  AND SUBSTRING(name, 1, 1) = UPPER(SUBSTRING(name, 1, 1))
ORDER BY project, name;
SQL
EXIT_CODE=$?
[ $EXIT_CODE -ne 0 ] && { echo "Cross-project query failed: $EXIT_CODE" >&2; exit $EXIT_CODE; }
echo "===DONE==="
```

Rules:
- Always open the primary session as `:memory:` when cross-querying to avoid locking any single project file.
- Always `(READ_ONLY)` on ATTACHed project databases — never write to them from a cross-project session.
- Prefix every table reference with the alias: `proj_a.ast`, not just `ast`.
- Use `LOAD sitting_duck;` once in the session; predicates work on attached tables without re-loading.

## Key columns from `read_ast()`

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

## Semantic type predicates (use in WHERE)

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

## Common semantic_type string values

`DEFINITION_FUNCTION`, `DEFINITION_CLASS`, `DEFINITION_VARIABLE`,
`DEFINITION_MODULE`, `EXECUTION_INVOCATION`, `FLOW_CONDITIONAL`, `FLOW_LOOP`,
`TYPE_REFERENCE`, `NAME_IDENTIFIER`, `LITERAL_STRING`, `OPERATOR_ASSIGNMENT`.

## Context levels for `read_ast()`

| Level | What it extracts | Speed |
|---|---|---|
| `'node_types_only'` | Only semantic types (no names, no signatures) | Fastest |
| `'normalized'` | Adds names (no signatures, no parameters) | Medium |
| `'native'` (default) | All extraction including signatures, parameters, modifiers | Full |
