import CoreUI
import SwiftUI

/// ⌘K: fuzzy search over every registered entry, grouped. Return runs, ⌘1–9 pick, Esc closes.
struct LauncherView: View {
    @Bindable var shell: ShellModel
    @State private var query = ""
    @State private var selection = 0
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
                    .onKeyPress(.downArrow) { move(1, rows.count) }
                    .onKeyPress(.upArrow) { move(-1, rows.count) }
                    .accessibilityLabel("Launcher")
            }
            .padding(Space.s4)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            if i == 0 || rows[i - 1].group != row.group { groupTitle(row.group) }
                            LauncherItem(row: row, number: i < 9 ? i + 1 : nil, selected: i == selection) {
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

    private func move(_ step: Int, _ count: Int) -> KeyPress.Result {
        guard count > 0 else { return .handled }
        selection = (selection + step + count) % count
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
    let number: Int?
    let selected: Bool
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: row.entry.symbol).font(.system(size: MacTextSize.body, weight: .medium))
                    .foregroundStyle(palette.btnInk)
                    .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .background(palette.btnPrimary, in: coreShape(Radius.control))
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
            .background(selected ? palette.navActive : hovering ? palette.rowHover : .clear, in: coreShape(Radius.row))
            .overlay { if selected { coreShape(Radius.row).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel([row.entry.title, row.entry.sub].compactMap { $0 }.joined(separator: ", "))
    }

    private var title: Text {
        var out = AttributedString(row.entry.title)
        let chars = Array(out.characters.indices)
        for i in row.matched where chars.indices.contains(i) {
            out[chars[i]..<out.characters.index(after: chars[i])].font = .system(
                size: MacTextSize.headline, weight: .bold)
        }
        return Text(out).font(.system(size: MacTextSize.headline, weight: .semibold))
    }
}
