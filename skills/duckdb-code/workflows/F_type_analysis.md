# Workflow F: "What types does this code use?" (Type analysis)

AST analysis captures rich type information: struct fields, function signatures, type references,
composition, and external dependency types. Use multi-step chaining to build a complete type picture.

## F1. Complete struct field type map — What fields does each struct have and what types are they?

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

## F2. Full function signature database — Every function with typed params and return types

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

## F3. Type flow trace — Where is a specific type defined, referenced, and used?

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

## F4. External dependency type map — Which external packages/types are used where?

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

## F5. Type composition graph — How types reference each other

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
