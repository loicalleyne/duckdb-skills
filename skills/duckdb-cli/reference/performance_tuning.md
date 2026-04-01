# DuckDB CLI: Performance & Resource Tuning

## Memory and threads

```sql
SET memory_limit = '4GB';
SET threads = 4;
```

Rule of thumb: **1-4 GB per thread**. Minimum ~125 MB per thread.

## Prefer Parquet over CSV for repeated access

Parquet has columnar layout, zonemaps, and metadata that enable projection and
filter pushdown. Convert once:

```bash
duckdb -c "COPY (FROM read_csv('big.csv')) TO 'big.parquet' (FORMAT parquet)" \
    && echo "===DONE===" || echo "===FAILED==="
```

## Enable compression for in-memory databases

In-memory databases are uncompressed by default. For large datasets this can be
8x slower than compressed:

```bash
duckdb -cmd "ATTACH ':memory:' AS db (COMPRESS); USE db;" -c "..."
```

## Larger-than-memory workloads

DuckDB spills to disk automatically. Ensure `temp_directory` is set to fast
storage (SSD/NVMe):

```sql
SET temp_directory = '/tmp/duckdb_spill.tmp/';
```

For large imports/exports that cause OOM, disable insertion order preservation:

```sql
SET preserve_insertion_order = false;
```

## Remote file queries

When reading over HTTP/S3, DuckDB uses synchronous IO per thread. Increase
threads beyond CPU core count (2-5x) to improve parallelism:

```sql
SET threads = 16;  -- e.g., on an 8-core machine
```

Minimize downloaded data: avoid `SELECT *`, apply filters, prefer partitioned
or sorted Parquet files.

## Profiling slow queries

```bash
duckdb mydb.duckdb -c "EXPLAIN ANALYZE SELECT ..." && echo "===DONE===" || echo "===FAILED==="
```

Look for: nested loop joins, missing filter pushdown, cardinality explosions.
