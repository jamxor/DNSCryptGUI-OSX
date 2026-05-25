import Foundation
import SwiftUI
import Combine
import ServiceManagement

enum SMAppServiceProxy {
    @available(macOS 13.5, *)
    static func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

/// App-wide observable state. Owns service objects, polls status, and publishes
/// to the SwiftUI views.
@MainActor
final class AppState: ObservableObject {
    // Services
    let helper = HelperClient()
    let brew = BrewService()
    let log = LogService()
    let resolvers = ResolverService()
    let loginItem = LaunchAtLoginService()
    // These three all use the helper, so they get the shared instance.
    lazy var proxy   = ProxyService(helper: helper)
    lazy var config  = ConfigService(helper: helper)
    lazy var network = NetworkService(helper: helper)

    // Published state
    @Published var status: ProxyStatus = .unknown
    @Published var isInstalled: Bool = false
    @Published var helperInstalled: Bool = false
    @Published var helperAwaitingApproval: Bool = false
    @Published var currentConfig: ProxyConfig?
    @Published var allResolvers: [Resolver] = []
    @Published var systemDNS: [String] = []
    @Published var launchAtLogin: Bool = false
    @Published var connectionCheck: ConnectionCheck = .unknown
    @Published var logLines: [String] = []
    @Published var logSource: LogSource = .server
    @Published var protocolFilter: Set<DNSProtocol> = Set(DNSProtocol.allCases)
    @Published var searchQuery: String = ""
    @Published var selectedTab: MainTab = .dashboard
    @Published var lastError: String?

    private var statusTimer: Timer?

    /// Called once when the main window first appears.
    func bootstrap() async {
        await installHelperIfNeeded()
        isInstalled = await brew.isInstalled()
        currentConfig = try? config.load()
        launchAtLogin = loginItem.isEnabled
        await refreshSystemDNS()
        await refreshStatus()
        await loadResolvers()
        startPolling()
        // LogService dispatches its callback on the main queue, but AppState
        // is @MainActor-isolated so still require a Task hop.
        startLogStream(for: logSource)
    }

    /// Tears down the current log tail (if any), clears the in-memory buffer
    /// the Logs view is bound to, and starts tailing the new source. Wired
    /// to LogsView's Picker so the user can flip between Server / Queries /
    /// NXDOMAIN without restarting the app.
    func switchLogSource(to newSource: LogSource) {
        logSource = newSource
        logLines.removeAll()
        startLogStream(for: newSource)
    }

    private func startLogStream(for source: LogSource) {
        log.start(source: source) { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logLines.append(line)
                if self.logLines.count > 2000 {
                    self.logLines.removeFirst(self.logLines.count - 2000)
                }
            }
        }
    }

