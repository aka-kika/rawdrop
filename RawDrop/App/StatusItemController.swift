import AppKit
import SwiftUI

/// NSStatusItem bridge so files can be dropped on the menu bar icon itself.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let appState: AppState
    private var clickOutsideMonitor: Any?
    private var pasteKeyMonitor: Any?
    private var appearanceObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "RawDrop")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "RawDrop — drop or paste to capture"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let dropView = StatusDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onDropURLs = { [weak self] urls in
                self?.appState.ingestFileURLs(urls)
                self?.showPopover()
            }
            dropView.onDropURLString = { [weak self] string in
                Task { @MainActor in
                    guard let self else { return }
                    do {
                        let result = try await IngestService.ingestURL(string, settings: self.appState.settings)
                        self.appState.recentIngests.insert(result.destination.lastPathComponent, at: 0)
                        self.appState.statusMessage = "Fetched \(result.destination.lastPathComponent)"
                        self.showPopover()
                    } catch {
                        self.appState.statusMessage = error.localizedDescription
                    }
                }
            }
            button.addSubview(dropView)
        }

        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 340, height: 420)
        rebuildPopoverContent()
        syncPopoverAppearance()

        statusItem = item

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                if let window = event.window, window.title == "RawDrop Settings" {
                    return
                }
                self.popover.performClose(nil)
            }
        }

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .rawDropAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Popover has its own NSAppearance; force it + rebuild SwiftUI root.
                self?.syncPopoverAppearance()
                if self?.popover.isShown == true {
                    self?.rebuildPopoverContent()
                } else {
                    // Keep content ready for next open
                    self?.rebuildPopoverContentKeepingClosed()
                }
            }
        }
    }

    private func rebuildPopoverContentKeepingClosed() {
        let root = PopoverView(
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.appState.openSettings()
            }
        )
        .environment(appState)
        .preferredColorScheme(appState.settings.appearance.colorScheme)
        .id(appState.appearanceEpoch)
        popover.contentViewController = NSHostingController(rootView: root)
        syncPopoverAppearance()
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    /// Apply theme to the popover itself (does not inherit NSApp reliably).
    func syncPopoverAppearance() {
        popover.appearance = appState.settings.appearance.nsAppearance
        popover.contentViewController?.view.window?.appearance = appState.settings.appearance.nsAppearance
        popover.contentViewController?.view.appearance = appState.settings.appearance.nsAppearance
    }

    func rebuildPopoverContent() {
        let wasShown = popover.isShown
        let button = statusItem?.button
        rebuildPopoverContentKeepingClosed()

        // Keep open if it was already open when theme changed
        if wasShown, let button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            syncPopoverAppearance()
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            // Ensure header shows the model currently saved in settings
            appState.syncOllamaStatusMessage()
            appState.refreshPendingCaptures()
            rebuildPopoverContent()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            syncPopoverAppearance()
            beginPasteCapture()
        }
    }

    // MARK: - Paste capture while popover is open

    private func beginPasteCapture() {
        appState.isCaptureSurfaceActive = true
        endPasteCaptureMonitorsOnly()

        pasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }
            if let keyWindow = NSApp.keyWindow, keyWindow.title == "RawDrop Settings" {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command,
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                Task { @MainActor in
                    await self.appState.ingestClipboard()
                }
                return nil
            }
            return event
        }
    }

    private func endPasteCapture() {
        appState.isCaptureSurfaceActive = false
        endPasteCaptureMonitorsOnly()
    }

    private func endPasteCaptureMonitorsOnly() {
        if let pasteKeyMonitor {
            NSEvent.removeMonitor(pasteKeyMonitor)
            self.pasteKeyMonitor = nil
        }
    }

    func popoverDidShow(_ notification: Notification) {
        syncPopoverAppearance()
        beginPasteCapture()
    }

    func popoverDidClose(_ notification: Notification) {
        endPasteCapture()
    }
}

/// Transparent overlay that accepts file/URL drops on the status item.
final class StatusDropView: NSView {
    var onDropURLs: (([URL]) -> Void)?
    var onDropURLString: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            NSPasteboard.PasteboardType("public.url"),
            .tiff,
            .png,
            .string
        ])
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: false
        ]) as? [URL], !urls.isEmpty {
            let files = urls.filter(\.isFileURL)
            let remote = urls.filter { !$0.isFileURL }
            if !files.isEmpty {
                onDropURLs?(files)
            }
            for url in remote {
                onDropURLString?(url.absoluteString)
            }
            return true
        }
        if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           str.hasPrefix("http://") || str.hasPrefix("https://") {
            onDropURLString?(str)
            return true
        }
        return false
    }

    override func mouseUp(with event: NSEvent) {
        if let button = superview as? NSStatusBarButton {
            button.performClick(nil)
        } else {
            super.mouseUp(with: event)
        }
    }
}
