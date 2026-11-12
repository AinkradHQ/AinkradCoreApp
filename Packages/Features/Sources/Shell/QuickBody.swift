import CoreUI
import SwiftUI

/// Quick actions in the four macOS sizes. Tiles use the glass well style and rise in one after another when the widget arrives.
struct QuickBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce
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
            shell.showToast("\(title) arrives with its feature module.")
        }
    }

    private var tiles: [(id: String, title: String, symbol: String, key: String?)] {
        [
            ("agents.new", "New AI session", "play", nil), ("new-terminal", "New terminal", "terminal", nil),
            ("add-device", "Add device", "plus", nil), ("launcher", "Launcher", "magnifyingglass", "⌘K"),
        ]
    }

    private func go(_ t: (id: String, title: String, symbol: String, key: String?)) {
        if t.id == "launcher" { shell.toggleLauncher() } else { run(t.id, t.title) }
    }

    /// Small: four icons in a square. Medium: one row with labels. Large: a list with keys. Extra large: big tiles.
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if size != .s { WHead("bolt", "Quick actions") }
            switch size {
            case .s:
                grid(columns: 2, labels: false)
            case .m:
                grid(columns: 4, labels: true)
            case .l, .t:
                VStack(spacing: Space.s2) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                        Button {
                            go(t)
                        } label: {
                            HStack(spacing: Space.s3) {
                                Image(systemName: t.symbol).foregroundStyle(GlassInk.blue).frame(width: 20)
                                Text(t.title).coreFont(size: MacTextSize.body, weight: .medium)
                                Spacer(minLength: 0)
                                if let k = t.key {
                                    Text(k).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                                }
                            }
                            .padding(.horizontal, Space.s3).frame(
                                maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        }
                        .buttonStyle(QuickTileStyle(prominent: false)).rise(arrived, i, reduce)
                    }
                    Spacer(minLength: 0)
                }
            case .x:
                grid(columns: 4, labels: true)
            }
        }
        .onAppear { arrived = true }
    }

    private func grid(columns: Int, labels: Bool) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: columns)
        return LazyVGrid(columns: cols, spacing: Space.s2) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                Button {
                    go(t)
                } label: {
                    VStack(spacing: Space.s1) {
                        Image(systemName: t.symbol).font(.system(size: 20, weight: .medium)).accessibilityHidden(true)
                        if labels {
                            Text(t.title).coreFont(size: MacTextSize.meta, weight: .medium).lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: size == .s ? 52 : size == .x ? 120 : 76)
                }
                .buttonStyle(QuickTileStyle(prominent: t.id == "launcher")).rise(arrived, i, reduce)
                .environment(\.coreForcedInteraction, forcedHover(i))
                .accessibilityLabel(t.title)
                .help(t.title)
            }
        }
    }
}

extension View {
    /// `fx.stagger({ from: 'rise', gap: 40 })`: rises 10 pt and fades in, one after another. Reduce Motion: a 200 ms fade, no travel.
    func rise(_ shown: Bool, _ index: Int, _ reduce: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : coreMove(reduce, 10))
            .animation(
                (reduce ? Animation.easeOut(duration: 0.2) : Motion.out(Motion.move)).delay(
                    reduce ? 0 : Double(index) * 0.04),
                value: shown)
    }
}

/// A quick-action tile on clear glass: a plain well (no second glass inside the widget), the launcher one blue. Hover lifts
/// the fill a step, a press shrinks it a little; Reduce Motion keeps the fill change and drops the shrink.
struct QuickTileStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        QuickTile(configuration: configuration, prominent: prominent)
    }
}

private struct QuickTile: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false

    private var lit: Bool { hovering || forced == .hover || configuration.isPressed }

    var body: some View {
        configuration.label
            .foregroundStyle(GlassInk.primary)
            .background(fill, in: coreShape(Radius.control))
            .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.out(Motion.hover), value: lit)
            .animation(Motion.press(Motion.press), value: configuration.isPressed)
    }

    private var fill: Color {
        prominent ? GlassInk.blue.opacity(lit ? 1 : 0.85) : lit ? GlassInk.wellEdge : GlassInk.wellHover
    }
}
