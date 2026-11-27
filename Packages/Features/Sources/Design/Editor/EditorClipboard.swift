import AppKit
import Foundation

/// The pasteboard side of copy and paste. The engine writes and reads the clipboard JSON (`de_copy` / `de_paste`, format
/// `ainkrad-design/1`, new ids on every paste, other designs welcome); the app only moves it to and from `NSPasteboard`.
enum EditorClipboard {
    static let tooBig = "That is too many layers to copy at once. Try fewer."
    static let format = "ainkrad-design/1"
    static let pasteboardType = NSPasteboard.PasteboardType("com.ainkrad.design.nodes")

    /// Just enough of the JSON to tell ours from other text, and to place it: its marker and the types of its layers.
    private struct Head: Decodable {
        struct Node: Decodable { let type: String }
        let format: String
        let nodes: [Node]
    }

    /// The types of the copied top-level layers, or nil when the JSON is not our clipboard.
    static func types(_ data: Data) -> [String]? {
        guard let h = try? JSONDecoder().decode(Head.self, from: data), h.format == format, !h.nodes.isEmpty else {
            return nil
        }
        return h.nodes.map(\.type)
    }

    static func write(_ json: Data, to pb: NSPasteboard = .general) {
        pb.clearContents()
        pb.setData(json, forType: pasteboardType)
        if let s = String(data: json, encoding: .utf8) { pb.setString(s, forType: .string) }
    }

    enum Content: Equatable {
        case nodes(Data)
        case text(String)
    }

    /// Our layers (on their own type, or as JSON text), else plain text; nil when the pasteboard holds neither.
    static func read(from pb: NSPasteboard = .general) -> Content? {
        if let d = pb.data(forType: pasteboardType), types(d) != nil { return .nodes(d) }
        guard let s = pb.string(forType: .string), !s.isEmpty else { return nil }
        if types(Data(s.utf8)) != nil { return .nodes(Data(s.utf8)) }
        return .text(String(s.prefix(10_000)))
    }
}

// MARK: editor

extension DesignEditor {
    /// The layer a paste lands in: the selected container, or the selected layer's parent; nothing selected: the page for
    /// frames, the first frame on the page for anything else.
    private func pasteParent(framesOnly: Bool) -> DesignLayer? {
        if let pick = selection.first.flatMap({ layers[$0] }) {
            let c = pick.isContainer ? pick : pick.parent.flatMap { layers[$0] }
            if let c, c.type != "page" { return c }
        }
        let page = currentPage
        if framesOnly { return page }
        return page.flatMap { p in layers.children(of: p.id).first { $0.type == "frame" } } ?? page
    }

    /// The page being shown.
    var currentPage: DesignLayer? {
        let p = pages
        return p.indices.contains(pageIndex) ? p[pageIndex] : p.first
    }

    /// Every page of the design, in order (the engine's page number is a place in this list).
    var pages: [DesignLayer] { layers.children(of: nil).filter { $0.type == "page" } }

    /// Copies the selected layers (and what is inside them) to the pasteboard. False when nothing could be copied.
    @discardableResult
    func copy() -> Bool {
        guard attached, !selection.isEmpty else { return false }
        guard let json = backend?.copy() else {
            notice =
                selection.allSatisfy({ layers[$0]?.type == "page" })
                ? "A page cannot be copied." : EditorClipboard.tooBig
            return false
        }
        EditorClipboard.write(json)
        notice = nil
        return true
    }

    func cut() {
        guard copy() else { return }
        let roots = selection.filter { layers[$0]?.type != "page" }
        apply(roots.map { EditOps.delete($0) })
    }

    /// Pastes what the pasteboard holds: copied layers (new ids, one undo step), or text as a text layer.
    @discardableResult
    func paste() -> Bool {
        guard attached, let content = EditorClipboard.read() else { return false }
        switch content {
        case .nodes(let json): return paste(json)
        case .text(let s): return pasteText(s)
        }
    }

    /// Copied layers go where the selection is. Screens land on the page, where the canvas is looking; anything else goes
    /// into the selected frame (or the first one) in place.
    @discardableResult
    func paste(_ json: Data) -> Bool {
        let framesOnly = (EditorClipboard.types(json) ?? []).allSatisfy { ["frame", "component"].contains($0) }
        guard let parent = pasteParent(framesOnly: framesOnly) else {
            notice = "There is nowhere to paste yet. Draw a frame first."
            return false
        }
        let onPage = parent.type == "page"
        guard backend?.paste(json, parent: onPage ? nil : parent.id, atCenter: onPage) == true else {
            notice = "That cannot be pasted here. Select a frame and try again."
            return false
        }
        notice = nil
        reload()
        return true
    }

    private func pasteText(_ s: String) -> Bool {
        guard let parent = pasteParent(framesOnly: false), parent.type != "page" else {
            notice = "Select a frame to paste text into."
            return false
        }
        let siblings = layers.children(of: parent.id)
        guard let order = FractionalOrder.between(siblings.last?.order, nil) else { return false }
        let body = InsertPreset.texts[1]
        var props = body.props
        let step = Double(siblings.count % 10) * 24
        props["x"] = .number(40 + step)
        props["y"] = .number(40 + step)
        props["w"] = .number(body.w)
        props["h"] = .number(body.h)
        let id = DesignOptions.nodeID()
        let words = String(s.prefix(2000))
        guard
            apply([
                [
                    "op": .string("add"), "id": .string(id), "type": .string("text"), "parent": .string(parent.id),
                    "order": .string(order), "name": .string(String(words.prefix(30))),
                    "props": .object(props), "text": .string(words),
                ]
            ])
        else { return false }
        selectMany([id])
        return true
    }

    /// A copy of each selected layer beside it; the copies become the selection. One undo step.
    @discardableResult
    func duplicate() -> Bool {
        guard attached, !selection.isEmpty else { return false }
        guard backend?.duplicate() == true else {
            notice = "Select a layer to duplicate. A page cannot be duplicated."
            return false
        }
        notice = nil
        reload()
        return true
    }

    /// Selects several layers at once (false when the canvas does not have one of them yet).
    @discardableResult
    func selectMany(_ ids: [String]) -> Bool {
        guard let b = backend else { return false }
        fromPanel = true  // a pick made in the panel does not scroll the panel
        let ok = b.select(ids)
        reload()
        return ok
    }
}
