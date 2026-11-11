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
            ("agents.new", "New agent session", "play", nil), ("new-terminal", "New terminal", "terminal", nil),
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
            case .l:
                VStack(spacing: Space.s2) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                        Button {
                            go(t)
                        } label: {
                            HStack(spacing: Space.s3) {
                                Image(systemName: t.symbol).foregroundStyle(WidgetInk.blue).frame(width: 20)
                                Text(t.title).coreFont(size: MacTextSize.body, weight: .medium)
                                Spacer(minLength: 0)
                                if let k = t.key {
                                    Text(k).coreFont(size: MacTextSize.meta).foregroundStyle(WidgetInk.secondary)
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

/// A quick-action tile on clear glass: a white well (no second glass inside the widget), the launcher one blue.
struct QuickTileStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(WidgetInk.primary)
            .background(
                prominent
                    ? WidgetInk.blue.opacity(configuration.isPressed ? 0.75 : 0.9)
                    : configuration.isPressed ? WidgetInk.wellEdge : WidgetInk.well,
                in: coreShape(Radius.control + 4)
            )
            .scaleEffect(configuration.isPressed && !reduce ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
