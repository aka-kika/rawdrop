# RawDrop

macOS **menu bar** app that feeds and compiles a personal [Karpathy-style LLM knowledge base](https://x.com/karpathy/status/2039805659525644595) living in Obsidian.

**Drop** anything into `Knowledge/raw/`. **Compile** turns new sources into wiki concept articles with a local (or cloud) Ollama model.

<p align="center">
  <img src="docs/screenshots/popover-light.png" alt="RawDrop popover — light mode" width="320" />
  &nbsp;
  <img src="docs/screenshots/popover-dark.png" alt="RawDrop popover — dark mode" width="320" />
</p>

<p align="center"><em>Light and dark — capture list under Compile; pending full opacity, compiled dimmed.</em></p>

| | |
|---|---|
| **Platform** | macOS 14+ (menu bar only, no Dock icon) |
| **Stack** | Swift · SwiftUI · AppKit · Ollama HTTP API |
| **License** | MIT |
| **Repo** | https://github.com/aka-kika/rawdrop |

## Download

**[⬇︎ Download RawDrop 0.3.7 (.dmg)](https://github.com/aka-kika/rawdrop/releases/latest)** — universal (Apple Silicon + Intel), signed and notarized by Apple.

Open the DMG, drag **RawDrop** to **Applications**, and launch it. It lives in the menu bar (no Dock icon). Requires macOS 14+. [Ollama](https://ollama.com) is needed for Compile.

## How it started

RawDrop follows the **LLM knowledge base** pattern Andrej Karpathy described: raw sources in, an LLM compiles a wiki, and the wiki compounds over time.

**[How it started — Karpathy on X](https://x.com/karpathy/status/2039805659525644595)**

This app is the capture + compile surface for that loop (menu bar drop/paste into `raw/`, one Compile button into `wiki/`).

---

## What it does

Two jobs, nothing more:

1. **Capture (drop / paste)**  
   Files, HTML, images, URLs → **copied** into `Knowledge/raw/` (never moved, never overwritten — collisions get ` 2`, ` 3`, …).  
   While the popover is open, **⌘V** captures the clipboard.  
   The list under Compile shows pending sources first, then already-compiled items (dimmed).

2. **Compile**  
   One button. For every raw file not yet processed (by content hash): chunk → summarize via Ollama `/api/chat` → write concept articles under `Knowledge/wiki/` with origin frontmatter → update `wiki/_index.md`.  
   Process state lives in `~/Library/Application Support/RawDrop/` — **not** in the vault.

---

## Hard rules (vault law)

- App writes only under `Knowledge/raw/` (on drop), `Knowledge/wiki/`, and optionally `Knowledge/outputs/`.
- Never edit or delete anything in `raw/` after it lands.
- Wiki articles: lean YAML (`type`, `date`, `status`, `tags`, `origin`, `sources` as `raw/…` paths, `compiled`), plain text, `[[wikilinks]]`, no emojis. URLs live in the `## Sources` footer. Recompile safety hash is internal (Application Support), not properties clutter.
- Hand-edit under `## Human` or `<!-- rawdrop:protected -->` so recompile will not overwrite your notes.
- No cloud LLM unless you configure Ollama Cloud + API key (Keychain).

---

## Features

See **[FEATURES.md](./FEATURES.md)** for the full list. Highlights:

- Menu bar popover: drop zone, ⌘V capture, Compile, capture list, Settings / Quit  
- Settings: vault path, Local / Cloud Ollama, API key (Keychain), model dropdown, **recommended models**, test connectivity, **Open at Login**, **System / Light / Dark** theme  
- HTML extraction, PDF text (PDFKit), image paste as PNG, URL fetch → markdown  
- Origin provenance + hybrid recompile merge on every compiled wiki article  

---

## Build & run

```bash
git clone https://github.com/aka-kika/rawdrop.git
cd rawdrop
xcodegen generate
xcodebuild -scheme RawDrop -configuration Debug -derivedDataPath ./DerivedData build
open ./DerivedData/Build/Products/Debug/RawDrop.app
```

Or open `RawDrop.xcodeproj` in Xcode and Run.

**Requirements:** macOS 14+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), [Ollama](https://ollama.com) for Compile.

After first launch, open **Settings…** and set **Knowledge root** to a folder that contains (or will contain) `raw/`, `wiki/`, and `outputs/`.

---

## Defaults

| Setting | Default |
|---|---|
| Knowledge root | `~/Documents/Knowledge` (change in Settings) |
| Ollama base URL | `http://localhost:11434` |
| Model | `ministral-3:latest` (change in Settings) |
| Theme | System |
| Open at Login | Off (Settings → General) |
| Cloud | `https://ollama.com` + Keychain API key |

---

## Project docs

| Doc | Purpose |
|---|---|
| [FEATURES.md](./FEATURES.md) | Feature inventory |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Layout and data flow |
| [CHANGELOG.md](./CHANGELOG.md) | What shipped |
| [DECISIONS.md](./DECISIONS.md) | Why we chose X over Y |
| [docs/environment.md](./docs/environment.md) | Dev setup |
| [docs/privacy.md](./docs/privacy.md) | Privacy & permissions |
| [docs/roadmap.md](./docs/roadmap.md) | Now / Next / Later |
| [SECURITY.md](./SECURITY.md) | Secrets and network rules |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | How to contribute |

---

## License

[MIT](./LICENSE) — free to use, modify, and share.
