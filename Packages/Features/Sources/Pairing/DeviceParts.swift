import CoreUI
import SwiftUI

/// A key fact as a small tile: icon, what it is, one line.
struct KeyFact: View {
    let symbol: String
    let title: String
    let detail: String
    let hue: Color
    var body: some View {
        HStack(spacing: Space.s3) {
            IconTile(symbol, hue: hue, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: MacTextSize.body, weight: .semibold))
                Text(detail).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .background(GlassInk.well, in: coreShape(Radius.row))
        .accessibilityElement(children: .combine)
    }
}

/// The key fingerprint in groups of four, so it can be read out and compared.
struct FingerprintView: View {
    let fingerprint: String
    var body: some View {
        let groups = stride(from: 0, to: fingerprint.count, by: 4).map { i -> String in
            let a = fingerprint.index(fingerprint.startIndex, offsetBy: i)
            return String(
                fingerprint[
                    a..<(fingerprint.index(a, offsetBy: 4, limitedBy: fingerprint.endIndex) ?? fingerprint.endIndex)])
        }
        VStack(alignment: .leading, spacing: Space.s1) {
            Label("Fingerprint", systemImage: "touchid").font(.system(size: MacTextSize.meta, weight: .semibold))
                .foregroundStyle(GlassInk.secondary)
            Text(groups.joined(separator: " ")).font(.system(size: MacTextSize.body, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Back to the list, beside the device's picture: a glass tile with an arrow that slides left on hover and a word that
/// shows what is behind it. ⌘← does the same.
struct BackTile: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 22, weight: .semibold))
                    .offset(x: hovering ? -4 : 0)
                    .symbolEffect(.bounce, value: hovering)
                Text(title).font(.system(size: MacTextSize.meta, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(GlassInk.primary)
            .frame(width: 84, height: 72)
            .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control + 4))
            .overlay { coreShape(Radius.control + 4).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            .contentShape(coreShape(Radius.control + 4))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
        .accessibilityLabel("Back to Devices")
    }
}
