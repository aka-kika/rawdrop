import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var knowledgePath: String = ""
    @State private var preset: OllamaEndpointPreset = .local
    @State private var ollamaURL: String = ""
    @State private var model: String = ""
    @State private var apiKey: String = ""
    @State private var appearance: AppAppearance = .system
    @State private var saveNote: String?
    @State private var keySaveError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at Login", isOn: Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.setLaunchAtLogin($0) }
                ))
                if let msg = appState.launchAtLoginMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Uses macOS Login Items. Prefer running from /Applications for reliable registration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, newValue in
                    // Apply immediately — do not wait for Save
                    appState.setAppearance(newValue)
                }
                Text("System follows macOS. Light / Dark force the popover and settings windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Knowledge vault") {
                TextField("Knowledge root path", text: $knowledgePath)
                Text("Must contain raw/, wiki/, outputs/.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Use Default") {
                        knowledgePath = AppSettings.defaults.knowledgeRootPath
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: knowledgePath)])
                    }
                }
            }

            Section("Ollama") {
                Picker("Endpoint", selection: $preset) {
                    ForEach(OllamaEndpointPreset.allCases) { p in
                        Text(p.title).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: preset) { _, newValue in
                    if ollamaURL == OllamaEndpointPreset.local.defaultBaseURL
                        || ollamaURL == "http://127.0.0.1:11434"
                        || ollamaURL == OllamaEndpointPreset.cloud.defaultBaseURL
                        || ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ollamaURL = newValue.defaultBaseURL
                    }
                }

                TextField("Base URL", text: $ollamaURL)
                    .textFieldStyle(.roundedBorder)
                    .help("Local default: http://localhost:11434")

                if preset == .cloud || ollamaURL.contains("ollama.com") {
                    SecureField("API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Keychain only. Create at ollama.com/settings/keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Dropdown — full installed list
                if appState.availableModels.isEmpty {
                    TextField("Model", text: $model)
                        .textFieldStyle(.roundedBorder)
                    Text("Refresh models after Ollama is reachable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: $model) {
                        ForEach(appState.availableModels) { m in
                            Text(m.name).tag(m.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model) { _, newValue in
                        // Persist immediately so the main popover shows the real model
                        appState.setOllamaModel(newValue)
                    }
                    .onChange(of: appState.availableModels) { _, models in
                        if !models.contains(where: { $0.name == model }), let first = models.first {
                            model = first.name
                            appState.setOllamaModel(first.name)
                        }
                    }

                    recommendedModelsSection
                }

                HStack {
                    Button {
                        applyToState()
                        Task { await appState.refreshOllama() }
                    } label: {
                        if appState.isRefreshingModels {
                            ProgressView().controlSize(.small)
                            Text("Refreshing…")
                        } else {
                            Text("Refresh models")
                        }
                    }
                    .disabled(appState.isRefreshingModels || appState.isTestingConnection)

                    Button {
                        applyToState()
                        Task { await appState.testConnectivity() }
                    } label: {
                        if appState.isTestingConnection {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        } else {
                            Text("Test connectivity")
                        }
                    }
                    .disabled(appState.isTestingConnection)

                    Spacer()
                    statusBadge
                }

                if let test = appState.lastConnectionTest {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(test.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(test.ok ? Color.green : Color.orange)
                        Text(test.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Button("Save") {
                    let seeded = applyToState()
                    saveNote = seeded ? "Saved · vault ready" : "Saved"
                    keySaveError = nil
                }
                .keyboardShortcut(.defaultAction)

                if let saveNote {
                    Text(saveNote).font(.caption).foregroundStyle(.secondary)
                }
                if let keySaveError {
                    Text(keySaveError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 420)
        .preferredColorScheme(appState.settings.appearance.colorScheme)
        .onAppear {
            loadFromState()
            appState.refreshLaunchAtLoginStatus()
        }
    }

    /// Recommended picks filtered from *installed* models only.
    private var recommendedModelsSection: some View {
        let picks = ModelRecommendations.recommended(from: appState.availableModels)
        return Group {
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recommended")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let top = picks.first {
                            Button("Use top pick") {
                                selectModel(top.model.name)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }

                    Text("From your installed models — best for compile / wiki synthesis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(picks) { pick in
                        Button {
                            selectModel(pick.model.name)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: model == pick.model.name
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .foregroundStyle(model == pick.model.name ? Color.accentColor : .secondary)
                                    .font(.body)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(pick.model.name)
                                            .font(.body.weight(model == pick.model.name ? .semibold : .regular))
                                            .foregroundStyle(.primary)
                                        if pick.score >= 90 {
                                            Text("Best")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(pick.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if let size = pick.model.sizeLabel {
                                    Text(size)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func selectModel(_ name: String) {
        model = name
        appState.setOllamaModel(name)
        saveNote = "Model set to \(name)"
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(appState.ollamaStatus.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var dotColor: Color {
        switch appState.ollamaStatus {
        case .connected: return .green
        case .checking, .unknown: return .secondary
        default: return .orange
        }
    }

    private func loadFromState() {
        knowledgePath = appState.settings.knowledgeRootPath
        preset = appState.settings.ollamaPreset
        ollamaURL = appState.settings.ollamaBaseURL
        if ollamaURL == "http://127.0.0.1:11434" {
            ollamaURL = "http://localhost:11434"
        }
        model = appState.settings.ollamaModel
        appearance = appState.settings.appearance
        apiKey = OllamaSecrets.apiKey ?? ""
        saveNote = nil
        keySaveError = nil
    }

    /// Commits the edited fields into app state and seeds the Knowledge root's
    /// structure. Returns true if seeding created any new folders or the explainer.
    @discardableResult
    private func applyToState() -> Bool {
        var s = appState.settings
        s.knowledgeRootPath = knowledgePath.trimmingCharacters(in: .whitespacesAndNewlines)
        s.ollamaPreset = preset
        s.ollamaBaseURL = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        s.ollamaModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        s.appearance = appearance
        appState.settings = s

        // Create-if-missing scaffold (raw/ wiki/ outputs/ + RawDrop.md). Idempotent.
        let seeded = VaultSeeder.seed(settings: s).didSomething

        do {
            try OllamaSecrets.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            keySaveError = nil
        } catch {
            keySaveError = error.localizedDescription
        }

        appState.applyOllamaConfig()
        appState.applyAppearance()
        appState.syncOllamaStatusMessage()

        return seeded
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
