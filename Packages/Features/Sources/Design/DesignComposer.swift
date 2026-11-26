import CoreKit
import CoreUI
import Observation
import SwiftUI

/// The Design AI (E11-4, D-29), shown as the AI panel over the canvas (`DesignAIPanel`). Two modes:
/// - New: describe a screen; an AI session draws one design, three directions or a flow of screens as frames on the canvas.
/// - Edit: with a frame selected (or anything inside one), describe a change; the AI redraws that screen with the change and
///   the redrawn frame takes the old one's place, name and position, as one undoable canvas edit.
/// The Core does the drawing (`POST /docs/{doc}/compose`); this polls it (`ComposePoll`). A Core from before API minor 109
/// has no edit mode, so an edit then sends the screen's contents in words with the change (`EditPrompt`).
/// One run at a time: starting another run, closing the item or switching design stops the task and the Core session.
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

    /// What the panel's Undo takes back: exactly what the AI added, never the person's earlier edit.
    private enum UndoPlan {
        /// A drawing: the kept frame(s) (and the other directions') are deleted as one local edit.
        case remove([String])
        /// An edit: the local replace step is undone (the old screen returns), then the new frame is deleted.
        case restore(new: String, extra: [String])
    }

    /// The Core's limit on a prompt, in unicode scalars (Rust `chars`).
    static let promptLimit = 600

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
    /// The poll interval, the longest a drawing may take, the longest wait between retries, and how long the frames get to
    /// reach the canvas (tests shorten them).
    nonisolated(unsafe) static var pollInterval = Duration.milliseconds(1200)
    nonisolated(unsafe) static var maxBackoff = Duration.seconds(5)
    nonisolated(unsafe) static var drawLimit = Duration.seconds(240)
    nonisolated(unsafe) static var arriveLimit = Duration.seconds(25)
    @ObservationIgnored private weak var model: DesignModel?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Tells a finishing run whether it is still the current one.
    @ObservationIgnored private var runID = 0
    /// A run that stopped on a failed poll: "Try again" asks the Core about it first (the Core finishes on read).
    @ObservationIgnored private var resumable: ComposeState?
    @ObservationIgnored private var undoPlan: UndoPlan?
    /// The empty frame a new design starts with, removed when the AI's frames land (Draw with AI from the home).
    @ObservationIgnored var starterFrame: String?
    @ObservationIgnored private var originalText = ""

    init(model: DesignModel, doc: String, prompt: String = "", target: Target? = nil) {
        self.model = model
        self.doc = doc
        self.prompt = prompt
        self.target = target
    }

    var trimmed: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    var promptLength: Int { trimmed.unicodeScalars.count }
    var overLimit: Bool { promptLength > Self.promptLimit }
    var editing: Bool { target != nil }
    /// The Core reads the edited frame itself (API 109); older Cores get the screen in words.
    private var nativeEdit: Bool { editing && model?.editSupported == true }
    /// What the Core is asked: the words, or for an older Core's edit the screen in words with the change.
    var request: String {
        guard let target, !nativeEdit, let editor = model?.editors[doc] else { return trimmed }
        return EditPrompt.make(
            change: trimmed, screen: target.name, size: screen, elements: EditPrompt.elements(of: target.id, in: editor)
        )
    }
    var canDraw: Bool { !trimmed.isEmpty && !overLimit && !busy && phase != .drawing }
    /// The screen to draw: the edited frame's size, else what the words ask for, else the default canvas (Settings, Design,
    /// Options).
    var screen: CGSize {
        if let target, let editor = model?.editors[doc], let r = Self.rect(of: target.id, in: editor) { return r.size }
        let s = (DesignOptions.Canvas.named(in: trimmed) ?? DesignOptions.canvas).size
        return CGSize(width: s.w, height: s.h)
    }
    /// How many frames the panel waits for.
    var expected: Int { editing || single ? 1 : 3 }

    func draw(resuming: ComposeState? = nil) {
        guard canDraw, let service = model?.service else { return }
        if phase == .drawing { cancelSession() }
        task?.cancel()
        runID += 1
        let run = runID
        busy = true
        resumable = nil
        undoPlan = nil
        let text = String(request.unicodeScalars.prefix(1000))
        let (doc, count, size, frame) = (doc, expected, screen, nativeEdit ? target?.id : nil)
        if originalText.isEmpty { originalText = trimmed }
        startedAt = Date()
        if let editor = model?.editors[doc] {
            busyRects =
                target.flatMap { Self.rect(of: $0.id, in: editor) }.map { [$0] }
                ?? Self.landing(count: expected, size: screen, in: editor)
            // Show the canvas where the work happens.
            if let all = busyRects.first.map({ busyRects.dropFirst().reduce($0) { $0.union($1) } }) { editor.fit(all) }
        }
        withAnimation(Motion.out(Motion.ui)) { phase = .drawing }
        // The task holds the service and plain values, the composer only weakly: a cancelled run lets go of it at once.
        task = Task { [weak self] in
            do {
                let s = try await ComposePoll.run(
                    service: service, doc: doc, resume: resuming,
                    start: {
                        if let frame {
                            return try await service.composeEdit(doc: doc, prompt: text, frame: frame, size: size)
                        }
                        return try await service.compose(doc: doc, prompt: text, count: count, size: size)
                    },
                    onState: { s in
                        guard let self, self.runID == run else { return }
                        self.state = s
                        self.busy = false
                    })
                await self?.finished(s, run: run)
            } catch is CancellationError {
                return
            } catch {
                self?.failed(error, run: run)
            }
        }
    }

    private func failed(_ error: any Error, run: Int) {
        guard run == runID else { return }
        busy = false
        if error is ComposeTimedOut {
            withAnimation(Motion.out(Motion.ui)) {
                phase = .failed("The AI took too long. Try again, or change the words.")
            }
            return
        }
        // A known compose id: Try again asks the Core about it before starting another session.
        if let s = state, s.phase == .drawing || s.phase == .applying { resumable = s }
        withAnimation(Motion.out(Motion.ui)) { phase = .failed(model?.words(error) ?? "That did not work.") }
    }

    private func finished(_ s: ComposeState, run: Int) async {
        guard run == runID else { return }
        busy = false
        state = s
        guard s.phase == .done, let best = s.directions.first else {
            withAnimation(Motion.out(Motion.ui)) { phase = .failed(Self.sentence(s.reason)) }
            return
        }
        if let target {
            await replace(target, with: best, all: s.directions, run: run)
        } else if s.flow == true {
            await keepFlow(best.screens.isEmpty ? s.directions.compactMap(\.frame) : best.screens, run: run)
        } else if single {
            await keep(best, all: s.directions, run: run)
        } else {
            withAnimation(Motion.out(Motion.ui)) { phase = .directions }
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
        runID += 1
        task?.cancel()
        cancelSession()
        busy = false
        state = nil
        resumable = nil
        withAnimation(Motion.out(Motion.ui)) { phase = .prompt }
    }

    /// The panel goes away (closed, another run, another design): the task and the Core session end, nothing is shown.
    func shutdown() {
        runID += 1
        task?.cancel()
        task = nil
        if phase == .drawing { cancelSession() }
        busy = false
    }

    /// Stops the Core's AI session for the current drawing, if it has one.
    private func cancelSession() {
        if let session = state?.session, let service = model?.service {
            Task { try? await service.cancelCompose(session: session) }
        }
    }

    /// Try again: a run that failed on a poll asks the Core about the same drawing first; otherwise a fresh one.
    func again() {
        let r = resumable
        state = nil
        draw(resuming: r)
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
        resumable = nil
        withAnimation(Motion.out(Motion.ui)) { phase = .prompt }
    }

    static let notArrived = "The new screen did not reach the canvas. Check the connection and try again."

    /// Waits (up to `arriveLimit`) for the Core's frames to reach the canvas over the sync; the phase stays `.drawing`.
    /// False when they never came.
    private func arrived(_ frames: [String], in editor: DesignEditor) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: Self.arriveLimit)
        while !frames.allSatisfy({ editor.layers[$0] != nil }) {
            if ContinuousClock.now >= deadline || Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(200))
            editor.reload()
        }
        return true
    }

    /// Keeps `d`'s frame, removes the other directions' frames (one undo step), selects and shows it.
    func use(_ d: ComposeState.Direction) {
        guard let all = state?.directions else { return }
        let run = runID
        Task { await keep(d, all: all, run: run) }
    }

    /// The empty starter frame (Draw with AI from the home), when it is still empty and not one of the AI's.
    private func starterOps(in editor: DesignEditor, except ai: [String]) -> [[String: DJSON]] {
        guard let f = starterFrame, !ai.contains(f), editor.layers[f] != nil, editor.layers.children(of: f).isEmpty
        else { return [] }
        starterFrame = nil
        return [EditOps.delete(f)]
    }

    private func keep(_ d: ComposeState.Direction, all: [ComposeState.Direction], run: Int) async {
        guard let editor = model?.editors[doc] else { return close() }
        let frames = all.compactMap(\.frame)
        // Only the kept frame must arrive: an older Core can draw more frames than asked (it ignores `count`).
        guard await arrived(d.frame.map { [$0] } ?? frames, in: editor), run == runID else {
            if !Task.isCancelled, run == runID {
                withAnimation(Motion.out(Motion.ui)) { phase = .failed(Self.notArrived) }
            }
            return
        }
        let drop = frames.filter { $0 != d.frame && editor.layers[$0] != nil }
        let ops = drop.map(EditOps.delete) + starterOps(in: editor, except: frames)
        if !ops.isEmpty { editor.apply(ops) }
        undoPlan = .remove(frames)
        if let f = d.frame, editor.select(f, quiet: true) { editor.fitSelection() }
        withAnimation(Motion.out(Motion.ui)) { phase = .done("\(d.name) is on the canvas.") }
    }

    /// A flow of screens (Core `flow: true`): every frame stays, all are selected and shown.
    private func keepFlow(_ frames: [String], run: Int) async {
        guard let editor = model?.editors[doc] else { return close() }
        guard await arrived(frames, in: editor), run == runID else {
            if !Task.isCancelled, run == runID {
                withAnimation(Motion.out(Motion.ui)) { phase = .failed(Self.notArrived) }
            }
            return
        }
        let ops = starterOps(in: editor, except: frames)
        if !ops.isEmpty { editor.apply(ops) }
        undoPlan = .remove(frames)
        if editor.select(frames, quiet: true) {
            let rects = frames.compactMap { Self.rect(of: $0, in: editor) }
            if let first = rects.first { editor.fit(rects.dropFirst().reduce(first) { $0.union($1) }) }
        }
        withAnimation(Motion.out(Motion.ui)) {
            phase = .done("\(Words.count(frames.count, "screen")) are on the canvas.")
        }
    }

    /// The edit: the redrawn frame takes the old one's place (parent, order, position) and name, the old one and any other
    /// direction go, all in one canvas edit, so one Undo brings the old screen back.
    private func replace(_ old: Target, with d: ComposeState.Direction, all: [ComposeState.Direction], run: Int) async {
        guard let editor = model?.editors[doc], let new = d.frame else { return close() }
        let frames = all.compactMap(\.frame)
        guard await arrived([new], in: editor), run == runID else {
            if !Task.isCancelled, run == runID {
                withAnimation(Motion.out(Motion.ui)) { phase = .failed(Self.notArrived) }
            }
            return
        }
        guard editor.layers[new] != nil, let was = editor.layers[old.id], let parent = was.parent,
            let oldNode = editor.node(of: old.id)
        else {
            withAnimation(Motion.out(Motion.ui)) {
                phase = .failed(Self.notArrived)
            }
            return
        }
        var ops: [[String: DJSON]] = [
            EditOps.move(new, parent: parent, order: was.order),
            EditOps.name(new, old.name),
        ]
        for k in ["x", "y"] { if let v = oldNode.props[k] { ops.append(EditOps.set(new, k, v)) } }
        ops.append(EditOps.delete(old.id))
        let extra = frames.filter { $0 != new && editor.layers[$0] != nil }
        ops += extra.map(EditOps.delete)
        guard editor.apply(ops) else {
            withAnimation(Motion.out(Motion.ui)) { phase = .failed("The canvas would not take the new screen.") }
            return
        }
        undoPlan = .restore(new: new, extra: extra)
        if editor.select(new, quiet: true) { editor.fitSelection() }
        target = Target(id: new, name: old.name)
        withAnimation(Motion.out(Motion.ui)) { phase = .done("\(old.name) is updated.") }
    }

    /// Takes back what the AI did and nothing else: a drawing's frames are deleted (one local edit); an edit's replace
    /// step is undone and the redrawn frame deleted. The person's earlier edits are never touched.
    func undo() {
        guard let editor = model?.editors[doc], let plan = undoPlan else { return close() }
        undoPlan = nil
        switch plan {
        case .remove(let ids):
            let ops = ids.filter { editor.layers[$0] != nil }.map(EditOps.delete)
            if !ops.isEmpty { editor.apply(ops) }
        case .restore(let new, let extra):
            editor.undo()
            let ops = ([new] + extra).filter { editor.layers[$0] != nil }.map(EditOps.delete)
            if !ops.isEmpty { editor.apply(ops) }
        }
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

    /// Closes the panel: ends the run, and only if this panel is still the open one (a finishing stale run never closes
    /// another design's panel).
    func close() {
        shutdown()
        guard model?.composer === self else { return }
        withAnimation(Motion.out(Motion.ui)) { model?.composer = nil }
    }

    static func sentence(_ reason: String) -> String {
        reason.isEmpty ? "The AI could not draw this one." : reason
    }
}

