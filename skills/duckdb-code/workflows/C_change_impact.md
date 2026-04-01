# Workflow C: "Where do I make this change?" (Change location & Interfaces)

## C1. Search by concept — Find definitions related to a concept using name + peek

```sql
LOAD sitting_duck;
SELECT file_path, name, type, start_line, end_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 150)
WHERE is_definition(semantic_type) AND name IS NOT NULL
  AND file_path NOT LIKE '%_test.go'
  AND (name ILIKE '%<CONCEPT>%' OR peek ILIKE '%<CONCEPT>%')
ORDER BY file_path, start_line;
```

## C2. Find error handling for a subsystem — Locate where errors are created/wrapped

```sql
SELECT file_path, name, start_line, peek
FROM read_ast('<PATTERN>', ignore_errors := true, peek := 200)
WHERE is_function_call(semantic_type)
  AND name IN ('Errorf', 'Wrap', 'Wrapf', 'New', 'Error')
  AND peek ILIKE '%<KEYWORD>%'
ORDER BY file_path, start_line;
```

## C3. Find methods on a type — What operations does type T support?

```sql
SELECT name as method, signature_type as returns, parameters, file_path, start_line,
       (end_line - start_line) as lines
FROM read_ast('<PATTERN>', ignore_errors := true)
WHERE type = 'method_declaration' AND name IS NOT NULL
  AND parameters[1].name LIKE '%<TYPE_NAME>%'
ORDER BY file_path, start_line;
```

## C4. Find similar patterns — Look for code that does something similar to what you want

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

## C5. "What implements this interface?" (Go interface resolution)

AST analysis can map method sets and match interfaces to types. It works best for **interfaces
defined in the same codebase**. For external interfaces (e.g. `io.Reader`, `driver.Conn`), you
already know their required methods — use that knowledge to find implementors by method name.

**Limitation**: sitting_duck parses syntax, not types. It cannot resolve cross-package interfaces
automatically. But it *can* find all the evidence you need to answer the question.

### C5a. Find all local interfaces and their required methods

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

### C5b. Map all receiver types and their method sets

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

### C5c. Find types implementing a known interface (external or local)

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

### C5d. Find type assertions — Where does code assert an interface?

```sql
SELECT file_path, name, start_line, peek
FROM ast
WHERE type = 'type_assertion_expression'
ORDER BY file_path, start_line;
```

After running these, summarize: "Type [X] implements [Interface] — it has methods [A, B, C]
defined in [file]. Type assertions for this interface appear at [locations]."
