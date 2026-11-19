import CoreKit
import CoreUI
import Foundation
import Shell

/// Live AI sessions: one long conversation per session, like typing in `claude` in a terminal. The composer stays open while the
/// session is live, a turn can be stopped without ending the session, and only "End Session…" closes it.
extension AgentsModel {
    // MARK: list state

    /// The sidebar's counts and groups for what is loaded now.
    func makeIndex(now: Date = Date()) -> SessionIndex {
        let needs = Set(pending.map(\.session))
        return SessionIndex(
            SessionIndex.Inputs(
                items: sessions.items, needsYou: needs, pinned: pinned, archived: archived, now: now,
                title: { [self] in title($0) }, runnerName: { [self] in runnerName($0) }, project: { $0.project }))
    }

    func togglePin(_ id: String) {
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        defaults.set(Array(pinned), forKey: "aisessions.pinned")
    }

    /// Archive by hand (A); again on an archived one brings it back.
    func toggleArchive(_ id: String) {
        if archived.contains(id) { archived.remove(id) } else { archived.insert(id) }
        defaults.set(Array(archived), forKey: "aisessions.archived")
    }

    // MARK: new session

    /// ⌘N: a live session at once with the defaults and an empty composer. The best ready runner, the default tool and order.
    public func startLiveSession(runner: String? = nil, prompt: String = "") async -> InlineNotice? {
        await loadRunners()
        let prefs = AgentPrefs.shared
        let pick =
            runner ?? (prefs.runner.isEmpty ? nil : runners.first { $0.id == prefs.runner }?.id)
            ?? runners.first { $0.online && $0.runsAgents && !$0.degraded }?.id ?? runners.first { $0.online }?.id
        guard let pick else {
            return InlineNotice(
                title: "No runner is online.",
                detail: "Bring a runner online, or choose one in New AI session (advanced).")
        }
        let chain = defaultChain
        return await create(
            NewAgentSession(
                runner: pick, harness: prefs.harness, model: chain == nil && !prefs.model.isEmpty ? prefs.model : nil,
                prompt: prompt, mode: prefs.mode, chain: chain?.id))
    }

    // MARK: the live conversation

    /// The composer is open for any live session (it queues while a turn runs). A finished one is recovered, not written to.
    /// Live, lost or ended for being idle: the Core reopens the last two with the next message.
    public func canWrite(_ s: AgentSessionInfo) -> Bool { s.live || s.idleEnded || s.state == .lost }

    /// What Esc and "Stop turn" apply to: a turn is running (not idle) in a live session.
    public func canStopTurn(_ s: AgentSessionInfo) -> Bool {
        switch s.state {
        case .running, .starting: true
        default: false
        }
    }

