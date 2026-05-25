import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // --- Helper approval banner ---
                // Highest-priority banner: if the user hasn't yet approved the
                // privileged helper in Login Items, *nothing else works*, so
                // we put it above everything. Disappears as soon as the
                // scene-phase observer picks up that approval was granted.
                if state.helperAwaitingApproval {
                    helperApprovalBanner
                }

                // --- Install banner ---
                if !state.isInstalled {
                    installBanner
                }

                // --- Status card ---
                GroupBox("Proxy Service") {
                    HStack(alignment: .center, spacing: 16) {
                        Circle()
                            .fill(state.status.color)
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.status.label)
                                .font(.title3).bold()
                            Text("dnscrypt-proxy via Homebrew service")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack {
                            Button { Task { await state.start() } } label: {
                                Label("Start", systemImage: "play.fill")
                            }.disabled(state.status == .running)
                            Button { Task { await state.stop() } } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }.disabled(state.status != .running)
                            Button { Task { await state.restart() } } label: {
                                Label("Restart", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                // --- Connection check card ---
                GroupBox("Connection") {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(state.connectionCheck.color)
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading) {
                            Text(state.connectionCheck.label).font(.headline)
                            Text("System DNS: \(state.systemDNS.isEmpty ? "DHCP default" : state.systemDNS.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.isRoutedThroughProxy {
                            Button("Revert DNS to DHCP") { Task { await state.clearSystemDNS() } }
                        } else {
                            Button("Route DNS → proxy") { Task { await state.setSystemDNSToProxy() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // --- Current selection card ---
                GroupBox("Active resolvers") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let cfg = state.currentConfig, !cfg.isAutoSelect {
                            ForEach(cfg.serverNames, id: \.self) { name in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(name).monospaced()
                                }
                            }
                            HStack {
                                Spacer()
                                Button("Switch to auto-select") {
                                    Task { await state.enableAutoSelect() }
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Auto-select mode (dnscrypt-proxy picks fastest servers matching your filters).")
                            }
                        }
                    }.padding(.vertical, 6)
                }

                // --- Quick filter summary ---
                if let cfg = state.currentConfig {
                    GroupBox("Config summary") {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
                            summaryRow("Listen", cfg.listenAddresses.joined(separator: ", "))
                            summaryRow("DNSCrypt servers", cfg.dnscryptServers ? "yes" : "no")
                            summaryRow("DoH servers", cfg.dohServers ? "yes" : "no")
                            summaryRow("ODoH servers", cfg.odohServers ? "yes" : "no")
                            summaryRow("Require DNSSEC", cfg.requireDNSSEC ? "yes" : "no")
                            summaryRow("Require no-log", cfg.requireNoLog ? "yes" : "no")
                            summaryRow("Require no-filter", cfg.requireNoFilter ? "yes" : "no")
                            summaryRow("Log file", cfg.logFile ?? "—")
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(20)
        }
    }

    private var installBanner: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("dnscrypt-proxy is not installed").font(.headline)
                    Text("Install the official Homebrew formula — signed by the Homebrew core tap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Install via Homebrew") { Task { await state.install() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 6)
        }
    }

    /// First-run blocker: the privileged helper has been registered with
    /// launchd but the user hasn't flipped the approval toggle in System
    /// Settings → General → Login Items & Extensions yet. Without that the
    /// XPC channel won't activate, so every privileged action below would
    /// fail with "Couldn't communicate with helper application."
    private var helperApprovalBanner: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approve the DNSCryptGUI helper").font(.headline)
                    Text("Open System Settings → General → Login Items & Extensions and turn on DNSCryptGUI under “Allow in the Background.” The status here will update automatically once you return.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(spacing: 6) {
                    Button("Open Login Items") { state.openLoginItemsSettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Re-check") {
                        Task { await state.refreshHelperStatus() }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func summaryRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospaced()
        }
    }
}
