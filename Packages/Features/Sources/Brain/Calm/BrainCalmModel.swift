import Foundation
import Observation

/// The calm Brain (E9-4, mockup 15): the areas the Core derives (`/areas`), what it learned lately with Undo, and the imports it
/// accepted by itself with Undo. Everything is read from the Core; nothing here is kept on the Mac.
@MainActor @Observable
public final class BrainCalmModel {
    public enum Page: String, CaseIterable, Hashable, Sendable {
        case home, me, rules, knowledge, timeline, places
        var title: String {
            switch self {
            case .home: "Home"
            case .me: "Me"
            case .rules: "Rules & preferences"
            case .knowledge: "Knowledge"
            case .timeline: "Timeline"
            case .places: "Places"
            }
        }
        var symbol: String {
            switch self {
            case .home: "brain"
            case .me: "person"
            case .rules: "slider.horizontal.3"
            case .knowledge: "sparkles"
            case .timeline: "clock"
            case .places: "folder"
            }
        }
        /// The Core's name for the area; nil for Home and Places.
        var area: String? {
            switch self {
            case .me: "me"
            case .rules: "rules"
            case .knowledge: "knowledge"
            case .timeline: "timeline"
            default: nil
            }
        }
    }

    /// A line of "What I learned today": one record Brain accepted, in words, with its area and time.
    public struct Learned: Identifiable, Equatable {
        public let id: String
        public let room: String
        public let roomName: String
        public let area: String
        public let line: String
        public let at: String
        init(_ w: LearnedWire) {
            id = w.id
            room = w.room
            roomName = w.roomName
            area = w.area
            at = SyncWords.date(w.createdAt).map { SyncWords.ago($0) } ?? ""
            line = Self.words(w.type, w.body)
        }
        /// "Learned a rule: ask before deleting files".
        static func words(_ type: String, _ body: String) -> String {
            let b = body.prefix(1).lowercased() + body.dropFirst()
            switch type {
            case "rule": return "Learned a rule: \(b)"
            case "preference": return "Noted that \(b)"
            case "decision": return "Noted a decision: \(b)"
            case "fact": return "Learned that \(b)"
            case "task": return "Picked up: \(b)"
            default: return "Noted: \(b)"
            }
        }
        var symbol: String {
            switch area {
            case "me": "person"
            case "rules": "checkmark.circle"
            case "knowledge": "sparkles"
            default: "clock"
            }
        }
        var areaTitle: String {
            switch area {
            case "me": "Me"
            case "rules": "Rules"
            case "knowledge": "Knowledge"
            default: "Timeline"
            }
        }
    }

    public var page: Page = .home
    public private(set) var areas: BrainAreasWire?
    public private(set) var records: [BrainAreaRecordWire] = []
    public private(set) var total = 0
    public private(set) var autoImports: [AutoImportWire] = []
    public private(set) var learned: [Learned] = []
    public private(set) var loading = false
    public private(set) var notice: String?
    /// Knowledge shows facts or decisions.
    public var knowledgeType = "fact"
    @ObservationIgnored var routes: BrainRoutes?
    @ObservationIgnored var service: (any BrainService)?
    @ObservationIgnored var rooms: () -> [RoomSummary] = { [] }

    public init() {}

    func attach(routes: BrainRoutes?, service: (any BrainService)?, rooms: @escaping () -> [RoomSummary]) {
        self.routes = routes
        self.service = service
        self.rooms = rooms
    }

    public func summary(_ area: String) -> BrainAreasWire.Summary? { areas?.areas.first { $0.area == area } }

    public func reload() async {
        guard let routes else { return }
        loading = true
        defer { loading = false }
        do {
            async let a = routes.areas()
            async let i = routes.autoImports()
            (areas, autoImports) = try await (a, i)
            notice = nil
        } catch is CancellationError {
        } catch { notice = BrainWords.failure(error) }
        await loadLearned()
        if page != .home, page != .places { await loadRecords() }
    }

    public func open(_ p: Page) async {
        page = p
        records = []
        total = 0
        if p.area != nil { await loadRecords() } else { await reload() }
    }

    func loadRecords() async {
        guard let routes, let area = page.area else { return }
        do {
            let p = try await routes.area(area, type: page == .knowledge ? knowledgeType : nil, limit: 60)
            records = p.records
            total = p.total
        } catch is CancellationError {
        } catch { notice = BrainWords.failure(error) }
    }

    func setKnowledge(_ type: String) async {
        knowledgeType = type
        await loadRecords()
    }

    /// Records accepted in the last day (the Core's `GET /learned`).
    func loadLearned() async {
        guard let routes, let l = try? await routes.learned() else { return }
        learned = l.map(Learned.init)
    }

    /// Takes the record out of memory (archived, never deleted).
    public func undo(_ l: Learned) async {
        guard let routes else { return }
        do {
            try await routes.archiveRecord(room: l.room, id: l.id)
            learned.removeAll { $0.id == l.id }
            await reload()
        } catch { notice = BrainWords.failure(error) }
    }

    /// Undo of an import the Core accepted: back to one pile, open for review.
    public func undoImport(_ a: AutoImportWire) async {
        guard let routes else { return }
        do {
            _ = try await routes.undoAutoImport(run: a.run)
            autoImports.removeAll { $0.run == a.run }
            await reload()
        } catch { notice = BrainWords.failure(error) }
    }

    #if DEBUG
    /// Debug demo only: the calm Brain's numbers without a Core.
    func demo(areas: BrainAreasWire, learned: [LearnedWire], autoImports: [AutoImportWire] = []) {
        page = .home
        self.areas = areas
        self.learned = learned.map(Learned.init)
        self.autoImports = autoImports
        notice = nil
    }
    #endif
}
