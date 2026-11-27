import CoreUI
import SwiftUI

extension DesignEditor {
    /// Shows page `i` (a place in `pages`), framed, with nothing selected.
    func showPage(_ i: Int) {
        guard pages.indices.contains(i) else { return }
        pageIndex = i
        _ = backend?.select([])
        backend?.setPage(i)
        reload()
    }

    /// A new page after the last, named "Page N", shown at once. One undo step.
    func addPage() {
        let list = pages
        guard attached, let order = FractionalOrder.between(list.last?.order, nil) else { return }
        let id = DesignOptions.nodeID()
        let op: [String: DJSON] = [
            "op": .string("add"), "id": .string(id), "type": .string("page"), "parent": .null, "order": .string(order),
            "name": .string("Page \(list.count + 1)"),
        ]
        guard apply([op]) else { return }
        showPage(pages.count - 1)
    }

    /// Renames in the layers list, where the page's row is.
    func renamePage(_ id: String) {
        expanded.insert(id)
        renaming = id
    }

    /// Removes a page and everything on it (Undo brings it back); the last page cannot go.
    func deletePage(_ id: String) {
        let list = pages
        guard list.count > 1, let at = list.firstIndex(where: { $0.id == id }) else {
            notice = "A design needs at least one page."
            return
        }
        guard apply([EditOps.delete(id)]) else { return }
        showPage(min(pageIndex > at ? pageIndex - 1 : pageIndex, pages.count - 1))
    }
}

/// The page switcher at the head of the layers panel: the page shown, and a menu to pick, add, rename or delete one.
struct PageSwitcher: View {
    @Bindable var editor: DesignEditor

    var body: some View {
        let pages = editor.pages
        let current = editor.currentPage
        Menu {
            ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                Button {
                    editor.showPage(i)
                } label: {
                    if p.id == current?.id {
                        Label(p.title, systemImage: "checkmark")
                    } else {
                        Text(p.title)
                    }
                }
            }
            Divider()
            Button("Add a page") { editor.addPage() }
            if let c = current {
                Button("Rename “\(c.title)”") { editor.renamePage(c.id) }
                Button("Delete “\(c.title)”") { editor.deletePage(c.id) }
                    .disabled(pages.count < 2)
            }
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "doc").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                Text(current?.title ?? "No page").lineLimit(1)
                Spacer(minLength: 0)
                Text(pages.count > 1 ? "\(pages.count) pages" : "").foregroundStyle(GlassInk.secondary)
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary)
            }
            .padding(.horizontal, Space.s2)
            .frame(maxWidth: .infinity, minHeight: MacSize.controlMd + 2)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Pages: switch, add, rename or delete. Delete can be undone with ⌘Z.")
        .accessibilityLabel("Page")
        .accessibilityIdentifier("design-pages")
    }
}
