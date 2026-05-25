import Foundation
import os.log
import Security

/// Implementation of the XPC interface. Runs as root inside the
/// DNSCryptGUIHelper launchd daemon.
final class HelperTool: NSObject, HelperProtocol, NSXPCListenerDelegate {

    // For ad-hoc local dev builds (no Team) the helper will refuse all
    // connections. Sign with a real (Apple Development or Developer ID)
    // identity and the value resolves automatically.
    private let expectedTeamID: String? = {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess,
              let selfCode else { return nil }

        var staticCodeRef: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCodeRef) == errSecSuccess,
              let staticCode = staticCodeRef else { return nil }

        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,
                                            SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any] else { return nil }

        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        guard let teamID, !teamID.isEmpty else { return nil }
        return teamID
    }()

    // Bundle ID of the GUI we accept connections from. Derived from the
    // helper's own bundle ID by stripping a trailing ".Helper" — this way
    // renaming the app only requires updating one place (the app's
    // CFBundleIdentifier) instead of keeping two strings in sync.
    private let expectedBundleID: String = {
        let helperID = Bundle.main.bundleIdentifier
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String)
            ?? "com.hlincore.DNSCryptGUI.Helper"
        if helperID.hasSuffix(".Helper") {
            return String(helperID.dropLast(".Helper".count))
        }
        return helperID
    }()

    // Only allow writing to these exact paths. Prevents a malicious
    // client from using the helper as an arbitrary root-file-write primitive.
    private let allowedConfigPaths: Set<String> = [
        "/opt/homebrew/etc/dnscrypt-proxy.toml",
        "/usr/local/etc/dnscrypt-proxy.toml"
    ]

    // Only brew paths we're willing to invoke.
    private let allowedBrewBinaries: Set<String> = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    private let listener: NSXPCListener

    // Diagnostic logging via the unified logging system (os_log).
    // To view live:
    //   log stream --predicate 'subsystem == "com.hlincore.DNSCryptGUI.Helper"'
    // To include info-level events:
    //   log show ... --info --last 1h
    // To include everything (debug):
    //   log show ... --debug --info --last 1h
    private static let log = Logger(subsystem: "com.hlincore.DNSCryptGUI.Helper",
                                    category: "helper")

    static func diag(_ msg: String) {
        log.debug("\(msg, privacy: .public)")
    }

    override init() {
        Self.diag("init() — creating listener for \(kHelperMachServiceName)")
        listener = NSXPCListener(machServiceName: kHelperMachServiceName)
        super.init()
        listener.delegate = self
        Self.diag("init() done — delegate set")
    }

    func run() -> Never {
        Self.diag("run() — calling listener.resume()")
        listener.resume()
        Self.diag("run() — listener resumed; entering dispatchMain")
        // Park the main thread on GCD. `RunLoop.current.run()` returns
        // immediately when no sources are attached, and NSXPCListener
        // does its work on its own internal queue rather than adding a
        // source to the main run loop.
        dispatchMain()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // verifyClient logs its own rejection reason at .error if it
        // returns false, and stays silent on success.
        guard verifyClient(newConnection) else { return false }
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - Client verification

    /// Confirms the connecting process is signed by the same Team ID
    /// Logging philosophy: success is silent (called on every XPC connection,
    /// would dominate the log), failure is logged at error level with the
    /// specific reason so we can debug rejected clients
    private func verifyClient(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier

        var codeRef: SecCode?
        let attrs = [kSecGuestAttributePid: NSNumber(value: pid)] as NSDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &codeRef) == errSecSuccess,
              let code = codeRef else {
            Self.log.error("verifyClient rejected pid=\(pid, privacy: .public): SecCodeCopyGuestWithAttributes failed")
            return false
        }

        // SecCode to SecStaticCode via the supported API. A previous
        // `code as! SecStaticCode` force-cast crashed the helper (oops).
        var staticCodeRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCodeRef) == errSecSuccess,
              let staticCode = staticCodeRef else {
            Self.log.error("verifyClient rejected pid=\(pid, privacy: .public): SecCodeCopyStaticCode failed")
            return false
        }

        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,
                                            SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else {
            Self.log.error("verifyClient rejected pid=\(pid, privacy: .public): SecCodeCopySigningInformation failed")
            return false
        }

        let teamID   = info[kSecCodeInfoTeamIdentifier as String] as? String
        let bundleID = (info[kSecCodeInfoPList as String] as? [String: Any])?["CFBundleIdentifier"] as? String

        // A correctly-signed helper always resolves a Team ID from its own code signature; nil means the helper is ad-hoc-signed or unsigned.
        guard let expectedTeam = expectedTeamID else {
            Self.log.error("verifyClient rejected pid=\(pid, privacy: .public): unable to determine helper's own Team ID (helper appears to be ad-hoc-signed or unsigned — sign with a real identity)")
            return false
        }
        if teamID != expectedTeam {
            Self.log.error("verifyClient rejected pid=\(pid, privacy: .public): teamID mismatch (got \(teamID ?? "nil", privacy: .public), want \(expectedTeam, privacy: .public))")
            return false
        }
        if bundleID != expectedBundleID {
            Self.log.error("verifyClient rejected pid=\(pid, privacy: .public): bundleID mismatch (got \(bundleID ?? "nil", privacy: .public), want \(self.expectedBundleID, privacy: .public))")
            return false
        }
        return true
    }

    // MARK: - HelperProtocol

    func helperVersion(reply: @escaping (String) -> Void) {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        reply(v)
    }

    /// Locations brew leaves the dnscrypt-proxy launchd plist after
    /// `brew install dnscrypt-proxy`. We try Apple Silicon first then Intel.
    /// This is the same plist `brew services start` would manipulate, just
    /// without running brew at all — modern brew refuses to run as root and
    /// hits its formula API.
    private let dnscryptPlistCandidates: [String] = [
        "/opt/homebrew/opt/dnscrypt-proxy/homebrew.mxcl.dnscrypt-proxy.plist",
        "/usr/local/opt/dnscrypt-proxy/homebrew.mxcl.dnscrypt-proxy.plist"
    ]

    private static let dnscryptDaemonLabel = "homebrew.mxcl.dnscrypt-proxy"

    private func dnscryptPlistPath() -> String? {
        dnscryptPlistCandidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Where we install the daemon plist so launchd can bootstrap it into
    /// the system domain. Brew leaves the source plist in /opt/homebrew but
    /// launchd requires daemons in /Library/LaunchDaemons (root-owned, 644).
    private static let installedDaemonPath = "/Library/LaunchDaemons/homebrew.mxcl.dnscrypt-proxy.plist"

    /// Copy the brew-provided plist into /Library/LaunchDaemons with the
    /// ownership/perms launchd demands, mutating it for system-domain use.
    /// This mirrors what `brew services start` would do, minus brew's
    /// formula-API roundtrip:
    ///   * Force UserName=root so dnscrypt-proxy can bind port 53.
    ///   * Write to /Library/LaunchDaemons/ as root:wheel mode 0644.
    /// Returns the destination path on success, or nil if anything failed.
    private func ensureInstalledDaemonPlist() -> String? {
        guard let src = dnscryptPlistPath() else {
            Self.log.error("ensureInstalledDaemonPlist: source plist missing — is dnscrypt-proxy installed via Homebrew?")
            return nil
        }
        let dest = Self.installedDaemonPath
        guard var dict = NSDictionary(contentsOfFile: src) as? [String: Any] else {
            Self.log.error("ensureInstalledDaemonPlist: failed to read \(src, privacy: .public)")
            return nil
        }
        // Force UserName as root to enable the bind attempt
        dict["UserName"] = "root"
        dict.removeValue(forKey: "LimitLoadToSessionType")

        let plistData: Data
        do {
            plistData = try PropertyListSerialization.data(fromPropertyList: dict,
                                                           format: .xml,
                                                           options: 0)
        } catch {
            Self.log.error("ensureInstalledDaemonPlist: serialize failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        do {
            try plistData.write(to: URL(fileURLWithPath: dest), options: .atomic)
            try FileManager.default.setAttributes([
                .posixPermissions: 0o644,
                .ownerAccountID: NSNumber(value: 0),
                .groupOwnerAccountID: NSNumber(value: 0)
            ], ofItemAtPath: dest)
        } catch {
            Self.log.error("ensureInstalledDaemonPlist: write/chmod failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        Self.diag("ensureInstalledDaemonPlist: wrote \(dest)")
        return dest
    }

    func startProxy(reply: @escaping (Int32, String) -> Void) {
        Self.log.info("startProxy")
        guard let plist = ensureInstalledDaemonPlist() else {
            reply(-1, "Couldn't prepare /Library/LaunchDaemons/homebrew.mxcl.dnscrypt-proxy.plist. Is dnscrypt-proxy installed via Homebrew?")
            return
        }
        bootstrapWithRecovery(plist: plist, reply: reply)
    }

    /// Sequence:
    ///   1. `launchctl bootstrap system <plist>`
    ///   2. If exit == 0 or 17 (EEXIST = already loaded, fine) → success.
    ///   3. If exit == 5 (EIO = stuck), explicit `bootout`, then bootstrap
    ///      again. The second attempt either succeeds or returns the real
    ///      error.
    private func bootstrapWithRecovery(plist: String,
                                       reply: @escaping (Int32, String) -> Void) {
        runBinary("/bin/launchctl", args: ["bootstrap", "system", plist]) { code, out in
            if code == 0 || code == 17 {
                Self.log.notice("bootstrap success (code=\(code, privacy: .public))")
                reply(0, "Started")
                return
            }
            guard code == 5 else {
                Self.log.error("bootstrap failed code=\(code, privacy: .public): \(out, privacy: .public)")
                reply(code, out)
                return
            }
            // EIO — almost always means launchd has a stuck half-registered
            // entry from a previous failed bootstrap. Try the bootout
            // recovery path (this has been painful).
            Self.log.notice("bootstrap returned EIO; attempting bootout + retry")
            self.runBinary("/bin/launchctl",
                           args: ["bootout",
                                  "system/\(Self.dnscryptDaemonLabel)"]) { _, _ in
                self.runBinary("/bin/launchctl",
                               args: ["bootstrap", "system", plist]) { c2, o2 in
                    if c2 == 0 || c2 == 17 {
                        Self.log.notice("bootstrap (after bootout) success")
                        reply(0, "Started")
                    } else {
                        Self.log.error("bootstrap (after bootout) failed code=\(c2, privacy: .public): \(o2, privacy: .public)")
                        reply(c2, o2)
                    }
                }
            }
        }
    }

    func stopProxy(reply: @escaping (Int32, String) -> Void) {
        Self.log.info("stopProxy")
        // bootout by label or path — label works even if the plist file is gone.
        runBinary("/bin/launchctl",
                  args: ["bootout", "system/\(Self.dnscryptDaemonLabel)"]) { code, out in
            // Exit 5 (ESRCH) means already stopped — treat as success.
            if code == 0 || code == 5 {
                reply(0, "Stopped")
            } else {
                reply(code, out)
            }
        }
    }

    func restartProxy(reply: @escaping (Int32, String) -> Void) {
        Self.log.info("restartProxy")
        // First try kickstart -k (works if already loaded). If that fails,
        // fall back to bootstrap-with-recovery using the sanitized plist.
        runBinary("/bin/launchctl",
                  args: ["kickstart", "-k", "system/\(Self.dnscryptDaemonLabel)"]) { code, _ in
            if code == 0 {
                Self.log.notice("restart via kickstart succeeded")
                reply(0, "Restarted")
                return
            }
            Self.log.notice("kickstart failed (code=\(code, privacy: .public)); falling back to bootstrap-with-recovery")
            guard let plist = self.ensureInstalledDaemonPlist() else {
                reply(-1, "dnscrypt-proxy launchd plist could not be prepared.")
                return
            }
            self.bootstrapWithRecovery(plist: plist, reply: reply)
        }
    }

    func writeConfig(data: Data, targetPath: String, reply: @escaping (Int32, String) -> Void) {
        Self.log.info("writeConfig targetPath=\(targetPath, privacy: .public) bytes=\(data.count, privacy: .public)")
        guard allowedConfigPaths.contains(targetPath) else {
            Self.log.error("writeConfig refused: disallowed path \(targetPath, privacy: .public)")
            reply(-1, "Refusing to write to disallowed path: \(targetPath)")
            return
        }
        do {
            let backup = targetPath + ".bak"
            // Back up existing config if present.
            if FileManager.default.fileExists(atPath: targetPath) {
                try? FileManager.default.removeItem(atPath: backup)
                try FileManager.default.copyItem(atPath: targetPath, toPath: backup)
            }
            try data.write(to: URL(fileURLWithPath: targetPath), options: .atomic)
            // Keep ownership root:wheel with mode 0644 (brew's default).
            try FileManager.default.setAttributes([
                .posixPermissions: 0o644
            ], ofItemAtPath: targetPath)
            reply(0, "ok")
        } catch {
            Self.log.error("writeConfig failed: \(error.localizedDescription, privacy: .public)")
            reply(-1, "writeConfig failed: \(error.localizedDescription)")
        }
    }

    func proxyStatus(reply: @escaping (String, Int32, Int32) -> Void) {
        // GUI polls every ~3 seconds. Stay at debug level.
        Self.diag("proxyStatus")
        // Run as root so launchctl can read the system domain.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["list", Self.dnscryptDaemonLabel]
        p.environment = systemEnvironment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            reply("unknown", 0, 0)
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: data, encoding: .utf8) ?? ""

        // Not loaded / exit 113 / "Could not find service".
        guard p.terminationStatus == 0 else {
            reply("stopped", 0, 0)
            return
        }
        // Parse `"PID" = N;` and `"LastExitStatus" = N;` lines (quote
        // characters vary across macOS releases, so strip them first).
        func extractInt(_ key: String) -> Int32? {
            for line in stdout.split(separator: "\n") {
                let stripped = line.replacingOccurrences(of: "\"", with: "")
                                   .trimmingCharacters(in: .whitespaces)
                guard stripped.hasPrefix("\(key) ") || stripped.hasPrefix("\(key)=") else { continue }
                let parts = stripped.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let v = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ;\t"))
                    return Int32(v)
                }
            }
            return nil
        }
        let pid = extractInt("PID") ?? 0
        let last = extractInt("LastExitStatus") ?? 0
        let state: String
        if pid > 0 {
            state = "running"
        } else if last != 0 {
            state = "errored"
        } else {
            state = "stopped"
        }
        Self.diag("proxyStatus → state=\(state) pid=\(pid) lastExit=\(last)")
        reply(state, pid, last)
    }

    func setSystemDNS(service: String, servers: [String], reply: @escaping (Int32, String) -> Void) {
        Self.log.info("setSystemDNS service=\(service, privacy: .public) servers=\(servers, privacy: .public)")
        // Validate IP inputs before shelling out.
        for s in servers {
            guard s.range(of: #"^[0-9A-Fa-f:.]+$"#, options: .regularExpression) != nil else {
                Self.log.error("setSystemDNS refused: non-IP value \(s, privacy: .public)")
                reply(-1, "Refusing non-IP DNS value: \(s)")
                return
            }
        }
        let args = ["-setdnsservers", service] + (servers.isEmpty ? ["empty"] : servers)
        runBinary("/usr/sbin/networksetup", args: args, reply: reply)
    }

    // MARK: - Shell helpers (run as root)

    private func runBrew(_ args: [String], reply: @escaping (Int32, String) -> Void) {
        let brew = allowedBrewBinaries.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let brew else {
            reply(-1, "brew not found at /opt/homebrew/bin/brew or /usr/local/bin/brew")
            return
        }
        runBinary(brew, args: args, env: brewEnvironment, reply: reply)
    }

    /// Environment we pass to `brew` to make it root-friendly (skip auto
    /// update, skip analytics) and locate its subcommands.
    private var brewEnvironment: [String: String] {
        return [
            "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/var/root",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            "HOMEBREW_NO_EMOJI": "1",
            "HOMEBREW_NO_ENV_HINTS": "1"
        ]
    }

    /// Default environment for system tools like launchctl and
    /// networksetup. Inheriting whatever launchd handed out would also be
    /// fine, but being explicit avoids surprises if launchd's env changes.
    private var systemEnvironment: [String: String] {
        return [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/var/root"
        ]
    }

    /// Default to `systemEnvironment` for any caller that doesn't pass
    /// `env:` explicitly.
    private func runBinary(_ path: String,
                           args: [String],
                           env: [String: String]? = nil,
                           reply: @escaping (Int32, String) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = env ?? systemEnvironment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            reply(p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            reply(-1, "launch failed: \(error.localizedDescription)")
        }
    }
}
