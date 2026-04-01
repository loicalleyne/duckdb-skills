# DuckDB CLI Quick Reference

## CLI Flags

| Flag                  | Description                                    |
|-----------------------|------------------------------------------------|
| `-c COMMAND`          | Execute SQL and exit                           |
| `-f FILENAME`         | Execute script file and exit                   |
| `-init FILENAME`      | Run init script (replaces `~/.duckdbrc`)       |
| `-csv`                | CSV output mode                                |
| `-json`               | JSON array output mode                         |
| `-jsonlines`          | Newline-delimited JSON output                  |
| `-line`               | One key=value per line                         |
| `-list`               | Pipe-delimited output                          |
| `-tabs`               | Tab-separated output                           |
| `-box`                | Unicode box-drawing table                      |
| `-table`              | ASCII-art table                                |
| `-markdown`           | Markdown table                                 |
| `-noheader`           | Suppress column headers                        |
| `-separator SEP`      | Custom column separator                        |
| `-nullvalue TEXT`      | Custom NULL display text                       |
| `-readonly`           | Open database in read-only mode                |
| `-bail`               | Stop on first error                            |
| `-batch`              | Force batch (non-interactive) I/O              |
| `-echo`               | Print SQL before execution                     |
| `-no-stdin`           | Exit after processing options                  |
| `-unsigned`           | Allow unsigned extensions (dev only)           |

## DuckDB Friendly SQL Shortcuts (for concise CLI usage)

These reduce the amount of SQL you type in one-liners:

| Shortcut                                   | Instead of                                    |
|--------------------------------------------|-----------------------------------------------|
| `FROM table`                               | `SELECT * FROM table`                         |
| `FROM 'file.csv'`                          | `SELECT * FROM read_csv('file.csv')`          |
| `FROM 'file.parquet'`                      | `SELECT * FROM read_parquet('file.parquet')`  |
| `GROUP BY ALL`                             | Listing all non-aggregate columns             |
| `ORDER BY ALL`                             | Listing all columns in ORDER BY               |
| `SELECT * EXCLUDE (col)`                   | Listing all columns except `col`              |
| `SELECT * REPLACE (expr AS col)`           | Overriding one column in a wildcard           |
| `DESCRIBE table_name`                      | Column names and types                        |
| `SUMMARIZE table_name`                     | Statistical profile of every column           |
| `count()`                                  | `count(*)`                                    |
| `LIMIT 10%`                               | Percentage-based limit                        |
