import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private var subtitleForTab: String {
        switch state.selectedTab {
        case .dashboard: return "DNSCryptGUI-OSX by HlinCore Security Team"
        case .resolvers: return "DNSCryptGUI-OSX by HlinCore Security Team"
        case .config: return "DNSCryptGUI-OSX by HlinCore Security Team"
        case .logs: return "DNSCryptGUI-OSX by HlinCore Security Team"
        case .settings: return "DNSCryptGUI-OSX by HlinCore Security Team"
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(MainTab.allCases, id: \.self, selection: $state.selectedTab) { tab in
                Label(tab.label, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch state.selectedTab {
                case .dashboard: DashboardView()
                case .resolvers: ResolversView()
                case .config:    ConfigEditorView()
                case .logs:      LogsView()
                case .settings:  SettingsView()
                }
            }
            
            .navigationTitle(state.selectedTab.label)
            .navigationSubtitle(subtitleForTab)
        }
        .alert("DNSCryptGUI", isPresented: Binding(
            get: { state.lastError != nil },
            set: { if !$0 { state.lastError = nil } }
        )) {
            Button("OK") { state.lastError = nil }
        } message: {
            Text(state.lastError ?? "")
        }
    }
}
