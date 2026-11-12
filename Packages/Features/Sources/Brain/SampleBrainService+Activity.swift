#if DEBUG
import Foundation

/// Debug only: the prototype's Activity and Checks sample data (brain-3.js, brain-data.js). Invented ids and codes only.
extension SampleBrainService {
    public func activity(limit: Int) async throws -> ActivityPage {
        if scenario.activityError { throw BrainFailure("Core did not answer.", code: "audit_unavailable") }
        if scenario.noActivity || scenario.empty { return ActivityPage(events: []) }
        let all = liveRows + Self.audit + Self.older
        return ActivityPage(events: Array(all.prefix(limit)), hasMore: limit < all.count)
    }

    public func liveActivity() async -> AsyncStream<ActivityEvent> {
        let (stream, cont) = AsyncStream<ActivityEvent>.makeStream()
        watchers.append(cont)
        return stream
    }

    /// Debug: a row arrives, the way a live Core would send one.
    public func arrive(blocked: Bool = false) {
        let seq = (liveRows.first?.seq ?? Self.audit[0].seq) + 1
        let e =
            blocked
            ? ActivityEvent(
                seq: seq, at: "now", actor: "Cloud runner (sample)", device: "Runner", action: "Asked for context",
                room: "ainkrad", result: .blocked, reason: "The lease for this runner had expired.", kind: .blocked,
                rule: Self.expiredRule, actionCode: "context.request", sessionID: "sess-c0de")
            : ActivityEvent(
                seq: seq, at: "now", actor: "Claude Code (sample)", device: "Mac Studio", action: "Searched",
                room: "ainkrad", result: .ok, kind: .access, actionCode: "memory.search", sessionID: "sess-7f3a")
        liveRows.insert(e, at: 0)
        for w in watchers { w.yield(e) }
    }

    public func egress(room: String) async throws -> [EgressCall] {
        if scenario.activityError { throw BrainFailure("Core did not answer.", code: "audit_unavailable") }
        if scenario.noActivity { return [] }
        return Self.calls.filter { $0.room == room }
    }

    public func checks() async throws -> ChecksReport {
        if scenario.error {
            throw BrainFailure("Core did not answer. Nothing was changed.", code: "sample_unreachable")
        }
        return ChecksReport(items: checkList, pilot: pilot())
    }

