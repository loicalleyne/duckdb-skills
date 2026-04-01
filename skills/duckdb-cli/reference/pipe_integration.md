# DuckDB CLI: POSIX Pipe Integration

DuckDB reads from `/dev/stdin` and writes to `/dev/stdout`, making it a
first-class participant in Unix pipelines.

## Read from stdin

```bash
cat data.csv | duckdb -c "SELECT * FROM read_csv('/dev/stdin') LIMIT 5" \
    && echo "===DONE===" || echo "===FAILED==="
```

## Write to stdout (COPY)

```bash
duckdb mydb.duckdb -c "COPY (SELECT * FROM t WHERE x > 100) TO '/dev/stdout' WITH (FORMAT csv, HEADER)" \
    | gzip > filtered.csv.gz \
    && echo "===DONE===" || echo "===FAILED==="
```

## Full pipeline: transform in-flight

```bash
curl -sL https://example.com/data.csv \
    | duckdb -c "
        COPY (
            SELECT col1, col2, col1 + col2 AS total
            FROM read_csv('/dev/stdin')
            WHERE col1 > 0
        ) TO '/dev/stdout' WITH (FORMAT parquet)
    " > output.parquet \
    && echo "===DONE===" || echo "===FAILED==="
```

## Post-process with POSIX tools

```bash
# Count matching rows with wc
duckdb mydb.duckdb -csv -noheader -c "FROM big_table WHERE status = 'error'" | wc -l

# Extract a column with cut
duckdb mydb.duckdb -csv -noheader -c "SELECT name, score FROM users ORDER BY score DESC LIMIT 20" \
    | cut -d',' -f1

# Filter with grep, sort with sort
duckdb mydb.duckdb -tabs -noheader -c "FROM logs" | grep 'ERROR' | sort -k2

# Pretty-print JSON with jq
duckdb mydb.duckdb -json -c "FROM config LIMIT 5" | jq '.[0]'

# Stream NDJSON to jq for line-by-line processing
duckdb mydb.duckdb -c ".mode jsonlines" -c "FROM events LIMIT 1000" | jq -c '.event_type'
```

## Combine multiple DuckDB invocations

```bash
# Use process substitution to join two sources
duckdb :memory: -csv -c "
    SELECT a.*, b.label
    FROM read_csv('/dev/fd/3') a
    JOIN read_csv('/dev/fd/4') b ON a.id = b.id
" 3< <(duckdb db1.duckdb -csv -c "FROM users") \
  4< <(duckdb db2.duckdb -csv -c "FROM labels") \
  && echo "===DONE===" || echo "===FAILED==="
```

## Write multiple output formats from one query

```bash
duckdb mydb.duckdb <<'SQL' && echo "===DONE===" || echo "===FAILED==="
.mode csv
.once results.csv
SELECT * FROM summary;
.mode json
.once results.json
SELECT * FROM summary;
SQL
```
