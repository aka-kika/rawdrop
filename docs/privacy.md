<!--
Privacy & Permissions — only claim what is true of the shipping build.
-->

# RawDrop — Privacy & Permissions

**Updated:** 2026-07-10 · **Version:** 0.3.7

## In one line

<!-- SF Symbol: hand.raised -->
Knowledge files stay on your Mac. Optional Ollama Cloud sends only the text you choose to compile, with a key you provide.

## Data the app handles

<!-- SF Symbol: externaldrive -->
| Data | Why | Where it lives | Leaves device? |
|---|---|---|---|
| Dropped files / pastes | Ingest into knowledge base | Copied under your Knowledge `raw/` | No (local copy) |
| Compiled wiki articles | Knowledge output | Knowledge `wiki/` | No |
| Compile state (source hashes + article body hashes) | Skip already-processed files; detect human edits on recompile | `~/Library/Application Support/RawDrop/` | No |
| Settings (paths, model, theme) | Preferences | UserDefaults | No |
| Ollama API key | Cloud auth | Keychain | Sent only to your configured Ollama base URL as Bearer token |
| Source text during Compile | Model input | Transient in memory / Ollama | Only if base URL is remote (e.g. ollama.com) |

## Permissions requested

<!-- SF Symbol: lock.shield -->
| Permission | When | What it's for |
|---|---|---|
| Filesystem (non-sandboxed) | Always | Read/write the vault path you configure |
| Network client | Ollama calls / URL fetch on drop | Local or cloud Ollama; fetch dropped URLs |
| Notifications | Compile finishes | Optional completion banner |

## Network

<!-- SF Symbol: network -->
- **Local default:** `http://localhost:11434` (Ollama on this Mac).
- **Optional cloud:** `https://ollama.com` (or your base URL) with Keychain API key.
- **URL drops:** HTTP(S) fetch to the URL you paste/drop, saved into `raw/`.
- No analytics SDKs. No ad networks.

## Third-party services

<!-- SF Symbol: shippingbox -->
- **Ollama** (local process or ollama.com) — only if you run Compile or Test connectivity.
- None otherwise.

## Your controls

<!-- SF Symbol: slider.horizontal.3 -->
- Clear API key in Settings.
- Change vault path or stop the app to halt writes.
- Delete Application Support `RawDrop` to reset compile state (does not delete vault files).
- Vault `raw/` is never deleted by the app.

## Contact

<!-- SF Symbol: envelope -->
Private project — owner: aka-kika / KIKA.
