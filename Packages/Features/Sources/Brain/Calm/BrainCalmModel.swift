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
            case .me: "About you"
            case .rules: "Rules"
            case .knowledge: "Knowledge"
            case .timeline: "Timeline"
            case .places: "Places"
            }
        }
        var symbol: String {
            switch self {
            case .home: "brain"
            case .me: "person"
            case .rules: "checkmark"
            case .knowledge: "sparkles"
            case .timeline: "clock"
            case .places: "folder"
            }
        }
        /// What the area means, in plain words.
        var meaning: String {
            switch self {
            case .me: "How you like to work"
            case .rules: "What to always or never do"
            case .knowledge: "Facts and decisions about your projects"
            case .timeline: "What happened, and when"
            default: ""
            }
        }
        /// The sidebar section that shows this page.
        var tab: BrainTab {
            switch self {
            case .home: .overview
            case .places: .rooms
            default: BrainTab(rawValue: rawValue) ?? .overview
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

    /// A record with the area it was read from.
    struct AreaRecord: Identifiable, Equatable {
        let area: String
        let record: BrainAreaRecordWire
        var id: String { record.id }
    }

    /// A line of "What I learned today": one record Brain accepted, in words, with its area and time.
    public struct Learned: Identifiable, Equatable {
        public let id: String
        public let room: String
        public let roomName: String
        public let area: String
        public let line: String
        public let body: String
        public let at: String
        init(_ w: LearnedWire) {
            id = w.id
            room = w.room
            roomName = w.roomName
            area = w.area
            at = SyncWords.date(w.createdAt).map { SyncWords.ago($0) } ?? ""
            createdAt = w.createdAt
            line = Self.words(w.type, w.body)
            body = w.body
        }
        /// "Learned a rule: ask before deleting files".
        static func words(_ type: String, _ body: String) -> String {
            let b = lowerFirst(body)
            switch type {
            case "rule": return "Learned a rule: \(b)"
            case "preference": return "Noted that \(b)"
            case "decision": return "Noted a decision: \(b)"
            case "fact": return "Learned that \(b)"
            case "task": return "Picked up: \(b)"
            default: return "Noted: \(b)"
            }
        }
        /// "Ask before…" reads "ask before…" after "Learned a rule:", but a name ("Acme Shop…") keeps its capital.
        static func lowerFirst(_ s: String) -> String {
            let first = s.prefix { $0.isLetter || $0 == "'" }.lowercased()
            return starters.contains(first) ? s.prefix(1).lowercased() + s.dropFirst() : s
        }
        static let starters: Set<String> = [
            "a", "an", "the", "ask", "use", "run", "show", "keep", "open", "push", "store", "add", "write", "do",
            "don't",
            "never", "always", "prefer", "avoid", "make", "every", "each", "all", "no", "it", "this", "that", "there",
            "you", "we", "they", "short", "plain", "test", "check", "read", "put", "send", "work", "works",
        ]
        var symbol: String {
            switch area {
            case "me": "person"
            case "rules": "checkmark"
            case "knowledge": "sparkles"
            default: "clock"
            }
        }
        /// The record's place, for the rows' "Knowledge · Studio app · 12 min ago".
        public var createdAt: String = ""
        var areaTitle: String {
            switch area {
            case "me": "About you"
            case "rules": "Rules"
            case "knowledge": "Knowledge"
            default: "Timeline"
            }
        }
    }

    public var page: Page = .home
    public private(set) var areas: BrainAreasWire?
    public internal(set) var records: [BrainAreaRecordWire] = []
    public internal(set) var total = 0
    public private(set) var autoImports: [AutoImportWire] = []
    public internal(set) var learned: [Learned] = []
    public private(set) var loading = false
    public internal(set) var notice: String?
    /// Knowledge shows facts or decisions.
    public var knowledgeType = "fact"
    /// The search over everything (⌘E): its words and the area it is narrowed to ("" for all).
    public var query = ""
    public var searchArea = ""
    /// Bumped to put the keyboard in the sidebar's search field.
    public private(set) var searchAsked = 0
    /// The record whose detail is open beside a list.
    public var picked: String?
    /// The redesign's routes (API minor 101) are there; without them each part falls back to what an older Core has.
    public internal(set) var v101 = false
    /// API minor 101: every place with its counts by area, whether it learns now.
    public internal(set) var places: [PlaceWire]?
    /// API minor 101: Knowledge's topics, the one opened, its place filter and words.
    public internal(set) var topics: [TopicWire]?
    public var topic: TopicWire?
    public var topicRoom: String?
    public var filterText = ""
    /// Rules: the kind tile picked (nil for All) and the place filter.
    public var ruleKind: String?
    public var ruleRoom: String?
    /// Knowledge's newest decisions and how many there are.
    public internal(set) var decisions: [BrainAreaRecordWire] = []
    public internal(set) var decisionsTotal = 0
    /// The ask box: the question, its answer, and whether it is being written.
    public var question = ""
    public internal(set) var answer: AskWire?
    public internal(set) var asking = false
    /// API minor 101: the last two weeks, newest day first.
    public internal(set) var days: ActivityDaysWire?
    /// To check: answered this visit (for "2 of 3") and the ones put off with Later, asked again last.
    public internal(set) var checked = 0
    public internal(set) var later: [String] = []
    #if DEBUG
    /// Debug demo only: each area's records without a Core.
    var demoRecords: [String: [BrainAreaRecordWire]] = [:]
    var demoTopic: [BrainAreaRecordWire] = []
    var demoAnswer: AskWire?
    var demoSources: [SourceWire]?
    #endif
    @ObservationIgnored var routes: BrainRoutes?
    @ObservationIgnored var service: (any BrainService)?
    @ObservationIgnored var rooms: () -> [RoomSummary] = { [] }

    public init() {}

    func attach(
        routes: BrainRoutes?, service: (any BrainService)?, v101: Bool, rooms: @escaping () -> [RoomSummary]
    ) {
        self.routes = routes
        self.v101 = v101
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
        if v101 { places = try? await routes.places() }
        if page != .home, page != .places { await loadRecords() }
    }

    public func open(_ p: Page) async {
        if page != p {
            picked = nil
            topic = nil
            filterText = ""
        }
        page = p
        records = []
        total = 0
        if p.area != nil { await loadRecords() } else { await reload() }
    }

    func loadRecords() async {
        guard let area = page.area else { return }
        #if DEBUG
        if routes == nil, let demo = demoRecords[area] {
            records = demo.filter(matches)
            total = records.count
            await loadPageExtras()
            return
        }
        #endif
        guard let routes else { return }
        do {
            let p: BrainAreaPageWire
            if v101 {
                p = try await routes.area(
                    area, kind: page == .rules ? ruleKind : nil, topic: page == .knowledge ? topic?.name : nil,
                    room: page == .rules ? ruleRoom : page == .knowledge ? topicRoom : nil,
                    q: filterText.isEmpty ? nil : filterText,
                    type: page == .knowledge && topic == nil ? knowledgeType : nil,
                    limit: page == .timeline ? 200 : 60)
            } else {
                p = try await routes.area(
                    area, type: page == .knowledge ? knowledgeType : nil, limit: page == .timeline ? 200 : 60)
            }
            records = p.records
            total = p.total
        } catch is CancellationError {
        } catch { notice = BrainWords.failure(error) }
        await loadPageExtras()
    }

    public func askSearch() { searchAsked += 1 }

    /// Every current record of the four areas, with its area, best supported and newest first (the search).
    func everything(limit: Int = 200) async -> [AreaRecord] {
        var all: [AreaRecord] = []
        for a in ["me", "rules", "knowledge", "timeline"] {
            #if DEBUG
            if routes == nil, let demo = demoRecords[a] {
                all += demo.map { AreaRecord(area: a, record: $0) }
                continue
            }
            #endif
            guard let routes else { break }
            do {
                all += try await routes.area(a, limit: limit).records.map { AreaRecord(area: a, record: $0) }
            } catch is CancellationError {
            } catch { notice = BrainWords.failure(error) }
        }
        return all.sorted { ($0.record.support, $0.record.seenAt) > ($1.record.support, $1.record.seenAt) }
    }

    /// Takes a record out of memory (archived, never deleted), from its detail.
    @discardableResult
    public func forget(_ r: BrainAreaRecordWire) async -> Bool {
        let next = records.firstIndex { $0.id == r.id }.flatMap { i in
            records.indices.contains(i + 1) ? records[i + 1].id : i > 0 ? records[i - 1].id : nil
        }
        #if DEBUG
        if routes == nil {
            for k in demoRecords.keys { demoRecords[k]?.removeAll { $0.id == r.id } }
            records.removeAll { $0.id == r.id }
            picked = next
            return true
        }
        #endif
        guard let routes else { return false }
        do {
            try await routes.archiveRecord(room: r.room, id: r.id)
            records.removeAll { $0.id == r.id }
            picked = next
            return true
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
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
    @discardableResult
    public func undo(_ l: Learned) async -> Bool {
        #if DEBUG
        if routes == nil {
            learned.removeAll { $0.id == l.id }
            return true
        }
        #endif
        guard let routes else { return false }
        do {
            try await routes.archiveRecord(room: l.room, id: l.id)
            learned.removeAll { $0.id == l.id }
            await reload()
            return true
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
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
    func demo(
        areas: BrainAreasWire, learned: [LearnedWire], autoImports: [AutoImportWire] = [],
        records: [String: [BrainAreaRecordWire]] = [:], places: [PlaceWire]? = nil, topics: [TopicWire]? = nil,
        days: ActivityDaysWire? = nil
    ) {
        demoRecords = records
        v101 = places != nil
        self.places = places
        self.topics = topics
        self.days = days
        topic = nil
        answer = nil
        question = ""
        checked = 0
        later = []
        page = .home
        self.areas = areas
        self.learned = learned.map(Learned.init)
        self.autoImports = autoImports
        notice = nil
    }
    #endif
}
