import CoreKit
import Foundation
import Projects
import Shell
import SwiftUI
import Testing

@testable import Design

/// Decodes as `LiveDesignService.call` does.
private func decode<T: Decodable>(_ json: String, as: T.Type = T.self) throws -> T {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return try d.decode(T.self, from: Data(json.utf8))
}

@Suite struct CollabWireTests {
    // The shapes are the Core's `CommentView`, `ApprovalView`, `DocView`, `AssetView` and `CollectionView`
    // (modules/design/api/openapi.core.json, API 1.107).
    @Test func aCommentWithAndWithoutAPin() throws {
        let c = try decode(
            """
            {"id":"dc_00000000000000a1","screen":"n_abcdefabcdef","body":"Bigger button","author":"d_01HZ",
             "created_at":"2026-11-26T10:00:00.123Z","node":"n_node","parent":null,"resolved_at":null,"x":12.5,"y":3}
            """, as: CommentWire.self
        ).comment
        #expect(c.screen == "n_abcdefabcdef" && c.node == "n_node" && c.x == 12.5 && !c.resolved && c.createdAt != nil)
        let r = try decode(
            """
            {"id":"dc_2","screen":"n_s","body":"Done","author":"session:as_1","created_at":"2026-11-26T10:01:00Z",
             "parent":"dc_00000000000000a1","resolved_at":"2026-11-26T10:05:00Z"}
            """, as: CommentWire.self
        ).comment
        #expect(r.parent == "dc_00000000000000a1" && r.resolved && r.node == nil && r.x == nil)
    }

    @Test func anApprovalKeepsAnUnknownStateAsOther() throws {
        let list = try decode(
            """
            [{"screen":"n_a","version":"dv_1","state":"approved","decided_by":"d_1","decided_at":"2026-11-26T10:00:00.000Z"},
             {"screen":"n_b","version":"dv_2","state":"changed","decided_by":"d_1","decided_at":"2026-11-26T10:00:00.000Z"},
             {"screen":"n_c","version":"dv_3","state":"sealed","decided_by":"d_1","decided_at":"2026-11-26T10:00:00.000Z"}]
            """, as: [ApprovalWire].self
        ).map(\.approval)
        #expect(list.map(\.state) == [.approved, .changed, .other])
    }

    @Test func aDocCarriesItsStateAndSystem() throws {
        let d = try decode(
            """
            {"id":"dd_1","kind":"design","name":"Checkout","state":"archived","system":"dd_9","projects":["1"],
             "ai_paused":true,"created_by":"d_1","created_at":"2026-11-26T10:00:00Z","updated_at":"2026-11-26T10:00:00Z"}
            """, as: DocWire.self
        ).doc
        #expect(d.archived && d.system == "dd_9" && d.aiPaused)
        // `state` is optional: an older Core without it is active.
        let old = try decode(
            """
            {"id":"dd_2","kind":"system","name":"S","projects":[],"ai_paused":false,"created_by":"d_1","updated_at":"2026-11-26T10:00:00Z"}
            """, as: DocWire.self
        ).doc
        #expect(!old.archived && old.system == nil)
    }

    @Test func aFolderIsKeptAndShownAsAFolder() throws {
        let k = try decode(
            """
            {"id":"dc_1","kind":"folder","name":"Pictures","colors":[],"fonts":[],"items":[{"sha256":"ab","role":null}],
             "projects":[],"created_by":"d_1","created_at":"2026-11-26T10:00:00Z","updated_at":"2026-11-26T10:00:00Z"}
            """, as: CollectionWire.self
        ).kit
        #expect(k.kind == .folder && k.items.count == 1)
        #expect(DesignItem.kit(k).category == .folders && DesignItem.kit(k).kindWord == "folder")
    }

