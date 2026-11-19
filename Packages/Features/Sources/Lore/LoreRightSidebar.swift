// LoreRightSidebar — outline, backlinks, versions, info of the open note (E10-1, mockup 18-lore).
import CoreKit
import CoreUI
import SwiftUI

struct LoreRightSidebar: View {
    let model: LoreModel
    @State private var picked: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                section("Outline")
                ForEach(model.outline) { h in
                    LoreSideRow(title: h.title, selected: picked == h.id, indented: h.level > 1) {
                        picked = h.id
                        model.reveal(h)
                    }
                }
                section("Backlinks")
                if model.backlinks.isEmpty {
                    quiet("No notes link here yet.")
                }
                ForEach(model.backlinks) { b in
                    LoreSideRow(title: b.title.isEmpty ? "Untitled note" : b.title, symbol: "link") {
                        Task { await model.openNote(b.note) }
                    }
                }
                section("Versions")
                ForEach(Array(model.sideVersions.prefix(12).enumerated()), id: \.element.id) { i, v in
                    VersionRow(model: model, version: v, current: i == 0)
                }
                section("Info")
                info
            }
            .padding(.horizontal, Space.s2).padding(.bottom, Space.s4)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("lore-right")
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
            Text(k).foregroundStyle(GlassInk.secondary).frame(width: 64, alignment: .leading)
            Text(v).lineLimit(1).truncationMode(.middle).help(v)
        }
        .coreFont(size: MacTextSize.meta + 1)
    }
}

private struct VersionRow: View {
    let model: LoreModel
    let version: LoreVersion
    let current: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "clock.arrow.circlepath").coreFont(size: MacTextSize.meta + 1)
                .foregroundStyle(GlassInk.secondary).frame(width: 16).accessibilityHidden(true)
            Text(LoreVersionWords.detail(version)).coreFont(size: MacTextSize.body).lineLimit(1)
            Spacer(minLength: Space.s1)
            if current {
                CoreChip("Current", minWidth: 0)
            } else if hover {
                Button("Restore") { Task { await model.restore(version.id) } }
                    .buttonStyle(CoreButtonStyle(.secondary)).help("Bring back this version")
            }
        }
        .padding(.horizontal, Space.s2).frame(minHeight: MacSize.controlMd)
        .background(hover ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
        .onHover { hover = $0 }
    }
}
