import CoreKit
import CoreUI
import SwiftUI

/// Notes that link to the open one, under the page. Only built when there are some; a click opens that note.
struct LoreBacklinksIsland: View {
    let model: LoreModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(model.backlinks.count == 1 ? "Linked from 1 note" : "Linked from \(model.backlinks.count) notes")
                .coreFont(size: MacTextSize.headline, weight: .semibold)
                .foregroundStyle(palette.text2)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: Space.s1) {
                    ForEach(model.backlinks) { b in
                        CoreRow(
                            b.title.isEmpty ? "Untitled note" : b.title, subtitle: b.context.isEmpty ? nil : b.context,
                            symbol: "arrow.turn.up.left", action: { Task { await model.openNote(b.note) } }
                        )
                        .help("Open \(b.title.isEmpty ? "this note" : b.title)")
                    }
                }
            }
            .frame(maxHeight: (MacSize.controlLg + Space.s2 + Space.s1) * 3)
        }
        .padding(Space.s4)
        .frame(maxWidth: LoreView.pageWidth, alignment: .leading)
        .coreFrame(radius: Radius.pane)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Backlinks")
        .accessibilityIdentifier("lore-backlinks")
        .transition(.opacity)
    }
}

/// The project chip: Personal, or one of the projects. A daily note is always personal, so its chip does not open.
struct LoreProjectChip: View {
    let model: LoreModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let personal = model.note?.project == nil
        let chip = AppStatChip(personal ? "person" : "folder", model.projectName, palette.text2)
        if model.note?.kind == "note" {
            CoreDropdown(items: items) {
                HStack(spacing: Space.s1) {
                    chip
                    Image(systemName: "chevron.up.chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(palette.text2).accessibilityHidden(true)
                }
            }
            .help("Move this note to a project, or keep it personal")
            .accessibilityLabel("Project: \(model.projectName)")
        } else {
            chip.help("Daily notes are personal").accessibilityLabel("Project: \(model.projectName)")
        }
    }

    private var items: [CoreDropdownItem] {
        let current = model.note?.project
        return [
            CoreDropdownItem("Personal", symbol: "person", checked: current == nil) {
                Task { await model.move(to: nil) }
            }
        ]
            + model.projectChoices.map { p in
                CoreDropdownItem(p.name, symbol: "folder", checked: current == p.id) {
                    Task { await model.move(to: p.id) }
                }
            }
    }
}

/// Versions: the list at the left, the chosen text at the right. Restore is one line afterwards, with Undo.
struct LoreVersionsSheet: View {
    let model: LoreModel
    let selecting: String?
    @State private var list: [LoreVersion]?
    @State private var failed: String?
    @State private var pick: String?
    @State private var text: String?
    @Environment(\.corePalette) private var palette

    /// The preview is plain text and capped: a note can be 2 MB.
    private static let previewLimit = 20_000

    var body: some View {
        CoreDialogPanel("Versions", width: Space.s8 * 20) {
            content.frame(height: Space.s8 * 10)
            CoreDialogFooter(
                cancel: CoreAction("Close", key: .cancel) { model.host.shell.closeDialog() },
                primary: CoreAction("Restore", key: .primary, run: restore),
                enabled: pick != nil && text != nil && model.note?.trashed != true)
        }
        .task { await load() }
        .onChange(of: pick) { Task { await loadText() } }
    }

    @ViewBuilder private var content: some View {
        if let failed {
            CoreStateCard(symbol: "exclamationmark.triangle", title: "Unable to load versions", line: failed)
        } else if let list, list.isEmpty {
            CoreStateCard(
                symbol: "clock.arrow.circlepath", title: "No versions yet",
                line: "Lore keeps a version after a pause in writing, before an AI session edits, and before a restore."
            )
        } else if let list {
            HStack(alignment: .top, spacing: Space.s4) {
                ScrollView {
                    VStack(spacing: Space.s1) {
                        ForEach(list) { v in
                            CoreRow(
                                LoreVersionWords.title(v), subtitle: LoreVersionWords.detail(v),
                                symbol: v.kind == "conflict" ? "exclamationmark.arrow.triangle.2.circlepath" : nil,
                                selected: v.id == pick, action: { pick = v.id }
                            )
                        }
                    }
                }
                .frame(width: Space.s8 * 8)
                ScrollView {
                    Text(verbatim: preview).coreFont(size: MacTextSize.body).foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(Space.s3)
                .background(GlassInk.well, in: coreShape(Radius.cardMac))
                .accessibilityLabel("Preview")
            }
        } else {
            CoreWorkingBar()
        }
    }

    private var preview: String {
        guard let text else { return pick == nil ? "Choose a version to see its text." : "" }
        return text.count > Self.previewLimit ? String(text.prefix(Self.previewLimit)) + "\n…" : text
    }

    private func load() async {
        guard let id = model.note?.id, let service = model.service else { return }
        do {
            let all = try await service.versions(id)
            list = all
            pick = selecting.flatMap { s in all.first { $0.id == s }?.id } ?? all.first?.id
        } catch { failed = model.words(error) }
    }

    private func loadText() async {
        text = nil
        guard let id = model.note?.id, let service = model.service, let v = pick else { return }
        let t = try? await service.versionText(id, version: v)
        if pick == v { text = t ?? "Unable to load this version." }
    }

    private func restore() {
        guard let v = pick else { return }
        model.host.shell.closeDialog()
        Task { await model.restore(v) }
    }
}
