import CoreUI
import SwiftUI

/// An agent's request, in words (Ahmed, 2026-11-05: plain words, visual, keyboard driven): what it wants to do as a sentence,
/// the exact command or file in a well, where and when, a live countdown with a bar, then Deny on the left and Approve on the
/// right. ⌘Return approves and ⌘⌫ denies while `keys` is on. Decided ones fold to a sentence; expired ones dim.
struct ApprovalCardView: View {
    @Bindable var model: AgentsModel
    let request: ApprovalRequest
    var keys = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let over = model.sessions.session(request.session)?.over ?? false
            let status = request.status(now: ctx.date, sessionOver: over)
            Group {
                switch status {
                case .pending: card(now: ctx.date)
                case .approved, .denied: line(status)
                case .expired: expired
                }
            }
            .animation(Motion.out(Motion.move), value: status)
        }
        .accessibilityElement(children: .contain)
    }

    private var elevated: Bool { model.shell.elevatedUntil.map { $0 > Date() } ?? false }
    private var who: String {
        model.sessions.session(request.session).map { AgentWords.harness($0.harness) } ?? "An agent"
    }
    private var ask: ApprovalWords.Ask { ApprovalWords.ask(request.tool) }

    private func card(now: Date) -> some View {
        let busy = model.deciding.contains(request.id)
        let left = request.remaining(now: now)
        let ratio = left.map { $0 / Double(max(request.timeoutSecs ?? 1, 1)) } ?? 1
        let hue = (left ?? 999) <= 20 ? GlassInk.red : (left ?? 999) <= 60 ? GlassInk.orange : GlassInk.blue
        let session = model.sessions.session(request.session)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                IconTile(ask.symbol, hue: GlassInk.orange, size: Space.s8 + Space.s3, bounce: request.id)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text("\(who) wants to \(ask.verb)").font(.system(size: MacTextSize.title, weight: .semibold))
                    Text(
                        "On \(session.map { model.runnerName($0.runner) } ?? "a runner") · asked \(AgentWords.ago(request.requestedAt, now: now))"
                    )
                    .foregroundStyle(GlassInk.secondary)
                    .help("Session \(request.session) · tool \(request.tool) · request \(request.id)")
                }
                Spacer(minLength: Space.s3)
                if let left {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(AgentWords.clock(left))
                            .font(.system(size: MacTextSize.large, weight: .semibold).monospacedDigit())
                            .foregroundStyle(hue).contentTransition(.numericText(countsDown: true))
                        Text("to answer").font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    }
                }
            }
            if !request.input.isEmpty {
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: ask.wellSymbol).foregroundStyle(GlassInk.secondary)
                    Text(request.input).font(.system(size: MacTextSize.body, design: .monospaced)).lineLimit(5)
                        .textSelection(.enabled).agentCopyMenu(request.input)
                    Spacer(minLength: 0)
                }
                .padding(Space.s3)
                .background(GlassInk.well, in: coreShape(Radius.cardMac))
                .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            }
            if request.timeoutSecs != nil {
                CoreMeter(ratio, low: (left ?? 999) <= 60, label: "Time left to answer")
            }
            if let n = model.approvalNotices[request.id] { NoticeBanner(notice: n) }
            HStack(spacing: Space.s2) {
                answer(approve: false, busy: busy)
                if busy {
                    Text("Waiting for your Core…").font(.system(size: MacTextSize.meta)).foregroundStyle(
                        GlassInk.secondary)
                }
                Spacer(minLength: 0)
                answer(approve: true, busy: busy)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s4)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1, active: keys)
        .transition(.opacity.combined(with: .offset(y: coreMove(reduce, Space.s2))))
    }

    private func answer(approve: Bool, busy: Bool) -> some View {
        let tile = AppActionTile(
            title: approve ? (elevated ? "Approve" : "Approve with Touch ID") : "Deny",
            symbol: approve ? (elevated ? "checkmark" : "touchid") : "xmark", key: approve ? "⌘↩" : "⌘⌫",
            hue: approve ? GlassInk.blue : GlassInk.slate, prominent: approve
        ) { Task { await model.decide(request, approved: approve) } }
        .disabled(busy)
        .help(
            approve
                ? "Let \(who) \(ask.verb) (⌘Return). Asks for Touch ID when this Mac is locked."
                : "Tell \(who) no (⌘Delete). It carries on without it."
        )
        .accessibilityLabel(approve ? "Approve: \(ask.verb)" : "Deny: \(ask.verb)")
        return Group {
            if keys {
                if approve {
                    tile.keyboardShortcut(.return, modifiers: .command)
                } else {
                    tile.keyboardShortcut(.delete, modifiers: .command)
                }
            } else {
                tile
            }
        }
    }

    private func line(_ status: ApprovalRequest.Status) -> some View {
        let ok = status == .approved
        let hue = ok ? GlassInk.green : GlassInk.slate
        return HStack(spacing: Space.s3) {
            IconTile(ok ? "checkmark" : "xmark", hue: hue, size: MacSize.controlMd)
            Text("\(ok ? "Approved" : "Denied"): \(ask.verb)").font(.system(size: MacTextSize.body, weight: .semibold))
            Text(request.input).font(.system(size: MacTextSize.body, design: .monospaced)).foregroundStyle(
                GlassInk.secondary
            )
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).frame(minHeight: 40)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
    }

    private var expired: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            IconTile("clock.badge.xmark", hue: GlassInk.slate, size: MacSize.controlMd)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nobody answered in time: \(ask.verb)").font(.system(size: MacTextSize.body, weight: .semibold))
                Text(request.input).font(.system(size: MacTextSize.body, design: .monospaced))
                    .foregroundStyle(GlassInk.secondary).lineLimit(2)
                Text("The agent stopped waiting for this. Ask it again from the composer if you still want it.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(GlassInk.well.opacity(0.7), in: coreShape(Radius.cardMac))
        .opacity(0.8)
        .accessibilityElement(children: .combine)
    }
}

/// A tool request as a sentence: `Bash` is "run a command", `Edit` is "change a file". The tool's own name stays as hover help.
enum ApprovalWords {
    struct Ask {
        let verb: String
        let symbol: String
        let wellSymbol: String
    }

    static func ask(_ tool: String) -> Ask {
        switch tool.lowercased() {
        case "bash", "shell", "exec", "command":
            Ask(verb: "run a command", symbol: "terminal.fill", wellSymbol: "chevron.right")
        case "edit", "write", "multiedit", "notebookedit", "apply_patch":
            Ask(verb: "change a file", symbol: "pencil", wellSymbol: "doc.text")
        case "read", "glob", "grep", "ls":
            Ask(verb: "read files", symbol: "doc.text.magnifyingglass", wellSymbol: "doc.text")
        case "webfetch", "websearch", "fetch": Ask(verb: "reach the internet", symbol: "globe", wellSymbol: "link")
        case "secrets", "secret": Ask(verb: "use a secret", symbol: "key.fill", wellSymbol: "key")
        default: Ask(verb: "use \(tool)", symbol: "lock.shield.fill", wellSymbol: "chevron.right")
        }
    }
}