    @Test func anUploadAnswerTellsADuplicate() throws {
        let json = """
            {"sha256":"ab","kind":"image","name":"Hero","content_type":"image/png","size":10,"check_state":"ok",
             "library":true,"tags":["a"],"projects":[],"created_by":"d_1","created_at":"2026-11-26T10:00:00Z","duplicate":true}
            """
        #expect(try decode(json, as: AssetWire.self).asset.tags == ["a"])
        struct Flag: Decodable { let duplicate: Bool? }
        #expect(try decode(json, as: Flag.self).duplicate == true)
    }

    @Test func queryEscapesEveryValue() {
        #expect(
            LiveDesignService.query([("name", "a&b c+d.png"), ("kind", nil), ("project", "1")])
                == "name=a%26b%20c%2Bd.png&project=1")
    }
}

@Suite struct LibraryRulesTests {
    private func doc(_ id: String, _ name: String, hours: Double) -> DesignItem {
        .doc(
            DesignDoc(
                id: id, kind: .design, name: name, system: nil, projects: [], aiPaused: false, createdBy: "d",
                updatedAt: Date(timeIntervalSince1970: 1_000_000 - hours * 3600)))
    }

    @Test @MainActor func sortRecentNameAndFavouritesFirst() {
        let a = doc("1", "Banana", hours: 1)
        let b = doc("2", "apple", hours: 5)
        let c = doc("3", "Cherry", hours: 3)
        let all = [a, b, c]
        #expect(
            DesignLibrary.order(all, sort: .recent, favourites: [], favouritesFirst: false).map(\.name) == [
                "Banana", "Cherry", "apple",
            ])
        #expect(
            DesignLibrary.order(all, sort: .name, favourites: [], favouritesFirst: false).map(\.name) == [
                "apple", "Banana", "Cherry",
            ])
        #expect(
            DesignLibrary.order(all, sort: .name, favourites: [c.id], favouritesFirst: true).map(\.name)
                == ["Cherry", "apple", "Banana"])
        // Favourites only lead when asked.
        #expect(
            DesignLibrary.order(all, sort: .name, favourites: [c.id], favouritesFirst: false).first?.name == "apple")
    }

    @Test @MainActor func shiftRangeRunsBothWays() {
        let ids = ["a", "b", "c", "d", "e"]
        #expect(DesignLibrary.range(in: ids, from: "b", to: "d") == ["b", "c", "d"])
        #expect(DesignLibrary.range(in: ids, from: "d", to: "b") == ["b", "c", "d"])
        #expect(DesignLibrary.range(in: ids, from: nil, to: "c") == ["c"])
    }

    @Test @MainActor func uploadsAreCheckedBeforeTheyGo() {
        #expect(DesignLibrary.uploadProblem(name: "x.png", size: 10) == nil)
        #expect(DesignLibrary.uploadProblem(name: "Inter.OTF", size: 10) == nil)
        #expect(DesignLibrary.uploadProblem(name: "x.exe", size: 10) != nil)
        #expect(DesignLibrary.uploadProblem(name: "x.png", size: 0) == "The file is empty.")
        #expect(DesignLibrary.uploadProblem(name: "x.png", size: 26 * 1024 * 1024) == "Over 25 MB.")
        #expect(DesignLibrary.uploadKind("a.svg") == "image" && DesignLibrary.uploadKind("a.ttf") == nil)
        #expect(DesignLibrary.uploadName(String(repeating: "x", count: 300)).count == 200)
    }

    @Test @MainActor func tagsFollowTheCoresLimits() {
        #expect(DesignLibrary.tags(from: " logo, dark ,logo\n,").tags == ["logo", "dark"])
        #expect(DesignLibrary.tags(from: String(repeating: "x", count: 33)).error != nil)
        let many = (1...21).map(String.init).joined(separator: ",")
        let r = DesignLibrary.tags(from: many)
        #expect(r.tags.count == 20 && r.error == "At most 20 tags.")
    }

    @Test @MainActor func kitColoursAreSixDigitHex() {
        #expect(DesignLibrary.kitColor("E3A857") == "#e3a857")
        #expect(DesignLibrary.kitColor("#E3A85780") == "#e3a857")  // the picker's alpha is dropped
        #expect(DesignLibrary.kitColor("#e3a") == nil && DesignLibrary.kitColor("blue") == nil)
    }

    @Test @MainActor func approvalBadgeSaysWhatChanged() {
        func a(_ s: ScreenApproval.State) -> ScreenApproval {
            ScreenApproval(screen: "s", version: "v", state: s, decidedBy: "d", decidedAt: nil)
        }
        #expect(DesignCollab.badge([]) == nil && DesignCollab.badge([a(.withdrawn)]) == nil)
        #expect(DesignCollab.badge([a(.approved)])?.label == "Approved")
        #expect(DesignCollab.badge([a(.approved), a(.approved)])?.label == "2 screens approved")
        #expect(DesignCollab.badge([a(.approved), a(.changed)])?.changed == true)
    }

    @Test @MainActor func repliesSitUnderTheirParent() {
        func c(_ id: String, _ parent: String?) -> DesignComment {
            DesignComment(
                id: id, screen: "s", body: id, author: "d", createdAt: nil, node: nil, parent: parent, resolvedAt: nil)
        }
        let t = DesignCollab.threads([c("1", nil), c("2", "1"), c("3", nil), c("4", "gone")])
        #expect(t.map(\.root.id) == ["1", "3", "4"] && t[0].replies.map(\.id) == ["2"])
        #expect(NewDesignComment(screen: "s", body: "  ").valid == false)
        #expect(NewDesignComment(screen: "s", body: String(repeating: "x", count: 4001)).valid == false)
    }

    @Test @MainActor func tokenNamesFollowTheCore() {
        #expect(TokenRules.isTokenName("color.brand-blue") && TokenRules.isTokenName("radius.control"))
        #expect(
            !TokenRules.isTokenName("Color.x") && !TokenRules.isTokenName("a..b") && !TokenRules.isTokenName("a-")
                && !TokenRules.isTokenName("1a"))
        let existing = [SystemToken(name: "color.primary", kind: "color", day: .string("#fff"), night: .string("#000"))]
        #expect(TokenRules.problem(short: "primary", group: .color, existing: existing) != nil)
        #expect(TokenRules.problem(short: "primary", group: .space, existing: existing) == nil)
        #expect(TokenRules.problem(short: "Bad Name", group: .color, existing: existing) != nil)
        #expect(
            TokenRules.problem(short: "primary", group: .color, existing: existing, renaming: "color.primary") == nil)
    }

    @Test @MainActor func renamingATokenIsOneBatchOfRemoveAndAdd() {
        let t = SystemToken(name: "space.md", kind: "space", day: .number(16), night: .number(16))
        let ops = TokenRules.renameOps(t, to: "space.medium")
        #expect(ops.count == 2)
        #expect(ops[0]["name"]?.string == "space.md" && ops[0]["value"] == .null)
        #expect(ops[1]["name"]?.string == "space.medium" && ops[1]["value"]?["day"]?.double == 16)
    }

    @Test @MainActor func aCopyAddsParentsBeforeChildren() {
        let layers = LayerTree([
            DesignLayer(id: "n_f", type: "frame", parent: "n_p", order: "a", name: "Home"),
            DesignLayer(id: "n_p", type: "page", parent: nil, order: "a", name: "Page"),
            DesignLayer(id: "n_t", type: "text", parent: "n_f", order: "a", name: "Hi"),
        ])
        let ops = DesignDuplicate.ops(layers: layers) { id in
            id == "n_t" ? EditorNode(id: id, type: "text", name: "Hi", props: ["x": .number(4)], text: "Hello") : nil
        }
        #expect(ops.compactMap { $0["id"]?.string } == ["n_p", "n_f", "n_t"])
        #expect(ops[0]["parent"] == .null && ops[2]["text"]?.string == "Hello" && ops[2]["props"]?["x"]?.double == 4)
    }

    @Test @MainActor func systemChoicesKeepAnArchivedLink() {
        let s = DesignDoc(
            id: "dd_s", kind: .system, name: "Calm", system: nil, projects: [], aiPaused: false, createdBy: "d")
        #expect(DocSystemPicker.options(systems: [s], current: "dd_s").map(\.value) == ["", "dd_s"])
        #expect(DocSystemPicker.options(systems: [s], current: "dd_gone").map(\.value) == ["", "dd_s", "dd_gone"])
    }
}

