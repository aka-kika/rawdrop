# Contributing

Thanks for interest in RawDrop. The app is intentionally small: **drop into raw/** and **compile into wiki/**.

## Development

1. Fork and clone the repo.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Xcode 15+.
3. `xcodegen generate` then open `RawDrop.xcodeproj` or build via `xcodebuild`.
4. Point Settings → Knowledge root at a test folder with `raw/`, `wiki/`, `outputs/`.
5. Run Ollama locally for Compile.

See [docs/environment.md](./docs/environment.md).

## Guidelines

- Do not add cloud providers beyond Ollama-compatible HTTP unless discussed.
- Never implement delete/edit of `raw/` after land.
- Prefer small PRs; match existing Swift style and doc rhythm (`CHANGELOG` / `DECISIONS` when behavior changes).
- No secrets in commits (API keys stay in Keychain).

## Reporting issues

Include macOS version, Xcode version, Ollama version/model, and steps to reproduce. Screenshots of the popover help.
