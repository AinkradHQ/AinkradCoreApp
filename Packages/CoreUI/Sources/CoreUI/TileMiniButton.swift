import SwiftUI

/// A small icon button on a tile (open, stop, kill...): the glyph over its key, a soft well that lightens on hover, a press
/// that settles to 0.97. Never resizes on hover. `destructive` tints the glyph red; the label is its help and its VoiceOver name.
public struct TileMiniButton: View {
    let symbol: String
    let key: String
    let label: String
    let destructive: Bool
    let run: () -> Void

    public init(_ symbol: String, key: String, label: String, destructive: Bool = false, run: @escaping () -> Void) {
        self.symbol = symbol
        self.key = key
        self.label = label
        self.destructive = destructive
        self.run = run
    }

    public var body: some View {
        Button(action: run) {
            VStack(spacing: 0) {
                Image(systemName: symbol).font(.system(size: MacTextSize.body, weight: .semibold))
                    .foregroundStyle(destructive ? GlassInk.red : GlassInk.primary)
                Text(key).font(.system(size: MacTextSize.meta, weight: .medium)).foregroundStyle(GlassInk.secondary)
            }
            .frame(width: MacSize.controlLg + Space.s2, height: MacSize.controlLg + Space.s2)
        }
        .buttonStyle(MiniStyle())
        .help("\(label) (\(key))")
        .accessibilityLabel(label)
    }
}

private struct MiniStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MiniBody(configuration: configuration)
    }
}

private struct MiniBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    var body: some View {
        configuration.label
            .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control))
            .overlay { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            .contentShape(coreShape(Radius.control))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.out(Motion.press), value: configuration.isPressed)
            .animation(Motion.out(Motion.hover), value: hovering)
            .onHover { hovering = $0 }
    }
}
