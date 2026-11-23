#if DEBUG
import Foundation

/// Debug only: the Brain redesign on invented data, as a Core with API minor 101 would answer, and a walk through every
/// page of it. Every name, sentence and number is made up (the places are the sample's).
extension BrainDemo {
    static let walk = [
        "calm-me", "calm-me-full", "calm-rules", "calm-knowledge", "calm-knowledge-ask", "calm-knowledge-topic",
        "calm-timeline", "calm-places", "calm-place", "calm-inbox", "calm-sources", "calm-activity", "calm-search",
    ]

    func showWalk(_ scene: String) async {
        showRedesign(learning: false, drop: false)
        // `show` starts Home loading on its own task; let it land before moving on.
        try? await Task.sleep(for: .milliseconds(450))
        patchChecks()
        let calm = model.calm
        switch scene {
        case "calm-places":
            model.placeOpen = false
            model.go(.rooms)
        case "calm-place":
            model.go(.rooms)
            model.view("acme-shop")
            await model.inspect("acme-shop")
            await model.candidates.loadPolicy("acme-shop")
            model.candidates.paneMode = .overview
            await model.roomOverview.open("acme-shop")
        case "calm-inbox": model.go(.inbox)
        case "calm-sources": model.go(.sources)
        case "calm-activity": model.go(.activity)
        case "calm-search":
            calm.query = "sync"
            model.go(.records)
            calm.picked = "k1"
        case "calm-me-full":
            calm.demoRecords["me"] = Self.me
            model.go(.me)
        case "calm-knowledge-ask":
            model.go(.knowledge)
            try? await Task.sleep(for: .milliseconds(50))
            calm.question = "How do Acme Shop releases work?"
            await calm.ask()
        case "calm-knowledge-topic":
            model.go(.knowledge)
            try? await Task.sleep(for: .milliseconds(50))
            await calm.openTopic(Self.topics[0])
        default:
            let t = BrainTab(rawValue: String(scene.dropFirst("calm-".count))) ?? .me
            model.go(t)
            try? await Task.sleep(for: .milliseconds(50))
            if t == .rules { calm.picked = "r1" }
        }
    }

