import CoreUI
import Foundation

/// The redesign's reads and actions (API minor 101): topics and decisions for Knowledge, the ask box, the two-week
/// activity, following a rule and writing one. On an older Core each call is skipped and its part of the page hides.
extension BrainCalmModel {
    /// Knowledge also shows its topics and newest decisions; a topic's list has no extras.
    func loadPageExtras() async {
        guard page == .knowledge, topic == nil else { return }
        #if DEBUG
        if routes == nil {
            let all = demoRecords["knowledge"] ?? []
            decisions = Array(all.filter { $0.type == "decision" }.prefix(4))
            decisionsTotal = max(decisionsTotal, decisions.count)
            return
        }
        #endif
        guard let routes else { return }
        if v101 { topics = try? await routes.topics() }
        if let p = try? await routes.area("knowledge", type: "decision", limit: 4) {
            decisions = p.records
            decisionsTotal = p.total
        }
    }

    /// The demo's filters, done here because there is no Core to do them.
    func matches(_ r: BrainAreaRecordWire) -> Bool {
        if page == .rules, let room = ruleRoom, r.room != room { return false }
        if page == .knowledge, topic == nil, r.type != knowledgeType { return false }
        if page == .knowledge || page == .timeline, let room = topicRoom, r.room != room, r.roomName != room {
            return false
        }
        if !filterText.isEmpty, !r.body.localizedCaseInsensitiveContains(filterText) { return false }
        return true
    }

    /// A rule's kind as the Core sends it; an older Core has none, and the rule is listed without one.
    static func kind(_ r: BrainAreaRecordWire) -> String? { r.kind }

    /// Opens a topic's list (nil goes back to the library).
    public func openTopic(_ t: TopicWire?) async {
        topic = t
        topicRoom = nil
        filterText = ""
        picked = nil
        #if DEBUG
        if routes == nil, t != nil {
            records = demoTopic.filter(matches)
            total = t?.count ?? records.count
            picked = records.first?.id
            return
        }
        #endif
        await loadRecords()
        if t != nil { picked = records.first?.id }
    }

    /// Re-reads the list after a filter changed (kind, place or words).
    public func refilter() async {
        #if DEBUG
        if routes == nil, page == .knowledge, topic != nil {
            records = demoTopic.filter(matches)
            return
        }
        #endif
        await loadRecords()
        if let p = picked, !records.contains(where: { $0.id == p }) { picked = records.first?.id }
    }

    /// Asks what Brain knows. Nothing is stored; a Core without an AI account answers with sources only.
    public func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }
        asking = true
        defer { asking = false }
        #if DEBUG
        if routes == nil {
            answer = demoAnswer
            return
        }
        #endif
        guard v101, let routes else { return }
        do { answer = try await routes.ask(q) } catch is CancellationError {
        } catch { notice = BrainWords.failure(error) }
    }

    public func clearAnswer() {
        answer = nil
        question = ""
    }

    func loadDays() async {
        guard v101, let routes else { return }
        days = try? await routes.activityDays()
    }

    /// Follow or keep a rule without using it.
    public func follow(_ r: BrainAreaRecordWire, _ on: Bool) async {
        func set() {
            if let i = records.firstIndex(where: { $0.id == r.id }) { records[i].following = on }
        }
        #if DEBUG
        if routes == nil {
            set()
            return
        }
        #endif
        guard v101, let routes else { return }
        do {
            try await routes.follow(room: r.room, id: r.id, on: on)
            set()
        } catch { notice = BrainWords.failure(error) }
    }

    /// Writes a rule in the person's words: everywhere (`rooms` nil) or in the places given. Answers the places it went
    /// into (0 when every one had it already), nil when it failed.
    public func newRule(_ body: String, kind: String, rooms: [String]?) async -> Int? {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        #if DEBUG
        if routes == nil {
            let r = BrainAreaRecordWire(
                id: "new-\(UUID().uuidString.prefix(6))", room: rooms?.first ?? "everywhere", roomName: "Everywhere",
                type: kind == "prefer" ? "preference" : "rule", body: text, tags: [], support: 5,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                seenAt: ISO8601DateFormatter().string(from: Date()), kind: kind, everywhere: rooms == nil)
            demoRecords["rules", default: []].insert(r, at: 0)
            records.insert(r, at: 0)
            picked = r.id
            return 1
        }
        #endif
        guard v101, let routes else { return nil }
        do {
            let n = try await routes.newRule(text, kind: kind, rooms: rooms)
            await reload()
            return n
        } catch {
            notice = BrainWords.failure(error)
            return nil
        }
    }

    /// Puts a forgotten record back (the toast's Undo).
    public func restore(room: String, id: String) async {
        #if DEBUG
        if routes == nil { return }
        #endif
        guard let routes else { return }
        do {
            try await routes.restoreRecord(room: room, id: id)
            await reload()
        } catch { notice = BrainWords.failure(error) }
    }

    /// To check: one more answered, or put off until the others are done.
    func answered(_ id: String, later put: Bool) {
        if put {
            later.removeAll { $0 == id }
            later.append(id)
        } else {
            checked += 1
            later.removeAll { $0 == id }
        }
    }

    public func resetChecks() {
        checked = 0
        later = []
    }
}

/// How sure Brain is, from how often it saw a thing: five steps, said in words.
enum BrainSure {
    static func level(_ support: Int) -> Int { min(5, max(1, support)) }
    static func words(_ support: Int) -> String {
        ["a guess", "a guess", "fairly sure", "sure", "very sure"][level(support) - 1]
    }
}

/// A rule kind's words and symbol (Always, Never, Prefer).
enum RuleKind: String, CaseIterable {
    case always, never, prefer
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var symbol: String {
        switch self {
        case .always: "checkmark"
        case .never: "xmark"
        case .prefer: "star"
        }
    }
    var line: String {
        switch self {
        case .always: "Brain does these every time"
        case .never: "Brain will not do these"
        case .prefer: "Brain leans this way when it can"
        }
    }
}
