import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            LabeledContent("Global hotkey") {
                Text("Option + Space")
            }

            Toggle("Start pinned (always on top)", isOn: $settings.startPinned)

            Divider()

            Text("Obsidian export")
                .font(.headline)

            TextField("CLI executable path", text: $settings.obsidianCLIPath)

            TextField("CLI arguments (use {header})", text: $settings.obsidianCLIArgs)

            TextField("Daily note header", text: $settings.dailyHeader)

            LabeledContent("In-app shortcuts") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cmd + Return → Export")
                    Text("Cmd + P → Pin/Unpin")
                    Text("Cmd + , → Settings")
                }
            }
        }
        .padding(16)
        .frame(width: 540)
    }
}
