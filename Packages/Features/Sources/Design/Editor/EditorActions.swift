import Foundation

/// What the engine can hold today. Lane E adds `locked` and rotation to the model; until its engine is in the app these
/// stay off, and the commands say so instead of failing (`validate::applies` refuses unknown props).
enum EngineSupport {
    static let locked = false
    static let rotation = false
    static let lockWhy = "Locking layers arrives with the next engine update."
}

extension DesignEditor {
    func notify(_ words: String) { notice = words }

    /// Applies an arrange result: the ops (one undo step), then selects what it says. A reason is shown, nothing changes.
    @discardableResult
    func run(_ a: Arranged) -> Bool {
        if let why = a.why {
            notice = why
            return false
        }
        guard !a.ops.isEmpty, apply(a.ops) else { return false }
        if !a.select.isEmpty { selectMany(a.select) }
        return true
    }

    private func box(_ id: String) -> NodeBox? { NodeBox(node(of: id)) }

    // MARK: arrange

    func group() { run(Arrange.group(selection, layers: layers, box: { box($0) })) }
    func ungroup() { run(Arrange.ungroup(selection, layers: layers, box: { box($0) })) }

    func zOrder(_ move: Arrange.ZMove) {
        let ops = Arrange.zOrder(selection, move, layers: layers)
        if ops.isEmpty {
            notice = selection.isEmpty ? "Select a layer first." : nil
            return
        }
        apply(ops)
    }

    func selectAll() {
        selectMany(Arrange.selectAll(selection: selection, layers: layers, page: currentPage?.id))
    }

    /// ⇧A: auto layout on a frame; on anything else the layers are wrapped in a frame that has it.
    func addAutoLayout() {
        guard let id = selection.first, let l = layers[id] else { return notify("Select a frame or layers first.") }
        if selection.count == 1, l.isContainer, l.type != "page" {
            guard node(of: id)?.hasLayout != true else { return notify("“\(l.title)” already has auto layout.") }
            let boxes = layers.children(of: id).compactMap { box($0.id) }
            apply([EditOps.set(id, "layout", Arrange.layout(direction: Arrange.direction(boxes)))])
            return
        }
        let boxes = selection.compactMap { box($0) }
        let dir = Arrange.direction(boxes)
        run(
            Arrange.group(
                selection, layers: layers, box: { box($0) }, extra: ["layout": Arrange.layout(direction: dir)]))
    }

    /// ⇧⌘H: hide the selection, or show it when it is all hidden.
    func toggleHidden() {
        let list = selection.filter { layers[$0]?.type != "page" }
        guard !list.isEmpty else { return notify("Select a layer first.") }
        let hide = !list.allSatisfy { layers[$0]?.hidden == true }
        apply(list.map { EditOps.set($0, "visible", hide ? .bool(false) : nil) })
    }

    func toggleLock() {
        guard EngineSupport.locked else { return notify(EngineSupport.lockWhy) }
        let list = selection.filter { layers[$0]?.type != "page" }
        guard !list.isEmpty else { return notify("Select a layer first.") }
        let on = !list.allSatisfy { node(of: $0)?.props["locked"]?.bool == true }
        apply(list.map { EditOps.set($0, "locked", on ? .bool(true) : nil) })
    }

    // MARK: commands

    /// A key the canvas offered: true when an editor command took it.
    func handle(_ key: EditorKey) -> Bool {
        guard let c = EditorCommand.from(key) else { return false }
        return perform(c)
    }

    /// Runs a command; false when it does not apply here, so the key goes on (⏎ ends a pen path, for one).
    @discardableResult
    func perform(_ c: EditorCommand) -> Bool {
        guard attached else { return false }
        switch c {
        case .copy: return copy()
        case .cut:
            guard !selection.isEmpty else { return false }
            cut()
        case .paste: return paste()
        case .duplicate: return duplicate()
        case .group: group()
        case .ungroup: ungroup()
        case .bringForward: zOrder(.forward)
        case .sendBackward: zOrder(.backward)
        case .bringToFront: zOrder(.front)
        case .sendToBack: zOrder(.back)
        case .selectAll: selectAll()
        case .selectChildren:
            guard tool == CanvasTool.select.rawValue, let ids = Arrange.children(of: selection, layers: layers) else {
                return false
            }
            selectMany(ids)
        case .selectParent:
            guard tool == CanvasTool.select.rawValue, let ids = Arrange.parents(of: selection, layers: layers) else {
                return false
            }
            selectMany(ids)
        case .createComponent: createComponent()
        case .detachInstance: detachInstance()
        case .zoomIn: zoomStep(up: true)
        case .zoomOut: zoomStep(up: false)
        case .zoom100: backend?.zoom(to: 1)
        case .fitAll: backend?.fitAll()
        case .fitSelection: fitSelection()
        case .autoLayout: addAutoLayout()
        case .toggleHidden: toggleHidden()
        case .toggleLock: toggleLock()
        case .renameLayer:
            guard let id = selection.first, layers[id] != nil else { return false }
            renaming = id
        case .shortcuts: shortcutsOpen = true
        }
        return true
    }

    /// Whether a command has something to act on, for the toolbar menu's disabled rows (never for a key: the key just says why).
    func canPerform(_ c: EditorCommand) -> (ok: Bool, why: String) {
        let has = !selection.isEmpty
        switch c {
        case .copy, .cut, .duplicate, .group, .bringForward, .sendBackward, .bringToFront, .sendToBack, .toggleHidden,
            .renameLayer:
            return (has, "Select a layer first.")
        case .ungroup:
            return (selection.contains { layers[$0]?.type == "frame" }, "Select a frame or group first.")
        case .createComponent:
            return (selection.first.flatMap { layers[$0]?.type } == "frame", "Select a frame first.")
        case .detachInstance:
            return (selection.contains { layers[$0]?.type == "instance" }, "Select an instance first.")
        case .toggleLock: return (EngineSupport.locked && has, has ? EngineSupport.lockWhy : "Select a layer first.")
        case .autoLayout: return (has, "Select a frame or layers first.")
        default: return (true, "")
        }
    }
}
