import Foundation

/// Projection of the bits of `dnscrypt-proxy.toml` we surface in the GUI.
///
/// Keep the raw TOML text authoritative so round-trips via the editor
/// don't lose comments or unknown keys. A tiny line-based parser extracts
/// the specific top-level keys the dashboard/settings views care about.
struct ProxyConfig {
    var rawText: String

    var serverNames: [String] {
        parseStringArray(key: "server_names") ?? []
    }

    var listenAddresses: [String] {
        parseStringArray(key: "listen_addresses") ?? ["127.0.0.1:53"]
    }

    var requireDNSSEC: Bool   { parseBool(key: "require_dnssec")   ?? false }
    var requireNoLog: Bool    { parseBool(key: "require_nolog")    ?? true  }
    var requireNoFilter: Bool { parseBool(key: "require_nofilter") ?? true  }
    var dnscryptServers: Bool { parseBool(key: "dnscrypt_servers") ?? true  }
    var dohServers: Bool      { parseBool(key: "doh_servers")      ?? true  }
    var odohServers: Bool     { parseBool(key: "odoh_servers")     ?? false }
    var logFile: String?      { parseString(key: "log_file") }

    /// True when `server_names` is empty or missing — dnscrypt-proxy will auto-select from its sources.
    var isAutoSelect: Bool { serverNames.isEmpty }

    // MARK: - Tiny TOML key extractor (top-level scope only)

    /// Scans lines *before the first [table.header]* so we only ever read top-level keys
    private func topLevelLines() -> [String] {
        var out: [String] = []
        for line in rawText.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { break }
            out.append(String(line))
        }
        return out
    }

    private func valueString(forKey key: String) -> String? {
        let pattern = #"^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*(.+?)\s*(#.*)?$"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in topLevelLines() {
            let range = NSRange(line.startIndex..., in: line)
            if let m = re.firstMatch(in: line, range: range),
               let r = Range(m.range(at: 1), in: line) {
                return String(line[r])
            }
        }
        return nil
    }

    private func parseBool(key: String) -> Bool? {
        guard let v = valueString(forKey: key) else { return nil }
        return v == "true" ? true : (v == "false" ? false : nil)
    }

    private func parseString(key: String) -> String? {
        guard let v = valueString(forKey: key) else { return nil }
        return v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func parseStringArray(key: String) -> [String]? {
        guard let v = valueString(forKey: key) else { return nil }
        guard v.hasPrefix("[") && v.hasSuffix("]") else { return nil }
        let inner = String(v.dropFirst().dropLast())
        return inner
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces)
                     .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }
}