/// The polling of a compose run, shared by the composer and the style guide's AI: start (or re-ask about a known drawing),
/// then read every 1.2 s until the Core is done. A network, offline or 5xx failure on a read is retried with backoff
/// (1.2 s up to 5 s) until the limit; only a definitive answer from the Core ends the run.
enum ComposePoll {
    @MainActor
    static func run(
        service: any DesignService, doc: String, resume: ComposeState?,
        start: () async throws -> ComposeState, onState: (ComposeState) -> Void
    ) async throws -> ComposeState {
        var s: ComposeState
        if let r = resume, let got = try? await service.composeState(doc: doc, id: r.id), got.phase != .failed {
            s = got
        } else {
            s = try await start()
        }
        onState(s)
        let interval = DesignComposer.pollInterval
        let deadline = ContinuousClock.now.advanced(by: DesignComposer.drawLimit)
        var wait = interval
        while s.phase == .drawing || s.phase == .applying {
            if ContinuousClock.now >= deadline {
                if let id = s.session { try? await service.cancelCompose(session: id) }
                throw ComposeTimedOut()
            }
            try await Task.sleep(for: wait)
            do {
                s = try await service.composeState(doc: doc, id: s.id)
                onState(s)
                wait = interval
            } catch {
                if Task.isCancelled { throw CancellationError() }
                guard isTransient(error) else { throw error }
                wait = min(DesignComposer.maxBackoff, wait * 1.6)
            }
        }
        return s
    }

    /// A failure that says nothing about the drawing: the network, a restart, a busy Core.
    static func isTransient(_ error: any Error) -> Bool {
        if error is URLError { return true }
        if let f = error as? DesignFailure { return f.status >= 500 && f.status != 501 }
        switch CoreError.unwrapping(error) {
        case .offline, .coreUnproven, .rateLimited: return true
        case .http(let status, _, _): return status >= 500 && status != 501
        default: return false
        }
    }
}

/// The drawing ran past its limit; the Core session was stopped.
struct ComposeTimedOut: Error {}

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
        var used = head.unicodeScalars.count
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
            guard used + part.unicodeScalars.count + 2 < 990 else { break }
            body.append(part)
            used += part.unicodeScalars.count + 2
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
