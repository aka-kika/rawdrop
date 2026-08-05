import Foundation

enum LinkPhase: Equatable {
    case idle
    case preparing
    case linking(current: Int, total: Int, title: String)
    case finished(updated: Int)
    case nothingToLink
    case failed(String)

    var progressText: String? {
        switch self {
        case .idle:
            return nil
        case .preparing:
            return "Preparing link pass…"
        case .linking(let current, let total, let title):
            return "Linking \(current)/\(total): \(title)"
        case .finished(let updated):
            return "Link pass done: \(updated) articles updated"
        case .nothingToLink:
            return "All articles already linked"
        case .failed(let message):
            return message
        }
    }
}

enum LinkServiceError: LocalizedError {
    case ollamaNotReady(String)
    case wikiMissing

    var errorDescription: String? {
        switch self {
        case .ollamaNotReady(let m): return m
        case .wikiMissing: return "Wiki folder is missing. Check Settings."
        }
    }
}

/// Link pass: cross-link wiki articles with a machine-owned ## Related section.
/// Chooses relations with the same Ollama model; writes ONLY the Related section
/// (prose, Human sections, and Sources are untouched). RawDrop-internal links
/// only — never reaches outside the Knowledge folder.
enum LinkService {
    static let systemPrompt = """
    You are the librarian for a personal LLM knowledge wiki.
    Given one article and the list of all other article titles, pick the few
    articles a reader of this one would genuinely want next.
    Rules:
    - Answer with 0 to 5 titles, one per line, copied EXACTLY from the candidate list.
    - No commentary, no bullets, no numbering, no new titles.
    - Only pick truly related topics. Fewer good links beat many weak ones.
    """

    static func run(
        settings: AppSettings,
        ollama: OllamaClient,
        onProgress: @MainActor @escaping (LinkPhase) -> Void
    ) async throws -> Int {
        await onProgress(.preparing)

        let status = await ollama.checkConnection(expectedModel: settings.ollamaModel)
        if case .modelMissing(let name) = status {
            throw LinkServiceError.ollamaNotReady("Selected model is missing: \(name). Pull it in Ollama or change the model in Settings.")
        }
        if status != .connected {
            throw LinkServiceError.ollamaNotReady(status.label)
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: settings.wikiURL.path) else {
            throw LinkServiceError.wikiMissing
        }
        let files = try fm.contentsOfDirectory(at: settings.wikiURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "md" && $0.lastPathComponent != "_index.md" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var titleByFilename: [String: String] = [:]
        for file in files {
            titleByFilename[file.lastPathComponent] = CompileService.articleTitle(of: file)
        }
        let allTitles = files.compactMap { titleByFilename[$0.lastPathComponent] }
        // lowercase title → canonical spelling, first wins
        let canonical = Dictionary(
            allTitles.map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var state = CompileStateStore.load()
        // Incremental: only articles that have never been through a link pass.
        let todo = files.filter { state.articleRelated[$0.lastPathComponent] == nil }
        guard !todo.isEmpty else {
            await onProgress(.nothingToLink)
            return 0
        }

        var updated = 0
        for (index, file) in todo.enumerated() {
            let filename = file.lastPathComponent
            let title = titleByFilename[filename] ?? filename
            await onProgress(.linking(current: index + 1, total: todo.count, title: title))

            let excerpt = CompileService.articleExcerpt(of: file)
            let candidates = allTitles.filter { $0 != title }
            let reply = try await ollama.chat(
                model: settings.ollamaModel,
                system: systemPrompt,
                user: """
                ARTICLE: \(title)

                EXCERPT:
                \(excerpt)

                CANDIDATE TITLES (pick only from these, exact spelling):
                \(candidates.joined(separator: "\n"))
                """
            )

            let related = parseRelated(reply, canonical: canonical, excluding: title)
            // Record even empty results so the pass stays incremental.
            state.articleRelated[filename] = related
            if !related.isEmpty {
                try CompileService.rewriteRelated(at: file, related: related)
                updated += 1
            }
            // Persist per article so an interrupted pass resumes where it stopped.
            try CompileStateStore.save(state)
        }

        await onProgress(.finished(updated: updated))
        return updated
    }

    /// Validate model output: exact-title lines only, deduped, capped at 5.
    private static func parseRelated(
        _ reply: String,
        canonical: [String: String],
        excluding selfTitle: String
    ) -> [String] {
        var out: [String] = []
        for rawLine in reply.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count))
            }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]0123456789. "))
            guard !line.isEmpty else { continue }
            guard let match = canonical[line.lowercased()], match != selfTitle else { continue }
            if !out.contains(match) {
                out.append(match)
            }
            if out.count == 5 { break }
        }
        return out
    }
}
