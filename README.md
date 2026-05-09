<table align="center"><tr><td><img width="128" height="128" alt="icon_128x128" src="https://github.com/user-attachments/assets/f558443c-e186-40c8-a788-522f44c67f7b" /></td></tr></table>

# DNSCryptGUI-OSX 💻

A native SwiftUI menu bar + window app for managing [`dnscrypt-proxy`](https://github.com/DNSCrypt/dnscrypt-proxy) on Apple Macs 🍎.

## Features ⭐

- Start / Stop / Restart of the `dnscrypt-proxy` service
- Live status indicator (menu bar + window) with running state, current resolver, and system DNS
- Resolver browser with protocol filter
- TOML config editor with validation and backup-on-save
- Live tail log viewer (last N lines, auto-scrolling)
- Auto-selection mode (let `dnscrypt-proxy` pick fastest servers by protocol)
- One-click Homebrew install / upgrade of `dnscrypt-proxy`
- Set system DNS to 127.0.0.1 or ::1 on the active network service (with admin auth)
- Launch GUI at login (SMAppService, macOS 13+)
- Connection status: resolves `whoami.cloudflare` etc. to confirm DNS is actually going through the proxy
- Coming soon to the AppStore

## Architecture 📂

In Progress...

## Building 🧰

Source code coming soon...

## Runtime requirements 🏃

- macOS 13+ on Apple Silicon (arm64). Intel Macs should also work; Homebrew paths differ (`/usr/local` vs `/opt/homebrew`) and the code handles both.
- Homebrew installed at `/opt/homebrew` (arm64) or `/usr/local` (x86_64).
- The first admin action (install, start, set DNS) will prompt for your password via the standard macOS admin dialog.

## Known TODOs ⏰

- Add resolver latency probing (loop over `127.0.0.1:53` or `::1` with each configured server exclusively enabled and time A queries).
- Replace the handrolled TOML reader in `ProxyConfig`/`ConfigService` with a real TOML library (e.g. TOMLKit) so mutations are lossless across nested tables.
- Add per-interface DNS management (Wi-Fi vs Ethernet) instead of "active service only".

## License 🔑

MIT - do whatever you want.
