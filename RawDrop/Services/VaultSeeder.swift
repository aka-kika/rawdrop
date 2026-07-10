import Foundation

/// Seeds a Knowledge root with the folder structure and explainer a new user needs,
/// so a fresh vault "just works" the same way a hand-built one does.
///
/// Everything here is create-if-missing and NEVER overwrites — safe to call on every
/// settings save. Consistent with RawDrop's vault law: writes only under the chosen
/// root, in the three sanctioned folders plus one clearly-named explainer, no deletes.
enum VaultSeeder {
    struct Result: Equatable {
        let createdFolders: [String]
        let wroteReadme: Bool

        /// True if anything new landed on disk.
        var didSomething: Bool { !createdFolders.isEmpty || wroteReadme }
    }

    /// The three folders every Knowledge root is expected to have.
    static let folderNames = ["raw", "wiki", "outputs"]

    /// Distinct name so it never collides with a user's own README.md.
    static let readmeName = "RawDrop.md"

    /// Create any missing folders and write the explainer if absent. Best-effort:
    /// per-item failures are swallowed so seeding never blocks saving settings.
    @discardableResult
    static func seed(settings: AppSettings) -> Result {
        let fm = FileManager.default
        let root = settings.knowledgeRootURL

        var created: [String] = []
        for name in folderNames {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    created.append(name)
                } catch {
                    // Best-effort — skip this folder, keep going.
                }
            }
        }

        var wroteReadme = false
        let readme = root.appendingPathComponent(readmeName, isDirectory: false)
        if !fm.fileExists(atPath: readme.path) {
            do {
                // Ensure the root itself exists before writing into it.
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                try readmeBody.data(using: .utf8)?.write(to: readme, options: .withoutOverwriting)
                wroteReadme = true
            } catch {
                // Best-effort — a pre-existing file or write failure just means no explainer.
            }
        }

        return Result(createdFolders: created, wroteReadme: wroteReadme)
    }

    /// Generic, de-personalized explainer dropped at the vault root. Plain text, no emojis.
    static let readmeBody = """
    ---
    type: note
    status: active
    tags: [knowledge-base, rawdrop]
    ---

    # Knowledge — your LLM-compiled knowledge base

    > [!danger] Ground truth
    > `raw/` is append-only — nothing in it is ever edited or deleted, by anyone (including RawDrop). New knowledge is written only into `wiki/` and `outputs/`.

    A Karpathy-style personal knowledge base. Raw sources go in, an LLM compiles them into a
    wiki, questions get answered from the wiki, and the good answers get filed back in. Your
    notes app (Obsidian or any Markdown editor) is the frontend; the LLM is the librarian.

    RawDrop is the capture-and-compile surface for this folder: drop things in, press Compile,
    and it turns new `raw/` material into linked articles under `wiki/`.

    ## The three folders

    | Folder | What it is | Who writes |
    |---|---|---|
    | `raw/` | Source material: web clippings, papers, notes, datasets, images. Whatever you drop onto RawDrop lands here. | You (and ingest tools). Append-only — nothing here is edited after it lands. |
    | `wiki/` | The compiled knowledge: concept articles, summaries of everything in `raw/`, backlinks, index files. | RawDrop, on Compile. You rarely touch it directly. |
    | `outputs/` | Rendered answers to questions: Markdown reports, slides, charts. Good ones get filed back into `wiki/`. | On request. |

    ## How it runs

    1. **Ingest** — drop anything into `raw/` (drag onto RawDrop, or paste with the popover open). No frontmatter required; capture stays raw.
    2. **Compile** — RawDrop summarizes new raw material, categorizes it into concepts, writes or updates articles under `wiki/`, and keeps `wiki/_index.md` current.
    3. **Q&A** — ask questions against the wiki; render answers into `outputs/`.
    4. **File back** — promote useful outputs into `wiki/` so every exploration adds up.

    ## Rules

    - `wiki/` and `outputs/` are the compiled layer. `raw/` is read-only after it lands — never edited, never deleted.
    - Wiki articles carry a small frontmatter set (`type: note`, `date`, `status`, `tags`); raw needs none.
    - Keep `wiki/_index.md` current — it is the entry point every Q&A session reads first.
    - Hand-edit under a `## Human` heading or between `<!-- rawdrop:protected -->` markers and RawDrop's recompile will leave your edits alone.

    You can safely edit or replace this file — RawDrop never overwrites it once it exists.
    """
}
