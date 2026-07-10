import Foundation

struct ProcessedSource: Codable, Equatable {
    var filename: String
    var contentHash: String
    var processedAt: Date
    var summary: String
    var articles: [String]
}

struct CompileStateFile: Codable, Equatable {
    /// raw filename → last successful compile
    var processed: [String: ProcessedSource]
    /// wiki article filename (e.g. "Topic.md") → body content hash for recompile safety.
    /// Kept here (not in YAML) so Obsidian properties stay clean.
    var articleBodyHashes: [String: String]

    static let empty = CompileStateFile(processed: [:], articleBodyHashes: [:])

    enum CodingKeys: String, CodingKey {
        case processed, articleBodyHashes
    }

    init(processed: [String: ProcessedSource], articleBodyHashes: [String: String] = [:]) {
        self.processed = processed
        self.articleBodyHashes = articleBodyHashes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        processed = try c.decodeIfPresent([String: ProcessedSource].self, forKey: .processed) ?? [:]
        articleBodyHashes = try c.decodeIfPresent([String: String].self, forKey: .articleBodyHashes) ?? [:]
    }
}

/// A raw file in the capture list (pending or already compiled).
struct CaptureItem: Identifiable, Equatable, Hashable {
    var id: String { filename }
    let filename: String
    let byteCount: Int64?
    let modifiedAt: Date?
    /// false = waiting to compile; true = compiled (shown dimmed at bottom of list)
    let isCompiled: Bool

    var detailLabel: String {
        var parts: [String] = []
        if let byteCount, byteCount > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        }
        if let modifiedAt {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            parts.append(f.string(from: modifiedAt))
        }
        if isCompiled {
            parts.append("compiled")
        }
        return parts.joined(separator: " · ")
    }
}

enum CompileStateStore {
    private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("RawDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var stateURL: URL {
        supportDirectory.appendingPathComponent("compile-state.json")
    }

    static func load() -> CompileStateFile {
        guard let data = try? Data(contentsOf: stateURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CompileStateFile.self, from: data)) ?? .empty
    }

    static func save(_ state: CompileStateFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }
}

enum AIConnectionStatus: Equatable {
    case unknown
    case checking
    case connected
    case ollamaNotRunning
    case noModelsInstalled
    case modelMissing(String)
    case failed(String)

    var label: String {
        switch self {
        case .unknown: return "Ollama status unknown"
        case .checking: return "Checking Ollama…"
        case .connected: return "Ollama connected"
        case .ollamaNotRunning: return "Ollama not running"
        case .noModelsInstalled: return "No models installed"
        case .modelMissing(let name): return "Model missing: \(name)"
        case .failed(let message): return "Ollama error: \(message)"
        }
    }

    var isReady: Bool {
        if case .connected = self { return true }
        return false
    }
}

enum CompilePhase: Equatable {
    case idle
    case preparing
    case compiling(current: Int, total: Int, filename: String)
    case finished(sources: Int, articles: Int)
    case nothingNew
    case failed(String)

    var progressText: String? {
        switch self {
        case .idle:
            return nil
        case .preparing:
            return "Preparing…"
        case .compiling(let current, let total, let filename):
            return "Compiling \(current)/\(total): \(filename)"
        case .finished(let sources, let articles):
            return "Done: \(sources) sources, \(articles) articles updated"
        case .nothingNew:
            return "Nothing new to compile"
        case .failed(let message):
            return message
        }
    }
}
