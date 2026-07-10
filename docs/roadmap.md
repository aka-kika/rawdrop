<!--
Roadmap — Now / Next / Later
-->

# RawDrop — Roadmap

**Updated:** 2026-07-10 · **Current version:** 0.3.7

> Now = building it · Next = committed, not started · Later = directional, may change

## Now

<!-- SF Symbol: circle.fill -->
- **Daily soak** — prove the drop+compile loop sticks without friction.

## Next

<!-- SF Symbol: circle.lefthalf.filled -->
- **Install convenience** — `/Applications` copy or simple install script (Open at Login works best from Applications).
- **Menu bar brand mark** — template glyph derived from app icon.

## Later

<!-- SF Symbol: circle -->
- **Wiki chat popup** — talk to the compiled wiki with the selected Ollama model (popup window; index + article context; optional `outputs/` save).
- **Append-update recompile mode** — `## Update — date` history instead of Compiled replace.
- **LLM smart merge** — model merges old article + new synthesis (Settings toggle).
- **Recompile policy in Settings** — pick Replace Compiled / Append / Skip if edited / Smart merge.
- **Tests** — ingest collision, lean origin frontmatter, body hash / Human preservation.
- **Share extension** — Send to RawDrop from other apps.
- **Compile cancel** — abort long Ollama runs.

## Recently shipped

<!-- SF Symbol: checkmark.circle -->
- **0.3.7** — lean wiki YAML (`sources` as `raw/…`); body hash in Application Support; no triple source_* properties.
- **0.3.6** — screenshots, LICENSE, CONTRIBUTING, public-ready docs; default Knowledge path generic.
- **0.3.5** — Compile button above capture list; compiled items dimmed.
- **0.3.4** — pending captures list + count on Compile.
- **0.3.3** — popover model line tracks real selection.
- **0.3.2** — Open at Login in Settings.
- **0.3.1** — hybrid recompile merge (Human / body hash / Compiled-only refresh).
- **0.3.0** — origin YAML, theme, recommended models, icon, private GitHub, full docs.
- **0.2.0** — cloud Ollama, paste/HTML, connectivity test.
- **0.1.0** — core drop + compile.

## Considering / not doing

<!-- SF Symbol: tray -->
- Always-on clipboard capture — too invasive.
- Full in-app Q&A platform — agents already use the wiki; keep RawDrop two-jobs-only (chat popup is the only planned exception).