    /// Stops the turn in flight; the session goes back to "Waiting for you".
    public func stopTurn(_ id: String) {
        guard let api, let s = sessions.session(id), canStopTurn(s) else { return }
        note(id, nil)
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await api.stopTurn(id)
                self.sessions.upsert(s)
                self.syncDerived()
            } catch { self.note(id, Self.notice(error, doing: "Stopping the turn")) }
        }
    }

    /// Stops one working sub-agent; the rest of the turn goes on. Its entry says how it ended when the tool reports it.
    public func stopSubagent(_ id: String, _ subagent: String) {
        guard let api, let s = sessions.session(id), s.canStopSubagents, canStopTurn(s) else { return }
        note(id, nil)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.elevated("Stop a sub-agent of \(AgentWords.toolName(s.harness)).") {
                    try await api.stopSubagent(id, subagent)
                }
            } catch { self.note(id, Self.notice(error, doing: "Stopping the sub-agent")) }
        }
    }

    /// Ends the session for good, after asking: the live process exits and the composer closes.
    public func confirmEnd(_ id: String) {
        guard let s = sessions.session(id), s.live else { return }
        shell.presentSheet(
            title: "End this AI session?",
            message:
                "\(AgentWords.toolName(s.harness)) exits and the composer closes. The transcript stays, and you can start a new AI session from it.",
            actions: [
                ShellSheetAction("Keep it open"),
                ShellSheetAction("End Session", primary: true, destructive: true) { [weak self] in self?.end(id) },
            ])
    }

    public func end(_ id: String) {
        guard let api else { return }
        note(id, nil)
        stopping[id] = .cancelling
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await self.elevated("End \(AgentWords.toolName(self.sessions.session(id)?.harness ?? "")).")
                {
                    try await api.end(id)
                }
                self.sessions.upsert(s)
                if s.over { self.stopping[id] = nil }
                self.syncDerived()
            } catch {
                self.stopping[id] = nil
                self.note(id, Self.notice(error, doing: "Ending the session"))
            }
        }
    }

    /// The last message you sent, for ↑ in the composer.
    func lastUserMessage(_ id: String) -> String? {
        transcripts[id]?.entries.last { if case .user = $0.kind { true } else { false } }
            .flatMap { if case .user(let t) = $0.kind { t } else { nil } }
    }

    /// Names a session from its first message when nobody did: the Core's title if it keeps one, else this Mac's.
    func nameFromFirstMessage(_ id: String, _ text: String) {
        guard sessions.session(id)?.title == nil, titles[id] == nil, let t = AgentWords.title(prompt: text) else {
            return
        }
        titles[id] = t
        refreshHeads()
        guard let api else { return }
        Task { _ = try? await api.rename(id, title: t) }
    }

    public func rename(_ id: String, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        titles[id] = t
        refreshHeads()
        guard let api else { return }
        Task { [weak self] in
            if let s = try? await api.rename(id, title: t) { self?.sessions.upsert(s) }
        }
    }

    // MARK: side panel facts

    /// Files this session touched, newest edit last, with the lines each added and removed.
    func filesTouched(_ id: String) -> [FileTouch] {
        var order: [String] = []
        var by: [String: FileTouch] = [:]
        func add(_ path: String, _ name: String, _ added: Int, _ removed: Int) {
            guard !path.isEmpty else { return }
            var t = by[path] ?? FileTouch(path: path, added: 0, removed: 0, created: name.lowercased() == "write")
            t.added += added
            t.removed += removed
            if by[path] == nil { order.append(path) }
            by[path] = t
        }
        // Every edit the conversation shows counts: a diff (toolEdit), or a plain Edit/Write step whose summary is the
        // path and whose output may say "+40 -6" (the review found the panel saying "Nothing changed yet" beside them).
        for e in transcripts[id]?.entries ?? [] {
            switch e.kind {
            case .toolEdit(_, let name, let path, let old, let new, let ok, _) where ok != false:
                let d = DiffLines.make(old: old, new: new)
                add(path, name, d.filter { $0.kind == .added }.count, d.filter { $0.kind == .removed }.count)
            case .toolDone(_, let name, let summary, true, _, let output, _) where Self.isEdit(name):
                let n = Self.lineCounts(output)
                add(summary, name, n.added, n.removed)
            default: break
            }
        }
        return order.compactMap { by[$0] }
    }

    static func isEdit(_ tool: String) -> Bool {
        ["edit", "write", "multiedit", "notebookedit"].contains(tool.lowercased())
    }

    /// "+40 -6" (or "+40 −6") in a tool's output: the lines it added and removed; zeros when it does not say.
    static func lineCounts(_ output: String) -> (added: Int, removed: Int) {
        let words = output.replacingOccurrences(of: "−", with: "-").split(whereSeparator: \.isWhitespace)
        let added = words.first { $0.hasPrefix("+") }.flatMap { Int($0.dropFirst()) } ?? 0
        let removed = words.first { $0.hasPrefix("-") }.flatMap { Int($0.dropFirst()) } ?? 0
        return (added, removed)
    }

    /// Cost of each turn with its number, from the turn separators. A turn without a cost keeps its number, so the
    /// card's "Turn 2" is the transcript's "Turn 2 done".
    func turnCosts(_ id: String) -> [(turn: Int, cost: Int64)] {
        let costs = (transcripts[id]?.entries ?? []).compactMap { e -> Int64?? in
            if case .turnEnded(let c, _) = e.kind { c } else { nil }
        }
        return costs.enumerated().compactMap { i, c in c.map { (i + 1, $0) } }
    }
}

struct FileTouch: Equatable, Identifiable {
    var path: String
    var added: Int
    var removed: Int
    var created: Bool
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}
