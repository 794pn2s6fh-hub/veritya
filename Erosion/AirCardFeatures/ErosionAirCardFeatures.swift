import SwiftUI
import UIKit
import Foundation

@MainActor
final class ErosionAirCardFeatures: ObservableObject {
    static let shared = ErosionAirCardFeatures()

    @Published var cards: [CardItem] = []
    @Published var walletLog: [String] = []
    @Published var walletScanning = false
    @Published var walletFlashing = false

    @Published var loadedTheme: PasscodeThemeInfo?
    @Published var passcodeLog: [String] = []
    @Published var passcodeFlashing = false

    @Published var tendieItems: [TendieItem] = []
    @Published var wallpaperLog: [String] = []
    @Published var wallpaperBusy = false
    @Published var posterBoardContainer = ""

    private var syslogRunning = false
    private static let cardRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"PDCardFileManager: writing card\s+([A-Za-z0-9+/_-]+={0,2})(?=\s|\)|,|$)"#),
        try! NSRegularExpression(pattern: #"(?:pass|card).{0,80}(?:id|identifier|uniqueID)[=: ]+([A-Za-z0-9+/_-]{20,64})"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"/var/mobile/Library/Passes/Cards/([^/]+)\.pkpass"#)
    ]

    private init() {
        loadSavedCards()
        loadTendies()
        posterBoardContainer = UserDefaults.standard.string(forKey: "erosion.posterboard_container") ?? ""
    }

    var pairingPath: String { ErosionAirlift.shared.pairingPath }
    var ready: Bool { ErosionAirlift.shared.hasPairing && AirliftNetworkStatus.isConnected() }

    // MARK: Wallet

    nonisolated static func cardImagePath(for cardId: String) -> URL {
        let safe = cardId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WalletCards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("card_\(safe).png")
    }

    func loadSavedCards() {
        let saved = UserDefaults.standard.stringArray(forKey: "erosion.wallet.cards") ?? []
        cards = saved.compactMap { CardItem.cleanCardId($0) }.map { id in
            let data = try? Data(contentsOf: Self.cardImagePath(for: id))
            return CardItem(id: id, customImageData: data, customImage: data.flatMap { ImageEngine.safeImageFromData($0, maxDimension: 512) })
        }
    }

    func saveCards() {
        UserDefaults.standard.set(cards.map(\.id), forKey: "erosion.wallet.cards")
    }

