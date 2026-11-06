import CoreUI
import Foundation
import Shell
import SwiftUI

/// The module's place in the shell: panes, the dialog for new sessions and approvals, launcher entries, the bell.
extension AgentsModel {
    static let listPane = "agents.list"
    static func paneID(_ session: String) -> String { "agents.s-\(session)" }

    static func harnessSymbol(_ h: String) -> String {
        switch h {
        case "claude": "sparkles"
        case "codex": "chevron.left.forwardslash.chevron.right"
        default: "terminal"
        }
    }

    // MARK: panes

    public func openList() {
        shell.openPane(
            PaneSpec(id: Self.listPane, title: "Agents", sub: "Home Core", symbol: "sparkles", chip: listChip) {
                AgentsListView(model: self)
            })
    }

    public func openSession(_ id: String) {
        selected = id
        _ = transcript(id)
        shell.closeDialog()
        guard let s = sessions.session(id) else {
            // Not in the loaded page (an old one from a notification): fetch it, then open.
            Task { [weak self] in
                await self?.refreshSession(id)
                if self?.sessions.session(id) != nil { self?.openSession(id) }
            }
            return
        }
        let head = head(s)
        shell.openPane(
            PaneSpec(
                id: Self.paneID(id), title: head.title, sub: head.sub, symbol: Self.harnessSymbol(s.harness),
                chip: head.chip, minWidth: 460
            ) { SessionView(model: self, sessionID: id) })
    }

    func head(_ s: AgentSessionInfo) -> (title: String, sub: String, chip: PaneChip) {
        let st = AgentWords.status(s, waiting: waiting(s.id))
        return (
            s.harness, "\(runnerName(s.runner)) · \(s.shortID)", PaneChip(st.label, tone: st.tone, symbol: st.symbol)
        )
    }

    var listChip: PaneChip? {
        let n = pending.count
        return n > 0 ? PaneChip("\(n) waiting on you", tone: .warn, symbol: "hand.raised") : nil
    }

    func refreshHeads() {
        for p in shell.panes where p.id.hasPrefix("agents.s-") {
            let id = String(p.id.dropFirst("agents.s-".count))
            if let s = sessions.session(id) {
                let h = head(s)
                shell.updatePane(p.id, title: h.title, sub: .some(h.sub), chip: .some(h.chip))
            }
        }
        shell.updatePane(Self.listPane, title: nil, sub: nil, chip: .some(listChip))
    }

    // MARK: dialogs

    /// Quick by default (one prompt, the defaults); `advanced` opens the full sheet (Ahmed, 2026-11-05).
    public func openNewSession(advanced: Bool = false) {
        Task { await loadRunners() }
        if advanced {
            shell.present(ShellDialog(id: "agents.new") { NewSessionSheet(model: self) })
        } else {
            shell.present(ShellDialog(id: "agents.quick") { QuickSessionView(model: self) })
        }
    }

    public func openInbox() {
        shell.present(ShellDialog(id: "agents.inbox") { InboxView(model: self) })
    }

    // MARK: launcher

