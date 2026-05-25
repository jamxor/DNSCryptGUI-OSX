import Foundation

enum ConfigError: LocalizedError {
    case notFound(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let p): return "dnscrypt-proxy.toml not found at \(p)"
        case .writeFailed(let s): return "Config write failed: \(s)"
        }
    }
}

/// Reads and writes `dnscrypt-proxy.toml`.
/// Reads go through Foundation directly - the file is world-readable.
/// Writes go through the privileged helper because the file is root-owned once the service has been started at least once.
@MainActor
final class ConfigService {
    private let brew = BrewService()
    let helper: HelperClient

    init(helper: HelperClient) {
        self.helper = helper
    }

    var configPath: String { brew.configPath }

    nonisolated func load() throws -> ProxyConfig {
        let path = BrewService().configPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw ConfigError.notFound(path)
        }
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        return ProxyConfig(rawText: raw)
    }

    func save(rawText: String) async throws {
        do {
            try await helper.writeConfig(text: rawText, targetPath: configPath)
        } catch {
            throw ConfigError.writeFailed(error.localizedDescription)
        }
    }

    /// Rewrites the top-level `server_names = [...]` line in place.
    /// Creates it if missing.
    func updateServerNames(_ names: [String]) async throws {
        var text = try load().rawText
        let quoted = names.map { "\"\($0)\"" }.joined(separator: ", ")
        let newLine = "server_names = [\(quoted)]"

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inTopScope = true
        var didReplace = false
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { inTopScope = false }
            if trimmed.hasPrefix("#") { continue }
            if inTopScope, trimmed.hasPrefix("server_names") {
                lines[i] = newLine
                didReplace = true
                break
            }
        }
        if !didReplace {
            var insertAt = 0
            for i in 0..<lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("#") || t.isEmpty { insertAt = i + 1; continue }
                break
            }
            lines.insert(newLine, at: insertAt)
        }
        text = lines.joined(separator: "\n")
        try await save(rawText: text)
    }
}
