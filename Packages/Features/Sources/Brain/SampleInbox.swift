#if DEBUG
import Foundation

/// Debug only: the prototype's sample Inbox (brain-data.js), invented text. Lives inside `SampleBrainService`.
struct SampleInbox: Sendable {
    var candidates: [Candidate]
    var conflicts: [Conflict]
    var blocked: [BlockedNote]
    var captures: [Capture]

    init(empty: Bool) {
        if empty {
            (candidates, conflicts, blocked, captures) = ([], [], [], [])
            return
        }
        candidates = [
            Candidate(
                id: "c1", room: "ainkrad", type: .decision,
                title: "Sample: ship the Brain pane behind a Debug flag first",
                text: "Sample text. The Mac pane ships against a mock until Core serves memory routes.",
                source: "Session 2026-11-08 (sample)", by: "Claude Code (sample)", age: "12 min ago"),
            Candidate(
                id: "c2", room: "ainkrad", type: .rule, title: "Sample: pull requests target the development branch",
                text: "Sample text. Merge commits only, never squash.", source: "AGENTS.md (sample)",
                by: "Codex (sample)", age: "1 h ago"),
            Candidate(
                id: "c3", room: "ainkrad", type: .fact, title: "Sample: the Mac prototype has 11 launcher entries",
                text:
                    "Sample text with a source badge. Flagged: this line reads like an instruction (\"ignore earlier rules\").",
                source: "Imported note (sample)", by: "Import (sample)", age: "3 h ago",
                flag: "Looks like an instruction. Shown as quoted text only."),
            Candidate(
                id: "c4", room: "automotive-ai", type: .preference,
                title: "Sample: write release notes in plain sentences",
                text: "Sample text for an employer room.", source: "Chat (sample)", by: "Claude Code (sample)",
                age: "5 h ago"),
        ]
        conflicts = [
            Conflict(
                id: "k1", room: "workan-space", title: "Sample: net payment terms",
                a: ConflictSide(
                    text: "Sample: customers pay within 30 days.", source: "Contract note (sample)",
                    authority: .projectOwner, scope: "All customers", when: "Oct 2"),
                b: ConflictSide(
                    text: "Sample: customers pay within 45 days.", source: "Email summary (sample)",
                    authority: .teamMember, scope: "Enterprise", when: "Nov 3"),
                age: "2 days ago")
        ]
        blocked = [
            BlockedNote(
                id: "b1", room: "automotive-ai", title: "Sample note blocked: it contained a secret",
                ruleName: "Secret scanner", ruleAbout: "Keys and passwords are never saved in a room.",
                source: "Pasted terminal log (sample)", by: "Capture (sample)", age: "40 min ago")
        ]
        captures = [
            Capture(id: "u1", source: "Sample screenshot note from the iPhone", days: 2, guess: "Ainkrad"),
            Capture(id: "u2", source: "Sample clipboard text", days: 6, guess: "Personal"),
            Capture(id: "u3", source: "Sample meeting transcript", days: 16),
            Capture(id: "u4", source: "Sample web clip", days: 31),
        ]
    }

    /// Worst case: a thousand captures, some with very long or non-Latin sources.
    mutating func inflate() {
        let long = "Sample clip from a very long page title that keeps going well past one line of the list, again"
        for i in 5...1000 {
            let src =
                i % 7 == 0
                ? "ملاحظة عينة طويلة جداً من الهاتف رقم \(i)" : i % 3 == 0 ? "\(long) \(i)" : "Sample capture \(i)"
            captures.append(
                Capture(
                    id: "u\(i)", source: src, days: i % 40, guess: i % 5 == 0 ? "Employer engagement programme" : nil))
        }
    }

    func inbox(room: String) -> RoomInbox {
        RoomInbox(
            room: room, waiting: candidates.filter { $0.room == room }, conflicts: conflicts.filter { $0.room == room },
            blocked: blocked.filter { $0.room == room })
    }

    /// The "needs you" lines the Overview and the bell read, from what is really left.
    var needs: [NeedItem] {
        var out: [NeedItem] = []
        func add(_ kind: NeedKind, _ rooms: [String], _ text: String) {
            for id in Array(NSOrderedSet(array: rooms)) as? [String] ?? [] {
                out.append(NeedItem(kind, room: id, n: rooms.filter { $0 == id }.count, text))
            }
        }
        add(.waiting, candidates.map(\.room), "memories wait for you")
        add(.conflict, conflicts.map(\.room), "conflict to settle")
        add(.blocked, blocked.map(\.room), "note blocked: a secret was found")
        if !captures.isEmpty { out.append(NeedItem(.unclassified, n: captures.count, "captures have no room yet")) }
        return out
    }

    mutating func apply(_ action: InboxAction) {
        switch action {
        case .approve(let id, _, _, _), .reject(let id, _): candidates.removeAll { $0.id == id }
        case .keep(let id, _, _): conflicts.removeAll { $0.id == id }
        case .redact(let id, let room):
            if let b = blocked.first(where: { $0.id == id }) {
                candidates.append(
                    Candidate(
                        id: "cr-\(id)", room: room, type: .fact, title: "Redacted: sample note",
                        text: "Sample text. The secret was removed; the rest is kept.", source: b.source,
                        by: "Redaction (sample)", age: "now"))
            }
            blocked.removeAll { $0.id == id }
        case .discard(let id, _): blocked.removeAll { $0.id == id }
        case .assign(let ids, let room, let mode):
            if mode == .move {
                for c in captures where ids.contains(c.id) {
                    candidates.append(
                        Candidate(
                            id: "m-\(c.id)", room: room, type: .fact, title: "Sample: assigned capture",
                            text: "Sample text. It waits for your approval in this room.", source: c.source,
                            by: "You (sample)", age: "now"))
                }
                captures.removeAll { ids.contains($0.id) }
            }
        case .split(let id, _): captures.removeAll { $0.id == id }
        case .markPrivate(let ids), .exclude(let ids), .delete(let ids): captures.removeAll { ids.contains($0.id) }
        }
    }
}
#endif
