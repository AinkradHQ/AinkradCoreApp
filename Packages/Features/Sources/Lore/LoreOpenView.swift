import CoreKit
import CoreUI
import LoreImport
import SwiftUI

/// The ⌘O sheet: the search field, the filters, the list (recent notes, hits or the trash) and the actions.
struct LoreOpenView: View {
    @Bindable var finder: LoreFinder
    @Environment(\.corePalette) private var palette

    static let width = Space.s8 * 20
    static let listHeight = Space.s8 * 12

    var body: some View {
        CoreDialogPanel("Open a Note", width: Self.width) {
            CoreTextField("Search", placeholder: "Search your notes", text: $finder.query, autofocus: true) {
                finder.openPicked()
            }
            filters
            if !finder.semantic, !finder.typed.isEmpty, finder.phase == .ready {
                CoreNotice(
                    symbol: "text.magnifyingglass", title: "Searching by words only",
                    text: "Meaning search is not ready on this Core yet.")
            }
            Text(heading).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
                .accessibilityAddTraits(.isHeader)
            list.frame(height: Self.listHeight)
            footer
        }
        // ↑↓ move, Return opens (the field's submit), Esc closes (the dialog). The list follows the keys.
        .onKeyPress(.upArrow) {
            finder.move(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            finder.move(1)
            return .handled
        }
        .accessibilityIdentifier("lore-open")
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreSegmented(
                "Show",
                segments: [
                    CoreSegment(LoreScope.notes, "Notes", symbol: "doc.text"),
                    CoreSegment(LoreScope.daily, "Daily", symbol: "calendar"),
                    CoreSegment(LoreScope.trash, "Trash", symbol: "trash"),
                ], selection: $finder.scope)
            HStack(alignment: .top, spacing: Space.s3) {
                CoreSelect("Project", selection: $finder.project, options: finder.projectOptions(all: true))
                CoreTextField("Tag", placeholder: "Any tag", text: $finder.tag)
            }
        }
    }

    private var heading: String {
        if !finder.typed.isEmpty { return "Matches" }
        switch finder.scope {
        case .notes: return "Recent"
        case .daily: return "Daily notes"
        case .trash: return "In the trash for 30 days"
        }
    }

    @ViewBuilder private var list: some View {
        switch finder.phase {
        case .loading:
            Text("Searching…").foregroundStyle(palette.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsWord:
            CoreStateCard(
                symbol: "number", title: "Add a word", line: "A tag narrows a search. Type a word to search within it.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let why):
            CoreStateCard(
                symbol: "exclamationmark.triangle", title: "Unable to search", line: why,
                primary: CoreAction("Try Again") { finder.refresh(wait: false) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready where finder.rows.isEmpty:
            empty.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Space.s1) {
                        ForEach(Array(finder.rows.enumerated()), id: \.element.id) { i, row in
                            LoreFinderRow(
                                row: row, selected: i == finder.picked && finder.scope != .trash,
                                open: { finder.open(row) }, restore: { Task { await finder.restore(row) } }
                            )
                            .id(row.id)
                        }
                    }
                }
                .onChange(of: finder.picked) {
                    if finder.rows.indices.contains(finder.picked) { proxy.scrollTo(finder.rows[finder.picked].id) }
                }
            }
        }
    }

    @ViewBuilder private var empty: some View {
        if !finder.typed.isEmpty {
            CoreStateCard(
                symbol: "magnifyingglass", title: "No Matches",
                line: "Nothing matches “\(finder.typed)”. Try fewer words, or search all projects.")
        } else {
            switch finder.scope {
            case .notes:
                CoreStateCard(
                    symbol: "doc.text", title: "No Notes Yet", line: "Write the first one.",
                    primary: CoreAction("New Note") { finder.quickNew() })
            case .daily:
                CoreStateCard(
                    symbol: "calendar", title: "No Daily Notes", line: "Today's note is made when you open Lore.")
            case .trash:
                CoreStateCard(symbol: "trash", title: "The Trash Is Empty", line: "Deleted notes wait here for 30 days.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await finder.export() }
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .disabled(finder.exporting)
            .help(
                finder.project.isEmpty
                    ? "Save every note as a zip of Markdown files" : "Save this project's notes as a zip of Markdown files")
            Button {
                finder.importNotes()
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .disabled(!LoreImport.supports(finder.lore.service))
            .help("Bring in notes from a project's repo or from Markdown files")
            Spacer(minLength: Space.s3)
            Button("Close") { finder.lore.host.shell.closeDialog() }
                .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
            Button("New Note (advanced)…") { finder.advancedNew() }
                .buttonStyle(CoreButtonStyle(.secondary))
                .help("Choose the project and tags of a new note")
            Button("New Note") { finder.quickNew() }
                .buttonStyle(CoreButtonStyle(.prominent))
                .help("A blank note in this project, or personal")
        }
    }
}

/// A hit, a recent note or a trashed one: the row, and under it the snippet with the matched words in bold.
private struct LoreFinderRow: View {
    let row: LoreRow
    let selected: Bool
    let open: () -> Void
    let restore: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A trashed note is not opened (its Restore is the action), so its row is not a button.
            // TODO(design-system): proposal CoreRow rich subtitle — a row whose second line is styled text (the snippet).
            CoreRow(row.title, subtitle: row.sub, symbol: row.symbol, selected: selected, action: row.trashed ? nil : open) {
                if row.trashed {
                    Button("Restore") { restore() }.buttonStyle(CoreButtonStyle(.secondary))
                        .help("Take “\(row.title)” out of the trash")
                }
            }
            if let s = row.snippet, !s.text.isEmpty {
                Text(LoreHighlight.attributed(s, tint: palette.text))
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Space.s3 + MacSize.controlMd + Space.s3).padding(.trailing, Space.s3)
                    .padding(.bottom, Space.s2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// New Note (advanced): the project and the tags, then Create.
struct LoreNewView: View {
    @Bindable var finder: LoreFinder
    @Environment(\.corePalette) private var palette

    var body: some View {
        CoreDialogPanel("New Note", width: Space.s8 * 15) {
            CoreSelect("Project", selection: $finder.newProject, options: finder.projectOptions(all: false))
            CoreTextField("Tags", placeholder: "garden, plans", text: $finder.newTags) { finder.createAdvanced() }
            Text("Tags are written into the note as #tags. Separate them with spaces or commas.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            CoreDialogFooter(
                cancel: CoreAction("Back") { finder.backToOpen() },
                primary: CoreAction("Create Note", key: .primary) { finder.createAdvanced() })
        }
        .accessibilityIdentifier("lore-new-advanced")
    }
}
