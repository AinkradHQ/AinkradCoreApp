import CoreUI
import SwiftUI

/// An agent's request to use a tool, with what it would do, the time left, and the two answers. ⌘Return approves and ⌘⌫ denies
/// while `keys` is on (the card the keyboard acts on). Decided and expired ones fold to a line or a dimmed card.
struct ApprovalCardView: View {
    @Bindable var model: AgentsModel
    let request: ApprovalRequest
    var keys = false
    @Environment(\.corePalette) private var palette
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
        }
        .accessibilityElement(children: .contain)
    }

    private var elevated: Bool { model.shell.elevatedUntil.map { $0 > Date() } ?? false }
    private var harness: String { model.sessions.session(request.session)?.harness ?? "An agent" }

    private func card(now: Date) -> some View {
        let busy = model.deciding.contains(request.id)
        let left = request.remaining(now: now)
        let ratio = (left.map { $0 / Double(max(request.timeoutSecs ?? 1, 1)) }) ?? 1
        let tone: Tone = (left ?? 999) <= 20 ? .fail : (left ?? 999) <= 60 ? .warn : .run
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "lock.shield").font(.system(size: MacTextSize.title)).foregroundStyle(palette.btnInk)
                    .frame(width: MacSize.controlLg + 2, height: MacSize.controlLg + 2)
                    .background(palette.btnPrimary, in: coreShape(Radius.control)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("\(harness) wants to use \(request.tool)").font(
                        .system(size: MacTextSize.headline, weight: .semibold))
                    if !request.input.isEmpty {
                        Text(request.input).font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.text2)
                            .lineLimit(4).agentCopyMenu(request.input)
                    }
                }
                Spacer(minLength: 0)
            }
            facts(now: now, left: left, tone: tone)
            if request.timeoutSecs != nil { MeterBar(value: ratio, tone: tone) }
            if let n = model.approvalNotices[request.id] { NoticeBanner(notice: n) }
            HStack(spacing: Space.s2) {
                if busy {
                    Text("Waiting for the Core…").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
                answer("Deny", keycap: "⌘⌫", prominent: false, busy: busy)
                answer(elevated ? "Approve" : "Approve with Touch ID", keycap: "⌘↩", prominent: true, busy: busy)
            }
        }
        .padding(Space.s4)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(palette.navActiveEdge, lineWidth: 1) }
        .transition(.opacity.combined(with: .offset(y: coreMove(reduce, Space.s2))))
    }

    private func facts(now: Date, left: TimeInterval?, tone: Tone) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Space.s4, verticalSpacing: Space.s1) {
            GridRow {
                fact("Session", "\(harness) · \(model.sessions.session(request.session)?.shortID ?? request.session)")
                fact("Runner", model.sessions.session(request.session).map { model.runnerName($0.runner) } ?? "")
                fact("Asked", AgentWords.ago(request.requestedAt, now: now))
                // The time left is words and a bar: the tone only backs them up.
                fact("Expires", left.map { AgentWords.clock($0) } ?? "no time limit", mono: true)
            }
        }
    }

    private func fact(_ k: String, _ v: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            Text(v).font(.system(size: MacTextSize.body, weight: .medium, design: mono ? .monospaced : .default))
                .lineLimit(1)
        }
    }

    private func answer(_ title: String, keycap: String, prominent: Bool, busy: Bool) -> some View {
        let approve = prominent
        let b = Button {
            Task { await model.decide(request, approved: approve) }
        } label: {
            HStack(spacing: Space.s2) {
                Text(title)
                AgentKeyHint(keys: keycap)
            }
        }
        .buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary))
        .disabled(busy)
        .help(
            approve
                ? "Let \(harness) use \(request.tool) (⌘Return). Asks for Touch ID when this Mac is locked."
                : "Tell \(harness) no (⌘Delete)"
        )
        .accessibilityLabel(approve ? "Approve \(request.tool)" : "Deny \(request.tool)")
        return Group {
            if keys {
                if approve {
                    b.keyboardShortcut(.return, modifiers: .command)
                } else {
                    b.keyboardShortcut(.delete, modifiers: .command)
                }
            } else {
                b
            }
        }
    }

    private func line(_ status: ApprovalRequest.Status) -> some View {
        let ok = status == .approved
        return HStack(spacing: Space.s2) {
            Image(systemName: ok ? "checkmark" : "xmark").foregroundStyle(palette.tone(ok ? .run : .queue).ink)
                .accessibilityHidden(true)
            Text(ok ? "Approved" : "Denied").font(.system(size: MacTextSize.headline, weight: .semibold))
            Text("\(request.tool) · \(request.input)").font(.system(size: MacTextSize.body)).foregroundStyle(
                palette.text2
            )
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(palette.glassCard, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
    }

    private var expired: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Label("Expired", systemImage: "clock.badge.xmark").font(
                .system(size: MacTextSize.headline, weight: .semibold))
            Text("\(request.tool) · \(request.input)").font(.system(size: MacTextSize.body)).foregroundStyle(
                palette.text2
            )
            .lineLimit(2)
            Text("Nobody answered in time. The agent stops waiting for this one; ask it again from the composer.")
                .font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2).fixedSize(
                    horizontal: false, vertical: true)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard.opacity(0.7), in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
    }
}
