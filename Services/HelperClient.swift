import Foundation
import ServiceManagement

/// XPC client for the privileged helper daemon.
///
/// The helper is registered via `SMAppService.daemon(plistName:)`. After
/// `install()` succeeds the user must approve the daemon once in
/// System Settings → General → Login Items & Extensions. Subsequent calls
/// don't prompt the event.
@MainActor
final class HelperClient {

    enum HelperError: LocalizedError {
        case notApproved
        case notFound
        case registerFailed(String)
        case connectionBroken
        case nonZero(Int32, String)

        var errorDescription: String? {
            switch self {
            case .notApproved:          return "Helper waiting for approval in System Settings → Login Items."
            case .notFound:             return "Helper executable not found inside the app bundle."
            case .registerFailed(let s): return "Helper registration failed: \(s)"
            case .connectionBroken:     return "XPC connection to helper broke."
            case .nonZero(let c, let o): return "Helper returned exit \(c): \(o)"
            }
        }
    }

    // No cached connection — see makeConnection() below for why.

    // MARK: - Install / status

    /// Registers the helper with launchd. Call once on first run, and any
    /// time the status changes out of `.enabled`.
    func install() throws {
        guard #available(macOS 13.0, *) else {
            throw HelperError.registerFailed("SMAppService requires macOS 13+")
        }
        let service = SMAppService.daemon(plistName: kHelperPlistName)
        switch service.status {
        case .enabled:
            return
        case .notRegistered, .notFound:
            do {
                try service.register()
                // After register() the status should be .requiresApproval
                // on first-ever install. Re-check and surface that to the
                // caller so AppState can guide the user into Settings.
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    throw HelperError.notApproved
                }
            } catch let e as HelperError {
                throw e
            } catch {
                throw HelperError.registerFailed(error.localizedDescription)
            }
        case .requiresApproval:
            // Registered previously; user still hasn't flipped the toggle.....
            SMAppService.openSystemSettingsLoginItems()
            throw HelperError.notApproved
        @unknown default:
            throw HelperError.registerFailed("unknown status \(service.status.rawValue)")
        }
    }

    /// Current approval/installation status. Used by Settings UI.
    var status: SMAppService.Status {
        if #available(macOS 13.0, *) {
            return SMAppService.daemon(plistName: kHelperPlistName).status
        }
        return .notFound
    }

    func uninstall() throws {
        guard #available(macOS 13.0, *) else { return }
        try SMAppService.daemon(plistName: kHelperPlistName).unregister()
    }

    // MARK: - Connection plumbing

    /// Always returns a freshly-created connection. Launchd re-activates the daemon on the new connection's first message; no user-visible latency.
    private func makeConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: kHelperMachServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        c.invalidationHandler = { /* no-op — this connection is per-call */ }
        c.interruptionHandler  = { /* no-op — this connection is per-call */ }
        c.resume()
        return c
    }

    private func call<T>(_ body: @escaping (HelperProtocol, @escaping (T) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            let conn = makeConnection()
            // Track whether the continuation has already resumed so we can
            // invalidate the connection after the call without double-resuming.
            let resumed = ManagedAtomicFlag()

            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                if resumed.testAndSet() == false {
                    cont.resume(throwing: error)
                    conn.invalidate()
                }
            }
            guard let helper = proxy as? HelperProtocol else {
                if resumed.testAndSet() == false {
                    cont.resume(throwing: HelperError.connectionBroken)
                    conn.invalidate()
                }
                return
            }
            body(helper) { result in
                if resumed.testAndSet() == false {
                    cont.resume(returning: result)
                    conn.invalidate()
                }
            }
        }
    }

    /// Tiny thread-safe flag for single-resume continuation guarding.
    private final class ManagedAtomicFlag {
        private let lock = NSLock()
        private var flag = false
        /// Atomically sets the flag to true. Returns the *previous* value
        /// callers invert this to mean "if not previously set, proceed."
        func testAndSet() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if flag { return true }
            flag = true
            return false
        }
    }

    // MARK: - Typed API

    @discardableResult
    func version() async throws -> String {
        try await call { helper, reply in helper.helperVersion(reply: reply) }
    }

    func startProxy() async throws {
        let r: (Int32, String) = try await call { h, reply in
            h.startProxy { code, out in reply((code, out)) }
        }
        try assertOK(r)
    }

    func stopProxy() async throws {
        let r: (Int32, String) = try await call { h, reply in
            h.stopProxy { code, out in reply((code, out)) }
        }
        try assertOK(r)
    }

    func restartProxy() async throws {
        let r: (Int32, String) = try await call { h, reply in
            h.restartProxy { code, out in reply((code, out)) }
        }
        try assertOK(r)
    }

    func writeConfig(text: String, targetPath: String) async throws {
        let data = Data(text.utf8)
        let r: (Int32, String) = try await call { h, reply in
            h.writeConfig(data: data, targetPath: targetPath) { code, msg in reply((code, msg)) }
        }
        try assertOK(r)
    }

    func setSystemDNS(service: String, servers: [String]) async throws {
        let r: (Int32, String) = try await call { h, reply in
            h.setSystemDNS(service: service, servers: servers) { code, out in reply((code, out)) }
        }
        try assertOK(r)
    }

    /// Asks the helper for the dnscrypt-proxy daemon's current state.
    /// Returns (state, pid, lastExitStatus) - state is "running", "stopped",
    /// "errored", or "unknown".
    func proxyStatus() async throws -> (state: String, pid: Int32, lastExit: Int32) {
        let r: (String, Int32, Int32) = try await call { h, reply in
            h.proxyStatus { s, p, l in reply((s, p, l)) }
        }
        return (r.0, r.1, r.2)
    }

    private func assertOK(_ r: (Int32, String)) throws {
        guard r.0 == 0 else { throw HelperError.nonZero(r.0, r.1) }
    }
}
