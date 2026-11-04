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
    @Namespace private var glide
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var rows: [LauncherRow] {
        Fuzzy.rank(shell.launcher.entries, query: query, recents: shell.launcher.recents)
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            HStack(spacing: Space.s3) {
                Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                    .accessibilityHidden(true)
                TextField("Open an app or run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: MacTextSize.large))
                    .focused($focused)
                    .onSubmit { run(rows) }
                    .onKeyPress(.escape) {
                        shell.closeTopmost()
                        return .handled
                    }
                    .onKeyPress(phases: [.down, .repeat]) { press in key(press, rows.count) }
                    .accessibilityLabel("Launcher")
            }
            .padding(Space.s4)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            if i == 0 || rows[i - 1].group != row.group { groupTitle(row.group) }
                            LauncherItem(
                                row: row, index: i, number: i < 9 ? i + 1 : nil, selected: i == selection, glide: glide,
                                hover: {
                                    if Date().timeIntervalSince(keyAt) > 0.3 { selection = i }
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
                    .animation(reduce ? nil : Motion.out(0.22), value: selection)
                }
                .onChange(of: selection) { _, new in
                    if rows.indices.contains(new) { proxy.scrollTo(rows[new].id) }
                }
            }
            footer
        }
        .frame(width: ShellMetrics.launcherWidth)
        .frame(maxHeight: Space.s8 * 18)
        .fixedSize(horizontal: false, vertical: true)
        .corePanel(radius: Radius.panel, padding: 0)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .background { numberShortcuts(rows) }
        .task {
            // The root holds focus while the window is calm; take it once the overlay is in place.
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
        .onChange(of: query) { selection = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Launcher")
        .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.97)))
    }

    private func groupTitle(_ group: LauncherEntry.Group) -> some View {
        Text(group.title).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
            .padding(.top, Space.s3).padding(.horizontal, Space.s2).accessibilityAddTraits(.isHeader)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Nothing matches “\(query)”").font(.system(size: MacTextSize.headline, weight: .semibold))
            Text("Try fewer letters, or the first letters of each word.").foregroundStyle(palette.text2)
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
        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
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
        selection = (selection + step + count) % count
        return .handled
    }

    private func jump(_ to: Int) -> KeyPress.Result {
        keyAt = Date()
        selection = to
        return .handled
    }

    private func run(_ rows: [LauncherRow]) {
        guard rows.indices.contains(selection) else { return }
        let entry = rows[selection].entry
        shell.launcher.remember(entry.id)
        shell.launcherOpen = false
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: row.entry.symbol).font(.system(size: MacTextSize.body, weight: .medium))
                    .foregroundStyle(row.entry.tile == .slate ? palette.text : palette.btnInk)
                    .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .background(tile, in: coreShape(Radius.control))
                    .accessibilityHidden(true)
                title
                Spacer(minLength: Space.s2)
                if let sub = row.entry.sub {
                    Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).lineLimit(1)
                }
                if let number { CoreKeycap("⌘\(number)") }
            }
            .padding(.horizontal, Space.s2)
            .frame(height: MacSize.controlLg + Space.s2)
            // One highlight that glides between rows (`shell-fx.css` .l-glide), not a background swapped per row.
            .background {
                if selected {
                    coreShape(Radius.row).fill(palette.navActive)
                        .overlay { coreShape(Radius.row).strokeBorder(palette.navActiveEdge, lineWidth: 1) }
                        .matchedGeometryEffect(id: "selection", in: glide)
                }
            }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        // Rows arrive one after another when the launcher opens (22 ms apart, the first nine).
        .opacity(arrived || reduce ? 1 : 0)
        .offset(y: arrived || reduce ? 0 : 6)
        .onAppear {
            withAnimation(Motion.out(0.3).delay(Double(min(index, 8)) * 0.022)) { arrived = true }
        }
        // Only a moving pointer selects: the first event on arrival (the launcher opening under a still pointer) does not.
        .onContinuousHover { phase in
            guard case .active(let p) = phase else { return lastPoint = nil }
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

    private var tile: Color { row.entry.tile == .slate ? palette.uDimHover : palette.btnPrimary }

    private var title: Text {
        var out = AttributedString(row.entry.title)
        let chars = Array(out.characters.indices)
        for i in row.matched where chars.indices.contains(i) {
            let r = chars[i]..<out.characters.index(after: chars[i])
            out[r].font = .system(size: MacTextSize.headline, weight: .bold)
            out[r].foregroundColor = palette.primary
        }
        return Text(out).font(.system(size: MacTextSize.headline, weight: .semibold))
    }
}
