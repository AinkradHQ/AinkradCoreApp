import Admin
import CoreKit
import Foundation
import Projects
import Shell
import Testing

@testable import Design

@MainActor
final class FakeHost: AdminHost {
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    func clearElevationNotice() { elevationNotice = nil }
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        try await op()
    }
    func rateLimited(retryAfter: TimeInterval?) {}
}

/// An in-memory Core: records what the model asked.
final class FakeService: DesignService, @unchecked Sendable {
    private let lock = NSLock()
    var docList: [DesignDoc] = []
    var assetList: [DesignAsset] = []
    var kitList: [BrandKit] = []
    var fail: DesignFailure?
    private(set) var calls: [String] = []
    func docs() async throws -> [DesignDoc] {
        if let fail { throw fail }
        return lock.withLock { docList }
    }
    func assets() async throws -> [DesignAsset] { lock.withLock { assetList } }
    func kits() async throws -> [BrandKit] { lock.withLock { kitList } }
    func data(_ sha: String) async throws -> Data {
        lock.withLock { calls.append("data \(sha)") }
        return Data()
    }
    func link(_ item: DesignItem, project: String, _ on: Bool) async throws {
        lock.withLock {
            calls.append("\(on ? "link" : "unlink") \(item.id) \(project)")
            if case .doc(let d) = item, let i = docList.firstIndex(where: { $0.id == d.id }) {
                docList[i].projects = on ? [project] : []
            }
        }
    }
}

private func doc(_ id: String, _ kind: DesignDoc.Kind, _ name: String, _ p: [String] = [], system: String? = nil)
    -> DesignDoc
{
    DesignDoc(
        id: id, kind: kind, name: name, system: system, projects: p, aiPaused: false, createdBy: "device:d_1",
        updatedAt: Date())
}

private func asset(
    _ sha: String, _ kind: DesignAsset.Kind, _ name: String, check: DesignAsset.Check = .ok,
    tags: [String] = [], type: String = "image/png"
) -> DesignAsset {
    DesignAsset(
        sha: sha, kind: kind, name: name, contentType: type, size: 10, check: check, tags: tags, projects: ["1"],
        createdAt: Date())
}

@MainActor
private func ready(_ s: FakeService) async -> DesignModel {
    let host = FakeHost()
    let m = DesignModel(host: host, projects: ProjectsModel(host: host))
    m.use(s)
    _ = await until { m.load == .ready }
    return m
}

@MainActor
@Suite struct DesignModelTests {
    @Test func categoriesSortEveryKindIntoItsRow() async {
        let s = FakeService()
        s.docList = [
            doc("dd_1", .design, "Checkout"), doc("dd_2", .system, "Calm"), doc("dd_3", .mockup, "Gallery v3"),
        ]
        s.assetList = [
            asset("a1", .logo, "Mark"), asset("a2", .iconComposer, "App icon", check: .pending),
            asset("a3", .icon, "Cart"), asset("a4", .image, "Scene"), asset("a5", .font, "Serif", check: .pending),
        ]
        s.kitList = [BrandKit(id: "dc_1", name: "Kit", colors: ["#112233"], fonts: [], items: [], projects: [])]
        let m = await ready(s)
        #expect(m.items(in: .screens).map(\.name) == ["Checkout"])
        #expect(m.items(in: .systems).map(\.name) == ["Calm"])
        #expect(m.items(in: .mockups).map(\.name) == ["Gallery v3"])
        #expect(Set(m.items(in: .brand).map(\.name)) == ["Mark", "Kit"])
        #expect(Set(m.items(in: .icons).map(\.name)) == ["App icon", "Cart"])
        #expect(m.items(in: .illustrations).map(\.name) == ["Scene"])
        #expect(m.items(in: .fonts).map(\.name) == ["Serif"])
        #expect(m.count(.all) == 9)
        // Review and AI drawing are later stories: nothing claims to need you yet.
        #expect(m.count(.needsYou) == 0 && m.count(.drawing) == 0)
    }

    @Test func filterMatchesNamesKindsAndTags() async {
        let s = FakeService()
        s.docList = [doc("dd_1", .design, "Lanterna checkout", ["1"]), doc("dd_2", .design, "Onboarding", ["2"])]
        s.assetList = [asset("a1", .icon, "Cart", tags: ["checkout"])]
        let m = await ready(s)
        m.filter = "checkout"
        #expect(Set(m.visible.map(\.name)) == ["Lanterna checkout", "Cart"])
        m.filter = "  "
        m.project = "2"
        #expect(m.visible.map(\.name) == ["Onboarding"])
        #expect(m.linked(to: "1").count == 2)
    }

    @Test func theRailSelectsOneRowAtATime() async {
        let s = FakeService()
        s.docList = [doc("dd_1", .design, "Checkout", ["1"]), doc("dd_2", .system, "Calm", ["2"])]
        let m = await ready(s)
        m.pick(.systems)
        m.pickProject("1")
        #expect(m.project == "1" && m.category == .all)
        #expect(m.items(in: .all).map(\.name) == ["Checkout"])
        // Category counts say what picking them shows, whatever project is selected.
        #expect(m.count(.systems) == 1)
        m.pick(.screens)
        #expect(m.project == nil)
    }