    public func runCheck(
        _ id: String, options: CheckRunOptions, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CheckItem {
        guard let i = checkList.firstIndex(where: { $0.id == id }) else {
            throw BrainFailure("That check does not exist.", code: "check_unknown")
        }
        if scenario.offline, checkList[i].needsServer {
            checkList[i].skippedOffline = true
            return checkList[i]
        }
        checkList[i].skippedOffline = false
        for step in 1...8 {
            try await Task.sleep(for: pace)
            progress(Double(step) / 8)
        }
        let bad = failing.remove(id) != nil
        var c = checkList[i]
        c.last = "Just now"
        c.outcome = bad ? .fail : .pass
        c.due = "in 6 days"
        c.value = bad ? Self.failValue[id] ?? "Failed" : Self.okValue[id] ?? c.target
        c.history = Array((c.history + [!bad]).suffix(7))
        c.clearedAfter = false
        checkList[i] = c
        // The service decides: a leak pauses search. A passing run does not clear it.
        if bad, id == "leakage" { scenario.paused = true }
        return c
    }

    /// Debug and tests: the next run of these checks fails.
    public func failNext(_ ids: Set<String>) { failing.formUnion(ids) }

    private func pilot() -> [PilotTarget] {
        func via(_ id: String) -> (String, PilotResult) {
            guard let c = checkList.first(where: { $0.id == id }) else { return ("—", .notMeasured) }
            return (c.value, c.outcome == .fail ? .fail : c.outcome == .never ? .notMeasured : .pass)
        }
        func row(_ code: String, _ title: String, _ target: String, _ id: String?, _ fixed: String = "") -> PilotTarget
        {
            guard let id else { return PilotTarget(code, title, target: target, value: fixed, result: .pass) }
            let v = via(id)
            return PilotTarget(code, title, target: target, value: v.0, result: v.1)
        }
        return [
            row("C1", "No room ever shows another room\u{2019}s memories", "Zero in 1,000 test questions", "leakage"),
            row("C3", "The right memory is in the first five results", "0.90 or more", "recall"),
            row("C4", "Every answer shows its source", "100%", nil, "100%"),
            row("C7", "Local search speed (p95)", "Under 300 ms", "speed"),
            row("C8", "Remote search speed (p95)", "Under 1.5 s", nil, "1.1 s"),
            row("C11", "Devices agree after reconnecting", "Under 60 s", "sync"),
            row("C12", "Restore on a clean Mac", "Under 30 min", "restore"),
            row("C14", "Local and cloud runner find the same records", "10 of 10", nil, "10 of 10"),
        ]
    }

    // MARK: data

    static let expiredRule = BlockRule("expired", "Token lease", fix: "Start the runner again to get a new lease.")
    static let failValue = [
        "leakage": "2 of 1,000", "recall": "0.81", "speed": "412 ms", "sync": "94 s", "restore": "41 min",
        "keys": "Old key still worked", "providers": "1 sent", "index": "Differs", "secrets": "1 saved",
    ]
    static let okValue = [
        "leakage": "0 of 1,000", "recall": "0.93", "speed": "212 ms", "sync": "38 s", "restore": "24 min",
        "keys": "Old key refused", "providers": "0 sent", "index": "Matches", "secrets": "2 blocked",
    ]

    static func initialChecks(_ s: Scenario) -> [CheckItem] {
        func item(
            _ id: String, _ name: String, _ about: String, _ last: String, _ o: CheckOutcome, _ due: String,
            _ value: String, _ target: String, _ h: String, server: Bool = false, hk: Bool = false
        ) -> CheckItem {
            CheckItem(
                id: id, name: name, about: about, last: last, outcome: o, due: due, value: value, target: target,
                history: h.map { $0 == "p" }, skippedOffline: s.offline && server, housekeeping: hk,
                needsServer: server,
                trend: id == "speed" ? [188, 204, 176, 231, 212, 245, 198, 168, 277, 214, 190, 226, 205, 212] : [],
                trendLimit: id == "speed" ? 300 : nil)
        }
        var list = [
            item(
                "leakage", "Leakage",
                "Asks 1,000 test questions and confirms no room ever shows another room\u{2019}s memories.",
                "Yesterday", .pass, "in 6 days", "0 of 1,000", "Zero", "ppppppp"),
            item(
                "recall", "Recall", "Checks that the right memory is found in the first five results.",
                "2 days ago", .pass, "in 5 days", "0.93", "0.90 or more", "ppfpppp"),
            item(
                "speed", "Speed", "Times local searches. 95 in 100 should answer in under 300 ms.", "Today", .pass,
                "in 1 day", "212 ms", "Under 300 ms", "ppppppp"),
            item(
                "sync", "Sync", "Changes on one device reach the others within a minute of reconnecting.", "Today",
                .pass, "in 1 day", "38 s", "Under 60 s", "pppfppp", server: true),
            item(
                "restore", "Backup test", "Rebuilds a room on a clean Mac from its backup.", "41 days ago", .due,
                "now", "24 min", "Under 30 min", "ppp", server: true),
            item(
                "keys", "Key rotation drill",
                "Changes a room\u{2019}s key and confirms the old one stops working.", "12 days ago", .pass,
                "in 18 days", "Old key refused", "Old key refused", "ppp", server: true),
            item(
                "providers", "Provider rules",
                "Confirms no room sent text to a provider it is not approved for.", "Today", .pass, "in 1 day",
                "0 sent", "Zero", "ppppppp"),
            item(
                "index", "Search index", "Compares the search index with the memories it should cover.", "8 min ago",
                .pass, "in 1 day", "Matches", "Matches", "ppp", hk: true),
            item(
                "secrets", "Secret scanner", "Looks for keys and passwords in what was saved.", "Today", .pass,
                "in 1 day", "2 blocked", "None saved", "pppp", hk: true),
        ]
        if s.paused, let i = list.firstIndex(where: { $0.id == "leakage" }) {
            list[i].outcome = .fail
            list[i].last = "Just now"
            list[i].value = failValue["leakage"] ?? ""
            list[i].history = [true, true, true, true, true, true, false]
        }
        return list
    }

    private static func ev(
        _ seq: Int, _ at: String, _ actor: String, _ device: String, _ action: String, _ room: String?,
        _ result: ActivityResult, _ kind: ActivityKind, code: String, reason: String? = nil, rule: BlockRule? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            seq: seq, at: at, actor: actor, device: device, action: action, room: room, result: result,
            reason: reason, kind: kind, rule: rule, actionCode: code,
            sessionID: "sess-" + String(seq * 7919 % 65535, radix: 16).leftPad(4))
    }

