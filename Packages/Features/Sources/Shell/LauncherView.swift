import AppKit
import CoreUI
import SwiftUI

/// ⌘K (07-launcher): about six suggestions ranked by use and a collapsed header per group; a query searches everything, grouped.
/// The list is built when the query, the open group or the entries change, never while drawing, and it is lazy. Fully on the
/// keyboard: ↑ ↓ move, ⇥ next group, ↵ opens (or opens/closes a group), ⌘↵ opens beside, ⌥↵ copies the name, → the actions, ⌘1–9 pick.
struct LauncherView: View {
    @Bindable var shell: ShellModel
    @State private var query = ""
    @State private var selection = 0
    /// The flat list of everything selectable, rebuilt by `rebuild()`.
    @State private var lines: [LauncherLine] = []
    /// The group whose entries are showing under its header.
    @State private var open: LauncherSection?
    /// Nothing matched the query: the lines are the fallback actions.
    @State private var noMatch = false
    /// The line whose actions menu (→) is showing.
    @State private var menuFor: String?
    /// The pointer only moves the selection while the keyboard has not moved it just now (a list scrolling under a still pointer is not a hover).
    @State private var keyAt = Date.distantPast
    /// The text field's own editor takes ↑ ↓ (it moves the text cursor), so the list never saw them: while the launcher
    /// is open, these keys are caught first and move the selection.
    @State private var keyMonitor: Any?
    @Namespace private var glide
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// The active pane's actions (⇧⌘A) instead of the launcher's entries.
    var actionsOnly = false

