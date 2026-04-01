# Workflow E: Individual Queries (Reference)

Use these standalone when you need a specific answer.

## E1. List all definitions

```sql
LOAD sitting_duck;
SELECT name, definition_type, file_path, start_line, end_line
FROM ast_definitions('<PATTERN>') ORDER BY file_path, start_line;
```

## E2. Import analysis

```sql
SELECT name, peek, file_path, start_line
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE is_import(semantic_type) ORDER BY file_path;
```

## E3. Pattern matching with wildcards (find code structures by example)

```sql
-- __X__ captures a single node as "X"
-- __ matches any single node
-- %__<BODY*>__% matches zero or more children
SELECT captures, file_path, start_line
FROM ast_match('<PATTERN>', '<CODE_PATTERN>', '<LANGUAGE>') LIMIT 20;
```

## E4. Detailed single-file analysis

```sql
SELECT name, type, semantic_type_to_string(semantic_type) as sem_type,
       signature_type, parameters, start_line, end_line, peek
FROM read_ast('<FILE>', peek := 200)
WHERE is_definition(semantic_type) AND name IS NOT NULL
ORDER BY start_line;
```

## E5. Tree navigation (inspect a specific node's subtree)

```sql
WITH base AS (FROM read_ast('<FILE>'))
SELECT * FROM ast_descendants(base, <NODE_ID>);
-- Also: ast_ancestors(base, <NODE_ID>), ast_children(base, <NODE_ID>)
```

## E6. Cross-language analysis

```sql
SELECT language, COUNT(*) as functions
FROM read_ast(['**/*.py', '**/*.js', '**/*.go'], ignore_errors := true)
WHERE is_function_definition(semantic_type)
GROUP BY language ORDER BY functions DESC;
```
