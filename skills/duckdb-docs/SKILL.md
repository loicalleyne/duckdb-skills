---
name: duckdb-docs
description: >
  Search DuckDB and DuckLake documentation and blog posts using a local FTS index.
  USE THIS SKILL when: the user asks a question about DuckDB/DuckLake features,
  functions, or syntax.
  USE THIS SKILL when: you encounter a DuckDB SQL error or execution failure in
  another skill and need to look up the correct syntax or error cause.
  DO NOT USE THIS SKILL to search the user's local source code.
argument-hint: <question or keyword>
allowed-tools:
  - Bash
  - run_in_terminal
---

Search DuckDB or DuckLake documentation via a locally cached full-text index.
Use for user questions and to self-heal on DuckDB errors in other skills.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Step 1 — Setup and cache validation

| Index | Cache filename | Use when |
|-------|---------------|----------|
| DuckDB docs + blog | `duckdb-docs.duckdb` | Default — any DuckDB question |
| DuckLake docs | `ducklake-docs.duckdb` | Query mentions DuckLake |

Schema: `chunk_id` (PK), `page_title`, `section`, `breadcrumb`, `url`, `version`, `text`.

```bash
export DOCS_TARGET="duckdb"  # or "ducklake"
bash ./scripts/refresh_cache.sh
```

## Step 2 — Extract search terms

- Natural language → extract key technical terms, drop stop words.
- Function name or keyword → use as-is.

Version selection: `stable` (default), `current` (nightly), `blog` (posts),
or empty string for all.

## Step 3 — Search

```bash
export SEARCH_QUERY="<extracted_keywords>"
export VERSION_FILTER="stable"  # or "current", "blog", ""
bash ./scripts/search_docs.sh
```

For both docs and blog results, run twice or set `VERSION_FILTER=""`.

## Step 4 — Handle errors

- **Extension not installed:** `duckdb :memory: -c "INSTALL httpfs; INSTALL fts;"` and retry.
- **ATTACH fails / network unreachable:** inform user, check connectivity.
- **No results:** broaden query (drop least specific term), retry. If still
  nothing, suggest https://duckdb.org/docs or https://ducklake.select/docs.

## Step 5 — Synthesize and present

Do NOT output raw chunks or JSON. Synthesize a concise answer. Always cite
the `url` of relevant documentation pages.
