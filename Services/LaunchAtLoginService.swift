import Foundation
import ServiceManagement

/// Wrapper around `SMAppService.mainApp` for the "Launch at login" toggle.
/// Requires macOS 13+.
final class LaunchAtLoginService {

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ on: Bool) throws {
        if #available(macOS 13.0, *) {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
