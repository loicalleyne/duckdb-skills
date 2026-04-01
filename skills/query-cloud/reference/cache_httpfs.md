# cache_httpfs Reference

The `cache_httpfs` community extension adds transparent on-disk and in-memory
caching on top of `httpfs`. It caches data blocks, file metadata, glob results,
and file handles — dramatically reducing egress and latency on repeated access.

**Platform support:** macOS and Linux only.

## Install and load

Replaces `LOAD httpfs` — it loads httpfs automatically:

```bash
duckdb :memory: -c "INSTALL cache_httpfs FROM community; LOAD cache_httpfs;" && echo "===DONE===" || echo "===FAILED==="
```

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `cache_httpfs_type` | `on_disk` | `on_disk`, `in_mem`, or `noop` (disables cache) |
| `cache_httpfs_cache_directory` | platform default | Directory for on-disk cache files |
| `cache_httpfs_cache_block_size` | 1 MiB | Block size — smaller reduces read amplification |
| `cache_httpfs_enable_metadata_cache` | `true` | Cache file metadata (size, mtime) |
| `cache_httpfs_enable_glob_cache` | `true` | Cache glob/list results |
| `cache_httpfs_profile_type` | `noop` | Set to `temp` to inspect IO |

## Profiling

```sql
LOAD cache_httpfs;
SET cache_httpfs_type = 'on_disk';
SET cache_httpfs_profile_type = 'temp';
```

## Status and inspection

```sql
FROM cache_httpfs_cache_status_query();        -- cached entries
FROM cache_httpfs_cache_access_info_query();    -- hit/miss stats
SELECT cache_httpfs_get_profile();              -- IO latency profile
SELECT cache_httpfs_get_ondisk_data_cache_size(); -- disk usage
```

## Cache management

Clear all: `SELECT cache_httpfs_clear_cache();`
Clear one file: `SELECT cache_httpfs_clear_cache_for_file('<URL>');`

Disable without unloading:
```sql
SET cache_httpfs_type = 'noop';
SET enable_external_file_cache = true;
```
