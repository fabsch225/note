import AppKit
import Combine
import SwiftUI

@MainActor
final class NoteWindowController {
    private let appState: AppState

    private(set) var window: NSWindow
    private var localKeyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    var isVisible: Bool { window.isVisible }
    var isKeyOrMain: Bool { window.isKeyWindow || window.isMainWindow }

    init(appState: AppState) {
        self.appState = appState

        let contentView = NoteView(appState: appState)
        let hosting = NSHostingView(rootView: contentView)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        hosting.autoresizingMask = [.width, .height]

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.alphaValue = 1.0
        applyWindowBackgroundOpacity(appState.settings.windowOpacity)
        window.level = appState.isPinned ? .floating : .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 320, height: 180)

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.contentView = hosting
        window.center()

        installKeyMonitor()

        appState.settings.$windowOpacity
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                self?.applyWindowBackgroundOpacity(newValue)
            }
            .store(in: &cancellables)
    }

    private func applyWindowBackgroundOpacity(_ opacity: Double) {
        let clamped = min(max(opacity, 0.0), 1.0)
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(clamped)
    }

    func show() {
        applyPinnedState()
        window.makeKeyAndOrderFront(nil)
        focusEditor()
    }

    func bringToFront() {
        applyPinnedState()
        window.makeKeyAndOrderFront(nil)
        focusEditor()
    }

    func hide() {
        window.orderOut(nil)
    }

    private func applyPinnedState() {
        window.level = appState.isPinned ? .floating : .normal
    }

    private func installKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.window.isKeyWindow else { return event }

            // Cmd+Return: export
            if event.modifierFlags.contains(.command), event.keyCode == 36 {
                Task { @MainActor in
                    await self.exportNote()
                }
                return nil
            }

            // Cmd+P: pin/unpin
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "p" {
                Task { @MainActor in
                    self.togglePinned()
                }
                return nil
            }

            // Cmd+, : settings
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
                Task { @MainActor in
                    self.showSettings()
                }
                return nil
            }

            return event
        }
    }

    private func focusEditor() {
        // Ask the SwiftUI view to focus its editor.
        NotificationCenter.default.post(name: .notePopFocusEditor, object: nil)
    }

    @MainActor
    private func togglePinned() {
        appState.isPinned.toggle()
        applyPinnedState()
    }

    @MainActor
    private func showSettings() {
        NotificationCenter.default.post(name: .notePopShowSettings, object: nil)
    }

    @MainActor
    private func exportNote() async {
        if appState.isExporting { return }
        appState.isExporting = true
        let start = CFAbsoluteTimeGetCurrent()
        do {
            try await appState.exporter.export(noteText: appState.noteText)
            appState.noteText = ""
        } catch {
            NSAlert(error: error).runModal()
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let minimum: Double = 0.5
        if elapsed < minimum {
            let remaining = minimum - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        appState.isExporting = false
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let window: NSWindow

    init(settings: SettingsStore) {
        self.settings = settings

        let view = SettingsView(settings: settings)
        let hosting = NSHostingView(rootView: view)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        hosting.autoresizingMask = [.width, .height]

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()

        NotificationCenter.default.addObserver(forName: .notePopShowSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.show()
            }
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let notePopFocusEditor = Notification.Name("NotePop.FocusEditor")
    static let notePopShowSettings = Notification.Name("NotePop.ShowSettings")
}
