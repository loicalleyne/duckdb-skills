# Schema & Macros Reference

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
