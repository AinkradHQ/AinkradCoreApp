import CoreUI
import LoreEditor
import Shell
import SwiftUI

/// The Lore space: a slim top bar island and the page island over the wallpaper. The pane draws no background of its
/// own (`own: true`), like the Projects and Leyline spaces. Opens on today's note with the cursor ready (L1).
struct LoreView: View {
    let model: LoreModel

    var body: some View {
        VStack(spacing: Space.s2) {
            LoreTopBar(model: model)
            if let line = model.notice {
                CoreNotice(symbol: "clock.arrow.circlepath", title: line, tone: .warn) {
                    Button("Dismiss") { model.notice = nil }.buttonStyle(CoreButtonStyle(.secondary))
                }
                .frame(maxWidth: Self.pageWidth)
                .transition(.opacity)
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Space.s2)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .animation(Motion.out(Motion.ui), value: model.notice)
        .paneLook(nil, own: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lore-space")
    }

    /// A reading measure: about 80 characters of body text.
    static let pageWidth = Space.s8 * 24

    @ViewBuilder private var content: some View {
        switch model.load {
        case .ready, .loading:
            LorePageIsland(model: model)
        case .notConnected:
            CoreStateCard(
                symbol: "wifi.slash", title: "Not connected",
                line: "Notes live on your Core. Today's note opens here once this Mac is connected.")
        case .absent:
            CoreStateCard(
                symbol: "text.book.closed", title: "Lore is not on this Core yet",
                line: "Update the Core to keep notes on it.")
        case .failed(let why):
            CoreStateCard(
                symbol: "exclamationmark.triangle", title: "Unable to open the note", line: why,
                primary: CoreAction("Try Again", key: .primary) { Task { await model.reload() } })
        }
    }
}

/// The note on a glass page. The editor stays the same view across days and notes; only its text changes.
private struct LorePageIsland: View {
    let model: LoreModel

    var body: some View {
        Group {
            if let editor = model.editor {
                LoreEditor(editor)
                    .opacity(model.load == .ready ? 1 : 0)
                    .onAppear { model.ready() }
                    .onChange(of: model.load) { if model.load == .ready { model.ready() } }
            }
        }
        .padding(.horizontal, Space.s6).padding(.vertical, Space.s5)
        .frame(maxWidth: LoreView.pageWidth, maxHeight: .infinity)
        .coreFrame(radius: Radius.pane)
        .accessibilityLabel(model.title)
        .accessibilityIdentifier("lore-page")
    }
}

/// Long date (or the note's title), ‹ › days, Today, the project chip; the save state, Open… ⌘O and New ⌘N.
private struct LoreTopBar: View {
    let model: LoreModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        AppHeader {
            CoreIconButton(symbol: "chevron.left", label: "Show the day before  ⌘[") { model.step(-1) }
                .keyboardShortcut("[", modifiers: .command)
            CoreIconButton(symbol: "chevron.right", label: "Show the next day  ⌘]") { model.step(1) }
                .keyboardShortcut("]", modifiers: .command)
            Text(model.title).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                .help(model.title)
                .accessibilityAddTraits(.isHeader)
            Button("Today") { Task { await model.openDay(model.todayKey) } }
                .buttonStyle(CoreButtonStyle(.secondary))
                .disabled(model.isToday || model.service == nil)
                .help("Go to today's note")
            // TODO(R6-04): the chip becomes the project menu (personal / projects).
            AppStatChip(model.note?.project == nil ? "person" : "folder", model.projectName, palette.text2)
                .help(model.day == nil ? "This note's project" : "Daily notes are personal")
                .accessibilityLabel("Project: \(model.projectName)")
        } actions: {
            Text(model.syncWords).foregroundStyle(GlassInk.secondary).accessibilityIdentifier("lore-sync")
            Button {
                LoreOpenSheet.open(model)
            } label: {
                Label("Open…", systemImage: "magnifyingglass")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .keyboardShortcut("o", modifiers: .command)
            .disabled(model.service == nil)
            .help("Find a note  ⌘O")
            Button {
                Task { await model.newNote() }
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent))
            .disabled(model.load != .ready)
            .help("A blank note in this project, or personal  ⌘N")
            .accessibilityIdentifier("lore-new")
        }
        .frame(maxWidth: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }
}
