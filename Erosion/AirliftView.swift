import SwiftUI
import Combine
import UniformTypeIdentifiers

struct AirliftView: View {
    @StateObject private var airlift = ErosionAirlift.shared
    @State private var showImporter = false
    @State private var vpnConnected = AirliftNetworkStatus.isConnected()
    @State private var tunnelIP = AirliftNetworkStatus.tunnelIP()
    @State private var copied = false

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: vpnConnected ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(vpnConnected ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LocalDevVPN").font(.headline)
                        Text(vpnConnected ? "Connected" : "Not connected")
                            .foregroundStyle(vpnConnected ? .green : .orange)
                        if let tunnelIP {
                            Text(tunnelIP)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)

                if !vpnConnected {
                    Text("Enable LocalDevVPN before running Airlift. This screen only detects the tunnel; it does not create the VPN profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                HeaderLabel("Experimental", symbol: "flask")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    HStack {
                        Label("Import Pairing File", systemImage: "doc.badge.plus")
                        Spacer()
                        if airlift.hasPairing {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }

                HStack {
                    Text("Status")
                    Spacer()
                    Text(airlift.pairingStatus)
                        .font(.footnote)
                        .foregroundStyle(airlift.hasPairing ? .green : .secondary)
                        .multilineTextAlignment(.trailing)
                }

                if airlift.hasPairing {
                    Button("Delete Pairing File", role: .destructive) {
                        airlift.deletePairing()
                    }
                }
            } header: {
                HeaderLabel("Pairing", symbol: "link.circle")
            } footer: {
                Text("Airlift needs a real Apple pairing record. The import check verifies the plist structure and common pairing fields; the Airlift core performs the final credential validation.")
            }

            Section {
                TextField("Target directory", text: $airlift.target)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    airlift.runExploit()
                } label: {
                    HStack {
                        Text("Run Airlift")
                        Spacer()
                        if case .running = airlift.state {
                            ProgressView()
                        }
                    }
                }
                .disabled(!airlift.hasPairing || !vpnConnected || isRunning)

                if case .done(let ok, let message) = airlift.state {
                    Label(message, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ok ? .green : .red)
                        .font(.footnote)
                }
            } header: {
                HeaderLabel("Airlift", symbol: "cpu")
            }

            Section {
                if airlift.exploitLog.isEmpty {
                    Text("No output yet.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, design: .monospaced))
                } else {
                    Text(airlift.exploitLog.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack {
                    Button(copied ? "Copied!" : "Copy Log") {
                        UIPasteboard.general.string = airlift.exploitLog.joined(separator: "\n")
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                    .disabled(airlift.exploitLog.isEmpty)

                    Spacer()

                    Button("Clear", role: .destructive) {
                        airlift.clearLog()
                    }
                    .disabled(airlift.exploitLog.isEmpty)
                }
            } header: {
                HeaderLabel("Log", symbol: "terminal")
            }
        }
        .navigationTitle("Airlift")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data, .propertyList, .item]
        ) { result in
            switch result {
            case .success(let url):
                _ = airlift.importPairing(from: url)
            case .failure(let error):
                airlift.clearLog()
                print("[airlift] import failed: \(error.localizedDescription)")
            }
        }
        .onAppear { refresh() }
        .onReceive(ticker) { _ in refresh() }
    }

    private var isRunning: Bool {
        if case .running = airlift.state { return true }
        return false
    }

    private func refresh() {
        let connected = AirliftNetworkStatus.isConnected()
        let ip = AirliftNetworkStatus.tunnelIP()
        if connected != vpnConnected { vpnConnected = connected }
        if ip != tunnelIP { tunnelIP = ip }
    }
}