/// A Core that has the new routes, in memory.
final class CollabService: DesignService, @unchecked Sendable {
    private let lock = NSLock()
    var docList: [DesignDoc] = []
    var assetList: [DesignAsset] = []
    var archivedList: [DesignDoc] = []
    var searchHits: [DesignAsset] = []
    private(set) var calls: [String] = []
    private func note(_ s: String) { lock.withLock { calls.append(s) } }
    var log: [String] { lock.withLock { calls } }

    func docs() async throws -> [DesignDoc] { lock.withLock { docList } }
    func assets() async throws -> [DesignAsset] { lock.withLock { assetList } }
    func kits() async throws -> [BrandKit] { [] }
    func data(_ sha: String) async throws -> Data { Data() }
    func link(_ item: DesignItem, project: String, _ on: Bool) async throws {}
    func archivedDocs() async throws -> [DesignDoc] { archivedList }
    func unarchive(doc: String) async throws {
        note("unarchive \(doc)")
        lock.withLock { archivedList.removeAll { $0.id == doc } }
    }
    func searchAssets(_ q: String) async throws -> [DesignAsset] {
        note("search \(q)")
        return searchHits
    }
    func remove(_ item: DesignItem) async throws { note("remove \(item.id)") }
    func pauseAI(doc: String) async throws -> DesignDoc {
        note("pause \(doc)")
        var d = lock.withLock { docList.first { $0.id == doc }! }
        d.aiPaused = true
        return d
    }
    func resumeAI(doc: String) async throws -> DesignDoc {
        note("resume \(doc)")
        var d = lock.withLock { docList.first { $0.id == doc }! }
        d.aiPaused = false
        return d
    }
    func setSystem(doc: String, system: String?) async throws -> DesignDoc {
        note("system \(doc) \(system ?? "nil")")
        var d = lock.withLock { docList.first { $0.id == doc }! }
        d.system = system
        return d
    }
    func create(kind: DesignDoc.Kind, name: String, project: String?, system: String?) async throws -> DesignDoc {
        note("create \(name) system=\(system ?? "nil")")
        return DesignDoc(
            id: "dd_new", kind: kind, name: name, system: system, projects: [], aiPaused: false, createdBy: "d")
    }
}

