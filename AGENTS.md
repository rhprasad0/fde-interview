# Purpose

Research wiki, and later design notes, for a forward-deployed engineering (FDE)
interview project. The wiki follows Andrej Karpathy's
[LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
pattern: Ryan curates sources and asks questions; the agent writes and maintains
everything in `wiki/`.

# Public repo: keep the company name out

This repo is public. **Never write the hiring company's name** in a tracked
file, commit message, branch name, or PR/issue text. Call it **the Firm**.

- The name and any other terms to keep out live in the gitignored
  `.forbidden-terms` file, one per line, no blank lines.
- `.githooks/pre-commit` and `.githooks/commit-msg` block commits that add one.
  After a fresh clone: `git config core.hooksPath .githooks` and recreate
  `.forbidden-terms`.
- If a source's title or URL contains the name, cite it by its `raw/` path only.

# Layout

- `raw/`: source documents. **Gitignored**, so third-party and confidential
  material stays local. Immutable: read, never edit. Name files
  `YYYY-MM-DD-short-slug.<ext>`.
- `wiki/`: agent-owned markdown, committed.
  - `index.md`: catalog of every page with a one-line summary, by category.
  - `log.md`: append-only timeline of ingests, queries, and lint passes.
  - `synthesis.md`: the evolving thesis and open research questions. Create it
    on the first ingest.
  - `sources/`: one summary page per ingested source.
  - `entities/`: people, orgs, products, systems.
  - `concepts/`: ideas, patterns, techniques.
  - `analyses/`: query answers worth keeping (comparisons, trade-offs, decisions).
- `AGENTS.md`: this schema. Update it with Ryan when a convention changes.

# Page conventions

- File names: lowercase kebab-case, e.g. `wiki/concepts/forward-deployed-engineering.md`.
- Links: relative markdown links (`[FDE](../concepts/forward-deployed-engineering.md)`),
  not `[[wikilinks]]`, so they render on GitHub.
- Cite every non-obvious claim inline with a link to its source page.
- When sources disagree, say so on the page ("Conflicts with [x](...)") instead
  of silently overwriting the older claim.

# Operations

**Ingest** (one source at a time unless Ryan asks for a batch)

1. Read the source in `raw/`. For images, read the text first, then view them.
2. Discuss the key takeaways with Ryan before writing.
3. Write `wiki/sources/<slug>.md`: citation (title, author, date, URL),
   summary, key claims, open questions.
4. Create or update the entity and concept pages it touches.
5. Update `synthesis.md` and `index.md`, then append to `log.md`.

**Query**

1. Read `index.md` first, then the relevant pages. Go to `raw/` only when the
   wiki lacks the detail.
2. Answer with citations to wiki pages.
3. Offer to file substantial answers in `wiki/analyses/`, then index and log them.

**Lint** (when asked)

- Look for contradictions, superseded claims, orphan pages, concepts mentioned
  without a page, missing cross-links, broken links, and gaps worth a web search.
- Run `git grep -iFf .forbidden-terms`; it must print nothing.
- Fix the mechanical problems, report the rest with suggested next questions and
  sources, and log the pass.

# Log format

Each entry starts with `## [YYYY-MM-DD] <op> | <title>`, followed
by a line or two. `grep "^## \[" wiki/log.md | tail -5` shows recent activity.
