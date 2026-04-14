import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var noteText: String
    @Published var isPinned: Bool

    let settings: SettingsStore
    let exporter: ObsidianExporter

    init(settings: SettingsStore) {
        self.settings = settings
        self.noteText = ""
        self.isPinned = settings.startPinned
        self.exporter = ObsidianExporter(settings: settings)
    }
}