    func registerBase() {
        shell.launcher.register(
            LauncherEntry(
                id: "agents.list", title: "Agents", sub: "sessions on the Home Core", symbol: "sparkles",
                keywords: ["sessions", "claude", "codex", "agent"]
            ) { [weak self] in self?.openList() })
        shell.launcher.register(
            LauncherEntry(
                id: "agents.new", title: "New agent session", sub: "One prompt, the defaults · needs Touch ID",
                symbol: "plus", keywords: ["start", "create", "agent", "claude", "codex"], isAction: true
            ) { [weak self] in self?.openNewSession() })
        shell.launcher.register(
            LauncherEntry(
                id: "agents.new-advanced", title: "New agent session (advanced)…",
                sub: "Choose the harness, runner, model, mode and secrets", symbol: "slider.horizontal.3",
                keywords: ["start", "agent", "harness", "codex", "model"], isAction: true
            ) { [weak self] in self?.openNewSession(advanced: true) })
        shell.launcher.register(
            LauncherEntry(
                id: "agents.inbox", title: "Approvals", sub: "what agents are waiting on you for",
                symbol: "lock.shield", keywords: ["inbox", "approve", "touch id", "deny"]
            ) { [weak self] in self?.openInbox() })
        shell.launcher.register(
            LauncherEntry(
                id: "settings.agents", title: "Agents settings", sub: "Surface and the defaults for new sessions",
                symbol: "gearshape", keywords: ["appearance", "defaults", "harness", "agent"]
            ) { [weak self] in
                self?.shell.settings.selected = "agents"
                self?.shell.open(.settings)
            })
        shell.settings.section(
            SettingsSection(
                id: "agents", group: .apps, title: "Agents", sub: "Surface and the defaults for new sessions",
                symbol: "sparkles", order: 30
            ) { AgentSettingsView(model: self) })
        shell.settings.section(
            SettingsSection(
                id: "notifications", group: .notifications, title: "Notifications", symbol: "bell", order: 0
            ) {
                NotificationsSection(model: self)
            })
    }

    /// One entry per loaded session, so ⌘K finds a session by its harness, runner or state.
    func syncLauncher() {
        let items = sessions.items.prefix(40)
        let ids = Set(items.map { "agents.s-\($0.id)" })
        for old in launcherIDs.subtracting(ids) { shell.launcher.unregister(old) }
        for s in items {
            let st = AgentWords.status(s, waiting: false).label
            shell.launcher.register(
                LauncherEntry(
                    id: "agents.s-\(s.id)", title: "\(s.harness) · \(s.shortID)",
                    sub: "\(runnerName(s.runner)) · \(st)", symbol: Self.harnessSymbol(s.harness),
                    keywords: ["agent", "session", s.harness, runnerName(s.runner), st]
                ) { [weak self] in self?.openSession(s.id) })
        }
        launcherIDs = ids
    }

    // MARK: bell, notifications, heads

    /// After anything changed: panes' heads, launcher entries, the bell, macOS notifications for new approvals.
    func syncDerived() {
        refreshHeads()
        syncLauncher()
        let now = Date()
        let list = pending
        let live = Set(list.map { $0.key })
        for gone in registered.subtracting(live) {
            shell.bell.remove(gone)
            notifier.clear(id: gone)
        }
        registered = live
        for r in list {
            shell.bell.add(bellItem(r, now: now))
            let id = r.key
            if primed, !announced.contains(id) {
                announced.insert(id)
                if notifyApprovals {
                    let h = sessions.session(r.session)?.harness ?? "An agent"
                    notifier.post(
                        id: id, title: "\(h) needs approval", body: "\(r.tool): \(r.input)".prefix(180).description,
                        session: r.session)
                }
            } else {
                announced.insert(id)
            }
        }
        if list.isEmpty {
            ticker?.cancel()
            ticker = nil
        } else if ticker == nil {
            ticker = Task { [weak self] in
                // Expiry is only noticed by looking: one look a second while something waits, none otherwise.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    if self.pending.count != self.registered.count { self.syncDerived() }
                }
            }
        }
    }

    func bellItem(_ r: ApprovalRequest, now: Date) -> BellItem {
        let s = sessions.session(r.session)
        let left = r.remaining(now: now).map { "expires in \(AgentWords.clock($0))" }
        return BellItem(
            id: r.key, kind: .approval,
            title: "\(s?.harness ?? "An agent") wants to use \(r.tool)",
            sub: [s.map { runnerName($0.runner) }, r.input.isEmpty ? nil : r.input, left].compactMap { $0 }
                .joined(separator: " · "),
            time: AgentWords.ago(r.requestedAt, now: now),
            actions: [
                BellAction("Deny") { [weak self] in Task { await self?.decide(r, approved: false) } },
                BellAction("Review") { [weak self] in
                    self?.shell.toggleBell()
                    self?.openSession(r.session)
                },
                BellAction("Approve", primary: true) { [weak self] in Task { await self?.decide(r, approved: true) } },
            ])
    }
}
