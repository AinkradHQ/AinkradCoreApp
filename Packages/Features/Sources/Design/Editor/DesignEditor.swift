import Foundation
import Observation

/// What a person asks the AI about the open design (V7-02 answers it): the words and the ids selected when they asked.
struct AskRequest: Equatable, Sendable {
    let doc: String
    let text: String
    let selection: [String]
}

/// The editor chrome's state for one open design (V3-04): layers, selection, the inspected node, presence and versions. It
/// reads the canvas through `DesignEditBackend` and writes only edit ops, so the engine stays the one place a design changes
/// (every write is one undo step and goes to the Core as a normal local edit).
@MainActor @Observable
final class DesignEditor {
    let doc: String
    private(set) var layers = LayerTree([])
    private(set) var selection: [String] = []
    private(set) var node: EditorNode?
    private(set) var peers: [DesignPeer] = []
    private(set) var tokens: [DesignToken] = []
    /// A design system's own tokens with their values (the style guide), name order.
    private(set) var systemTokens: [SystemToken] = []
    /// A sentence when the engine refused the last write; cleared by the next change.
    var notice: String?
    /// The canvas cannot send an unsent edit to the Core: shown until the design is reopened (never a retry).
    private(set) var syncStuck = false
    /// The design has its first content (the Core's first snapshot arrived, or layers are listed): until then the canvas is blank.
    private(set) var loaded = false
    private(set) var syncConnected = true
    /// The canvas's engine no longer takes remote updates: edits go nowhere until the canvas is rebuilt (`reopen`).
    private(set) var syncHalted = false
    /// The Core could not be reached after a few tries.
    private(set) var syncUnreachable = false
    /// Images that gave up loading.
    private(set) var assetFailures = 0
    /// The canvas could not start (no Metal, a bad id).
    var canvasFailed = false
    /// Bumped by `reopen`: the stage rebuilds the canvas (a new engine) when it changes.
    private(set) var generation = 0
    /// A viewer: the canvas, layers and inspector show but never edit.
    var readOnly = false {
        didSet { backend?.setReadOnly(readOnly) }
    }
    /// The inspected node and the other selected nodes of its type (at most 64), for "Mixed" and per-field writes.
    private(set) var selectedNodes: [EditorNode] = []
    /// Counts selections made on the canvas (not in the panel): the layers panel scrolls to them.
    private(set) var revealStamp = 0
    @ObservationIgnored private var fromPanel = false
    @ObservationIgnored private var undoShown = false
    /// The AI is drawing: the layers panel does not chase the selection meanwhile.
    var revealPaused = false
    #if DEBUG
    /// Debug scenes: "halted" and "offline" show those states over a healthy canvas.
    var debugForce: Set<String> = []
    #endif
    static let haltedSentence = "This design stopped syncing — Reopen"
    static let readOnlySentence = "You can look at this design but not change it."
    static let stuckSentence = "This design stopped syncing — reopen it (unsent edits are lost)"
    var expanded: Set<String> = []
    var renaming: String?
    /// The layer being dragged (a drag carries only its id).
    var dragging: String?
    var versions: [DesignVersion] = []
    var versionsOpen = false
    var versionsNote: String?
    var versionsBusy = false
    var askText = ""
    /// Answers the Ask… field (V7-02). Nil: no AI is wired yet, and the field says so.
    @ObservationIgnored var ask: (@MainActor (AskRequest) async -> Bool)?
    @ObservationIgnored let service: (any DesignService)?
    /// Held strongly: the canvas hands over a fresh object and keeps none, so a weak hold dropped it at once and the
    /// chrome never saw the canvas (no layers, no selection). The object holds the canvas view weakly, so no cycle.
    private var backend: (any DesignEditBackend)?
    @ObservationIgnored private var pending = false
    /// What a brand-new design starts with (its page and a frame of the default canvas); written once, when the canvas is up
    /// and the design is still empty.
    @ObservationIgnored var starter: [[String: DJSON]]?
    @ObservationIgnored private var lastPresence = ""

    init(doc: String, service: (any DesignService)? = nil) {
        self.doc = doc
        self.service = service
    }

    // MARK: canvas

    /// Called by the app when the canvas is up (and with nil when it goes away).
    func attach(_ backend: (any DesignEditBackend)?) {
        self.backend = backend
        backend?.setReadOnly(readOnly)
        reload()
    }

