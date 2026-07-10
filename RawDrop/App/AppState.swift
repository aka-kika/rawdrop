import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
@Observable
final class AppState {
    var settings: AppSettings {
        didSet { SettingsStore.save(settings) }
    }

    var ollamaStatus: AIConnectionStatus = .unknown
    var availableModels: [LocalModel] = []
    var lastConnectionTest: OllamaConnectionTestResult?
    var isTestingConnection: Bool = false
    var isRefreshingModels: Bool = false

    var compilePhase: CompilePhase = .idle
    var statusMessage: String = "Ready"
    var lastIngestMessage: String?
    var isCompiling: Bool = false
    var isIngestingPaste: Bool = false
    var recentIngests: [String] = []
    /// All raw captures: pending first, then compiled (for the list under Compile).
    var captureList: [CaptureItem] = []

    /// Raw files not yet compiled (or hash-changed).
    var pendingCaptures: [CaptureItem] {
        captureList.filter { !$0.isCompiled }
    }

    var compiledCaptures: [CaptureItem] {
        captureList.filter(\.isCompiled)
    }
    /// True while the menu popover is open — paste is captured then.
    var isCaptureSurfaceActive: Bool = false
    /// Bumped on every theme change so SwiftUI hosts re-render.
    var appearanceEpoch: Int = 0
    /// Open at Login (SMAppService) — not stored in UserDefaults; OS is source of truth.
    var launchAtLoginEnabled: Bool = false
    var launchAtLoginMessage: String?

    let ollama = OllamaClient()

    init() {
        self.settings = SettingsStore.load()
        applyOllamaConfig()
        applyAppearance()
        refreshLaunchAtLoginStatus()
        refreshPendingCaptures()
    }

    /// Scan Knowledge/raw vs compile-state; pending first, compiled after (dimmed in UI).
    func refreshPendingCaptures() {
        let rawURL = settings.rawURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: rawURL.path) else {
            captureList = []
            return
        }
        let state = CompileStateStore.load()
        guard let urls = try? fm.contentsOfDirectory(
            at: rawURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            captureList = []
            return
        }

