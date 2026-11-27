import Admin
import Foundation
import Projects
import Shell
import Testing

@testable import Design

/// The Core's real `VersionView` (openapi.core.json): `name` only on a named version, `origin` instead of `created_by`.
@MainActor
@Suite struct VersionViewTests {
    private func decode(_ json: String) throws -> [VersionWire] {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try LiveDesignService.lossy(VersionWire.self, from: Data(json.utf8), decoder: d)
    }

    @Test func theCoresVersionShapeDecodes() throws {
        let rows = try decode(
            """
            [{"id":"dv_00000000000000a1","kind":"named","name":"Before the redesign","origin":"person:d_1","created_at":"2026-11-26T10:00:00.250Z","bytes":2048},
             {"id":"dv_00000000000000a2","kind":"auto","name":null,"origin":"session:as_9","created_at":"2026-11-26T09:00:00Z","bytes":1024},
             {"id":"dv_00000000000000a3","kind":"approval","origin":"system","created_at":"2026-11-25T09:00:00Z","bytes":10}]
            """)
        #expect(rows.count == 3)
        let v = rows.map(\.version)
        #expect(v[0].name == "Before the redesign" && v[0].kind == .named && v[0].createdAt != nil)
        #expect(v[1].name.hasPrefix("Automatic save · ") && v[1].createdBy == "session:as_9")
        #expect(v[2].name.hasPrefix("Approved version") && v[2].kind == .approval)
    }

    @Test func aRowThisAppCannotReadIsSkipped() throws {
        let rows = try decode(
            #"[{"id":"x"},{"id":"dv_1","kind":"auto","origin":"system","created_at":"2026-11-26T09:00:00Z","bytes":1}]"#)
        #expect(rows.map(\.id) == ["dv_1"])
    }

    @Test func whoIsItFromTheOrigin() {
        #expect(AboutIsland.who("person:d_1", me: "d_1") == "You")
        #expect(AboutIsland.who("person:d_2", me: "d_1") == "Another device")
        #expect(AboutIsland.who("session:as_1", me: "d_1") == "An AI session")
        #expect(AboutIsland.who("system", me: "d_1") == "The Core")
    }
}

@MainActor
@Suite struct LibraryWordsTests {
    @Test func aMissingThingIsNotAMissingModule() {
        let item = LiveDesignService.failure(status: 404, code: "not_found", message: "no such comment")
        #expect(item.sentence == "no such comment")
        let bare = LiveDesignService.failure(status: 404, code: "not_found", message: "")
        #expect(!bare.sentence.contains("Design yet"))
    }

    @Test func namesFollowTheCoreRule() {
        #expect(DesignName.valid("Hello", limit: 100))
        #expect(!DesignName.valid("  ", limit: 100))
        #expect(!DesignName.valid("two\nlines", limit: 100))  // a control character inside
        #expect(DesignName.valid("name\n", limit: 100) && DesignName.clean("name\n") == "name")
        #expect(!DesignName.valid(String(repeating: "a", count: 101), limit: 100))
        #expect(DesignName.valid(String(repeating: "a", count: 200), limit: 200))
        // a family emoji is one grapheme but several scalars, and the Core counts scalars
        let family = String(repeating: "👨‍👩‍👧", count: 40)  // 40 graphemes, 200 scalars
        #expect(family.count == 40 && !DesignName.valid(family, limit: 100))
    }

    @Test func saveBadgeTellsTheTruth() {
        #expect(SaveState.of(connected: true, stuck: false, halted: false, recentEdit: false) == .saved)
        #expect(SaveState.of(connected: true, stuck: false, halted: false, recentEdit: true) == .saving)
        #expect(SaveState.of(connected: false, stuck: false, halted: false, recentEdit: true) == .reconnecting)
        #expect(SaveState.of(connected: true, stuck: true, halted: false, recentEdit: false) == .notSaving)
        #expect(SaveState.of(connected: false, stuck: false, halted: true, recentEdit: false) == .notSaving)
        #expect(SaveState.notSaving.label == "Not saving — reopen")
    }

    @Test func theIslandNeverSaysNoDesignsForACoreItCouldNotAsk() {
        #expect(DesignsIsland.unavailable(.ready) == nil)
        #expect(DesignsIsland.unavailable(.notConnected)?.contains("Not connected") == true)
        #expect(DesignsIsland.unavailable(.failed("Timed out."))?.contains("did not load") == true)
    }
}

@MainActor
@Suite struct LibraryModelTests {
    private func model(_ s: FakeService) async -> DesignModel {
        let host = FakeHost()
        let m = DesignModel(host: host, projects: ProjectsModel(host: host))
        m.use(s)
        _ = await until { m.load == .ready }
        return m
    }
    private func doc(_ id: String, _ kind: DesignDoc.Kind, _ name: String, _ p: [String] = []) -> DesignDoc {
        DesignDoc(
            id: id, kind: kind, name: name, system: nil, projects: p, aiPaused: false, createdBy: "person:d_1",
            updatedAt: Date())
    }
    private func asset(_ sha: String, _ kind: DesignAsset.Kind, _ at: TimeInterval) -> DesignAsset {
        DesignAsset(
            sha: sha, kind: kind, name: sha, contentType: "image/png", size: 1, check: .ok, tags: [], projects: [],
            createdAt: Date(timeIntervalSince1970: at))
    }

