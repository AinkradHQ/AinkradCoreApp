import CoreUI
import Observation
import SwiftUI

/// The Design composer (E11-4, D-29): describe a design, an AI session draws three directions as frames on the canvas, you
/// pick one. The Core does the drawing (`POST /docs/{doc}/compose`); this polls it and, on "Use this", deletes the other two
/// frames as one undoable canvas edit. "Draw 3 more" and "Refine" are new drawings (a refine names the direction).
@MainActor @Observable
final class DesignComposer {
    enum Phase: Equatable {
        case prompt, drawing, directions
        case failed(String)
    }

    let doc: String
    var prompt: String
    private(set) var phase = Phase.prompt
    private(set) var state: ComposeState?
    private(set) var busy = false
    @ObservationIgnored private weak var model: DesignModel?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(model: DesignModel, doc: String, prompt: String = "") {
        self.model = model
        self.doc = doc
        self.prompt = prompt
    }

    var trimmed: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canDraw: Bool { !trimmed.isEmpty && trimmed.count <= 1000 && !busy }

    func draw() {
        guard canDraw, let service = model?.service else { return }
        busy = true
        let text = trimmed
        if originalText.isEmpty { originalText = text }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            defer { busy = false }
            do {
                var s = try await service.compose(doc: doc, prompt: text)
                state = s
                phase = .drawing
                busy = false
                // ponytail: a 1.2 s poll; the Core finishes the drawing on the read that finds the AI done.
                while s.phase == .drawing || s.phase == .applying {
                    try await Task.sleep(for: .milliseconds(1200))
                    s = try await service.composeState(doc: doc, id: s.id)
                    state = s
                }
                phase = s.phase == .done ? .directions : .failed(Self.sentence(s.reason))
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(model?.words(error) ?? "That did not work.")
            }
        }
    }

    /// Stop watching, and stop the AI session too.
    func stop() {
        task?.cancel()
        let session = state?.session
        state = nil
        phase = .prompt
        if let session, let service = model?.service { Task { try? await service.cancelCompose(session: session) } }
    }

    func again() {
        state = nil
        draw()
    }

    func refine(_ d: ComposeState.Direction) {
        prompt =
            "Refine the \(d.name) direction (\(d.summary)). Keep what works and improve it. Original request: "
            + original
        phase = .prompt
    }

    @ObservationIgnored private var originalText = ""
    private var original: String { originalText.isEmpty ? trimmed : originalText }

    /// Keeps `d`'s frame, removes the other directions' frames from the canvas (undo brings them back).
    func use(_ d: ComposeState.Direction) {
        guard let editor = model?.editors[doc], let all = state?.directions else {
            close()
            return
        }
        let drop = all.filter { $0.frame != d.frame }.compactMap(\.frame)
        if !drop.isEmpty { editor.apply(drop.map(EditOps.delete)) }
        if let f = d.frame { editor.select(f) }
        close()
    }

    /// The picture of a direction's frame, when the canvas has it.
    func sketch(_ d: ComposeState.Direction) -> FrameSketch? {
        d.frame.flatMap { model?.editors[doc]?.sketch(frame: $0) }
    }

    func close() {
        task?.cancel()
        model?.host.shell.closeDialog()
    }

    static func sentence(_ reason: String) -> String {
        reason.isEmpty ? "The AI could not draw this one." : reason
    }
}

struct ComposerView: View {
    @Bindable var composer: DesignComposer
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        CoreDialogPanel(title, width: Space.s8 * 22) {
            switch composer.phase {
            case .prompt: promptStep
            case .drawing: drawing
            case .directions: directions
            case .failed(let why): failed(why)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .accessibilityIdentifier("design-composer")
    }

    private var title: String {
        switch composer.phase {
        case .prompt, .failed: "Draw with AI"
        case .drawing: "AI is drawing 3 directions"
        case .directions: "Pick a direction"
        }
    }

    private var promptStep: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Describe what you want. AI draws three different ideas on this canvas to pick from.")
                .foregroundStyle(GlassInk.secondary)
            CoreTextField(
                "What should it show?", placeholder: "A calm welcome screen for a notes app",
                text: $composer.prompt, autofocus: true
            ) { composer.draw() }
            HStack(spacing: Space.s2) {
                Text("3 different ideas").foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s2)
                Button("Cancel") { composer.close() }.buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Button {
                    composer.draw()
                } label: {
                    Label("Draw 3 directions", systemImage: "sparkles")
                }
                .buttonStyle(CoreButtonStyle(.prominent, busy: composer.busy)).coreShortcut(.primary)
                .disabled(!composer.canDraw).opacity(composer.canDraw || composer.busy ? 1 : 0.45)
            }
        }
    }

    private var drawing: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("“\(composer.trimmed)”").foregroundStyle(GlassInk.secondary).lineLimit(2)
            HStack(alignment: .top, spacing: Space.s3) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        coreShape(Radius.cardMac).fill(GlassInk.well).frame(height: Space.s8 * 5)
                        Text("Direction \(["A", "B", "C"][i])").coreFont(size: MacTextSize.body, weight: .semibold)
                        CoreBusyBar()
                        Text("Sketching the first shapes").foregroundStyle(GlassInk.secondary)
                            .coreFont(size: MacTextSize.meta)
                    }
                    .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                    .coreWell(radius: Radius.pane)
                }
            }
            HStack {
                Spacer(minLength: Space.s2)
                Button("Stop") { composer.stop() }.buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The AI is drawing three directions")
    }

    private var directions: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("They are on the canvas now. Keep one, and the other two go away (Undo brings them back).")
                .foregroundStyle(GlassInk.secondary)
            HStack(alignment: .top, spacing: Space.s3) {
                ForEach(Array((composer.state?.directions ?? []).enumerated()), id: \.offset) { i, d in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        thumb(d)
                        HStack(spacing: Space.s2) {
                            Text(d.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                            if i == 0 { StateBadge("Best match", tone: .run, symbol: "star") }
                        }
                        Text(d.summary).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Space.s2)
                        HStack(spacing: Space.s2) {
                            Button("Refine") { composer.refine(d) }.buttonStyle(CoreButtonStyle(.secondary))
                            Button("Use this") { composer.use(d) }
                                .buttonStyle(CoreButtonStyle(i == 0 ? .prominent : .secondary))
                        }
                    }
                    .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 4, alignment: .leading)
                    .coreWell(radius: Radius.pane)
                }
            }
            HStack {
                Button {
                    composer.again()
                } label: {
                    Label("Draw 3 more", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CoreButtonStyle(.secondary))
                Spacer(minLength: Space.s2)
                Button("Keep all three") { composer.close() }.buttonStyle(CoreButtonStyle(.secondary))
                    .coreShortcut(.cancel)
            }
        }
    }

    /// The direction's frame as drawn on the canvas, or a quiet well while the canvas has not listed it.
    @ViewBuilder private func thumb(_ d: ComposeState.Direction) -> some View {
        Group {
            if let sk = composer.sketch(d) {
                FrameSketchView(sketch: sk)
            } else {
                coreShape(Radius.cardMac).fill(GlassInk.well)
            }
        }
        .frame(height: Space.s8 * 5)
        .frame(maxWidth: .infinity)
    }

    private func failed(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreNotice(symbol: "exclamationmark.triangle", title: why, tone: .warn)
            HStack(spacing: Space.s2) {
                Spacer(minLength: Space.s2)
                Button("Close") { composer.close() }.buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Button("Try again") { composer.again() }.buttonStyle(CoreButtonStyle(.prominent))
            }
        }
    }
}