    /// The redesign's Home on invented data: at rest, or learning from Acme Shop; `drop` opens the dropdown over it.
    func showRedesign(learning: Bool, drop: Bool) {
        func ago(_ s: Double) -> String { ISO8601DateFormatter().string(from: Date().addingTimeInterval(-s)) }
        func area(_ a: String, _ n: Int, _ today: Int, _ latest: String?, _ s: [Int]) -> BrainAreasWire.Summary {
            .init(area: a, count: n, today: today, latest: latest, series: s)
        }
        var areas = BrainAreasWire(
            areas: [
                area(
                    "knowledge", 15_824, 212, "Acme Shop releases ship as a signed .dmg, built on the release box.",
                    [20, 40, 30, 80, 60, 180, 200, 140, 100, 70, 60, 40, 50, 212]),
                area(
                    "rules", 270, 6, "Ask before deleting anything outside the project folder.",
                    [1, 1, 2, 3, 1, 5, 6, 4, 2, 2, 1, 2, 1, 6]),
                area(
                    "timeline", 156, 4, "Initech API 2.4 went live on Thursday after the login fix.",
                    [1, 1, 1, 2, 2, 3, 4, 4, 3, 2, 2, 1, 1, 4]),
                area("me", 0, 0, nil, Array(repeating: 0, count: 14)),
            ], places: 8, evidence: 15_000, lockedRooms: 0)
        areas.ruleKinds = .init(always: 142, never: 88, prefer: 40)
        let learned: [LearnedWire] = [
            .init(
                id: "l1", room: "acme-shop", roomName: "Acme Shop", type: "fact", area: "knowledge",
                body: "Acme Shop releases ship as a signed .dmg", createdAt: ago(720)),
            .init(
                id: "l2", room: "northwind", roomName: "Northwind", type: "rule", area: "rules",
                body: "Do not add new libraries without asking", createdAt: ago(2_400)),
            .init(
                id: "l3", room: "initech", roomName: "Initech", type: "project-state", area: "timeline",
                body: "Initech API 2.4 went live after the login fix", createdAt: ago(7_200)),
            .init(
                id: "l4", room: "northwind", roomName: "Northwind", type: "decision", area: "knowledge",
                body: "Keep the old login screen until the new one is tested", createdAt: ago(10_800)),
            .init(
                id: "l5", room: "hooli", roomName: "Hooli", type: "fact", area: "knowledge",
                body: "Hooli builds run on the attic box", createdAt: ago(18_000)),
        ]
        func place(_ id: String, _ name: String, _ k: Int, _ r: Int, _ t: Int, _ s: Double, live: Bool = false)
            -> PlaceWire
        {
            .init(
                room: id, name: name, knowledge: k, rules: r, timeline: t, lastLearnedAt: ago(s),
                learning: learning && live, locked: false)
        }
        let places = [
            place("acme-shop", "Acme Shop", 6_120, 92, 48, 720, live: true),
            place("initech", "Initech", 3_480, 61, 31, 7_200), place("globex", "Globex", 2_210, 38, 22, 90_000),
            place("northwind", "Northwind", 1_460, 29, 18, 180_000, live: true),
            place("hooli", "Hooli", 1_130, 22, 14, 260_000), place("global-safe", "Global safe", 870, 14, 11, 350_000),
            place("personal", "Personal", 330, 9, 7, 520_000),
            PlaceWire(
                room: "me", name: "About you", knowledge: 0, rules: 0, timeline: 0, lastLearnedAt: nil, learning: false,
                locked: false),
        ]
        model.calm.demo(
            areas: areas, learned: learned, records: Self.records, places: places, topics: Self.topics,
            days: Self.days(ago))
        model.calm.demoTopic = Self.topicRecords
        model.calm.demoAnswer = Self.answer
        model.calm.decisionsTotal = 922
        model.calm.demoSources = Self.sources(learning: learning, ago)
        model.status.demo(
            BrainActivityWire(
                state: learning ? "working" : "idle", health: "ok", rooms: 8, distilling: learning ? 1 : 0, queued: 0,
                overviews: 0, failed: 0, needs: [], lastDoneAt: nil))
        patchChecks()
        // The sample service's own load can land after this one: ask again once it has.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            patchChecks()
        }
        model.show(.overview)
        if drop { model.host.shell.toggleMenu(.brain) }
    }

    /// To check's three demo questions, over the sample's first candidates (their ids, so Keep and Not Right work).
    func patchChecks() {
        let asks = Self.checks
        guard model.candidates.items.first?.reason == nil else { return }
        model.candidates.inbox.items = Array(model.candidates.items.prefix(asks.count)).enumerated().map { i, c in
            var n = InboxCandidate(
                id: c.id, room: c.room, roomName: asks[i].3, kind: i == 1 ? .rule : .fact, text: asks[i].0,
                sources: c.sources, sortKey: c.sortKey)
            n.reason = asks[i].1
            n.otherBody = asks[i].2
            return n
        }
    }

    private static func sources(learning: Bool, _ ago: (Double) -> String) -> [SourceWire] {
        var a = SourceWire(id: "mac_claude_code", device: "Laptop", kind: "claude_code", lastRun: ago(720))
        a.readTotal = 2_418
        a.readWeek = 31
        a.lastReadAt = ago(720)
        a.reading = learning
        var n = SourceWire(id: "mac_doc", device: "Laptop", kind: "doc", lastRun: ago(3_600))
        n.readTotal = 1_204
        n.readWeek = 14
        n.lastReadAt = ago(3_600)
        let g = SourceWire(id: "github", device: "core", kind: "github", enabled: false)
        return [a, n, g]
    }

    private static func days(_ ago: (Double) -> String) -> ActivityDaysWire {
        let learned = [30, 64, 70, 90, 54, 210, 320, 900, 1_200, 30, 60, 40, 52, 38]
        let tidied = [20, 40, 30, 70, 30, 120, 160, 200, 260, 20, 40, 30, 50, 120]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let events: [[ActivityDaysWire.Event]] = [
            [
                .init(kind: "learned", count: 38, rooms: ["Acme Shop", "Northwind", "Initech", "Hooli"]),
                .init(kind: "tidied", count: 120, rooms: ["Acme Shop"], tookS: 360),
                .init(kind: "merged", count: 14, rooms: []),
                .init(kind: "overview", count: 1, rooms: ["Acme Shop"]),
            ],
            [
                .init(kind: "learned", count: 64, rooms: ["Initech", "Globex", "Hooli"]),
                .init(kind: "asked", count: 2, rooms: ["Globex"]),
                .init(kind: "tidied", count: 210, rooms: ["Initech"], tookS: 660),
            ],
            [
                .init(kind: "imported", count: 12_391, rooms: ["Acme Shop", "Initech", "Globex", "Northwind"]),
                .init(kind: "learned", count: 1_200, rooms: []),
            ],
        ]
        return ActivityDaysWire(
            days: (0..<14).map { i in
                .init(
                    day: f.string(from: Date().addingTimeInterval(-Double(i) * 86_400)), learned: learned[13 - i],
                    tidied: tidied[13 - i], events: i < events.count ? events[i] : [])
            })
    }

    private static func r(
        _ id: String, _ room: String, _ name: String, _ type: String, _ body: String, _ support: Int, _ ago: Double,
        kind: String? = nil, everywhere: Bool = false
    ) -> BrainAreaRecordWire {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-ago))
        return BrainAreaRecordWire(
            id: id, room: room, roomName: name, type: type, body: body, tags: [], support: support, createdAt: at,
            seenAt: at, kind: kind, everywhere: everywhere ? true : nil, following: true)
    }

    private static let day = 86_400.0

    static let records: [String: [BrainAreaRecordWire]] = [
        "me": [],
        "rules": [
            r(
                "r1", "acme-shop", "Acme Shop", "rule", "Ask before deleting anything outside the project folder", 9,
                3 * day, kind: "always", everywhere: true),
            r("r2", "initech", "Initech", "rule", "Run the tests before saying a fix is done", 7, day, kind: "always"),
            r(
                "r3", "acme-shop", "Acme Shop", "rule", "Show a screenshot for every screen that changes", 4, 2 * day,
                kind: "always"),
            r(
                "r4", "acme-shop", "Acme Shop", "rule", "Open a pull request for every change", 12, 8 * day,
                kind: "always", everywhere: true),
            r(
                "r5", "acme-shop", "Acme Shop", "rule", "Push straight to the main branch", 11, 7 * day, kind: "never",
                everywhere: true),
            r(
                "r6", "hooli", "Hooli", "rule", "Store keys or passwords in the code", 6, 21 * day, kind: "never",
                everywhere: true),
            r(
                "r7", "northwind", "Northwind", "rule", "Add a new library without asking first", 1, 2_400,
                kind: "never"),
            r("r8", "initech", "Initech", "rule", "Squash commits when merging", 4, 7 * day, kind: "never"),
            r(
                "r9", "globex", "Globex", "preference", "Short answers with the command to run", 3, 4 * day,
                kind: "prefer", everywhere: true),
            r("r10", "hooli", "Hooli", "preference", "Files under 500 lines", 4, 14 * day, kind: "prefer"),
        ],
        "knowledge": [
            r(
                "k1", "acme-shop", "Acme Shop", "fact",
                "Acme Shop releases ship as a signed .dmg, built on the release box", 5, 720),
            r("k2", "initech", "Initech", "fact", "Initech API keeps sessions in Postgres 17", 4, day),
            r(
                "d1", "acme-shop", "Acme Shop", "decision", "Chose SQLite over Postgres for the desktop cache", 4,
                11 * day),
            r(
                "d2", "acme-shop", "Acme Shop", "decision", "Dropped the beta channel; one stable channel only", 3,
                14 * day),
            r("d3", "initech", "Initech", "decision", "Moved payments to the hosted checkout page", 3, 21 * day),
            r(
                "d4", "northwind", "Northwind", "decision", "Kept the old login screen until the new one is tested", 2,
                26 * day),
        ],
        "timeline": [
            r(
                "t1", "acme-shop", "Acme Shop", "project-state",
                "Acme Shop 0.10.6 was released and installed on the server.", 1, 3_000),
            r("t2", "hooli", "Hooli", "project-state", "The runner on the attic box was updated to 0.10.6.", 1, 8_000),
            r(
                "t3", "initech", "Initech", "project-state", "Initech API 2.4 went live after the login fix.", 1,
                3 * day),
            r(
                "t4", "northwind", "Northwind", "project-state",
                "Decided to keep the old login screen until the new one is tested.", 1, 3.2 * day),
            r("t5", "globex", "Globex", "project-state", "Globex site moved to the new host.", 1, 5 * day),
        ]
            + (0..<40).map { i in
                r(
                    "h\(i)", "acme-shop", "Acme Shop", "project-state", "Shipped a small fix.", 1,
                    Double(i * i % 170 + 6) * day)
            },
    ]

    static let me: [BrainAreaRecordWire] = [
        r("m1", "me", "About you", "preference", "Short answers, with the command to run", 5, 2 * day),
        r("m2", "me", "About you", "preference", "Screenshots for every screen change", 4, 3 * day),
        r("m3", "me", "About you", "preference", "Reviews every change before it merges", 5, 4 * day),
        r("m4", "me", "About you", "fact", "Works on Mac apps and services", 3, 6 * day),
        r("m5", "me", "About you", "fact", "Uses Xcode, a terminal and GitHub all day", 4, 8 * day),
    ]

    static let topics: [TopicWire] = [
        .init(
            name: "Releases", count: 1_840, example: "Releases ship as a signed .dmg, built on the release box",
            rooms: ["Acme Shop", "Initech", "Globex", "Northwind", "Hooli"]),
        .init(
            name: "Sign-in", count: 1_210, example: "Northwind signs in with the same accounts as Initech",
            rooms: ["Northwind", "Initech"]),
        .init(
            name: "Builds", count: 1_096, example: "Hooli builds run on the attic box, never on the laptop",
            rooms: ["Hooli"]),
        .init(name: "Database", count: 980, example: "Initech keeps sessions in Postgres 17", rooms: ["Initech"]),
        .init(
            name: "Design", count: 860, example: "Screens follow the glass look, blue accent only", rooms: ["Acme Shop"]
        ),
        .init(
            name: "Payments", count: 612, example: "Payments go through the hosted checkout page", rooms: ["Initech"]),
        .init(
            name: "Tests", count: 590, example: "Every fix needs a passing test before it merges", rooms: ["Acme Shop"]),
        .init(name: "Deploys", count: 544, example: "Globex deploys every night at 02:00", rooms: ["Globex"]),
    ]

    static let topicRecords: [BrainAreaRecordWire] = [
        r(
            "q1", "acme-shop", "Acme Shop", "fact",
            "Acme Shop releases ship as a signed .dmg, built on the release box.", 5, 3_000),
        r(
            "q2", "initech", "Initech", "fact", "Initech keeps release notes in the repository, one file per version.",
            4, day),
        r("q3", "globex", "Globex", "fact", "Globex deploys from the main branch every night at 02:00.", 3, 2 * day),
        r("q4", "northwind", "Northwind", "fact", "Northwind ships through the store's beta track first.", 3, 3 * day),
        r(
            "q5", "hooli", "Hooli", "fact",
            "Hooli is shared by Acme Shop and Northwind; a release needs both to build.", 4, 7 * day),
        r(
            "q6", "acme-shop", "Acme Shop", "decision", "Dropped the beta channel; one stable channel only.", 3,
            14 * day),
        r("q7", "initech", "Initech", "decision", "A version bump goes in its own pull request.", 2, 21 * day),
    ]

    /// As this Core answers: the best matches, no written answer yet.
    static let answer = AskWire(
        answer: nil,
        sources: [
            .init(
                id: "q1", room: "acme-shop", roomName: "Acme Shop", type: "fact",
                body: "Acme Shop releases ship as a signed .dmg, built on the release box"),
            .init(
                id: "q6", room: "acme-shop", roomName: "Acme Shop", type: "decision",
                body: "Dropped the beta channel; one stable channel only"),
            .init(
                id: "q8", room: "acme-shop", roomName: "Acme Shop", type: "fact",
                body: "Every fix needs a passing test before it merges"),
        ])

    /// To check's three questions: a disagreement, a rule seen once, and a duplicate.
    static let checks: [(String, String?, String?, String)] = [
        ("Globex deploys every night at 02:00.", "conflict", "Deploys moved to 04:00 this week", "Globex"),
        ("Always answer in short sentences.", "single_source", nil, "Personal"),
        ("Use merge commits.", "duplicate", "Never squash pull requests", "Initech"),
    ]
}
#endif
