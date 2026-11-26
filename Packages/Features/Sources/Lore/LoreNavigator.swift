// LoreNavigator — the left side of the space, straight on the pane's surface: search, the Today card with the week,
// then Notes, Projects, AI documents, Tags and Recents as quiet rows with counts. Only the Today card is a well.
import CoreKit
import CoreUI
import SwiftUI

/// ⌘L puts the cursor in the search field; ↑ ↓ walk every row (`ids`, in the order they are drawn), Return opens it,
/// Esc clears the search, then goes back to the note.
struct LoreLeftSidebar: View {
    let model: LoreModel
    var focus: FocusState<Bool>.Binding
    @State private var open: Set<String> = []  // every folder starts collapsed
    @State private var query = ""
    @State private var cursor: String?
    /// The row whose title is a field, and what is typed in it.
    @State private var renaming: String?
    @State private var draft = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    // The sidebar slides in; its parts arrive a beat after it, top first.
                    search.loreArrive(0)
                    LoreWeekCard(model: model, cursor: cursor == "today").id("today")
                        .padding(.bottom, Space.s2)
                        .loreArrive(1)
                    Group {
                        if let f = model.sideFilter {
                            found(f)
                        } else {
                            groupSection("Notes", notes)
                            groupSection("Projects", projects)
                        }
                        docs
                        tags
                        recents
                    }
                    .loreArrive(2)
                }
                .padding(.bottom, Space.s4)
            }
            .scrollIndicators(.never)
            .onChange(of: cursor) { if let cursor { proxy.scrollTo(cursor) } }
        }
        // ⌘⌫ on the list's cursor row (Finder's Move to Trash). A key equivalent, so it comes before the search
        // field's own ⌘⌫; disabled (and so passed on) unless the cursor is on a note that can go.
        .background {
            Button("Delete the note") { trashCursor() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!focus.wrappedValue || cursor.flatMap(noteFor).map(LoreModel.canEdit) != true)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .onChange(of: focus.wrappedValue) { if !focus.wrappedValue { cursor = nil } }
        .onChange(of: model.renameRequest) { if let id = model.renameRequest { startRename(id) } }
        .onAppear { if let id = model.renameRequest { startRename(id) } }
        .accessibilityIdentifier("lore-left")
    }

    // MARK: keys

    private var groups: [LoreGroup] { LoreTree.groups(model.sideNotes, projects: model.projectNames) }
    /// Personal and Journal; the projects get their own heading.
    /// Journal first (the daily notes), then the rest in their order.
    private var notes: [LoreGroup] {
        let own = groups.filter { !$0.id.hasPrefix("project-") }
        return own.filter { $0.id == "journal" } + own.filter { $0.id != "journal" }
    }
    private var projects: [LoreGroup] { groups.filter { $0.id.hasPrefix("project-") } }
    private var recent: [LoreNote] { Array(model.sideNotes.filter { $0.kind == "note" }.prefix(5)) }

    /// Every row, in the order the list draws them.
    private var ids: [String] {
        var out = ["today"]
        if model.sideFilter != nil {
            out += model.filterHits.map { "found:\($0.id)" }
        } else {
            for g in notes + projects {
                out.append("group:\(g.id)")
                if open.contains(g.id) { out += g.notes.prefix(60).map { "tree:\($0.id)" } }
            }
        }
        out += model.sessionDocs.prefix(30).map { "doc:\($0.note)" }
        out += model.sideTags.prefix(24).map { "tag:\($0.tag)" }
        out += recent.map { "recent:\($0.id)" }
        return out
    }

    /// Return on the cursor's row: what a click on it does.
    private func run(_ id: String) {
        guard let colon = id.firstIndex(of: ":") else {
            Task { await model.openDay(model.todayKey) }
            return
        }
        let kind = id[..<colon]
        let value = String(id[id.index(after: colon)...])
        switch kind {
        case "group": toggle(value)
        case "tag": model.setFilter(.tag(value))
        default: Task { await model.openNote(value) }
        }
    }

    private func toggle(_ group: String) {
        if open.contains(group) { open.remove(group) } else { open.insert(group) }
    }

    private func back() {
        if !query.isEmpty || model.sideFilter != nil {
            clear()
        } else {
            focus.wrappedValue = false
            // After SwiftUI has let go of its focus, or it takes the first responder back from the page.
            Task { @MainActor in model.page.focus() }
        }
    }

    private func clear() {
        query = ""
        model.setFilter(nil)
    }

    private func row(
        _ id: String, _ title: String, symbol: String?, count: String? = nil, selected: Bool = false,
        indented: Bool = false, subtitle: String? = nil, action: @escaping () -> Void
    ) -> some View {
        LoreSideRow(
            title: title, symbol: symbol, count: count, selected: selected, indented: indented, subtitle: subtitle,
            cursor: cursor == id, rename: renaming == id ? $draft : nil, done: { finishRename(id, keep: $0) },
            action: action
        )
        .id(id)
    }

    // MARK: rename, delete

    /// The note under a row id (`tree:`, `found:`, `recent:`).
    private func noteFor(_ rowID: String) -> LoreNote? {
        guard let colon = rowID.firstIndex(of: ":"), ["tree", "found", "recent"].contains(rowID[..<colon]) else {
            return nil
        }
        let id = rowID[rowID.index(after: colon)...]
        return (model.sideNotes + model.filterHits).first { $0.id == id }
    }

    private func beginRename(_ rowID: String, _ n: LoreNote) {
        draft = Self.name(n)
        renaming = rowID
    }

    /// The header's Rename…: the row it is drawn on, its group opened first.
    private func startRename(_ id: String) {
        model.renameRequest = nil
        guard let n = (model.sideNotes + model.filterHits).first(where: { $0.id == id }), LoreModel.canEdit(n) else {
            return
        }
        if model.sideFilter != nil, model.filterHits.contains(where: { $0.id == id }) {
            beginRename("found:\(id)", n)
        } else if let g = groups.first(where: { $0.notes.prefix(60).contains { $0.id == id } }) {
            open.insert(g.id)
            if model.sideFilter != nil { clear() }
            beginRename("tree:\(id)", n)
        } else if recent.contains(where: { $0.id == id }) {
            beginRename("recent:\(id)", n)
        }
    }

    private func finishRename(_ rowID: String, keep: Bool) {
        guard renaming == rowID else { return }
        renaming = nil
        if keep, let n = noteFor(rowID), draft != Self.name(n) {
            let title = draft
            Task { await model.rename(n.id, to: title) }
        }
    }

    /// ⌘⌫ on the cursor's note (Finder's Move to Trash).
    private func trashCursor() {
        guard let c = cursor, let n = noteFor(c), LoreModel.canEdit(n) else { return }
        cursor = LoreKeys.next(ids, from: c, step: 1).flatMap { $0 == c ? nil : $0 }
        Task { await model.trashNote(n.id, title: Self.name(n)) }
    }

    @ViewBuilder private func menu(_ n: LoreNote, _ rowID: String) -> some View {
        let name = Self.name(n)
        Button("Open") { show(n) }
        if LoreModel.canEdit(n) {
            Button("Rename…") { beginRename(rowID, n) }
            Menu("Move to") {
                moveItem(n, to: nil, "Personal")
                ForEach(model.projectChoices, id: \.id) { p in moveItem(n, to: p.id, p.name) }
            }
        }
        Button("Copy Link") { model.copyLink(n.id, title: name) }
        if LoreModel.canEdit(n) {
            Divider()
            Button("Delete", role: .destructive) { Task { await model.trashNote(n.id, title: name) } }
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    private func moveItem(_ n: LoreNote, to project: String?, _ name: String) -> some View {
        Button {
            Task { await model.moveNote(n.id, to: project) }
        } label: {
            if n.project == project { Label(name, systemImage: "checkmark") } else { Text(name) }
        }
    }

    private func show(_ n: LoreNote) {
        Task { if n.kind == "daily", let d = n.day { await model.openDay(d) } else { await model.openNote(n.id) } }
    }

    // MARK: parts

    /// The design system's field surface, like Projects' Filter and Leyline's find field.
    private var search: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Search notes").foregroundStyle(GlassInk.secondary))
                .textFieldStyle(.plain).coreFont(size: MacTextSize.body)
                .focused(focus)
                .accessibilityLabel("Search notes")
                .onChange(of: query) { model.setFilter(query.isEmpty ? nil : .query(query)) }
                .onSubmit { run(cursor ?? LoreKeys.next(ids, from: nil, step: 1) ?? "today") }
                .onExitCommand(perform: back)
                .loreListKeys(ids, cursor: $cursor, run: run, back: back)
            if query.isEmpty {
                CoreKeycap(LoreKeys.find.label)
            } else {
                CoreIconButton(symbol: "xmark", label: "Clear the search") { clear() }
            }
        }
        .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
        .coreFieldSurface(focused: focus.wrappedValue)
        .padding(.bottom, Space.s3)
    }

    @ViewBuilder private func groupSection(_ title: String, _ list: [LoreGroup]) -> some View {
        if !list.isEmpty {
            LoreSideSection(title: title)
            ForEach(list) { g in
                row(
                    "group:\(g.id)", g.name,
                    symbol: g.id == "journal" ? "calendar" : open.contains(g.id) ? "folder.fill" : "folder",
                    count: "\(g.notes.count)"
                ) { toggle(g.id) }
                if open.contains(g.id) {
                    ForEach(g.notes.prefix(60)) { noteRow($0, "tree", indented: true) }
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder private func found(_ f: LoreSideFilter) -> some View {
        let name: String = {
            switch f {
            case .project(let p): "In \(model.projectNames[p] ?? "project")"
            case .tag(let t): "Tagged #\(t)"
            case .query: "Found"
            }
        }()
        HStack {
            LoreSideSection(title: name)
            Spacer()
            Button("Clear", action: clear).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .help("Show every note again  esc")
        }
        if model.filterHits.isEmpty {
            Text("Nothing found.").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .padding(.horizontal, Space.s3)
        }
        ForEach(model.filterHits) { noteRow($0, "found", indented: false) }
    }

    private func noteRow(_ n: LoreNote, _ section: String, indented: Bool) -> some View {
        row(
            "\(section):\(n.id)", Self.name(n), symbol: n.kind == "daily" ? "sun.max" : "doc.text",
            selected: model.note?.id == n.id, indented: indented
        ) { show(n) }
        .contextMenu { menu(n, "\(section):\(n.id)") }
        .accessibilityIdentifier("lore-row-\(section)-\(n.id)")
    }

    /// A note's title; a day's note is named by its date.
    static func name(_ n: LoreNote) -> String {
        if n.kind == "daily", let d = n.day.flatMap(LoreModel.date) {
            return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        let t = n.title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Untitled note" : t
    }

    @ViewBuilder private var docs: some View {
        if !model.sessionDocs.isEmpty {
            LoreSideSection(title: "AI documents")
            ForEach(model.sessionDocs.prefix(30)) { d in
                row(
                    "doc:\(d.note)", d.fileName, symbol: "sparkles", selected: model.note?.id == d.note,
                    subtitle: "From “\(d.sessionTitle ?? "an AI session")”"
                ) { Task { await model.openNote(d.note) } }
            }
        }
    }

    @ViewBuilder private var tags: some View {
        if !model.sideTags.isEmpty {
            LoreSideSection(title: "Tags")
            FlowRow(spacing: Space.s2) {
                ForEach(model.sideTags.prefix(24)) { t in
                    LoreTagChip(tag: t.tag, on: model.sideFilter == .tag(t.tag), cursor: cursor == "tag:\(t.tag)") {
                        model.setFilter(.tag(t.tag))
                    }
                    .id("tag:\(t.tag)")
                }
            }
            .padding(.horizontal, Space.s3)
        }
    }

    @ViewBuilder private var recents: some View {
        if !recent.isEmpty {
            LoreSideSection(title: "Recents")
            ForEach(recent) { n in
                row("recent:\(n.id)", Self.name(n), symbol: "clock", selected: model.note?.id == n.id) {
                    Task { await model.openNote(n.id) }
                }
                .contextMenu { menu(n, "recent:\(n.id)") }
                .accessibilityIdentifier("lore-row-recent-\(n.id)")
            }
        }
    }
}