    var body: some View {
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
                .coreFont(size: MacTextSize.large)
                .focused($focused)
                .onSubmit { activate(at: selection) }
                .onKeyPress(phases: [.down, .repeat]) { press in key(press) }
                .onAppear { catchKeys() }
                .onDisappear {
                    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                    keyMonitor = nil
                }
                .accessibilityLabel("Launcher")
            }
            .padding(Space.s4)
            ScrollViewReader { proxy in
                GlassScroll {
                    LazyVStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                            if let h = line.heading, i == 0 || lines[i - 1].heading != h { sectionTitle(h) }
                            if i == 0, case .pick = line { sectionTitle(suggestionTitle) }
                            if case .group = line, i == 0 || !lines[i - 1].isGroup, !isNested(i - 1) {
                                sectionTitle("Browse")
                            }
                            if noMatch, i == 0 { empty }
                            if case .pick = line {
                                // Two to a row (07-launcher `.n7-picks`); the second of each pair is drawn with the first.
                                if i % 2 == 0 {
                                    HStack(spacing: Space.s1) {
                                        pickCell(i, line)
                                        if lines.indices.contains(i + 1), case .pick = lines[i + 1] {
                                            pickCell(i + 1, lines[i + 1])
                                        } else {
                                            Color.clear.frame(maxWidth: .infinity)
                                        }
                                    }
                                    .id(line.id)
                                }
                            } else {
                                row(i, line).id(line.id)
                            }
                        }
                        if lines.isEmpty { empty }
                    }
                    .padding(.horizontal, Space.s3)
                }
                .onChange(of: selection) { _, new in
                    // The list scrolls on the same curve the highlight glides on, so the two move together.
                    // Only the keyboard scrolls the list; a row under the pointer is already in view.
                    guard lines.indices.contains(new), Date().timeIntervalSince(keyAt) < 0.3 else { return }
                    var target = lines[new].id
                    // A suggestion is drawn with its row's first cell.
                    if case .pick = lines[new], new % 2 == 1 { target = lines[new - 1].id }
                    proxy.scrollTo(target)
                }
            }
            footer
        }
        .frame(width: ShellMetrics.launcherWidth)
        .frame(maxHeight: Space.s8 * 18)
        .fixedSize(horizontal: false, vertical: true)
        // The one frame: a glass rim around the Look's background (Settings, Appearance).
        .coreFrame(radius: Radius.pane + Space.s1, part: .launcher)
        .background { numberShortcuts }
        // The root holds focus while the window is calm; the field takes it as it appears, so the first typed key lands.
        .defaultFocus($focused, true)
        .onAppear {
            focused = true
            shell.launcher.refreshPicks()
            query = shell.launcherQuery
            shell.launcherQuery = ""
            rebuild()
        }
        .onChange(of: query) {
            selection = 0
            menuFor = nil
            rebuild()
        }
        .onChange(of: shell.launcher.version) { rebuild() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Launcher")
        .transition(.opacity)
    }

    // MARK: the list

    /// Built once per change, off the drawing path.
    private func rebuild() {
        let found: [LauncherLine]
        if actionsOnly {
            found = LauncherLines.actions(Fuzzy.rank(shell.paneActionEntries(), query: query, recents: []))
        } else if query.isEmpty {
            found = LauncherLines.browse(entries: shell.launcher.entries, picks: shell.launcher.picks, open: open)
        } else {
            var hits = LauncherLines.results(
                Fuzzy.rank(
                    shell.launcher.entries, query: query, recents: shell.launcher.recents, usage: shell.launcher.bonus))
            // Nothing matched: what the modules offer to do with the words instead.
            let none = hits.isEmpty
            if none {
                hits = shell.launcher.fallbacks.map { f in
                    let q = query
                    let e = LauncherEntry(id: "fallback-\(f.id)", title: f.title(q), symbol: f.symbol, isAction: true) {
                        f.run(q)
                    }
                    return .item(LauncherRow(entry: e, group: .actions, matched: []), heading: nil, nested: false)
                }
            }
            noMatch = none
            found = hits
        }
        if actionsOnly || query.isEmpty { noMatch = false }
        lines = found
        selection = min(selection, max(found.count - 1, 0))
    }

    private var suggestionTitle: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Suggested for this morning"
        case 12..<18: "Suggested for this afternoon"
        default: "Suggested for this evening"
        }
    }

    private func isNested(_ i: Int) -> Bool {
        guard lines.indices.contains(i), case .item(_, _, let nested) = lines[i] else { return false }
        return nested
    }

    @ViewBuilder private func row(_ i: Int, _ line: LauncherLine) -> some View {
        switch line {
        case .pick(let p):
            LauncherItem(
                entry: p.entry, matched: [], sub: p.reason, number: i < 6 ? i + 1 : nil, nested: false,
                selected: i == selection, glide: glide, hover: { hoverOver(i) }
            ) { activate(at: i) }
        case .item(let r, _, let nested):
            LauncherItem(
                entry: r.entry, matched: r.matched, sub: r.entry.sub,
                number: !nested && (actionsOnly || !query.isEmpty) && i < 9 ? i + 1 : nil, nested: nested,
                selected: i == selection,
                glide: glide, hover: { hoverOver(i) }, copy: { copyName(r.entry) },
                beside: { activate(at: i, beside: true) }
            ) { activate(at: i) }
            if menuFor == line.id { actionsMenu(r.entry, at: i) }
        case .group(let s, let count, let isOpen):
            LauncherGroupRow(
                section: s, count: count, open: isOpen, selected: i == selection, glide: glide, hover: { hoverOver(i) }
            ) { activate(at: i) }
        }
    }

    @ViewBuilder private func pickCell(_ i: Int, _ line: LauncherLine) -> some View {
        if case .pick(let p) = line {
            LauncherPickCell(
                entry: p.entry, reason: p.reason, number: i < 6 ? i + 1 : nil, selected: i == selection, glide: glide,
                hover: { hoverOver(i) }
            ) { activate(at: i) }
        }
    }

    private func hoverOver(_ i: Int) {
        if Date().timeIntervalSince(keyAt) > 0.3 { point(i) }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .padding(.top, Space.s3).padding(.horizontal, Space.s2).accessibilityAddTraits(.isHeader)
    }

    /// Nothing matched: says so and how to try again.
    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Nothing matches “\(query)”").coreFont(size: MacTextSize.headline, weight: .semibold)
            Text("Try fewer letters, or the first letters of each word.").foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s4)
    }

    private func actionsMenu(_ entry: LauncherEntry, at i: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            menuItem("arrow.right", "Open", "↵") { activate(at: i) }
            menuItem("rectangle.split.2x1", "Open beside the current app", "⌘↵") { activate(at: i, beside: true) }
            menuItem("doc.on.doc", "Copy name", "⌥↵") { copyName(entry) }
            menuItem("folder", "Show in Projects", "⌘⇧P", enabled: isProject(entry)) { activate(at: i) }
            menuItem("xmark", "Close it", "⌘⌫", enabled: isOpen(entry)) { closeIt(entry) }
        }
        .padding(Space.s1)
        .coreGlass(radius: Radius.cardMac, interactive: false)
        .padding(.leading, Space.s8 * 3)
        .transition(.opacity)
    }

    private func isProject(_ e: LauncherEntry) -> Bool { LauncherSection.of(e) == .projects }
    /// Sessions and terminals are launcher entries named like their pane: while the pane is open it can be closed from here.
    private func isOpen(_ e: LauncherEntry) -> Bool { shell.allPanes.contains { $0.id == e.id } }

    private func closeIt(_ e: LauncherEntry) {
        guard isOpen(e) else { return }
        menuFor = nil
        shell.dismissPane(e.id)
        rebuild()
    }

    private func menuItem(
        _ symbol: String, _ title: String, _ keys: String, enabled: Bool = true, _ run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            HStack(spacing: Space.s2) {
                Image(systemName: symbol).frame(width: 16).accessibilityHidden(true)
                Text(title)
                Spacer(minLength: Space.s3)
                CoreKeycap(keys)
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s2).frame(height: MacSize.controlMd)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var footer: some View {
        HStack(spacing: Space.s3) {
            hint("↑↓", "move")
            hint("↵", "open")
            hint("⇥", "next group")
            hint("⌘↵", "beside")
            hint("⌥↵", "copy name")
            hint("esc", "close")
        }
        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(Space.s3)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: Space.s1) {
            CoreKeycap(keys)
            Text(label)
        }
    }

    /// ⌘1–⌘9 as invisible buttons: they exist only while the launcher is open. They pick the first suggestions, or the first results.
    private var numberShortcuts: some View {
        ZStack {
            ForEach(1...9, id: \.self) { n in
                Button("Pick \(n)") {
                    guard lines.indices.contains(n - 1), !lines[n - 1].isGroup, !isNested(n - 1) else { return }
                    activate(at: n - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    // MARK: keys

    /// ↑ ↓ and ⌃P ⌃N wrap around; ⇞ ⇟ jump 8 rows; ⌘↑ ⌘↓ go to the first and last row.
    private func key(_ press: KeyPress) -> KeyPress.Result {
        let count = lines.count
        guard count > 0 else { return .ignored }
        let control = press.modifiers == .control
        switch press.key {
        case .downArrow where press.modifiers == .command: return jump(count - 1)
        case .upArrow where press.modifiers == .command: return jump(0)
        case .downArrow where press.modifiers.isEmpty: return go(.down)
        case .upArrow where press.modifiers.isEmpty: return go(.up)
        case .leftArrow where press.modifiers.isEmpty: return go(.left)
        case .rightArrow where press.modifiers.isEmpty: return go(.right)
        case .pageDown: return jump(min(selection + 8, count - 1))
        case .pageUp: return jump(max(selection - 8, 0))
        case KeyEquivalent("n") where control: return go(.down)
        case KeyEquivalent("p") where control: return go(.up)
        default: return .ignored
        }
    }

    private func catchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let count = lines.count
            let command = e.modifierFlags.contains(.command)
            let option = e.modifierFlags.contains(.option)
            let shift = e.modifierFlags.contains(.shift)
            let control = e.modifierFlags.contains(.control)
            switch e.keyCode {
            case 53 where menuFor != nil: menuFor = nil  // Esc closes the actions menu before the launcher
            case 36 where command, 76 where command: activate(at: selection, beside: true)  // ⌘↵
            case 36 where option, 76 where option:  // ⌥↵
                if let entry = lines.indices.contains(selection) ? lines[selection].entry : nil { copyName(entry) }
            case 48:  // ⇥ and ⇧⇥ between groups
                if let to = LauncherLines.nextGroup(lines, from: selection, step: shift ? -1 : 1) { jump(to) }
            case 124
            where !query.isEmpty && caretAtEnd() && lines.indices.contains(selection)
                && lines[selection].entry != nil:  // → opens the actions
                menuFor = lines[selection].id
            case 125 where count > 0 && command: _ = jump(count - 1)  // ⌘↓
            case 126 where count > 0 && command: _ = jump(0)  // ⌘↑
            case 125 where count > 0: go(.down)  // ↓
            case 126 where count > 0: go(.up)  // ↑
            case 123 where count > 0 && selectedIsPick(): go(.left)  // ← across the suggestions
            case 124 where count > 0 && selectedIsPick(): go(.right)  // → across the suggestions
            case 35 where command && shift:  // ⌘⇧P show in Projects
                if lines.indices.contains(selection), let e = lines[selection].entry, isProject(e) {
                    activate(at: selection)
                } else {
                    return e
                }
            case 51 where command && menuFor != nil:  // ⌘⌫ close it, while the menu is open
                if lines.indices.contains(selection), let en = lines[selection].entry, isOpen(en) { closeIt(en) }
            case 121 where count > 0: _ = jump(min(selection + 8, count - 1))  // page down
            case 116 where count > 0: _ = jump(max(selection - 8, 0))  // page up
            case 45 where count > 0 && control: go(.down)  // ⌃N
            case 35 where count > 0 && control: go(.up)  // ⌃P
            default: return e
            }
            return nil
        }
    }

    private func caretAtEnd() -> Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return tv.selectedRange.length == 0 && tv.selectedRange.location == (tv.string as NSString).length
    }

    private func selectedIsPick() -> Bool {
        guard lines.indices.contains(selection), case .pick = lines[selection] else { return false }
        return true
    }

    /// One arrow press: the grid moves in two dimensions, the rest of the list in one.
    @discardableResult private func go(_ d: LauncherDirection) -> KeyPress.Result {
        guard let to = LauncherLines.move(lines, from: selection, d) else { return .ignored }
        return jump(to)
    }

    @discardableResult private func jump(_ to: Int) -> KeyPress.Result {
        keyAt = Date()
        menuFor = nil
        glide(to)
        return .handled
    }

    /// The keyboard moves the highlight at once (Ahmed, 2026-11-21: fast and instant, no glide).
    private func glide(_ to: Int) { selection = to }

    /// The pointer glides it too, on a short spring that redirects as the pointer moves on instead of queueing one glide
    /// per row it crossed (that lag read as a glitch).
    private func point(_ to: Int) {
        guard to != selection else { return }
        selection = to
    }

    // MARK: acting

    /// ↵ or a click: a header opens or closes its group, anything else opens its app. `beside` (⌘↵) leaves focus mode so it tiles.
    private func activate(at i: Int, beside: Bool = false) {
        guard lines.indices.contains(i) else { return }
        selection = i
        switch lines[i] {
        case .group(let s, _, _):
            withAnimation(reduce ? nil : Motion.out(Motion.ui)) {
                open = open == s ? nil : s
                rebuild()
            }
        case .pick(let p): launch(p.entry, beside: beside)
        case .item(let r, _, _): launch(r.entry, beside: beside)
        }
    }

    private func launch(_ entry: LauncherEntry, beside: Bool) {
        shell.launcher.remember(entry.id)
        shell.launcherOpen = false
        shell.actionsOpen = false
        if beside {
            // The app comes next to the current one (a new workspace when it does not fit), even from another workspace.
            shell.openBeside = true
            shell.focusedPane = nil
        }
        entry.run()
        if beside {
            // Entries that open their app after a fetch still see the flag for a moment.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                shell.openBeside = false
            }
        }
    }

    private func copyName(_ entry: LauncherEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.title, forType: .string)
        shell.launcherOpen = false
        shell.actionsOpen = false
        shell.showToast("Name copied")
    }
}

