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
Use this both for user questions and to self-heal when you encounter DuckDB
errors in other skills.

Always append `&& echo "===DONE===" || echo "===FAILED==="` to each command.

## Step 1 — Setup and cache validation

### Data source selection

| Index | Remote URL | Cache filename | Versions | Use when |
|-------|-----------|---------------|----------|----------|
| **DuckDB docs + blog** | `https://duckdb.org/data/docs-search.duckdb` | `duckdb-docs.duckdb` | `stable`, `current`, `blog` | Default — any DuckDB question |
| **DuckLake docs** | `https://ducklake.select/data/docs-search.duckdb` | `ducklake-docs.duckdb` | `stable`, `preview` | Query mentions DuckLake |

Both indexes share the same schema:

| Column | Type | Description |
|--------|------|-------------|
| `chunk_id` | `VARCHAR` (PK) | e.g. `stable/sql/functions/numeric#absx` |
| `page_title` | `VARCHAR` | Page title from front matter |
| `section` | `VARCHAR` | Section heading (null for page intros) |
| `breadcrumb` | `VARCHAR` | e.g. `SQL > Functions > Numeric` |
| `url` | `VARCHAR` | URL path with anchor |
| `version` | `VARCHAR` | See table above |
| `text` | `TEXT` | Full markdown of the chunk |

Determine which index to use (`duckdb` or `ducklake`), export `DOCS_TARGET`,
and run the setup block. It auto-installs extensions and refreshes the cache
if older than 2 days.

```bash
export DOCS_TARGET="duckdb"  # or "ducklake"

mkdir -p "$HOME/.duckdb/docs"
if [ "$DOCS_TARGET" = "ducklake" ]; then
    CACHE_FILE="$HOME/.duckdb/docs/ducklake-docs.duckdb"
    REMOTE_URL="https://ducklake.select/data/docs-search.duckdb"
else
    CACHE_FILE="$HOME/.duckdb/docs/duckdb-docs.duckdb"
    REMOTE_URL="https://duckdb.org/data/docs-search.duckdb"
fi

# Check DuckDB is installed
command -v duckdb || { echo "DuckDB not found — delegate to /duckdb-skills:install-duckdb"; echo "===FAILED==="; exit 1; }

# Refresh cache if missing or older than 2 days (POSIX-safe, no stat needed)
if [ ! -f "$CACHE_FILE" ] || [ -n "$(find "$CACHE_FILE" -mmin +2880 2>/dev/null)" ]; then
    echo "Updating cache from $REMOTE_URL..."
    duckdb :memory: -c "
        INSTALL httpfs; LOAD httpfs;
        INSTALL fts; LOAD fts;
        ATTACH '$REMOTE_URL' AS remote (READ_ONLY);
        ATTACH '${CACHE_FILE}.tmp' AS tmp;
        COPY FROM DATABASE remote TO tmp;
    " && mv "${CACHE_FILE}.tmp" "$CACHE_FILE" \
      && echo "===CACHE_UPDATED===" \
      || { echo "===FAILED==="; exit 1; }
else
    echo "===CACHE_FRESH==="
fi
echo "===DONE==="
```

## Step 2 — Extract search terms

If the input is a **natural language question** (e.g. "how do I find the most
frequent value"), extract the key technical terms (nouns, function names, SQL
keywords) to form a compact BM25 query string. Drop stop words.

If the input is already a **function name or technical term** (e.g. `arg_max`,
`GROUP BY ALL`), use it as-is.

### Version selection

- Default → `stable`
- User asks about nightly/current features → `current`
- User asks about a blog post or motivation → `blog`
- DuckLake queries → `stable`
- Unsure → leave `VERSION_FILTER` empty to search all versions

## Step 3 — Search the docs

Export the search query as an environment variable and use `getenv()` to read
it safely inside SQL — this prevents breakage from quotes or special characters.

```bash
export SEARCH_QUERY="<extracted_keywords_here>"
export VERSION_FILTER="stable"  # or "current", "blog", "" for all

duckdb "$CACHE_FILE" -readonly -json -c "
LOAD fts;
SELECT
    chunk_id, page_title, section, breadcrumb, url, version, text,
    fts_main_docs_chunks.match_bm25(chunk_id, getenv('SEARCH_QUERY')) AS score
FROM docs_chunks
WHERE score IS NOT NULL
  AND (getenv('VERSION_FILTER') = '' OR version = getenv('VERSION_FILTER'))
ORDER BY score DESC
LIMIT 5;
" && echo "===DONE===" || echo "===FAILED==="
```

If the user's question could benefit from both docs and blog results, run two
queries or set `VERSION_FILTER=""` to search across all versions.

## Step 4 — Handle errors

- **Extension not installed**: run `duckdb :memory: -c "INSTALL httpfs; INSTALL fts;"` and retry.
- **ATTACH fails / network unreachable**: inform the user and suggest checking connectivity.
- **No results**: broaden the query — drop the least specific term, try a single keyword — then retry Step 3. If still nothing, tell the user and suggest visiting https://duckdb.org/docs or https://ducklake.select/docs directly.

## Step 5 — Synthesize and present

Do NOT output the raw markdown chunks or JSON to the user. Read the search
results silently, then synthesize a concise, direct answer to the user's
original question.

Always include the `url` of the relevant documentation page(s) as citations
at the end of your answer so the user can read more if they want.
