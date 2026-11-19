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
    /// A sentence when the engine refused the last write; cleared by the next change.
    var notice: String?
    /// The canvas cannot send an unsent edit to the Core: shown until the design is reopened (never a retry).
    private(set) var syncStuck = false
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
    @ObservationIgnored private let service: (any DesignService)?
    @ObservationIgnored private weak var backend: (any DesignEditBackend)?
    @ObservationIgnored private var pending = false
    @ObservationIgnored private var lastPresence = ""

    init(doc: String, service: (any DesignService)? = nil) {
        self.doc = doc
        self.service = service
    }

    // MARK: canvas

    /// Called by the app when the canvas is up (and with nil when it goes away).
    func attach(_ backend: (any DesignEditBackend)?) {
        self.backend = backend
        reload()
    }

    var attached: Bool { backend != nil }

    /// A picture of one frame (the composer's direction cards); nil until the engine lists it.
    func sketch(frame id: String) -> FrameSketch? {
        guard let b = backend else { return nil }
        let list = b.tree().flatMap { try? JSONDecoder().decode([DesignLayer].self, from: $0) } ?? []
        return FrameSketch.make(frame: id, layers: LayerTree(list)) { b.node($0).flatMap { EditorNode(json: $0) } }
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
        guard let b = backend else {
            layers = LayerTree([])
            selection = []
            node = nil
            peers = []
            return
        }
        let list = b.tree().flatMap { try? JSONDecoder().decode([DesignLayer].self, from: $0) } ?? []
        let next = LayerTree(list)
        if next != layers { layers = next }
        let sel = b.selection()
        if sel != selection {
            selection = sel
            for id in sel { expanded.formUnion(next.ancestors(of: id)) }  // reveal what the canvas picked
            publishPresence()
        }
        node = sel.first.flatMap { b.node($0) }.flatMap { EditorNode(json: $0) }
        peers = DesignPeer.decode(b.peers())
        if tokens.isEmpty {
            tokens = b.tokens().flatMap { try? JSONDecoder().decode([DesignToken].self, from: $0) } ?? []
        }
    }

    private func publishPresence() {
        let o: [String: DJSON] = [
            "label": .string("You"), "selection": .array(selection.prefix(64).map { .string($0) }),
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

    func select(_ id: String) {
        guard let b = backend else { return }
        if b.select([id]) {
            reload()
        } else {
            notice = "This canvas cannot select from the layers yet. Click it on the canvas."
        }
    }

    func rename(_ id: String, to name: String) {
        renaming = nil
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard let l = layers[id], n != l.name else { return }
        apply([EditOps.name(id, n)])
    }

    /// Hide or show (`visible: false`; showing removes the prop).
    func setHidden(_ id: String, _ hidden: Bool) { apply([EditOps.set(id, "visible", hidden ? .bool(false) : nil)]) }

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

    func undo() {
        backend?.undo()
        reload()
    }
    func redo() {
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
