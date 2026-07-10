# Architecture

## High-level flow

```
[User drop / ⌘V]
       │
       ▼
 IngestService ──copy──► Knowledge/raw/   (append-only)
       │
       │  content hash
       ▼
 CompileStateStore  (Application Support)
       │  processed sources + articleBodyHashes
       │  unprocessed files
       ▼
 ContentExtractor ──► chunks
       │
       ▼
 OllamaClient (/api/chat)
       │
       ▼
 CompileService ──write──► Knowledge/wiki/*.md  (lean YAML + ## Compiled)
                       └──► Knowledge/wiki/_index.md
```

## Module map

```
RawDrop/
  App/
    RawDropApp.swift                 SwiftUI @main + AppDelegate
    AppState.swift                   Observable hub (settings, ingest, compile, capture list)
    StatusItemController.swift       NSStatusItem + NSPopover + paste monitor
    SettingsWindowController.swift   Dedicated settings NSWindow
  Models/
    AppSettings.swift                Path, Ollama, theme (UserDefaults)
    CompileState.swift               Processed sources + article body hashes JSON
  Services/
    IngestService.swift              Copy / URL fetch / data write
    ContentExtractor.swift           PDF / HTML / text / hash / chunk
    HTMLTextExtractor.swift          Shared HTML → markdown-ish
    OllamaClient.swift               tags + chat + connectivity test
    CompileService.swift             LLM pass + lean wiki writers + hybrid recompile
    ModelRecommendations.swift       Rank installed models
    KeychainStore.swift              API key
    LaunchAtLoginService.swift       SMAppService open-at-login
  Views/
    PopoverView.swift                Capture zone + Compile + capture list
    SettingsView.swift               Form: vault / Ollama / theme / login
  Resources/
    Assets.xcassets/AppIcon…         macOS icon set
```

## State locations

| Data | Where |
|---|---|
| Settings (non-secret) | `UserDefaults` key `rawdrop.settings` |
| Ollama API key | Keychain service `com.akakika.RawDrop` |
| Compile progress + article body hashes | `~/Library/Application Support/RawDrop/compile-state.json` |
| Ground truth sources | `{knowledgeRoot}/raw/` |
| Compiled knowledge | `{knowledgeRoot}/wiki/` |

## Wiki article shape

**YAML (Obsidian properties)** — lean only:

```yaml
type / date / status / tags
origin: rawdrop
sources:
  - raw/filename.md
compiled: YYYY-MM-DD
```

**Not in YAML:** `source`, `source_path`, `source_url`, `body_hash`.  
**URLs:** body `## Sources` footer only.  
**Body hash:** Application Support `articleBodyHashes` — recompile safety fingerprint for title + Human + Compiled.

## Hybrid recompile

| Condition | Write policy |
|---|---|
| New article | Full write with `## Compiled` |
| Hash matches last machine write | Refresh `## Compiled` only; keep `## Human` / protected blocks |
| Hash mismatch (human edited) | Provenance only (sources + footer); no prose overwrite |
| Nothing new to compile | Origin backfill still runs (YAML/footer only) |

## Trust boundaries

- **Vault write surface:** only `raw/` (create/copy), `wiki/` (create/update), never delete.
- **Network:** Ollama base URL only (localhost or ollama.com when configured). No other providers.
- **Secrets:** Keychain only; never log API keys.

## UI shell

- Activation policy: `.accessory` (menu bar)
- Briefly `.regular` while Settings window is open
- Popover: `.semitransient` so buttons receive clicks
- Theme: `NSPopover.appearance` + settings window appearance (not app-only)
