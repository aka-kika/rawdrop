<!--
Environment Setup — zero to running.
-->

<!-- SF Symbol: macbook.and.iphone -->
# Environment Setup

Project: RawDrop · **v0.3.7**  
Last tested on: macOS 15/27-series host — 2026-07-10

---

<!-- SF Symbol: gearshape -->
## Prerequisites

- Xcode 15+ (or current Xcode beta with macOS SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Ollama (optional for UI; **required** for Compile) at `http://localhost:11434`
- Write access to a Knowledge folder with `raw/`, `wiki/`, `outputs/` (default `~/Documents/Knowledge` — set in Settings)

---

<!-- SF Symbol: arrow.down.to.line.compact -->
## Installation

```bash
git clone https://github.com/aka-kika/rawdrop.git
cd rawdrop
```

---

<!-- SF Symbol: hammer -->
## Build

```bash
xcodegen generate
xcodebuild -scheme RawDrop -configuration Debug -derivedDataPath ./DerivedData build
```

---

<!-- SF Symbol: play -->
## Run

```bash
open ./DerivedData/Build/Products/Debug/RawDrop.app
```

Or open `RawDrop.xcodeproj` in Xcode and Run.

---

<!-- SF Symbol: checkmark.circle -->
## Verify it works

1. Tray icon appears (no Dock icon).
2. Open popover → Settings → Test connectivity (Ollama running).
3. Drop a `.md` or paste a URL → file appears under `Knowledge/raw/`.
4. Compile → new/updated files under `Knowledge/wiki/` and `_index.md` (lean YAML properties; body hashes in Application Support).

---

<!-- SF Symbol: key -->
## Secrets / Config

- **Ollama Cloud API key** (optional): Settings → stored in Keychain (`com.akakika.RawDrop` / `ollama.apiKey`)
- **Knowledge root**: Settings (UserDefaults `rawdrop.settings`)
- **Open at Login**: Settings → General (macOS Login Items via `SMAppService`; prefer app in `/Applications`)
- No `.env` file required

---

<!-- SF Symbol: bug -->
## Troubleshooting

| Symptom | Fix |
|---|---|
| Settings does nothing | Use popover **Settings…** (dedicated window); rebuild if old binary |
| Theme doesn't change popover | Need build with `NSPopover.appearance` fix (0.3+) |
| Compile says Ollama not running | Start Ollama; check Base URL `http://localhost:11434` |
| Model missing | Refresh models; pick from Recommended or pull model |
| Can't write vault | Confirm path exists; sandbox is intentionally off |
