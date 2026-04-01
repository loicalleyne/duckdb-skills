# DuckDB CLI: Robustness Patterns

## Bail on first error

```bash
duckdb mydb.duckdb -bail <<'SQL' && echo "===DONE===" || echo "===FAILED==="
CREATE TABLE t1 AS SELECT 1 AS id;
CREATE TABLE t2 AS SELECT * FROM nonexistent_table;  -- stops here
INSERT INTO t1 VALUES (2);  -- never reached
SQL
```

## Timeout long-running commands

```bash
timeout 60 duckdb mydb.duckdb -c "SELECT * FROM huge_table" \
    && echo "===DONE===" || echo "===FAILED==="
```

## Read-only mode for safety

```bash
duckdb -readonly mydb.duckdb -csv -c "FROM analytics LIMIT 100" \
    && echo "===DONE===" || echo "===FAILED==="
```

## Skip ~/.duckdbrc for reproducible results

```bash
duckdb -init /dev/null :memory: -c "SELECT 1" && echo "===DONE===" || echo "===FAILED==="
```

## Capture exit code

```bash
if duckdb mydb.duckdb -c "SELECT count() FROM my_table;"; then
    echo "Query succeeded"
else
    echo "Query failed with exit code $?"
fi
```

## Probe before running large queries

```bash
ROW_COUNT=$(duckdb mydb.duckdb -csv -noheader -c "SELECT count() FROM big_table;")
if [[ "$ROW_COUNT" -gt 1000000 ]]; then
    echo "Large table ($ROW_COUNT rows) — adding LIMIT"
fi
```

## Sandboxing ad-hoc file queries

```bash
duckdb :memory: -csv <<'SQL' && echo "===DONE===" || echo "===FAILED==="
SET allowed_paths = ['./data/input.csv'];
SET enable_external_access = false;
SET allow_persistent_secrets = false;
SET lock_configuration = true;
SELECT * FROM read_csv('./data/input.csv') LIMIT 10;
SQL
```
