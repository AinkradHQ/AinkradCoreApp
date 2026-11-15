import AppKit
import CoreUI
import SwiftUI

/// What the message actions can do for one session. `canSend` is the only data (the rows compare it); the closures are not
/// compared. A row without actions (`nil`) shows Copy only.
struct EntryActions: Sendable {
    var canSend = false
    var edit: @MainActor @Sendable (String) -> Void = { _ in }
    var send: @MainActor @Sendable (String) -> Void = { _ in }

    @MainActor static func make(_ model: AgentsModel, _ session: AgentSessionInfo) -> EntryActions {
        let id = session.id
        return EntryActions(
            canSend: model.canReply(session),
            edit: { model.drafts[id] = $0 },
            send: { text in Task { await model.say(id, text) } })
    }
}

/// The words of an answer's first paragraph as a Markdown quote, ready for the composer.
enum EntryQuote {
    static func draft(_ text: String) -> String {
        let first =
            text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        return first.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
            + "\n\n"
    }
}

private struct Act: Identifiable {
    let id: String
    let symbol: String
    var needsSend = true
    let run: () -> Void
}

/// Hover actions under a message and the same in its right-click menu. The bar always takes its room and only fades in,
/// so nothing jumps; Reduce Motion drops the fade.
private struct MessageActions: ViewModifier {
    let text: String  // copied
    let words: String  // edit / resend
    let user: Bool
    let actions: EntryActions?
    @State private var hovering = false
    @State private var hideTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var list: [Act] {
        let a = actions ?? EntryActions()
        let copy = Act(id: "Copy", symbol: "doc.on.doc", needsSend: false) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        guard actions != nil else { return [copy] }
        if user {
            return [
                copy, Act(id: "Edit", symbol: "pencil") { a.edit(words) },
                Act(id: "Resend", symbol: "arrow.up.message") { a.send(words) },
            ]
        }
        return [
            copy, Act(id: "Retry", symbol: "arrow.clockwise") { a.send("Please try that again.") },
            Act(id: "Quote", symbol: "text.quote") { a.edit(EntryQuote.draft(text)) },
        ]
    }

    private var shown: [Act] { list.filter { !$0.needsSend || actions?.canSend == true } }

    func body(content: Content) -> some View {
        // Floats over the message (no space kept for it): left of your bubble, at the top right of an answer. It stays a
        // moment after the pointer leaves, so reaching for it never makes it vanish.
        content
            .overlay(alignment: user ? .leading : .topTrailing) {
                HStack(spacing: Space.s1) {
                    ForEach(shown) { act in CoreIconButton(symbol: act.symbol, label: act.id, action: act.run) }
                }
                .padding(Space.s1)
                .coreWell(radius: Radius.control)
                .alignmentGuide(.leading) { d in user ? d[.trailing] + Space.s2 : d[.leading] }
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .accessibilityHidden(!hovering)
                .onHover { hover($0) }
            }
            .contentShape(Rectangle())
            .onHover { hover($0) }
            .animation(reduce ? nil : Motion.out(Motion.hover), value: hovering)
            .contextMenu {
                ForEach(shown) { act in Button(act.id, action: act.run) }
            }
    }

    private func hover(_ inside: Bool) {
        hideTask?.cancel()
        if inside {
            hovering = true
        } else {
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { hovering = false }
            }
        }
    }
}

extension View {
    /// Copy, Edit, Resend (your message) or Copy, Retry, Quote (an answer): hover row and context menu.
    func messageActions(text: String, words: String? = nil, user: Bool, _ actions: EntryActions?) -> some View {
        modifier(MessageActions(text: text, words: words ?? text, user: user, actions: actions))
    }
}
