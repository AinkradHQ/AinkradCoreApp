// LoreSide — the two sidebars (E10-1, mockup 18-lore): left = Today, notes tree, AI documents, projects, tags, recents;
// right = outline, backlinks, versions, info. The model half lives here too, so LoreModel stays under its size.
import CoreKit
import CoreUI
import Foundation
import LoreEditor
import SwiftUI

/// Whether each sidebar is open, kept per user (UserDefaults); both open until the person hides one.
enum LoreSidebarPrefs {
    static func read(_ side: String, _ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: "lore.sidebar.\(side)") as? Bool ?? true
    }

    static func write(_ side: String, _ open: Bool, _ d: UserDefaults = .standard) {
        d.set(open, forKey: "lore.sidebar.\(side)")
    }
}

enum LoreSideFilter: Equatable {
    case project(String)
    case tag(String)
    case query(String)
}

extension LoreModel {
    /// Loads what the sidebars list. Each part fails alone: a Core without tags or session files shows none.
    func refreshSide() async {
        guard let service, load != .absent else { return }
        if let n = try? await service.list(filter: LoreFilter()) { sideNotes = n }
        if serves95 {
            if let t = try? await service.tags() { sideTags = t }
            if let d = try? await service.sessionDocs() { sessionDocs = d }
        }
        if let id = note?.id, let v = try? await service.versions(id) { sideVersions = v }
        await applyFilter()
    }

    func setFilter(_ f: LoreSideFilter?) {
        sideFilter = sideFilter == f ? nil : f
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            if case .query? = self?.sideFilter { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            await self?.applyFilter()
        }
    }

    func applyFilter() async {
        guard let f = sideFilter else {
            filterHits = []
            return
        }
        var hits: [LoreNote] = []
        switch f {
        case .project(let p): hits = sideNotes.filter { $0.kind == "note" && $0.project == p }
        case .tag(let t): hits = (try? await service?.list(filter: LoreFilter(tag: t))) ?? []
        case .query(let q):
            let word = q.trimmingCharacters(in: .whitespaces)
            if word.isEmpty {
                hits = []
            } else if let r = try? await service?.search(word, filter: LoreFilter(), limit: 30) {
                hits = r.hits.map(\.note)
            } else {
                hits = sideNotes.filter { $0.title.localizedCaseInsensitiveContains(word) }
            }
        }
        // A newer filter replaced this one while it was loading.
        if sideFilter == f { filterHits = hits }
    }

    func refreshOutline(after wait: Duration) {
        outlineTask?.cancel()
        outlineTask = Task { [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled, let self else { return }
            let md = page.markdown()
            outline = LoreOutline.headings(md)
            wordCount = LoreOutline.words(md)
            hasTable = LoreOutline.hasTable(md)
            noteTags = LoreOutlineTags.tags(md)
        }
    }

    func toggleFocus() {
        let focus = showLeft || showRight
        showLeft = !focus
        showRight = !focus
        if focus { host.shell.showToast("Focus mode. Press ⌘. to bring the sidebars back.", kind: .info) }
    }

    func tableTool(_ c: LoreTableCommand) { editor?.tableEdit(c) }

    func setTablesAsText(_ on: Bool) {
        tablesAsText = on
        editor?.tablesAsText = on
    }

    func reveal(_ h: LoreHeading) { editor?.reveal(headingIndex: h.index) }

    /// The AI document the open note is, if it is one.
    var openDoc: LoreSessionDoc? { sessionDocs.first { $0.note == note?.id } }

    /// Where the note is kept: the file for an AI document, else Lore.
    var savedIn: String { openDoc?.path ?? "Lore" }
}

/// `#tag` words of a note, as the Core reads them (letters, digits, `-`, `_`), in order, no repeats.
enum LoreOutlineTags {
    static func tags(_ markdown: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        var inCode = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCode.toggle()
                continue
            }
            let heading = line.hasPrefix("#") && line.drop(while: { $0 == "#" }).first == " "
            guard !inCode, !heading else { continue }
            for word in line.split(whereSeparator: { $0.isWhitespace }) where word.hasPrefix("#") && word.count > 1 {
                let t = word.dropFirst().prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
                if !t.isEmpty, seen.insert(t.lowercased()).inserted { out.append(t.lowercased()) }
            }
        }
        return out
    }
}

// MARK: views

/// One compact line of a sidebar: icon, title, a count or chip on the right. 28 pt, 8 pt radius, no outline. `cursor`:
/// the keyboard's row (↑ ↓), lit with the hover fill.
struct LoreSideRow: View {
    let title: String
    var symbol: String?
    var count: String?
    var selected = false
    var indented = false
    var subtitle: String?
    var cursor = false
    let action: () -> Void
    @State private var hover = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                if let symbol {
                    Image(systemName: symbol).coreFont(size: MacTextSize.meta + 1)
                        .foregroundStyle(selected ? palette.primary : GlassInk.secondary)
                        .frame(width: Space.s4).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).coreFont(size: MacTextSize.body, weight: selected ? .semibold : .regular).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s1)
                if let count { Text(count).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary) }
            }
            .padding(.leading, indented ? Space.s5 + Space.s2 : Space.s2).padding(.trailing, Space.s2)
            .frame(minHeight: subtitle == nil ? MacSize.controlMd : MacSize.controlLg + Space.s2, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                cursor ? GlassInk.lift(0.16) : selected || hover ? GlassInk.wellHover : .clear,
                in: coreShape(Radius.control)
            )
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityAddTraits(selected || cursor ? .isSelected : [])
    }
}