@MainActor
private func ready(_ s: CollabService) async -> DesignModel {
    let host = FakeHost()
    let m = DesignModel(host: host, projects: ProjectsModel(host: host))
    m.use(s)
    _ = await until { m.load == .ready }
    return m
}

private func design(_ id: String, _ name: String, paused: Bool = false) -> DesignDoc {
    DesignDoc(
        id: id, kind: .design, name: name, system: nil, projects: [], aiPaused: paused, createdBy: "d",
        updatedAt: Date())
}

@MainActor
@Suite struct CollabModelTests {
    @Test func theArchivedPageLoadsAndRestoreNeedsTheCoreUpdate() async {
        let s = CollabService()
        s.archivedList = [
            DesignDoc(
                id: "dd_old", kind: .design, name: "Old", system: nil, projects: [], aiPaused: false, createdBy: "d",
                updatedAt: nil, archived: true)
        ]
        let m = await ready(s)
        #expect(m.count(.archived) == -1)  // not read until asked
        m.pick(.archived)
        #expect(await until { m.lib.archivedLoaded })
        #expect(m.items(in: .archived).map(\.name) == ["Old"] && m.count(.archived) == 1)
        await m.restore(s.archivedList[0])
        #expect(!s.log.contains { $0.hasPrefix("unarchive") })  // no restore route: it says so and calls nothing
        m.lib.restoreSupported = true
        await m.restore(s.archivedList[0])
        #expect(s.log.contains("unarchive dd_old") && m.items(in: .archived).isEmpty)
    }

