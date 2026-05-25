import Foundation

/// The XPC protocol exposed by the privileged helper. Shared between the
/// GUI target (DNSCryptGUI) and the helper target (DNSCryptGUIHelper).
///
/// Every method MUST:
///   * be `@objc`
///   * take its arguments as plain-old-Objective-C types (String, Data,
///     NSNumber, NSArray-with-plist-safe-contents, …)
///   * return via a completion closure; XPC can't proxy async/await here
///
/// We deliberately expose a *narrow*, *typed* surface - no generic
/// "runShellCommand(_)". That way the attack surface is the union of what
/// the individual operations can do, not "arbitrary root".
@objc public protocol HelperProtocol {

    /// Health check. Returns the helper's bundle version so the GUI can
    /// detect a stale helper still installed from a previous app version.
    func helperVersion(reply: @escaping (_ version: String) -> Void)

    /// `sudo brew services start dnscrypt-proxy`
    func startProxy(reply: @escaping (_ exitCode: Int32, _ combinedOutput: String) -> Void)

    /// `sudo brew services stop dnscrypt-proxy`
    func stopProxy(reply: @escaping (_ exitCode: Int32, _ combinedOutput: String) -> Void)

    /// `sudo brew services restart dnscrypt-proxy`
    func restartProxy(reply: @escaping (_ exitCode: Int32, _ combinedOutput: String) -> Void)

    /// Atomically writes TOML text to the config file. `targetPath` is
    /// validated by the helper against an allow-list (see HelperTool).
    func writeConfig(data: Data,
                     targetPath: String,
                     reply: @escaping (_ exitCode: Int32, _ message: String) -> Void)

    /// `networksetup -setdnsservers <service> <servers...>` (or `empty`
    /// when `servers` is empty).
    func setSystemDNS(service: String,
                      servers: [String],
                      reply: @escaping (_ exitCode: Int32, _ combinedOutput: String) -> Void)

    /// Returns a status string for the dnscrypt-proxy daemon. The helper
    /// runs `launchctl list <label>` as root (which the GUI can't do) and
    /// returns the raw output so the GUI can parse it. `state` will be
    /// "running", "stopped", "errored", or "unknown".
    func proxyStatus(reply: @escaping (_ state: String, _ pid: Int32, _ lastExit: Int32) -> Void)
}

/// Mach service name used by both ends. Must match the `MachServices` key
/// in the helper's launchd plist exactly.
public let kHelperMachServiceName = "com.hlincore.DNSCryptGUI.Helper"

/// The expected reverse-DNS label for the helper's launchd plist file.
public let kHelperPlistName = "com.hlincore.DNSCryptGUI.Helper.plist"
