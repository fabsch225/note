import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            LabeledContent("Global hotkey") {
                Text("Option + Space")
            }

            Toggle("Start pinned (always on top)", isOn: $settings.startPinned)

            LabeledContent("Window opacity") {
                HStack(spacing: 12) {
                    Slider(value: $settings.windowOpacity, in: 0.70...1.00)
                        .frame(width: 220)
                    Text("\(Int((settings.windowOpacity * 100.0).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }

            Divider()

            Text("Obsidian export")
                .font(.headline)

            Text("Writes directly to your vault’s daily note (does not launch Obsidian).")
                .foregroundStyle(.secondary)

            TextField("Insert under header", text: $settings.dailyHeader)

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
