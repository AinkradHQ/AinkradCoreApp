import AppKit
import CoreUI
import Projects
import SwiftUI

/// One key: its pattern, name, "type · used on N hosts · added 3 Nov" and up to three host chips. Selected (a click, or
/// ↑ ↓) it opens in place: the whole fingerprint, every host that signs in with it (a click selects it on the map), Copy
/// Public Key and Install on Host…. One row is open at a time.
struct KeyRow: View {
    let model: LeylineModel
    let key: KeyItem
    @State private var hover = false

    private var open: Bool { model.keySelected == key.id }
    private var fresh: Bool { model.keyFresh == key.id }
    private var used: [HostItem] { model.usedBy(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s3) {
                KeyIdenticon(fingerprint: key.fingerprint, big: true).coreBounce(fresh)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(key.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                            .truncationMode(.middle).help(key.name)
                        Spacer(minLength: 0)
                        if let d = key.createdAt {
                            Text("added \(d.formatted(.dateTime.day().month(.abbreviated)))")
                                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).fixedSize()
                        }
                    }
                    Text(summary).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(GlassInk.secondary).rotationEffect(.degrees(open ? 0 : -90))
                    .opacity(hover || open ? 1 : 0).accessibilityHidden(true)
            }
            if open { details.transition(.opacity) } else if !used.isEmpty { chips }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SelectedFill(selected: open || fresh, hover: hover, radius: Radius.cardMac))
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture { model.keySelected = open ? nil : key.id }
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        // Just made: the pattern bounces once, and the row is lit with the selected fill.
        .animation(Motion.out(Motion.ui), value: fresh)
        .contextMenu {
            Button("Copy Public Key") { model.copyPublicKey(key) }
            Button("Copy Fingerprint") { copy(key.fingerprint) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(key.name), \(summary)")
        .accessibilityAddTraits(open ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("key-row-\(key.name)")
    }

    private var summary: String {
        "\(key.typeWord) · " + (used.isEmpty ? "on no host yet" : "used on \(Words.count(used.count, "host"))")
    }

    private var chips: some View {
        let c = KeyText.chips(used)
        return HStack(spacing: Space.s1) {
            ForEach(c.shown) { CoreChip($0.name, symbol: "server.rack", minWidth: 0) }
            if c.more > 0 {
                CoreChip("+\(c.more)", minWidth: 0).help(used.dropFirst(3).map(\.name).joined(separator: ", "))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Used on \(used.map(\.name).joined(separator: ", "))")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Fingerprint").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Text(key.fingerprint).coreFont(size: MacTextSize.meta, design: .monospaced)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("key-fingerprint")
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Used on").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                if used.isEmpty {
                    Text("No host signs in with it yet.").coreFont(size: MacTextSize.meta)
                } else {
                    KeyChipFlow {
                        ForEach(used) { h in
                            Button {
                                model.select(h.id)
                            } label: {
                                CoreChip(h.name, symbol: "server.rack", minWidth: 0)
                            }
                            .buttonStyle(CoreQuietPressStyle(radius: Radius.chip))
                            .help("Show \(h.name) on the map")
                        }
                    }
                }
            }
            HStack(spacing: Space.s2) {
                Button {
                    model.copyPublicKey(key)
                } label: {
                    Label("Copy Public Key", systemImage: "doc.on.doc")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).fixedSize()
                .accessibilityIdentifier("key-copy-public")
                // TODO(Y1-04): installing a public key on a host over SSH arrives with the SSH driver (Y2-02).
                Soon(prominent: false, help: "Installing a key on a host arrives with the SSH update") {
                    Text("Install on Host…")
                }
                .controlSize(.small)
            }
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        model.host.shell.showToast("Fingerprint copied")
    }
}

/// A pinned host key on one line: its pattern, the host and its state; a changed key has Review, which opens the host's
/// Access where its key is.
struct KnownHostRow: View {
    let model: LeylineModel
    let known: KnownHostItem

    var body: some View {
        HStack(spacing: Space.s3) {
            KeyIdenticon(fingerprint: known.fingerprint, rows: 2)
            Text(known.host).lineLimit(1)
            Spacer(minLength: Space.s2)
            switch known.state {
            case .trusted: StateBadge("Trusted", tone: .done, symbol: "checkmark.circle")
            case .changed:
                StateBadge("Changed", tone: .warn, symbol: "exclamationmark.triangle")
                Button("Review") { model.reviewHostKey(known) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Open \(known.host)’s Access to see its new key")
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
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
    /// The list's size; the small one is for one-line rows.
    var big = false
    static let columns = 5
    @Environment(\.corePalette) private var palette

    var body: some View {
        // Every byte of the digest folds to a tone, so a changed key looks different; text that is not a SHA256 still
        // draws a steady pattern from its own bytes.
        let digest = FingerprintPattern.digest(fingerprint)
        let bytes = digest.isEmpty ? Array(fingerprint.utf8) : digest
        let cell = big ? Space.s1 + 2 : Space.s1
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<Self.columns, id: \.self) { c in
                        let b = bytes.isEmpty ? 0 : bytes[(r * Self.columns + c) % bytes.count]
                        coreShape(Radius.chip / 4).fill(ink(Int((b ^ (b >> 2) ^ (b >> 4) ^ (b >> 6)) & 3)))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .padding(big ? Space.s2 : Space.s1 + 2)
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

/// Chips that wrap onto the next line.
struct KeyChipFlow: Layout {
    var spacing = Space.s1

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 300, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (s, f) in zip(subviews, arrange(bounds.width, subviews).frames) {
            s.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var frames: [CGRect] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
        }
        return (CGSize(width: width, height: y + row), frames)
    }
}
