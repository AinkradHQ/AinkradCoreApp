import SwiftUI

/// ⇧⌘A: the active pane's actions in the launcher.
extension ShellModel {
    public func toggleActions() {
        bellOpen = false
        launcherOpen = false
        actionsOpen.toggle()
    }

    /// Every action for the active pane (its tab menu, submenus flattened) and the workspace's, as launcher rows.
    public func paneActionEntries() -> [LauncherEntry] {
        guard let id = activePane ?? panes.first?.id, let spec = panes.first(where: { $0.id == id }) else { return [] }
        var out: [LauncherEntry] = []
        for item in paneMenus[id]?() ?? [] where item.enabled {
            if item.children.isEmpty {
                out.append(
                    LauncherEntry(
                        id: "pane.\(item.title)", title: item.title, sub: spec.title, symbol: item.symbol,
                        isAction: true,
                        run: item.run))
            } else {
                for c in item.children {
                    out.append(
                        LauncherEntry(
                            id: "pane.\(item.title).\(c.title)", title: "\(item.title): \(c.title)", sub: spec.title,
                            symbol: item.symbol, isAction: true, run: c.run))
                }
            }
        }
        let full = focusedPane == id
        out.append(
            LauncherEntry(
                id: "pane.focus", title: full ? "Tile All Panes" : "Full Pane", sub: spec.title,
                symbol: full ? "rectangle.split.2x1" : "arrow.up.left.and.arrow.down.right", isAction: true, tile: .view
            ) { [weak self] in
                self?.activePane = id
                self?.focusedPane = full ? nil : id
            })
        out.append(
            LauncherEntry(
                id: "pane.close", title: "Close Pane", sub: spec.title, symbol: "xmark", isAction: true, tile: .view
            ) {
                [weak self] in self?.dismissPane(id)
            })
        if panes.count > 1 {
            out.append(
                LauncherEntry(
                    id: "pane.others", title: "Close Other Panes", sub: spec.title, symbol: "xmark.square",
                    isAction: true
                ) { [weak self] in self?.closeOtherPanes(except: id) })
        }
        return out
    }

    /// The name a tab shows: the person's own, else the pane's sub (runner-1), else its title.
    public func tabName(_ spec: PaneSpec) -> String { tabNames[spec.id] ?? spec.sub ?? spec.title }

    /// Rename a tab; an empty name goes back to the pane's own.
    public func renameTab(_ id: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tabNames[id] = n.isEmpty ? nil : String(n.prefix(40))
        renamingTab = nil
    }
}
