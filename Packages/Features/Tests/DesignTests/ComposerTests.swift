import Foundation
import Projects
import Testing

@testable import Design

private final class ComposeService: DesignService, @unchecked Sendable {
    var reads = 0
    var started: [String] = []
    func docs() async throws -> [DesignDoc] { [] }
    func assets() async throws -> [DesignAsset] { [] }
    func kits() async throws -> [BrandKit] { [] }
    func data(_ sha: String) async throws -> Data { Data() }
    func link(_ item: DesignItem, project: String, _ on: Bool) async throws {}
    func compose(doc: String, prompt: String, count: Int, size: CGSize) async throws -> ComposeState {
        started.append(prompt)
        return ComposeState(id: "dc_1", phase: .drawing, reason: "", session: "s_1", directions: [])
    }
    func composeState(doc: String, id: String) async throws -> ComposeState {
        reads += 1
        let done = reads >= 2
        return ComposeState(
            id: id, phase: done ? .done : .drawing, reason: "", session: "s_1",
            directions: done
                ? ["Calm", "Bold", "Playful"].map { .init(name: $0, summary: "x", frame: "n_\($0)") } : [])
    }
}

@Suite("Design composer") @MainActor
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
