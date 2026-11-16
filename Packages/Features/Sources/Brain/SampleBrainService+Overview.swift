#if DEBUG
import Foundation

/// Debug only: a room Overview on invented data (an online lighting shop that does not exist).
extension SampleBrainService: RoomOverviewService {
    public nonisolated var overviewService: (any RoomOverviewService)? { servesOverview ? self : nil }

    public func roomOverview(room: String) async throws -> RoomOverview {
        guard let state = scenario.overview else { throw BrainFailure("No overview here.", code: "not_served") }
        if roomOverviews[room] == nil {
            roomOverviews[room] = SampleOverview.make(state, approved: scenario.overviewApproved)
        }
        return roomOverviews[room]!
    }

    public func writeOverview(room: String) async throws {
        var o = try await roomOverview(room: room)
        o.state = .writing
        o.progress = OverviewProgress(done: 0, total: 35)
        roomOverviews[room] = o
        Task { await self.advance(room) }
    }

    /// Fills the bar in five steps, then files a finished overview.
    private func advance(_ room: String) async {
        for done in stride(from: 7, through: 35, by: 7) {
            try? await Task.sleep(for: pace * 2)
            roomOverviews[room]?.progress = OverviewProgress(done: done, total: 35)
        }
        roomOverviews[room] = SampleOverview.make(.written, approved: false)
    }

    public func setInstructions(room: String, text: String?, approved: Bool) async throws {
        var o = try await roomOverview(room: room)
        if let text { o.instructions = text }
        o.instructionsApprovedAt = approved ? SampleOverview.iso(-60) : nil
        roomOverviews[room] = o
    }

    public func overviewSources(room: String, ids: [String]) async throws -> [OverviewSource] {
        ids.compactMap(SampleOverview.item)
    }
}

enum SampleOverview {
    static func iso(_ minutes: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// Made-up items the rules were read from.
    static let items: [(String, String)] = [
        ("Release checklist", "note"), ("Review thread on checkout PR", "chat"), ("Deploy runbook", "doc"),
        ("Sprint 14 retro", "note"), ("CONTRIBUTING.md", "file"), ("Standup 3 Mar", "chat"),
        ("Billing design doc", "doc"), ("Hotfix for coupon rounding", "chat"),
    ]

    /// Item `s7` is the eighth title again after the list runs out: enough variety for a made-up room.
    static func item(_ id: String) -> OverviewSource? {
        guard let n = Int(id.dropFirst()) else { return nil }
        let t = items[n % items.count]
        return OverviewSource(id: id, title: t.0, type: t.1)
    }

    static func rule(_ text: String, _ n: Int) -> OverviewRule { OverviewRule(text, sources: (0..<n).map { "s\($0)" }) }

    static func make(_ state: OverviewState, approved: Bool) -> RoomOverview {
        switch state {
        case .written, .writing:
            RoomOverview(
                state: state, detail: state == .writing ? "running on build-box" : "", writtenAt: iso(-120),
                model: "claude:personal",
                progress: state == .writing ? OverviewProgress(done: 12, total: 35) : nil, overview: body,
                instructions: body.instructions, instructionsApprovedAt: approved ? iso(-60) : nil)
        default:
            RoomOverview(
                state: state,
                detail: state == .failed ? "the model answered with something that is not an overview" : "")
        }
    }

    static let body = OverviewBody(
        summary: """
            Acme Shop is an online shop for handmade lighting. A Laravel API handles catalogue, orders and payments; \
            a Next.js storefront sells to customers and a small admin lets the team manage stock.

            The team ships weekly from development. The current focus is the checkout rewrite and moving image \
            uploads to object storage. Most open questions are about tax rounding for EU orders.
            """,
        facts: OverviewFacts(
            stack: "Laravel 11, Next.js 15, PostgreSQL, Redis, Stripe",
            state: "Checkout rewrite in progress; v2.3 live",
            lastActivity: "2 days ago · hotfix for coupon rounding"),
        rules: OverviewRules(
            workflow: [
                rule("Branch from development and open a pull request for every change.", 14),
                rule("Merge with a merge commit, never squash.", 9),
                rule("Tag releases v* on main once staging passes.", 6),
                rule("Run php artisan test and npm run lint before opening a pull request.", 11),
            ],
            code: [
                rule("Laravel logic lives in app/Actions, one class per use case.", 8),
                rule("Validate input with Form Requests, never in controllers.", 5),
                rule("Next.js pages are server components; client components only for forms and charts.", 7),
                rule("Store money as integer cents.", 4),
            ],
            design: [
                rule("Use the shared Tailwind tokens; no raw hex colours.", 6),
                rule("Sentence case for labels, Title Case for buttons.", 3),
                rule("Every screen has an empty and an error state.", 5),
            ],
            never: [
                rule("Never commit .env files or API keys.", 10),
                rule("Never edit a migration that has shipped; add a new one.", 7),
                rule("Never call the payment API from the browser.", 3),
            ]),
        instructions: """
            Acme Shop is a Laravel API with a Next.js storefront. Branch from development and open a pull request for \
            every change; merge with a merge commit. Run php artisan test and npm run lint first. Keep logic in \
            app/Actions, validate with Form Requests, store money as integer cents. Never commit .env files or edit a \
            migration that has shipped.
            """)
}
#endif
