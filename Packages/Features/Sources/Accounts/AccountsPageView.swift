import CoreUI
import SwiftUI

/// The way back to a list, as a tile beside the page's icon (the Devices look): it nudges left on hover. Esc does the same.
struct BackTile: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward").font(.system(size: 15, weight: .bold)).foregroundStyle(
                GlassInk.primary
            )
            .offset(x: hovering ? -2 : 0)
            .frame(width: 36, height: 56)
            .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(10))
            .overlay { coreShape(10).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            .contentShape(coreShape(10))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .help("All accounts (esc)")
        .accessibilityLabel("All accounts")
    }
}
