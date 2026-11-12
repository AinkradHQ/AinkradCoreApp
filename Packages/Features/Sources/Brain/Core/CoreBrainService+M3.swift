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
        let date = SyncWords.date(w.createdAt)
        return InboxCandidate(
            id: w.id, room: room.id, roomName: room.name, kind: CandidateKind(wire: w.type), text: w.body,
            date: date.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "",
            distilled: date.map(Self.when) ?? "",
            // TODO(brain-m3-core): confirm the Core names each source's tool, title, quote and the distilling account.
            sources: w.sources.enumerated().map {
                CandidateSource(id: $0.element, title: "Source \($0.offset + 1)", place: room.name)
            },
            sortKey: w.createdAt)
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
            case .edit(let kind, let text): DecisionBody(action: "edit", body: text, type: kind.wire)
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
        p.kinds = w.autoAccept.isEmpty ? [] : [.fact]
        // The Core accepts only facts, preferences and summaries without a review, and keeps no source minimum yet.
        p.autoKindsAllowed = [.fact]
        p.minSourcesServed = false
        p.queued = queued
        return p
    }

    public func setPolicy(room: String, _ change: PolicyChange) async throws -> RoomPolicy {
        try await wrap {
            let now = try await policy(room: room)
            let on = change.autoAccept ?? now.autoAccept
            let kinds = (change.kinds ?? now.kinds).intersection(now.autoKindsAllowed)
            let body = PolicyPatchBody(
                model: change.model?.rawValue,
                autoAccept: change.autoAccept != nil || change.kinds != nil
                    ? (on && kinds.contains(.fact) ? ["fact", "preference", "summary"] : []) : nil)
            var p = Self.policy(try await routes.patchPolicy(room: room, body), queued: now.queued)
            p.minSources = change.minSources ?? now.minSources
            return p
        }
    }

    // MARK: runner history

    public func runners() async throws -> [RunnerHistory] {
        do { return try await routes.runnerHistory().map(Self.runner) } catch let e as BrainHTTPError
            where [404, 405, 501].contains(e.status)
        {
            // This Core has no runner history route yet: the Sources page shows no Runners section.
            return []
        } catch let e as BrainHTTPError { throw Self.failure(e) }
    }

    public func setRunnerHistory(_ id: String, enabled: Bool, tools: [String]) async throws -> RunnerHistory {
        Self.runner(try await wrap { try await routes.putRunnerHistory(id, enabled: enabled, tools: tools) })
    }

    static func runner(_ w: RunnerHistoryWire) -> RunnerHistory {
        RunnerHistory(
            id: w.id, name: w.name, online: w.online, enabled: w.enabled,
            tools: w.tools.map { RunnerTool(id: $0.id, name: $0.name, found: $0.found, on: $0.on) },
            items: w.items ?? 0, lastRun: w.lastRun)
    }
}
