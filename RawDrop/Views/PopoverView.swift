import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    @Environment(AppState.self) private var appState
    var onOpenSettings: (() -> Void)?
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            CaptureZoneView(isTargeted: isTargeted, isPasting: appState.isIngestingPaste)
                .frame(height: 84)
                .onDrop(
                    of: [.fileURL, .url, .html, .image, .plainText],
                    isTargeted: $isTargeted
                ) { providers in
                    Task { await appState.ingestDroppedProviders(providers) }
                    return true
                }

            // Compile stays fixed under the drop zone so the list never shoves it down
            compileSection

            captureListSection

            Spacer(minLength: 0)

            footer
        }
        .padding(14)
        .frame(width: 340, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appState.settings.appearance.colorScheme)
        .id(appState.appearanceEpoch)
        .onAppear {
            appState.refreshPendingCaptures()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RawDrop")
                    .font(.headline)
                Text(appState.displayStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help("Selected model: \(appState.settings.ollamaModel)")
            }
            Spacer()
            statusDot
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .help(appState.ollamaStatus.label)
    }

    private var dotColor: Color {
        switch appState.ollamaStatus {
        case .connected: return .green
        case .checking, .unknown: return .secondary
        case .ollamaNotRunning, .noModelsInstalled, .modelMissing, .failed: return .orange
        }
    }

    private var compileSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await appState.compile() }
            } label: {
                HStack {
                    if appState.isCompiling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(compileButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(appState.isCompiling || (appState.pendingCaptures.isEmpty && !appState.isCompiling))

            if let progress = appState.compilePhase.progressText, appState.isCompiling || isTerminal(appState.compilePhase) {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var compileButtonTitle: String {
        if appState.isCompiling { return "Compiling…" }
        let n = appState.pendingCaptures.count
        if n == 0 { return "Compile" }
        return n == 1 ? "Compile 1 source" : "Compile \(n) sources"
    }

    /// List under Compile: pending (full opacity) then compiled (50% opacity).
    private var captureListSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(listTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !appState.pendingCaptures.isEmpty {
                    Text("\(appState.pendingCaptures.count) pending")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !appState.compiledCaptures.isEmpty {
                    Text("\(appState.compiledCaptures.count) done")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if appState.captureList.isEmpty {
                Text("Nothing captured yet — drop or paste above.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.captureList) { item in
                            captureRow(item)
                        }
                    }
                }
                .frame(maxHeight: 148)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var listTitle: String {
        let n = appState.captureList.count
        if n == 0 { return "Captures" }
        return n == 1 ? "1 capture" : "\(n) captures"
    }

    private func captureRow(_ item: CaptureItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: iconName(for: item.filename))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !item.detailLabel.isEmpty {
                    Text(item.detailLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .opacity(item.isCompiled ? 0.5 : 1.0)
    }

    private func iconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        case "md", "txt", "markdown": return "doc.text"
        default: return "doc"
        }
    }

    private var footer: some View {
        HStack {
            Text(appState.makeOllamaStatusLine())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .help(appState.settings.ollamaModel)

            Spacer()

            Button("Settings…") {
                if let onOpenSettings {
                    onOpenSettings()
                } else {
                    appState.openSettings()
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func isTerminal(_ phase: CompilePhase) -> Bool {
        switch phase {
        case .finished, .nothingNew, .failed: return true
        default: return false
        }
    }
}

struct CaptureZoneView: View {
    var isTargeted: Bool
    var isPasting: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                )

            VStack(spacing: 4) {
                if isPasting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Capturing…")
                        .font(.subheadline.weight(.medium))
                } else {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    Text("Drop or paste")
                        .font(.subheadline.weight(.medium))
                    Text("Files, links, images, HTML — ⌘V")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    PopoverView()
        .environment(AppState())
}
