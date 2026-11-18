import Foundation
import Testing

@testable import CoreKit

/// The import routes and their shapes, as AinkradCore R4-01 serves them.
struct LoreImportServiceTests {
    final class Wire: @unchecked Sendable {
        let lock = NSLock()
        var sent: [(String, String, Data)] = []
        var answer = Data()
    }

    static let run = """
        {"id":"li_abcdefghijkl","source":"mirror","project":"7","repo":"3","state":"review","items":5,"include":4,
         "refused":1,"ignored":2,"error":null,"flags":{"conflict":1,"too_large":1},"results":{},"undone":0,"kept":0,
         "created_by":"person:d_1","created_at":"2026-11-18T10:00:00.000Z","updated_at":"x","committed_at":null}
        """

    func service(_ w: Wire) -> LiveLoreService {
        LiveLoreService(send: { m, t, b in
            w.lock.withLock {
                w.sent.append((m, t, b))
                return w.answer
            }
        })
    }

    @Test func aRunReadsItsCounts() async throws {
        let w = Wire()
        w.answer = Data(Self.run.utf8)
        let r = try await service(w).startImport(repo: true, project: "7")
        #expect(r.id == "li_abcdefghijkl" && r.state == "review" && r.include == 4 && r.refused == 1 && r.ignored == 2)
        // The Core's `too_large` key arrives camelCased.
        #expect(r.flags == ["conflict": 1, "tooLarge": 1] && r.fresh == 3)
        #expect(w.sent[0].0 == "POST" && w.sent[0].1 == "/modules/lore/v1/imports")
        #expect(String(decoding: w.sent[0].2, as: UTF8.self).contains(#""source":"mirror""#))
    }

    @Test func anUploadRunNamesNoProjectWhenPersonal() async throws {
        let w = Wire()
        w.answer = Data(Self.run.utf8)
        _ = try await service(w).startImport(repo: false, project: nil)
        let body = String(decoding: w.sent[0].2, as: UTF8.self)
        #expect(body.contains(#""source":"upload""#) && !body.contains("project"))
    }

    @Test func uploadsGoToTheRunsRoutes() async throws {
        let w = Wire()
        w.answer = Data(Self.run.utf8)
        let s = service(w)
        _ = try await s.addImportFiles("li_abcdefghijkl", [LoreImportFile(path: "a.md", text: "# A")])
        _ = try await s.addImportZip("li_abcdefghijkl", Data([0x50, 0x4b, 0x03, 0x04]))
        _ = try await s.finishImport("li_abcdefghijkl")
        #expect(
            w.sent.map(\.1) == [
                "/modules/lore/v1/imports/li_abcdefghijkl/items", "/modules/lore/v1/imports/li_abcdefghijkl/zip",
                "/modules/lore/v1/imports/li_abcdefghijkl/finish",
            ])
        #expect(String(decoding: w.sent[0].2, as: UTF8.self) == ##"{"items":[{"path":"a.md","text":"# A"}]}"##)
        #expect(w.sent[1].2 == Data([0x50, 0x4b, 0x03, 0x04]))
    }

    @Test func movingToPersonalSendsNull() async throws {
        let w = Wire()
        w.answer = Data(Self.run.utf8)
        _ = try await service(w).moveImportItems("li_abcdefghijkl", seqs: [], project: nil)
        _ = try await service(w).markImportItems("li_abcdefghijkl", seqs: [2], include: false)
        #expect(w.sent[0].0 == "PATCH")
        #expect(String(decoding: w.sent[0].2, as: UTF8.self).contains(#""project":null"#))
        #expect(String(decoding: w.sent[1].2, as: UTF8.self).contains(#""mark":"skip""#))
    }

    @Test func itemsReadTheirFlagAndMark() async throws {
        let w = Wire()
        w.answer = Data(
            #"[{"seq":1,"path":"plans/a.md","title":"A","tags":["x"],"project":null,"flag":"too_large","mark":"skip","match_note":null,"result":null}]"#
                .utf8)
        let items = try await service(w).importItems("li_abcdefghijkl", after: 0, limit: 500)
        #expect(
            items.first
                == LoreImportItem(seq: 1, path: "plans/a.md", title: "A", tags: ["x"], flag: "too_large", mark: "skip"))
        #expect(items[0].locked)
        #expect(w.sent[0].1 == "/modules/lore/v1/imports/li_abcdefghijkl/items?after=0&limit=500")
    }

    @Test func aRunIdNeverAddsAPath() async throws {
        let w = Wire()
        w.answer = Data(Self.run.utf8)
        _ = try await service(w).commitImport("../x?y")
        #expect(w.sent[0].1 == "/modules/lore/v1/imports/..%2Fx%3Fy/commit")
    }
}
