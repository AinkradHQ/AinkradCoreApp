import CoreUI
import SwiftUI

/// Every shortcut the shell owns. The ⌘/ sheet reads this; `ShellCommands` binds the same keys.
enum ShortcutCatalog {
    static let groups: [(name: String, items: [(title: String, keys: String)])] = [
        ("Ainkrad Core", [("Settings…", "⌘,"), ("Keyboard Shortcuts", "⌘/")]),
        (
            "File",
            [("Launcher…", "⌘K"), ("Close Pane", "⌘W"), ("Close All Panes", "⌥⌘W")]
        ),
        (
            "View",
            [
                ("Home", "⌘0"), ("Workspace", "⇧⌘0"), ("Focus Mode", "⇧⌘F"), ("Notifications", "⇧⌘B"),
                ("Next Pane", "⌘`"), ("Previous Pane", "⇧⌘`"), ("Move Pane Left", "⌃⌥←"), ("Move Pane Right", "⌃⌥→"),
            ]
        ),
        ("Launcher", [("Move", "↑ ↓"), ("Open", "↵"), ("Pick a result", "⌘1–9"), ("Close", "esc")]),
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
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard Shortcuts")
        .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.97)))
    }
}

/// The app menus. Add to a scene with `.commands { ShellCommands(shell: shell) }`.
public struct ShellCommands: Commands {
    let shell: ShellModel
    public init(shell: ShellModel) { self.shell = shell }

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { shell.open(.settings) }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Launcher…") { shell.toggleLauncher() }.keyboardShortcut("k")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Pane") { if let id = shell.activePane { shell.closePane(id) } }
                .keyboardShortcut("w").disabled(shell.panes.isEmpty)
            Button("Close All Panes") { shell.closeAllPanes() }
                .keyboardShortcut("w", modifiers: [.command, .option]).disabled(shell.panes.isEmpty)
        }
        CommandGroup(replacing: .sidebar) {
            Button("Home") { shell.show(.home) }.keyboardShortcut("0")
            Button("Workspace") { shell.show(.workspace) }.keyboardShortcut("0", modifiers: [.command, .shift])
            Button(shell.focusedPane == nil ? "Focus Mode" : "Tile Panes") { shell.toggleFocusMode() }
                .keyboardShortcut("f", modifiers: [.command, .shift]).disabled(shell.panes.isEmpty)
            Button("Notifications") { shell.toggleBell() }.keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
            Button("Next Pane") { shell.cyclePane(1) }.keyboardShortcut("`").disabled(shell.panes.count < 2)
            Button("Previous Pane") { shell.cyclePane(-1) }.keyboardShortcut("`", modifiers: [.command, .shift])
                .disabled(shell.panes.count < 2)
            Button("Move Pane Left") { shell.nudgeActivePane(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [.control, .option]).disabled(shell.panes.count < 2)
            Button("Move Pane Right") { shell.nudgeActivePane(1) }
                .keyboardShortcut(.rightArrow, modifiers: [.control, .option]).disabled(shell.panes.count < 2)
        }
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .windowSize) {}
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { shell.open(.shortcuts) }.keyboardShortcut("/")
        }
    }
}
