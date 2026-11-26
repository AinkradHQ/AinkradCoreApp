import Foundation
import Projects
import Testing

@testable import Design

private final class ComposeService: DesignService, @unchecked Sendable {
    private let lock = NSLock()
    var reads = 0
    var stuck = false
    var cancelled: [String] = []
    var started: [String] = []
    /// The next reads that fail: transient (the network) or definitive (the Core says 404).
    var transientFailures = 0
    var definitiveFailures = 0
    var flow = false
    var frames = ["n_Calm", "n_Bold", "n_Playful"]
    func cancelCompose(session: String) async throws { lock.withLock { cancelled.append(session) } }
    func docs() async throws -> [DesignDoc] { [] }
    func assets() async throws -> [DesignAsset] { [] }
    func kits() async throws -> [BrandKit] { [] }
    func data(_ sha: String) async throws -> Data { Data() }
    func link(_ item: DesignItem, project: String, _ on: Bool) async throws {}
    func compose(doc: String, prompt: String, count: Int, size: CGSize) async throws -> ComposeState {
        let n = lock.withLock { () -> Int in
            started.append(prompt)
            return started.count
        }
        return ComposeState(id: "dc_\(n)", phase: .drawing, reason: "", session: "s_\(n)", directions: [])
    }
    func composeState(doc: String, id: String) async throws -> ComposeState {
        let n = id.split(separator: "_").last.map(String.init) ?? "1"
        let (read, transient, definitive) = lock.withLock { () -> (Int, Bool, Bool) in
            reads += 1
            let t = transientFailures > 0
            let d = !t && definitiveFailures > 0
            if t { transientFailures -= 1 }
            if d { definitiveFailures -= 1 }
            return (reads, t, d)
        }
        if transient { throw URLError(.notConnectedToInternet) }
        if definitive { throw DesignFailure(sentence: "No such drawing.", code: "not_found", status: 404) }
        if stuck { return ComposeState(id: id, phase: .drawing, reason: "", session: "s_\(n)", directions: []) }
        let done = read >= 2
        let names = ["Calm", "Bold", "Playful"]
        return ComposeState(
            id: id, phase: done ? .done : .drawing, reason: "", session: "s_\(n)",
            directions: done
                ? zip(names, frames).map { .init(name: $0, summary: "x", frame: $1, screens: flow ? frames : []) } : [],
            flow: flow ? true : nil)
    }
}

@Suite("Design composer", .serialized) @MainActor
struct ComposerTests {
    @Test func drawsThenShowsThreeDirections() async {
        let model = DesignModel(host: FakeHost(), projects: ProjectsModel(host: FakeHost()))
        let service = ComposeService()
        model.service = service
        let c = DesignComposer(model: model, doc: "dd_0000000000000001", prompt: "  a welcome screen ")
        c.single = false  // One design is the default now; three ideas is the choice
        #expect(c.canDraw && c.expected == 3)
        c.draw()
        #expect(await until { c.phase == .directions })
        #expect(service.started == ["a welcome screen"])
        #expect(c.state?.directions.map(\.name) == ["Calm", "Bold", "Playful"])
    }

    @Test func aDrawingThatNeverFinishesFailsAndStopsTheSession() async {
        let (poll, limit) = (DesignComposer.pollInterval, DesignComposer.drawLimit)
        defer { (DesignComposer.pollInterval, DesignComposer.drawLimit) = (poll, limit) }
        DesignComposer.pollInterval = .milliseconds(10)
        DesignComposer.drawLimit = .milliseconds(100)
        let model = DesignModel(host: FakeHost(), projects: ProjectsModel(host: FakeHost()))
        let service = ComposeService()
        service.stuck = true
        model.service = service
        let c = DesignComposer(model: model, doc: "dd_0000000000000001", prompt: "x")
        c.draw()
        #expect(await until { c.phase == .failed("The AI took too long. Try again, or change the words.") })
        #expect(await until { service.cancelled == ["s_1"] })
    }

    @Test func theWordsPickTheScreenSize() {
        typealias C = DesignOptions.Canvas
        #expect(C.named(in: "create a web comming soon page (desktop size)") == .desktop)
        #expect(C.named(in: "A landing page for a bakery") == .desktop)
        #expect(C.named(in: "an iPad reading app") == .tablet)
        #expect(C.named(in: "create a login mobile screen") == .phone)
        #expect(C.named(in: "a calm checkout") == nil)
        #expect(C.named(in: "webhooks settings") == nil)
        #expect(C.named(in: "phone dashboard") == .phone)
        #expect(C.named(in: "a mobile app dashboard") == .phone)
        #expect(C.named(in: "web dashboard") == .desktop)
        #expect(C.named(in: "an iPad iOS app") == .tablet)
        #expect(C.named(in: "تطبيق موبايل") == .phone && C.named(in: "صفحة ويب") == .desktop)
        #expect(C.named(in: "une tablette") == .tablet && C.named(in: "app móvil") == .phone)
        #expect(C.named(in: "eine Webseite") == .desktop && C.named(in: "Handy App") == .phone)
    }

