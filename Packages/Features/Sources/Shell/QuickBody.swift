import CoreUI
import SwiftUI

/// Quick actions. Tiles stack the icon over
/// the label in the wide size and list in the large one; they rise in one after another when the widget arrives.
struct QuickBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @State private var arrived = false

    private func forcedHover(_ i: Int) -> CoreInteraction? {
        #if DEBUG
        return shell.debugForceQuickHover && i == 1 ? .hover : nil
        #else
        return nil
        #endif
    }

    private func run(_ id: String, _ title: String) {
        if let e = shell.launcher.entry(id) {
            e.run()
        } else {
            shell.showToast("Not available yet")
        }
    }

    var body: some View {
        let tiles: [(String, String, String)] = [
            ("agents.new", "New agent session", "play"), ("new-terminal", "New terminal", "terminal"),
            ("add-device", "Add device", "plus"),
        ]
        let wide = size == .m
        VStack(alignment: .leading, spacing: Space.s2) {
            let cols = [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: Space.s2) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                    Button {
                        run(t.0, t.1)
                    } label: {
                        label(t.2, t.1, wide: wide)
                    }
                    .buttonStyle(QuickTileStyle(prominent: false)).coreRise(arrived, i)
                    .environment(\.coreForcedInteraction, forcedHover(i))
                }
                Button {
                    shell.toggleLauncher()
                } label: {
                    label("magnifyingglass", "Launcher", wide: wide, key: "⌘K")
                }
                .buttonStyle(QuickTileStyle(prominent: true)).coreRise(arrived, tiles.count)
            }
            if !wide { Spacer(minLength: 0) }
        }
        .frame(maxHeight: .infinity, alignment: wide ? .center : .top)
        .onAppear { arrived = true }
    }

    /// A big icon over a short label, Apple style; the launcher tile adds its key.
    private func label(_ symbol: String, _ title: String, wide: Bool, key: String? = nil) -> some View {
        VStack(spacing: Space.s1) {
            Image(systemName: symbol).font(.system(size: MacTextSize.large, weight: .medium)).accessibilityHidden(true)
            Text(key.map { "\(title) \($0)" } ?? title).font(.system(size: MacTextSize.meta, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: wide ? 52 : 64)
    }
}

/// A quick-action tile on clear glass: a white well (no second glass inside the widget), the launcher one blue.
/// Hover brightens the fill; a press dips the tile.
struct QuickTileStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hovering = false
    @Environment(\.coreForcedInteraction) private var forced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(GlassInk.primary)
            .background(
                prominent
                    ? GlassInk.blue.opacity(configuration.isPressed ? 0.75 : hovering ? 1 : 0.9)
                    : configuration.isPressed || hovering || forced == .hover ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.cardMac)
            )
            .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.out(Motion.hover), value: hovering)
            .animation(Motion.press(Motion.press), value: configuration.isPressed)
    }
}
