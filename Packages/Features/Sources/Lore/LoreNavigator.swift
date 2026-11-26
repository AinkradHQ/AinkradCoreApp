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
    @State private var open: Set<String> = ["personal"]
    @State private var query = ""
    @State private var cursor: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    search
                    LoreWeekCard(model: model, cursor: cursor == "today").id("today")
                        .padding(.bottom, Space.s2)
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
                .padding(.bottom, Space.s4)
            }
            .scrollIndicators(.never)
            .onChange(of: cursor) { if let cursor { proxy.scrollTo(cursor) } }
        }
        .onChange(of: focus.wrappedValue) { if !focus.wrappedValue { cursor = nil } }
        .accessibilityIdentifier("lore-left")
    }

    // MARK: keys

    private var groups: [LoreGroup] { LoreTree.groups(model.sideNotes, projects: model.projectNames) }
    /// Personal and Journal; the projects get their own heading.
    private var notes: [LoreGroup] { groups.filter { !$0.id.hasPrefix("project-") } }
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
            cursor: cursor == id, action: action
        )
        .id(id)
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
        ) {
            Task { if n.kind == "daily", let d = n.day { await model.openDay(d) } else { await model.openNote(n.id) } }
        }
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
            }
        }
    }
}
