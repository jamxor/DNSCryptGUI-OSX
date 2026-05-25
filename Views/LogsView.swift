import SwiftUI

struct LogsView: View {
    @EnvironmentObject var state: AppState
    @State private var autoscroll = true
    @State private var filter = ""

    var filtered: [String] {
        guard !filter.isEmpty else { return state.logLines }
        let q = filter.lowercased()
        return state.logLines.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar row: source picker, file path, filter, autoscroll, clear.
            HStack(spacing: 12) {
                Picker("Source", selection: $state.logSource) {
                    ForEach(LogSource.allCases) { src in
                        Text(src.label).tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: state.logSource) { newValue in
                    state.switchLogSource(to: newValue)
                }

                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                    Text(state.log.logPath(for: state.logSource) ?? "(not configured)")
                        .font(.caption).monospaced().foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }

                Spacer(minLength: 8)

                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Toggle("Auto-scroll", isOn: $autoscroll).toggleStyle(.switch)
                Button("Clear view") { state.logLines.removeAll() }
            }
            .padding(12)
            Divider()

            // The log itself.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 1)
                                .background(idx % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                                .id(idx)
                        }
                    }
                }
                .onChange(of: filtered.count) { newCount in
                    if autoscroll, newCount > 0 {
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}
