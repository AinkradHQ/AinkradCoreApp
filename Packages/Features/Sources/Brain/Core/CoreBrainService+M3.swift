import Foundation

/// Brain M3 on a real Core: the Inbox across the open rooms, a room's policy, and runner history.
extension CoreBrainService {
    public var servesCandidates: Bool { true }

    // MARK: Inbox

    public func candidates() async throws -> CandidateInbox {
        try await wrap {
            var items: [InboxCandidate] = []
            var queued: [QueuedRoom] = []
            for r in try await routes.rooms() {
                if r.open {
                    // A room that closed since the list was read has nothing to show; the next load tells the truth.
                    do {
                        let page = try await routes.inbox(room: r.id)
                        items += page.items.map { Self.candidate($0, room: r) }
                    } catch let e as BrainHTTPError where e.status == 409 {}
                }
                let n = try await routes.distils(room: r.id).filter { $0.state == "needs_local_model" }
                    .reduce(0) { $0 + $1.sources }
                if n > 0 { queued.append(QueuedRoom(room: r.id, name: r.name, items: n)) }
            }
            return CandidateInbox(items: items.sorted { $0.sortKey > $1.sortKey }, queued: queued)
        }
    }

    static func candidate(_ w: InboxRecordWire, room: RoomViewWire) -> InboxCandidate {
        let date = SyncWords.date(w.distilledAt)
        return InboxCandidate(
            id: w.id, room: room.id, roomName: room.name, kind: CandidateKind(type: w.type, tags: w.tags),
            text: w.body, app: w.tool.map(Self.toolName) ?? "",
            date: date.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "",
            distilled: date.map(Self.when) ?? "",
            account: w.distilledBy.map { "\($0.provider.capitalized), \($0.account)" } ?? "",
            sources: w.sources.map { src in
                let at = SyncWords.date(src.startedAt).map(Self.when) ?? ""
                return CandidateSource(
                    id: src.itemID, title: src.title,
                    place: ([src.room ?? room.name] + (at.isEmpty ? [] : [at])).joined(separator: " · "),
                    quote: src.quote)
            },
            tags: w.tags, sortKey: w.distilledAt ?? "")
    }

    /// The harness name the Core sends (`claude`, `codex`) as the screens say it.
    static func toolName(_ tool: String) -> String {
        switch tool {
        case "claude", "claude_code": "Claude Code"
        case "codex": "Codex"
        case "opencode": "OpenCode"
        default: tool.capitalized
        }
    }

    /// "today, 14:02" or "11 Nov, 14:02".
    static func when(_ d: Date) -> String {
        let time = d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
        let day = Calendar.current.isDateInToday(d) ? "today" : d.formatted(.dateTime.day().month(.abbreviated))
        return "\(day), \(time)"
    }

    public func decide(_ id: String, room: String, _ decision: CandidateDecision) async throws {
        let body: DecisionBody =
            switch decision {
            case .accept: DecisionBody(action: "accept")
            case .reject: DecisionBody(action: "reject")
            case .edit(let kind, let text, let tags):
                DecisionBody(action: "edit", body: text, type: kind.wireType, tags: kind.retag(tags))
            }
        _ = try await wrap { try await routes.decide(room: room, id: id, body) }
    }

    // MARK: policy

    public func policy(room: String) async throws -> RoomPolicy {
        try await wrap {
            let w = try await routes.policy(room: room)
            let queued = try await routes.distils(room: room).filter { $0.state == "needs_local_model" }
                .reduce(0) { $0 + $1.sources }
            return Self.policy(w, queued: queued)
        }
    }

    static func policy(_ w: PolicyWire, queued: Int) -> RoomPolicy {
        var p = RoomPolicy()
        p.model = w.model == "local_only" ? .localOnly : .cloud
        p.autoAccept = !w.autoAccept.isEmpty
        p.kinds = Set(w.autoAccept.compactMap(CandidateKind.init(autoType:)))
        p.otherAuto = w.autoAccept.filter { CandidateKind(autoType: $0) == nil }
        p.minSources = w.minSources ?? 1
        p.provider = w.accounts?.first.map { $0.provider.capitalized } ?? "Anthropic"
        p.accounts = (w.accounts ?? []).map(\.name)
        p.localModels = w.localModels ?? []
        p.queued = queued
        return p
    }

