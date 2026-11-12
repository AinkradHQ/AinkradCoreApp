#if DEBUG
import BrainImport
import Foundation

/// Debug only: an invented Core behind the Import wizard, so the walk can open it. It reads nothing on this Mac, keeps
/// nothing on disk, and every room and count is made up.
actor SampleImportTransport: BrainTransport {
    static let run = "sample-run"
    private var cards: [ProposalCard] = [
        ProposalCard(
            id: "ainkrad", name: "Ainkrad", kind: "product", signals: ["path"], itemCount: 1412,
            sampleTitles: ["Sample: queue migration order", "Sample: runner rewrite plan"]),
        ProposalCard(
            id: "workan-space", name: "Workan space", kind: "product", signals: ["path"], itemCount: 204,
            sampleTitles: ["Sample: tenant dashboard"]),
        ProposalCard(
            id: "pricing", name: "Pricing experiments", kind: "project", itemCount: 14,
            sampleTitles: ["Sample: price page test"]),
        ProposalCard(
            id: "acme", name: "Acme", kind: "employer", warnings: ["mixed_employers"], itemCount: 38,
            sampleTitles: ["Sample: two employers in one folder"]),
        ProposalCard(id: ProposalCard.unsortedID, name: "Unsorted", kind: "unsorted", itemCount: 91),
    ]

    func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        let route = path.dropFirst(BrainRoutes.base.count).split(separator: "?")[0]
        let p = route.split(separator: "/").map(String.init)
        let e = JSONEncoder()
        switch (method, p.count, p.last ?? "") {
        case ("POST", 1, "imports"): return try e.encode(["run": Self.run])
        case ("GET", 2, _): return try e.encode(Self.view("review"))
        case ("POST", 3, "collected"): return try e.encode(Self.view("discovering"))
        case ("POST", 3, "items"): return Data(#"{"results":[]}"#.utf8)
        case ("PATCH", 3, "items"): return Data("{}".utf8)
        case ("GET", 3, "proposals"): return try e.encode(cards)
        case ("GET", 5, "items"):
            let rows = (1...3).map { ItemRow(id: "i\($0)", cursor: $0, title: "Sample item \($0)") }
            return try e.encode(ItemPage(items: rows, next: nil))
        case ("PATCH", 4, let id):
            let b = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            return try e.encode(
                update(id) { c in
                    if let s = b["state"] as? String { c.state = s }
                    if let n = b["name"] as? String { c.name = n }
                    if let k = b["kind"] as? String { c.kind = k }
                })
        case ("POST", 5, "refuse"): return try e.encode(update(p[3]) { $0.state = "refused" })
        case ("POST", 3, "commit"):
            let made = cards.filter(\.isAccepted).map {
                RoomMade(proposal: $0.id, room: $0.id, name: $0.name, kind: $0.kind, sources: 1, created: true)
            }
            return try e.encode(CommitResult(rooms: made, held: [], rulesEnabled: 0, state: "committed"))
        default:
            throw BrainHTTPError(status: 404, code: "not_found", message: "The sample has no answer for this.")
        }
    }

    private func update(_ id: String, _ change: (inout ProposalCard) -> Void) throws -> ProposalCard {
        guard let i = cards.firstIndex(where: { $0.id == id }) else {
            throw BrainHTTPError(status: 404, code: "not_found")
        }
        change(&cards[i])
        return cards[i]
    }

    private static func view(_ state: String) -> RunView {
        var c = RunCounts()
        c.found = 1759
        c.stored = 1712
        c.duplicate = 47
        return RunView(
            run: run, kind: "full", state: state, stage: state, counts: c, sources: ["claude_code", "codex"],
            startedAt: "2026-11-12T10:00:00Z")
    }
}

/// Debug only: what the wizard lists, with invented counts. Collecting reads and sends nothing.
struct SampleImportSource: ImportSource {
    let id: String
    let title: String
    let found: Int

    static let all: [any ImportSource] = [
        SampleImportSource(id: "claude_code", title: "Claude Code sessions", found: 1284),
        SampleImportSource(id: "codex", title: "Codex sessions", found: 212),
        SampleImportSource(id: "opencode", title: "OpenCode sessions", found: 37),
        NotReadableSource(
            id: "antigravity", title: "Antigravity sessions",
            reason: "Its history is kept in a format Ainkrad cannot read yet."),
    ]

    func scan() async -> CollectReport {
        var r = CollectReport()
        r.found = found
        return r
    }

    func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        var p = StreamProgress()
        p.filesDone = 1
        p.filesTotal = 1
        await onProgress(p)
        var r = CollectReport()
        r.found = found
        r.items = found
        return r
    }
}
#endif
