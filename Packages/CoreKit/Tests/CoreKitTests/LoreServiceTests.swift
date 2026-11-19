import Foundation
import Testing

@testable import CoreKit

/// The Lore routes and their shapes, as AinkradCore `feat/lore-save` (R1-01 + R1-02) serves them.
struct LoreServiceTests {
    final class Wire: @unchecked Sendable {
        let lock = NSLock()
        var sent: [(String, String, String)] = []
        var answer = Data()
    }

    static let note = """
        {"id":"ln_abcdefgh2345","kind":"daily","day":"2026-11-17","project":null,"title":"Tuesday, 17 November 2026",
         "rev":3,"created_by":"person:d_1","updated_by":"person:d_1","created_at":"x","updated_at":"x","trashed_at":null,
         "text":"# Hi\\n"}
        """

    func service(_ w: Wire) -> LiveLoreService {
        LiveLoreService(send: { m, t, b in
            w.lock.withLock {
                w.sent.append((m, t, String(decoding: b, as: UTF8.self)))
                return w.answer
            }
        })
    }

    @Test func todayAndSave() async throws {
        let w = Wire()
        w.answer = Data(Self.note.utf8)
        let n = try await service(w).today("2026-11-17")
        #expect(
            n
                == LoreNote(
                    id: "ln_abcdefgh2345", kind: "daily", day: "2026-11-17", title: "Tuesday, 17 November 2026", rev: 3,
                    text: "# Hi\n"))
        #expect(w.sent[0].0 == "GET" && w.sent[0].1 == "/modules/lore/v1/today?day=2026-11-17")

        let out = String(Self.note.dropLast()) + #","outcome":"conflict","version":"lv_x"}"#
        w.answer = Data(out.utf8)
        let r = try await service(w).save("ln_abcdefgh2345", baseRev: 2, text: "a")
        #expect(r.outcome == "conflict" && r.version == "lv_x" && r.keptVersion && r.note.rev == 3)
        #expect(w.sent[1].0 == "PUT" && w.sent[1].1 == "/modules/lore/v1/notes/ln_abcdefgh2345/text")
        #expect(w.sent[1].2.contains(#""base_rev":2"#))
    }

    @Test func dailyNeverCreates() async throws {
        let w = Wire()
        w.answer = Data("[]".utf8)
        let n = try await service(w).daily("2026-11-16")
        #expect(n == nil)
        #expect(w.sent.map(\.1) == ["/modules/lore/v1/notes?kind=daily&state=active"])
    }

    @Test func anIdNeverAddsAPath() async throws {
        let w = Wire()
        w.answer = Data(Self.note.utf8)
        _ = try await service(w).note("../x?y")
        #expect(w.sent[0].1 == "/modules/lore/v1/notes/..%2Fx%3Fy")
    }

    @Test func searchReadsHitsAndSnippets() async throws {
        let w = Wire()
        let hit =
            String(Self.note.dropLast())
            + #","score":0.1,"via":"both","heading":"Plan","snippet":{"text":"a café plan","matches":[{"start":2,"end":7}]}}"#
        w.answer = Data(#"{"results":[\#(hit)],"semantic":false}"#.utf8)
        let r = try await service(w).search(
            "caf é", filter: LoreFilter(state: "trashed", kind: "daily", project: "7", tag: "x"), limit: 30)
        #expect(
            w.sent[0].1
                == "/modules/lore/v1/search?q=caf%20%C3%A9&limit=30&state=trashed&kind=daily&project=7&tag=x")
        #expect(!r.semantic && r.hits.count == 1)
        #expect(r.hits[0].note.id == "ln_abcdefgh2345" && r.hits[0].via == "both" && r.hits[0].heading == "Plan")
        #expect(r.hits[0].snippet == LoreSnippet(text: "a café plan", matches: [LoreSpan(start: 2, end: 7)]))
    }

    @Test func listRestoreAndExport() async throws {
        let w = Wire()
        w.answer = Data("[\(Self.note)]".utf8)
        let list = try await service(w).list(filter: LoreFilter(state: "trashed", tag: "plans"))
        #expect(w.sent[0].1 == "/modules/lore/v1/notes?state=trashed&tag=plans")
        #expect(list.count == 1 && list[0].text == "# Hi\n")

        w.answer = Data(Self.note.utf8)
        _ = try await service(w).restore("ln_abcdefgh2345")
        #expect(w.sent[1].0 == "PATCH" && w.sent[1].1 == "/modules/lore/v1/notes/ln_abcdefgh2345")
        #expect(w.sent[1].2.contains(#""trashed":false"#))

        w.answer = Data([0x50, 0x4b, 0x03, 0x04])
        let zip = try await service(w).export(project: "7")
        #expect(zip == w.answer && w.sent[2].1 == "/modules/lore/v1/export?project=7")
    }

    @Test func tagsAndSessionDocs() async throws {
        let w = Wire()
        w.answer = Data(#"[{"tag":"plans","count":3}]"#.utf8)
        #expect(try await service(w).tags() == [LoreTagCount(tag: "plans", count: 3)])
        #expect(w.sent[0].1 == "/modules/lore/v1/tags")
        w.answer = Data(
            #"[{"note":"ln_abcdefgh2345","session":"as_1","path":"docs/login-plan.md","title":"Plan","session_title":"Fix the login flow","project":null,"updated_at":"x"}]"#
                .utf8)
        let d = try await service(w).sessionDocs()
        #expect(w.sent[1].1 == "/modules/lore/v1/session-docs")
        #expect(d.first?.fileName == "login-plan.md" && d.first?.sessionTitle == "Fix the login flow")
    }

    @Test func backlinksVersionsRestoreAndMove() async throws {
        let w = Wire()
        w.answer = Data(
            #"[{"note":"ln_bbbbbbbbbbbb","title":"Plot map","heading":"","context":"see [[Hi]]","project":"7","updated_at":"x"}]"#
                .utf8)
        let b = try await service(w).backlinks("ln_abcdefgh2345")
        #expect(b.first?.note == "ln_bbbbbbbbbbbb" && b.first?.project == "7")
        #expect(w.sent[0].1 == "/modules/lore/v1/notes/ln_abcdefgh2345/backlinks")

        w.answer = Data(
            #"[{"id":"lv_1","kind":"named","name":"Draft","rev":2,"origin":"system","created_at":"x"}]"#.utf8)
        let v = try await service(w).versions("ln_abcdefgh2345")
        #expect(v.first == LoreVersion(id: "lv_1", kind: "named", name: "Draft", rev: 2, createdAt: "x"))

        w.answer = Data(#"{"id":"lv_1","kind":"auto","rev":2,"origin":"system","created_at":"x","text":"old"}"#.utf8)
        #expect(try await service(w).versionText("ln_abcdefgh2345", version: "lv_1") == "old")
        #expect(w.sent[2].1 == "/modules/lore/v1/notes/ln_abcdefgh2345/versions/lv_1")

        w.answer = Data((String(Self.note.dropLast()) + #","outcome":"restored","version":"lv_2"}"#).utf8)
        let r = try await service(w).restore("ln_abcdefgh2345", version: "lv_1")
        #expect(r.outcome == "restored" && r.version == "lv_2" && !r.keptVersion)
        #expect(w.sent[3].0 == "POST" && w.sent[3].2 == #"{"version":"lv_1"}"#)

        w.answer = Data(Self.note.utf8)
        _ = try await service(w).move("ln_abcdefgh2345", project: nil)
        #expect(w.sent[4].0 == "PATCH" && w.sent[4].2 == #"{"project":null}"#)
    }
}
