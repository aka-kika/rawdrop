import Foundation
import AppKit
import SwiftUI

enum OllamaEndpointPreset: String, Codable, CaseIterable, Identifiable {
    case local
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Local Ollama"
        case .cloud: return "Ollama Cloud"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .local: return "http://localhost:11434"
        case .cloud: return "https://ollama.com"
        }
    }

    var helpText: String {
        switch self {
        case .local:
            return "Talks to Ollama on this Mac. No API key needed."
        case .cloud:
            return "Talks to https://ollama.com with an API key from ollama.com/settings/keys."
        }
    }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// AppKit appearance for windows / popovers (nil = follow system).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func applyToApp() {
        NSApp.appearance = nsAppearance
    }
}

extension Notification.Name {
    static let rawDropAppearanceDidChange = Notification.Name("rawDropAppearanceDidChange")
}

struct AppSettings: Codable, Equatable {
    var knowledgeRootPath: String
    var ollamaPreset: OllamaEndpointPreset
    var ollamaBaseURL: String
    var ollamaModel: String
    var appearance: AppAppearance

    static let defaults = AppSettings(
        knowledgeRootPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Knowledge", isDirectory: true)
            .path,
        ollamaPreset: .local,
        ollamaBaseURL: OllamaEndpointPreset.local.defaultBaseURL,
        ollamaModel: "ministral-3:latest",
        appearance: .system
    )

    var knowledgeRootURL: URL {
        URL(fileURLWithPath: knowledgeRootPath, isDirectory: true)
    }

    var rawURL: URL { knowledgeRootURL.appendingPathComponent("raw", isDirectory: true) }
    var wikiURL: URL { knowledgeRootURL.appendingPathComponent("wiki", isDirectory: true) }
    var outputsURL: URL { knowledgeRootURL.appendingPathComponent("outputs", isDirectory: true) }

    enum CodingKeys: String, CodingKey {
        case knowledgeRootPath, ollamaPreset, ollamaBaseURL, ollamaModel, appearance
    }

    init(
        knowledgeRootPath: String,
        ollamaPreset: OllamaEndpointPreset,
        ollamaBaseURL: String,
        ollamaModel: String,
        appearance: AppAppearance
    ) {
        self.knowledgeRootPath = knowledgeRootPath
        self.ollamaPreset = ollamaPreset
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModel = ollamaModel
        self.appearance = appearance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        knowledgeRootPath = try c.decodeIfPresent(String.self, forKey: .knowledgeRootPath)
            ?? AppSettings.defaults.knowledgeRootPath
        var base = try c.decodeIfPresent(String.self, forKey: .ollamaBaseURL)
            ?? AppSettings.defaults.ollamaBaseURL
        if base == "http://127.0.0.1:11434" {
            base = "http://localhost:11434"
        }
        ollamaBaseURL = base
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel)
            ?? AppSettings.defaults.ollamaModel
        if let preset = try c.decodeIfPresent(OllamaEndpointPreset.self, forKey: .ollamaPreset) {
            ollamaPreset = preset
        } else if ollamaBaseURL.contains("ollama.com") {
            ollamaPreset = .cloud
        } else {
            ollamaPreset = .local
        }
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
    }
}

enum SettingsStore {
    private static let key = "rawdrop.settings"

    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .defaults
        }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
