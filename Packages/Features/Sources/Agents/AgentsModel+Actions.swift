import CoreKit
import CoreUI
import Foundation
import Shell

/// Everything done to a session. Each needs a live Touch ID (the Core marks them destructive): ask first when the session is
/// not elevated, and once more if the Core still says `step_up_required`.
extension AgentsModel {
    func elevated<T>(_ reason: String, _ op: () async throws -> T) async throws -> T {
        if let host, let n = await host.elevate(reason: reason, force: false) { throw ElevationDeclined(notice: n) }
        do { return try await op() } catch {
            guard case .stepUpRequired = CoreError.unwrapping(error), let host else { throw error }
            if let n = await host.elevate(reason: reason, force: true) { throw ElevationDeclined(notice: n) }
            return try await op()
        }
    }

    /// The words for something that went wrong, in place.
    static func notice(_ error: any Error, doing: String) -> InlineNotice {
        if let d = error as? ElevationDeclined { return d.notice }
        let e = CoreError.unwrapping(error)
        let words = e?.localizedDescription ?? error.localizedDescription
        return InlineNotice(title: "\(doing) did not go through.", detail: words)
    }

    func note(_ id: String, _ n: InlineNotice?) { notices[id] = n }

    // MARK: composer

    public func canSend(_ id: String) -> Bool {
        let text = drafts[id] ?? ""
        var running = false
        if case .running? = sessions.session(id)?.state { running = true }
        return running && !text.isEmpty && text.utf8.count <= Self.messageLimit && !sending.contains(id)
    }
    public static let messageLimit = 16 * 1024

    public func send(_ id: String) async {
        guard let api, canSend(id), let text = drafts[id] else { return }
        sending.insert(id)
        note(id, nil)
        defer { sending.remove(id) }
        do {
            let s = try await elevated("Send a message to \(sessions.session(id)?.harness ?? "the agent").") {
                try await api.send(id, text: text)
            }
            drafts[id] = ""
            sessions.upsert(s)
            if let t = transcripts[id] { await t.refresh(api, knownLast: s.lastSeq) }
        } catch {
            note(id, Self.notice(error, doing: "Sending"))
        }
    }

    // MARK: cancel, kill, resume, wake

    /// Cancel and Kill ask first: what the agent already did stays, but it stops.
    public func confirmCancel(_ id: String) {
        guard let s = sessions.session(id) else { return }
        shell.presentSheet(
            title: "Cancel this session?",
            message:
                "\(s.harness) finishes the tool call in flight, then the session ends as cancelled. What it already did stays in the transcript.",
            actions: [
                ShellSheetAction("Keep running"),
                ShellSheetAction("Cancel session", primary: true, destructive: true) { [weak self] in
                    self?.run(id, "Cancelling", stop: .cancelling) { try await $0.cancel(id) }
                },
            ])
    }

    public func confirmKill(_ id: String) {
        guard let s = sessions.session(id) else { return }
        shell.presentSheet(
            title: "Kill this session?",
            message:
                "Cancel asks \(s.harness) to stop. Kill stops it at once on \(runnerName(s.runner)) and can leave files half-written. Use it only if Cancel did not work.",
            actions: [
                ShellSheetAction("Keep running"),
                ShellSheetAction("Kill session", primary: true, destructive: true) { [weak self] in
                    self?.run(id, "Killing", stop: .killing) { try await $0.kill(id) }
                },
            ])
    }

    public func resume(_ id: String) { run(id, "Resuming") { try await $0.resume(id) } }

    public func wake(_ id: String) {
        guard let api else { return }
        note(id, nil)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.elevated("Wake \(self.sessions.session(id)?.harness ?? "the agent").") {
                    try await api.wake(id, key: UUID().uuidString)
                }
                self.shell.showToast("Wake sent. The session starts again from its last turn.")
                await self.refreshSession(id)
            } catch { self.note(id, Self.notice(error, doing: "Waking")) }
        }
    }

    private func run(
        _ id: String, _ doing: String, stop: StopKind? = nil,
        _ op: @escaping @Sendable (any AgentsAPI) async throws -> AgentSessionInfo
    ) {
        guard let api else { return }
        note(id, nil)
        let h = sessions.session(id)?.harness ?? "the agent"
        if let stop { stopping[id] = stop }
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await self.elevated("\(doing) \(h).") { try await op(api) }
                self.sessions.upsert(s)
                if s.over { self.stopping[id] = nil }
                self.syncDerived()
            } catch {
                if stop != nil { self.stopping[id] = nil }
                self.note(id, Self.notice(error, doing: doing))
            }
        }
    }

    // MARK: approvals

    /// ⌘Return and ⌘⌫ land here, as do the buttons. The choice shows at once; the Core confirms it with an event.
    public func decide(_ r: ApprovalRequest, approved: Bool) async {
        guard let api, !deciding.contains(r.id) else { return }
        deciding.insert(r.id)
        approvalNotices[r.id] = nil
        let t = store(r.session)
        defer { deciding.remove(r.id) }
        do {
            _ = try await elevated("\(sessions.session(r.session)?.harness ?? "An agent") asks to use \(r.tool).") {
                t.mark(r.id, approved: approved)
                return try await api.decide(r.session, request: r.id, approved: approved)
            }
            await refreshSession(r.session)
            syncDerived()
        } catch {
            t.unmark(r.id)
            approvalNotices[r.id] = Self.notice(error, doing: approved ? "Approving" : "Denying")
        }
    }

    // MARK: new session

    public func loadRunners() async {
        if let api, let r = try? await api.runners() { runners = r }
        if let api { setChains((try? await api.chains()) ?? []) }
    }

    /// Starts a session. The error comes back as words for the sheet; nothing is half done.
    public func create(_ new: NewAgentSession) async -> InlineNotice? {
        guard let api else { return InlineNotice(title: "Connect to a Core first.") }
        do {
            let s = try await elevated("Start \(new.harness) on \(runnerName(new.runner)).") {
                try await api.create(new)
            }
            sessions.upsert(s)
            openSession(s.id)
            shell.showToast("Session created")
            return nil
        } catch {
            if let e = CoreError.unwrapping(error) {
                if case .http(_, let code, let message) = e {
                    let said = message.hasSuffix(".") ? message : message + "."
                    return InlineNotice(title: Self.refusal(code), detail: "\(said) \(Self.fix(code))")
                }
                if case .forbiddenScope = e {
                    return InlineNotice(
                        title: "Only an admin can start a session from a chain or an agent.",
                        detail:
                            "Use a device that holds the admin scope, or start a plain session by choosing a harness.")
                }
            }
            return Self.notice(error, doing: "Starting the session")
        }
    }

    /// The Core's refusal words, by its code; a code this build does not know shows as it is.
    static func refusal(_ code: String) -> String {
        switch code {
        case "runner_offline": "That runner is offline"
        case "unsupported_command": "That runner cannot run agents"
        case "runner_busy": "That runner is too busy right now"
        default: "The Core refused: \(code)"
        }
    }

    /// What to do about it, in a sentence.
    static func fix(_ code: String) -> String {
        switch code {
        case "runner_offline": "Pick another runner, or bring this one back online."
        case "unsupported_command": "Pick a runner that can run agents."
        case "runner_busy": "Wait a moment and choose Try again, or pick another runner."
        default: "Check what you chose and choose Try again."
        }
    }
}