    @Test func theLimitCountsUnicodeScalarsLikeTheCore() {
        let model = DesignModel(host: FakeHost(), projects: ProjectsModel(host: FakeHost()))
        let c = DesignComposer(model: model, doc: "dd_0000000000000001", prompt: String(repeating: "a", count: 600))
        #expect(c.canDraw && !c.overLimit)
        c.prompt += "b"
        #expect(c.overLimit && !c.canDraw && c.promptLength == 601)
        // A family emoji is one character to the person but 5 scalars: counted like the Core counts it.
        c.prompt = String(repeating: "👨‍👩‍👧", count: 121)
        #expect(c.prompt.count == 121 && c.promptLength == 605 && c.overLimit)
    }

    @Test func brandColoursAreNormalisedForTheCore() {
        #expect(BrandColor.normalize("#FFF") == "#ffffff")
        #expect(BrandColor.normalize("2f6fec") == "#2f6fec")
        #expect(BrandColor.normalize("#2F6FECcc") == "#2f6fec")
        #expect(BrandColor.normalize("#f00a") == "#ff0000")
        #expect(BrandColor.normalize("red") == nil && BrandColor.normalize("#12345") == nil)
    }

    @Test func emptyPromptCannotDraw() {
        let model = DesignModel(host: FakeHost(), projects: ProjectsModel(host: FakeHost()))
        #expect(!DesignComposer(model: model, doc: "dd_0000000000000001", prompt: "   ").canDraw)
    }

    @Test func aCoreWithoutComposeSaysSo() async {
        let model = DesignModel(host: FakeHost(), projects: ProjectsModel(host: FakeHost()))
        model.service = FakeService()
        let c = DesignComposer(model: model, doc: "dd_0000000000000001", prompt: "x")
        c.draw()
        #expect(await until { if case .failed = c.phase { true } else { false } })
    }
}

/// The run lifecycle: one run at a time, cancelled with the panel, patient with the network, undone exactly.
@Suite("Design composer runs", .serialized) @MainActor
struct ComposerRunTests {
    private static let docID = "dd_0000000000000001"
    private func fast() -> () -> Void {
        let (poll, back, limit) = (DesignComposer.pollInterval, DesignComposer.maxBackoff, DesignComposer.drawLimit)
        DesignComposer.pollInterval = .milliseconds(5)
        DesignComposer.maxBackoff = .milliseconds(20)
        DesignComposer.drawLimit = .seconds(10)
        return {
            (DesignComposer.pollInterval, DesignComposer.maxBackoff, DesignComposer.drawLimit) = (poll, back, limit)
        }
    }
    private func make() -> (DesignModel, ComposeService) {
        let model = DesignModel(host: FakeHost(), projects: ProjectsModel(host: FakeHost()))
        let service = ComposeService()
        model.service = service
        model.docs = [
            DesignDoc(
                id: Self.docID, kind: .design, name: "D", system: nil, projects: [], aiPaused: false,
                createdBy: "device:d_1", updatedAt: Date())
        ]
        model.openID = "doc:\(Self.docID)"
        return (model, service)
    }
    private func editor(_ model: DesignModel, _ tree: [String]) -> (DesignEditor, FakeBackend) {
        let b = FakeBackend()
        let nodes = tree.map {
            #"{"id":"\#($0)","type":"frame","parent":"p","order":"i","name":"\#($0)"}"#
        }
        b.treeJSON =
            #"[{"id":"p","type":"page","parent":null,"order":"i","name":"Page"},"# + nodes.joined(separator: ",") + "]"
        b.nodes["old"] = #"{"id":"old","type":"frame","parent":"p","order":"i","name":"Home","props":{"x":10,"y":20}}"#
        let e = DesignEditor(doc: Self.docID)
        e.attach(b)
        model.editors[Self.docID] = e
        return (e, b)
    }

