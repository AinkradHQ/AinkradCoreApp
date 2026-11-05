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
    /// Rows rise in one after another when the launcher opens; the selection glides between them.
    @State private var arrived = false
    @Namespace private var lens

    private var rows: [LauncherRow] {
        Fuzzy.rank(shell.launcher.entries, query: query, recents: shell.launcher.recents)
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            HStack(spacing: Space.s3) {
                Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                    .accessibilityHidden(true)
                TextField(
                    "Launcher", text: $query,
                    prompt: Text("Open an app or run a command…").foregroundStyle(WidgetInk.secondary)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(WidgetInk.primary)
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
                            LauncherItem(
                                row: row, number: i < 9 ? i + 1 : nil, selected: i == selection, lens: lens
                            ) {
                                selection = i
                                run(rows)
                            }
                            .id(row.id)
                            .rise(arrived, min(i, 10), reduce)
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
        // The widgets' clear glass: the sky shows through, white ink on top (Ahmed, 2026-11-05).
        // Darker than a widget: it is an input, so the text sits on a calmer surface.
        .background(Color.black.opacity(palette.isDay ? 0.4 : 0.32), in: coreShape(Radius.panel + Space.s1))
        .coreGlass(radius: Radius.panel + Space.s1, interactive: false, tinted: false, frosted: true)
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .background { numberShortcuts(rows) }
        .animation(reduce ? .easeOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.2), value: selection)
        .onAppear { arrived = true }
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
        Text(group.title).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(WidgetInk.secondary)
            .padding(.top, Space.s3).padding(.horizontal, Space.s2).accessibilityAddTraits(.isHeader)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Nothing matches “\(query)”").font(.system(size: MacTextSize.headline, weight: .semibold))
            Text("Try fewer letters, or the first letters of each word.").foregroundStyle(WidgetInk.secondary)
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
        .font(.system(size: MacTextSize.meta)).foregroundStyle(WidgetInk.secondary)
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
    let lens: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    /// Each group has its colour, so the list reads at a glance.
    private var hue: Color {
        switch row.group {
        case .recent, .topHit: WidgetInk.blue
        case .actions: WidgetInk.green
        case .goTo: WidgetInk.orange
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: row.entry.symbol).font(.system(size: MacTextSize.body + 1, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: selected)
                    .frame(width: MacSize.controlLg, height: MacSize.controlLg)
                    .background(
                        LinearGradient(
                            colors: [hue.opacity(0.95), hue.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                        in: coreShape(Radius.control)
                    )
                    .overlay { coreShape(Radius.control).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                    .shadow(color: hue.opacity(selected ? 0.6 : 0), radius: 8)
                    .accessibilityHidden(true)
                title
                Spacer(minLength: Space.s2)
                if let sub = row.entry.sub {
                    Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(WidgetInk.secondary).lineLimit(1)
                }
                if let number { CoreKeycap("⌘\(number)") }
            }
            .foregroundStyle(WidgetInk.primary)
            .padding(.horizontal, Space.s2)
            .frame(height: MacSize.controlLg + Space.s3)
            .background {
                if selected {
                    coreShape(Radius.row).fill(.white.opacity(0.18))
                        .overlay { coreShape(Radius.row).strokeBorder(.white.opacity(0.3), lineWidth: 1) }
                        .matchedGeometryEffect(id: "selection", in: lens)
                } else if hovering {
                    coreShape(Radius.row).fill(WidgetInk.well.opacity(0.6))
                }
            }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel([row.entry.title, row.entry.sub].compactMap { $0 }.joined(separator: ", "))
    }

    /// Matched letters in the group's colour, the rest white.
    private var title: Text {
        var out = AttributedString(row.entry.title)
        let chars = Array(out.characters.indices)
        for i in row.matched where chars.indices.contains(i) {
            let r = chars[i]..<out.characters.index(after: chars[i])
            out[r].font = .system(size: MacTextSize.headline, weight: .bold)
            out[r].foregroundColor = hue
        }
        return Text(out).font(.system(size: MacTextSize.headline, weight: .semibold))
    }
}
