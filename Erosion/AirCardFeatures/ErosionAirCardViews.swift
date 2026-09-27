import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct ErosionAirCardHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { ErosionWalletCardsView() } label: { Label("Wallet Cards", systemImage: "creditcard") }
                NavigationLink { ErosionPasscodeView() } label: { Label("Passcode Theme", systemImage: "circle.grid.3x3") }
                NavigationLink { ErosionWallpapersView() } label: { Label("Wallpapers (.tendies)", systemImage: "photo.stack") }
            } header: {
                HeaderLabel("Airlift Features", symbol: "wand.and.stars")
            } footer: {
                Text("These features use the same imported pairing file and LocalDevVPN connection as Airlift.")
            }
        }
        .navigationTitle("Customization")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ErosionWalletCardsView: View {
    @StateObject private var vm = ErosionAirCardFeatures.shared
    @State private var showPicker = false
    @State private var selectedCardID: String?
    @State private var hash = ""

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: vm.ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(vm.ready ? .green : .orange)
                    Text(vm.ready ? "Airlift ready" : "Import pairing + enable LocalDevVPN")
                        .font(.subheadline)
                }
                Button(vm.walletScanning ? "Stop Card Scan" : "Scan Wallet Cards") {
                    vm.walletScanning ? vm.stopCardScan() : vm.startCardScan()
                }
                .disabled(!ErosionAirlift.shared.hasPairing || vm.walletFlashing)
            } header: { HeaderLabel("Detection", symbol: "waveform") }

            Section {
                HStack {
                    TextField("Card identifier / hash", text: $hash)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add") { vm.addCardHash(hash); hash = "" }
                }
                if vm.cards.isEmpty {
                    Text("No cards detected yet. Open Apple Pay and select a card while the scan is running.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(vm.cards) { card in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { card.isSelected }, set: { value in
                            if let i = vm.cards.firstIndex(where: { $0.id == card.id }) { vm.cards[i].isSelected = value }
                        })).labelsHidden()
                        if let image = card.uiImage {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 58, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 58, height: 36)
                        }
                        Text(String(card.id.prefix(18)) + "…").font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button("Image") { selectedCardID = card.id; showPicker = true }
                            .font(.caption)
                        Button(role: .destructive) { vm.deleteCard(card.id) } label: { Image(systemName: "trash") }
                    }
                }
                if !vm.cards.isEmpty {
                    Button(vm.walletFlashing ? "Applying…" : "Apply Selected Cards") { vm.flashSelectedCards() }
                        .disabled(vm.walletFlashing || !vm.cards.contains(where: { $0.isSelected && $0.customImageData != nil }))
                }
            } header: { HeaderLabel("Cards", symbol: "creditcard") }

            logSection(vm.walletLog)
        }
        .navigationTitle("Wallet Cards")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            PhotoPicker { image in
                if let id = selectedCardID, let image { vm.setCardImage(id: id, image: image) }
                showPicker = false
            }
        }
    }
}

struct ErosionPasscodeView: View {
    @StateObject private var vm = ErosionAirCardFeatures.shared
    @State private var showImporter = false

    var body: some View {
        List {
            Section {
                Button("Import .passthm") { showImporter = true }
                if let theme = vm.loadedTheme {
                    Text("Loaded: \(theme.name) · \(theme.keysPreview.count) keys")
                        .font(.footnote).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach((0...9).map(String.init), id: \.self) { digit in
                            ZStack {
                                Circle().fill(.quaternary)
                                if let image = theme.keysPreview[digit] { Image(uiImage: image).resizable().scaledToFill().clipShape(Circle()) }
                                Text(digit).font(.headline).foregroundStyle(.white).shadow(radius: 2)
                            }.frame(height: 76)
                        }
                    }
                } else {
                    Text("Import a .passthm theme to preview and apply custom TelephonyUI keypad artwork.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { HeaderLabel("Theme", symbol: "circle.grid.3x3") }

            Section {
                Button(vm.passcodeFlashing ? "Applying…" : "Apply Passcode Theme") { vm.flashPassthm() }
                    .disabled(vm.passcodeFlashing || vm.loadedTheme == nil || !vm.ready)
            } header: { HeaderLabel("Apply", symbol: "wand.and.stars") }

            logSection(vm.passcodeLog)
        }
        .navigationTitle("Passcode Theme")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result { vm.importPassthm(url) }
        }
    }
}

struct ErosionWallpapersView: View {
    @StateObject private var vm = ErosionAirCardFeatures.shared
    @State private var showImporter = false

    var body: some View {
        List {
            Section {
                Button("Import .tendies") { showImporter = true }
                Button("Detect PosterBoard Container") { vm.detectPosterBoard() }
                if !vm.posterBoardContainer.isEmpty {
                    Text(vm.posterBoardContainer).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            } header: { HeaderLabel("PosterBoard", symbol: "rectangle.stack") }

            Section {
                if vm.tendieItems.isEmpty {
                    Text("No .tendies wallpapers imported.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach($vm.tendieItems) { $item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $item.isSelected).labelsHidden()
                            if let image = item.uiPreview { Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 60).clipShape(RoundedRectangle(cornerRadius: 7)) }
                            VStack(alignment: .leading) {
                                Text(item.name).lineLimit(1)
                                Text(item.posterType.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { vm.deleteTendie(item) } label: { Image(systemName: "trash") }
                        }
                    }
                }
                Button(vm.wallpaperBusy ? "Applying…" : "Apply Selected Wallpapers") { vm.flashWallpapers() }
                    .disabled(vm.wallpaperBusy || !vm.ready || !vm.tendieItems.contains(where: { $0.isSelected }))
            } header: { HeaderLabel("Wallpapers", symbol: "photo.stack") }

            logSection(vm.wallpaperLog)
        }
        .navigationTitle("Wallpapers")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result { vm.importTendie(url) }
        }
    }
}

private func logSection(_ lines: [String]) -> some View {
    Section {
        Text(lines.isEmpty ? "No output yet." : lines.joined(separator: "\n"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(lines.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
    } header: { HeaderLabel("Log", symbol: "terminal") }
}

private struct PhotoPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first?.itemProvider else { completion(nil); return }
            item.loadObject(ofClass: UIImage.self) { object, _ in DispatchQueue.main.async { self.completion(object as? UIImage) } }
        }
    }
}
