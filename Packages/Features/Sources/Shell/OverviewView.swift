import AppKit
import CoreUI
import SwiftUI

/// Overview (⌃↑, ⇧⌘O, or a click on the top-bar indicator; 06-workspaces `overview`): every workspace as a tile with its
/// apps laid out as they are tiled, the current one lit, and a new one at the end. ← → choose, ⏎ or 1–9 open, N new, esc
/// closes. Opening a workspace switches to it.
struct OverviewView: View {
    @Environment(\.coreAccent) private var paneAccent
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Bindable var shell: ShellModel
    @State private var selected = 0
    @State private var shown = false
    @State private var monitor: Any?

    private static let tileWidth: CGFloat = 200
    private static let miniHeight: CGFloat = 112

    var body: some View {
        // ponytail: one row; past ~7 workspaces it runs wider than the screen. Wrap or scroll if that ever happens.
        HStack(spacing: Space.s3) {
            ForEach(shell.spaces.indices, id: \.self) { i in
                tile(i)
            }
            newTile
        }
        .padding(Space.s3)
        .coreFrame(radius: Radius.pane, part: .popups)
        .shadow(color: GlassInk.shade(0.35), radius: 40, y: 16)
        .offset(y: shown || reduce ? 0 : -14)
        .opacity(shown ? 1 : 0)
        .animation(Motion.out(Motion.ui), value: shown)
        .coreAnimation(Motion.out(Motion.hover), value: selected)
        .padding(.top, ShellMetrics.topBar + Space.s1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            selected = shell.spaceIndex
            shown = true
            listen()
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All workspaces")
    }

    private func tile(_ i: Int) -> some View {
        let current = i == shell.spaceIndex
        let id = shell.spaces[i].id
        let apps = shell.allPanes.filter { shell.paneSpace[$0.id] == id }
        return Button {
            open(i)
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                mini(i, apps: apps, current: current)
                HStack(spacing: Space.s1) {
                    Text("Workspace \(i + 1)").coreFont(size: MacTextSize.meta + 1, weight: .semibold).lineLimit(1)
                    if current {
                        Text("Now").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    }
                    Spacer(minLength: 0)
                    if i < 9 { CoreKeycap("⌃\(i + 1)") }
                }
                .padding(.horizontal, 2)
            }
            .padding(6)
            .frame(width: Self.tileWidth)
            .background(selected == i ? palette.navActive : .clear, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.coreQuietPress)
        .onHover { if $0 { selected = i } }
        .accessibilityLabel(
            "Workspace \(i + 1)\(current ? ", current" : ""), "
                + (apps.isEmpty ? "empty" : apps.map { shell.tabName($0) }.joined(separator: ", "))
        )
        .accessibilityAddTraits(selected == i ? .isSelected : [])
    }

    /// The workspace as it is tiled: each app a small rounded rect with its icon and name.
    private func mini(_ i: Int, apps: [PaneSpec], current: Bool) -> some View {
        let size = CGSize(width: Self.tileWidth - 12 - Space.s2 * 2, height: Self.miniHeight - Space.s2 * 2)
        let frames = shell.spaceTree(i).layout(minWidth: { _ in 0 }, container: size, gap: 4, minHeight: 0).frames
        return ZStack(alignment: .topLeading) {
            if apps.isEmpty {
                Text("Empty").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .frame(width: size.width, height: size.height)
            }
            ForEach(apps) { p in
                let f = frames[p.id] ?? CGRect(origin: .zero, size: size)
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: p.symbol).coreFont(size: MacTextSize.meta, weight: .medium)
                    Text(shell.tabName(p)).coreFont(size: MacTextSize.meta - 1, weight: .medium).lineLimit(1)
                }
                .foregroundStyle(current ? palette.text : palette.text2)
                .padding(Space.s1)
                .frame(width: f.width, height: f.height, alignment: .topLeading)
                .background(
                    current ? GlassInk.accent(paneAccent).opacity(0.28) : GlassInk.lift(0.12),
                    in: coreShape(Radius.chip)
                )
                .offset(x: f.minX, y: f.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .padding(Space.s2)
        .coreWell(radius: Radius.control)
        .accessibilityHidden(true)
    }

    private var newTile: some View {
        let i = shell.spaces.count
        return Button {
            shell.newSpace()
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                Image(systemName: "plus").font(.system(size: 20, weight: .regular)).foregroundStyle(palette.text2)
                    .frame(maxWidth: .infinity).frame(height: Self.miniHeight)
                    .background(GlassInk.lift(0.05), in: coreShape(Radius.control))
                HStack(spacing: Space.s1) {
                    Text("New workspace").coreFont(size: MacTextSize.meta + 1, weight: .semibold).lineLimit(1)
                    Spacer(minLength: 0)
                    CoreKeycap("N")
                }
                .padding(.horizontal, 2)
            }
            .padding(6)
            .frame(width: Self.tileWidth)
            .background(selected == i ? palette.navActive : .clear, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.coreQuietPress)
        .onHover { if $0 { selected = i } }
        .accessibilityLabel("New workspace")
        .accessibilityAddTraits(selected == i ? .isSelected : [])
    }

    private func open(_ i: Int) {
        guard shell.spaces.indices.contains(i) else { return shell.newSpace() }
        shell.overviewOpen = false
        shell.switchSpace(to: i)
    }

    private func listen() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return e }
            let last = shell.spaces.count
            switch e.keyCode {
            case 123: selected = max(selected - 1, 0)
            case 124: selected = min(selected + 1, last)
            case 36, 76: open(selected)
            default:
                let c = e.charactersIgnoringModifiers?.lowercased()
                if c == "n" {
                    shell.newSpace()
                } else if let c, let n = Int(c), n >= 1, n <= min(9, last) {
                    open(n - 1)
                } else {
                    return e
                }
            }
            return nil
        }
    }
}