    static let audit: [ActivityEvent] = [
        ev(
            2041, "now", "Claude Code (sample)", "Mac Studio", "Searched", "ainkrad", .ok, .access,
            code: "memory.search"),
        ev(2040, "1 min ago", "You", "Mac Studio", "Opened the room", "ainkrad", .ok, .access, code: "room.open"),
        ev(
            2039, "12 min ago", "Claude Code (sample)", "Mac Studio", "Proposed a memory", "ainkrad", .ok, .changes,
            code: "memory.propose"),
        ev(
            2038, "40 min ago", "Capture (sample)", "Mac Studio", "Saved a note", "globex", .blocked, .blocked,
            code: "capture.save", reason: "A secret was found. Nothing was saved.",
            rule: BlockRule(
                "secret_found", "Secret scanner", fix: "Remove the secret from the note and save again.")),
        ev(
            2037, "1 h ago", "Cloud runner (sample)", "Runner", "Asked for context", "northwind", .blocked, .blocked,
            code: "context.request", reason: "This room is local only. Cloud AI sessions cannot read it.",
            rule: BlockRule(
                "local_only", "Room is local only", fix: "Change the room to synced, or use a local model.")),
        ev(
            2036, "1 h ago", "Codex (sample)", "MacBook", "Searched", nil, .blocked, .blocked, code: "memory.search",
            reason: "No room was chosen. Nothing was searched.",
            rule: BlockRule("no_room", "A room must be chosen", fix: "Choose a room and ask again.")),
        ev(2035, "2 h ago", "Sync", "iPhone", "Synced 6 changes", "ainkrad", .ok, .sync, code: "sync.push"),
        ev(2034, "3 h ago", "You", "Mac Studio", "Approved a memory", "ainkrad", .ok, .changes, code: "memory.approve"),
        ev(
            2033, "3 h ago", "Sync", "MacBook", "Sync fell behind", "acme-shop", .failed, .sync, code: "sync.fault",
            reason: "The MacBook has not synced for 3 h."),
        ev(
            2032, "5 h ago", "Embedding (sample)", "Mac Studio", "Sent text to a cloud model", "ainkrad", .blocked,
            .blocked, code: "model.egress", reason: "That provider is not approved for this room.",
            rule: BlockRule(
                "no_approval", "Provider rules", fix: "Approve the provider for this room, or use a local model.")),
        ev(
            2031, "Yesterday", "You", "Mac Studio", "Changed storage mode", "hooli", .ok, .changes,
            code: "room.mode.change"),
        ev(2030, "Yesterday", "Check", "Mac Studio", "Leakage check passed", nil, .ok, .access, code: "check.run"),
        ev(2029, "Yesterday", "You", "Mac Studio", "Revoked a device", "ainkrad", .ok, .changes, code: "device.revoke"),
        ev(2028, "2 days ago", "Sync", "iPhone", "Synced 2 changes", "global-safe", .ok, .sync, code: "sync.push"),
    ]

    static let older: [ActivityEvent] = [
        ev(
            2027, "2 days ago", "You", "Mac Studio", "Approved a memory", "globex", .ok, .changes,
            code: "memory.approve"),
        ev(
            2026, "2 days ago", "Claude Code (sample)", "Mac Studio", "Searched", "ainkrad", .ok, .access,
            code: "memory.search"),
        ev(
            2025, "3 days ago", "Cloud runner (sample)", "Runner", "Asked for context", "acme-shop", .blocked,
            .blocked, code: "context.request", reason: "The lease for this runner had expired.", rule: expiredRule),
        ev(2024, "3 days ago", "Sync", "MacBook", "Synced 14 changes", "initech", .ok, .sync, code: "sync.push"),
        ev(
            2023, "4 days ago", "You", "Mac Studio", "Changed storage mode", "northwind", .ok, .changes,
            code: "room.mode.change"),
        ev(2022, "4 days ago", "Check", "Mac Studio", "Speed check passed", nil, .ok, .access, code: "check.run"),
        ev(
            2021, "5 days ago", "Sync", "iPhone", "Sync could not reach the server", "ainkrad", .failed, .sync,
            code: "sync.fault", reason: "The server was unreachable for 4 min. Changes were queued."),
        ev(
            2020, "6 days ago", "Embedding (sample)", "Mac Studio", "Sent text to a cloud model", "ainkrad", .ok,
            .access, code: "model.egress"),
    ]

