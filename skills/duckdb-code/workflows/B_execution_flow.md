# Workflow B: "How does X work?" (Execution flow tracing)

To trace how a feature/function works, chain these queries.

## B1. Find the function definition

```sql
LOAD sitting_duck;
SELECT name, file_path, start_line, end_line, parameters, signature_type, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200)
WHERE is_function_definition(semantic_type) AND name = '<FUNCTION_NAME>'
  AND file_path NOT LIKE '%_test.go';
```

## B2. What does it call? (outgoing calls from a function)

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

## B3. What calls it? (incoming calls — find all callers across the codebase)

```sql
SELECT file_path, name as call_site, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE is_function_call(semantic_type) AND name = '<FUNCTION_NAME>'
  AND file_path NOT LIKE '%_test.go'
ORDER BY file_path, start_line;
```

## B4. Build a call graph and trace N-level execution flow (multi-step chain)

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
