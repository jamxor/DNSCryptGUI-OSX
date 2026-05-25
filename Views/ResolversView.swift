import SwiftUI

struct ResolversView: View {
    @EnvironmentObject var state: AppState
    @State private var selection = Set<Resolver.ID>()
    
    /// Limit search field buffer to 128 chars
    private static let searchQueryMaxLength = 128

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            Table(state.filteredResolvers, selection: $selection) {
                TableColumn("Name") { r in
                    HStack {
                        Image(systemName: r.protocol.symbol).foregroundStyle(.tint)
                        Text(r.name).monospaced()
                    }
                }
                TableColumn("Protocol") { r in
                    Text(r.protocol.label)
                }
                .width(min: 120, ideal: 140)
                TableColumn("Flags") { r in
                    HStack(spacing: 6) {
                        if r.dnssec  { flag("DNSSEC",   .blue) }
                        if r.noLog   { flag("No-Log",   .green) }
                        if r.noFilter { flag("No-Filter", .orange) }
                    }
                }
                .width(min: 160, ideal: 200)
                TableColumn("Description") { r in
                    Text(r.description).lineLimit(2).foregroundStyle(.secondary)
                }
            }
            Divider()
            actionBar
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search by name or description", text: Binding(
                    get: { state.searchQuery },
                    set: { state.searchQuery = String($0.prefix(Self.searchQueryMaxLength)) }
                ))
                .textFieldStyle(.plain)
                Spacer()
                Text("\(state.filteredResolvers.count) of \(state.allResolvers.count) servers available")
                    .foregroundStyle(.secondary).font(.caption)
                Button { Task { await state.loadResolvers() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            HStack(spacing: 8) {
                ForEach([DNSProtocol.dnscrypt, .doh, .odohTarget, .dnscryptRelay, .odohRelay, .plainDNS, .doq, .dot], id: \.self) { p in
                    Toggle(isOn: Binding(
                        get: { state.protocolFilter.contains(p) },
                        set: { on in
                            if on { state.protocolFilter.insert(p) }
                            else  { state.protocolFilter.remove(p) }
                        }
                    )) {
                        Label(p.label, systemImage: p.symbol)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
    }

    private var actionBar: some View {
        HStack {
            Button("Select all visible") {
                selection = Set(state.filteredResolvers.map(\.id))
            }
            Button("Clear selection") { selection.removeAll() }
            Spacer()
            if let cfg = state.currentConfig {
                Text(cfg.isAutoSelect ? "Currently: auto-select" : "Currently: \(cfg.serverNames.count) pinned")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Auto-select") {
                Task { await state.enableAutoSelect() }
            }
            Button("Apply selection") {
                let picked = state.filteredResolvers.filter { selection.contains($0.id) }.map(\.name)
                Task { await state.applyResolverSelection(picked) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.isEmpty)
        }
        .padding(12)
    }

    @ViewBuilder
    private func flag(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
