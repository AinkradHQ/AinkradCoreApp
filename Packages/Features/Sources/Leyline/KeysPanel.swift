import AppKit
import CoreUI
import SwiftUI

/// The Keys panel: slides in over the right of the map or the list, the pane's full height, the map usable beside it. The
/// keys the Core keeps sealed, one row each, and the host keys it pinned. ⌘G generates, ⌘I imports (a key file dropped on
/// the panel opens Import filled in), ↑ ↓ select, Esc closes.
struct KeysPanel: View {
    static let width: CGFloat = 380
    let model: LeylineModel
    @State private var knownOpen = true
    @Environment(\.corePalette) private var palette

    private var canWrite: Bool { !model.readOnly && model.load == .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s2) {
                    if model.keys.isEmpty { empty } else { keys }
                    known
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            Text("⌘G generate · ⌘I import · ↑↓ select · esc close")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .frame(width: Self.width - Space.s4 * 2)
        .frame(maxHeight: .infinity, alignment: .top)
        .corePanel(radius: Radius.pane, padding: Space.s4)
        .contentShape(coreShape(Radius.pane))
        .background { shortcuts }
        .onDrop(of: [.fileURL], isTargeted: nil) { items in
            guard canWrite else { return false }
            _ = items.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    guard let text = DropZone.text(url) else { return }
                    KeyDialogs.openImport(model, name: url.deletingPathExtension().lastPathComponent, pem: text)
                }
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keys")
        .accessibilityIdentifier("leyline-keys")
    }

    /// ⌘G and ⌘I wherever focus is while the panel shows.
    private var shortcuts: some View {
        Group {
            Button("Generate Key") { KeyDialogs.openGenerate(model) }.keyboardShortcut("g", modifiers: .command)
            Button("Import Key") { KeyDialogs.openImport(model) }.keyboardShortcut("i", modifiers: .command)
        }
        .disabled(!canWrite).opacity(0).accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "key").coreFont(size: MacTextSize.body, weight: .medium).accessibilityHidden(true)
            Text("Keys").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s2)
            if !model.keys.isEmpty {
                CoreIconButton(symbol: "plus", label: "Generate Key (⌘G) · needs Touch ID") {
                    KeyDialogs.openGenerate(model)
                }
                .disabled(!canWrite).accessibilityIdentifier("leyline-generate-key")
                CoreIconButton(symbol: "square.and.arrow.down", label: "Import Key (⌘I) · needs Touch ID") {
                    KeyDialogs.openImport(model)
                }
                .disabled(!canWrite).accessibilityIdentifier("leyline-import-key")
            }
            Button("esc") { model.keysOpen = false }
                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                .help("Close Keys")
                .accessibilityLabel("Close Keys")
        }
    }

    private var keys: some View {
        VStack(spacing: Space.s1 + 2) {
            ForEach(model.keys) { k in
                KeyRow(model: model, key: k, selected: model.keySelected == k.id)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "key").coreFont(size: MacTextSize.large, weight: .medium)
                .frame(width: Space.s8 + Space.s5, height: Space.s8 + Space.s5)
                .background(palette.btnPrimary.opacity(0.22), in: coreShape(Radius.cardMac))
                .accessibilityHidden(true)
            Text("No keys yet").coreFont(size: MacTextSize.title, weight: .semibold)
            Text("Kept sealed in your Core. Hosts sign in with them; nobody sees them again.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                Button {
                    KeyDialogs.openGenerate(model)
                } label: {
                    Text("Generate").frame(maxWidth: .infinity)
                }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small)).environment(\.coreKeycap, "⌘G")
                .accessibilityIdentifier("leyline-generate-key")
                Button {
                    KeyDialogs.openImport(model)
                } label: {
                    Text("Import").frame(maxWidth: .infinity)
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).environment(\.coreKeycap, "⌘I")
                .accessibilityIdentifier("leyline-import-key")
            }
            .disabled(!canWrite)
            Text("or drop a key file here").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
    }

    @ViewBuilder private var known: some View {
        if !model.knownHosts.isEmpty {
            Button {
                knownOpen.toggle()
            } label: {
                HStack(spacing: Space.s1 + 2) {
                    Image(systemName: "chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .rotationEffect(.degrees(knownOpen ? 0 : -90))
                    Text("Known hosts · \(model.knownHosts.count) pinned").coreFont(size: MacTextSize.meta + 1)
                }
                .foregroundStyle(GlassInk.secondary).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s3)
            .accessibilityValue(knownOpen ? "shown" : "hidden")
            .accessibilityIdentifier("leyline-known-hosts")
            if knownOpen {
                VStack(spacing: Space.s1) {
                    ForEach(model.knownHosts) { KnownHostRow(known: $0) }
                }
            }
        }
    }
}

