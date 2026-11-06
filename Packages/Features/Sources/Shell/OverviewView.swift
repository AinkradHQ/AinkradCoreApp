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
    /// The pointer only tints a card; the highlight (and Return) follows the keyboard.
    @State private var hovered: Int?
    /// The grid and the ↑ ↓ keys share this, so a row down is always the card below.
    private static let columns = 4
    @Namespace private var lens

    var body: some View {
        let panes = shell.panes
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                IconTile("square.grid.2x2", hue: GlassInk.blue, size: 40, bounce: shown)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Overview").font(.system(size: MacTextSize.large, weight: .semibold))
                    Text(panes.count == 1 ? "1 app open" : "\(panes.count) apps open")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
            }
            .help("← → ↑ ↓ choose · ↩ or 1–9 open · esc close")
            if panes.isEmpty {
                Text("No app is open").foregroundStyle(GlassInk.secondary)
                    .frame(maxWidth: .infinity, minHeight: Space.s8 * 4)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: Self.columns),
                    spacing: Space.s3
                ) {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { i, p in
                        card(p, index: i, on: i == selected, hover: hovered == i)
                            .onTapGesture { open(i) }
                            .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
                            .coreRise(shown, i)
                    }
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: Space.s8 * 34 - Space.s6 * 2)
        .corePanel(radius: Radius.panel, padding: Space.s6, part: .popups)
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .scaleEffect(shown ? 1 : 0.94).opacity(shown ? 1 : 0)
        .animation(Motion.out(Motion.move), value: shown)
        .animation(Motion.out(Motion.ui), value: selected)
        .onAppear {
            selected = panes.firstIndex { $0.id == shell.activePane } ?? 0
            shown = true
            listen(count: panes.count)
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview")
    }

    private func card(_ p: PaneSpec, index: Int, on: Bool, hover: Bool) -> some View {
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
                    Text("\(index + 1)").font(.system(size: MacTextSize.meta, weight: .semibold, design: .rounded))
                        .frame(width: MacSize.controlSm, height: MacSize.controlSm)
                        .background(.white.opacity(0.14), in: coreShape(Radius.chip))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(shell.tabName(p)).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                HStack(spacing: Space.s1) {
                    if let state { coreShape(2).fill(state).frame(width: 6, height: 6) }
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
                    .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.6), lineWidth: 1) }
                    .matchedGeometryEffect(id: "pick", in: lens)
            } else {
                coreShape(Radius.cardMac).fill(hover ? GlassInk.wellHover : GlassInk.well)
                    .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            }
        }
        .animation(Motion.out(Motion.hover), value: hover)
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
        let cols = Self.columns
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            switch e.keyCode {
            case 123: selected = max(selected - 1, 0)
            case 124: selected = min(selected + 1, count - 1)
            case 125: selected = min(selected + cols, count - 1)
            case 126: selected = max(selected - cols, 0)
            case 36, 76: open(selected)
            case 53: shell.overviewOpen = false
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