    @Test func shortSectionsStretchAcrossTheRow() {
        // 1,648 pt fits six 256 pt columns.
        #expect(DesignWall.columns(for: 2, width: 1648).count == 2)
        #expect(DesignWall.columns(for: 1, width: 1648).count == 2)
        #expect(DesignWall.columns(for: 9, width: 1648).count == 6)
        #expect(DesignWall.columns(for: 3, width: 200).count == 1)
    }

    @Test func fontsAndUncheckedFilesAreNeverFetched() async {
        let s = FakeService()
        let font = asset("f1", .font, "Serif", check: .ok, type: "font/ttf")
        let pending = asset("p1", .iconComposer, "Icon", check: .pending)
        let refused = asset("r1", .image, "Bad", check: .refused)
        s.assetList = [font, pending, refused]
        let m = await ready(s)
        for a in [font, pending, refused] { await m.loadImage(a) }
        #expect(s.calls.isEmpty)
        #expect(!font.loadable && !pending.loadable && !refused.loadable)
    }

    @Test func linkingWritesAndReloads() async {
        let s = FakeService()
        s.docList = [doc("dd_1", .design, "Checkout")]
        let m = await ready(s)
        guard let item = m.items.first else { return #expect(Bool(false)) }
        await m.setLink(item, project: ProjectRef(id: "4", name: "Harbor"), true)
        #expect(s.calls == ["link doc:dd_1 4"])
        #expect(m.docs.first?.projects == ["4"])
    }

    @Test func aCoreWithoutTheModuleSaysSo() async {
        let s = FakeService()
        s.fail = DesignFailure(sentence: "x", code: "not_found", status: 404)
        let host = FakeHost()
        let m = DesignModel(host: host, projects: ProjectsModel(host: host))
        m.use(s)
        #expect(await until { m.load == .absent })
    }

    @Test func onlyDesignEventsReload() async {
        let host = FakeHost()
        let m = DesignModel(host: host, projects: ProjectsModel(host: host))
        m.event(kind: "project.changed")
        #expect(m.load == .notConnected)
    }

    @Test func installsTheProjectIsland() {
        let host = FakeHost()
        let projects = ProjectsModel(host: host)
        _ = DesignModel(host: host, projects: projects)
        #expect(projects.designsIsland != nil)
    }
}

@Suite struct DesignWireTests {
    @Test func decodesTheCoreShapes() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let doc = try d.decode(
            DocWire.self,
            from: Data(
                #"{"id":"dd_00000000000000a1","kind":"system","name":"Calm","state":"active","system":null,"projects":["3"],"ai_paused":true,"created_by":"device:d_1","created_at":"2026-11-17T10:00:00Z","updated_at":"2026-11-17T11:00:00.123Z"}"#
                    .utf8)
        ).doc
        #expect(doc.kind == .system && doc.aiPaused && doc.projects == ["3"] && doc.updatedAt != nil)
        let a = try d.decode(
            AssetWire.self,
            from: Data(
                #"{"sha256":"ab","kind":"icon_composer","name":"Icon","content_type":"application/zip","size":12,"check_state":"pending","library":true,"tags":["app"],"projects":[],"created_by":"x","created_at":"2026-11-17T10:00:00Z"}"#
                    .utf8)
        ).asset
        #expect(a.kind == .iconComposer && a.check == .pending && a.fileName == "Icon.icon.zip")
        let k = try d.decode(
            CollectionWire.self,
            from: Data(
                ##"{"id":"dc_1","kind":"brand_kit","name":"Kit","colors":["#2b2520"],"fonts":["ff"],"items":[{"sha256":"ab","role":"logo"}],"projects":["1"],"created_by":"x","created_at":"2026-11-17T10:00:00Z","updated_at":"2026-11-17T10:00:00Z"}"##
                    .utf8)
        ).kit
        #expect(k.items.first?.role == "logo" && k.fonts == ["ff"])
    }

    @Test func pathSegmentsCannotEscape() {
        #expect(LiveDesignService.seg("a/b?c#d") == "a%2Fb%3Fc%23d")
    }

    @Test func swatchReadsOnlyRealHex() {
        #expect(Swatch.color("#2b2520") != nil)
        #expect(Swatch.color("red") == nil)
        #expect(Swatch.color("#12345") == nil)
    }

    @Test func iconBundleIsFoundWithoutFollowingLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("icon-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("Lamp.icon/Assets"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("Lamp.icon/icon.json"))
        #expect(IconComposerPreview.iconBundle(in: root)?.lastPathComponent == "Lamp.icon")
        #expect(IconComposerPreview.firstLayer(in: root.appendingPathComponent("Lamp.icon")) == nil)
    }
}