    func startPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStatus()
                await self?.refreshSystemDNS()
            }
        }
    }

    func refreshStatus() async {
        status = await proxy.currentStatus()
        if status == .running {
            connectionCheck = await network.verifyDNSThroughProxy()
        } else {
            connectionCheck = .proxyNotRunning
        }
    }

    func refreshSystemDNS() async {
        systemDNS = (try? await network.currentDNSServers()) ?? []
    }

    // MARK: - Actions

    func start() async {
        do {
            try await proxy.start()
            await refreshStatus()
        } catch { lastError = "Start failed: \(error.localizedDescription)" }
    }

    func stop() async {
        do {
            try await proxy.stop()
            await refreshStatus()
        } catch { lastError = "Stop failed: \(error.localizedDescription)" }
    }

    func restart() async {
        do {
            try await proxy.restart()
            await refreshStatus()
        } catch { lastError = "Restart failed: \(error.localizedDescription)" }
    }

    func install() async {
        do {
            try await brew.installOrUpgrade()
            isInstalled = await brew.isInstalled()
        } catch { lastError = "Install failed: \(error.localizedDescription)" }
    }

    func setSystemDNSToProxy() async {
        do {
            // Set both loopback families so macOS uses whichever the active interface is
            try await network.setSystemDNS(to: ["127.0.0.1", "::1"])
            await refreshSystemDNS()
        } catch { lastError = "Set DNS failed: \(error.localizedDescription)" }
    }

    /// True when *every* configured DNS server is a loopback the proxy is listening on. A mixed list like ["8.8.8.8", "::1"] is NOT routed,
    /// macOS will send queries to 8.8.8.8 per its configured position in the list, leaking around dnscrypt-proxy. Empty list (DHCP defaults),
    /// is also not routed. Delegates to NetworkService so the dashboard, menu bar icon, and Settings status all read from the same rule book.
    var isRoutedThroughProxy: Bool {
        NetworkService.isAllLoopback(systemDNS)
    }
    
    var menuBarSymbol: String {
        switch status {
        case .running:
            return isRoutedThroughProxy
                ? "lock.shield.fill"
                : "point.3.connected.trianglepath.dotted"
        case .stopped:               return "lock.open"
        case .starting, .stopping:   return "hourglass"
        case .errored:               return "exclamationmark.shield.fill"
        case .unknown:               return "questionmark.circle"
        }
    }

    // MARK: - Helper install

    func installHelperIfNeeded() async {
        do {
            try helper.install()
            helperInstalled = true
            helperAwaitingApproval = false
        } catch HelperClient.HelperError.notApproved {
            // User needs to approve in System Settings. We DON'T raise
            // lastError here — the awaiting-approval state is already
            // surfaced by the Dashboard banner and the Settings status
            helperInstalled = false
            helperAwaitingApproval = true
        } catch {
            helperInstalled = false
            helperAwaitingApproval = false
            lastError = "Helper install failed: \(error.localizedDescription)"
        }
    }

    /// Read-only refresh of the helper's current SMAppService status.
    /// Never calls `register()` and never opens System Settings
    func refreshHelperStatus() async {
        guard #available(macOS 13.0, *) else { return }
        switch helper.status {
        case .enabled:
            helperInstalled = true
            helperAwaitingApproval = false
        case .requiresApproval:
            helperInstalled = false
            helperAwaitingApproval = true
        case .notRegistered, .notFound:
            // Either bootstrap hasn't run yet (in which case it'll set these flags itself)
            // or the user manually unregistered the helper
            break
        @unknown default:
            break
        }
    }

    func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppServiceProxy.openLoginItems()
        }
    }

    func clearSystemDNS() async {
        do {
            try await network.clearSystemDNS()
            await refreshSystemDNS()
        } catch { lastError = "Clear DNS failed: \(error.localizedDescription)" }
    }

    func toggleLaunchAtLogin(_ on: Bool) {
        do {
            try loginItem.setEnabled(on)
            launchAtLogin = loginItem.isEnabled
        } catch { lastError = "Login item error: \(error.localizedDescription)" }
    }

    func loadResolvers() async {
        do {
            allResolvers = try await resolvers.fetchAll()
        } catch { lastError = "Resolver fetch failed: \(error.localizedDescription)" }
    }

    func saveConfig(_ text: String) async {
        do {
            try await config.save(rawText: text)
            currentConfig = try? config.load()
            // Restart so changes take effect
            if status == .running { await restart() }
        } catch { lastError = "Save config failed: \(error.localizedDescription)" }
    }

    /// Applies a set of resolver names to the config's `server_names` and saves.
    func applyResolverSelection(_ names: [String]) async {
        do {
            try await config.updateServerNames(names)
            currentConfig = try? config.load()
            if status == .running { await restart() }
        } catch { lastError = "Apply selection failed: \(error.localizedDescription)" }
    }

    /// Switches to pure auto-select mode: empties `server_names` and lets
    /// dnscrypt-proxy pick servers from the sources.
    func enableAutoSelect() async {
        await applyResolverSelection([])
    }

    // MARK: - Derived views

    var filteredResolvers: [Resolver] {
        allResolvers.filter { r in
            guard protocolFilter.contains(r.protocol) else { return false }
            guard !searchQuery.isEmpty else { return true }
            let q = searchQuery.lowercased()
            return r.name.lowercased().contains(q)
                || r.description.lowercased().contains(q)
        }
    }
}

enum MainTab: String, Hashable, CaseIterable {
    case dashboard, resolvers, config, logs, settings

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .resolvers: return "Resolvers"
        case .config: return "Config"
        case .logs: return "Logs"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .resolvers: return "server.rack"
        case .config: return "doc.text"
        case .logs: return "text.alignleft"
        case .settings: return "gearshape"
        }
    }
}
