import SwiftUI

struct ConfigEditorView: View {
    @EnvironmentObject var state: AppState
    @State private var text: String = ""
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.config.configPath)
                    .font(.caption).monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Revert") { load() }
                Button("Save & restart") {
                    Task {
                        await state.saveConfig(text)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty)
            }
            .padding(12)
            Divider()
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { if !loaded { load() } }
        }
    }

    private func load() {
        if let cfg = try? state.config.load() {
            text = cfg.rawText
        } else {
            text = "# dnscrypt-proxy.toml not found at \(state.config.configPath)\n# Install dnscrypt-proxy via Homebrew first."
        }
        loaded = true
    }
}
