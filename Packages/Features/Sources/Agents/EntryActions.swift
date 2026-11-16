import AppKit
import CoreUI
import SwiftUI

/// What the message actions can do for one session. `canSend` is the only data (the rows compare it); the closures are not
/// compared. A row without actions (`nil`) shows Copy only.
struct EntryActions: Sendable {
    var canSend = false
    var edit: @MainActor @Sendable (String) -> Void = { _ in }
    var send: @MainActor @Sendable (String) -> Void = { _ in }

    @MainActor static func make(_ model: AgentsModel, _ session: AgentSessionInfo, ui: SessionUI? = nil) -> EntryActions
    {
        let id = session.id
        return EntryActions(
            canSend: model.canReply(session),
            // Edit and Quote fill the field and put the cursor in it, so the change is right there to see.
            edit: { text in
                model.drafts[id] = text
                ui?.focusComposer += 1
            },
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

/// The message actions (Ahmed, 2026-11-15: not on every message, not floating over the next row). Only your latest
/// message and the latest answer carry a quiet row of icons under them: the answer's always shows, yours on hover with its
/// room kept so nothing jumps. Every message keeps the same actions in its right-click menu.
private struct MessageActions: ViewModifier {
    let text: String  // copied
    let words: String  // edit / resend
    let user: Bool
    let latest: Bool
    let actions: EntryActions?
    @State private var hovering = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    private var list: [Act] {
        let a = actions ?? EntryActions()
        let copy = Act(id: "Copy", symbol: copied ? "checkmark" : "doc.on.doc", needsSend: false) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
        guard actions != nil else { return [copy] }
        if user {
            var l = [copy, Act(id: "Edit", symbol: "pencil") { a.edit(words) }]
            if latest { l.append(Act(id: "Resend", symbol: "arrow.clockwise") { a.send(words) }) }
            return l
        }
        var l = [copy, Act(id: "Quote", symbol: "text.quote") { a.edit(EntryQuote.draft(text)) }]
        if latest { l.insert(Act(id: "Retry", symbol: "arrow.clockwise") { a.send("Please try that again.") }, at: 1) }
        return l
    }

    private var shown: [Act] { list.filter { !$0.needsSend || actions?.canSend == true } }

    func body(content: Content) -> some View {
        VStack(alignment: user ? .trailing : .leading, spacing: Space.s1) {
            content
            if latest {
                HStack(spacing: Space.s1) {
                    ForEach(shown) { act in
                        CoreIconButton(symbol: act.symbol, label: act.id, action: act.run)
                            .help(help(act.id))
                            .keyHint(act.id == "Copy" && !user ? "⇧⌘C" : "")
                    }
                }
                .opacity(user && !hovering ? 0 : 1)
                .allowsHitTesting(!user || hovering)
                .accessibilityHidden(user && !hovering)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .contextMenu {
            ForEach(shown) { act in Button(act.id, action: act.run) }
        }
    }

    private func help(_ id: String) -> String {
        switch id {
        case "Copy": user ? "Copy your message" : "Copy the answer (⇧⌘C)"
        case "Edit": "Put this message in the field to change and send again"
        case "Resend": "Send this message again"
        case "Retry": "Ask for the answer again"
        default: "Quote the answer in a new message"
        }
    }
}

extension View {
    /// Copy, Edit, Resend (your message) or Copy, Retry, Quote (an answer): a row under the latest of each, and the right-click
    /// menu on every one.
    func messageActions(
        text: String, words: String? = nil, user: Bool, latest: Bool = false, _ actions: EntryActions?
    ) -> some View {
        modifier(MessageActions(text: text, words: words ?? text, user: user, latest: latest, actions: actions))
    }
}
