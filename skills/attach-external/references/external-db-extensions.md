# DuckDB External Database Extensions

## Supported Databases & Extensions

| Database | Extension | ATTACH syntax | Install |
|----------|-----------|--------------|---------|
| **PostgreSQL** | `postgres` | `ATTACH 'dbname=mydb user=postgres host=localhost' AS pg (TYPE POSTGRES)` | `INSTALL postgres;` |
| **SQLite** | `sqlite` | `ATTACH 'path/to/db.sqlite' AS sq (TYPE SQLITE)` | `INSTALL sqlite;` |
| **MySQL** | `mysql` | `ATTACH 'host=localhost user=root port=3306 database=mydb' AS my (TYPE MYSQL)` | `INSTALL mysql;` |

## Connection String Formats

### PostgreSQL
```
dbname=<db> user=<user> host=<host> port=<port> password=<pass>
```
Or standard URI: `postgresql://user:pass@host:port/dbname`

Supports: read/write, transactions, schema filtering.

### SQLite
```
path/to/database.sqlite
```
Or `:memory:` for in-memory SQLite.

Supports: read/write, full table scanning, index usage.

### MySQL
```
host=<host> user=<user> port=<port> database=<db> password=<pass>
```

Supports: read-only by default, table scanning.

## Common Operations After Attach

```sql
-- List all tables in the attached database
SELECT * FROM duckdb_tables() WHERE database_name = '<alias>';

-- Query directly
SELECT * FROM <alias>.<schema>.<table> LIMIT 10;

-- Copy a remote table into local DuckDB for fast querying
CREATE TABLE local_copy AS SELECT * FROM <alias>.<table>;

-- Detach when done
DETACH <alias>;
```

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Extension "postgres" not loaded` | Extension not installed | `INSTALL postgres; LOAD postgres;` |
| `could not connect to server` | Wrong host/port or server down | Verify connection string, check server status |
| `password authentication failed` | Wrong credentials | Check username/password |
| `SSL connection required` | Server requires SSL | Add `sslmode=require` to connection string |
| `relation "X" does not exist` | Wrong schema | Use `<alias>.<schema>.<table>` fully qualified |
