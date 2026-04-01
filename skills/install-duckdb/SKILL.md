---
name: install-duckdb
description: >
  Install or update DuckDB extensions. Each argument is either a plain
  extension name (installs from core) or name@repo (e.g. magic@community).
  Pass --update to update extensions instead of installing.
argument-hint: "[--update] [ext1 ext2@repo ext3 ...]"
allowed-tools:
  - Bash
  - run_in_terminal
---

Arguments: `$@`

Extension argument format: `name` → `INSTALL name;`, `name@repo` → `INSTALL name FROM repo;`

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Step 1 — Locate DuckDB

```bash
DUCKDB=$(command -v duckdb)
```

If not found:
> **DuckDB is not installed.** Install with:
> - macOS: `brew install duckdb`
> - Linux: `curl -fsSL https://install.duckdb.org | sh`
> - Windows: `winget install DuckDB.cli`

Stop if not found.

## Step 2 — Install or update

If `--update` in `$@` → **update mode**. Otherwise → **install mode**.

**Install mode:** Parse each arg, build statements, run in one call:
```bash
"$DUCKDB" :memory: -c "INSTALL <ext1>; INSTALL <ext2> FROM <repo2>; ..." && echo "===DONE===" || echo "===FAILED==="
```

**Update mode:**

Check CLI version:
```bash
CURRENT=$(duckdb --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
LATEST=$(curl -fsSL https://duckdb.org/data/latest_stable_version.txt)
```

If outdated, ask user to upgrade (brew/curl/winget per platform).

Then update extensions:
```bash
"$DUCKDB" :memory: -c "UPDATE EXTENSIONS;" && echo "===DONE===" || echo "===FAILED==="
# or with specific extensions:
"$DUCKDB" :memory: -c "UPDATE EXTENSIONS (<ext1>, <ext2>);" && echo "===DONE===" || echo "===FAILED==="
```

Report success or failure.
