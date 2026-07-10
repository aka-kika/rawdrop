import AppKit
import SwiftUI

/// Dedicated settings window — SwiftUI `Settings` scene is unreliable for LSUIElement / accessory apps.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private weak var appState: AppState?
    private var appearanceObserver: NSObjectProtocol?

    override init() {
        super.init()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .rawDropAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncAppearance()
            }
        }
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    func show(appState: AppState) {
        self.appState = appState

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "RawDrop Settings"
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("RawDropSettingsWindow")
            self.window = window
        }

        rebuildContent()
        syncAppearance()

        guard let window else { return }
        if window.frame.origin == .zero {
            window.center()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func rebuildContent() {
        guard let appState, let window else { return }
        let root = SettingsView()
            .environment(appState)
            .preferredColorScheme(appState.settings.appearance.colorScheme)
            .id(appState.appearanceEpoch)
            .frame(minWidth: 480, minHeight: 440)
        window.contentViewController = NSHostingController(rootView: root)
    }

    func syncAppearance() {
        guard let appState else { return }
        let appearance = appState.settings.appearance.nsAppearance
        // AppKit window chrome (titlebar, etc.)
        window?.appearance = appearance
        window?.contentView?.appearance = appearance
        window?.contentViewController?.view.appearance = appearance
        // Do not rebuild the hosting controller here — that would wipe unsaved form state.
        // SwiftUI recolors via preferredColorScheme bound to appState in SettingsView.
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
