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
            pageBlank = md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// A key was typed: the blank prompt goes at once, and the chrome steps back until 3 s without typing.
    func typed() {
        if pageBlank { pageBlank = false }
        if !typing { typing = true }
        typingTask?.cancel()
        typingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.typing = false
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
/// the keyboard's row (↑ ↓), lit with the hover fill. `rename`: the title is a field (Return keeps it, Esc puts the old
/// one back, clicking away keeps it, like Finder).
struct LoreSideRow: View {
    let title: String
    var symbol: String?
    var count: String?
    var selected = false
    var indented = false
    var subtitle: String?
    var cursor = false
    var rename: Binding<String>?
    var done: (Bool) -> Void = { _ in }
    let action: () -> Void
    @State private var hover = false
    @FocusState private var field: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        Group {
            if let rename {
                line(
                    TextField("", text: rename).textFieldStyle(.plain)
                        .coreFont(size: MacTextSize.body, weight: .semibold)
                        .focused($field)
                        .onSubmit { done(true) }
                        .onExitCommand { done(false) }
                        .onAppear { field = true }
                        .onChange(of: field) { if !field { done(true) } }
                        .accessibilityLabel("New name for \(title)"),
                    lit: true)
            } else {
                Button(action: action) {
                    line(
                        Text(title).coreFont(size: MacTextSize.body, weight: selected ? .semibold : .regular)
                            .lineLimit(1),
                        lit: false)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityAddTraits(selected || cursor ? .isSelected : [])
    }

    private func line(_ name: some View, lit: Bool) -> some View {
        HStack(spacing: Space.s2) {
            if let symbol {
                Image(systemName: symbol).coreFont(size: MacTextSize.meta + 1)
                    .foregroundStyle(selected ? palette.primary : GlassInk.secondary)
                    .frame(width: Space.s4).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                name
                if let subtitle {
                    Text(subtitle).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: Space.s1)
            if let count { Text(count).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary) }
        }
        .padding(.leading, indented ? Space.s6 + Space.s3 : Space.s3).padding(.trailing, Space.s3)
        .frame(minHeight: subtitle == nil ? MacSize.controlMd : MacSize.controlLg + Space.s2, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            lit || cursor ? GlassInk.lift(0.16) : selected || hover ? GlassInk.wellHover : .clear,
            in: coreShape(Radius.control)
        )
        .contentShape(coreShape(Radius.control))
    }
}

struct LoreSideSection: View {
    let title: String
    var body: some View {
        Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .padding(.horizontal, Space.s3).padding(.top, Space.s4).padding(.bottom, Space.s1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A tag in the list: the chip, lit while it filters or the keyboard's cursor is on it.
struct LoreTagChip: View {
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
struct FlowRow: Layout {
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