    /// Rebuilds the canvas for this design: a new engine, a new socket, the Core's state again. Unsent edits are lost.
    func reopen() {
        backend = nil
        syncHalted = false
        syncStuck = false
        loaded = false
        canvasFailed = false
        generation += 1
        reload()
    }

    func retryAssets() { backend?.retryAssets() }

    func duplicateSelection() {
        guard !readOnly, !selection.isEmpty else { return }
        backend?.duplicate()
        reload()
    }

    var attached: Bool { backend != nil }

    /// The canvas tool (`CanvasTool` raw value), read on every change: drawing a shape returns it to select.
    private(set) var tool = 0
    func setTool(_ t: CanvasTool) {
        backend?.setTool(t.rawValue)
        tool = backend?.tool ?? 0
    }

    /// The screen an AI edit works on: the top-level frame (a frame or component right under a page) the selection is in.
    func targetFrame() -> DesignLayer? {
        var id = selection.first
        while let i = id, let l = layers[i] {
            if ["frame", "component"].contains(l.type), let p = l.parent, layers[p]?.type == "page" { return l }
            id = l.parent
        }
        return nil
    }

    /// The canvas camera now (not observed: the AI overlay reads it every display frame).
    func camera() -> CanvasCamera? { backend?.camera() }
    func fit(_ rect: CGRect) { backend?.fit(rect) }
    /// Presenting: clicks report the node under them; nil goes back to editing.
    func present(_ tap: (@MainActor (String?) -> Void)?) { backend?.present(tap) }

    /// Sets a token of this design system (nil removes it): one undo step, synced like any edit.
    @discardableResult
    func setToken(_ name: String, kind: String, day: DJSON?, night: DJSON?) -> Bool {
        let value: DJSON =
            day.map { d in .object(["kind": .string(kind), "day": d, "night": night ?? d]) } ?? .null
        return apply([["op": .string("token"), "name": .string(name), "value": value]])
    }

    /// Writes many tokens in one undo step (a starter set).
    @discardableResult
    func setTokens(_ list: [SystemToken]) -> Bool {
        apply(
            list.map {
                [
                    "op": .string("token"), "name": .string($0.name),
                    "value": .object(["kind": .string($0.kind), "day": $0.day, "night": $0.night]),
                ]
            })
    }

    /// One node as the engine has it now (not observed).
    func node(of id: String) -> EditorNode? { backend?.node(id).flatMap { EditorNode(json: $0) } }

    /// A picture of one frame (the composer's direction cards); nil until the engine lists it.
    func sketch(frame id: String) -> FrameSketch? {
        guard let b = backend else { return nil }
        // Reads the observed `layers`, so a card waiting for its frame redraws when the sync brings it.
        return FrameSketch.make(frame: id, layers: layers) { b.node($0).flatMap { EditorNode(json: $0) } }
    }

