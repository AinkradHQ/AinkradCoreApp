import CoreUI
import SwiftUI

/// Quick actions in the four macOS sizes. Tiles use the glass well style and rise in one after another when the widget arrives.
struct QuickBody: View {
    @Environment(\.coreAccent) private var paneAccent
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

    private typealias Tile = (id: String, title: String, symbol: String, sub: String)
    /// The five actions of the 05-home mockup. Small and Medium show the first four.
    private var tiles: [Tile] {
        [
            ("agents.new", "New AI session", "sparkles", "Pick a task, it starts at once"),
            ("new-terminal", "New terminal", "terminal", "On this Mac or in the sandbox"),
            ("brain", "Search Brain", "magnifyingglass", "Ask what you already know"),
            ("projects", "Open a project", "folder", "Jump back into your work"),
            ("lore-capture", "Today note", "note.text", "Write something down"),
        ]
    }

    private func go(_ t: Tile) { run(t.id, t.title) }

    /// Small: four icons in a square. Medium: one row with labels. Large: a list with keys. Extra large: big tiles.
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if size != .s { WHead("bolt", "Quick actions") }
            switch size {
            case .s:
                grid(tiles.prefix(4), columns: 2, labels: false)
            case .m:
                grid(tiles.prefix(4), columns: 4, labels: true)
            case .l:
                VStack(spacing: Space.s2) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                        Button {
                            go(t)
                        } label: {
                            HStack(spacing: Space.s3) {
                                Image(systemName: t.symbol).foregroundStyle(GlassInk.accent(paneAccent)).frame(
                                    width: 20)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(t.title).coreFont(size: MacTextSize.body, weight: .medium)
                                    Text(t.sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Space.s3).frame(
                                maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        }
                        .buttonStyle(QuickTileStyle(prominent: false)).rise(arrived, i, reduce)
                    }
                    Spacer(minLength: 0)
                }
            case .w:
                grid(tiles[...], columns: 5, labels: true)
            }
        }
        .onAppear { arrived = true }
    }

    private func grid(_ shown: ArraySlice<Tile>, columns: Int, labels: Bool) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: columns)
        return LazyVGrid(columns: cols, spacing: Space.s2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, t in
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
                    .frame(maxWidth: .infinity, minHeight: size == .s ? 52 : size == .w ? 80 : 76)
                }
                .buttonStyle(QuickTileStyle(prominent: false)).rise(arrived, i, reduce)
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
    @Environment(\.coreAccent) private var paneAccent
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
        prominent ? GlassInk.accent(paneAccent).opacity(lit ? 1 : 0.85) : lit ? GlassInk.wellEdge : GlassInk.wellHover
    }
}
