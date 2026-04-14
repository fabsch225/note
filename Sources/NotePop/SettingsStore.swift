import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let startPinned = "startPinned"
        static let obsidianCLIPath = "obsidianCLIPath"
        static let obsidianCLIArgs = "obsidianCLIArgs"
        static let dailyHeader = "dailyHeader"
    }

    @Published var startPinned: Bool {
        didSet { defaults.set(startPinned, forKey: Keys.startPinned) }
    }

    /// Executable name or full path, e.g. `obsidian` or `/opt/homebrew/bin/obsidian`.
    @Published var obsidianCLIPath: String {
        didSet { defaults.set(obsidianCLIPath, forKey: Keys.obsidianCLIPath) }
    }

    /// Arguments string, split like a shell (quotes supported). You can use `{header}` placeholder.
    @Published var obsidianCLIArgs: String {
        didSet { defaults.set(obsidianCLIArgs, forKey: Keys.obsidianCLIArgs) }
    }

    /// Header text to insert under in the daily note.
    @Published var dailyHeader: String {
        didSet { defaults.set(dailyHeader, forKey: Keys.dailyHeader) }
    }

    // Global hotkey: Option+Space by default.
    let globalHotKeyKeyCode: UInt32 = 49
    let globalHotKeyModifiers: HotKeyModifiers = [.option]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.startPinned = defaults.object(forKey: Keys.startPinned) as? Bool ?? false
        self.obsidianCLIPath = defaults.string(forKey: Keys.obsidianCLIPath) ?? ""
        self.obsidianCLIArgs = defaults.string(forKey: Keys.obsidianCLIArgs) ?? ""
        self.dailyHeader = defaults.string(forKey: Keys.dailyHeader) ?? "Quick Notes"
    }
}
