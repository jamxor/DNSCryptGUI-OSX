import Foundation
import SystemConfiguration

/// Wraps `networksetup` for DNS server management and runs a lightweight
/// connection verification against the local proxy.
@MainActor
final class NetworkService {
    let helper: HelperClient
    init(helper: HelperClient) { self.helper = helper }


    /// The current network service name (e.g. "Wi-Fi", "Ethernet").
    /// Uses SCDynamicStore to find the service associated with the primary
    /// interface, then maps BSD name → service name via networksetup.
    func activeNetworkService() async throws -> String {
        // `networksetup -listnetworkserviceorder` prints every service plus
        // the hardware port / device. We pick the first enabled service that
        // has a matching `Device: <en0|en1|...>` and declare it the primary interface.
        let primaryIface = primaryInterfaceBSD() ?? "en0"

        let r = try await PrivilegedShell.run(
            PrivilegedShell.which("networksetup") ?? "/usr/sbin/networksetup",
            ["-listnetworkserviceorder"]
        )

        let lines = r.stdout.split(separator: "\n").map(String.init)
        let nameRegex = try? NSRegularExpression(pattern: #"^\(\d+\)\s+(.+?)\s*$"#)
        for i in 0..<lines.count {
            if lines[i].contains("Device: \(primaryIface)") {
                // previous non-blank line is "(N) Service Name"
                var j = i - 1
                while j >= 0 && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j -= 1 }
                guard j >= 0, let re = nameRegex else { continue }
                let ns = lines[j] as NSString
                if let m = re.firstMatch(in: lines[j], range: NSRange(location: 0, length: ns.length)),
                   m.numberOfRanges >= 2 {
                    return ns.substring(with: m.range(at: 1))
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return "Wi-Fi"
    }

    private func primaryInterfaceBSD() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "DNSCryptGUI" as CFString, nil, nil) else { return nil }
        guard let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else {
            return nil
        }
        return dict["PrimaryInterface"] as? String
    }

    func currentDNSServers() async throws -> [String] {
        let service = try await activeNetworkService()
        let r = try await PrivilegedShell.run(
            PrivilegedShell.which("networksetup") ?? "/usr/sbin/networksetup",
            ["-getdnsservers", service]
        )
        // Returns either one IP per line, or "There aren't any DNS Servers set…"
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.lowercased().contains("aren't any") { return [] }
        return out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    func setSystemDNS(to servers: [String]) async throws {
        let service = try await activeNetworkService()
        // Input validation also happens on the helper side; do validation here
        // too for a snappier error message and to avoid a pointless XPC trip.
        for s in servers {
            guard s.range(of: #"^[0-9A-Fa-f:.]+$"#, options: .regularExpression) != nil else {
                throw ShellError.launchFailed("Refusing to set non-IP DNS value: \(s)")
            }
        }
        try await helper.setSystemDNS(service: service, servers: servers)
    }

    /// Reverts DNS to DHCP defaults.
    func clearSystemDNS() async throws {
        try await setSystemDNS(to: [])
    }

    /// Checks whether name resolution is actually going through the local
    /// proxy. Strategy: query a known-resolvable public domain via 127.0.0.1
    /// and verify we got an A or AAAA record back. Combined with the brew-services
    /// status check in ProxyService and the system-DNS comparison below,
    /// that's enough to distinguish "running + routed" from "running + not
    /// routed" from "not running".
    func verifyDNSThroughProxy() async -> ConnectionCheck {
        // Try the two loopback addresses dnscrypt-proxy commonly binds to.
        // First one that answers wins.
        let candidates: [(listen: String, qtype: String)] = [
            ("127.0.0.1", "A"),
            ("::1",       "AAAA")
        ]
        var proxyAnswers = false
        for c in candidates {
            if await digSucceeds(at: c.listen, domain: "cloudflare.com", qtype: c.qtype) {
                proxyAnswers = true
                break
            }
        }
        guard proxyAnswers else { return .unknown }

        //    The proxy is up. Decide whether the *system* is actually
        //    sending its queries to it. Strict definition: every DNS
        //    server in the system list must be a loopback the proxy is
        //    listening on. If even one non-loopback address is in there,
        //    macOS will route some (often most) queries to it per the
        //    configured order, leaking around the proxy. Likewise, an
        //    empty list means DHCP defaults are in play.
        let servers = (try? await currentDNSServers()) ?? []
        return NetworkService.isAllLoopback(servers) ? .ok : .proxyRunningButDNSNotRouted
    }

    static func isAllLoopback(_ servers: [String]) -> Bool {
        guard !servers.isEmpty else { return false }
        let loopbacks: Set<String> = ["127.0.0.1", "::1"]
        return servers.allSatisfy { loopbacks.contains($0) }
    }

    /// Runs `dig @<listen> <domain> <qtype>` and returns true if any line of the +short output parses as a v4 or v6 literal.
    private func digSucceeds(at listen: String, domain: String, qtype: String) async -> Bool {
        let dig = PrivilegedShell.which("dig") ?? "/usr/bin/dig"
        guard let result = try? await PrivilegedShell.run(
            dig, ["@\(listen)", domain, qtype, "+short", "+timeout=2", "+tries=1"]
        ), result.ok else { return false }

        // IPv4 dotted quad OR anything that looks like an IPv6 literal
        // (hex groups + colons, with optional "::" compression). Deliberately
        // loose - we need to just distinguish "got an address" from "empty
        // output / SERVFAIL / refused".
        let ipv4 = #"^\d{1,3}(\.\d{1,3}){3}$"#
        let ipv6 = #"^[0-9A-Fa-f:]+(:[0-9A-Fa-f]{1,4}){1,}$"#
        return result.stdout
            .split(separator: "\n")
            .contains { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.range(of: ipv4, options: .regularExpression) != nil
                    || t.range(of: ipv6, options: .regularExpression) != nil
            }
    }
}
