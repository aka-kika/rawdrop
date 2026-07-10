import Foundation

struct IngestResult: Equatable {
    let destination: URL
    let originalName: String
    let wasURL: Bool
}

enum IngestError: LocalizedError {
    case invalidPath
    case copyFailed(String)
    case urlFetchFailed(String)
    case emptyDrop

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "Knowledge raw folder is not available."
        case .copyFailed(let m): return "Copy failed: \(m)"
        case .urlFetchFailed(let m): return "URL fetch failed: \(m)"
        case .emptyDrop: return "Nothing to drop."
        }
    }
}

enum IngestService {
    /// Copy file into raw/. Never moves. Never overwrites — collision gets " 2", " 3", …
    static func ingestFile(at source: URL, settings: AppSettings) throws -> IngestResult {
        let raw = settings.rawURL
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)

        // Resolve security-scoped / alias if needed
        let accessing = source.startAccessingSecurityScopedResource()
        defer {
            if accessing { source.stopAccessingSecurityScopedResource() }
        }

        let name = source.lastPathComponent
        let dest = uniqueDestination(in: raw, preferredName: name)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            throw IngestError.copyFailed(error.localizedDescription)
        }
        return IngestResult(destination: dest, originalName: name, wasURL: false)
    }

    /// Write arbitrary data into raw/ with a preferred filename.
    static func ingestData(_ data: Data, preferredName: String, settings: AppSettings) throws -> IngestResult {
        let raw = settings.rawURL
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let dest = uniqueDestination(in: raw, preferredName: preferredName)
        try data.write(to: dest, options: .atomic)
        return IngestResult(destination: dest, originalName: preferredName, wasURL: false)
    }

    /// Write a UTF-8 text note into raw/.
    static func ingestText(_ text: String, preferredName: String, settings: AppSettings) throws -> IngestResult {
        guard let data = text.data(using: .utf8) else {
            throw IngestError.copyFailed("Could not encode text")
        }
        return try ingestData(data, preferredName: preferredName, settings: settings)
    }

    /// Fetch a URL and save clean-ish markdown into raw/.
    static func ingestURL(_ urlString: String, settings: AppSettings) async throws -> IngestResult {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw IngestError.urlFetchFailed("Not an http(s) URL: \(urlString)")
        }

        let raw = settings.rawURL
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("RawDrop/0.1 (local knowledge ingest)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw IngestError.urlFetchFailed("HTTP \(code)")
        }

        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let body: String
        if contentType.contains("html") || HTMLTextExtractor.looksLikeHTML(data) {
            let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            body = HTMLTextExtractor.toMarkdown(html, sourceLabel: url.absoluteString)
        } else if let text = String(data: data, encoding: .utf8) {
            body = text
        } else {
            throw IngestError.urlFetchFailed("Unreadable content type: \(contentType)")
        }

        let baseName = sanitizeFilename(url.host.map { "\($0)-\(url.path)" } ?? url.absoluteString)
        let filename = baseName.hasSuffix(".md") ? baseName : baseName + ".md"
        let dest = uniqueDestination(in: raw, preferredName: filename)
        let header = """
        ---
        source_url: \(url.absoluteString)
        fetched: \(isoDate())
        ---

        """
        try (header + body).write(to: dest, atomically: true, encoding: .utf8)
        return IngestResult(destination: dest, originalName: url.absoluteString, wasURL: true)
    }

    static func uniqueDestination(in directory: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        let ns = preferredName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var candidate = directory.appendingPathComponent(preferredName)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let suffix = " \(n)"
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }

    private static func sanitizeFilename(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "?", with: "-")
            .replacingOccurrences(of: "&", with: "-")
            .replacingOccurrences(of: "=", with: "-")
            .replacingOccurrences(of: "#", with: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._ "))
        s = String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        if s.count > 80 { s = String(s.prefix(80)) }
        if s.isEmpty { s = "url-drop" }
        return s
    }

    private static func isoDate() -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: Date())
    }
}