    @Test func arrowKeysFollowTheGroupedWallOnLibrary() async {
        let s = FakeService()
        // newest first would be: icon (3), logo (2), font (1); the wall groups brand, icons, illustrations, fonts
        s.assetList = [asset("font", .font, 1), asset("logo", .logo, 2), asset("icon", .icon, 3)]
        let m = await model(s)
        m.pick(.library)
        #expect(m.shown.map(\.name) == ["logo", "icon", "font"])
        m.move(1)
        m.move(1)
        #expect(m.item(m.selected)?.name == "icon")
    }

    @Test func newOnTheMockupsPageAsksWhichDesignInsteadOfMakingADraft() async {
        let s = FakeService()
        s.docList = [doc("dd_1", .design, "Checkout")]
        let m = await model(s)
        m.pick(.mockups)
        await m.quickNew()
        #expect(m.host.shell.dialog?.id == "new-design")
        #expect(!s.calls.contains { $0.hasPrefix("create") })
    }

    @Test func drawWithAIFromAnotherPageMakesADesignNotASystem() async {
        let s = FakeService()
        let m = await model(s)
        m.pick(.systems)
        await m.drawWithAI()
        #expect(s.calls.contains("create design Untitled design -"))
        #expect(!s.calls.contains { $0.hasPrefix("create system") })
    }

    @Test func aDesignEventReloadsOnlyItsList() async {
        let s = FakeService()
        let m = await model(s)
        let before = s.listCalls.count
        m.event(kind: "design.asset")
        _ = await until { s.listCalls.count > before }
        #expect(s.listCalls.dropFirst(before).allSatisfy { $0 == "assets" } && s.listCalls.count == before + 1)
        m.event(kind: "design.comment")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(s.listCalls.count == before + 1)
    }

    @Test func pageCountsFollowTheProjectChip() async {
        let s = FakeService()
        s.docList = [doc("dd_1", .design, "A", ["1"]), doc("dd_2", .design, "B", ["2"])]
        let m = await model(s)
        #expect(m.count(.screens) == 2)
        m.project = "1"
        #expect(m.count(.screens) == 1)
    }

    @Test func aFailedRefreshKeepsTheListsAndSaysSo() async {
        let s = FakeService()
        s.docList = [doc("dd_1", .design, "A")]
        let m = await model(s)
        s.fail = DesignFailure(sentence: "The Core did not answer.", code: "x", status: 500)
        await m.reload()
        #expect(m.load == .ready && m.docs.count == 1 && m.refreshFailure == "The Core did not answer.")
        s.fail = nil
        await m.reload()
        #expect(m.refreshFailure == nil)
    }

    @Test func aMissingModuleIsTheDocsListAnswering404() async {
        let s = FakeService()
        s.fail = DesignFailure(sentence: "x", code: "not_found", status: 404)
        let host = FakeHost()
        let m = DesignModel(host: host, projects: ProjectsModel(host: host))
        m.use(s)
        #expect(await until { m.load == .absent })
    }

    @Test func detachLetsGoOfTheOpenItem() async {
        let s = FakeService()
        s.docList = [doc("dd_1", .design, "A")]
        let m = await model(s)
        m.openItem("doc:dd_1")
        _ = m.editor(for: "dd_1")
        m.detach()
        #expect(m.openID == nil && m.editors.isEmpty && m.composer == nil && m.presenter == nil)
    }
}

@MainActor
@Suite struct PresentLinkTests {
    private func presenter() -> (DesignPresenter, FakeBackend, DesignModel) {
        let host = FakeHost()
        let m = DesignModel(host: host, projects: ProjectsModel(host: host))
        let d = DesignDoc(
            id: "dd_1", kind: .design, name: "D", system: nil, projects: [], aiPaused: false, createdBy: "system",
            updatedAt: nil)
        let p = DesignPresenter(model: m, doc: d, frame: nil, size: nil)
        let b = FakeBackend()
        b.treeJSON = """
            [{"id":"p","type":"page","parent":null,"order":"a","name":"Page"},
             {"id":"f1","type":"frame","parent":"p","order":"a","name":"One"},
             {"id":"f2","type":"frame","parent":"p","order":"b","name":"Two"},
             {"id":"in2","type":"text","parent":"f2","order":"a","name":"Inside"},
             {"id":"btn","type":"rect","parent":"f1","order":"a","name":"Go"},
             {"id":"dead","type":"rect","parent":"f1","order":"b","name":"Dead"},
             {"id":"deep","type":"rect","parent":"f1","order":"c","name":"Deep"}]
            """
        func node(_ id: String, _ link: String) -> String {
            #"{"id":"\#(id)","type":"rect","parent":"f1","order":"a","name":"n","props":{"link":{"to":"\#(link)"}}}"#
        }
        b.nodes["btn"] = node("btn", "f2")
        b.nodes["dead"] = node("dead", "gone")
        b.nodes["deep"] = node("deep", "in2")
        p.viewer.attach(b)
        return (p, b, m)
    }

    @Test func prevAndNextStopAtTheEnds() {
        let (p, b, _) = presenter()
        withExtendedLifetime(b) {}
        #expect(p.frames.map(\.id) == ["f1", "f2"])
        #expect(!p.canStep(-1) && p.canStep(1))
    }

    @Test func aLinkToAnInnerLayerGoesToItsScreen() {
        let (p, b, _) = presenter()
        withExtendedLifetime(b) {}
        #expect(p.screen(containing: "in2") == "f2" && p.screen(containing: "f1") == "f1")
        #expect(p.screen(containing: "nowhere") == nil)
    }

    @Test func aDeadLinkSaysSo() {
        let (p, b, m) = presenter()
        withExtendedLifetime((b, m)) {}
        p.tap("dead")
        #expect(m.host.shell.toast?.message == "That screen was removed.")
    }
}
