import Foundation

struct LocalModel: Identifiable, Hashable {
    let id: String
    let name: String
    var sizeLabel: String?
}

struct OllamaConnectionTestResult: Equatable {
    var ok: Bool
    var title: String
    var detail: String
    var modelCount: Int
    var latencyMs: Int
}

enum OllamaError: LocalizedError {
    case notRunning
    case badResponse
    case http(Int, String?)
    case emptyReply
    case decoding
    case timeout
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Cannot reach Ollama at the configured URL."
        case .badResponse: return "Invalid response from Ollama."
        case .http(let code, let body):
            if let body, !body.isEmpty {
                return "Ollama HTTP \(code): \(body)"
            }
            return "Ollama HTTP \(code)."
        case .emptyReply: return "Ollama returned an empty reply."
        case .decoding: return "Could not decode Ollama response."
        case .timeout: return "Ollama request timed out."
        case .unauthorized: return "Unauthorized — check your Ollama API key."
        }
    }
}

final class OllamaClient: @unchecked Sendable {
    var baseURL: URL
    var apiKey: String?
    var timeout: TimeInterval

    init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        apiKey: String? = nil,
        timeout: TimeInterval = 300
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
    }

    func apply(settings: AppSettings) {
        if let url = normalizedBaseURL(settings.ollamaBaseURL) {
            baseURL = url
        }
        let key = OllamaSecrets.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = (key?.isEmpty == false) ? key : nil
    }

    /// GET /api/tags with timing — used by Settings “Test connectivity”.
    func testConnectivity(expectedModel: String?) async -> OllamaConnectionTestResult {
        let start = Date()
        do {
            let models = try await listModels()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if models.isEmpty {
                return OllamaConnectionTestResult(
                    ok: false,
                    title: "Connected, no models",
                    detail: "Reached \(baseURL.absoluteString) but /api/tags returned an empty list. Pull a model or check cloud access.",
                    modelCount: 0,
                    latencyMs: ms
                )
            }
            if let expectedModel, !expectedModel.isEmpty, !modelExists(expectedModel, in: models) {
                return OllamaConnectionTestResult(
                    ok: false,
                    title: "Connected — model missing",
                    detail: "Endpoint OK (\(models.count) models, \(ms) ms). Selected model “\(expectedModel)” is not in the list.",
                    modelCount: models.count,
                    latencyMs: ms
                )
            }
            let names = models.prefix(5).map(\.name).joined(separator: ", ")
            let more = models.count > 5 ? "…" : ""
            return OllamaConnectionTestResult(
                ok: true,
                title: "Connected",
                detail: "\(baseURL.absoluteString) · \(models.count) models · \(ms) ms\n\(names)\(more)",
                modelCount: models.count,
                latencyMs: ms
            )
        } catch let error as OllamaError {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return OllamaConnectionTestResult(
                ok: false,
                title: "Connection failed",
                detail: "\(error.localizedDescription) (\(ms) ms)\nURL: \(baseURL.absoluteString)",
                modelCount: 0,
                latencyMs: ms
            )
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let ns = error as NSError
            let title: String
            if ns.domain == NSURLErrorDomain {
                title = "Cannot reach endpoint"
            } else {
                title = "Connection failed"
            }
            return OllamaConnectionTestResult(
                ok: false,
                title: title,
                detail: "\(error.localizedDescription) (\(ms) ms)\nURL: \(baseURL.absoluteString)",
                modelCount: 0,
                latencyMs: ms
            )
        }
    }

    func checkConnection(expectedModel: String?) async -> AIConnectionStatus {
        let result = await testConnectivity(expectedModel: expectedModel)
        if result.ok { return .connected }
        if result.title.contains("model missing") {
            return .modelMissing(expectedModel ?? "")
        }
        if result.title.contains("no models") {
            return .noModelsInstalled
        }
        if result.detail.localizedCaseInsensitiveContains("unauthorized")
            || result.detail.localizedCaseInsensitiveContains("401") {
            return .failed("Unauthorized — check API key")
        }
        if result.title.contains("Cannot reach") {
            return .ollamaNotRunning
        }
        return .failed(result.detail.components(separatedBy: "\n").first ?? result.title)
    }

    func listModels() async throws -> [LocalModel] {
        let url = endpoint("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        applyAuth(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfBad(response: response, data: data)

        struct TagsResponse: Decodable {
            struct Model: Decodable {
                let name: String
                let size: Int64?
            }
            let models: [Model]?
        }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        let models = decoded.models ?? []
        return models
            .map { m in
                LocalModel(
                    id: m.name,
                    name: m.name,
                    sizeLabel: m.size.map(Self.formatBytes)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func chat(model: String, system: String, user: String) async throws -> String {
        let url = endpoint("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        applyAuth(&request)

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let ns = error as NSError
            if ns.code == NSURLErrorTimedOut { throw OllamaError.timeout }
            if ns.domain == NSURLErrorDomain { throw OllamaError.notRunning }
            throw error
        }

        try throwIfBad(response: response, data: data)

        struct ChatResponse: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message?
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw OllamaError.emptyReply
        }
        return content
    }

    // MARK: - Internals

    private func endpoint(_ path: String) -> URL {
        // Avoid double /api if user typed https://ollama.com/api
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/api"), path.hasPrefix("api/") {
            let trimmed = String(path.dropFirst(4))
            return URL(string: base + "/" + trimmed)!
        }
        return URL(string: base + "/" + path)!
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private func throwIfBad(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OllamaError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OllamaError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(200), encoding: .utf8)
            throw OllamaError.http(http.statusCode, body)
        }
    }

    private func modelExists(_ expected: String, in models: [LocalModel]) -> Bool {
        models.contains { model in
            model.name == expected
                || model.id == expected
                || model.name.hasPrefix(expected + ":")
                || expected.hasPrefix(model.name)
        }
    }

    private func normalizedBaseURL(_ string: String) -> URL? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
