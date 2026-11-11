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
        return InlineNotice(title: "\(doing) did not go through.", detail: sentence(words))
    }

    /// The Core's refusals are short lower-case phrases: say the known ones plainly, and make the rest a sentence.
    static func sentence(_ words: String) -> String {
        switch words {
        case "only a lost or interrupted session is resumed":
            return "Only a session that was lost or interrupted can be resumed. This one is running or finished."
        case "the session's account is full: resume again when one of its sessions ends":
            return "The account this session runs on is full. Try again when one of its sessions ends."
        default:
            guard let first = words.first else { return words }
            let s = first.uppercased() + words.dropFirst()
            return s.hasSuffix(".") || s.hasSuffix("?") || s.hasSuffix("!") ? s : s + "."
        }
    }

    func note(_ id: String, _ n: InlineNotice?) { notices[id] = n }

    // MARK: composer

    /// A running session takes a reply; a finished one (it succeeded) takes the next turn, which wakes it.
    public func canReply(_ s: AgentSessionInfo) -> Bool {
        if case .running = s.state { return true }
        if case .ended = s.state, s.outcome == .succeeded { return true }
        return false
    }

    public func canSend(_ id: String) -> Bool {
        let text = drafts[id] ?? ""
        guard let s = sessions.session(id) else { return false }
        return canReply(s) && !text.isEmpty && text.utf8.count <= Self.messageLimit && !sending.contains(id)
    }
    public static let messageLimit = 16 * 1024

    public func send(_ id: String) async {
        guard let api, canSend(id), let text = drafts[id] else { return }
        sending.insert(id)
        note(id, nil)
        defer { sending.remove(id) }
        if case .ended? = sessions.session(id)?.state {
            await wake(id, text: text)
            return
        }
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

    /// Wake with no message: the session continues from its last turn.
    public func wake(_ id: String) { Task { await wake(id, text: nil) } }

    /// The next turn on a finished session (the harness runs one turn at a time). With `text` the draft is cleared once the
    /// Core takes it.
    func wake(_ id: String, text: String?) async {
        guard let api else { return }
        note(id, nil)
        do {
            try await elevated("Wake \(sessions.session(id)?.harness ?? "the agent").") {
                try await api.wake(id, key: UUID().uuidString, text: text)
            }
            if text != nil { drafts[id] = "" }
            shell.showToast(
                text == nil ? "Wake sent. The session starts again from its last turn." : "Waiting for the agent…")
            await refreshSession(id)
        } catch { note(id, Self.notice(error, doing: "Waking")) }
    }

    /// An ended session cannot be resumed: start a new one with the same prompt, runner and agent.
    public func startAgain(_ id: String) {
        guard let s = sessions.session(id) else { return }
        let prompt = transcripts[id]?.entries.lazy.compactMap { e -> String? in
            if case .user(let t) = e.kind { return t } else { return nil }
        }.first
        guard let prompt, !prompt.isEmpty else {
            note(
                id,
                InlineNotice(
                    title: "Starting again did not go through.",
                    detail: "The first message is not loaded. Scroll the transcript to its start and try again."))
            return
        }
        let agent = s.route?.agent
        let new = NewAgentSession(
            runner: s.runner, harness: s.harness, model: s.model, prompt: prompt,
            chain: agent == nil ? s.route?.chainID : nil, agent: agent)
        Task { [weak self] in
            if let n = await self?.create(new) { self?.note(id, n) }
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
            if let e = CoreError.unwrapping(error), case .http(let status, _, _) = e, status == 404 || status == 409 {
                approvalNotices[r.id] = InlineNotice(
                    title: "This request was already answered or expired.", detail: "Nothing was changed.",
                    symbol: "clock.badge.exclamationmark", tone: .queue)
            } else {
                approvalNotices[r.id] = Self.notice(error, doing: approved ? "Approving" : "Denying")
            }
        }
    }

    // MARK: new session

    public func loadRunners() async {
        if let api, let r = try? await api.runners() { runners = r }
        if let api { setChains((try? await api.chains()) ?? []) }
        if let api { agentNames = (try? await api.agents()) ?? [] }
    }

    /// Starts a session. The error comes back as words for the sheet; nothing is half done.
    public func create(_ new: NewAgentSession) async -> InlineNotice? {
        guard let api else { return InlineNotice(title: "Connect to a Core first.") }
        do {
            let s = try await elevated("Start \(new.harness) on \(runnerName(new.runner)).") {
                try await api.create(new)
            }
            sessions.upsert(s)
            if let t = AgentWords.title(prompt: new.prompt) { titles[s.id] = t }
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
