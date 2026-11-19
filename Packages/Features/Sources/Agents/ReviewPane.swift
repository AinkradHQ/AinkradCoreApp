import CoreUI
import Foundation
import SwiftUI

/// Where a changed file stands in the review. Accept is a mark kept on this Mac (it survives a relaunch); Revert is the Core's.
enum ReviewState: String, Equatable {
    case toReview, accepted, revertAsked, reverted

    var label: String {
        switch self {
        case .toReview: "To review"
        case .accepted: "Accepted"
        case .revertAsked: "Revert asked"
        case .reverted: "Reverted"
        }
    }
    var tone: Tone {
        switch self {
        case .toReview: .queue
        case .accepted: .done
        case .revertAsked: .warn
        case .reverted: .queue
        }
    }
    var symbol: String {
        switch self {
        case .toReview: "circle.dashed"
        case .accepted: "checkmark"
        case .revertAsked, .reverted: "arrow.uturn.backward"
        }
    }
}

/// Review marks per session, kept in UserDefaults so an Accept survives a relaunch.
@MainActor @Observable
final class ReviewStore {
    static let shared = ReviewStore()
    private var marks: [String: [String: ReviewState]] = [:]

    private func key(_ session: String) -> String { "agents.review." + session }

    func state(_ session: String, _ path: String) -> ReviewState {
        if marks[session] == nil {
            let saved = UserDefaults.standard.dictionary(forKey: key(session)) as? [String: String] ?? [:]
            marks[session] = saved.compactMapValues(ReviewState.init(rawValue:))
        }
        return marks[session]?[path] ?? .toReview
    }

    func set(_ session: String, _ path: String, _ s: ReviewState) {
        _ = state(session, path)
        marks[session, default: [:]][path] = s
        UserDefaults.standard.set(marks[session]?.mapValues(\.rawValue), forKey: key(session))
    }
}

/// The Codex-style review: changed files on top, the selected file's diff below, then Accept, Revert and a comment.
/// Accept marks a file reviewed; Revert goes to the Core, which restores the file from this session's recorded edits.
struct ReviewPane: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    let diff: (String) -> [DiffLine]
    /// Inside the Changes card: no frame or scroller of its own (the card and the column have them).
    var embedded = false
    let close: () -> Void

    @State private var selected: String?
    @State private var comment = ""
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette
    private let store = ReviewStore.shared

    var body: some View {
        let files = model.filesTouched(session.id)
        let current = files.first { $0.path == selected } ?? files.first
        let content = VStack(alignment: .leading, spacing: Space.s3) {
            header(files)
            if files.isEmpty {
                Text("Nothing changed yet.").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            } else {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(files) { f in fileRow(f, selected: f.path == current?.path) }
                }
                if let f = current { detail(f) }
            }
        }
        .foregroundStyle(palette.text)
        return Group {
            if embedded {
                content.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    content.padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                        .coreWell(radius: 12)  // follows the Appearance setting (Look)
                }
                .scrollIndicators(.never)
            }
        }
        .focusable().focusEffectDisabled().focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { move(-1, files, current?.path) }
        .onKeyPress(.downArrow) { move(1, files, current?.path) }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    private func move(_ d: Int, _ files: [FileTouch], _ now: String?) -> KeyPress.Result {
        guard let i = files.firstIndex(where: { $0.path == now }) else { return .ignored }
        let n = min(max(i + d, 0), files.count - 1)
        selected = files[n].path
        comment = ""
        return .handled
    }

    /// The title with Close at the right; with more than one file, Accept all and Revert all on their own row under it, so
    /// nothing wraps in the panel's width.
    private func header(_ files: [FileTouch]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // Inside the Changes card the card's own header carries the title and Done.
            if !embedded { titleRow(files) }
            if files.count > 1 { bulk(files) }
        }
    }

    private func titleRow(_ files: [FileTouch]) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checklist").coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                .frame(width: Space.s4).accessibilityHidden(true)
            Text("Review").coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1).fixedSize()
                .accessibilityAddTraits(.isHeader)
            if !files.isEmpty { CountBadge(files.count, tone: .quiet) }
            Spacer(minLength: 0)
            Button("Close") { close() }.buttonStyle(CoreButtonStyle(.plain, size: .small)).fixedSize()
                .help("Close the review (Esc or ⇧⌘R)").keyHint(.review)
        }
        // Room at the right for the fixed panel toggle (SessionView), as the Session header leaves.
        .padding(.trailing, Space.s6)
    }

    private func bulk(_ files: [FileTouch]) -> some View {
        HStack(spacing: Space.s2) {
            Button("Accept all") { for f in files { store.set(session.id, f.path, .accepted) } }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).fixedSize()
                .help("Accept every changed file")
            Button("Revert all") {
                let id = session.id
                let paths = files.map(\.path)
                Task { await model.revert(id, paths: paths) }
            }
            .buttonStyle(CoreButtonStyle(.quietDanger, size: .small)).fixedSize()
            .disabled(!model.canWrite(session))
            .help("Put every changed file back as it was")
        }
    }

    private func fileRow(_ f: FileTouch, selected on: Bool) -> some View {
        let s = store.state(session.id, f.path)
        return Button {
            selected = f.path
            comment = ""
        } label: {
            HStack(spacing: Space.s2) {
                Text(f.name).coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Space.s2)
                Text("+\(f.added)").foregroundStyle(palette.tone(.run).ink)
                Text(f.created ? "new" : "−\(f.removed)").foregroundStyle(palette.tone(f.created ? .run : .fail).ink)
                StateBadge(s.label, tone: s.tone, symbol: s.symbol)
            }
            .coreFont(size: MacTextSize.meta).monospacedDigit()
            .padding(.vertical, Space.s1).padding(.horizontal, Space.s2).contentShape(Rectangle())
            .background(on ? palette.navActive : .clear, in: coreShape(Radius.control))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
        .help(f.path)
    }

    private func detail(_ f: FileTouch) -> some View {
        let id = session.id
        let writable = model.canWrite(session)
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text(f.path).coreFont(size: MacTextSize.meta, design: .monospaced).foregroundStyle(palette.text2)
                .lineLimit(2).truncationMode(.middle)
            DiffBlock(lines: diff(f.path)).id(f.path)
            HStack(spacing: Space.s2) {
                Button("Accept") { store.set(id, f.path, .accepted) }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small)).help("Mark this file as reviewed")
                Button("Revert") { Task { await model.revert(id, paths: [f.path]) } }
                .buttonStyle(CoreButtonStyle(.quietDanger, size: .small)).disabled(!writable)
                .help("Put this file back as it was before this session's edits")
            }
            CoreTextArea(
                nil, placeholder: "Comment on this file", text: $comment, minHeight: Space.s8, maxHeight: Space.s8 * 3)
            Button("Send comment") {
                let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                comment = ""
                Task { await model.say(id, "About `\(f.path)`: \(text)") }
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .disabled(!writable || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Send this comment in the conversation")
        }
    }
}
