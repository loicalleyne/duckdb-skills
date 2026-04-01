# Workflow G: LLM-specific workflows (Accelerating coding tasks)

These workflows integrate AST analysis into the LLM's coding process — use them
*before*, *during*, and *after* writing code.

## G1. Context window priming — Build a skeletal map in minimal tokens

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

## G2. Impact analysis — Before editing, find everything that depends on it

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

## G3. Test coverage gap detection — Find exported functions without tests

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

## G4. Pre-write pattern discovery — Find similar existing patterns before writing new code

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

## G5. Targeted file reading — Use AST results to decide exactly which files and lines to read

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

## G6. Error handling consistency — Find how errors are created throughout the codebase

```sql
SELECT file_path, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE semantic_type = 'EXECUTION_INVOCATION'
AND name IN ('Errorf', 'Wrapf', 'Wrap', 'New', 'Newf', 'WithStack')
ORDER BY file_path, start_line;
```

Use this to maintain consistent error handling style when writing new code.

## G7. Post-edit validation with `parse_ast()` — After generating code, verify its structure

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
