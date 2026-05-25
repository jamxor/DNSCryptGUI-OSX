import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Privileged helper") {
                HStack {
                    Circle()
                        .fill(state.helperInstalled ? Color.green : (state.helperAwaitingApproval ? .orange : .red))
                        .frame(width: 10, height: 10)
                    if state.helperInstalled {
                        Text("Installed and approved")
                    } else if state.helperAwaitingApproval {
                        Text("Waiting for approval in System Settings")
                    } else {
                        Text("Not installed")
                    }
                    Spacer()
                    Button("Open Login Items") { state.openLoginItemsSettings() }
                    Button("Retry install") {
                        Task { await state.installHelperIfNeeded() }
                    }
                }
                Text("The helper runs as root and handles brew services, networksetup, and writes to dnscrypt-proxy.toml. You only need to approve it once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch DNSCryptGUI at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.toggleLaunchAtLogin($0) }
                ))
                /// Changing the look of these fields from the beta.
                //LabeledContent("dnscrypt-proxy status", value: state.status.label)
                //LabeledContent("System DNS", value: state.systemDNS.isEmpty ? "DHCP default" : state.systemDNS.joined(separator: ", "))
                //LabeledContent("Connection check", value: state.connectionCheck.label)
                LabeledContent("dnscrypt-proxy Status:") {
                    Text(state.status.label)
                        .foregroundStyle(state.status.color)
                }
                
                LabeledContent("Connection Check:") {
                    Text(state.connectionCheck.label)
                        .foregroundStyle(state.connectionCheck.color)
                }
                
                LabeledContent("System DNS", value: state.systemDNS.isEmpty ? "DHCP default" : state.systemDNS.joined(separator: ", "))
        
            }

            Section("Install / upgrade") {
                HStack {
                    Text(state.isInstalled ? "Installed via Homebrew" : "Not installed")
                    Spacer()
                    if state.isInstalled {
                        Button("Upgrade") { Task { await state.install() } }
                    } else {
                        Button("Install now") { Task { await state.install() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("System DNS") {
                HStack {
                    Button("Route system DNS to loopback (v4 + v6)") {
                        Task { await state.setSystemDNSToProxy() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Revert to DHCP") {
                        Task { await state.clearSystemDNS() }
                    }
                }
                Text("Changes the DNS servers for the active network service. Needs admin.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Protocol filter (resolver list)") {
                // Mirrors the chip bar on the Resolvers tab.
                ForEach([DNSProtocol.dnscrypt, .doh, .odohTarget, .dnscryptRelay, .odohRelay, .plainDNS, .doq, .dot], id: \.self) { p in
                    Toggle(p.label, isOn: Binding(
                        get: { state.protocolFilter.contains(p) },
                        set: { on in
                            if on { state.protocolFilter.insert(p) }
                            else  { state.protocolFilter.remove(p) }
                        }
                    ))
                }
            }

            Section("Paths") {
                LabeledContent("Config", value: state.config.configPath)
                    .font(.caption)
                LabeledContent("Proxy Log", value: state.log.currentLogPath)
                    .font(.caption)
                LabeledContent("Query Log", value: state.log.currentQueryPath)
                    .font(.caption)
                LabeledContent("NXDOMAIN Log", value: state.log.currentNXPath)
                    .font(.caption)
            }

            Section("About") {
                Link("HlinCore Security Team - Official website",
                     destination: URL(string: "https://www.hlincore.com")!)
                Link("dnscrypt-proxy on GitHub",
                     destination: URL(string: "https://github.com/DNSCrypt/dnscrypt-proxy")!)
                Link("DNS Stamp spec",
                     destination: URL(string: "https://dnscrypt.info/stamps-specifications/")!)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}