    private static func call(
        _ id: String, _ at: String, _ room: String, _ kind: EgressKind, _ target: String, _ p: ProviderClass,
        _ ids: [String], block: EgressBlock? = nil, bytes: Int = 0, tin: Int = 0, tout: Int = 0, red: Int = 0,
        actor: String, session: String, approval: String? = nil
    ) -> EgressCall {
        EgressCall(
            id: id, at: at, room: room, kind: kind, target: target, provider: p, block: block, recordIDs: ids,
            bytes: bytes, tokensIn: tin, tokensOut: tout, redacted: red, actor: actor, sessionID: session,
            approvalID: approval)
    }

    static let calls: [EgressCall] = [
        call(
            "eg-0412", "2 min ago", "ainkrad", .model, "Sample cloud model A", .approvedCloud, ["r1", "r2", "r4"],
            bytes: 3400, tin: 812, tout: 240, actor: "Claude Code (sample)", session: "sess-7f3a", approval: "apr-p2"),
        call(
            "eg-0411", "9 min ago", "ainkrad", .embedding, "Sample local model", .local, ["r2"], bytes: 900, tin: 210,
            actor: "Embedding (sample)", session: "job-91c2"),
        call(
            "eg-0409", "1 h ago", "ainkrad", .distill, "Sample cloud model A", .approvedCloud, ["r4", "r7"],
            bytes: 5200, tin: 1320, tout: 410, red: 2, actor: "Distiller (sample)", session: "job-8d10",
            approval: "apr-p2"),
        call(
            "eg-0408", "1 h ago", "ainkrad", .rerank, "Sample cloud model B", .unapproved, ["r1", "r3"],
            block: .noApproval, actor: "Claude Code (sample)", session: "sess-7f3a"),
        call(
            "eg-0404", "3 h ago", "ainkrad", .model, "Sample cloud model A", .approvedCloud, ["r9"],
            block: .visibility, actor: "Codex (sample)", session: "sess-2b91", approval: "apr-p2"),
        call(
            "eg-0399", "Yesterday", "ainkrad", .model, "Sample cloud model A", .approvedCloud, ["r2", "r4", "r5"],
            bytes: 4100, tin: 990, tout: 300, actor: "Claude Code (sample)", session: "sess-1a44", approval: "apr-p2"),
        call(
            "eg-0410", "20 min ago", "acme-shop", .model, "Sample cloud model A", .approvedCloud, ["r10"],
            bytes: 2200, tin: 530, tout: 190, actor: "Cloud runner (sample)", session: "sess-c0de", approval: "apr-p2"),
        call(
            "eg-0405", "3 h ago", "acme-shop", .model, "Sample cloud model A", .approvedCloud, ["r11"],
            block: .expired, actor: "Cloud runner (sample)", session: "sess-c0de", approval: "apr-p2"),
        call(
            "eg-0407", "5 h ago", "globex", .embedding, "Sample cloud model B", .unapproved, ["r12"],
            block: .noApproval, actor: "Embedding (sample)", session: "job-77aa"),
        call(
            "eg-0406", "5 h ago", "globex", .embedding, "Sample local model", .local, ["r12"], bytes: 700,
            tin: 160, actor: "Embedding (sample)", session: "job-77ab"),
        call(
            "eg-0403", "1 h ago", "northwind", .model, "Sample cloud model A", .approvedCloud, ["r13"],
            block: .notListed, actor: "Cloud runner (sample)", session: "sess-bad1"),
    ]
}

extension String {
    fileprivate func leftPad(_ n: Int) -> String { String(repeating: "0", count: max(0, n - count)) + self }
}
#endif
