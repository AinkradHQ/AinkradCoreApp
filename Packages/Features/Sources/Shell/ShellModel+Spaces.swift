import Foundation
import SwiftUI

/// One workspace: its own tiling of apps. A new app joins while every pane keeps its minimum (`place`); otherwise it opens a new one.
public struct Workspace: Identifiable {
    public let id: UUID
    var tree = TileTree()
    var active: String?
    var focused: String?
    init(id: UUID = UUID()) { self.id = id }
}

extension ShellModel {
    /// 0-based place of the workspace on screen.
    public var spaceIndex: Int { spaces.firstIndex { $0.id == currentSpace } ?? 0 }

    /// How many workspaces away from this one a pane's workspace is (0 here), for sliding the others off to the side.
    func spaceOffset(of pane: String) -> Int {
        guard let home = paneSpace[pane], let i = spaces.firstIndex(where: { $0.id == home }) else { return 0 }
        return i - spaceIndex
    }

    /// The apps of a workspace by index, for the switcher thumbnails.
    func paneCount(inSpace index: Int) -> Int {
        guard spaces.indices.contains(index) else { return 0 }
        let id = spaces[index].id
        return allPanes.filter { paneSpace[$0.id] == id }.count
    }

    /// The one placement rule every way of opening an app goes through (launcher, top bar, keys, links, notifications, ⇧⌘T,
    /// ⌘↵): `spec` joins the current workspace when the tiling can give every pane, old and new, its minimum width and height
    /// (side by side first, then stacked under the roomiest pane); only when it cannot, or a full-screen app is involved, it
    /// opens a workspace of its own, which becomes the current one. `spec` must not be placed yet.
    func place(_ spec: PaneSpec) {
        if !panes.isEmpty {
            let mins = Dictionary((panes + [spec]).map { ($0.id, CGSize(width: $0.minWidth, height: $0.minHeight)) }) {
                a, _ in a
            }
            let area = CGSize(width: workspaceWidth, height: workspaceHeight)
            let joined =
                spec.fullScreenOnly || panes.contains { $0.fullScreenOnly }
                ? nil
                : tree.placing(spec.id, in: area, gap: ShellMetrics.paneGap) {
                    mins[$0] ?? CGSize(width: ShellMetrics.paneMinWidth, height: ShellMetrics.paneMinHeight)
                }
            if let joined {
                tree = joined
            } else {
                openSpace(for: spec)
                tree.open(spec.id)
            }
        } else {
            tree.open(spec.id)
        }
        paneSpace[spec.id] = currentSpace
        // A workspace in focus mode stays in it, with the new app in front (a new workspace loads unfocused).
        if focusedPane != nil { focusedPane = spec.id }
        syncOrder()
    }

    /// Makes a workspace for `spec` and goes there. No animation of its own: callers already animate.
    func openSpace(for spec: PaneSpec) {
        enterSpace(addSpace())
    }

    /// ⌘↵ on an app that is open in another workspace: it moves here, beside the current app, or into a new workspace when it
    /// does not fit (the same rule as opening it new).
    func bringHere(_ id: String) {
        guard let home = paneSpace[id], home != currentSpace, let spec = allPanes.first(where: { $0.id == id }),
            let k = spaces.firstIndex(where: { $0.id == home })
        else { return }
        spaces[k].tree.remove(id)
        if spaces[k].active == id { spaces[k].active = spaces[k].tree.leaves.first }
        if spaces[k].focused == id { spaces[k].focused = nil }
        if spaces[k].tree.leaves.isEmpty { spaces.remove(at: k) }
        paneSpace[id] = nil
        place(spec)
    }

    /// A workspace's apps in the reading order of its tiling, for its group in the tab strip.
    func panes(inSpace index: Int) -> [PaneSpec] {
        guard spaces.indices.contains(index) else { return [] }
        return spaceTree(index).leaves.compactMap { id in allPanes.first { $0.id == id } }
    }

    /// A click on an app in another workspace's group: that workspace comes up with the app picked.
    public func goTo(_ id: String) {
        guard let home = paneSpace[id], let i = spaces.firstIndex(where: { $0.id == home }) else { return }
        switchSpace(to: i)
        animate {
            activePane = id
            if focusedPane != nil { focusedPane = id }
        }
    }

    /// Adds an empty workspace after the current one.
    func addSpace() -> UUID {
        let w = Workspace()
        spaces.insert(w, at: min(spaceIndex + 1, spaces.count))
        return w.id
    }

    /// Goes to a workspace: the current one is saved and the target's panes become the live ones.
    func enterSpace(_ id: UUID) {
        guard id != currentSpace, let to = spaces.firstIndex(where: { $0.id == id }) else { return }
        let leaving = currentSpace
        let wasEmpty = !paneSpace.values.contains(leaving)
        if let from = spaces.firstIndex(where: { $0.id == leaving }) {
            spaces[from].tree = tree
            spaces[from].active = activePane
            spaces[from].focused = focusedPane
        }
        load(to)
        // An empty workspace left behind is not kept.
        if wasEmpty, spaces.count > 1 { spaces.removeAll { $0.id == leaving } }
    }

    private func load(_ k: Int) {
        currentSpace = spaces[k].id
        tree = spaces[k].tree
        activePane = spaces[k].active
        focusedPane = spaces[k].focused
    }

    /// ⌃1–9.
    public func switchSpace(to index: Int) {
        guard spaces.indices.contains(index) else { return }
        animate {
            enterSpace(spaces[index].id)
            surface = .workspace
        }
    }

    /// ⌃← / ⌃→, round the ring.
    public func moveSpace(_ step: Int) {
        guard spaces.count > 1 else { return }
        switchSpace(to: (spaceIndex + step + spaces.count) % spaces.count)
    }

    /// A new, empty workspace (⌃N): it waits for an app; leaving it empty drops it.
    public func newSpace() {
        animate {
            enterSpace(addSpace())
            surface = .workspace
            overviewOpen = false
        }
    }

    /// The current workspace lost its last app: it closes at once and its neighbour comes up; with none left, Home does.
    /// No animation of its own: callers already animate.
    func closeEmptySpace() {
        guard panes.isEmpty else { return }
        if spaces.count > 1, let k = spaces.firstIndex(where: { $0.id == currentSpace }) {
            spaces.remove(at: k)
            load(max(0, k - 1))
        } else {
            surface = .home
        }
    }

    /// ⌃↑ / ⇧⌘O: the overview, every workspace as a tile.
    public func toggleSpaces() { overviewOpen.toggle() }

    /// A workspace's tiling, for its overview tile (the current one's lives in `tree`).
    func spaceTree(_ index: Int) -> TileTree { spaces[index].id == currentSpace ? tree : spaces[index].tree }
}