    public func setPolicy(room: String, _ change: PolicyChange) async throws -> RoomPolicy {
        try await wrap {
            let now = try await policy(room: room)
            let on = change.autoAccept ?? now.autoAccept
            let kinds = change.kinds ?? now.kinds
            // Auto-accept filters by type: Landmines is every rule and Open threads is every task.
            let types = Array(Set(kinds.map(\.wireType) + now.otherAuto)).sorted()
            let touchesAuto = change.autoAccept != nil || change.kinds != nil
            let body = PolicyPatchBody(
                model: change.model?.rawValue, autoAccept: touchesAuto ? (on ? types : []) : nil,
                minSources: change.minSources)
            return Self.policy(try await routes.patchPolicy(room: room, body), queued: now.queued)
        }
    }

    // MARK: AI access

    public func roomAccess(room: String) async throws -> RoomAccess {
        try await wrap { try await routes.roomAccess(room: room) }
    }

    public func setRoomAccess(room: String, kind: AccessKind, values: [String]) async throws -> RoomAccess {
        try await wrap { try await routes.putRoomAccess(room: room, kind: kind, values: values) }
    }

    // MARK: runner history

    /// A runner's history is one source on `/sources`, `runner-<id>`, off until you turn it on.
    public func runners() async throws -> [RunnerHistory] {
        try await wrap {
            let names = Dictionary(
                ((try? await routes.runners()) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            return try await routes.sources().compactMap(Self.runner).map { r in
                var r = r
                if let n = names[r.id] { r.name = n }
                return r
            }
        }
    }

    /// Turning it on sets the runner's history sharing first when it is not on, then the source's switch; the caller's
    /// one Touch ID covers both. Turning it off only switches the source off.
    public func setRunnerHistory(_ id: String, enabled: Bool) async throws -> RunnerHistory {
        try await wrap {
            let key = Self.runnerPrefix + id
            let rows = try await routes.sources()
            var restarting = false
            if enabled, rows.first(where: { $0.id == key })?.runner?.historyOffered != true {
                restarting = try await shareHistory(id)
            }
            let row =
                rows.first { $0.id == key }
                ?? SourceWire(id: key, device: id, kind: "claude_code", enabled: false)
            var out =
                try await Self.runner(routes.putSource(row, enabled: enabled))
                ?? RunnerHistory(id: id, name: row.device)
            out.restarting = restarting
            return out
        }
    }

    /// `PUT /runners/{id}/policy` takes the whole policy: the runner's own, with history sharing on. True when the
    /// runner restarts to apply it.
    private func shareHistory(_ id: String) async throws -> Bool {
        guard let policy = try await routes.runners().first(where: { $0.id == id })?.policy else {
            throw BrainFailure("That runner is not paired any more.", code: "not_found")
        }
        guard policy.shareHistory != true else { return false }
        var next = policy
        next.shareHistory = true
        return try await routes.setRunnerPolicy(id, next).restarting == true
    }

    static let runnerPrefix = "runner-"

    static func runner(_ w: SourceWire) -> RunnerHistory? {
        guard w.id.hasPrefix(runnerPrefix) else { return nil }
        // The Core reads a runner's Claude Code history only, so that is the one tool listed.
        let tools =
            w.runner?.tools.contains("claude") == true ? [RunnerTool(id: "claude_code", name: "Claude Code")] : []
        return RunnerHistory(
            id: String(w.id.dropFirst(runnerPrefix.count)), name: w.device, online: w.runner?.online ?? true,
            enabled: w.enabled, tools: tools, items: w.items ?? 0,
            lastRun: SyncWords.date(w.lastRun).map { SyncWords.ago($0) })
    }
}
