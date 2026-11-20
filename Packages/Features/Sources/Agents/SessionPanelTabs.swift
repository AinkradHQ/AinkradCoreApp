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
    @Environment(\.coreAccent) private var paneAccent
    let items: [TodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Image(
                        systemName: t.status == .completed
                            ? "checkmark.square.fill" : t.status == .inProgress ? "square.lefthalf.filled" : "square"
                    )
                    .foregroundStyle(t.status == .pending ? SessionInk.text2 : GlassInk.accent(paneAccent)).frame(
                        width: Space.s4)
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
        guard let list = TasksCard.latest(entries), list.contains(where: { $0.status != .completed }) else {
            return nil
        }
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

/// The Files tab: the session's project as a tree, one folder at a time (the Core lists a level per call), with the files this
/// session changed marked. A Core without the listing route shows just the files the session touched.
struct FilesTab: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @State private var open: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// One visible line of the tree.
    struct Line: Identifiable, Equatable {
        var path: String
        var entry: FolderEntry
        var depth: Int
        var id: String { path }
    }

    /// The tree flattened: a folder's children follow it while it is open.
    static func lines(_ folders: [String: FolderListing], open: Set<String>, dir: String = "", depth: Int = 0) -> [Line]
    {
        var out: [Line] = []
        for e in folders[dir]?.entries ?? [] {
            let path = dir.isEmpty ? e.name : dir + "/" + e.name
            out.append(Line(path: path, entry: e, depth: depth))
            if e.dir, open.contains(path) { out += lines(folders, open: open, dir: path, depth: depth + 1) }
        }
        return out
    }

    var body: some View {
        let touched = model.filesTouched(session.id)
        let changed = Set(touched.map { ($0.path as NSString).lastPathComponent })
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Text(session.project ?? "Fresh folder").coreFont(size: MacTextSize.meta).foregroundStyle(
                    SessionInk.text2)
                Spacer(minLength: 0)
                if model.sessionTools {
                    CoreIconButton(symbol: "arrow.clockwise", label: "Reload the folder") {
                        Task {
                            for d in [""] + Array(open) { await model.listFolder(session.id, dir: d, force: true) }
                        }
                    }
                    .help("Reload the folder")
                }
            }
            if model.sessionTools {
                let tree = Self.lines(model.folders[session.id] ?? [:], open: open)
                if model.folders[session.id]?[""] == nil {
                    Text("Loading the folder…").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                } else if tree.isEmpty {
                    Text("This folder is empty.").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                }
                ForEach(tree) { l in row(l, changed: l.entry.dir ? false : changed.contains(l.entry.name)) }
                if model.folders[session.id]?[""]?.truncated == true {
                    Text("Only the first 500 entries of a folder are listed.").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(SessionInk.text2)
                }
            } else {
                if touched.isEmpty {
                    Text("Nothing touched yet.").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                }
                ForEach(touched) { f in
                    HStack(spacing: Space.s2) {
                        Image(systemName: f.created ? "doc.badge.plus" : "pencil").foregroundStyle(SessionInk.text2)
                            .frame(width: Space.s4)
                        Text(f.name).coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Space.s2)
                        Text(f.created ? "new" : "+\(f.added) \u{2212}\(f.removed)").coreFont(size: MacTextSize.meta)
                            .monospacedDigit().foregroundStyle(SessionInk.text2)
                    }
                    .padding(.horizontal, Space.s2).frame(minHeight: 30).help(f.path)
                }
            }
        }
        .task(id: session.id) { await model.listFolder(session.id) }
        .task(id: model.sessionTools) { await model.listFolder(session.id) }
    }

    private func row(_ l: Line, changed: Bool) -> some View {
        Button {
            guard l.entry.dir else { return }
            withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) {
                if open.contains(l.path) { open.remove(l.path) } else { open.insert(l.path) }
            }
            if open.contains(l.path) { Task { await model.listFolder(session.id, dir: l.path) } }
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(SessionInk.text2).rotationEffect(.degrees(open.contains(l.path) ? 90 : 0))
                    .opacity(l.entry.dir ? 1 : 0).frame(width: Space.s3)
                Image(systemName: l.entry.dir ? "folder" : "doc").foregroundStyle(SessionInk.text2)
                    .frame(width: Space.s4)
                Text(l.entry.name).coreFont(size: MacTextSize.body, design: l.entry.dir ? .default : .monospaced)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: Space.s2)
                if changed {
                    coreShape(2).fill(GlassInk.accent(paneAccent)).frame(width: 6, height: 6).accessibilityLabel(
                        "Changed")
                }
            }
            .padding(.leading, CGFloat(l.depth) * Space.s4 + Space.s1).padding(.trailing, Space.s2)
            .frame(minHeight: 28).contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
        .help(l.path)
    }
}

/// The Terminal tab: a real shell in the session's folder on its runner, drawn by the Terminals module's own emulator. Where
/// the app has no terminals (a Core with none), the button opens the Terminals app instead.
struct TerminalTab: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo

    var body: some View {
        if let terminal = model.host?.embeddedTerminal(on: session.runner, session: session.id) {
            terminal.frame(height: 380).accessibilityLabel("Terminal in the session's folder")
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("A terminal opens on \(model.runnerName(session.runner)).")
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
}
