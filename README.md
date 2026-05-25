<table align="center"><tr><td><img width="128" height="128" alt="icon_128x128" src="https://github.com/user-attachments/assets/f558443c-e186-40c8-a788-522f44c67f7b" /></td></tr></table>

# DNSCryptGUI-OSX 💻

A native SwiftUI menu bar + window app for managing [`dnscrypt-proxy`](https://github.com/DNSCrypt/dnscrypt-proxy) on Apple Macs 🍎.

## Features ⭐

- Start / stop / restart the `dnscrypt-proxy` service via a privileged XPC helper — no AppleScript prompts, no per-action password dialogs.
- Live status indicator in the menu bar and main window. The menu bar icon distinguishes "proxy running and DNS routed through it" from "proxy running but system DNS still points elsewhere," so a partial-routing leak is visible at a glance.
- Resolver browser with protocol filter (DNSCrypt, DoH, DoT, DoQ, Anonymized DNSCrypt relay, ODoH target, ODoH relay, plain).
- TOML config editor with validation and backup-on-save.
- Live log viewer with a picker for the three dnscrypt-proxy streams — server log (default), query log (`[query_log]`, every resolved query), and NXDOMAIN log (`[nx_log]`, blocked / cloaked names). The picker reflects the live TOML so adding a section and restarting the proxy lights up the corresponding stream without restarting the app.
- Auto-selection mode (let `dnscrypt-proxy` pick the fastest servers per protocol).
- One-click Homebrew install / upgrade of `dnscrypt-proxy`.
- Toggle system DNS to `127.0.0.1` (and `::1`) on the active network service.
- Launch GUI at login (`SMAppService`, macOS 13+). The menu bar status and connection check populate at login — opening the dashboard isn't required.
- Connection probe — runs a canary lookup against the loopback to confirm the proxy is responsive, then verifies the system DNS list contains *only* loopback entries. A mixed list like `["8.8.8.8", "::1"]` is reported as unrouted, because macOS will send most queries to Google rather than the proxy.
- Coming soon to the AppStore

## Architecture 📂
The app is split into three Swift targets:

```
DNSCryptGUI/                    # SwiftUI app target (runs as user)
├── DNSCryptGUIApp.swift        # @main, Window + MenuBarExtra scenes
├── AppState.swift              # @MainActor ObservableObject — app-wide state
├── Models/
│   ├── DNSStamp.swift          # sdns:// stamp parser
│   ├── Resolver.swift          # Resolver metadata
│   ├── ProxyStatus.swift       # running / stopped / errored / unknown
│   └── ProxyConfig.swift       # TOML-backed config model
├── Services/
│   ├── HelperClient.swift      # NSXPCConnection wrapper for the helper
│   ├── ProxyService.swift      # Routes start/stop/status through helper
│   ├── BrewService.swift       # Detect / install / upgrade dnscrypt-proxy
│   ├── ConfigService.swift     # Read/write dnscrypt-proxy.toml (write via helper)
│   ├── LogService.swift        # File-tail log reader
│   ├── NetworkService.swift    # System DNS toggle (write via helper)
│   ├── ResolverService.swift   # Fetches public-resolvers.md / relays.md
│   ├── LaunchAtLoginService.swift  # SMAppService.mainApp wrapper
│   └── PrivilegedShell.swift   # Non-privileged Process runner
└── Views/
    ├── ContentView.swift, DashboardView.swift, ResolversView.swift,
    └── ConfigEditorView.swift, LogsView.swift, SettingsView.swift, MenuBarView.swift

DNSCryptGUIHelper/              # Privileged daemon target (runs as root)
├── HelperTool.swift            # NSXPCListener delegate, validates clients
├── main.swift                  # Daemon entry point — listener + dispatchMain
├── HelperInfo.plist            # Embedded into binary; SMAuthorizedClients
└── com.hlincore.DNSCryptGUI.Helper.plist   # launchd plist

DNSCryptGUIShared/              # Common code, in BOTH targets
└── HelperProtocol.swift        # @objc XPC protocol + mach service constants
```

The privileged helper is registered via `SMAppService.daemon(plistName:)` (macOS 13+), which is Apple's modern replacement for `SMJobBless`. The user approves the helper once in System Settings → Login Items, after which the GUI calls into it over XPC for any operation that needs root: starting/stopping the proxy, writing the TOML config, toggling system DNS.

Each side validates the other:
- **GUI → helper**: `SMPrivilegedExecutables` in the app's Info.plist names the helper's bundle ID and a designated requirement string. `SMAppService` enforces this at install time.
- **Helper → GUI**: `SMAuthorizedClients` in the helper's Info.plist + a runtime `SecCode` check in `verifyClient` (Team ID + bundle ID).

Read-only status (`launchctl list`) routes through the helper too, because querying a system-domain launchd service requires root on modern macOS.

## Building 🧰

You'll need an Xcode project. The repo is organised as plain source folders so it can drop into a new project cleanly.

### 1. Create the Xcode project

1. File → New → Project → macOS → **App**. Name **DNSCryptGUI**, Interface **SwiftUI**, Language **Swift**, Minimum Deployment **macOS 13.0**.
2. Delete the default `ContentView.swift` and the default `@main` app file.
3. Drag `Sources/DNSCryptGUI/` into the project. Add to the **app** target only.
4. File → New → Target → macOS → **Command Line Tool**. Name **DNSCryptGUIHelper**, Language **Swift**.
5. Drag `Sources/DNSCryptGUIHelper/` into the helper target. Add to the **helper** target only.
6. Drag `Sources/DNSCryptGUIShared/HelperProtocol.swift` into the project and check **both** targets in Target Membership.

### 2. Build settings

App target:
- **Signing & Capabilities** → App Sandbox **off**. (The app shells out to `brew`, `networksetup`, `dig` and cannot be sandboxed.)
- **Build Settings** → `INFOPLIST_FILE` = `Sources/DNSCryptGUI/Resources/Info.plist`.
- **Build Settings** → `CODE_SIGN_ENTITLEMENTS` = `Sources/DNSCryptGUI/Resources/DNSCryptGUI.entitlements`.

Helper target:
- **Build Settings** → `CREATE_INFOPLIST_SECTION_IN_BINARY` = **YES** (embeds Info.plist into the Mach-O — required for command-line-tool helpers).
- **Build Settings** → `INFOPLIST_FILE` = `Sources/DNSCryptGUIHelper/HelperInfo.plist`.
- **Build Settings** → `GENERATE_INFOPLIST_FILE` = **NO**.
- **Build Settings** → `SKIP_INSTALL` = **NO**.

Both targets:
- **Signing & Capabilities** → **Hardened Runtime** on (required for notarization).
- **Signing & Capabilities** → Same Team and signing identity. For shipping, use **Developer ID Application**.

### 3. Embed the helper in the app bundle

On the app target, Build Phases → **+** → **New Copy Files Phase**:

- Destination: **Wrapper** (or "Absolute Path") with subpath `Contents/Library/LaunchDaemons`.
- Add the helper product (`DNSCryptGUIHelper`) to the phase.
- Add `com.hlincore.DNSCryptGUI.Helper.plist` to the phase.

After a successful build, the app bundle layout should be:

```
DNSCryptGUI.app/
└── Contents/
    ├── MacOS/
    │   └── DNSCryptGUI
    └── Library/
        └── LaunchDaemons/
            ├── DNSCryptGUIHelper                              # signed Mach-O
            └── com.hlincore.DNSCryptGUI.Helper.plist          # launchd plist
```

This is the layout `SMAppService.daemon(plistName:)` reads from.

### 4. Bundle identifiers

If you fork this project, you must change the bundle IDs and update every reference together:

- App: `com.hlincore.DNSCryptGUI` → `<your-id>`
- Helper: `com.hlincore.DNSCryptGUI.Helper` → `<your-id>.Helper`
- Helper plist filename: `com.hlincore.DNSCryptGUI.Helper.plist` → `<your-id>.Helper.plist`

Files that reference these IDs:
- `Sources/DNSCryptGUI/Resources/Info.plist` — `CFBundleIdentifier`, `SMPrivilegedExecutables` (key + designated requirement)
- `Sources/DNSCryptGUIHelper/HelperInfo.plist` — `CFBundleIdentifier`, `SMAuthorizedClients` requirement
- `Sources/DNSCryptGUIHelper/<helper-id>.plist` — `Label`, `MachServices` key, file *name*
- `Sources/DNSCryptGUIHelper/HelperTool.swift` — fallback bundle ID, `os.Logger` subsystem
- `Sources/DNSCryptGUIShared/HelperProtocol.swift` — `kHelperMachServiceName`, `kHelperPlistName`

A `grep -r "com.hlincore" Sources/` will surface them all.

### 5. Signing

After building, verify both binaries (DNSCryptGUI and DNSCryptGUIHelper) have the same signing ID or the app will be blocked by Gatekeeper. You can sign using a local certificate to just run locally, or if you want to release your own version, you'll need to sign up for a Developer ID through Apple.

```bash
codesign -dvvv "DNSCryptGUI.app" 2>&1 | grep -E "Authority|TeamIdentifier"
codesign -dvvv "DNSCryptGUI.app/Contents/Library/LaunchDaemons/DNSCryptGUIHelper" 2>&1 | grep -E "Authority|TeamIdentifier"
```
## First-run UX

When the user launches from a fresh install, `AppState.bootstrap()` calls `HelperClient.install()` which invokes `SMAppService.daemon(plistName:).register()`. Three outcomes:

- **First time, never approved**: status becomes `.requiresApproval`, the app opens **System Settings → General → Login Items & Extensions**, and the user flips the toggle for DNSCryptGUI. No password prompt.
- **Already approved on this Mac**: status is `.enabled`, no UI.
- **Previously denied**: the user has to flip the toggle in Settings. The Settings tab in DNSCryptGUI has an "Open Login Items" button that deep-links there.

Once approved, all privileged operations go over XPC silently — no further prompts.

## Runtime requirements 🏃

- macOS 13+ (Apple Silicon or Intel). `MenuBarExtra` and `SMAppService.daemon` require this.
- Homebrew installed at `/opt/homebrew` (arm64) or `/usr/local` (x86_64).
- `dnscrypt-proxy` installed via Homebrew. The app can install it for you on first launch if it's missing.

## Known TODOs ⏰

- Add resolver latency probing (loop over `127.0.0.1:53` or `::1` with each configured server exclusively enabled and time A queries).
- Replace the handrolled TOML reader in `ProxyConfig`/`ConfigService` with a real TOML library (e.g. TOMLKit) so mutations are lossless across nested tables.
- Add per-interface DNS management (Wi-Fi vs Ethernet) instead of "active service only".

## License 🔑

MIT - do whatever you want.
