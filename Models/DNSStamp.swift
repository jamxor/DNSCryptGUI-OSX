import Foundation

/// DNS-Stamp protocol byte. See https://dnscrypt.info/stamps-specifications/
enum DNSProtocol: Int, CaseIterable, Identifiable, Codable {
    case plainDNS       = 0x00
    case dnscrypt       = 0x01
    case doh            = 0x02
    case dot            = 0x03
    case doq            = 0x04
    case odohTarget     = 0x05
    case dnscryptRelay  = 0x81
    case odohRelay      = 0x85
    case unknown        = -1

    var id: Int { rawValue }
// Added PlainDNS, DoT and DoQ, but not sure if there is any real use for these currently?
    var label: String {
        switch self {
        case .plainDNS:      return "Plain DNS"
        case .dnscrypt:      return "DNSCrypt"
        case .doh:           return "DoH"
        case .dot:           return "DoT"
        case .doq:           return "DoQ"
        case .odohTarget:    return "oDoH Target"
        case .dnscryptRelay: return "DNSCrypt Relay"
        case .odohRelay:     return "oDoH Relay"
        case .unknown:       return "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .plainDNS:      return "lock.open"
        case .dnscrypt:      return "lock.shield"
        case .doh:           return "globe.americas"
        case .dot:           return "network"
        case .doq:           return "bolt.horizontal"
        case .odohTarget:    return "eye.slash"
        case .dnscryptRelay: return "arrow.triangle.2.circlepath"
        case .odohRelay:     return "arrow.triangle.branch"
        case .unknown:       return "questionmark"
        }
    }
}

/// Minimal sdns:// stamp parser — we only decode the protocol byte plus the property-flag byte(s) we expose in the UI
struct DNSStamp {
    let raw: String
    let `protocol`: DNSProtocol
    let dnssec: Bool
    let noLog: Bool
    let noFilter: Bool

    init?(raw: String) {
        guard raw.hasPrefix("sdns://") else { return nil }
        let b64 = String(raw.dropFirst("sdns://".count))
        guard let data = Self.base64URLDecode(b64), data.count >= 9 else { return nil }
        self.raw = raw
        let proto = DNSProtocol(rawValue: Int(data[0])) ?? .unknown
        self.`protocol` = proto
        // 8 bytes little-endian props flags follow for most stamp types
        let props = data.subdata(in: 1..<9).withUnsafeBytes { $0.load(as: UInt64.self) }
        self.dnssec   = (props & 0x01) != 0
        self.noLog    = (props & 0x02) != 0
        self.noFilter = (props & 0x04) != 0
    }

    private static func base64URLDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        b64 += String(repeating: "=", count: pad)
        return Data(base64Encoded: b64)
    }
}
