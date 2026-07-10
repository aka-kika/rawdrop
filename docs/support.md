# RawDrop — Support

**For version:** 0.3.7 · **Updated:** 2026-07-10

## Getting help

- Found a bug? Open an [issue](https://github.com/aka-kika/rawdrop/issues/new/choose) using the bug report template.
- Something sensitive? See [SECURITY.md](../SECURITY.md) — please don't open a public issue for it.
- Setup, requirements, and defaults are all in the [README](../README.md).

## Frequently asked

### Do I need an internet connection or an account?
No. RawDrop runs fully local against Ollama on your machine. There's no account, no telemetry. The only time it reaches the network is if you deliberately switch to Ollama Cloud (with your own API key) or capture a URL.

### Where do my notes go?
Into the **Knowledge root** you set in Settings — drops land in `raw/`, compiled articles in `wiki/`, and `wiki/_index.md` is kept up to date. RawDrop only writes under those folders (and optionally `outputs/`).

### Why is there no Dock icon?
By design — RawDrop is a menu bar app (`LSUIElement`). Everything lives in the popover from the menu bar icon.

### Can I hand-edit compiled articles?
Yes. Put your edits under a `## Human` heading or between `<!-- rawdrop:protected -->` markers and recompile will leave them untouched. Freeform edits elsewhere are detected via an internal content hash so RawDrop won't clobber your work silently.

## Troubleshooting

### "RawDrop can't be opened" or a Gatekeeper warning
The release build is signed and notarized by Apple, so it should open normally. If macOS still blocks it (e.g. after an unusual download), right-click the app → **Open** once, or run `xattr -dr com.apple.quarantine /Applications/RawDrop.app`.

### Compile does nothing / "no models"
Ollama isn't reachable. Make sure it's installed and running (`ollama serve`) and that you've pulled at least one model (`ollama pull ministral-3`). Then open **Settings → Compile**, run **Test connectivity**, and pick a model. For Ollama Cloud, set the base URL to `https://ollama.com` and add your API key.

### It compiled but I don't see new articles
Check that your **Knowledge root** points where you expect, and look in `wiki/`. RawDrop only processes files in `raw/` that are new or changed since the last compile (tracked by content hash).

## Resetting the app

RawDrop's process state (compile tracking, body hashes) lives outside your vault at `~/Library/Application Support/RawDrop/`. Delete that folder to reset compile tracking — your `raw/` and `wiki/` files are untouched. The next Compile will reprocess everything in `raw/`.

## Uninstalling

Quit RawDrop, drag **RawDrop.app** from Applications to the Trash, and delete `~/Library/Application Support/RawDrop/`. Your Knowledge vault (`raw/`, `wiki/`, `outputs/`) is yours and stays where it is. API keys are stored in the macOS Keychain under service `com.akakika.RawDrop` — remove that item in Keychain Access if you want it gone.
