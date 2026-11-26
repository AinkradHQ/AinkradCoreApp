// LoreBars — the two bars over the page: the AI document banner (D-28) and the table tools (E0-7).
import CoreKit
import CoreUI
import SwiftUI

/// Shown on a note that came from an AI session's `.md` file: edits save back to that file.
struct LoreAIBanner: View {
    @Environment(\.coreAccent) private var paneAccent
    let model: LoreModel
    let doc: LoreSessionDoc

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "sparkles").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.accent(paneAccent))
                .accessibilityHidden(true)
            Text("From session “\(doc.sessionTitle ?? "an AI session")” · edits save back to the file \(doc.fileName)")
                .coreFont(size: MacTextSize.meta + 1).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Space.s2)
            Button {
                model.openSession?(doc.session)
            } label: {
                Label("Open session", systemImage: "arrow.right")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .disabled(model.openSession == nil)
            .help("Open the AI session that wrote this file")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: LoreView.measure)
        .background(GlassInk.accent(paneAccent).opacity(0.14), in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lore-ai-banner")
    }
}

/// Table: Grid | Text, and, with the caret in a table, Row, Column and Delete row.
struct LoreTableBar: View {
    let model: LoreModel

    var body: some View {
        HStack(spacing: Space.s2) {
            Text("Table").coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            Spacer(minLength: Space.s2)
            if model.caretInTable {
                tool("Row", "plus", "Add a row below this one") { model.tableTool(.addRow) }
                tool("Column", "plus", "Add a column at the end") { model.tableTool(.addColumn) }
                tool("Delete row", "trash", "Delete the row the cursor is in") { model.tableTool(.deleteRow) }
            }
            CoreSegmented(
                "Table view", segments: [CoreSegment(false, "Grid"), CoreSegment(true, "Text")],
                selection: Binding(get: { model.tablesAsText }, set: { model.setTablesAsText($0) }))
        }
        .frame(maxWidth: LoreView.measure, minHeight: MacSize.controlMd)
        .accessibilityIdentifier("lore-table-bar")
    }

    private func tool(_ title: String, _ symbol: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Label(title, systemImage: symbol) }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help(help)
    }
}
