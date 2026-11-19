import Foundation
import SwiftUI

/// One workspace: its own set of side-by-side apps (D-14). Apps are never stacked; one that does not fit opens a new workspace.
public struct Workspace: Identifiable {
    public let id: UUID
    var tree = TileTree()
    var active: String?
    var focused: String?
    init(id: UUID = UUID()) { self.id = id }
}

/// The one-time card that says why an app opened in a workspace of its own.
public struct SpaceNote: Equatable, Sendable {
    public let app: String
    public let fullScreen: Bool
    /// The 1-based number of the workspace to go back to with ⌃←.
    public let backTo: Int
}

extension ShellModel {
    static let spaceNoteKey = "ainkrad.core.workspace.noteHidden"

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

    /// Side by side at their minimum widths, with the gaps, inside the width the workspace has.
    func fits(_ spec: PaneSpec) -> Bool {
        guard workspaceWidth > 0 else { return true }
        let all = panes + [spec]
        let need = all.map(\.minWidth).reduce(0, +) + ShellMetrics.paneGap * CGFloat(all.count - 1)
        return need <= workspaceWidth
    }

    /// A full-screen app gets a workspace alone and nothing joins it; any other app joins the current one while it fits.
    func needsNewSpace(for spec: PaneSpec) -> Bool {
        guard !panes.isEmpty else { return false }
        return spec.fullScreenOnly || panes.contains { $0.fullScreenOnly } || !fits(spec)
    }

    /// Makes a workspace for `spec` and goes there. No animation of its own: callers already animate.
    func openSpace(for spec: PaneSpec) {
        let back = spaceIndex + 1
        enterSpace(addSpace())
        if !defaults.bool(forKey: Self.spaceNoteKey) {
            spaceNote = SpaceNote(app: spec.tab ?? spec.title, fullScreen: spec.fullScreenOnly, backTo: back)
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
            spaceNote = nil
        }
    }

    /// ⌃← / ⌃→, round the ring.
    public func moveSpace(_ step: Int) {
        guard spaces.count > 1 else { return }
        switchSpace(to: (spaceIndex + step + spaces.count) % spaces.count)
    }

    /// A new, empty workspace: it shows the empty card and goes Home after three seconds unless you open an app or stay.
    public func newSpace() {
        animate {
            enterSpace(addSpace())
            surface = .workspace
            spaceNote = nil
        }
    }

    /// The empty workspace's countdown ran out: it closes (when another exists) and the app goes Home.
    public func closeEmptySpace() {
        guard surface == .workspace, panes.isEmpty else { return }
        animate {
            if spaces.count > 1, let k = spaces.firstIndex(where: { $0.id == currentSpace }) {
                spaces.remove(at: k)
                load(max(0, k - 1))
            }
            surface = .home
        }
    }

    public func dismissSpaceNote(forever: Bool) {
        if forever { defaults.set(true, forKey: Self.spaceNoteKey) }
        spaceNote = nil
    }

    /// ⌃↑: every workspace as a thumbnail.
    public func toggleSpaces() {
        guard spaces.count > 1 || !panes.isEmpty else { return }
        spacesOpen.toggle()
    }
}
