import CoreUI
import Observation
import SwiftUI

/// The Design AI (E11-4, D-29), shown as the AI panel over the canvas (`DesignAIPanel`). Two modes:
/// - New: describe a screen; an AI session draws one design or three directions as frames on the canvas, you pick one.
/// - Edit: with a frame selected (or anything inside one), describe a change; the AI redraws that screen with the change and
///   the redrawn frame takes the old one's place, name and position, as one undoable canvas edit.
/// The Core does the drawing (`POST /docs/{doc}/compose`); this polls it. The Core has no edit mode yet, so an edit sends the
/// screen's contents in words with the change (`EditPrompt`).
@MainActor @Observable
final class DesignComposer {
    enum Phase: Equatable {
        case prompt, drawing, directions
        /// An edit landed (or the one design was kept): the panel says so, with Undo.
        case done(String)
        case failed(String)
    }

    /// The frame an edit redraws.
    struct Target: Equatable {
        let id: String
        let name: String
    }

    let doc: String
    var prompt: String
    /// One design: asks the Core for one (`count: 1`). A Core from before that draws three, and the best match is kept.
    var single = true
    /// Edit this frame, or nil for a new screen.
    var target: Target?
    private(set) var phase = Phase.prompt
    private(set) var state: ComposeState?
    private(set) var busy = false
    /// When the current drawing started, for the panel's stages and timer.
    private(set) var startedAt: Date?
    /// While drawing: the document rects the canvas overlay animates (the frame being redrawn, or where new ones land).
    private(set) var busyRects: [CGRect] = []
    @ObservationIgnored private weak var model: DesignModel?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var originalText = ""

    init(model: DesignModel, doc: String, prompt: String = "", target: Target? = nil) {
        self.model = model
        self.doc = doc
        self.prompt = prompt
        self.target = target
    }

    var trimmed: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    var editing: Bool { target != nil }
    /// What the Core is asked: the words, or for an edit the screen in words with the change.
    var request: String {
        guard let target, let editor = model?.editors[doc] else { return trimmed }
        return EditPrompt.make(
            change: trimmed, screen: target.name, size: screen, elements: EditPrompt.elements(of: target.id, in: editor)
        )
    }
    var canDraw: Bool { !trimmed.isEmpty && trimmed.count <= 600 && !busy }
    /// The screen to draw: the edited frame's size, else the default canvas (Settings, Design, Options).
    var screen: CGSize {
        if let target, let editor = model?.editors[doc], let r = Self.rect(of: target.id, in: editor) { return r.size }
        let s = DesignOptions.canvas.size
        return CGSize(width: s.w, height: s.h)
    }
    /// How many frames the panel waits for.
    var expected: Int { editing || single ? 1 : 3 }

    func draw() {
        guard canDraw, let service = model?.service else { return }
        busy = true
        let text = request
        if originalText.isEmpty { originalText = trimmed }
        task?.cancel()
        startedAt = Date()
        if let editor = model?.editors[doc] {
            busyRects =
                target.flatMap { Self.rect(of: $0.id, in: editor) }.map { [$0] }
                ?? Self.landing(count: expected, size: screen, in: editor)
            // Show the canvas where the work happens.
            if let all = busyRects.first.map({ busyRects.dropFirst().reduce($0) { $0.union($1) } }) { editor.fit(all) }
        }
        withAnimation(Motion.out(Motion.ui)) { phase = .drawing }
        task = Task { [weak self] in
            guard let self else { return }
            defer { busy = false }
            do {
                var s = try await service.compose(
                    doc: doc, prompt: String(text.prefix(1000)), count: expected, size: screen)
                state = s
                busy = false
                // ponytail: a 1.2 s poll; the Core finishes the drawing on the read that finds the AI done.
                while s.phase == .drawing || s.phase == .applying {
                    try await Task.sleep(for: .milliseconds(1200))
                    s = try await service.composeState(doc: doc, id: s.id)
                    state = s
                }
                guard s.phase == .done, let best = s.directions.first else {
                    withAnimation(Motion.out(Motion.ui)) { phase = .failed(Self.sentence(s.reason)) }
                    return
                }
                if let target {
                    await replace(target, with: best, all: s.directions)
                } else if single {
                    await keep(best, all: s.directions)
                } else {
                    withAnimation(Motion.out(Motion.ui)) { phase = .directions }
                }
            } catch is CancellationError {
                return
            } catch {
                withAnimation(Motion.out(Motion.ui)) { phase = .failed(model?.words(error) ?? "That did not work.") }
            }
        }
    }

    #if DEBUG
    /// Snapshots only: shows a phase without a Core.
    func debugShow(_ s: ComposeState?, phase p: Phase) {
        state = s
        startedAt = Date().addingTimeInterval(-7)
        if p == .drawing, let editor = model?.editors[doc] {
            busyRects =
                target.flatMap { Self.rect(of: $0.id, in: editor) }.map { [$0] }
                ?? Self.landing(count: expected, size: screen, in: editor)
        }
        phase = p
    }
    #endif

    /// Stop watching, and stop the AI session too.
    func stop() {
        task?.cancel()
        let session = state?.session
        state = nil
        withAnimation(Motion.out(Motion.ui)) { phase = .prompt }
        if let session, let service = model?.service { Task { try? await service.cancelCompose(session: session) } }
    }

    func again() {
        state = nil
        draw()
    }

    /// Back to the prompt with a refine of one direction written for the person to adjust.
    func refine(_ d: ComposeState.Direction) {
        prompt = "Like \(d.name) (\(d.summary)), but "
        withAnimation(Motion.out(Motion.ui)) { phase = .prompt }
    }

