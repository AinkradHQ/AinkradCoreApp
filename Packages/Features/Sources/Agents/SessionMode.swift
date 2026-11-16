import CoreUI
import SwiftUI

/// How a session works (Ahmed, 2026-11-16: "no option shows the permissions or the harness type (build or plan)"):
/// Plan reads and plans, edits nothing; Build asks first, or accepts edits in its folder; Sandboxed runs in a sandbox and
/// asks for nothing (chosen at start: it decides where the session runs). The Core enforces it (`setAgentSessionMode`).
public enum SessionMode: String, CaseIterable, Equatable, Sendable {
    case plan, ask, acceptEdits, sandboxed

    public static func of(_ s: AgentSessionInfo) -> SessionMode? {
        guard let p = s.policy else { return nil }
        if s.plan { return .plan }
        return switch p {
        case "accept_edits": .acceptEdits
        case "sandboxed": .sandboxed
        default: .ask
        }
    }

    /// What the Core takes: the permission and Plan.
    var change: (policy: String?, plan: Bool) {
        switch self {
        case .plan: (nil, true)
        case .ask: ("ask", false)
        case .acceptEdits: ("accept_edits", false)
        case .sandboxed: ("sandboxed", false)
        }
    }

    public var title: String {
        switch self {
        case .plan: "Plan"
        case .ask: "Asks first"
        case .acceptEdits: "Accepts edits"
        case .sandboxed: "Sandboxed"
        }
    }

    var symbol: String {
        switch self {
        case .plan: "list.bullet.clipboard"
        case .ask: "hand.raised"
        case .acceptEdits: "pencil.line"
        case .sandboxed: "shippingbox"
        }
    }

    var help: String {
        switch self {
        case .plan: "Plan: it reads and plans, edits nothing, and ends with a plan for you to approve."
        case .ask: "Build, asks first: every edit and command waits for your approval."
        case .acceptEdits: "Build, accepts edits: edits in the session's folder go ahead; commands still ask."
        case .sandboxed: "Sandboxed: runs in a sandbox and asks for nothing. Chosen when the session starts."
        }
    }

    /// ⇧⇥, as in Claude Code: Asks first → Accepts edits → Plan → Asks first. Plan only where the tool has it; a
    /// sandboxed session does not cycle.
    public func next(harness: String) -> SessionMode? {
        switch self {
        case .ask: .acceptEdits
        case .acceptEdits: harness == "claude" ? .plan : .ask
        case .plan: .ask
        case .sandboxed: nil
        }
    }

    /// The permission modes a new session can start in (the new-session sheet), in plain words.
    static let all = ["ask", "accept_edits", "sandboxed"]
    static func words(_ mode: String) -> String {
        switch mode {
        case "ask": "Asks first"
        case "sandboxed": "Sandboxed"
        default: "Accepts edits"
        }
    }
    static func help(_ mode: String) -> String {
        switch mode {
        case "ask": "Asks you before each tool call that changes something."
        case "sandboxed": "Runs in a sandbox and asks for nothing. Needs the admin scope."
        default: "Edits files without asking; still asks before running commands."
        }
    }

    static func words(policy: String, plan: Bool) -> String {
        plan ? "Plan" : policy == "accept_edits" ? "Accepts edits" : policy == "sandboxed" ? "Sandboxed" : "Asks first"
    }
}

extension AgentsModel {
    /// Switches the session's mode; a step-up first, as the Core asks for it (it can widen what the tool does unasked).
    public func setMode(_ id: String, policy: String?, plan: Bool?) async {
        guard let api, sessions.session(id) != nil else { return }
        note(id, nil)
        do {
            let s = try await elevated("Change how the AI session works.") {
                try await api.setMode(id, policy: policy, plan: plan)
            }
            sessions.upsert(s)
            if let t = transcripts[id] { await t.refresh(api, knownLast: s.lastSeq) }
        } catch {
            note(id, Self.notice(error, doing: "Changing the mode"))
        }
    }

    func setMode(_ id: String, to mode: SessionMode) async {
        let c = mode.change
        await setMode(id, policy: c.policy, plan: c.plan)
    }
}

/// The composer's mode control, beside the model: the mode's icon and name, a menu of the others (⇧⇥ cycles them).
struct ModeChip: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo

    var body: some View {
        if let mode = SessionMode.of(session) {
            CoreDropdown(
                items: SessionMode.allCases.filter { $0 != .plan || session.harness == "claude" }.map { m in
                    CoreDropdownItem(
                        m.title, symbol: m.symbol, enabled: m != .sandboxed || mode == .sandboxed, checked: m == mode,
                        note: m == .sandboxed && mode != .sandboxed ? "chosen at start" : nil
                    ) {
                        guard m != mode else { return }
                        Task { await model.setMode(session.id, to: m) }
                    }
                }
            ) {
                HStack(spacing: Space.s1) {
                    Image(systemName: mode.symbol)
                    Text(mode.title)
                    Image(systemName: "chevron.up.chevron.down").coreFont(size: MacTextSize.meta - 1)
                }
                .coreFont(size: MacTextSize.meta, weight: .medium)
                .foregroundStyle(mode == .plan ? SessionInk.text : SessionInk.text2)
                .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                .background(mode == .plan ? SessionInk.selected : SessionInk.row, in: coreShape(Radius.chip))
            }
            .help(mode.help + " (⇧⇥ switches)")
            .accessibilityLabel("Mode: \(mode.title)")
        }
    }
}