/// One of the suggestions: icon, name and why, in a half-width cell.
private struct LauncherPickCell: View {
    @Environment(\.coreAccent) private var paneAccent
    let entry: LauncherEntry
    let reason: String
    let number: Int?
    let selected: Bool
    let glide: Namespace.ID
    let hover: () -> Void
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var lastPoint: CGPoint?

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                IconTile(entry.symbol, hue: GlassInk.accent(paneAccent), size: MacSize.controlLg)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    Text(reason).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s1)
                if let number { CoreKeycap("⌘\(number)") }
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s2)
            .frame(maxWidth: .infinity, minHeight: MacSize.controlLg + Space.s3, alignment: .leading)
            .background {
                if selected {
                    coreShape(Radius.row).fill(palette.navActive).matchedGeometryEffect(id: "selection", in: glide)
                }
            }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            guard case .active = phase else {
                lastPoint = nil
                return
            }
            let p = NSEvent.mouseLocation
            if let last = lastPoint, last != p { hover() }
            lastPoint = p
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(entry.title), \(reason)")
    }
}

/// A group's header: collapsed until opened.
private struct LauncherGroupRow: View {
    let section: LauncherSection
    let count: Int
    let open: Bool
    let selected: Bool
    let glide: Namespace.ID
    let hover: () -> Void
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var lastPoint: CGPoint?

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                IconTile(section.symbol, hue: GlassInk.slate, size: MacSize.controlLg)
                Text(section.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer(minLength: Space.s2)
                Text("\(count)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GlassInk.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .animation(reduce ? nil : Motion.out(Motion.ui), value: open)
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s2)
            .frame(height: MacSize.controlLg + Space.s3)
            .background {
                if selected {
                    coreShape(Radius.row).fill(palette.navActive).matchedGeometryEffect(id: "selection", in: glide)
                }
            }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            guard case .active = phase else {
                lastPoint = nil
                return
            }
            let p = NSEvent.mouseLocation
            if let last = lastPoint, last != p { hover() }
            lastPoint = p
        }
        .accessibilityLabel("\(section.title), \(count)")
        .accessibilityValue(open ? "expanded" : "collapsed")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LauncherItem: View {
    @Environment(\.coreAccent) private var paneAccent
    private var textScale: Double { TextSizePrefs.shared.scale }
    let entry: LauncherEntry
    let matched: [Int]
    let sub: String?
    let number: Int?
    let nested: Bool
    let selected: Bool
    let glide: Namespace.ID
    let hover: () -> Void
    var copy: (() -> Void)?
    var beside: (() -> Void)?
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var lastPoint: CGPoint?

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                IconTile(entry.symbol, hue: hue, size: nested ? MacSize.controlMd : MacSize.controlLg)
                title
                Spacer(minLength: Space.s2)
                if let sub {
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                if let number { CoreKeycap("⌘\(number)") }
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s2)
            .padding(.leading, nested ? Space.s4 : 0)
            .frame(height: MacSize.controlLg + Space.s3)
            // One highlight that glides between rows (`shell-fx.css` .l-glide), not a background swapped per row.
            .background {
                if selected {
                    // The app's one selection: a quiet fill, no outline (Ahmed, 2026-11-15).
                    coreShape(Radius.row).fill(palette.navActive)
                        .matchedGeometryEffect(id: "selection", in: glide)
                }
            }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
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
            if let beside { Button("Open Beside", action: beside) }
            Button("Copy Name") {
                if let copy {
                    copy()
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.title, forType: .string)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel([entry.title, sub].compactMap { $0 }.joined(separator: ", "))
    }

    private var hue: Color {
        switch entry.tile {
        case .slate: GlassInk.slate
        case .danger: GlassInk.red
        case .blue, .view: GlassInk.accent(paneAccent)
        }
    }

    private var title: some View {
        var out = AttributedString(entry.title)
        let chars = Array(out.characters.indices)
        for i in matched where chars.indices.contains(i) {
            let r = chars[i]..<out.characters.index(after: chars[i])
            out[r].font = .core(size: MacTextSize.headline, weight: .bold, scale: textScale)
            out[r].foregroundColor = hue
        }
        return Text(out).coreFont(size: MacTextSize.headline, weight: .semibold)
    }
}

/// ⇧⌘A's header: the pane the actions are for, its picture, title and live state, arriving with a bounce.
private struct PaneActionsHeader: View {
    @Environment(\.coreAccent) private var paneAccent
    let shell: ShellModel
    @State private var shown = false
    var body: some View {
        if let id = shell.activePane ?? shell.panes.first?.id, let spec = shell.panes.first(where: { $0.id == id }) {
            HStack(spacing: Space.s3) {
                IconTile(spec.symbol, hue: GlassInk.accent(paneAccent), size: 44, bounce: shown)
                    .shadow(color: GlassInk.accent(paneAccent).opacity(0.45), radius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Actions").coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(
                        GlassInk.secondary)
                    HStack(spacing: Space.s2) {
                        Text(spec.title).coreFont(size: MacTextSize.title, weight: .bold)
                        if let sub = spec.sub { Text(sub).foregroundStyle(GlassInk.secondary) }
                    }
                }
                Spacer(minLength: 0)
                if let chip = spec.chip {
                    HStack(spacing: Space.s1) {
                        StatusDot(
                            color: chip.tone == .fail
                                ? GlassInk.red : chip.tone == .warn ? GlassInk.amber : GlassInk.green,
                            live: chip.tone == .run || chip.tone == .done)
                        Text(chip.label).coreFont(size: MacTextSize.meta, weight: .medium)
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