    /// Back to the prompt to ask for another change or another screen.
    func another() {
        prompt = ""
        state = nil
        withAnimation(Motion.out(Motion.ui)) { phase = .prompt }
    }

    /// Waits (up to 8 s) for the Core's frames to reach the canvas over the sync.
    private func arrived(_ frames: [String], in editor: DesignEditor) async {
        for _ in 0..<40 where !frames.allSatisfy({ editor.layers[$0] != nil }) {
            try? await Task.sleep(for: .milliseconds(200))
            editor.reload()
        }
    }

    /// Keeps `d`'s frame, removes the other directions' frames (one undo step), selects and shows it.
    func use(_ d: ComposeState.Direction) {
        guard let all = state?.directions else { return }
        Task { await keep(d, all: all) }
    }

    private func keep(_ d: ComposeState.Direction, all: [ComposeState.Direction]) async {
        guard let editor = model?.editors[doc] else { return close() }
        let frames = all.compactMap(\.frame)
        await arrived(frames, in: editor)
        let drop = frames.filter { $0 != d.frame && editor.layers[$0] != nil }
        if !drop.isEmpty { editor.apply(drop.map(EditOps.delete)) }
        if let f = d.frame, editor.select(f, quiet: true) { editor.fitSelection() }
        withAnimation(Motion.out(Motion.ui)) { phase = .done("\(d.name) is on the canvas.") }
    }

    /// The edit: the redrawn frame takes the old one's place (parent, order, position) and name, the old one and any other
    /// direction go, all in one canvas edit, so one Undo brings the old screen back.
    private func replace(_ old: Target, with d: ComposeState.Direction, all: [ComposeState.Direction]) async {
        guard let editor = model?.editors[doc], let new = d.frame else { return close() }
        let frames = all.compactMap(\.frame)
        await arrived(frames, in: editor)
        guard editor.layers[new] != nil, let was = editor.layers[old.id], let parent = was.parent,
            let oldNode = editor.node(of: old.id)
        else {
            withAnimation(Motion.out(Motion.ui)) {
                phase = .failed("The new screen did not reach the canvas. Try again.")
            }
            return
        }
        var ops: [[String: DJSON]] = [
            EditOps.move(new, parent: parent, order: was.order),
            EditOps.name(new, old.name),
        ]
        for k in ["x", "y"] { if let v = oldNode.props[k] { ops.append(EditOps.set(new, k, v)) } }
        ops.append(EditOps.delete(old.id))
        ops += frames.filter { $0 != new && editor.layers[$0] != nil }.map(EditOps.delete)
        guard editor.apply(ops) else {
            withAnimation(Motion.out(Motion.ui)) { phase = .failed("The canvas would not take the new screen.") }
            return
        }
        if editor.select(new, quiet: true) { editor.fitSelection() }
        target = Target(id: new, name: old.name)
        withAnimation(Motion.out(Motion.ui)) { phase = .done("\(old.name) is updated.") }
    }

    func undo() {
        model?.editors[doc]?.undo()
        close()
    }

    /// The picture of a direction's frame, when the canvas has it.
    func sketch(_ d: ComposeState.Direction) -> FrameSketch? {
        d.frame.flatMap { model?.editors[doc]?.sketch(frame: $0) }
    }

    /// Shows one direction on the canvas without keeping it yet.
    func preview(_ d: ComposeState.Direction) {
        guard let f = d.frame, let editor = model?.editors[doc], editor.select(f, quiet: true) else { return }
        editor.fitSelection()
    }

    func close() {
        task?.cancel()
        withAnimation(Motion.out(Motion.ui)) { model?.composer = nil }
    }

    static func sentence(_ reason: String) -> String {
        reason.isEmpty ? "The AI could not draw this one." : reason
    }
}

/// An edit request in words: the change, then the screen as it is, top to bottom, within the Core's 1000 characters.
enum EditPrompt {
    struct Element: Equatable {
        let kind: String
        let text: String?
        let color: String?
        let size: Double?
        let y: Double
    }

    static func make(
        change: String, screen: String, size: CGSize = CGSize(width: 360, height: 630), elements: [Element]
    )
        -> String
    {
        let kind = size.width >= 1100 ? "desktop" : size.width >= 600 ? "tablet" : "phone"
        let head =
            "Redraw the existing \(kind) screen \"\(screen)\" (\(Int(size.width))×\(Int(size.height))) with this change: "
            + "\(change). Keep everything else as it is now "
            + "(same texts, colours and layout) unless the change says otherwise. The screen now, top to bottom: "
        var body: [String] = []
        var used = head.count
        for e in elements.sorted(by: { $0.y < $1.y }) {
            let part: String
            switch e.kind {
            case "text":
                part =
                    "text \"\((e.text ?? "").prefix(60))\"" + (e.size.map { " \(Int($0))pt" } ?? "")
                    + (e.color.map { " \($0)" } ?? "")
            default:
                part = "\(e.kind)" + (e.color.map { " \($0)" } ?? "")
            }
            guard used + part.count + 2 < 990 else { break }
            body.append(part)
            used += part.count + 2
        }
        return head + (body.isEmpty ? "an empty screen" : body.joined(separator: "; ")) + "."
    }

    @MainActor static func elements(of frame: String, in editor: DesignEditor) -> [Element] {
        editor.layers.children(of: frame).compactMap { l in
            guard let n = editor.node(of: l.id) else { return nil }
            return Element(
                kind: n.type, text: n.text, color: FrameSketch.hex(n), size: n.props["type"]?["size"]?.double,
                y: n.props["y"]?.double ?? 0)
        }
    }
}
