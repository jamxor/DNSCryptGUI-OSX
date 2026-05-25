import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // First-run blocker: surface approval prompt at the top of the menu
        // so users who only interact via the menu bar (this is a
        // LSUIElement app) aren't stuck with privileged actions failing
        // silently. Disappears once approval is granted and the scene-phase
        // observer in DNSCryptGUIApp picks up the new status.
        if state.helperAwaitingApproval {
            Button("Helper not approved — Open Login Items") {
                state.openLoginItemsSettings()
            }
            Divider()
        }

        // Status line
        Label(state.status.label, systemImage: state.status.menuBarSymbol)
        if state.status == .running {
            Label(state.connectionCheck.label, systemImage: "point.3.connected.trianglepath.dotted")
        }

        Divider()

        // Service control
        Button("Start")   { Task { await state.start() } }
            .disabled(state.status == .running)
        Button("Stop")    { Task { await state.stop() } }
            .disabled(state.status != .running)
        Button("Restart") { Task { await state.restart() } }

        Divider()

        // Active resolvers submenu
        Menu("Active resolvers") {
            if let cfg = state.currentConfig, !cfg.isAutoSelect {
                ForEach(cfg.serverNames, id: \.self) { n in
                    Label(n, systemImage: "checkmark")
                }
                Divider()
            }
            Button("Switch to auto-select") { Task { await state.enableAutoSelect() } }
        }

        // DNS routing — covers IPv4 (127.0.0.1) and IPv6 (::1) loopbacks.
        if state.isRoutedThroughProxy {
            Button("Revert system DNS to DHCP") { Task { await state.clearSystemDNS() } }
        } else {
            Button("Route system DNS → proxy") { Task { await state.setSystemDNSToProxy() } }
        }

        Divider()

        Button("Open DNSCryptGUI…") {
            // openWindow recreates the Window scene if it's been closed,
            // and brings it forward if it's already alive. NSApp.activate
            // ensures the app comes to the foreground so the window
            // actually appears on top rather than behind everything else.
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: DNSCryptGUIApp.mainWindowID)
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