    @Test func takeOverPauseAndResumeUpdateTheDesign() async {
        let s = CollabService()
        s.docList = [design("dd_1", "Checkout")]
        let m = await ready(s)
        await m.setAI(s.docList[0], .pause)
        #expect(m.doc("dd_1")?.aiPaused == true)
        await m.setAI(m.doc("dd_1")!, .resume)
        #expect(m.doc("dd_1")?.aiPaused == false && s.log == ["pause dd_1", "resume dd_1"])
    }

    @Test func linkingASystemAndUnlinkingIt() async {
        let s = CollabService()
        s.docList = [design("dd_1", "Checkout")]
        let m = await ready(s)
        await m.setSystem(s.docList[0], "dd_sys")
        #expect(m.doc("dd_1")?.system == "dd_sys")
        await m.setSystem(m.doc("dd_1")!, nil)
        #expect(m.doc("dd_1")?.system == nil && s.log.last == "system dd_1 nil")
    }

    @Test func aNewDesignCanFollowASystem() async {
        let s = CollabService()
        let m = await ready(s)
        #expect(await m.create(kind: .design, name: "X", project: nil, system: "dd_sys", toast: false) == nil)
        #expect(s.log.contains("create X system=dd_sys"))
    }

    @Test func deleteWithoutRestoreWaitsAndUndoBringsItBack() async {
        let s = CollabService()
        s.assetList = [
            DesignAsset(
                sha: "a1", kind: .logo, name: "Mark", contentType: "image/png", size: 1, check: .ok, tags: [],
                projects: [], createdAt: Date())
        ]
        let m = await ready(s)
        let item = m.items[0]
        #expect(await m.removeUndoable([item]) == nil)
        #expect(m.items.isEmpty)  // hidden while Undo is possible
        #expect(m.host.shell.undoToast())
        #expect(await until { !m.items.isEmpty })
        #expect(!s.log.contains { $0.hasPrefix("remove") })
    }

    @Test func deleteWithRestoreArchivesAtOnceAndUndoUnarchives() async {
        let s = CollabService()
        s.docList = [design("dd_1", "Checkout")]
        let m = await ready(s)
        m.lib.restoreSupported = true
        #expect(await m.removeUndoable([m.items[0]]) == nil)
        #expect(s.log == ["remove doc:dd_1"])
        #expect(m.host.shell.undoToast())
        #expect(await until { s.log.contains("unarchive dd_1") })
    }

    @Test func theFilterAsksTheCoreForFilesTheListsDoNotHold() async {
        let s = CollabService()
        s.assetList = [
            DesignAsset(
                sha: "a1", kind: .icon, name: "Cart", contentType: "image/png", size: 1, check: .ok, tags: [],
                projects: [], createdAt: Date())
        ]
        s.searchHits = [
            s.assetList[0],
            DesignAsset(
                sha: "a2", kind: .icon, name: "Cart old", contentType: "image/png", size: 1, check: .ok, tags: [],
                projects: [], createdAt: Date()),
        ]
        let m = await ready(s)
        m.filter = "ca"
        #expect(await until { m.lib.extra.count == 1 })
        #expect(Set(m.visible.map(\.name)) == ["Cart", "Cart old"])
        m.filter = ""
        #expect(m.lib.extra.isEmpty)
    }

    @Test func selectionCollectsRangesAndClears() async {
        let s = CollabService()
        s.docList = [design("dd_1", "A"), design("dd_2", "B"), design("dd_3", "C")]
        let m = await ready(s)
        let ids = m.shown.map(\.id)
        m.lib.toggle(ids[0])
        m.lib.extend(to: ids[2], in: ids)
        #expect(m.lib.multi == Set(ids))
        #expect(m.targets(m.items[1]).count == 3)
        m.lib.clearSelection()
        #expect(m.targets(m.items[1]).count == 1)
    }
}
