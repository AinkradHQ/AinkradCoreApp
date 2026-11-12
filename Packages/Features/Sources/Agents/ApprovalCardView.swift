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
            .animation(.smooth(duration: 0.35), value: status)
        }
        .accessibilityElement(children: .contain)
    }

    private var elevated: Bool { model.shell.elevatedUntil.map { $0 > Date() } ?? false }
    private var who: String {
        model.sessions.session(request.session).map { AgentWords.harnessName($0.harness) } ?? "An AI session"
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
                IconTile(ask.symbol, hue: GlassInk.orange, size: 44, bounce: request.id)
                    .shadow(color: GlassInk.orange.opacity(0.45), radius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(who) wants to \(ask.verb)").coreFont(size: MacTextSize.title, weight: .bold)
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
                            .coreFont(size: MacTextSize.large + 2, weight: .bold, design: .rounded).monospacedDigit()
                            .foregroundStyle(GlassInk.ink(hue)).contentTransition(.numericText(countsDown: true))
                        Text("to answer").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                }
            }
            if !request.input.isEmpty {
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: ask.wellSymbol).foregroundStyle(GlassInk.secondary)
                    Text(request.input).coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(5)
                        .textSelection(.enabled).agentCopyMenu(request.input)
                    Spacer(minLength: 0)
                }
                .padding(Space.s3)
                .background(Color.black.opacity(0.25), in: coreShape(Radius.control + 2))
                .overlay { coreShape(Radius.control + 2).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            }
            if request.timeoutSecs != nil {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        coreShape(3).fill(GlassInk.track.opacity(0.6))
                        coreShape(3)
                            .fill(
                                LinearGradient(
                                    colors: [hue.opacity(0.5), hue], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: g.size.width * min(1, max(0, ratio)))
                            .shadow(color: hue.opacity(0.5), radius: 5)
                    }
                }
                .frame(height: 6)
                .animation(.linear(duration: 1), value: ratio)
            }
            if let n = model.approvalNotices[request.id] { NoticeBanner(notice: n) }
            HStack(spacing: Space.s2) {
                answer(approve: false, busy: busy)
                if busy {
                    Text("Waiting for your Core…").coreFont(size: MacTextSize.meta).foregroundStyle(
                        GlassInk.secondary)
                }
                Spacer(minLength: 0)
                answer(approve: true, busy: busy)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s4)
        .background(GlassInk.orange.opacity(0.08), in: coreShape(Radius.cardMac))
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                GlassInk.orange.opacity(keys ? 0.6 : 0.35), lineWidth: keys ? 1.5 : 1)
        }
        .transition(.opacity.combined(with: .offset(y: coreMove(reduce, Space.s2))))
    }

    private func answer(approve: Bool, busy: Bool) -> some View {
        let tile = AppActionTile(
            title: approve ? (elevated ? "Approve" : "Approve with Touch ID") : "Deny",
            symbol: approve ? (elevated ? "checkmark" : "touchid") : "xmark", key: approve ? "⌘↩" : "⌘⌫",
            hue: approve ? GlassInk.blue : GlassInk.slate, prominent: approve  // blue primary: green is for status only
        ) { Task { await model.decide(request, approved: approve) } }
        .disabled(busy)
        .help(
            approve
                ? "Let \(who) \(ask.verb) (⌘Return). Asks for Touch ID when this Mac is locked."
                : "Tell \(who) no (⌘Delete). It carries on without it."
        )
        .accessibilityLabel(approve ? "Approve \(request.tool)" : "Deny \(request.tool)")
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
            IconTile(ok ? "checkmark" : "xmark", hue: hue, size: 26)
            Text("\(ok ? "Approved" : "Denied"): \(ask.verb)").coreFont(size: MacTextSize.body, weight: .semibold)
            Text(request.input).coreFont(size: MacTextSize.body, design: .monospaced).foregroundStyle(
                GlassInk.secondary
            )
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).frame(minHeight: 40)
        .background(GlassInk.well, in: coreShape(Radius.control + 2))
        .accessibilityElement(children: .combine)
    }

    private var expired: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            IconTile("clock.badge.xmark", hue: GlassInk.slate, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nobody answered in time: \(ask.verb)").coreFont(size: MacTextSize.body, weight: .semibold)
                Text(request.input).coreFont(size: MacTextSize.body, design: .monospaced)
                    .foregroundStyle(GlassInk.secondary).lineLimit(2)
                Text("The AI session stopped waiting for this. Ask it again from the composer if you still want it.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
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
