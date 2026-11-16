#if DEBUG
import Foundation

/// Debug only: a room Overview on invented data (an online lighting shop that does not exist).
extension SampleBrainService: RoomOverviewService {
    public nonisolated var overviewService: (any RoomOverviewService)? { servesOverview ? self : nil }

    public func roomOverview(room: String) async throws -> RoomOverview {
        guard let state = scenario.overview else { throw BrainFailure("No overview here.", code: "not_served") }
        if roomOverviews[room] == nil {
            roomOverviews[room] = SampleOverview.make(
                state, approved: scenario.overviewApproved, stage: scenario.overviewStage,
                stageSeconds: scenario.overviewStageSeconds)
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
}

enum SampleOverview {
    static func iso(_ minutes: Int, seconds: Int = 0) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(minutes * 60 + seconds)))
    }

    /// Made-up items the rules were read from.
    static let items: [(String, String)] = [
        ("Release checklist", "note"), ("Review thread on checkout PR", "chat"), ("Deploy runbook", "doc"),
        ("Sprint 14 retro", "note"), ("CONTRIBUTING.md", "file"), ("Standup 3 Mar", "chat"),
        ("Billing design doc", "doc"), ("Hotfix for coupon rounding", "chat"),
    ]

    /// Item `s7` is the eighth title again after the list runs out: enough variety for a made-up room.
    static func title(_ id: String) -> String? {
        Int(id.dropFirst()).map { items[$0 % items.count].0 }
    }

    static func rule(_ text: String, _ n: Int) -> OverviewRule { OverviewRule(text, sources: (0..<n).map { "s\($0)" }) }

    static func make(
        _ state: OverviewState, approved: Bool, stage: OverviewStage? = nil, stageSeconds: Int = 0
    ) -> RoomOverview {
        switch state {
        case .written, .writing:
            RoomOverview(
                state: state, detail: state == .writing ? "running on build-box" : "", writtenAt: iso(-120),
                model: "claude:personal",
                progress: state == .writing ? OverviewProgress(done: 12, total: 35) : nil, overview: body,
                instructions: body.instructions, instructionsApprovedAt: approved ? iso(-60) : nil,
                sourceTitles: titles, stage: state == .writing ? stage : nil,
                stageSince: state == .writing && stage != nil
                    ? iso(-stageSeconds / 60, seconds: -stageSeconds % 60) : nil,
                picked: state == .writing && stage != nil && stage != .queued && stage != .picking ? 14 : nil)
        default:
            RoomOverview(
                state: state,
                detail: state == .failed ? "the model answered with something that is not an overview" : "")
        }
    }

    static let titles: [String: String] = Dictionary(
        uniqueKeysWithValues: (0..<14).compactMap { id in title("s\(id)").map { ("s\(id)", $0) } })

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
