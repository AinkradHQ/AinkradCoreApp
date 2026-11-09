import AppKit
import CoreUI
import SwiftUI

/// Overview (⇧⌘O): every open app as a card, like Mission Control. Pick one with the arrows and Return, its number, or a
/// click; it comes to the front (out of the stack if it was there). Esc closes.
struct OverviewView: View {
    @Bindable var shell: ShellModel
    @State private var selected = 0
    @State private var shown = false
    @State private var monitor: Any?
    @Namespace private var lens

    var body: some View {
        let panes = shell.panes
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                IconTile("square.grid.2x2", hue: GlassInk.blue, size: 40, bounce: shown)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Overview").font(.system(size: MacTextSize.large + 2, weight: .bold))
                    Text("\(panes.count) apps open · ← → ↑ ↓ choose · ↩ or 1–9 open · esc close")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: Space.s3)], spacing: Space.s3) {
                ForEach(Array(panes.enumerated()), id: \.element.id) { i, p in
                    card(p, index: i, on: i == selected)
                        .onTapGesture { open(i) }
                        .onHover { if $0 { selected = i } }
                        .coreRise(shown, i)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s6)
        .frame(maxWidth: Space.s8 * 34)
        .corePanel(radius: Radius.panel + Space.s1, padding: 0, part: .popups)
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .scaleEffect(shown ? 1 : 0.94).opacity(shown ? 1 : 0)
        .animation(Motion.out(Motion.ui), value: shown)
        .animation(.spring(duration: 0.25), value: selected)
        .onAppear {
            selected = panes.firstIndex { $0.id == shell.activePane } ?? 0
            shown = true
            listen(count: panes.count)
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview")
    }

    private func card(_ p: PaneSpec, index: Int, on: Bool) -> some View {
        let state: Color? = p.chip.map {
            $0.tone == .fail
                ? GlassInk.red
                : $0.tone == .warn ? GlassInk.orange : $0.tone == .queue ? GlassInk.slate : GlassInk.green
        }
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                IconTile(p.symbol, hue: on ? GlassInk.blue : GlassInk.slate, size: 44, bounce: on)
                Spacer()
                if index < 9 {
                    Text("\(index + 1)").font(.system(size: MacTextSize.meta, weight: .bold, design: .rounded))
                        .frame(width: 22, height: 22).background(.white.opacity(0.14), in: coreShape(6))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(shell.tabName(p)).font(.system(size: MacTextSize.headline + 1, weight: .semibold)).lineLimit(1)
                HStack(spacing: Space.s1) {
                    if let state { coreShape(1.5).fill(state).frame(width: 6, height: 6) }
                    Text([p.title, p.chip?.label].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background {
            if on {
                coreShape(Radius.cardMac).fill(GlassInk.blue.opacity(0.22))
                    .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.6), lineWidth: 1.5) }
                    .shadow(color: GlassInk.blue.opacity(0.45), radius: 16)
                    .matchedGeometryEffect(id: "pick", in: lens)
            } else {
                coreShape(Radius.cardMac).fill(GlassInk.well)
                    .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            }
        }
        .scaleEffect(on ? 1.03 : 1)
        .contentShape(coreShape(Radius.cardMac))
        .accessibilityLabel(shell.tabName(p))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func open(_ i: Int) {
        guard shell.panes.indices.contains(i) else { return }
        let id = shell.panes[i].id
        shell.overviewOpen = false
        shell.surface = .workspace
        shell.activePane = id
        if shell.focusedPane != nil { shell.focusedPane = id }
    }

    private func listen(count: Int) {
        guard monitor == nil else { return }
        let cols = 4
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            switch e.keyCode {
            case 123: selected = max(selected - 1, 0)
            case 124: selected = min(selected + 1, count - 1)
            case 125: selected = min(selected + cols, count - 1)
            case 126: selected = max(selected - cols, 0)
            case 36, 76: open(selected)
            default:
                if let c = e.charactersIgnoringModifiers, let n = Int(c), n >= 1, n <= 9 {
                    open(n - 1)
                } else {
                    return e
                }
            }
            return nil
        }
    }
}
