import Foundation

/// Wrapper around Homebrew operations.
final class BrewService {
    /// Homebrew binary on Apple Silicon, with x86 fallback.
    var brewPath: String {
        PrivilegedShell.which("brew") ?? "/opt/homebrew/bin/brew"
    }

    /// Homebrew prefix, used to locate configs and logs.
    var prefix: String {
        FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
    }

    func isInstalled() async -> Bool {
        guard let brew = PrivilegedShell.which("brew") else { return false }
        guard let result = try? await PrivilegedShell.run(brew, ["list", "--formula"]) else {
            return false
        }
        return result.stdout.split(separator: "\n").contains("dnscrypt-proxy")
    }

    /// Installs or upgrades `dnscrypt-proxy` from the official Homebrew core tap.
    /// Does not require admin privileges (user-level brew install). Maybe an update feature for version 2. Stay tuned.
    func installOrUpgrade() async throws {
        let brew = brewPath
        if await isInstalled() {
            _ = try await PrivilegedShell.run(brew, ["upgrade", "dnscrypt-proxy"])
        } else {
            let result = try await PrivilegedShell.run(brew, ["install", "dnscrypt-proxy"])
            guard result.ok else { throw ShellError.nonZeroExit(result.exitCode, result.combined) }
        }
    }

    /// Path to the installed `dnscrypt-proxy.toml`. Defaults to
    /// `<prefix>/etc/dnscrypt-proxy.toml`, but we also check the example path.
    var configPath: String {
        let primary = "\(prefix)/etc/dnscrypt-proxy.toml"
        if FileManager.default.fileExists(atPath: primary) { return primary }
        let example = "\(prefix)/etc/dnscrypt-proxy/example-dnscrypt-proxy.toml"
        if FileManager.default.fileExists(atPath: example) { return example }
        return primary
    }

    /// Default log file path suggested for users who haven't set one. Should test and monitor to ensure its truncating correctly.
    var defaultLogPath: String { "\(prefix)/var/log/dnscrypt-proxy.log" }
    var defaultQueryLogPath: String { "\(prefix)/var/log/query.log"}
    var defaultNXLogPath: String { "\(prefix)/var/log/nx.log"}
}
