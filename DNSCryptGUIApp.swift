import SwiftUI

@main
struct DNSCryptGUIApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        // Main window: a single-instance `Window` (not `WindowGroup`) so
        // closing it with the red X doesn't destroy the scene. The window
        // can be re-opened from the menu bar via openWindow(id:).
        Window("DNSCryptGUI", id: Self.mainWindowID) {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 820, minHeight: 560)
                .task { await state.bootstrap() }
                // When the user comes back from System Settings (after
                // toggling Login Items approval), the scene becomes active
                // again - time to re-poll the helper's status so
                // the awaiting-approval banner clears on its own.
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        Task { await state.refreshHelperStatus() }
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New" menu item
        }

        // NOTE: MenuBarExtra with .menu style renders each row as an NSMenuItem,
        // which does NOT propagate SwiftUI's environment. Pass `state` directly.
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.menuBarSymbol)
                .task(id: "bootstrap") { await state.bootstrap() }
        }
        .menuBarExtraStyle(.menu)
    }

    /// Stable identifier shared by the main Window scene and the
    /// menu bar's openWindow(id:) call.
    static let mainWindowID = "main"
}
