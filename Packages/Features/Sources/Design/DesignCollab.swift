import Foundation
import Observation

/// Comments and approvals of the designs on screen, by doc id. The open design loads both; a card on the wall asks for its
/// approvals once (for its badge). Every `design.*` event from the Core refreshes what is loaded (live).
@MainActor @Observable
final class DesignCollab {
    private(set) var comments: [String: [DesignComment]] = [:]
    private(set) var approvals: [String: [ScreenApproval]] = [:]
    /// The last refusal, in words, for the panel to show.
    private(set) var error: String?
    private(set) var busy = false
    @ObservationIgnored weak var model: DesignModel?
    @ObservationIgnored private var asked: Set<String> = []

    private var service: (any DesignService)? { model?.service }

    func reset() {
        comments = [:]
        approvals = [:]
        asked = []
        error = nil
    }

    // MARK: reads

    /// Both lists of an open design.
    func load(_ doc: String) async {
        guard let service else { return }
        async let c = try? service.comments(doc: doc)
        async let a = try? service.approvals(doc: doc)
        if let c = await c { comments[doc] = c }
        if let a = await a {
            approvals[doc] = a
            asked.insert(doc)
        }
    }

    /// A card's badge asks once per design.
    func loadApprovalsOnce(_ doc: String) async {
        guard let service, !asked.contains(doc) else { return }
        asked.insert(doc)
        if let a = try? await service.approvals(doc: doc) { approvals[doc] = a }
    }

    /// A `design.*` event: what is loaded is read again.
    func refresh() {
        let loaded = Set(comments.keys).union(approvals.keys)
        for d in loaded { Task { await load(d) } }
    }

    // MARK: derived

    func open(_ doc: String) -> [DesignComment] { (comments[doc] ?? []).filter { !$0.resolved } }
    func openCount(_ doc: String) -> Int { open(doc).filter { $0.parent == nil }.count }
    func approval(_ doc: String, screen: String) -> ScreenApproval? {
        approvals[doc]?.first { $0.screen == screen && $0.state != .withdrawn }
    }

    /// The card's badge words, nil when nothing was ever approved.
    func badge(_ doc: String) -> (label: String, changed: Bool)? {
        Self.badge(approvals[doc] ?? [])
    }

    static func badge(_ list: [ScreenApproval]) -> (label: String, changed: Bool)? {
        let live = list.filter { $0.state == .approved || $0.state == .changed }
        guard !live.isEmpty else { return nil }
        let changed = live.filter { $0.state == .changed }.count
        if changed > 0 { return ("\(changed) changed since approved", true) }
        return (live.count == 1 ? "Approved" : "\(live.count) screens approved", false)
    }

    /// Replies sit under their parent, oldest first; a reply whose parent is not in the list is shown as its own note.
    static func threads(_ list: [DesignComment]) -> [(root: DesignComment, replies: [DesignComment])] {
        let ids = Set(list.map(\.id))
        let roots = list.filter { $0.parent == nil || !ids.contains($0.parent!) }
        return roots.map { r in (r, list.filter { $0.parent == r.id }) }
    }

    // MARK: writes

    private func run(_ doc: String, _ work: (any DesignService) async throws -> Void) async -> Bool {
        guard let service, let model else { return false }
        if model.readOnly {
            error = "This device can look at designs but not change them."
            return false
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work(service)
            await load(doc)
            return true
        } catch {
            self.error = model.words(error)
            return false
        }
    }

    func post(doc: String, _ new: NewDesignComment) async -> Bool {
        var n = new
        n.body = new.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return await run(doc) { _ = try await $0.postComment(doc: doc, n) }
    }
    func resolve(doc: String, id: String, _ resolved: Bool) async {
        _ = await run(doc) { try await $0.resolveComment(doc: doc, id: id, resolved: resolved) }
    }
    func approve(doc: String, screen: String) async {
        _ = await run(doc) { try await $0.approve(doc: doc, screen: screen) }
    }
    func withdraw(doc: String, screen: String) async {
        _ = await run(doc) { try await $0.withdrawApproval(doc: doc, screen: screen) }
    }
}
