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
            if !wide { WidgetHead(title: "Quick actions", symbol: "bolt") }
            let cols = wide ? [GridItem(.flexible(), spacing: 6), GridItem(.flexible())] : [GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                    Button {
                        run(t.0, t.1)
                    } label: {
                        label(t.2, t.1, wide: wide)
                    }
                    .buttonStyle(CoreButtonStyle(.secondary)).rise(arrived, i, reduce)
                    .environment(\.coreForcedInteraction, forcedHover(i))
                }
                Button {
                    shell.toggleLauncher()
                } label: {
                    label("magnifyingglass", "Launcher", wide: wide, key: "⌘K")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).rise(arrived, tiles.count, reduce)
            }
            if !wide { Spacer(minLength: 0) }
        }
        .frame(maxHeight: .infinity, alignment: wide ? .center : .top)
        .onAppear { arrived = true }
    }

    @ViewBuilder private func label(_ symbol: String, _ title: String, wide: Bool, key: String? = nil) -> some View {
        let icon = Image(systemName: symbol).font(.system(size: wide ? 14 : 13)).accessibilityHidden(true)
        let text = Text(title).font(.system(size: wide ? MacTextSize.meta : MacTextSize.body, weight: .medium))
            .lineLimit(1)
        if wide {
            VStack(spacing: 2) {
                icon
                HStack(spacing: Space.s1) {
                    text
                    if let key { Text(key).font(.system(size: MacTextSize.meta)).opacity(0.8) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        } else {
            HStack(spacing: Space.s2) {
                icon
                text
                if let key { CoreKeycap(key) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
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
