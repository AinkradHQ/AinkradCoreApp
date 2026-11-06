import AppKit
import CoreUI
import SwiftUI

/// ⌘K: fuzzy search over every registered entry, grouped. Return runs, ⌘1–9 pick, Esc closes.
struct LauncherView: View {
    @Bindable var shell: ShellModel
    @State private var query = ""
    @State private var selection = 0
    /// The pointer only moves the selection while the keyboard has not moved it just now (a list scrolling under a still pointer is not a hover).
    @State private var keyAt = Date.distantPast
    /// The text field's own editor takes ↑ ↓ (it moves the text cursor), so the list never saw them: while the launcher
    /// is open, these keys are caught first and move the selection.
    @State private var arrowMonitor: Any?
    @Namespace private var glide
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// The active pane's actions (⇧⌘A) instead of the launcher's entries.
    var actionsOnly = false

    private var rows: [LauncherRow] {
        actionsOnly
            ? Fuzzy.rank(shell.paneActionEntries(), query: query, recents: [])
            : Fuzzy.rank(shell.launcher.entries, query: query, recents: shell.launcher.recents)
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            if actionsOnly { PaneActionsHeader(shell: shell) }
            HStack(spacing: Space.s3) {
                Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                    .accessibilityHidden(true)
                TextField(
                    "Launcher", text: $query,
                    prompt: Text(actionsOnly ? "Do something with this pane…" : "Open an app or run a command…")
                        .foregroundStyle(GlassInk.secondary)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(GlassInk.primary)
                .font(.system(size: MacTextSize.large))
                .focused($focused)
                .onSubmit { run(rows) }
                .onKeyPress(.escape) {
                    shell.closeTopmost()
                    return .handled
                }
                .onKeyPress(phases: [.down, .repeat]) { press in key(press, rows.count) }
                .onAppear { catchArrows() }
                .onDisappear {
                    if let arrowMonitor { NSEvent.removeMonitor(arrowMonitor) }
                    arrowMonitor = nil
                }
                .accessibilityLabel("Launcher")
            }
            .padding(Space.s4)
            ScrollViewReader { proxy in
                GlassScroll {
                    // Not lazy: a lazy stack builds rows as they scroll in, and each one replayed its arrival.
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            if i == 0 || rows[i - 1].group != row.group { groupTitle(row.group) }
                            LauncherItem(
                                row: row, index: i, number: i < 9 ? i + 1 : nil, selected: i == selection, glide: glide,
                                hover: {
                                    if Date().timeIntervalSince(keyAt) > 0.3 { point(i) }
                                }
                            ) {
                                selection = i
                                run(rows)
                            }
                            .id(row.id)
                        }
                        if rows.isEmpty { empty }
                    }
                    .padding(.horizontal, Space.s3)
                }
                .onChange(of: selection) { _, new in
                    // The list scrolls on the same curve the highlight glides on, so the two move together.
                    // Only the keyboard scrolls the list; a row under the pointer is already in view.
                    guard rows.indices.contains(new), Date().timeIntervalSince(keyAt) < 0.3 else { return }
                    withAnimation(reduce ? nil : Motion.out(Motion.hover)) { proxy.scrollTo(rows[new].id) }
                }
            }
            footer
        }
        .frame(width: ShellMetrics.launcherWidth)
        .frame(maxHeight: Space.s8 * 18)
        .fixedSize(horizontal: false, vertical: true)
        // The one frame: a glass rim around the Look's background (Settings, Appearance).
        .coreFrame(radius: Radius.panel + Space.s1)
        .background { numberShortcuts(rows) }
        .task {
            // The root holds focus while the window is calm; take it once the overlay is in place.
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
        .onAppear {
            query = shell.launcherQuery
            shell.launcherQuery = ""
        }
        .onChange(of: query) { selection = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Launcher")
        .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.97)))
    }

    private func groupTitle(_ group: LauncherEntry.Group) -> some View {
        Text(group.title).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.secondary)
            .padding(.top, Space.s3).padding(.horizontal, Space.s2).accessibilityAddTraits(.isHeader)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            if query.isEmpty {
                Text(actionsOnly ? "No app is open" : "Nothing to show yet")
                    .font(.system(size: MacTextSize.headline, weight: .semibold))
            } else {
                Text("Nothing matches “\(query)”").font(.system(size: MacTextSize.headline, weight: .semibold))
                Text("Try fewer letters, or the first letters of each word.").foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(Space.s4)
    }

    private var footer: some View {
        HStack(spacing: Space.s4) {
            hint("↑↓", "move")
            hint("↵", "open")
            hint("⌘1–9", "pick")
            hint("⌘/", "all shortcuts")
            hint("esc", "close")
        }
        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(Space.s3)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: Space.s1) {
            CoreKeycap(keys)
            Text(label)
        }
    }

    /// ⌘1–⌘9 as invisible buttons: they exist only while the launcher is open.
    private func numberShortcuts(_ rows: [LauncherRow]) -> some View {
        ZStack {
            ForEach(1...9, id: \.self) { n in
                Button("Pick \(n)") {
                    guard rows.indices.contains(n - 1) else { return }
                    selection = n - 1
                    run(rows)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    /// ↑ ↓ and ⌃P ⌃N wrap around; ⇞ ⇟ jump 8 rows; ⌘↑ ⌘↓ go to the first and last row.
    private func key(_ press: KeyPress, _ count: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        let step: Int
        let control = press.modifiers == .control
        switch press.key {
        case .downArrow where press.modifiers == .command: return jump(count - 1)
        case .upArrow where press.modifiers == .command: return jump(0)
        case .downArrow where press.modifiers.isEmpty: step = 1
        case .upArrow where press.modifiers.isEmpty: step = -1
        case .pageDown: return jump(min(selection + 8, count - 1))
        case .pageUp: return jump(max(selection - 8, 0))
        case KeyEquivalent("n") where control: step = 1
        case KeyEquivalent("p") where control: step = -1
        default: return .ignored
        }
        keyAt = Date()
        glide((selection + step + count) % count)
        return .handled
    }

    private func catchArrows() {
        guard arrowMonitor == nil else { return }
        arrowMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let count = rows.count
            guard count > 0 else { return e }
            let command = e.modifierFlags.contains(.command)
            let control = e.modifierFlags.contains(.control)
            switch e.keyCode {
            case 125 where command: _ = jump(count - 1)  // ⌘↓
            case 126 where command: _ = jump(0)  // ⌘↑
            case 125: step(1, count)  // ↓
            case 126: step(-1, count)  // ↑
            case 121: _ = jump(min(selection + 8, count - 1))  // page down
            case 116: _ = jump(max(selection - 8, 0))  // page up
            case 45 where control: step(1, count)  // ⌃N
            case 35 where control: step(-1, count)  // ⌃P
            default: return e
            }
            return nil
        }
    }

    private func step(_ by: Int, _ count: Int) {
        keyAt = Date()
        glide((selection + by + count) % count)
    }

    private func jump(_ to: Int) -> KeyPress.Result {
        keyAt = Date()
        glide(to)
        return .handled
    }

    /// The keyboard moves the highlight with a glide and scrolls along on the same curve.
    private func glide(_ to: Int) {
        withAnimation(reduce ? nil : Motion.out(Motion.hover)) { selection = to }
    }

    /// The pointer glides it too, on a short ease that redirects as the pointer moves on instead of queueing one glide
    /// per row it crossed (that lag read as a glitch).
    private func point(_ to: Int) {
        guard to != selection else { return }
        withAnimation(reduce ? nil : Motion.out(Motion.hover)) { selection = to }
    }

    private func run(_ rows: [LauncherRow]) {
        guard rows.indices.contains(selection) else { return }
        let entry = rows[selection].entry
        shell.launcher.remember(entry.id)
        shell.launcherOpen = false
        shell.actionsOpen = false
        entry.run()
    }
}

private struct LauncherItem: View {
    let row: LauncherRow
    let index: Int
    let number: Int?
    let selected: Bool
    let glide: Namespace.ID
    let hover: () -> Void
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var arrived = false
    @State private var lastPoint: CGPoint?
    /// Counts only the moments this row becomes selected, so the icon bounces on select and not on deselect.
    @State private var picked = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: row.entry.symbol).font(.system(size: MacTextSize.headline, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: MacSize.controlLg, height: MacSize.controlLg)
                    .background(
                        LinearGradient(
                            colors: [hue.opacity(0.95), hue.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                        in: coreShape(Radius.control)
                    )
                    .overlay { coreShape(Radius.control).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                    .symbolEffect(.bounce, value: picked)
                    .accessibilityHidden(true)
                title
                Spacer(minLength: Space.s2)
                if let sub = row.entry.sub {
                    Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                if let number { CoreKeycap("⌘\(number)") }
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s2)
            .frame(height: MacSize.controlLg + Space.s3)
            // One highlight that glides between rows (`shell-fx.css` .l-glide), not a background swapped per row.
            .background {
                if selected {
                    coreShape(Radius.row).fill(.white.opacity(0.18))
                        .overlay { coreShape(Radius.row).strokeBorder(.white.opacity(0.3), lineWidth: 1) }
                        .matchedGeometryEffect(id: "selection", in: glide)
                }
            }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onChange(of: selected) { _, now in if now { picked += 1 } }
        // Rows arrive one after another when the launcher opens (22 ms apart, the first nine).
        .opacity(arrived || reduce ? 1 : 0)
        .offset(y: arrived || reduce ? 0 : 6)
        .onAppear {
            withAnimation(Motion.out(Motion.ui).delay(Double(min(index, 8)) * 0.022)) { arrived = true }
        }
        // Only a moving pointer selects: the first event on arrival (the launcher opening under a still pointer) does not.
        // Only a pointer that really moves selects. Rows scrolling under a still pointer change the row-local point, so
        // the screen position is what is compared (that loop made scrolling jitter).
        .onContinuousHover { phase in
            guard case .active = phase else {
                lastPoint = nil
                return
            }
            let p = NSEvent.mouseLocation
            if let last = lastPoint, last != p { hover() }
            lastPoint = p
        }
        .contextMenu {
            Button("Open", action: action)
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.entry.title, forType: .string)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel([row.entry.title, row.entry.sub].compactMap { $0 }.joined(separator: ", "))
    }

    /// Blue when selected, slate otherwise; red stays for a destructive entry (it means something).
    private var hue: Color {
        if row.entry.tile == .danger { return GlassInk.red }
        return selected ? GlassInk.blue : GlassInk.slate
    }

    private var title: Text {
        var out = AttributedString(row.entry.title)
        let chars = Array(out.characters.indices)
        for i in row.matched where chars.indices.contains(i) {
            let r = chars[i]..<out.characters.index(after: chars[i])
            out[r].font = .system(size: MacTextSize.headline, weight: .semibold)
            out[r].foregroundColor = row.entry.tile == .danger ? GlassInk.red : GlassInk.blue
        }
        return Text(out).font(.system(size: MacTextSize.headline, weight: .semibold))
    }
}

/// ⇧⌘A's header: the pane the actions are for, its picture, title and live state, arriving with a bounce.
private struct PaneActionsHeader: View {
    let shell: ShellModel
    @State private var shown = false
    var body: some View {
        if let id = shell.activePane ?? shell.panes.first?.id, let spec = shell.panes.first(where: { $0.id == id }) {
            HStack(spacing: Space.s3) {
                IconTile(spec.symbol, hue: GlassInk.blue, size: 44, bounce: shown)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Actions").font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(
                        GlassInk.secondary)
                    HStack(spacing: Space.s2) {
                        Text(spec.title).font(.system(size: MacTextSize.title, weight: .semibold))
                        if let sub = spec.sub { Text(sub).foregroundStyle(GlassInk.secondary) }
                    }
                }
                Spacer(minLength: 0)
                if let chip = spec.chip {
                    HStack(spacing: Space.s1) {
                        StatusDot(
                            color: chip.tone == .fail
                                ? GlassInk.red : chip.tone == .warn ? GlassInk.orange : GlassInk.green,
                            live: chip.tone == .run || chip.tone == .done)
                        Text(chip.label).font(.system(size: MacTextSize.meta, weight: .medium))
                    }
                    .padding(.horizontal, Space.s2).frame(height: MacSize.controlSm + 2)
                    .background(GlassInk.well, in: coreShape(Radius.chip))
                }
            }
            .foregroundStyle(GlassInk.primary)
            .padding([.horizontal, .top], Space.s4)
            .coreRise(shown, 0)
            .onAppear { shown = true }
        }
    }
}
