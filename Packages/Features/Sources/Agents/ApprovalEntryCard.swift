import CoreUI
import SwiftUI

/// One approval in the transcript (N33), one card in the agent's column: what the agent wants in a sentence, the short
/// command (full text on hover), and the result. While it waits it carries Allow and Deny (⌘↩ and ⌘⌫ on the first one).
struct ApprovalEntryCard: View {
    @Bindable var model: AgentsModel
    let request: ApprovalRequest
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let over = model.sessions.session(request.session)?.over ?? false
            card(ApprovalCardState.of(request, now: ctx.date, sessionOver: over))
        }
        .accessibilityElement(children: .contain)
    }

    private var who: String {
        model.sessions.session(request.session).map { AgentWords.harnessName($0.harness) } ?? "An AI session"
    }
    private var ask: ApprovalWords.Ask { ApprovalWords.ask(request.tool) }
    private var elevated: Bool { model.shell.elevatedUntil.map { $0 > Date() } ?? false }

    private func card(_ state: ApprovalCardState) -> some View {
        var waiting = false
        if case .waiting = state { waiting = true }
        let busy = model.deciding.contains(request.id)
        return HStack {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: ask.symbol).foregroundStyle(waiting ? GlassInk.orange : GlassInk.secondary)
                        .accessibilityHidden(true)
                    Text("\(who) wants to \(ask.verb)").coreFont(size: MacTextSize.body, weight: .semibold)
                    Spacer(minLength: Space.s2)
                    chip(state)
                }
                if !request.input.isEmpty {
                    Text(PathWords.short(request.input)).coreFont(size: 12, design: .monospaced).lineLimit(1)
                        .truncationMode(.tail).textSelection(.enabled)
                        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1 + 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.25), in: coreShape(Radius.control))
                        .help(request.input).agentCopyMenu(request.input)
                }
                if waiting {
                    if let n = model.approvalNotices[request.id] { NoticeBanner(notice: n) }
                    HStack(spacing: Space.s2) {
                        button(approve: true, busy: busy)
                        button(approve: false, busy: busy)
                        if busy {
                            Text("Waiting for your Core…").coreFont(size: MacTextSize.meta)
                                .foregroundStyle(GlassInk.secondary)
                        }
                        Spacer(minLength: 0)
                        if case .waiting(let left?) = state {
                            Text("Asks again in \(AgentWords.clock(left))").coreFont(size: MacTextSize.meta)
                                .foregroundStyle(GlassInk.secondary).monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                        }
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: 560, alignment: .leading)
            .background(waiting ? GlassInk.orange.opacity(0.1) : GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    waiting ? GlassInk.orange.opacity(0.6) : GlassInk.wellEdge, lineWidth: waiting ? 1.5 : 1)
            }
            Spacer(minLength: Space.s8)
        }
        .animation(reduce ? nil : .smooth(duration: 0.3), value: state)
    }

    @ViewBuilder private func chip(_ state: ApprovalCardState) -> some View {
        if let text = state.result {
            let ok = { if case .allowed = state { return true } else { return false } }()
            Label(text, systemImage: ok ? "checkmark" : "xmark")
                .coreFont(size: MacTextSize.meta, weight: .semibold)
                .foregroundStyle(GlassInk.ink(ok ? GlassInk.green : GlassInk.red))
                .padding(.horizontal, Space.s2).frame(height: 20)
                .background((ok ? GlassInk.green : GlassInk.red).opacity(0.15), in: coreShape(5))
        } else {
            Label("Waiting for you", systemImage: "hand.raised")
                .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.orangeInk)
                .padding(.horizontal, Space.s2).frame(height: 20)
                .background(GlassInk.orange.opacity(0.15), in: coreShape(5))
        }
    }

    private func button(approve: Bool, busy: Bool) -> some View {
        let first = model.cards(for: request.session).first?.id == request.id
        let live =
            first && model.shell.activePane == AgentsModel.paneID(request.session) && !model.shell.coverOpen
        let tile = AppActionTile(
            title: approve ? (elevated ? "Allow" : "Allow with Touch ID") : "Deny",
            symbol: approve ? (elevated ? "checkmark" : "touchid") : "xmark", key: approve ? "⌘↩" : "⌘⌫",
            hue: approve ? GlassInk.blue : GlassInk.slate, prominent: approve
        ) { Task { await model.decide(request, approved: approve) } }
        .disabled(busy)
        .help(
            approve
                ? "Let \(who) \(ask.verb) (⌘Return). Asks for Touch ID when this Mac is locked."
                : "Tell \(who) no (⌘Delete). It carries on without it."
        )
        .accessibilityLabel(approve ? "Allow \(request.tool)" : "Deny \(request.tool)")
        return Group {
            if live {
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
}
