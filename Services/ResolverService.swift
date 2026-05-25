import Foundation

/// Fetches the canonical resolver lists and parses them into Resolver records.
/// Lists come from the dnscrypt.info CDN (signed upstream by the project).
final class ResolverService {

    /// Cached to disk on first launch to speed up UI.
    /// Public resolvers and anonymized-DNSCrypt relays live in separate
    /// v3 lists; ODoH targets and ODoH relays live in two *more* v3 lists.
    /// We merge all four so the protocol filter has something to filter on.
    static let sources: [(url: URL, cacheKey: String)] = [
        (URL(string: "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md")!, "public-resolvers.md"),
        (URL(string: "https://download.dnscrypt.info/resolvers-list/v3/relays.md")!,          "relays.md"),
        (URL(string: "https://download.dnscrypt.info/resolvers-list/v3/odoh-servers.md")!,    "odoh-servers.md"),
        (URL(string: "https://download.dnscrypt.info/resolvers-list/v3/odoh-relays.md")!,     "odoh-relays.md"),
    ]

    /// Fetches every resolver list in parallel and returns them merged.
    func fetchAll() async throws -> [Resolver] {
        try await withThrowingTaskGroup(of: [Resolver].self) { group in
            for src in Self.sources {
                group.addTask { try await self.fetchList(url: src.url, cacheKey: src.cacheKey) }
            }
            var all: [Resolver] = []
            for try await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    private func fetchList(url: URL, cacheKey: String) async throws -> [Resolver] {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DNSCryptGUI", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cachePath = cacheDir.appendingPathComponent(cacheKey)

        var text: String?
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                try? data.write(to: cachePath)
                text = String(data: data, encoding: .utf8)
            }
        } catch {
            // fall through to cache
        }
        if text == nil, let cached = try? String(contentsOf: cachePath, encoding: .utf8) {
            text = cached
        }
        guard let markdown = text else { return [] }
        return parseResolverMarkdown(markdown)
    }

    /// We walk line-by-line collecting name + description + stamp.
    func parseResolverMarkdown(_ text: String) -> [Resolver] {
        var out: [Resolver] = []
        var currentName: String?
        var currentDesc: [String] = []
        var currentStamp: String?

        func flush() {
            if let n = currentName, let s = currentStamp,
               let r = Resolver(name: n, description: currentDesc.joined(separator: " "), stampString: s) {
                out.append(r)
            }
            currentName = nil
            currentDesc = []
            currentStamp = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                flush()
                currentName = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("sdns://") {
                currentStamp = line
            } else if line.isEmpty {
                // section separator — keep accumulating
            } else if currentName != nil, currentStamp == nil {
                currentDesc.append(line)
            }
        }
        flush()
        return out
    }
}
