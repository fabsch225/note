import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private lazy var appState = AppState(settings: settingsStore)

    private var noteWindowController: NoteWindowController?
    private var settingsWindowController: SettingsWindowController?

    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        noteWindowController = NoteWindowController(appState: appState)
        settingsWindowController = SettingsWindowController(settings: settingsStore)

        hotKeyManager = HotKeyManager(
            keyCode: settingsStore.globalHotKeyKeyCode,
            modifiers: settingsStore.globalHotKeyModifiers
        ) { [weak self] in
            self?.toggleNoteWindow()
        }
        hotKeyManager?.start()

        // Start hidden; user toggles via global hotkey.
        noteWindowController?.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.stop()
    }

    func toggleNoteWindow() {
        guard let noteWindowController else { return }

        if !noteWindowController.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            noteWindowController.show()
            return
        }

        // If the window is visible but not active (user clicked elsewhere), the hotkey
        // should bring it forward instead of hiding it.
        if noteWindowController.isKeyOrMain {
            noteWindowController.hide()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            noteWindowController.bringToFront()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
