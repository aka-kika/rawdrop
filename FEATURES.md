# Features

Inventory of what RawDrop does today. Keep this in sync with releases.

## Capture

| Feature | Detail |
|---|---|
| Drop on menu bar icon | Files and URLs via status-item overlay |
| Drop in popover | Files, HTML, images, plain text, URLs |
| Paste while open (⌘V) | Clipboard: files, URLs, images (PNG), HTML, plain text notes |
| URL fetch | HTTP(S) → clean-ish markdown into `raw/` with `source_url` frontmatter |
| HTML files | Copied as-is; convert to text only at compile |
| PDF | Text extraction via PDFKit at compile |
| Images | Stored as files; compile notes filename/context |
| Collision-safe copy | Never overwrites; suffix ` 2`, ` 3`, … |
| Never moves sources | Originals always untouched |
| Capture list under Compile | Pending (full opacity) then compiled (dimmed); count on Compile button |

## Compile

| Feature | Detail |
|---|---|
| Single Compile button | Processes only new / changed raw files (SHA-256) |
| Ollama `/api/chat` | Local or cloud endpoint |
| Chunking | Long docs split before model calls |
| Concept articles | 1–3 articles per source (model-driven) |
| Wiki index | `wiki/_index.md` topics + raw sources table |
| Origin YAML | Lean properties: `origin`, `sources` (`raw/…` list), `compiled` — no `source` / `source_path` / `source_url` / `body_hash` in YAML |
| Sources section | Footer on each article: `raw/…` paths and optional source URLs |
| Origin backfill | Compile with nothing new still refreshes provenance only (never prose) |
| Hybrid recompile merge | Keep `## Human` / protected blocks; skip body if human-edited (internal body hash); else refresh `## Compiled` only |
| Progress UI | In-popover status + macOS notification on finish |
| Ollama down | Clear error, no crash, no partial silent writes of half-pass |

## Settings

| Feature | Detail |
|---|---|
| Knowledge root path | Configurable vault root (raw/wiki/outputs under it) |
| Endpoint | Local Ollama ↔ Ollama Cloud |
| Base URL | Default `http://localhost:11434` / `https://ollama.com` |
| API key | Cloud; stored in **Keychain** only |
| Model dropdown | Full list from `GET /api/tags` |
| Recommended models | Ranked subset of *installed* models for wiki work |
| Use top pick | One-click best recommendation |
| Refresh models | Reload tags |
| Test connectivity | Latency, model count, clear OK/fail |
| Theme | System / Light / Dark (live, popover + settings) |
| Open at Login | SMAppService toggle in Settings → General |
| Dedicated settings window | Works for LSUIElement menu bar apps |

## Shell / chrome

| Feature | Detail |
|---|---|
| Menu bar only | `LSUIElement`, activation policy accessory |
| Popover | Drop/paste zone, Compile, recent, Settings, Quit |
| App icon | Full macOS asset catalog + icns |
| Menu bar glyph | SF Symbol template (`tray.and.arrow.down`) |
| No sandbox | Needs filesystem access to vault path |

## Future features

| Feature | Notes |
|---|---|
| **Wiki chat popup** | Popup chat window to talk to the Knowledge wiki with the selected Ollama model (read `wiki/` + `_index.md`, answers with `[[wikilinks]]`; optional save to `outputs/`) |
| Append-only `## Update — date` sections | Option B — grow history instead of replacing Compiled |
| LLM smart merge | Option E — model merges old body + new synthesis (Settings toggle) |
| Settings: recompile policy picker | Replace Compiled / Append / Skip if edited / Smart merge |
| Menu bar brand mark | Template glyph from app icon |
| Install to `/Applications` | Script or simple package |
| Compile cancel | Abort long Ollama runs |
| Share extension | “Send to RawDrop” from other apps |
| Unit tests | Ingest collision, lean origin frontmatter, body hash / Human preservation |
| Open last article / Reveal raw | Popover quick links |

## Explicit non-goals (v0.x core loop)

Keep the two-job core (drop + compile). Wiki chat is a **future feature**, not a non-goal forever.

- Full agent/RAG platform (beyond a simple chat popup)
- Lint / health pass  
- Cloud providers other than Ollama-compatible  
- Editing or deleting `raw/`  
- Multi-vault simultaneous compile  
- Electron / server  
- Always-on global clipboard sniffer  
