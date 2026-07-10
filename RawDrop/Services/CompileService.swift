import Foundation
import UserNotifications

struct CompileOutcome: Equatable {
    var sourcesCompiled: Int
    var articlesUpdated: Int
    var message: String
}

enum CompileServiceError: LocalizedError {
    case ollamaNotReady(String)
    case vaultMissing
    case partialWritePrevented(String)

    var errorDescription: String? {
        switch self {
        case .ollamaNotReady(let m): return m
        case .vaultMissing: return "Knowledge folders are missing. Check Settings."
        case .partialWritePrevented(let m): return m
        }
    }
}

/// Compile pass: raw files not yet processed → wiki articles + _index.md.
/// Writes ONLY under Knowledge/wiki/ (and never touches raw/).
enum CompileService {
    static let systemPrompt = """
    You are the librarian for a personal Karpathy-style LLM knowledge base.
    Rules:
    - Output plain text only. No emojis.
    - Use wikilinks like [[Article Title]] when referring to related concepts.
    - Prefer concept articles over dumping the source.
    - Be concise and factual. Impute nothing you cannot support from the source.
    """

    static func run(
        settings: AppSettings,
        ollama: OllamaClient,
        onProgress: @MainActor @escaping (CompilePhase) -> Void
    ) async throws -> CompileOutcome {
        await onProgress(.preparing)

        let status = await ollama.checkConnection(expectedModel: settings.ollamaModel)
        guard status.isReady || {
            if case .modelMissing = status { return false }
            return status == .connected
        }() else {
            throw CompileServiceError.ollamaNotReady(status.label)
        }
        // Require connected specifically (model missing should fail clearly)
        if case .modelMissing(let name) = status {
            throw CompileServiceError.ollamaNotReady("Selected model is missing: \(name). Pull it in Ollama or change the model in Settings.")
        }
        if status != .connected {
            throw CompileServiceError.ollamaNotReady(status.label)
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: settings.rawURL.path) else {
            throw CompileServiceError.vaultMissing
        }
        try fm.createDirectory(at: settings.wikiURL, withIntermediateDirectories: true)

        var state = CompileStateStore.load()
        let rawFiles = try listRawFiles(in: settings.rawURL)
        let pending = rawFiles.filter { file in
            let name = file.lastPathComponent
            guard let hash = try? ContentExtractor.sha256(of: file) else { return true }
            if let existing = state.processed[name], existing.contentHash == hash {
                return false
            }
            return true
        }

        if pending.isEmpty {
            // Still repair provenance on existing wiki articles from state.
            try backfillOrigins(state: state, settings: settings)
            try rewriteIndex(state: state, wikiURL: settings.wikiURL)
            await onProgress(.nothingNew)
            return CompileOutcome(sourcesCompiled: 0, articlesUpdated: 0, message: "Nothing new to compile (origins refreshed)")
        }

        var articlesUpdated = 0
        var sourcesCompiled = 0

        for (index, file) in pending.enumerated() {
            let name = file.lastPathComponent
            await onProgress(.compiling(current: index + 1, total: pending.count, filename: name))

            let text = try ContentExtractor.extractText(from: file)
            let hash = try ContentExtractor.sha256(of: file)
            let sourceURL = extractSourceURL(fromRawText: text) ?? extractSourceURL(fromFile: file)
            let result = try await compileOne(
                filename: name,
                text: text,
                settings: settings,
                ollama: ollama
            )

            // Write articles only after successful model synthesis for this source
            for article in result.articles {
                try writeWikiArticle(
                    article,
                    wikiURL: settings.wikiURL,
                    sourceFilename: name,
                    sourceURL: sourceURL
                )
                articlesUpdated += 1
            }

            state.processed[name] = ProcessedSource(
                filename: name,
                contentHash: hash,
                processedAt: Date(),
                summary: result.summary,
                articles: result.articles.map(\.title)
            )
            // Persist state after each source so a later failure does not re-do finished ones.
            // Articles for the current source are already fully written.
            try CompileStateStore.save(state)
            sourcesCompiled += 1
        }

        try backfillOrigins(state: state, settings: settings)
        try rewriteIndex(state: state, wikiURL: settings.wikiURL)

        let outcome = CompileOutcome(
            sourcesCompiled: sourcesCompiled,
            articlesUpdated: articlesUpdated,
            message: "\(sourcesCompiled) sources compiled, \(articlesUpdated) articles updated"
        )
        await onProgress(.finished(sources: sourcesCompiled, articles: articlesUpdated))
        notify(outcome.message)
        return outcome
    }

