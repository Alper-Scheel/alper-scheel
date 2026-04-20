import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API Key", text: $coordinator.apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Uses gpt-4o-mini-transcribe by default and gpt-4o-mini for polite rewrite.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Auto-paste after transcription", isOn: $coordinator.autoPaste)
                Toggle("Enable polite rewrite mode", isOn: $coordinator.rewriteEnabled)
            }

            Section("Live State") {
                LabeledContent("Status", value: coordinator.status.rawValue)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last transcript")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $coordinator.lastTranscript)
                        .font(.body.monospaced())
                        .frame(minHeight: 80)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last rewritten text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $coordinator.lastRewrittenText)
                        .font(.body.monospaced())
                        .frame(minHeight: 80)
                }
            }

            Section("Hotkeys") {
                Text("Standard hold: Control + Option (hold)")
                Text("Standard toggle: Control + Option (double press within 350ms)")
                Text("Polite hold: Option + Command (hold)")
                Text("Polite toggle: Option + Command (double press within 350ms)")
            }

            Section {
                Button("Quit app") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(.red)
            }
        }
        .padding()
    }
}
