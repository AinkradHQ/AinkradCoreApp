#if DEBUG
import BrainImport
import Foundation

/// Debug only: an invented Core behind the Import wizard, so the walk can open it. It reads nothing on this Mac, keeps
/// nothing on disk, and every room and count is made up.
actor SampleImportTransport: BrainTransport {
    static let run = "sample-run"
    /// The local AI's step for this run: `pending`, `ready` or `off`.
    private let semantic: String
    private var state: String { semantic }
    private var settings: [String: Int] = [
        "semantic.enabled": 1, "semantic.strength": 1, "semantic.threads": 1, "semantic.max_tokens": 128,
    ]

    init(semantic: String = "off") { self.semantic = semantic }

    /// Made-up work of the local AI: what it tidied by itself, applied until Undo.
    private var undone = false
    static let sampleTidy = TidySummary(
        duplicatesMerged: 9, roomsMerged: 1, roomsFolded: 3, itemsMoved: 2, roomsBefore: 10, roomsAfter: 6)
    static let sampleChanges = [
        TidyChange(kind: "duplicate", itemIds: ["k1a", "k1b", "k1c", "k1d"], to: "k1"),
        TidyChange(kind: "duplicate", itemIds: ["k2a", "k2b", "k2c"], to: "k2"),
        TidyChange(kind: "duplicate", itemIds: ["k3a", "k3b"], to: "k3"),
        TidyChange(kind: "merge", from: "shop-admin", fromName: "Shop admin", to: "acme-shop", toName: "Acme Shop"),
        TidyChange(kind: "fold", from: "garden", fromName: "Garden notes", to: "unsorted", toName: "Unsorted"),
        TidyChange(
            kind: "fold", from: "pv", fromName: "Price page variant", to: "pricing", toName: "Pricing experiments"),
        TidyChange(kind: "fold", from: "osa", fromName: "Old shop api", to: "acme-shop", toName: "Acme Shop"),
        TidyChange(kind: "move", itemIds: ["m1"], from: "unsorted", to: "acme-shop", toName: "Acme Shop"),
        TidyChange(kind: "move", itemIds: ["m2"], from: "unsorted", to: "pricing", toName: "Pricing experiments"),
    ]
    static let sampleTitles = [
        "k1": "Sample: queue migration order", "k2": "Sample: runner rewrite plan", "k3": "Sample: tenant dashboard",
        "m1": "Sample: checkout tax settings", "m2": "Sample: price page test B",
    ]
    private var cards: [ProposalCard] = [
        ProposalCard(
            id: "ainkrad", name: "Ainkrad", kind: "product", signals: ["path"], itemCount: 1412,
            sampleTitles: ["Sample: queue migration order", "Sample: runner rewrite plan"]),
        ProposalCard(
            id: "acme-shop", name: "Acme Shop", kind: "product", signals: ["path"], itemCount: 204,
            sampleTitles: ["Sample: tenant dashboard"]),
        ProposalCard(
            id: "pricing", name: "Pricing experiments", kind: "project", itemCount: 14,
            sampleTitles: ["Sample: price page test"]),
        ProposalCard(
            id: "acme-shop-api", name: "AcmeShopApi", kind: "product", signals: ["path"], itemCount: 9,
            sampleTitles: ["Sample: tenant dashboard api"],
            suggestMerge: MergeSuggestion(into: "acme-shop", name: "Acme Shop", reason: "prefix")),
        ProposalCard(
            id: "pricing-experiment", name: "Pricing experiment", kind: "project", itemCount: 5,
            sampleTitles: ["Sample: price page variant"],
            suggestMerge: MergeSuggestion(into: "pricing", name: "Pricing experiments", reason: "close")),
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
        case ("PATCH", 3, "items"):
            let b = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            let ids = Set(b["ids"] as? [String] ?? [])
            if let to = b["proposal"] as? String { _ = try? update(to) { $0.itemCount += ids.count } }
            return Data("{}".utf8)
        case ("GET", 3, "proposals"):
            let tagged = cards.map { c -> ProposalCard in
                var c = c
                c.semantic = state
                return c
            }
            return try e.encode(tagged)
        case ("GET", 3, "semantic"): return try e.encode(semanticView())
        case ("GET", 4, "changes"):
            return try e.encode(TidyChanges(changes: undone || state != "ready" ? [] : Self.sampleChanges))
        case ("POST", 4, "undo"):
            undone = true
            return try e.encode(semanticView())
        case ("GET", 1, "settings"):
            return try e.encode(
                settings.sorted { $0.key < $1.key }.map {
                    BrainSettingWire(name: $0.key, value: $0.value, default: 1, min: 0, max: 2, description: "")
                })
        case ("PUT", 2, _):
            let b = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            settings[p[1]] = b["value"] as? Int ?? settings[p[1]]
            return try e.encode(
                BrainSettingWire(name: p[1], value: settings[p[1]] ?? 0, default: 1, min: 0, max: 2, description: ""))
        case ("POST", 5, "split"):
            let b = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            let ids = b["item_ids"] as? [String] ?? []
            let name = b["name"] as? String ?? "New room"
            let made = ProposalCard(
                id: name.lowercased().replacingOccurrences(of: " ", with: "-"), name: name, kind: "project",
                itemCount: ids.count)
            cards.insert(made, at: max(cards.count - 1, 0))
            _ = try update(p[3]) { $0.itemCount -= ids.count }
            return try e.encode(made)
        case ("GET", 5, "items"):
            var rows = (1...3).map { ItemRow(id: "i\($0)", cursor: $0, title: "Sample item \($0)") }
            rows += Self.sampleTitles.sorted { $0.key < $1.key }.enumerated().map {
                ItemRow(id: $1.key, cursor: 10 + $0, title: $1.value)
            }
            if p[3] == ProposalCard.unsortedID {
                rows += [
                    ItemRow(id: "c1", cursor: 4, title: "Checkout page: tenant-level tax settings"),
                    ItemRow(id: "c2", cursor: 5, title: "Pruning the old apple trees in spring"),
                    ItemRow(id: "c3", cursor: 6, title: "Variant B of the pricing page"),
                ]
            }
            return try e.encode(ItemPage(items: rows, next: nil))
        case ("PATCH", 4, let id):
            let b = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            return try e.encode(
                update(id) { c in
                    if let s = b["state"] as? String { c.state = s }
                    if let n = b["name"] as? String { c.name = n }
                    if let k = b["kind"] as? String { c.kind = k }
                })
        case ("POST", 3, "regroup"):
            return try e.encode(Regrouped(proposals: cards.count, kept: cards.count, dropped: 0))
        case ("POST", 5, "merge"):
            let b = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            let into = b["into"] as? String ?? ""
            let moved = cards.first { $0.id == p[3] }?.itemCount ?? 0
            cards.removeAll { $0.id == p[3] }
            return try e.encode(update(into) { $0.itemCount += moved })
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

    private func semanticView() -> SemanticView {
        var v = SemanticView(state: state)
        if state == "pending" { v.progress = SemanticProgress(done: 1240, total: 2980) }
        if state == "ready" { v.aiTidy = AiTidy(state: undone ? "undone" : "applied", summary: Self.sampleTidy) }
        return v
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
        SampleImportSource(id: "antigravity", title: "Antigravity sessions", found: 18),
    ]

    /// Sessions plus the Notes and docs kinds, whose counts follow what `places` is set to (invented numbers).
    static func withNotes(_ places: ImportPlaces) -> [any ImportSource] {
        all + [
            SampleNotesSource(id: "doc", title: "Project docs", perFolder: 42, wholeDisk: 318, places: places),
            SampleNotesSource(
                id: "vault", title: "Notes (Obsidian vaults)", perFolder: 0, wholeDisk: 126, places: places),
            SampleNotesSource(
                id: "agents_md", title: "AGENTS.md, CLAUDE.md and README files", perFolder: 9, wholeDisk: 74,
                places: places),
            SampleNotesSource(id: "chat", title: "Chat exports", perFolder: 0, wholeDisk: 0, places: places),
        ]
    }

    /// A made-up Mac: two folders chosen, two suggested, and a whole-disk search that counts up and finishes. Reads nothing.
    static func demoPlaces(_ mode: ImportPlaces.Mode, endless: Bool = false) -> ImportPlaces {
        let base = URL(fileURLWithPath: "/Users/sample")
        return ImportPlaces(
            mode: mode,
            folders: [base.appending(path: "Work/Shop Docs"), base.appending(path: "Studio")],
            search: { progress in
                // `endless` stays at a count until stopped, so the walk can show the live line.
                for n in stride(from: 1000, through: endless ? 0 : 48000, by: 12000) {
                    progress(n)
                    Thread.sleep(forTimeInterval: 0.02)
                }
                while endless && !Task.isCancelled {
                    progress(1240)
                    Thread.sleep(forTimeInterval: 0.05)
                }
                var f = DocWalker.Found()
                f.checked = endless ? 1240 : 48210
                f.stopped = endless ? "cancelled" : nil
                f.docFolders = ["/Users/sample/Work/Shop/Docs"]
                return f
            },
            suggest: { taken in
                [base.appending(path: "Code/Client Sites"), base.appending(path: "Notes Vault")].filter { s in
                    !taken.contains { $0.path == s.path }
                }
            })
    }

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

/// Debug only: a Notes and docs source with invented counts that follow the Where to look choice.
struct SampleNotesSource: ImportSource {
    let id: String
    let title: String
    let perFolder: Int
    let wholeDisk: Int
    let places: ImportPlaces

    func scan() async -> CollectReport {
        var r = CollectReport()
        if id == "chat" {
            r.found = places.chat == nil ? 0 : 6
        } else {
            r.found = places.mode == .disk ? wholeDisk : perFolder * places.folders.count
            if r.found > 20 { r.skipped = ["restricted": 2, "deprecated:Sample": 3] }
        }
        return r
    }

    func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport { CollectReport() }
}
#endif
