import Foundation

/// A single resolver or relay entry parsed out of `public-resolvers.md` (or `relays.md`).
struct Resolver: Identifiable, Hashable {
    let id = UUID()
    let name: String                // e.g. "cloudflare"
    let description: String
    let stampString: String         // sdns://...
    let `protocol`: DNSProtocol
    let dnssec: Bool
    let noLog: Bool
    let noFilter: Bool

    init?(name: String, description: String, stampString: String) {
        guard let stamp = DNSStamp(raw: stampString) else { return nil }
        self.name = name
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.stampString = stampString
        self.`protocol` = stamp.protocol
        self.dnssec = stamp.dnssec
        self.noLog = stamp.noLog
        self.noFilter = stamp.noFilter
    }
}
