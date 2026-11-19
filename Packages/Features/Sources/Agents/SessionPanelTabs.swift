import CoreUI
import SwiftUI

/// The slide-in panel's four tabs (the mockup's 22: Plan, Changes, Files, Terminal). The chosen tab is remembered.
enum PanelTab: String, CaseIterable, Sendable {
    case plan, changes, files, terminal

    var title: String {
        switch self {
        case .plan: "Plan"
        case .changes: "Changes"
        case .files: "Files"
        case .terminal: "Terminal"
        }
    }
}

/// The todo list as rows: done struck through, the current one marked, the rest open boxes.
struct TodoRows: View {
    let items: [TodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Image(
                        systemName: t.status == .completed
                            ? "checkmark.square.fill" : t.status == .inProgress ? "square.lefthalf.filled" : "square"
                    )
                    .foregroundStyle(t.status == .pending ? SessionInk.text2 : GlassInk.blue).frame(width: Space.s4)
                    Text(t.text).strikethrough(t.status == .completed)
                        .foregroundStyle(t.status == .completed ? SessionInk.text2 : SessionInk.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .coreFont(size: MacTextSize.body)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The todo strip above the composer: one line with the step in progress and "3 of 5"; it opens upward to the whole list.
/// It shows only while the agent keeps a todo list that is not finished. Under Reduce Motion it opens without sliding.
struct TodoStrip: View {
    let items: [TodoItem]
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// The newest list, or nil when there is none or every item is done (a finished list is history, not a strip).
    static func items(_ entries: [TranscriptEntry]) -> [TodoItem]? {
        guard let list = TasksCard.latest(entries), list.contains(where: { $0.status != .completed }) else { return nil }
        return list
    }

    var body: some View {
        let done = items.filter { $0.status == .completed }.count
        let now = items.first { $0.status == .inProgress } ?? items.first { $0.status == .pending }
        VStack(alignment: .leading, spacing: 0) {
            if open {
                TodoRows(items: items).padding([.horizontal, .top], Space.s3).padding(.bottom, Space.s2)
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s1)))
            }
            Button {
                withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { open.toggle() }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checklist").foregroundStyle(SessionInk.text2).frame(width: Space.s4)
                    Text(now?.text ?? "All steps done").coreFont(size: MacTextSize.body).lineLimit(1)
                        .truncationMode(.tail).foregroundStyle(SessionInk.text)
                    Spacer(minLength: Space.s2)
                    Text("\(done) of \(items.count)").coreFont(size: MacTextSize.meta).monospacedDigit()
                        .foregroundStyle(SessionInk.text2)
                    Image(systemName: "chevron.up").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(SessionInk.text2).rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg).contentShape(Rectangle())
            }
            .buttonStyle(CoreQuietPressStyle(radius: Radius.row, scale: 0.99, hoverFill: true))
            .help(open ? "Fold the list" : "Show every step")
            .accessibilityLabel("Steps: \(done) of \(items.count) done")
        }
        .background(SessionInk.row, in: coreShape(Radius.row))
    }
}

/// The Plan tab: the plan the agent proposed (when it did), its todo list, then its helpers.
struct PlanTab: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    let entries: [TranscriptEntry]
    var again: ((SubAgentInfo) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            let plan = entries.reversed().compactMap { e -> String? in
                if case .plan(_, let t) = e.kind { return t }
                return nil
            }.first
            let todos = TasksCard.latest(entries)
            if plan == nil && todos == nil {
                Text("No plan yet. Switch to Plan mode (⇧⇥) and the agent writes one before it edits anything.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
            }
            if let todos {
                let done = todos.filter { $0.status == .completed }.count
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text("Steps").coreFont(size: MacTextSize.body, weight: .semibold)
                        Text("\(done) of \(todos.count)").coreFont(size: MacTextSize.meta).monospacedDigit()
                            .foregroundStyle(SessionInk.text2)
                    }
                    CoreMeter(todos.isEmpty ? 0 : Double(done) / Double(todos.count), label: "Steps done")
                    TodoRows(items: todos)
                }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
            }
            if let plan { PlanCard(text: plan) }
            let subs = SubAgentInfo.all(entries)
            if !subs.isEmpty {
                SubAgentsCard(
                    list: subs, again: again,
                    stop: session.canStopSubagents ? { model.stopSubagent(session.id, $0.id) } : nil)
            }
        }
    }
}

/// The Files tab: the files this session touched, each with its counts. A full project tree needs a listing route the Core
/// does not have, so this is the session's own list, not a fake tree.
struct FilesTab: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo

    var body: some View {
        let files = model.filesTouched(session.id)
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(session.project ?? "Fresh folder").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
            if files.isEmpty {
                Text("Nothing touched yet.").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
            }
            ForEach(files) { f in
                HStack(spacing: Space.s2) {
                    Image(systemName: f.created ? "doc.badge.plus" : "pencil").foregroundStyle(SessionInk.text2)
                        .frame(width: Space.s4)
                    Text(f.name).coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Space.s2)
                    Text(f.created ? "new" : "+\(f.added) −\(f.removed)").coreFont(size: MacTextSize.meta)
                        .monospacedDigit().foregroundStyle(SessionInk.text2)
                }
                .padding(.horizontal, Space.s2).frame(minHeight: 30)
                .help(f.path)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The Terminal tab: a real shell in the session's folder opens in the Terminals app (the one place a shell runs), not a
/// pretend one in the panel.
struct TerminalTab: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(
                session.folder == nil
                    ? "A terminal opens on \(model.runnerName(session.runner))."
                    : "A terminal opens in this session's folder on \(model.runnerName(session.runner))."
            )
            .coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text2)
            Button {
                model.host?.openTerminal(on: session.runner, session: session.id)
            } label: {
                Label("Open a terminal here", systemImage: "terminal")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).keyHint(.terminal)
        }
    }
}
