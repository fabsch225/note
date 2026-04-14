import AppKit
import SwiftUI

@MainActor
final class NoteWindowController {
    private let appState: AppState

    private(set) var window: NSWindow
    private var localKeyMonitor: Any?

    var isVisible: Bool { window.isVisible }

    init(appState: AppState) {
        self.appState = appState

        let contentView = NoteView(appState: appState)
        let hosting = NSHostingView(rootView: contentView)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.level = appState.isPinned ? .floating : .normal
        window.collectionBehavior = [.moveToActiveSpace]

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.contentView = hosting
        window.center()

        installKeyMonitor()
    }

    func show() {
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
        do {
            try await appState.exporter.export(noteText: appState.noteText)
        } catch {
            NSAlert(error: error).runModal()
        }
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
