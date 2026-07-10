# Changelog

Append-only. Newest on top. What shipped — not why (see DECISIONS.md).

## [0.3.8] — 2026-07-10

### Added
- First-run vault seeding: saving a Knowledge root creates `raw/`, `wiki/`, and `outputs/` if missing, plus a `RawDrop.md` explainer at the root — the app works out of the box on a fresh folder
- App icon shown above the title in the README

### Notes
- Seeding is create-if-missing and never overwrites: a distinct `RawDrop.md` name avoids clobbering an existing `README.md`, and an edited `RawDrop.md` is preserved on re-save

## [0.3.7] — 2026-07-10

### Changed
- Wiki YAML is lean: `type` / `date` / `status` / `tags` / `origin` / `sources` (`raw/…` list) / `compiled` only
- Removed properties clutter: no more `source`, `source_path`, `source_url`, or `body_hash` in frontmatter
- Body hash lives in Application Support `compile-state.json` (`articleBodyHashes`) — still powers hybrid recompile
- Web URLs stay in the `## Sources` footer only; legacy source fields migrate on next rewrite
- Marketing version set to **0.3.7** (was stuck at 0.1.0)
- Full docs sync (ARCHITECTURE, status, roadmap, PROJECT, privacy, STATE, TODO, GOALS)
- Dropped unused `PendingCapture` typealias

## [0.3.6] — 2026-07-10

### Added
- README screenshots (light + dark popover)
- MIT LICENSE, CONTRIBUTING.md, docs/PUBLIC-CHECKLIST.md (public-ready, visibility still private)

### Changed
- Default knowledge root is `~/Documents/Knowledge` (set your vault in Settings)
- README oriented for public visitors

## [0.3.5] — 2026-07-10

### Changed
- Compile button sits directly under the drop zone (fixed); capture list is below it
- List shows pending captures first, then compiled items at 50% opacity
- Tighter spacing between button and list

## [0.3.4] — 2026-07-10

### Added
- Pending captures list under the drop zone: all `raw/` files not yet compiled (or changed since last compile); Compile button shows count

## [0.3.3] — 2026-07-10

### Fixed
- Main popover “Ollama ready” line now tracks the real selected model (live `settings.ollamaModel`); model picker saves immediately

## [0.3.2] — 2026-07-10

### Added
- Open at Login toggle in Settings → General (`SMAppService`)

## [0.3.1] — 2026-07-10

### Added
- Hybrid recompile merge: `body_hash` provenance, preserve `## Human` and `<!-- rawdrop:protected -->` blocks, refresh only `## Compiled` when safe
- Future features list in FEATURES.md (append-update, LLM smart merge, policy picker, …)
- Design note still at `docs/recompile-merge.md` (updated status)

### Changed
- Wiki articles write under `## Compiled`; origin backfill never rewrites prose
- New articles include structured Compiled section for future-safe recompiles

## [0.3.0] — 2026-07-10

### Added
- Full project documentation: FEATURES, ARCHITECTURE, DECISIONS, STATE, SECURITY, README overhaul
- Recommended models section in Settings (ranked from installed Ollama models)
- Origin provenance on wiki articles (`source`, `source_path`, `source_url`, `sources`, `compiled`, `origin: rawdrop`)
- `## Sources` footer on compiled articles; origin backfill on compile
- App theme: System / Light / Dark (live update on popover + settings window)
- App icon from send-and-forget icon cropper export
- Clipboard capture while popover open (⌘V): files, URLs, images, HTML, text
- Ollama Cloud endpoint + API key in Keychain
- Model dropdown + Test connectivity + Refresh models
- HTML ingest/extract, paste-link capture path consolidated into drop/paste zone

### Changed
- Default Ollama URL: `http://localhost:11434`
- Cleaner popover: single capture zone (drop or paste), no separate URL field
- Settings via dedicated `NSWindow` (reliable for menu bar accessory apps)
- Index source column shows `raw/…` paths

### Fixed
- Settings window not opening under LSUIElement / accessory policy
- Theme change not applying to main popover (`NSPopover` own appearance)

## [0.2.0] — 2026-07-10

### Added
- Local / Cloud Ollama preset
- Keychain-backed API key
- Paste link + HTML drop
- Connectivity test result UI

## [0.1.0] — 2026-07-10

### Added
- Initial menu bar app: drop → `raw/`, Compile via Ollama → `wiki/` + `_index.md`
- Application Support compile state (content-hash tracking)
- Configurable knowledge root
- Gate GO (`GATE.md`)