    /// The document or selection may have changed. Reads are coalesced to one per 60 ms: a drag or a remote burst must not
    /// re-list a large document on every event.
    func changed() {
        guard !pending else { return }
        pending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.pending = false
            self?.reload()
        }
    }

    func reload() {
        syncStuck = backend?.syncStuck ?? false
        syncHalted = backend?.syncHalted ?? false
        syncUnreachable = backend?.syncUnreachable ?? false
        assetFailures = backend?.assetFailures ?? 0
        let undoRefused = backend?.lastUndoTooLarge ?? false
        if undoRefused, !undoShown { notice = "That undo is too large to send. Nothing was changed." }
        undoShown = undoRefused
        var conn = backend?.syncConnected ?? true
        #if DEBUG
        if debugForce.contains("halted") { syncHalted = true }
        if debugForce.contains("offline") { conn = false }
        #endif
        if conn != syncConnected { syncConnected = conn }
        if let d = backend?.docTokens(), let list = try? JSONDecoder().decode([SystemToken].self, from: d),
            list != systemTokens
        {
            systemTokens = list
        }
        if let t = backend?.tool, t != tool { tool = t }
        guard let b = backend else {
            layers = LayerTree([])
            loaded = false
            selection = []
            node = nil
            peers = []
            return
        }
        let list = b.tree().flatMap { try? JSONDecoder().decode([DesignLayer].self, from: $0) } ?? []
        let next = LayerTree(list)
        // The first time a design shows its layers, open its pages and their frames, so what is on the canvas is listed.
        if layers.layers.isEmpty, !next.layers.isEmpty {
            for p in next.children(of: nil) {
                expanded.insert(p.id)
                for f in next.children(of: p.id) where f.isContainer { expanded.insert(f.id) }
            }
        }
        if next != layers { layers = next }
        let isLoaded = b.loaded || !next.layers.isEmpty
        if isLoaded != loaded { loaded = isLoaded }
        // A new design's page and starter frame go in only once the Core's state is here: before it, "empty" means "not
        // loaded yet", and writing then made a second page.
        if loaded, let ops = starter, next.layers.isEmpty, !readOnly {
            starter = nil
            apply(ops)
            return
        }
        let sel = b.selection()
        if sel != selection {
            selection = sel
            for id in sel { expanded.formUnion(next.ancestors(of: id)) }  // reveal what the canvas picked
            if !fromPanel, !sel.isEmpty { revealStamp &+= 1 }
            publishPresence()
        }
        fromPanel = false
        node = sel.first.flatMap { b.node($0) }.flatMap { EditorNode(json: $0) }
        selectedNodes =
            node.map { n in
                [n]
                    + sel.dropFirst().prefix(63).compactMap { id in
                        b.node(id).flatMap { EditorNode(json: $0) }.flatMap { $0.type == n.type ? $0 : nil }
                    }
            } ?? []
        peers = DesignPeer.decode(b.peers())
        // Linked tokens follow the system doc: read again (cheap, a short list) so an edit there shows here.
        let fresh = b.tokens().flatMap { try? JSONDecoder().decode([DesignToken].self, from: $0) } ?? []
        if fresh != tokens { tokens = fresh }
    }

    /// This device's name, as the Mac calls it (the Core, not the client, says who is who to the others).
    static let deviceName = Host.current().localizedName ?? "This Mac"

    private func publishPresence() {
        let o: [String: DJSON] = [
            "label": .string(Self.deviceName), "selection": .array(selection.prefix(64).map { .string($0) }),
        ]
        guard let d = try? JSONEncoder().encode(DJSON.object(o)), let s = String(data: d, encoding: .utf8),
            s != lastPresence
        else { return }
        lastPresence = s
        backend?.setPresence(s)
    }

    // MARK: writes

    /// Applies ops as one undo step. A refusal leaves the document as it was and says so in `notice`.
    @discardableResult func apply(_ ops: [[String: DJSON]]?) -> Bool {
        guard let b = backend, let ops, let json = EditOps.json(ops) else { return false }
        if readOnly {
            notice = Self.readOnlySentence
            return false
        }
        if syncHalted {
            notice = Self.haltedSentence
            return false
        }
        if b.edit(json) {
            notice = nil
            reload()
            return true
        }
        syncStuck = b.syncStuck
        notice =
            b.lastEditTooLarge && !syncStuck
            ? "That change is too large to send at once. Nothing was changed."
            : "The design refused that change. Nothing was changed."
        return false
    }

    /// Selects a layer. False when the canvas does not have it (yet): `quiet` for a caller that waits for the sync.
    @discardableResult
    func select(_ id: String, quiet: Bool = false) -> Bool {
        guard let b = backend else { return false }
        fromPanel = true
        if b.select([id]) {
            reload()
            return true
        }
        if !quiet { notice = "That layer is not on the canvas yet. Try again in a moment." }
        return false
    }

    /// Selects several layers (⌘ and ⇧-click in the panel).
    @discardableResult
    func selectMany(_ ids: [String]) -> Bool {
        guard let b = backend else { return false }
        fromPanel = true
        if b.select(ids) {
            reload()
            return true
        }
        return false
    }

    /// Deletes every selected layer (never a page; a layer inside another selected one goes with it).
    func deleteSelected() {
        let ids = Set(selection.filter { layers[$0].map { $0.type != "page" } ?? false })
        let tops = ids.filter { id in !layers.ancestors(of: id).contains { ids.contains($0) } }
        apply(tops.sorted().map { EditOps.delete($0) })
    }

    /// Selects the parent of the first selected layer (never a page).
    func selectParent() {
        guard let id = selection.first, let p = layers[id]?.parent, layers[p]?.type != "page" else { return }
        select(p, quiet: true)
    }

    func rename(_ id: String, to name: String) {
        renaming = nil
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard let l = layers[id], n != l.name else { return }
        apply([EditOps.name(id, n)])
    }

    /// Hide or show (`visible: false`; showing removes the prop).
    func setHidden(_ id: String, _ hidden: Bool) { apply([EditOps.set(id, "visible", hidden ? .bool(false) : nil)]) }

    /// Hide or show several layers in one undo step.
    func setHidden(_ ids: [String], _ hidden: Bool) {
        apply(ids.map { EditOps.set($0, "visible", hidden ? .bool(false) : nil) })
    }

    func delete(_ id: String) { if layers[id]?.type != "page" { apply([EditOps.delete(id)]) } }

    func drop(_ id: String, _ drop: LayerDrop) {
        dragging = nil
        apply(layers.moveOps(id, drop))
    }

    func step(_ id: String, up: Bool) { apply(layers.step(id, up: up)) }

    /// The inspector's write: `key` to `value` (nil removes it) on every selected node that is the inspected one's type.
    func set(_ key: String, _ value: DJSON?) {
        guard let n = node else { return }
        let same = selection.filter { layers[$0]?.type == n.type || $0 == n.id }
        apply(same.map { EditOps.set($0, key, value) })
    }

    /// The write for a prop made of several fields (fill, type, layout, stroke, shadow): `value` gets each selected node, so
    /// only the one field a person changed is written and every other field of that node stays its own.
    func setEach(_ key: String, _ value: (EditorNode) -> DJSON?) {
        apply(selectedNodes.map { EditOps.set($0.id, key, value($0)) })
    }

    /// True when the selected nodes of the inspected type disagree on a value (the inspector says "Mixed").
    func mixed(_ value: (EditorNode) -> DJSON?) -> Bool {
        let all = selectedNodes.map(value)
        guard let first = all.first else { return false }
        return all.dropFirst().contains { $0 != first }
    }

    // MARK: align

    private func boxes() -> [EditorAlign.Box] {
        selection.prefix(200).compactMap { id in
            guard let n = node(of: id) else { return nil }
            return .init(
                id: id, x: n.props["x"]?.double ?? 0, y: n.props["y"]?.double ?? 0, w: n.props["w"]?.double ?? 0,
                h: n.props["h"]?.double ?? 0)
        }
    }

    /// Several layers: to the selection's bounds, each by its own size. One layer: to its parent.
    func align(_ edge: EditorAlign.Edge) {
        let list = boxes()
        var within: (w: Double, h: Double)?
        if list.count == 1 {
            guard let p = node.flatMap({ $0.parent }).flatMap({ node(of: $0) }), let w = p.props["w"]?.double,
                let h = p.props["h"]?.double
            else { return }
            within = (w, h)
        }
        write(EditorAlign.align(list, edge, in: within))
    }

    func distribute(horizontal: Bool) { write(EditorAlign.distribute(boxes(), horizontal: horizontal)) }

    private func write(_ moves: [(String, String, Double)]) {
        apply(moves.map { EditOps.set($0.0, $0.1, .number($0.2)) })
    }

    func undo() {
        guard !readOnly else { return }
        backend?.undo()
        reload()
    }
    func redo() {
        guard !readOnly else { return }
        backend?.redo()
        reload()
    }
    func fitSelection() { backend?.fitSelection() }

    // MARK: Ask…

    var canAsk: Bool { ask != nil }

    func submitAsk() async {
        let t = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let ask else { return }
        askText = ""
        if await ask(AskRequest(doc: doc, text: String(t.prefix(4000)), selection: selection)) == false { askText = t }
    }

    // MARK: versions

    func loadVersions() async {
        guard let service else {
            versionsNote = "Versions need a connection to the Core."
            return
        }
        versionsBusy = true
        defer { versionsBusy = false }
        do {
            versions = try await service.versions(doc: doc)
            versionsNote =
                versions.isEmpty
                ? "No versions yet. The Core saves one before each AI turn and every 10 minutes of edits." : nil
        } catch let e as DesignFailure { versionsNote = e.sentence } catch { versionsNote = "Unable to load versions." }
    }

    func saveVersion(named name: String) async {
        guard let service else { return }
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !n.isEmpty else { return }
        versionsBusy = true
        defer { versionsBusy = false }
        do {
            _ = try await service.saveVersion(doc: doc, name: n)
            await loadVersions()
        } catch let e as DesignFailure { versionsNote = e.sentence } catch {
            versionsNote = "Unable to save the version."
        }
    }

    /// Rewrites the live design to the version in one Core transaction; everyone sees normal edits, and Undo works.
    func restore(_ v: DesignVersion) async {
        guard let service else { return }
        versionsBusy = true
        defer { versionsBusy = false }
        do {
            try await service.restoreVersion(doc: doc, id: v.id)
            versionsOpen = false
            reload()
        } catch let e as DesignFailure { versionsNote = e.sentence } catch {
            versionsNote = "Unable to restore the version."
        }
    }
}
