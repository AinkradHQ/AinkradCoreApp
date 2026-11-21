#if DEBUG
import Foundation

/// Debug only: a walk through every sidebar section of the one Brain app on the full calm Home and the sample places.
/// Every record is invented.
extension BrainDemo {
    static let walk = [
        "calm-me", "calm-rules", "calm-knowledge", "calm-timeline", "calm-places", "calm-place", "calm-inbox",
        "calm-sources", "calm-activity", "calm-search",
    ]

    func showWalk(_ scene: String) async {
        showCalm("calm-home")
        model.calm.demoRecords = Self.records
        // `show` starts Home loading on its own task; let it land before moving on.
        try? await Task.sleep(for: .milliseconds(100))
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
        case "calm-inbox":
            model.go(.inbox)
            await model.candidates.load()
        case "calm-sources":
            model.go(.sources)
            await model.sync?.reload()
        case "calm-activity": model.go(.activity)
        case "calm-search":
            calm.query = "sync"
            model.go(.records)
            calm.picked = "k1"
        default:
            let t = BrainTab(rawValue: String(scene.dropFirst("calm-".count))) ?? .me
            model.tab = t
            if let p = t.calmPage { await calm.open(p) }
            if t == .knowledge { calm.picked = "k1" }
        }
    }

    private static func r(
        _ id: String, _ room: String, _ name: String, _ type: String, _ body: String, _ support: Int, _ ago: Double
    ) -> BrainAreaRecordWire {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-ago))
        let first = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-ago * 9))
        return BrainAreaRecordWire(
            id: id, room: room, roomName: name, type: type, body: body, tags: [], support: support, createdAt: first,
            seenAt: at)
    }

    static let records: [String: [BrainAreaRecordWire]] = [
        "me": [
            r("m1", "personal", "Personal", "preference", "Prefers short answers in plain words", 6, 3_000),
            r("m2", "personal", "Personal", "fact", "Works best in long quiet mornings, 9 to 1", 4, 90_000),
            r("m3", "personal", "Personal", "preference", "Programs in Swift, TypeScript and Go", 3, 200_000),
        ],
        "rules": [
            r("r1", "personal", "Personal", "rule", "Ask before deleting any file", 5, 480),
            r("r2", "acme-shop", "Acme Shop", "rule", "Open a pull request, never merge it yourself", 3, 86_000),
            r("r3", "acme-shop", "Acme Shop", "rule", "Two spaces in TypeScript, tabs in Go", 2, 300_000),
            r("r4", "personal", "Personal", "rule", "Show the plan before any big change", 1, 400_000),
        ],
        "knowledge": [
            r(
                "k1", "acme-shop", "Acme Shop", "fact", "The shop syncs orders through a local database, not the cloud",
                4, 3_600),
            r("k2", "northwind", "Northwind", "fact", "The API runs on two small servers in one region", 2, 86_000),
            r("k3", "acme-shop", "Acme Shop", "fact", "The website and the app share one design system", 11, 200_000),
        ],
        "timeline": [
            r(
                "t1", "acme-shop", "Acme Shop", "project-state", "Merged the sync rewrite after the last test passed",
                1, 7_000),
            r("t2", "northwind", "Northwind", "project-state", "Split the API across two servers", 1, 170_000),
        ],
    ]
}
#endif
