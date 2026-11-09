import CoreUI
import SwiftUI

/// Quick actions. Buttons use the one CoreUI button (ghost: glass edge, `u-dim` on hover, 0.97 press), tiles stack the icon over
/// the label in the wide size and list in the large one; they rise in one after another when the widget arrives.
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
                    .buttonStyle(QuickTileStyle(prominent: false)).rise(arrived, i, reduce)
                    .environment(\.coreForcedInteraction, forcedHover(i))
                }
                Button {
                    shell.toggleLauncher()
                } label: {
                    label("magnifyingglass", "Launcher", wide: wide, key: "⌘K")
                }
                .buttonStyle(QuickTileStyle(prominent: true)).rise(arrived, tiles.count, reduce)
            }
            if !wide { Spacer(minLength: 0) }
        }
        .frame(maxHeight: .infinity, alignment: wide ? .center : .top)
        .onAppear { arrived = true }
    }

    /// A big icon over a short label, Apple style; the launcher tile adds its key.
    private func label(_ symbol: String, _ title: String, wide: Bool, key: String? = nil) -> some View {
        VStack(spacing: Space.s1) {
            Image(systemName: symbol).font(.system(size: 22, weight: .medium)).accessibilityHidden(true)
            Text(key.map { "\(title) \($0)" } ?? title).coreFont(size: MacTextSize.meta, weight: .medium)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: wide ? 52 : 64)
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