    @Test func closingThePanelStopsTheTaskAndTheCoreSession() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        service.stuck = true
        let c = DesignComposer(model: model, doc: Self.docID, prompt: "x")
        model.composer = c
        c.draw()
        #expect(await until { c.state != nil })
        c.close()
        #expect(await until { service.cancelled == ["s_1"] })
        let reads = service.reads
        try? await Task.sleep(for: .milliseconds(80))
        #expect(service.reads <= reads + 1, "the poll stopped")
        #expect(model.composer == nil)
    }

    @Test func aSecondRunCancelsTheFirst() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        service.stuck = true
        await model.drawWithAI(prompt: "first")
        let first = model.composer
        #expect(await until { first?.state != nil })
        await model.drawWithAI(prompt: "second")
        #expect(model.composer !== first)
        #expect(await until { service.cancelled == ["s_1"] })
        #expect(await until { model.composer?.state?.session == "s_2" })
        model.closeItem()
        #expect(await until { service.cancelled.sorted() == ["s_1", "s_2"] })
    }

    @Test func aFinishingStaleRunNeverClosesAnotherPanel() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        let (e, b) = editor(model, ["n_Calm"])
        withExtendedLifetime(b) {}
        _ = e
        let old = DesignComposer(model: model, doc: Self.docID, prompt: "x")
        let other = DesignComposer(model: model, doc: "dd_0000000000000002", prompt: "y")
        model.composer = other
        old.close()
        #expect(model.composer === other)
        _ = service
    }

    @Test func aTransientFailureIsRetriedOnTheSameDrawing() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        service.transientFailures = 3
        let c = DesignComposer(model: model, doc: Self.docID, prompt: "x")
        c.single = false
        c.draw()
        #expect(await until { c.phase == .directions })
        #expect(service.started.count == 1, "no second session")
    }

    @Test func tryAgainAsksAboutTheSameDrawingFirst() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        service.definitiveFailures = 1
        let c = DesignComposer(model: model, doc: Self.docID, prompt: "x")
        c.single = false
        c.draw()
        #expect(await until { if case .failed = c.phase { true } else { false } })
        c.again()
        #expect(await until { c.phase == .directions })
        #expect(service.started.count == 1, "the same drawing was polled, not a new session")
    }

    @Test func tryAgainStartsANewSessionWhenTheCoreSaysFailed() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        service.definitiveFailures = 2  // the failed poll, then the re-poll
        let c = DesignComposer(model: model, doc: Self.docID, prompt: "x")
        c.single = false
        c.draw()
        #expect(await until { if case .failed = c.phase { true } else { false } })
        c.again()
        #expect(await until { c.phase == .directions })
        #expect(service.started.count == 2)
    }

    @Test func undoAfterADrawingRemovesOnlyTheAIFrames() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        let (e, b) = editor(model, ["mine", "n_Calm", "n_Bold", "n_Playful"])
        _ = service
        let c = DesignComposer(model: model, doc: Self.docID, prompt: "x")
        model.composer = c
        c.draw()
        #expect(await until { if case .done = c.phase { true } else { false } })
        let afterKeep = b.edits.count
        c.undo()
        #expect(b.edits.count == afterKeep + 1, "one local edit")
        let last = b.edits.last ?? ""
        #expect(last.contains("n_Calm") && !last.contains("mine") && !b.edits.contains("undo"))
        _ = e
    }

    @Test func undoAfterAnEditRestoresTheOldFrame() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        service.frames = ["n_New", "n_x", "n_y"]
        let (e, b) = editor(model, ["old", "n_New"])
        _ = service
        let c = DesignComposer(
            model: model, doc: Self.docID, prompt: "darker", target: .init(id: "old", name: "Home"))
        model.composer = c
        c.draw()
        #expect(await until { if case .done = c.phase { true } else { false } })
        let n = b.edits.count
        c.undo()
        let tail = Array(b.edits.dropFirst(n))
        #expect(tail.count == 2 && tail[0] == "undo" && tail[1].contains("n_New") && !tail[1].contains("old"))
        _ = e
    }

    @Test func aFlowKeepsEveryScreenAndSelectsThem() async {
        let restore = fast()
        defer { restore() }
        let (model, service) = make()
        service.flow = true
        service.frames = ["n_a", "n_b", "n_c"]
        let (e, b) = editor(model, ["n_a", "n_b", "n_c"])
        let c = DesignComposer(model: model, doc: Self.docID, prompt: "an onboarding flow")
        model.composer = c
        c.draw()
        #expect(await until { c.phase == .done("3 screens are on the canvas.") })
        #expect(b.edits.isEmpty, "nothing was dropped")
        #expect(e.selection == ["n_a", "n_b", "n_c"])
    }
}

@Suite struct EditPromptTests {
    @Test func anEditNamesTheChangeAndTheScreenWithinTheCoresLimit() {
        let many = (0..<80).map {
            EditPrompt.Element(
                kind: $0.isMultiple(of: 2) ? "text" : "rect", text: "Line \($0)", color: "#112233", size: 16,
                y: Double($0))
        }
        let p = EditPrompt.make(change: "make the button green", screen: "Checkout", elements: many)
        #expect(p.count <= 1000)
        #expect(
            p.contains("make the button green") && p.contains("\"Checkout\"")
                && p.contains("text \"Line 0\" 16pt #112233"))
        // Top to bottom, whatever order the layers came in.
        let two = EditPrompt.make(
            change: "x", screen: "S",
            elements: [
                .init(kind: "rect", text: nil, color: nil, size: nil, y: 50),
                .init(kind: "text", text: "Hi", color: nil, size: nil, y: 10),
            ])
        #expect(two.range(of: "text \"Hi\"")!.lowerBound < two.range(of: "rect")!.lowerBound)
        #expect(EditPrompt.make(change: "x", screen: "S", elements: []).contains("an empty screen"))
        // The screen's own size and kind go with the change, so a desktop stays a desktop.
        let desk = EditPrompt.make(change: "x", screen: "Home", size: CGSize(width: 1440, height: 900), elements: [])
        #expect(desk.contains("desktop screen") && desk.contains("1440×900"))
    }
}
