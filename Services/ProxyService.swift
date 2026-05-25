import Foundation

/// Manages the `dnscrypt-proxy` service.
///
/// Privileged operations (start / stop / restart) are routed through the
/// XPC helper. Read-only status calls run directly from the GUI by parsing
/// `launchctl list` output — we deliberately bypass `brew services` so the
/// status check doesn't depend on brew's formula API.
@MainActor
final class ProxyService {
    let helper: HelperClient

    init(helper: HelperClient) {
        self.helper = helper
    }

    /// The launchd label the helper uses for the dnscrypt-proxy daemon.
    private static let daemonLabel = "homebrew.mxcl.dnscrypt-proxy"

    func currentStatus() async -> ProxyStatus {
        // Querying a system-domain launchd service via `launchctl list <label>`
        // requires root on modern macOS. The GUI runs as the user, so we
        // route the query through the helper, which is already root.
        guard let result = try? await helper.proxyStatus() else {
            return .unknown
        }
        switch result.state {
        case "running": return .running
        case "errored": return .errored
        case "stopped": return .stopped
        default:        return .unknown
        }
    }

    func start()   async throws { try await helper.startProxy() }
    func stop()    async throws { try await helper.stopProxy() }
    func restart() async throws { try await helper.restartProxy() }
}