    // MARK: - One source

    private struct ArticleDraft: Equatable {
        var title: String
        var tags: [String]
        var body: String
    }

    private struct SourceCompileResult {
        var summary: String
        var articles: [ArticleDraft]
    }

    private static func compileOne(
        filename: String,
        text: String,
        settings: AppSettings,
        ollama: OllamaClient
    ) async throws -> SourceCompileResult {
        let chunks = ContentExtractor.chunk(text)
        var chunkSummaries: [String] = []

        if chunks.isEmpty {
            chunkSummaries = ["(empty or unreadable source: \(filename))"]
        } else if chunks.count == 1 {
            let summary = try await ollama.chat(
                model: settings.ollamaModel,
                system: systemPrompt,
                user: """
                Summarize this raw source for a knowledge wiki. Filename: \(filename)

                SOURCE:
                \(chunks[0])
                """
            )
            chunkSummaries = [summary]
        } else {
            for (i, chunk) in chunks.enumerated() {
                let summary = try await ollama.chat(
                    model: settings.ollamaModel,
                    system: systemPrompt,
                    user: """
                    This is chunk \(i + 1)/\(chunks.count) of raw source "\(filename)".
                    Write a tight factual summary of THIS chunk only.

                    CHUNK:
                    \(chunk)
                    """
                )
                chunkSummaries.append(summary)
            }
        }

        let joined = chunkSummaries.enumerated().map { "### Chunk \($0.offset + 1)\n\($0.element)" }.joined(separator: "\n\n")

        let synthesis = try await ollama.chat(
            model: settings.ollamaModel,
            system: systemPrompt + """

            Respond in this exact format (no extra commentary outside the blocks):

            SUMMARY:
            <one paragraph summary of the whole source>

            ARTICLES:
            ---
            TITLE: <Concept Title>
            TAGS: tag-one, tag-two
            BODY:
            <markdown article body, may use [[wikilinks]]>
            ---
            TITLE: <Another Concept>
            TAGS: tag
            BODY:
            <body>
            ---

            Create 1-3 concept articles. Prefer updating conceptual knowledge over restating the source.
            """,
            user: """
            Raw filename: \(filename)

            Chunk summaries:
            \(joined)
            """
        )

        return parseSynthesis(synthesis, fallbackTitle: titleFromFilename(filename))
    }

