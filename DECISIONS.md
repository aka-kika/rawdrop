# DECISIONS

Append-only. Newest on top. What was chosen, what was rejected, and **why**.

---

## 2026-07-10 — Lean wiki YAML (one sources list; body hash out of properties)
**Chose:** Properties = `type` / `date` / `status` / `tags` / `origin` / `sources` (`raw/…`) / `compiled`. URLs only in `## Sources` footer. Body hash in Application Support `articleBodyHashes`.  
**Over:** Stacking `source` + `source_path` + `source_url` + `body_hash` into every note’s YAML  
**Because:** Three source-ish fields + a machine fingerprint made Obsidian Properties a visual mess. One list + footer is enough for humans; recompile safety does not need to live in the vault note.

---

## 2026-07-10 — Open at Login via SMAppService
**Chose:** `SMAppService.mainApp` register/unregister from Settings toggle  
**Over:** LaunchAgent plist or legacy `SMLoginItemSetEnabled`  
**Because:** Current macOS API, user-visible Login Items, no helper app. Best reliability when the app lives in `/Applications`.

---

## 2026-07-10 — Hybrid recompile merge (not full replace, not LLM merge yet)
**Chose:** Body content hash + preserve `## Human` / protected markers + replace only `## Compiled` when hash matches; provenance-only when human-edited  
**Over:** Always full body replace; append-only Updates; LLM smart merge  
**Because:** Protects hand edits without extra Ollama cost. Append history and LLM merge stay future features (see FEATURES.md / docs/recompile-merge.md). Hash storage later moved out of YAML (see lean YAML decision).

---

## 2026-07-10 — Origin fields on wiki articles
**Chose:** YAML provenance (later simplified to `origin` + `sources` + `compiled`) plus a `## Sources` body section  
**Over:** Only the index table, or no provenance  
**Because:** Concept articles alone hide which raw file produced them; properties + footer make origin legible. Superseded in shape by lean YAML (no triple source_*).

---

## 2026-07-10 — Theme via NSPopover/NSWindow appearance
**Chose:** Set `NSPopover.appearance` / window appearance and rebuild popover root on change  
**Over:** Only `NSApp.appearance` or only SwiftUI `preferredColorScheme`  
**Because:** Menu bar popovers keep their own AppKit appearance and ignore app-level theme unless set explicitly.

---

## 2026-07-10 — Dedicated Settings NSWindow
**Chose:** `SettingsWindowController` hosting SwiftUI  
**Over:** Relying on SwiftUI `Settings` scene + `showSettingsWindow:`  
**Because:** LSUIElement / `.accessory` apps often never surface the system Settings window; a normal titled window is reliable.

---

## 2026-07-10 — Paste capture only while popover is open
**Chose:** Local ⌘V monitor when popover is shown  
**Over:** Global always-on clipboard sniffer  
**Because:** Always-on capture steals paste from other apps; open-popover scope matches “I’m using RawDrop now.”

---

## 2026-07-10 — Ollama Cloud via same HTTP API + Keychain key
**Chose:** Configurable base URL + Bearer key in Keychain; `/api/tags` + `/api/chat`  
**Over:** Separate cloud SDKs (OpenAI, Anthropic, …)  
**Because:** One client path; cloud is opt-in; secrets never in UserDefaults/plist.

---

## 2026-07-10 — Recommended models = filter of installed only
**Chose:** Rank `availableModels` by name heuristics  
**Over:** Hardcoded cloud model catalog that may not be installed  
**Because:** Selecting a missing model fails at compile; recommendations must be runnable.

---

## 2026-07-10 — Compile state outside the vault
**Chose:** `~/Library/Application Support/RawDrop/compile-state.json`  
**Over:** State file inside `Knowledge/`  
**Because:** Vault is git/sync-sensitive; app bookkeeping must not pollute ground truth or agent write surfaces.

---

## 2026-07-10 — Copy into raw/, never move or edit after land
**Chose:** `copyItem` + unique suffix; compile is read-only on raw  
**Over:** Move ingest or “clean up raw” features  
**Because:** Vault law: `raw/` is append-only ground truth.

---

## 2026-07-10 — NSStatusItem + NSPopover over pure MenuBarExtra
**Chose:** AppKit status item for drag-on-icon + popover  
**Over:** MenuBarExtra-only  
**Because:** Dropping files onto the menu bar glyph needs AppKit drag registration; MenuBarExtra is weaker for that.

---

## 2026-07-10 — Native Swift only, no Electron
**Chose:** Single XcodeGen macOS target  
**Over:** Electron / Tauri / local server  
**Because:** Menu bar, Keychain, PDFKit, notifications, and vault FS are first-class natively; keeps the surface small enough to kill cheaply.

---

## 2026-07-10 — New project gate: GO
**Chose:** Build the menu bar drop+compile cut  
**Over:** CLI-only or agent-only compile  
**Because:** Capture is a human gesture (drag/paste); compile is a one-button loop; both deserve a tiny dedicated surface. Kill if unused 30 days.
