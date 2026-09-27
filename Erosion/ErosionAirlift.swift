import Foundation
import Combine

final class ErosionAirlift: ObservableObject {
    static let shared = ErosionAirlift()

    enum State: Equatable {
        case idle
        case running
        case done(ok: Bool, message: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var pairingStatus = "No pairing file selected"
    @Published private(set) var exploitLog: [String] = []
    @Published var target = "/var/mobile/Library/SpringBoard"

    private let pairingURL: URL
    private var lines: [String] = []

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        pairingURL = documents.appendingPathComponent("erosion_airlift_pairing.plist")
        if hasPairing {
            pairingStatus = "Pairing file imported"
        }
        al_log_init({ _, message in
            guard let message else { return }
            let line = String(cString: message)
            DispatchQueue.main.async {
                ErosionAirlift.shared.appendLog(line)
            }
        }, nil)
    }

    var hasPairing: Bool {
        FileManager.default.fileExists(atPath: pairingURL.path)
        && ((try? FileManager.default.attributesOfItem(atPath: pairingURL.path)[.size] as? Int) ?? 0) > 0
    }

    var pairingPath: String { pairingURL.path }

    @discardableResult
    func importPairing(from source: URL) -> Result<Void, Error> {
        do {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: source)
            try Self.validatePairingPlist(data)

            try data.write(to: pairingURL, options: .atomic)
            pairingStatus = "Pairing file imported (\(data.count) B)"
            state = .idle
            return .success(())
        } catch {
            pairingStatus = "Invalid pairing file: \(error.localizedDescription)"
            return .failure(error)
        }
    }

    func deletePairing() {
        try? FileManager.default.removeItem(at: pairingURL)
        pairingStatus = "No pairing file selected"
        state = .idle
    }

    func runExploit() {
        guard hasPairing else {
            state = .done(ok: false, message: "Import a pairing file first.")
            return
        }
        guard AirliftNetworkStatus.isConnected() else {
            state = .done(ok: false, message: "LocalDevVPN is not connected.")
            return
        }

        state = .running
        lines.removeAll()
        exploitLog.removeAll()
        let path = pairingURL.path
        let destination = target.trimmingCharacters(in: .whitespacesAndNewlines)

        Task.detached {
            var outJSON: UnsafeMutablePointer<CChar>?
            var outError: UnsafeMutablePointer<CChar>?

            let rc = path.withCString { pairing in
                destination.withCString { target in
                    al_exploit_run(pairing, target, nil, nil, &outJSON, &outError)
                }
            }

            let json = outJSON.map { pointer -> String in
                let value = String(cString: pointer)
                al_string_free(pointer)
                return value
            }
            let error = outError.map { pointer -> String in
                let value = String(cString: pointer)
                al_string_free(pointer)
                return value
            }

            await MainActor.run {
                if rc == 0 {
                    self.appendLog("[airlift] success: \(json ?? "ok")")
                    self.state = .done(ok: true, message: json ?? "Airlift completed.")
                } else {
                    self.appendLog("[airlift] failed: \(error ?? "rc=\(rc)")")
                    self.state = .done(ok: false, message: error ?? "Airlift failed (rc=\(rc)).")
                }
            }
        }
    }

    func clearLog() {
        lines.removeAll()
        exploitLog.removeAll()
    }

    private func appendLog(_ line: String) {
        lines.append(line)
        if lines.count > 600 { lines.removeFirst(lines.count - 600) }
        exploitLog = lines
    }

    private static func validatePairingPlist(_ data: Data) throws {
        guard !data.isEmpty else { throw PairingValidationError.empty }
        var format = PropertyListSerialization.PropertyListFormat.binary
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard let dict = object as? [String: Any], !dict.isEmpty else {
            throw PairingValidationError.notPairingRecord
        }

        // Pairing records vary slightly by iOS/tooling. Require several identity/
        // certificate fields rather than hard-coding one exact schema. The Airlift
        // core performs the authoritative cryptographic validation when it connects.
        let identityKeys = [
            "HostID", "SystemBUID", "DeviceCertificate", "HostCertificate",
            "HostPrivateKey", "RootCertificate", "DevicePublicKey"
        ]
        let matches = identityKeys.filter { dict[$0] != nil }
        guard matches.count >= 2 else {
            throw PairingValidationError.missingIdentityFields
        }
    }

    enum PairingValidationError: LocalizedError {
        case empty, notPairingRecord, missingIdentityFields

        var errorDescription: String? {
            switch self {
            case .empty:
                return "The selected file is empty."
            case .notPairingRecord:
                return "The selected file is not a property-list pairing record."
            case .missingIdentityFields:
                return "The file is a plist, but it does not look like a valid Apple pairing record."
            }
        }
    }
}
