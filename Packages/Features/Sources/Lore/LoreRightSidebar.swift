// LoreRightSidebar — outline, backlinks, versions, info of the open note (E10-1, mockup 18-lore).
import CoreKit
import CoreUI
import SwiftUI

/// ⌘3 puts the cursor here: ↑ ↓ walk the headings, backlinks and versions, Return goes to the heading, opens the
/// backlink or shows the version; Esc goes back to the note.
struct LoreRightSidebar: View {
    let model: LoreModel
    var focus: FocusState<Bool>.Binding
    @State private var picked: Int?
    @State private var cursor: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    section("Outline")
                    ForEach(model.outline) { h in
                        LoreSideRow(
                            title: h.title, selected: picked == h.id, indented: h.level > 1,
                            cursor: cursor == "h:\(h.id)"
                        ) { go(h) }
                        .id("h:\(h.id)")
                    }
                    section("Backlinks")
                    if model.backlinks.isEmpty {
                        quiet("No notes link here yet.")
                    }
                    ForEach(model.backlinks) { b in
                        LoreSideRow(
                            title: b.title.isEmpty ? "Untitled note" : b.title, symbol: "link",
                            cursor: cursor == "b:\(b.note)"
                        ) {
                            Task { await model.openNote(b.note) }
                        }
                        .id("b:\(b.note)")
                    }
                    section("Versions")
                    ForEach(Array(model.sideVersions.prefix(12).enumerated()), id: \.element.id) { i, v in
                        VersionRow(model: model, version: v, current: i == 0, cursor: cursor == "v:\(v.id)")
                            .id("v:\(v.id)")
                    }
                    section("Info")
                    info
                }
                .padding(.horizontal, Space.s2).padding(.bottom, Space.s4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: cursor) { if let cursor { proxy.scrollTo(cursor) } }
        }
        .focusable()
        .focused(focus)
        .focusEffectDisabled()
        .loreListKeys(ids, cursor: $cursor, run: run) {
            focus.wrappedValue = false
            model.page.focus()
        }
        .onChange(of: focus.wrappedValue) { cursor = focus.wrappedValue ? ids.first : nil }
        .accessibilityIdentifier("lore-right")
    }

    private var ids: [String] {
        model.outline.map { "h:\($0.id)" } + model.backlinks.map { "b:\($0.note)" }
            + model.sideVersions.prefix(12).map { "v:\($0.id)" }
    }

    private func go(_ h: LoreHeading) {
        picked = h.id
        model.reveal(h)
    }

    private func run(_ id: String) {
        let value = String(id.dropFirst(2))
        switch id.prefix(2) {
        case "h:": if let h = model.outline.first(where: { "\($0.id)" == value }) { go(h) }
        case "b:": Task { await model.openNote(value) }
        default: model.showVersions(selecting: value)
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .padding(.horizontal, Space.s2).padding(.top, Space.s4).padding(.bottom, Space.s1)
            .accessibilityAddTraits(.isHeader)
    }

    private func quiet(_ t: String) -> some View {
        Text(t).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s2)
    }

    private var info: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
            row("Words", "\(model.wordCount)")
            row("Project", model.note?.project == nil ? "None" : model.projectName)
            row("Saved in", model.savedIn)
            row("Tags", model.noteTags.isEmpty ? "None" : model.noteTags.map { "#" + $0 }.joined(separator: " "))
        }
        .padding(.horizontal, Space.s2)
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(GlassInk.secondary).frame(width: Space.s8 * 2, alignment: .leading)
            Text(v).lineLimit(1).truncationMode(.middle).help(v)
        }
        .coreFont(size: MacTextSize.meta + 1)
    }
}

private struct VersionRow: View {
    let model: LoreModel
    let version: LoreVersion
    let current: Bool
    var cursor = false
    @State private var hover = false

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "clock.arrow.circlepath").coreFont(size: MacTextSize.meta + 1)
                .foregroundStyle(GlassInk.secondary).frame(width: Space.s4).accessibilityHidden(true)
            Text(LoreVersionWords.detail(version)).coreFont(size: MacTextSize.body).lineLimit(1)
            Spacer(minLength: Space.s1)
            if current {
                CoreChip("Current", minWidth: 0)
            } else if hover || cursor {
                Button("Restore") { Task { await model.restore(version.id) } }
                    .buttonStyle(CoreButtonStyle(.secondary)).help("Bring back this version")
            }
        }
        .padding(.horizontal, Space.s2).frame(minHeight: MacSize.controlMd)
        .background(
            cursor ? GlassInk.lift(0.16) : hover ? GlassInk.wellHover : .clear, in: coreShape(Radius.control)
        )
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
    }
}