    func addCardHash(_ raw: String) {
        for part in raw.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))) {
            guard let id = CardItem.cleanCardId(part), !cards.contains(where: { $0.id == id }) else { continue }
            cards.append(CardItem(id: id))
        }
        saveCards()
    }

    func setCardImage(id: String, image: UIImage) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        let thumb = ImageEngine.normalizeAndDownsample(image, maxDimension: 512)
        cards[i].customImage = thumb
        cards[i].customImageData = ImageEngine.prepareCardImage(from: image)
        if let data = cards[i].customImageData { try? data.write(to: Self.cardImagePath(for: id), options: .atomic) }
    }

    func deleteCard(_ id: String) {
        cards.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.cardImagePath(for: id))
        saveCards()
    }

    func startCardScan() {
        guard ErosionAirlift.shared.hasPairing else {
            walletLog.append("❌ Import a pairing file first."); return
        }
        guard !syslogRunning else { return }
        walletLog.removeAll()
        walletScanning = true
        syslogRunning = true
        let pair = pairingPath
        walletLog.append("🔎 Scanning device log for Wallet card identifiers…")

        guard let strongSelf = self else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var error: UnsafeMutablePointer<CChar>?
            let rc = pair.withCString { p in
                al_syslog_stream_start(p, { ctx, line in
                    guard let ctx, let line else { return }
                    let owner = Unmanaged<ErosionAirCardFeatures>.fromOpaque(ctx).takeUnretainedValue()
                    owner.parseWalletLog(String(cString: line))
                }, Unmanaged.passUnretained(strongSelf).toOpaque(), &error)
            }
            if let error { let message = String(cString: error); al_string_free(error); DispatchQueue.main.async { strongSelf.walletLog.append("❌ Syslog error: \(message)") } }
            DispatchQueue.main.async { strongSelf.walletScanning = false; strongSelf.syslogRunning = false; strongSelf.walletLog.append("⏹ Scan stopped.") }
            _ = rc
        }
    }

    func stopCardScan() {
        guard syslogRunning else { return }
        al_syslog_stream_stop()
        syslogRunning = false
        walletScanning = false
    }

    nonisolated private func parseWalletLog(_ line: String) {
        for regex in Self.cardRegexes {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges > 1 {
                let raw = ns.substring(with: match.range(at: 1))
                Task { @MainActor in self.addCardHash(raw); self.walletLog.append("✅ Found card: \(raw.prefix(16))…") }
                return
            }
        }
    }

    func flashSelectedCards() {
        guard ready else { walletLog.append("❌ Pairing file and LocalDevVPN are required."); return }
        let selected = cards.filter { $0.isSelected && ($0.customImage != nil || $0.customImageData != nil) }
        guard !selected.isEmpty else { walletLog.append("❌ Select a card with custom artwork first."); return }
        walletFlashing = true
        walletLog.removeAll()
        let pair = pairingPath

        guard let strongSelf = self else { return }
        Task.detached {
            var success = 0
            for card in selected {
                let id = CardItem.cleanCardId(card.id) ?? card.id
                let source = card.customImageData.flatMap(UIImage.init(data:)).flatMap { ImageEngine.prepareAllCardSkins(from: $0) } ?? [:]
                guard !source.isEmpty else { continue }
                let stage = FileManager.default.temporaryDirectory.appendingPathComponent("erosion_wallet_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                for (name, data) in source { try? data.write(to: stage.appendingPathComponent(name)) }
                let target = "/var/mobile/Library/Passes/Cards/\(id).pkpass"
                let ok = await Self.writeDirectory(pair: pair, source: stage.path, target: target) { line in
                    Task { @MainActor in strongSelf.walletLog.append("  \(line)") }
                }
                try? FileManager.default.removeItem(at: stage)
                if ok {
                    success += 1
                    await MainActor.run { strongSelf.walletLog.append("✅ Applied artwork to \(id.prefix(12))…") }
                } else {
                    await MainActor.run { strongSelf.walletLog.append("❌ Failed to write \(id.prefix(12))…") }
                }

                let inv = FileManager.default.temporaryDirectory.appendingPathComponent("erosion_wallet_inv_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: inv, withIntermediateDirectories: true)
                for leaf in ["FrontFace", "Preview", "PlaceHolder"] { try? Data("corrupted".utf8).write(to: inv.appendingPathComponent(leaf)) }
                for ext in [".cache", ".pkcache"] { _ = await Self.writeDirectory(pair: pair, source: inv.path, target: "/var/mobile/Library/Passes/Cards/\(id)\(ext)", log: nil) }
                try? FileManager.default.removeItem(at: inv)
            }
            await MainActor.run {
                strongSelf.walletFlashing = false
                strongSelf.walletLog.append("🎉 \(success)/\(selected.count) card(s) processed. Force-close Wallet to refresh artwork.")
            }
        }
    }

    // MARK: Passcode

    func importPassthm(_ url: URL) {
        Task.detached { [weak self] in
            let result = PasscodeThemeReader.inspect(url: url)
            await MainActor.run {
                guard let result else { self?.passcodeLog.append("❌ Invalid or unsupported .passthm file."); return }
                self?.loadedTheme = PasscodeThemeInfo(name: url.deletingPathExtension().lastPathComponent, filePath: url.path, fileCount: result.fileCount, keysPreview: result.keys, rawKeyData: result.rawData)
                self?.passcodeLog = ["✅ Loaded \(result.keys.count) keypad images from \(url.lastPathComponent)"]
            }
        }
    }

    func flashPassthm() {
        guard ready, let theme = loadedTheme else { passcodeLog.append("❌ Pairing, LocalDevVPN and a .passthm theme are required."); return }
        passcodeFlashing = true
        passcodeLog.removeAll()
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("erosion_passthm_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let langs = KeypadLocales.all
        let suffixes = ["", "-bold"]
        for (digit, image) in theme.keysPreview {
            let data = theme.rawKeyData[digit] ?? image.pngData()
            guard let data else { continue }
            let subtext = KeypadLayout.subtexts[digit] ?? ""
            for lang in langs { for suffix in suffixes {
                let names: [String]
                if digit == "0" { names = ["\(lang)-0---white\(suffix).png", "\(lang)-0-+--white\(suffix).png"] }
                else if digit == "1" { names = ["\(lang)-1---white\(suffix).png"] }
                else { names = ["\(lang)-\(digit)---white\(suffix).png", "\(lang)-\(digit)-\(subtext)--white\(suffix).png"] }
                for name in names { try? data.write(to: stage.appendingPathComponent(name)) }
            }}
        }
        try? Data().write(to: stage.appendingPathComponent("_big"))
        let pair = pairingPath
        Task.detached { [weak self] in
            let targets = ["/var/mobile/Library/Caches/TelephonyUI-10", "/var/mobile/Library/Caches/TelephonyUI-9", "/var/mobile/Library/Caches/TelephonyUI-8"]
            var ok = true
            for target in targets {
                let result = await Self.writeDirectory(pair: pair, source: stage.path, target: target) { line in
                    Task { @MainActor in self?.passcodeLog.append("  \(line)") }
                }
                ok = ok && result
            }
            try? FileManager.default.removeItem(at: stage)
            await MainActor.run {
                self?.passcodeFlashing = false
                self?.passcodeLog.append(ok ? "🎉 Passcode theme applied. Lock the device to see it." : "❌ One or more TelephonyUI cache writes failed.")
            }
        }
    }

    // MARK: Wallpapers

    func importTendie(_ url: URL) {
        Task { @MainActor in
            do {
                let item = try await TendiesEngine.shared.importTendie(from: url)
                tendieItems.removeAll { $0.fileName == item.fileName }
                tendieItems.append(item)
                saveTendies()
                wallpaperLog.append("✅ Imported \(item.name)")
            } catch { wallpaperLog.append("❌ \(error.localizedDescription)") }
        }
    }

    func loadTendies() {
        if let data = UserDefaults.standard.data(forKey: "erosion.tendies.items"), let items = try? JSONDecoder().decode([TendieItem].self, from: data) { tendieItems = items }
    }

    func saveTendies() {
        if let data = try? JSONEncoder().encode(tendieItems) { UserDefaults.standard.set(data, forKey: "erosion.tendies.items") }
    }

    func deleteTendie(_ item: TendieItem) {
        try? FileManager.default.removeItem(at: item.fileURL)
        tendieItems.removeAll { $0.id == item.id }
        saveTendies()
    }

    func detectPosterBoard() {
        guard ErosionAirlift.shared.hasPairing else { wallpaperLog.append("❌ Import a pairing file first."); return }
        Task { @MainActor in
            do {
                posterBoardContainer = try await TendiesEngine.shared.detectPosterBoardContainer(pairingPath: pairingPath)
                UserDefaults.standard.set(posterBoardContainer, forKey: "erosion.posterboard_container")
                wallpaperLog.append("✅ PosterBoard container detected.")
            } catch { wallpaperLog.append("❌ Detection failed: \(error.localizedDescription)") }
        }
    }

    func flashWallpapers() {
        guard ready else { wallpaperLog.append("❌ Pairing file and LocalDevVPN are required."); return }
        let selected = tendieItems.filter(\.isSelected)
        guard !selected.isEmpty else { wallpaperLog.append("❌ Import/select a .tendies wallpaper first."); return }
        wallpaperBusy = true
        wallpaperLog.removeAll()
        Task { @MainActor in
            do {
                var container = posterBoardContainer
                if container.isEmpty { container = try await TendiesEngine.shared.detectPosterBoardContainer(pairingPath: pairingPath); posterBoardContainer = container }
                try await TendiesEngine.shared.flashTendies(items: selected, containerPath: container, resetProtections: true, pairingPath: pairingPath, log: { [weak self] line in self?.wallpaperLog.append(line) }, progress: { _ in })
                wallpaperLog.append("🎉 Wallpapers injected. Refreshing SpringBoard…")
                var error: UnsafeMutablePointer<CChar>?
                _ = pairingPath.withCString { al_device_respring($0, nil, nil, &error) }
                if let error { al_string_free(error) }
            } catch { wallpaperLog.append("❌ \(error.localizedDescription)") }
            wallpaperBusy = false
        }
    }

    nonisolated private static func writeDirectory(pair: String, source: String, target: String, log: ((String) -> Void)?) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var outError: UnsafeMutablePointer<CChar>?
                let rc = pair.withCString { p in source.withCString { s in target.withCString { t in
                    al_exploit_write_dir(p, s, t, { _, msg in if let msg { log?(String(cString: msg)) } }, nil, &outError)
                }}}
                if let outError { log?(String(cString: outError)); al_string_free(outError) }
                continuation.resume(returning: rc == 0)
            }
        }
    }
}
