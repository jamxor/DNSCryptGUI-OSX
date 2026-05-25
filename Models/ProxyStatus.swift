import Foundation
import SwiftUI

enum ProxyStatus: String {
    case running, stopped, starting, stopping, errored, unknown

    var label: String {
        switch self {
        case .running:  return "Running"
        case .stopped:  return "Stopped"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .errored:  return "Error"
        case .unknown:  return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .running:   return .green
        case .stopped:   return .secondary
        case .starting,
             .stopping:  return .yellow
        case .errored:   return .red
        case .unknown:   return .gray
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .running:   return "lock.shield.fill"
        case .stopped:   return "lock.open"
        case .starting,
             .stopping:  return "hourglass"
        case .errored:   return "exclamationmark.shield.fill"
        case .unknown:   return "questionmark.circle"
        }
    }
}

enum ConnectionCheck: String {
    case ok
    case proxyRunningButDNSNotRouted
    case proxyNotRunning
    case testing
    case unknown

    var label: String {
        switch self {
        case .ok:                              return "DNS is routed through dnscrypt-proxy"
        case .proxyRunningButDNSNotRouted:     return "Proxy running but system DNS not routed to loopback (127.0.0.1 or ::1)"
        case .proxyNotRunning:                 return "Proxy is not running"
        case .testing:                         return "Testing…"
        case .unknown:                         return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .ok:                            return .green
        case .proxyRunningButDNSNotRouted:   return .orange
        case .proxyNotRunning:               return .red
        case .testing:                       return .yellow
        case .unknown:                       return .gray
        }
    }
}
