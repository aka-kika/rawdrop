import SwiftUI
import AppKit

@main
struct RawDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings are opened via SettingsWindowController (menu-bar accessory apps
        // cannot reliably use the SwiftUI Settings scene + showSettingsWindow:).
        // Keep a minimal Settings scene so ⌘, still has a target when regular.
        Settings {
            SettingsView()
                .environment(appDelegate.appState)
                .frame(minWidth: 480, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.appState.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.applyAppearance()
        let controller = StatusItemController(appState: appState)
        controller.start()
        statusController = controller
        Task {
            await appState.refreshOllama()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
