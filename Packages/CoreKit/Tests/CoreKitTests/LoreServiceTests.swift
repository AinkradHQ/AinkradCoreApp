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
}
