import CoreUI
import SwiftUI

/// Every shortcut the shell owns. The ⌘/ sheet reads this; `ShellCommands` binds the same keys.
enum ShortcutCatalog {
    static let groups: [(name: String, items: [(title: String, keys: String)])] = [
        ("Ainkrad", [("Settings…", "⌘,"), ("Keyboard Shortcuts", "⌘/")]),
        (
            "File",
            [
                ("Launcher…", "⌘K"), ("New Agent Session", "⌘N"), ("New Terminal", "⌘T"), ("Close Pane", "⌘W"),
                ("Reopen Closed Pane", "⇧⌘T"), ("Close All Panes", "⌥⌘W"),
            ]
        ),
        (
            "View",
            [
                ("Home", "⌘0"), ("Workspace", "⇧⌘0"), ("Focus Mode", "⇧⌘F"), ("Notifications", "⇧⌘N"),
                ("Reconnect to Core", "⌘R"),
                ("Switch Day and Night", "⌃⌘D"), ("Next Pane", "⌘`"), ("Previous Pane", "⇧⌘`"),
                ("Move Pane Left", "⌃⌥←"), ("Move Pane Right", "⌃⌥→"),
            ]
        ),
        (
            "Panes",
            [("Focus mode tabs", "← →"), ("Focus or tile a pane", "double click head"), ("Tile a pane", "drag head")]
        ),
        (
            "Launcher",
            [
                ("Move", "↑ ↓  ⌃N ⌃P"), ("Page", "⇞ ⇟"), ("First or last", "⌘↑ ⌘↓"), ("Open", "↵"),
                ("Pick a result", "⌘1–9"), ("Close", "esc"),
            ]
        ),
    ]
}

/// ⌘/ : all shortcuts, filterable.
struct ShortcutsView: View {
    @Bindable var shell: ShellModel
    @State private var filter = ""
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Keyboard Shortcuts").font(.system(size: MacTextSize.title, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            TextField("Filter shortcuts", text: $filter)
                .textFieldStyle(.plain)
                .padding(.horizontal, Space.s3).frame(height: MacSize.controlLg)
                .background(palette.uDim, in: coreShape(Radius.control))
                .overlay {
                    if focused { coreShape(Radius.control).strokeBorder(palette.focusRing, lineWidth: Space.s1 / 2) }
                }
                .focused($focused)
                .onKeyPress(.escape) {
                    shell.overlay = nil
                    return .handled
                }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(ShortcutCatalog.groups, id: \.name) { g in
                        let items = g.items.filter {
                            filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter)
                        }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: Space.s1) {
                                Text(g.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(items, id: \.title) { item in
                                    HStack {
                                        Text(item.title)
                                        Spacer()
                                        CoreKeycap(item.keys)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { shell.overlay = nil }.buttonStyle(.coreProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s5)
        .frame(width: Space.s8 * 14, height: Space.s8 * 16)
        .corePanel(radius: Radius.panel, padding: 0)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .task {
            // The root holds focus while the window is calm; take it once the overlay is in place.
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard Shortcuts")
        .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.97)))
    }
}

/// The app menus. Add to a scene with `.commands { ShellCommands(shell: shell) }`.
public struct ShellCommands: Commands {
    let shell: ShellModel
    /// Passed in from the App body: `Commands` do not observe `@Observable` models, so a value read from the model inside
    /// them goes stale. The App body reads them, so the menus rebuild when they change.
    let paneCount: Int
    let focusMode: Bool
    let closedCount: Int
    let chipOn: Bool
    let coreOffline: Bool
    let paneTitles: [(id: String, title: String)]
    public init(
        shell: ShellModel, paneCount: Int, focusMode: Bool, closedCount: Int = 0, chipOn: Bool = true,
        coreOffline: Bool = false,
        paneTitles: [(id: String, title: String)] = []
    ) {
        self.shell = shell
        self.paneCount = paneCount
        self.focusMode = focusMode
        self.closedCount = closedCount
        self.chipOn = chipOn
        self.coreOffline = coreOffline
        self.paneTitles = paneTitles
    }

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { shell.open(.settings) }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Launcher…") { shell.toggleLauncher() }.keyboardShortcut("k")
            Divider()
            Button("New Agent Session") { shell.launcher.entry("agents.new")?.run() }.keyboardShortcut("n")
            Button("New Terminal") { shell.launcher.entry("new-terminal")?.run() }.keyboardShortcut("t")
            Button("New Terminal (Advanced)…") { shell.launcher.entry("new-terminal-advanced")?.run() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Pane") { if let id = shell.activePane { shell.dismissPane(id) } }
                .keyboardShortcut("w").disabled(paneCount == 0)
            Button("Reopen Closed Pane") { shell.reopenClosedPane() }
                .keyboardShortcut("t", modifiers: [.command, .shift]).disabled(closedCount == 0)
            Button("Close All Panes") { shell.closeAllPanes() }
                .keyboardShortcut("w", modifiers: [.command, .option]).disabled(paneCount == 0)
        }
        CommandGroup(replacing: .sidebar) {
            Button("Home") { shell.show(.home) }.keyboardShortcut("0")
            Button("Workspace") { shell.show(.workspace) }.keyboardShortcut("0", modifiers: [.command, .shift])
            Button(!focusMode ? "Focus Mode" : "Tile Panes") { shell.toggleFocusMode() }
                .keyboardShortcut("f", modifiers: [.command, .shift]).disabled(paneCount == 0)
            Button("Notifications") { shell.toggleBell() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Switch Day and Night") {
                shell.theme = shell.theme == .night ? .day : .night
            }
            .keyboardShortcut("d", modifiers: [.control, .command])
            Button("Reconnect to Core") { shell.retryConnection?() }.keyboardShortcut("r").disabled(!coreOffline)
            Toggle("Show Activity in Status Bar", isOn: Binding(get: { chipOn }, set: { shell.showActivityChip = $0 }))
            Divider()
            Button("Next Pane") { shell.cyclePane(1) }.keyboardShortcut("`").disabled(paneCount < 2)
            Button("Previous Pane") { shell.cyclePane(-1) }.keyboardShortcut("`", modifiers: [.command, .shift])
                .disabled(paneCount < 2)
            Button("Move Pane Left") { shell.nudgeActivePane(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [.control, .option]).disabled(paneCount < 2)
            Button("Move Pane Right") { shell.nudgeActivePane(1) }
                .keyboardShortcut(.rightArrow, modifiers: [.control, .option]).disabled(paneCount < 2)
        }
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .windowSize) {}
        // Panes by name. (⌘1–9 stays with the launcher's own picks, so these have no shortcuts.)
        CommandGroup(before: .windowList) {
            ForEach(paneTitles, id: \.id) { p in
                Button(p.title) {
                    if let spec = shell.panes.first(where: { $0.id == p.id }) { shell.openPane(spec) }
                }
            }
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { shell.open(.shortcuts) }.keyboardShortcut("/")
        }
    }
}
