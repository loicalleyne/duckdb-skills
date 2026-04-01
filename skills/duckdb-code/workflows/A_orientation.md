# Workflow A: "Help me understand this codebase" (Orientation)

Run these in sequence to build a mental model.

## A1. Inventory — What languages, how big, how many files?

```sql
LOAD sitting_duck;
SELECT language, COUNT(DISTINCT file_path) as files, COUNT(*) as nodes,
       COUNT(CASE WHEN is_function_definition(semantic_type) THEN 1 END) as functions,
       COUNT(CASE WHEN is_class_definition(semantic_type) THEN 1 END) as types
FROM read_ast('<PATTERN>', ignore_errors := true)
GROUP BY language ORDER BY nodes DESC;
```

## A2. File map — Which files have the most logic?

```sql
SELECT file_path, COUNT(CASE WHEN is_function_definition(semantic_type) THEN 1 END) as functions,
       COUNT(CASE WHEN is_function_call(semantic_type) THEN 1 END) as calls,
       MAX(depth) as max_depth
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE file_path NOT LIKE '%_test.go' AND file_path NOT LIKE '%test_%'
GROUP BY file_path ORDER BY functions DESC;
```

## A3. Public API — What are the entry points / exported functions?

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

## A4. Types and structures — What are the key data types?

```sql
-- Go: named types (struct, interface)
SELECT name, type, file_path, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE type = 'type_spec' AND name IS NOT NULL
  AND file_path NOT LIKE '%_test.go'
ORDER BY file_path, start_line;
```

## A5. Dependencies — What external packages are used?

```sql
SELECT file_path, name as import_path
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE is_import(semantic_type) AND name IS NOT NULL
  AND name LIKE '%/%'
ORDER BY file_path;
```

After these queries, summarize: "This is a [size] [language] project with [N] files.
The core logic lives in [files]. Key types are [X, Y, Z]. It depends on [packages]."
