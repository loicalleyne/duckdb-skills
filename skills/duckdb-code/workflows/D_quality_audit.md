# Workflow D: "What's wrong / what needs attention?" (Quality audit)

## D1. Most complex functions (refactoring candidates)

```sql
LOAD sitting_duck;
SELECT name, file_path, cyclomatic, max_depth, lines
FROM ast_function_metrics('<PATTERN>')
WHERE name NOT LIKE 'Test%'
ORDER BY cyclomatic DESC LIMIT 20;
```

## D2. Deeply nested code

```sql
SELECT file_path, name, max_depth, start_line
FROM ast_nesting_analysis('<PATTERN>')
ORDER BY max_depth DESC LIMIT 20;
```

## D3. Dead code (unreferenced functions)

```sql
SELECT name, file_path, start_line, reason
FROM ast_dead_code('<PATTERN>')
WHERE name NOT LIKE 'Test%' AND name NOT LIKE 'Benchmark%'
  AND name NOT LIKE 'Example%'
LIMIT 30;
```

## D4. Control flow hotspots — Files with high branching

```sql
SELECT file_path,
    COUNT(CASE WHEN is_conditional(semantic_type) THEN 1 END) as conditionals,
    COUNT(CASE WHEN is_loop(semantic_type) THEN 1 END) as loops,
    COUNT(CASE WHEN is_jump(semantic_type) THEN 1 END) as jumps
FROM read_ast('<PATTERN>', ignore_errors := true)
GROUP BY file_path HAVING (conditionals + loops) > 10
ORDER BY (conditionals + loops) DESC;
```

## D5. Security audit (most effective for Python, JS, Ruby, PHP)

```sql
SELECT * FROM ast_security_audit('<PATTERN>')
WHERE risk_level = 'high' ORDER BY file_path, start_line;
```
