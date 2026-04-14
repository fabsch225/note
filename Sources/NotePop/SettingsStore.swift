import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let startPinned = "startPinned"
        static let dailyHeader = "dailyHeader"
        static let windowOpacity = "windowOpacity"
    }

    @Published var startPinned: Bool {
        didSet { defaults.set(startPinned, forKey: Keys.startPinned) }
    }

    /// Header text to insert under in the daily note.
    @Published var dailyHeader: String {
        didSet { defaults.set(dailyHeader, forKey: Keys.dailyHeader) }
    }

    /// Window opacity in the range 0.0...1.0.
    @Published var windowOpacity: Double {
        didSet { defaults.set(windowOpacity, forKey: Keys.windowOpacity) }
    }

    // Global hotkey: Option+Space by default.
    let globalHotKeyKeyCode: UInt32 = 49
    let globalHotKeyModifiers: HotKeyModifiers = [.option]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.startPinned = defaults.object(forKey: Keys.startPinned) as? Bool ?? false
        self.dailyHeader = defaults.string(forKey: Keys.dailyHeader) ?? "Quick Notes"
        // Keep opacity within the UI slider range so the window can't become "lost" (fully invisible).
        let minOpacity = 0.70
        let savedOpacity = defaults.object(forKey: Keys.windowOpacity) as? Double
        if let savedOpacity {
            let clamped = min(max(savedOpacity, minOpacity), 1.0)
            self.windowOpacity = clamped
            if clamped != savedOpacity {
                defaults.set(clamped, forKey: Keys.windowOpacity)
            }
        } else {
            self.windowOpacity = 1.0
        }
    }
}