        var pending: [CaptureItem] = []
        var compiled: [CaptureItem] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate
            let isCompiled: Bool
            if let hash = try? ContentExtractor.sha256(of: url),
               let existing = state.processed[name],
               existing.contentHash == hash {
                isCompiled = true
            } else {
                isCompiled = false
            }
            let item = CaptureItem(
                filename: name,
                byteCount: size,
                modifiedAt: modified,
                isCompiled: isCompiled
            )
            if isCompiled {
                compiled.append(item)
            } else {
                pending.append(item)
            }
        }
        let byName: (CaptureItem, CaptureItem) -> Bool = {
            $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending
        }
        // Pending (needs compile) on top; compiled below at 50% opacity in the UI
        captureList = pending.sorted(by: byName) + compiled.sorted(by: byName)
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
        launchAtLoginMessage = LaunchAtLoginService.statusDescription
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            _ = try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            launchAtLoginMessage = LaunchAtLoginService.statusDescription
            if enabled && !launchAtLoginEnabled {
                launchAtLoginMessage = LaunchAtLoginService.statusDescription
            }
        } catch {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            launchAtLoginMessage = error.localizedDescription
        }
    }

    func applyOllamaConfig() {
        ollama.apply(settings: settings)
    }

    /// Persist selected model and refresh main-window status to match (live).
    func setOllamaModel(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = settings
        next.ollamaModel = trimmed
        settings = next
        applyOllamaConfig()
        syncOllamaStatusMessage()
    }

    /// Rebuild the Ollama status line from live settings + connection state.
    /// Used so the popover never shows a stale model name after Settings changes.
    func syncOllamaStatusMessage() {
        // Don't clobber active work feedback
        if isCompiling || isIngestingPaste { return }
        let transientPrefixes = [
            "Copied ", "Captured ", "Fetched ", "Compiling", "Done:", "Nothing new"
        ]
        if transientPrefixes.contains(where: { statusMessage.hasPrefix($0) }) {
            // Leave recent action text; still OK — header uses displayStatusLine for idle
            return
        }
        statusMessage = makeOllamaStatusLine()
    }

    /// Live line for the popover header (always uses current `settings.ollamaModel` when idle).
    var displayStatusLine: String {
        if isCompiling || isIngestingPaste {
            return statusMessage
        }
        // Recent action feedback — keep it until the next Ollama sync/open
        let actionPrefixes = ["Copied ", "Captured ", "Fetched ", "Done:", "Nothing new"]
        if actionPrefixes.contains(where: { statusMessage.hasPrefix($0) }) {
            return statusMessage
        }
        if statusMessage.contains("sources compiled") || statusMessage.contains("articles updated") {
            return statusMessage
        }
        return makeOllamaStatusLine()
    }

    func makeOllamaStatusLine() -> String {
        let model = settings.ollamaModel
        switch ollamaStatus {
        case .connected:
            return "Ollama ready · \(model)"
        case .checking:
            return "Checking Ollama…"
        case .modelMissing:
            return "Model missing: \(model)"
        case .unknown:
            return "Ollama · \(model)"
        case .ollamaNotRunning, .noModelsInstalled, .failed:
            return ollamaStatus.label
        }
    }

    func setAppearance(_ appearance: AppAppearance) {
        var next = settings
        next.appearance = appearance
        settings = next
        applyAppearance()
    }

    func applyAppearance() {
        settings.appearance.applyToApp()
        appearanceEpoch &+= 1
        NotificationCenter.default.post(
            name: .rawDropAppearanceDidChange,
            object: settings.appearance
        )
    }

    func refreshOllama() async {
        isRefreshingModels = true
        ollamaStatus = .checking
        statusMessage = makeOllamaStatusLine()
        applyOllamaConfig()
        do {
            availableModels = try await ollama.listModels()
            ollamaStatus = await ollama.checkConnection(expectedModel: settings.ollamaModel)
            statusMessage = makeOllamaStatusLine()
        } catch {
            availableModels = []
            ollamaStatus = .ollamaNotRunning
            statusMessage = makeOllamaStatusLine()
        }
        isRefreshingModels = false
    }

    func testConnectivity() async {
        isTestingConnection = true
        applyOllamaConfig()
        let result = await ollama.testConnectivity(expectedModel: settings.ollamaModel)
        lastConnectionTest = result
        if result.ok {
            ollamaStatus = .connected
            do {
                availableModels = try await ollama.listModels()
            } catch {
                // keep previous list
            }
            // Still show the *selected* model in the main window, not only count
            statusMessage = "Ollama ready · \(settings.ollamaModel)"
        } else if result.title.localizedCaseInsensitiveContains("model missing") {
            ollamaStatus = .modelMissing(settings.ollamaModel)
            statusMessage = makeOllamaStatusLine()
        } else if result.title.localizedCaseInsensitiveContains("Cannot reach") {
            ollamaStatus = .ollamaNotRunning
            statusMessage = result.title
        } else if result.title.localizedCaseInsensitiveContains("no models") {
            ollamaStatus = .noModelsInstalled
            statusMessage = result.title
        } else {
            ollamaStatus = .failed(result.title)
            statusMessage = result.title
        }
        isTestingConnection = false
    }

    /// Capture whatever is on the pasteboard: files, URLs, images, HTML, text.
    func ingestClipboard() async {
        guard !isIngestingPaste else { return }
        isIngestingPaste = true
        defer { isIngestingPaste = false }

        let pb = NSPasteboard.general
        var count = 0

        do {
            // 1) File / remote URLs
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: false
            ]) as? [URL], !urls.isEmpty {
                for url in urls {
                    try await ingestAnyURL(url)
                    count += 1
                }
                finishPaste(count: count)
                return
            }

            // 2) Images
            if let image = NSImage(pasteboard: pb),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let name = "paste-\(timestamp()).png"
                let result = try IngestService.ingestData(png, preferredName: name, settings: settings)
                recentIngests.insert(result.destination.lastPathComponent, at: 0)
                count = 1
                finishPaste(count: count)
                return
            }

            // 3) HTML fragment
            if let html = pb.string(forType: .html)
                ?? pb.string(forType: NSPasteboard.PasteboardType("public.html")) {
                let name = "paste-\(timestamp()).html"
                let result = try IngestService.ingestText(html, preferredName: name, settings: settings)
                recentIngests.insert(result.destination.lastPathComponent, at: 0)
                count = 1
                finishPaste(count: count)
                return
            }

            // 4) Plain text — URL or note
            if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !str.isEmpty {
                if let url = normalizedHTTPURL(str) {
                    try await ingestAnyURL(url)
                    count = 1
                } else if HTMLTextExtractor.looksLikeHTML(string: str) {
                    let name = "paste-\(timestamp()).html"
                    let result = try IngestService.ingestText(str, preferredName: name, settings: settings)
                    recentIngests.insert(result.destination.lastPathComponent, at: 0)
                    count = 1
                } else {
                    let name = "paste-\(timestamp()).md"
                    let result = try IngestService.ingestText(str + "\n", preferredName: name, settings: settings)
                    recentIngests.insert(result.destination.lastPathComponent, at: 0)
                    count = 1
                }
                finishPaste(count: count)
                return
            }

            statusMessage = "Clipboard empty — nothing to capture"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func finishPaste(count: Int) {
        if recentIngests.count > 8 {
            recentIngests = Array(recentIngests.prefix(8))
        }
        if count > 0 {
            lastIngestMessage = count == 1
                ? "Captured 1 item from paste"
                : "Captured \(count) items from paste"
            statusMessage = lastIngestMessage ?? statusMessage
        }
        refreshPendingCaptures()
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    func ingestDroppedProviders(_ providers: [NSItemProvider]) async {
        var count = 0
        defer { refreshPendingCaptures() }
        for provider in providers {
            do {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let url = try await loadURL(from: provider, type: UTType.fileURL.identifier)
                    try await ingestAnyURL(url)
                    count += 1
                } else if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                    // Some apps drop HTML content without a file URL — save as .html
                    if let data = try await loadData(from: provider, type: UTType.html.identifier) {
                        let name = "dropped-\(Int(Date().timeIntervalSince1970)).html"
                        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                        try data.write(to: temp)
                        let result = try IngestService.ingestFile(at: temp, settings: settings)
                        recentIngests.insert(result.destination.lastPathComponent, at: 0)
                        try? FileManager.default.removeItem(at: temp)
                        count += 1
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let url = try await loadURL(from: provider, type: UTType.url.identifier)
                    try await ingestAnyURL(url)
                    count += 1
                } else if provider.canLoadObject(ofClass: URL.self) {
                    let url = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                        _ = provider.loadObject(ofClass: URL.self) { url, error in
                            if let error { cont.resume(throwing: error); return }
                            if let url { cont.resume(returning: url) }
                            else { cont.resume(throwing: IngestError.emptyDrop) }
                        }
                    }
                    try await ingestAnyURL(url)
                    count += 1
                } else if provider.canLoadObject(ofClass: String.self) {
                    let text = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                        _ = provider.loadObject(ofClass: String.self) { str, error in
                            if let error { cont.resume(throwing: error); return }
                            if let str { cont.resume(returning: str) }
                            else { cont.resume(throwing: IngestError.emptyDrop) }
                        }
                    }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = normalizedHTTPURL(trimmed) {
                        try await ingestAnyURL(url)
                        count += 1
                    } else if HTMLTextExtractor.looksLikeHTML(string: trimmed) {
                        let name = "dropped-\(Int(Date().timeIntervalSince1970)).html"
                        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                        try trimmed.write(to: temp, atomically: true, encoding: .utf8)
                        let result = try IngestService.ingestFile(at: temp, settings: settings)
                        recentIngests.insert(result.destination.lastPathComponent, at: 0)
                        try? FileManager.default.removeItem(at: temp)
                        count += 1
                    }
                }
            } catch {
                lastIngestMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }

        if recentIngests.count > 8 {
            recentIngests = Array(recentIngests.prefix(8))
        }
        if count > 0 {
            lastIngestMessage = count == 1
                ? "Copied 1 item into raw/"
                : "Copied \(count) items into raw/"
            statusMessage = lastIngestMessage ?? statusMessage
        }
    }

    func ingestFileURLs(_ urls: [URL]) {
        var count = 0
        defer { refreshPendingCaptures() }
        for url in urls {
            do {
                if url.isFileURL {
                    let result = try IngestService.ingestFile(at: url, settings: settings)
                    recentIngests.insert(result.destination.lastPathComponent, at: 0)
                    count += 1
                } else {
                    Task {
                        do {
                            let result = try await IngestService.ingestURL(url.absoluteString, settings: settings)
                            recentIngests.insert(result.destination.lastPathComponent, at: 0)
                            statusMessage = "Fetched \(result.destination.lastPathComponent)"
                            refreshPendingCaptures()
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
        if recentIngests.count > 8 {
            recentIngests = Array(recentIngests.prefix(8))
        }
        if count > 0 {
            lastIngestMessage = count == 1 ? "Copied 1 item into raw/" : "Copied \(count) items into raw/"
            statusMessage = lastIngestMessage ?? statusMessage
        }
    }

    func compile() async {
        guard !isCompiling else { return }
        isCompiling = true
        compilePhase = .preparing
        statusMessage = "Compiling…"
        applyOllamaConfig()

        do {
            let outcome = try await CompileService.run(
                settings: settings,
                ollama: ollama
            ) { [weak self] phase in
                self?.compilePhase = phase
                if let text = phase.progressText {
                    self?.statusMessage = text
                }
            }
            statusMessage = outcome.message
        } catch {
            compilePhase = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }

        isCompiling = false
        refreshPendingCaptures()
    }

    func openSettings() {
        SettingsWindowController.shared.show(appState: self)
    }

    // MARK: - Private

    private func ingestAnyURL(_ url: URL) async throws {
        if url.isFileURL {
            let result = try IngestService.ingestFile(at: url, settings: settings)
            recentIngests.insert(result.destination.lastPathComponent, at: 0)
        } else {
            let result = try await IngestService.ingestURL(url.absoluteString, settings: settings)
            recentIngests.insert(result.destination.lastPathComponent, at: 0)
        }
    }

    private func loadURL(from provider: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data,
                          let path = String(data: data, encoding: .utf8) {
                    if let url = URL(string: path) {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(returning: URL(fileURLWithPath: path))
                    }
                } else if let str = item as? String {
                    if let url = URL(string: str) {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(returning: URL(fileURLWithPath: str))
                    }
                } else {
                    cont.resume(throwing: IngestError.emptyDrop)
                }
            }
        }
    }

    private func loadData(from provider: NSItemProvider, type: String) async throws -> Data? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let data = item as? Data {
                    cont.resume(returning: data)
                } else if let str = item as? String {
                    cont.resume(returning: Data(str.utf8))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func normalizedHTTPURL(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow bare domains with scheme missing only if clearly pasted as URL-like
        if !s.hasPrefix("http://"), !s.hasPrefix("https://") {
            if s.contains(".") && !s.contains(" ") {
                s = "https://" + s
            } else {
                return nil
            }
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}