    private static func parseSynthesis(_ text: String, fallbackTitle: String) -> SourceCompileResult {
        var summary = ""
        var articles: [ArticleDraft] = []

        if let sumRange = text.range(of: #"SUMMARY:\s*"#, options: .regularExpression) {
            let after = text[sumRange.upperBound...]
            if let articlesMark = after.range(of: "ARTICLES:", options: .caseInsensitive) {
                summary = String(after[..<articlesMark.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                summary = String(after).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let articleBlocks = text.components(separatedBy: "---").filter { $0.localizedCaseInsensitiveContains("TITLE:") }
        for block in articleBlocks {
            guard let title = firstMatch(#"TITLE:\s*(.+)"#, in: block)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            let tagsLine = firstMatch(#"TAGS:\s*(.+)"#, in: block) ?? ""
            let tags = tagsLine
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "-") }
                .filter { !$0.isEmpty }
            var body = ""
            if let bodyRange = block.range(of: #"BODY:\s*"#, options: .regularExpression) {
                body = String(block[bodyRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if body.isEmpty { body = summary.isEmpty ? "Compiled from source." : summary }
            articles.append(ArticleDraft(title: sanitizeTitle(title), tags: tags.isEmpty ? ["compiled"] : tags, body: body))
        }

        if articles.isEmpty {
            let body = summary.isEmpty ? text : summary
            articles = [ArticleDraft(title: fallbackTitle, tags: ["compiled"], body: body)]
        }
        if summary.isEmpty {
            summary = articles.first?.body.prefix(280).description ?? fallbackTitle
        }
        return SourceCompileResult(summary: summary, articles: articles)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .anchorsMatchLines]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // MARK: - Wiki writes (hybrid recompile merge)

    /// Policy when an article file already exists.
    /// - provenanceOnly: human edited body — never overwrite prose
    /// - replaceCompiled: safe machine recompile — keep ## Human, refresh ## Compiled
    private enum RecompileBodyPolicy {
        case provenanceOnly
        case replaceCompiled
    }

    private static func writeWikiArticle(
        _ article: ArticleDraft,
        wikiURL: URL,
        sourceFilename: String,
        sourceURL: String?
    ) throws {
        let filename = sanitizeFilename(article.title) + ".md"
        let dest = wikiURL.appendingPathComponent(filename)
        let today = Self.todayString()
        let tags = article.tags.map { $0 }.joined(separator: ", ")
        let newCompiled = stripSourcesSection(article.body)
        let sourceRef = normalizeSourceRef(sourceFilename)

        var state = CompileStateStore.load()
        var sources: [String] = []
        var date = today
        var humanSection: String? = nil
        var policy: RecompileBodyPolicy = .replaceCompiled
        var existingType = "note"
        var existingStatus = "active"
        var existingTagsBracket = "[\(tags)]"
        // URL only in ## Sources footer (not YAML) — keep map filename → url for footer lines
        var sourceURLs: [String: String] = [:]

        if FileManager.default.fileExists(atPath: dest.path),
           let existing = try? String(contentsOf: dest, encoding: .utf8) {
            sources = parseSourcesList(from: existing)
            date = parseFrontmatterValue(key: "date", in: existing) ?? today
            existingType = parseFrontmatterValue(key: "type", in: existing) ?? "note"
            existingStatus = parseFrontmatterValue(key: "status", in: existing) ?? "active"
            if let t = parseFrontmatterValue(key: "tags", in: existing) {
                existingTagsBracket = t.hasPrefix("[") ? t : "[\(t)]"
            }
            // Migrate legacy YAML source_url + any URLs already in ## Sources
            sourceURLs = parseSourceURLsFromBody(existing)
            if let oldURL = parseFrontmatterValue(key: "source_url", in: existing)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")),
               !oldURL.isEmpty {
                let primary = normalizeSourceRef(sources.first ?? sourceRef)
                if sourceURLs[primary] == nil {
                    sourceURLs[primary] = oldURL
                }
            }

            let parsed = parseArticleBody(stripFrontmatter(existing))
            humanSection = parsed.humanSection

            // Prefer Application Support hash; fall back to legacy YAML body_hash once
            var storedHash = state.articleBodyHashes[filename]
            if storedHash == nil || storedHash?.isEmpty == true {
                storedHash = parseFrontmatterValue(key: "body_hash", in: existing)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            let currentHash = bodyContentHash(
                title: parsed.title,
                human: parsed.humanSection,
                compiled: parsed.compiledBody
            )
            if let storedHash, !storedHash.isEmpty, storedHash != currentHash {
                policy = .provenanceOnly
            }
        }

        sources = uniqueNormalizedSources(sources + [sourceRef])
        if let sourceURL, !sourceURL.isEmpty {
            sourceURLs[sourceRef] = sourceURL
        }

        let content: String
        let bodyHashToStore: String
        switch policy {
        case .provenanceOnly:
            guard let existing = try? String(contentsOf: dest, encoding: .utf8) else { return }
            let parsed = parseArticleBody(stripFrontmatter(existing))
            bodyHashToStore = bodyContentHash(
                title: parsed.title,
                human: parsed.humanSection,
                compiled: parsed.compiledBody
            )
            content = renderArticleMarkdown(
                title: parsed.title.isEmpty ? article.title : parsed.title,
                date: date,
                compiled: today,
                tagsBracket: existingTagsBracket,
                type: existingType,
                status: existingStatus,
                sources: sources,
                sourceURLs: sourceURLs,
                humanSection: parsed.humanSection,
                compiledBody: parsed.compiledBody
            )
        case .replaceCompiled:
            let title = article.title
            bodyHashToStore = bodyContentHash(title: title, human: humanSection, compiled: newCompiled)
            let tagsOut = FileManager.default.fileExists(atPath: dest.path)
                ? existingTagsBracket
                : "[\(tags)]"
            content = renderArticleMarkdown(
                title: title,
                date: date,
                compiled: today,
                tagsBracket: tagsOut,
                type: existingType,
                status: existingStatus,
                sources: sources,
                sourceURLs: sourceURLs,
                humanSection: humanSection,
                compiledBody: newCompiled
            )
        }

        try content.write(to: dest, atomically: true, encoding: .utf8)
        state.articleBodyHashes[filename] = bodyHashToStore
        try CompileStateStore.save(state)
    }

    /// Inject/merge origin YAML into existing wiki articles from compile state (no LLM).
    /// Never replaces human/compiled prose — provenance + sources footer only.
    static func backfillOrigins(state: CompileStateFile, settings: AppSettings) throws {
        for source in state.processed.values {
            let sourceURL = extractSourceURL(
                fromFile: settings.rawURL.appendingPathComponent(source.filename)
            )
            for title in source.articles {
                let candidates = [
                    settings.wikiURL.appendingPathComponent(sanitizeFilename(title) + ".md"),
                    settings.wikiURL.appendingPathComponent(
                        sanitizeFilename(title.replacingOccurrences(of: " / ", with: " - ")) + ".md"
                    )
                ]
                for dest in candidates where FileManager.default.fileExists(atPath: dest.path) {
                    try mergeOriginProvenanceOnly(
                        into: dest,
                        sourceFilename: source.filename,
                        sourceURL: sourceURL
                    )
                    break
                }
            }
        }
    }

    private static func mergeOriginProvenanceOnly(
        into dest: URL,
        sourceFilename: String,
        sourceURL: String?
    ) throws {
        guard let existing = try? String(contentsOf: dest, encoding: .utf8) else { return }
        let date = parseFrontmatterValue(key: "date", in: existing) ?? todayString()
        let tags = parseFrontmatterValue(key: "tags", in: existing) ?? "[compiled]"
        let status = parseFrontmatterValue(key: "status", in: existing) ?? "active"
        let type = parseFrontmatterValue(key: "type", in: existing) ?? "note"
        var sources = parseSourcesList(from: existing)
        let sourceRef = normalizeSourceRef(sourceFilename)
        sources = uniqueNormalizedSources(sources + [sourceRef])

        let tagsFormatted = tags.hasPrefix("[") ? tags : "[\(tags)]"
        let parsed = parseArticleBody(stripFrontmatter(existing))
        let title = parsed.title.isEmpty ? dest.deletingPathExtension().lastPathComponent : parsed.title

        var sourceURLs = parseSourceURLsFromBody(existing)
        if let sourceURL, !sourceURL.isEmpty {
            sourceURLs[sourceRef] = sourceURL
        }
        if let oldURL = parseFrontmatterValue(key: "source_url", in: existing)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")),
           !oldURL.isEmpty {
            let primary = sources.first ?? sourceRef
            if sourceURLs[primary] == nil {
                sourceURLs[primary] = oldURL
            }
        }

        // Preserve existing body hash in Application Support (do not change on backfill)
        var state = CompileStateStore.load()
        let wikiName = dest.lastPathComponent
        if state.articleBodyHashes[wikiName] == nil {
            // Migrate from legacy YAML if present
            if let legacy = parseFrontmatterValue(key: "body_hash", in: existing)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")),
               !legacy.isEmpty {
                state.articleBodyHashes[wikiName] = legacy
            } else {
                state.articleBodyHashes[wikiName] = bodyContentHash(
                    title: title,
                    human: parsed.humanSection,
                    compiled: parsed.compiledBody
                )
            }
            try? CompileStateStore.save(state)
        }

        let content = renderArticleMarkdown(
            title: title,
            date: date,
            compiled: parseFrontmatterValue(key: "compiled", in: existing) ?? todayString(),
            tagsBracket: tagsFormatted,
            type: type,
            status: status,
            sources: sources,
            sourceURLs: sourceURLs,
            humanSection: parsed.humanSection,
            compiledBody: parsed.compiledBody
        )
        try content.write(to: dest, atomically: true, encoding: .utf8)
    }

    /// Lean YAML for Obsidian properties — no redundant source_* / body_hash.
    private static func renderArticleMarkdown(
        title: String,
        date: String,
        compiled: String,
        tagsBracket: String,
        type: String,
        status: String,
        sources: [String],
        sourceURLs: [String: String],
        humanSection: String?,
        compiledBody: String
    ) -> String {
        var middle = ""
        if let human = humanSection?.trimmingCharacters(in: .whitespacesAndNewlines), !human.isEmpty {
            middle += human
            if !human.hasSuffix("\n") { middle += "\n" }
            middle += "\n"
        }
        let compiledText = compiledBody.trimmingCharacters(in: .whitespacesAndNewlines)
        middle += "## Compiled\n\n"
        middle += compiledText
        if !compiledText.isEmpty { middle += "\n" }

        let sourceLines = sources.map { ref in
            sourceLine(ref, url: sourceURLs[ref])
        }.joined(separator: "\n")

        return """
        ---
        type: \(type)
        date: \(date)
        status: \(status)
        tags: \(tagsBracket)
        origin: rawdrop
        sources:
        \(sources.map { "  - \(escapeYAML($0))" }.joined(separator: "\n"))
        compiled: \(compiled)
        ---

        # \(title)

        \(middle.trimmingCharacters(in: .whitespacesAndNewlines))

        ## Sources

        \(sourceLines)
        """
    }

    /// Normalize to `raw/filename` (single form for the sources list).
    private static func normalizeSourceRef(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if s.hasPrefix("raw/") { return s }
        if s.hasPrefix("Knowledge/raw/") {
            return String(s.dropFirst("Knowledge/".count))
        }
        // strip leading path junk
        let name = (s as NSString).lastPathComponent
        return "raw/\(name)"
    }

    // MARK: - Body structure helpers

    private struct ParsedArticleBody {
        var title: String
        /// Full `## Human` … block including heading, if present.
        var humanSection: String?
        /// Machine prose (was under `## Compiled`, or whole body for legacy notes).
        var compiledBody: String
    }

    /// Split article body into title, optional Human section, and compiled prose.
    private static func parseArticleBody(_ bodyWithMaybeHeading: String) -> ParsedArticleBody {
        var rest = stripSourcesSection(bodyWithMaybeHeading)
        var title = ""
        if let heading = firstMatch(#"^#\s+(.+)$"#, in: rest) {
            title = heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = rest.range(of: #"^#\s+.+\n?"#, options: .regularExpression) {
                rest = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Protected HTML comment blocks are treated as part of Human (never overwritten as Compiled).
        var human: String? = nil
        var compiled = rest

        if let humanBlock = extractSection(named: "Human", from: rest) {
            human = "## Human\n\n" + humanBlock.content
            compiled = humanBlock.remainder
        }

        // Pull explicit Compiled section if present
        if let compiledBlock = extractSection(named: "Compiled", from: compiled) {
            compiled = compiledBlock.content
            // Anything before ## Compiled that isn't Human stays as leftover human-ish material
            let before = compiledBlock.before.trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                if var h = human {
                    h += "\n\n" + before
                    human = h
                } else {
                    human = before
                }
            }
        }

        // Extract <!-- rawdrop:protected --> … <!-- /rawdrop:protected --> into human
        if let protected = extractProtectedBlocks(from: compiled) {
            if var h = human {
                h += "\n\n" + protected.blocks
                human = h
            } else {
                human = protected.blocks
            }
            compiled = protected.remainder
        }

        return ParsedArticleBody(
            title: title,
            humanSection: human?.trimmingCharacters(in: .whitespacesAndNewlines),
            compiledBody: compiled.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private struct SectionExtract {
        var content: String
        var remainder: String
        var before: String
    }

    /// Extract `## Name` section until next `## ` or end.
    private static func extractSection(named name: String, from text: String) -> SectionExtract? {
        let pattern = #"(?m)^## \#(name)\s*\n([\s\S]*?)(?=^## |\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let fullR = Range(match.range(at: 0), in: text),
              let contentR = Range(match.range(at: 2), in: text)
        else { return nil }

        let before = String(text[..<fullR.lowerBound])
        let content = String(text[contentR]).trimmingCharacters(in: .whitespacesAndNewlines)
        let after = String(text[fullR.upperBound...])
        let remainder = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        return SectionExtract(content: content, remainder: remainder, before: before.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private struct ProtectedExtract {
        var blocks: String
        var remainder: String
    }

    private static func extractProtectedBlocks(from text: String) -> ProtectedExtract? {
        let pattern = #"<!--\s*rawdrop:protected\s-->([\s\S]*?)<!--\s*/rawdrop:protected\s-->"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }

        var blocks: [String] = []
        var remainder = text
        // Remove from end so ranges stay valid on string rebuild via regex replace
        for match in matches.reversed() {
            if let r = Range(match.range, in: remainder) {
                let full = String(remainder[r])
                blocks.insert(full, at: 0)
                remainder.replaceSubrange(r, with: "\n")
            }
        }
        return ProtectedExtract(
            blocks: blocks.joined(separator: "\n\n"),
            remainder: remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Hash of title + human + compiled — used to detect post-compile human edits.
    private static func bodyContentHash(title: String, human: String?, compiled: String) -> String {
        let payload = [
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            (human ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            compiled.trimmingCharacters(in: .whitespacesAndNewlines)
        ].joined(separator: "\n---\n")
        return ContentExtractor.sha256(of: payload)
    }

    /// Footer line. `ref` is already `raw/filename` (or bare legacy, which we still show as-is).
    private static func sourceLine(_ ref: String, url: String?) -> String {
        if let url, !url.isEmpty {
            return "- `\(ref)` — \(url)"
        }
        return "- `\(ref)`"
    }

    /// Normalize + de-dupe sources (order: sorted case-insensitive).
    private static func uniqueNormalizedSources(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in raw {
            let n = normalizeSourceRef(item)
            if seen.insert(n).inserted {
                out.append(n)
            }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Pull `raw/…` → URL pairs from the body `## Sources` section (and legacy forms).
    private static func parseSourceURLsFromBody(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        // - `raw/foo.md` — https://…
        // - raw/foo.md — https://…
        let pattern = #"(?m)^-\s+`?([^`\n]+?)`?\s+[—\-]\s+(https?://\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return map }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        for match in matches where match.numberOfRanges >= 3 {
            if let refR = Range(match.range(at: 1), in: text),
               let urlR = Range(match.range(at: 2), in: text) {
                let ref = normalizeSourceRef(String(text[refR]))
                let url = String(text[urlR]).trimmingCharacters(in: CharacterSet(charactersIn: ".,);]\""))
                if !ref.isEmpty, !url.isEmpty {
                    map[ref] = url
                }
            }
        }
        return map
    }

    private static func rewriteIndex(state: CompileStateFile, wikiURL: URL) throws {
        let date = todayString()
        let topics = state.processed.values
            .flatMap(\.articles)
            .reduce(into: [String]()) { acc, title in
                if !acc.contains(title) { acc.append(title) }
            }
            .sorted()

        let topicLines: String
        if topics.isEmpty {
            topicLines = "*(none yet)*"
        } else {
            topicLines = topics.map { "- [[\($0)]]" }.joined(separator: "\n")
        }

        let sortedSources = state.processed.values.sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
        let rows = sortedSources.map { src in
            let linkName = (src.filename as NSString).deletingPathExtension
            let compiled = src.articles.map { "[[\($0)]]" }.joined(separator: ", ")
            let summary = src.summary.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
            let short = summary.count > 160 ? String(summary.prefix(157)) + "..." : summary
            return "| `raw/\(src.filename)` | \(short) | \(compiled.isEmpty ? "—" : compiled) |"
        }.joined(separator: "\n")

        let content = """
        ---
        type: note
        date: \(date)
        status: active
        tags: [knowledge-base, index]
        origin: rawdrop
        ---

        # Wiki Index

        Entry point for the compiled knowledge base. Maintained by the LLM — every compile pass updates this file.

        ## Topics

        \(topicLines)

        ## Raw sources ingested

        | Source | Summary | Compiled into |
        |---|---|---|
        \(rows.isEmpty ? "| — | — | — |" : rows)
        """
        let indexURL = wikiURL.appendingPathComponent("_index.md")
        try content.write(to: indexURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Origin helpers

    private static func extractSourceURL(fromFile file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return extractSourceURL(fromRawText: text)
    }

    private static func extractSourceURL(fromRawText text: String) -> String? {
        // From RawDrop URL ingest frontmatter: source_url: https://...
        if let v = parseFrontmatterValue(key: "source_url", in: text), !v.isEmpty {
            return v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        // First http(s) URL in first 2KB
        let head = String(text.prefix(2000))
        if let match = firstMatch(#"(https?://[^\s\)\]\>\"']+)"#, in: head) {
            return match
        }
        return nil
    }

    private static func parseFrontmatterValue(key: String, in text: String) -> String? {
        guard text.hasPrefix("---") else { return nil }
        let parts = text.split(separator: "---", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let fm = String(parts[1])
        return firstMatch(#"^\#(key):\s*(.+)$"#, in: fm)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseSourcesList(from text: String) -> [String] {
        var sources: [String] = []
        if let single = parseFrontmatterValue(key: "source", in: text) {
            let cleaned = single.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !cleaned.isEmpty { sources.append(cleaned) }
        }
        // sources: block
        if let fmRange = text.range(of: #"^---\n([\s\S]*?)\n---"# , options: .regularExpression) {
            let fm = String(text[fmRange])
            let lines = fm.components(separatedBy: .newlines)
            var inSources = false
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces) == "sources:" {
                    inSources = true
                    continue
                }
                if inSources {
                    if line.hasPrefix("  - ") || line.hasPrefix("- ") {
                        var item = line.trimmingCharacters(in: .whitespaces)
                        if item.hasPrefix("- ") { item = String(item.dropFirst(2)) }
                        item = item.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !item.isEmpty, !sources.contains(item) {
                            sources.append(item)
                        }
                    } else if !line.hasPrefix(" ") && !line.hasPrefix("\t") && line.contains(":") {
                        inSources = false
                    }
                }
            }
        }
        return sources
    }

    private static func stripSourcesSection(_ body: String) -> String {
        if let range = body.range(of: #"\n## Sources\b[\s\S]*$"#, options: .regularExpression) {
            return String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escapeYAML(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func listRawFiles(in rawURL: URL) throws -> [URL] {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: rawURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func sanitizeTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = title.unicodeScalars.map { invalid.contains($0) ? Character("-") : Character($0) }
        var s = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "untitled" }
        return s
    }

    private static func titleFromFilename(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    private static func stripFrontmatter(_ text: String) -> String {
        if text.hasPrefix("---") {
            let parts = text.split(separator: "---", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count >= 3 {
                return parts[2...].joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func notify(_ body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "RawDrop"
            content.body = body
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req)
        }
    }
}