struct LoreSideSection: View {
    let title: String
    var body: some View {
        Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .padding(.horizontal, Space.s2).padding(.top, Space.s4).padding(.bottom, Space.s1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Today, the notes tree, AI documents, projects, tags, recents. ⌘L puts the cursor in the search field; ↑ ↓ walk every
/// row (`ids`, in the order they are drawn), Return opens it, Esc clears the search, then goes back to the note.
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
                    row("today", "Today", symbol: "sun.max", count: todayCount, selected: model.isToday) {
                        Task { await model.openDay(model.todayKey) }
                    }
                    if let f = model.sideFilter { found(f) } else { tree }
                    docs
                    projects
                    tags
                    recents
                }
                .padding(.horizontal, Space.s2).padding(.bottom, Space.s4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: cursor) { if let cursor { proxy.scrollTo(cursor) } }
        }
        .onChange(of: focus.wrappedValue) { if !focus.wrappedValue { cursor = nil } }
        .accessibilityIdentifier("lore-left")
    }

    private var todayCount: String? {
        let n = model.sideNotes.filter { $0.kind == "daily" && $0.day == model.todayKey }.count
        return n > 0 ? "\(n)" : nil
    }

    // MARK: keys

    private var groups: [LoreGroup] { LoreTree.groups(model.sideNotes, projects: model.projectNames) }
    private var liveProjects: [(id: String, name: String)] {
        model.projectChoices.filter { p in model.sideNotes.contains { $0.project == p.id } }
    }
    private var recent: [LoreNote] { Array(model.sideNotes.filter { $0.kind == "note" }.prefix(5)) }

    /// Every row, in the order the list draws them.
    private var ids: [String] {
        var out = ["today"]
        if model.sideFilter != nil {
            out += model.filterHits.map { "found:\($0.id)" }
        } else {
            for g in groups {
                out.append("group:\(g.id)")
                if open.contains(g.id) { out += g.notes.prefix(60).map { "tree:\($0.id)" } }
            }
        }
        out += model.sessionDocs.prefix(30).map { "doc:\($0.note)" }
        out += liveProjects.map { "project:\($0.id)" }
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
        case "group": if open.contains(value) { open.remove(value) } else { open.insert(value) }
        case "project": model.setFilter(.project(value))
        case "tag": model.setFilter(.tag(value))
        default: Task { await model.openNote(value) }
        }
    }

    private func back() {
        if !query.isEmpty || model.sideFilter != nil {
            clear()
        } else {
            focus.wrappedValue = false
            model.page.focus()
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
        .padding(.bottom, Space.s1)
    }

    @ViewBuilder private var tree: some View {
        LoreSideSection(title: "Notes")
        ForEach(groups) { g in
            row(
                "group:\(g.id)", g.name, symbol: open.contains(g.id) ? "folder.fill" : "folder",
                count: "\(g.notes.count)"
            ) {
                if open.contains(g.id) { open.remove(g.id) } else { open.insert(g.id) }
            }
            if open.contains(g.id) { ForEach(g.notes.prefix(60)) { noteRow($0, "tree", indented: true) } }
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
                .padding(.horizontal, Space.s2)
        }
        ForEach(model.filterHits) { noteRow($0, "found", indented: false) }
    }

    private func noteRow(_ n: LoreNote, _ section: String, indented: Bool) -> some View {
        let t = n.title.trimmingCharacters(in: .whitespaces)
        return row(
            "\(section):\(n.id)", t.isEmpty ? "Untitled note" : t, symbol: "doc.text",
            selected: model.note?.id == n.id, indented: indented
        ) { Task { await model.openNote(n.id) } }
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

    @ViewBuilder private var projects: some View {
        if !liveProjects.isEmpty {
            LoreSideSection(title: "Projects")
            ForEach(liveProjects, id: \.id) { p in
                row(
                    "project:\(p.id)", p.name, symbol: "folder",
                    count: "\(model.sideNotes.filter { $0.project == p.id }.count)",
                    selected: model.sideFilter == .project(p.id)
                ) { model.setFilter(.project(p.id)) }
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
            .padding(.horizontal, Space.s2)
        }
    }

    @ViewBuilder private var recents: some View {
        if !recent.isEmpty {
            LoreSideSection(title: "Recents")
            ForEach(recent) { n in
                row(
                    "recent:\(n.id)", n.title.isEmpty ? "Untitled note" : n.title, symbol: "clock",
                    selected: model.note?.id == n.id
                ) { Task { await model.openNote(n.id) } }
            }
        }
    }
}

/// A tag in the list: the chip, lit while it filters or the keyboard's cursor is on it.
private struct LoreTagChip: View {
    let tag: String
    let on: Bool
    let cursor: Bool
    let pick: () -> Void
    var body: some View {
        Button(action: pick) {
            CoreChip("#\(tag)", minWidth: 0).opacity(on || cursor ? 1 : 0.85)
                .background(cursor ? GlassInk.lift(0.16) : .clear, in: coreShape(Radius.chip))
        }
        .buttonStyle(.plain)
        .help("Show the notes tagged #\(tag)")
    }
}

/// Chips that wrap onto new lines.
private struct FlowRow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 200, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var pts: [CGPoint] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            pts.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            row = max(row, sz.height)
        }
        return (pts, CGSize(width: width, height: y + row))
    }
}
