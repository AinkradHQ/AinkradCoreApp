import CoreUI
import SwiftUI

/// Find in a conversation (⌘F, Ahmed 2026-11-15: Codex parity): what each entry says, for matching.
enum ConversationSearch {
    static func text(_ k: EntryKind) -> String {
        switch k {
        case .user(let t), .assistant(let t): t
        case .toolUse(_, let name, let summary): name + " " + summary
        case .toolDone(_, let name, let summary, _, _, let output, _): name + " " + summary + " " + output
        case .toolResult(_, let name, _, _, let output, _): (name ?? "") + " " + output
        case .toolEdit(_, _, let path, _, let new, _, _): path + " " + new
        case .toolTodos(_, let items): items.map(\.text).joined(separator: " ")
        case .subAgent(_, let type, let task, let prompt, let result, _, _):
            [type, task, prompt, result ?? ""].joined(separator: " ")
        case .plan(_, let text): text
        default: ""
        }
    }

    /// The entries that mention `query` (case and accents ignored), oldest first.
    static func hits(_ entries: [TranscriptEntry], _ query: String) -> [Int64] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return entries.filter { text($0.kind).range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map(\.seq)
    }

    /// Your messages, oldest first: the stops for ⌥↑ / ⌥↓.
    static func turns(_ entries: [TranscriptEntry]) -> [Int64] {
        entries.filter { if case .user = $0.kind { return true } else { return false } }.map(\.seq)
    }
}

/// The find bar over a conversation: the words, "3 of 12", previous / next, close. ↩ or ↓ next, ⇧↩ or ↑ previous, Esc closes.
struct ConversationFindBar: View {
    @Binding var query: String
    let count: Int
    let index: Int
    let step: (Int) -> Void
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("Find in this conversation", text: $query)
                .textFieldStyle(.plain).focused($focused)
                .onSubmit { step(NSEvent.modifierFlags.contains(.shift) ? -1 : 1) }
                .onKeyPress(.downArrow) {
                    step(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    step(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
            Text(query.isEmpty ? "" : count == 0 ? "No match" : "\(index + 1) of \(count)")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
            CoreIconButton(symbol: "chevron.up", label: "Previous match") { step(-1) }.disabled(count == 0)
            CoreIconButton(symbol: "chevron.down", label: "Next match") { step(1) }.disabled(count == 0)
            CoreIconButton(symbol: "xmark", label: "Close find") { close() }
        }
        .coreFont(size: MacTextSize.body)
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlLg)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .onAppear { focused = true }
    }
}
