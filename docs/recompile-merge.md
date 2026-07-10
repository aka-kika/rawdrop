<!--
Recompile merge — implemented hybrid (F) plus backlog for B/E/settings.
-->

# Recompile merge strategy

**Status:** hybrid **implemented** (0.3.1+) · **Related:** `CompileService.writeWikiArticle`  
**Updated:** 2026-07-10

## What ships now (recommended hybrid)

1. **Always** merge origin / `sources:` (and refresh Sources footer).
2. **New file** → write with lean YAML + `## Compiled` wrapping model prose.
3. **Preserve** `## Human` and `<!-- rawdrop:protected -->…<!-- /rawdrop:protected -->` blocks.
4. **If body no longer matches the stored body hash** → treat as human-edited: **provenance only** (no prose overwrite).
5. **Else** → refresh **`## Compiled` only** (safe machine recompile).
6. **Not implemented yet:** append-only Updates (B), LLM smart merge (E), Settings policy picker.

### Lean YAML (Obsidian properties)

```yaml
type: note
date: 2026-07-10
status: active
tags: [compiled, topic]
origin: rawdrop
sources:
  - raw/some-capture.md
compiled: 2026-07-10
```

- **One** source list: `sources` as `raw/filename` paths.
- Web URLs live only in the body **`## Sources`** footer (not in properties).
- **No** `source` / `source_path` / `source_url` / `body_hash` in YAML (legacy keys are read once on recompile, then rewritten clean).

### What is body_hash?

Internal fingerprint of `title + ## Human + ## Compiled` so recompile can tell:

| Hash vs current body | Behavior |
|---|---|
| **Match** | Safe machine rewrite of `## Compiled` only; Human stays |
| **Mismatch** | You (or something) edited the body → **provenance only** (sources/origin/footer), prose left alone |

The hash is stored in `~/Library/Application Support/RawDrop/compile-state.json` under `articleBodyHashes`, **not** in the note’s YAML — so Obsidian properties stay calm.

### How to hand-edit safely

Put permanent notes under:

```markdown
## Human

Your notes here — RawDrop will not overwrite this section.
```

Or wrap any block:

```markdown
<!-- rawdrop:protected -->
Keep this paragraph forever.
<!-- /rawdrop:protected -->
```

If you edit `## Compiled` (or a legacy freeform body) after a compile, the next Compile
detects a hash mismatch and only updates origin/sources.

## Problem (background)

Without a merge policy, recompile **rewrote the entire body**, destroying hand edits
and clobbering multi-source concept pages.

Messy YAML also stacked three source-ish fields (`source`, `source_path`, `source_url`) plus a machine `body_hash` into every note’s properties.

## Options map

| | Strategy | Status |
|---|---|---|
| **A** | Full body replace | Superseded by hybrid |
| **B** | Append `## Update — date` | **Future** |
| **C** | Protect Human / markers | **Shipped** (part of hybrid) |
| **D** | Skip body if human-touched | **Shipped** via internal body hash |
| **E** | LLM merge old + new | **Future** (Settings toggle) |
| **F** | Hybrid C+D+Compiled refresh | **Shipped** |

## Future features (explicit)

- Append-only update sections (B)
- LLM smart merge (E)
- Settings: recompile policy picker (Replace Compiled / Append / Skip if edited / Smart merge)
- Unit tests for body hash and Human preservation

## Acceptance (hybrid)

1. First compile → article with lean YAML + `## Compiled`; hash in Application Support.
2. Add `## Human` notes → recompile same source → Human still present; Compiled may refresh.
3. Edit Compiled text by hand → recompile → edit preserved (provenance-only).
4. Two sources, same title → `sources:` lists both as `raw/…`; Human kept.
5. Origin backfill never strips prose.
6. Properties stay free of `body_hash` / triple source fields after rewrite.
