import SwiftUI

@main
struct NotePopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // We manage windows manually via AppDelegate/NSWindowController.
        // Provide an empty Settings scene so SwiftUI runtime is initialized.
        Settings {
            EmptyView()
        }
    }
}