/// One key: its pattern, name and "type · N hosts"; Copy Public Key and More show on hover or when selected.
struct KeyRow: View {
    let model: LeylineModel
    let key: KeyItem
    let selected: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: Space.s3) {
            KeyIdenticon(fingerprint: key.fingerprint)
            VStack(alignment: .leading, spacing: 1) {
                Text(key.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text("\(key.typeWord) · \(Words.count(model.usedBy(key).count, "host"))")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            HStack(spacing: Space.s1) {
                CoreIconButton(symbol: "doc.on.doc", label: "Copy Public Key", action: copy)
                CoreDropdown(
                    items: [
                        CoreDropdownItem("Copy Public Key", symbol: "doc.on.doc", run: copy),
                        // TODO(Y1-04): installing a public key on a host over SSH arrives with the SSH driver (Y2-02).
                        CoreDropdownItem("Install on Host…", symbol: "server.rack", enabled: false, note: "soon") {},
                    ]
                ) {
                    Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .medium)
                        .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                }
                .help("More")
                .accessibilityLabel("More for \(key.name)")
            }
            .opacity(hover || selected ? 1 : 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
        .modifier(SelectedFill(selected: selected, hover: hover, radius: Radius.cardMac))
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture { model.keySelected = key.id }
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(key.name), \(key.line)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("key-row-\(key.name)")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key.publicKey, forType: .string)
        model.host.shell.showToast("Public key copied")
    }
}

/// A pinned host key on one line: its pattern, the host and whether it is still the key that was pinned.
struct KnownHostRow: View {
    let known: KnownHostItem

    var body: some View {
        HStack(spacing: Space.s3) {
            KeyIdenticon(fingerprint: known.fingerprint, rows: 2)
            Text(known.host).lineLimit(1)
            Spacer(minLength: Space.s2)
            switch known.state {
            case .trusted: StateBadge("Trusted", tone: .done, symbol: "checkmark.circle")
            case .changed: StateBadge("Changed · review", tone: .warn, symbol: "exclamationmark.triangle")
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s1 + 2)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .help(known.fingerprint)
        .accessibilityElement(children: .combine)
        .accessibilityValue(FingerprintPattern.short(known.fingerprint))
    }
}

/// A key's fingerprint as a small 5-wide pattern in the accent and ink tones, the same key always the same pattern. An aid
/// to the eye beside the name; `FingerprintPattern` is the full one.
struct KeyIdenticon: View {
    let fingerprint: String
    var rows = 4
    static let columns = 5
    @Environment(\.corePalette) private var palette

    var body: some View {
        // Every byte of the digest folds to a tone, so a changed key looks different; text that is not a SHA256 still
        // draws a steady pattern from its own bytes.
        let digest = FingerprintPattern.digest(fingerprint)
        let bytes = digest.isEmpty ? Array(fingerprint.utf8) : digest
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<Self.columns, id: \.self) { c in
                        let b = bytes.isEmpty ? 0 : bytes[(r * Self.columns + c) % bytes.count]
                        coreShape(1.5).fill(ink(Int((b ^ (b >> 2) ^ (b >> 4) ^ (b >> 6)) & 3)))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .padding(5)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .accessibilityHidden(true)
    }

    private func ink(_ tone: Int) -> Color {
        switch tone {
        case 0: palette.btnPrimary
        case 1: GlassInk.secondary.opacity(0.8)
        default: GlassInk.secondary.opacity(0.3)
        }
    }
}
