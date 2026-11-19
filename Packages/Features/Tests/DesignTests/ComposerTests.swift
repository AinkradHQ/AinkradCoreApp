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
    func compose(doc: String, prompt: String) async throws -> ComposeState {
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
        #expect(c.canDraw)
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
