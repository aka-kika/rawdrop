# Vault seeding for new users — design

**Date:** 2026-07-10
**Status:** approved
**Component:** `RawDrop/Services/VaultSeeder.swift` (new), `RawDrop/Views/SettingsView.swift` (hook)

## Problem

A new RawDrop user points **Settings → Knowledge root** at a folder that usually doesn't
exist yet or is empty. Today the app only creates `raw/` lazily on the first drop and `wiki/`
on the first compile, and it never writes any explainer. So a fresh vault looks bare and its
structure/rules aren't self-documenting. The author's own Mac vault, by contrast, ships with
`raw/ wiki/ outputs/` **plus a README** describing the three folders and the rules — that's
what "works properly like on my Mac" means.

## Goal

When a user commits a Knowledge root, scaffold the same structure they'd get by hand:
the three folders plus a generic, de-personalized explainer file.

## Behavior

On save, **create-if-missing, never overwrite**:

- `raw/`, `wiki/`, `outputs/` — created with `withIntermediateDirectories: true`; no-op if present.
- `RawDrop.md` at the root — written **only if no file of that name exists**. Distinct name so it
  never collides with a user's own `README.md`. Never overwritten (protects user edits / re-saves).
- Nothing else is touched. No deletes. Failures are per-item and swallowed — seeding must never
  block saving settings.

This is fully consistent with RawDrop's existing vault law: writes only under the chosen root,
in the three sanctioned folders plus one clearly-named explainer.

## Component — `VaultSeeder`

Stateless enum-of-statics, matching `IngestService` style.

```swift
enum VaultSeeder {
    struct Result: Equatable { let createdFolders: [String]; let wroteReadme: Bool }
    @discardableResult
    static func seed(settings: AppSettings) -> Result
}
```

- Iterates `["raw", "wiki", "outputs"]`, creating each; records which were newly made.
- Writes `RawDrop.md` from a bundled string constant if absent; records whether it wrote.
- `Result` drives user feedback but is otherwise ignored (`@discardableResult`).

The `RawDrop.md` body is a generic rewrite of the author's vault README: same "ground truth /
`raw/` is append-only" callout, the three-folder table, the drop → compile → file-back loop, and
the agent rules — with all personal references removed (no author name, no personal wikilinks,
no personal tooling). Plain text, no emojis.

## Integration

Hook into `SettingsView.applyToState()` immediately after `s.knowledgeRootPath` is committed and
`appState.settings = s` is set. `applyToState()` is the single funnel where the root is committed;
it fires on **Save** and on **Choose folder**, both explicit user intent. Idempotency makes repeat
calls harmless. The Save button's `saveNote` reads *"Saved · vault ready"* when anything was newly
created, plain *"Saved"* otherwise.

## Testing / verification

No XCTest target exists in the project (verified in `project.yml`); adding one via XcodeGen is out
of scope for a change this size. Verification instead:

1. **Build** — `xcodebuild ... build` compiles clean with the new service + hook.
2. **Logic exercise** — a throwaway Swift snippet exercising `VaultSeeder.seed` against temp dirs:
   - fresh dir → 3 folders + `RawDrop.md` created;
   - second run → nothing new, `RawDrop.md` byte-identical;
   - pre-existing `RawDrop.md` with custom text → left intact;
   - partial vault (only `raw/`) → the missing two folders filled in.
3. **Runtime** — launch app, set a fresh Knowledge root in Settings, confirm the folders +
   `RawDrop.md` appear and `saveNote` reflects it.

## Out of scope (YAGNI)

- Seeding a starter file into `raw/` (empty vault + clear README is cleaner).
- A separate "Set up vault" button (implicit-on-save is enough).
- A test target.
