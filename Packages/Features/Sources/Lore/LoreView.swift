import CoreUI
import LoreEditor
import Shell
import SwiftUI

/// The Lore space: a slim top bar island and the page island over the wallpaper. The pane draws no background of its
/// own (`own: true`), like the Projects and Leyline spaces. Opens on today's note with the cursor ready (L1).
struct LoreView: View {
    let model: LoreModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.s2) {
            LoreTopBar(model: model)
            if let line = model.notice {
                CoreNotice(symbol: "clock.arrow.circlepath", title: line, tone: .warn) { noticeButtons }
                    .frame(maxWidth: Self.pageWidth)
                    .transition(.opacity)
            }
            HStack(spacing: Space.s2) {
                if model.showLeft {
                    LoreLeftSidebar(model: model).frame(width: Self.leftWidth).coreWell(radius: Radius.pane)
                        .transition(.opacity)
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showRight {
                    LoreRightSidebar(model: model).frame(width: Self.rightWidth).coreWell(radius: Radius.pane)
                        .transition(.opacity)
                }
            }
            // Reduce Motion: the sidebars simply appear.
            .animation(reduceMotion ? nil : Motion.out(Motion.ui), value: model.showLeft)
            .animation(reduceMotion ? nil : Motion.out(Motion.ui), value: model.showRight)
        }
        .padding(Space.s2)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .animation(Motion.out(Motion.ui), value: model.notice)
        .appLook(AppLookPrefs.shared("lore"))
        .onAppear { model.editor?.setTextScale(LoreOptions.scale(LoreOptions.options.string(LoreOptions.textSize, "medium"))) }
        .onChange(of: LoreOptions.options.string(LoreOptions.textSize, "medium")) { _, id in
            model.editor?.setTextScale(LoreOptions.scale(id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lore-space")
    }

    @ViewBuilder private var noticeButtons: some View {
        switch model.noticeAction {
        case .undoRestore(let version)?:
            // "Restored · Undo": one line, no Dismiss.
            Button("Undo") { Task { await model.restore(version, offerUndo: false) } }
                .buttonStyle(CoreButtonStyle(.secondary)).help("Bring back the text before the restore")
        case .seeChanges(let version)?:
            Button("See changes") { model.showVersions(selecting: version) }
                .buttonStyle(CoreButtonStyle(.secondary)).help("Open the version that was kept")
            Button("Dismiss") { model.notice = nil }.buttonStyle(CoreButtonStyle(.secondary))
        case nil:
            Button("Dismiss") { model.notice = nil }.buttonStyle(CoreButtonStyle(.secondary))
        }
    }

    /// The page's widest text column. It was 768; the page now takes the room the sidebars leave (E10-1).
    static let pageWidth = Space.s8 * 28
    static let leftWidth = Space.s8 * 7.5
    static let rightWidth = Space.s8 * 8

    @ViewBuilder private var content: some View {
        switch model.load {
        case .ready, .loading:
            VStack(spacing: Space.s2) {
                LorePageIsland(model: model)
            }
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
        VStack(spacing: Space.s2) {
            if let doc = model.openDoc { LoreAIBanner(model: model, doc: doc) }
            if model.hasTable { LoreTableBar(model: model) }
            Group {
                if let editor = model.editor {
                    LoreEditor(editor)
                        .opacity(model.load == .ready ? 1 : 0)
                        .onAppear { model.ready() }
                        .onChange(of: model.load) { if model.load == .ready { model.ready() } }
                }
            }
            .frame(maxWidth: LoreView.pageWidth)
        }
        .padding(.horizontal, Space.s6).padding(.vertical, Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coreFrame(radius: Radius.pane)
        .accessibilityLabel(model.title)
        .accessibilityIdentifier("lore-page")
    }
}

/// Long date (or the note's title), ‹ › days, Today, the project chip; the save state, Open… ⌘O and New ⌘N.
private struct LoreTopBar: View {
    let model: LoreModel

    var body: some View {
        AppHeader {
            CoreIconButton(symbol: "chevron.left", label: "Show the day before  ⌥⌘[") { model.step(-1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            CoreIconButton(symbol: "chevron.right", label: "Show the next day  ⌥⌘]") { model.step(1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Text(model.title).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                .help(model.title)
                .accessibilityAddTraits(.isHeader)
            Button("Today") { Task { await model.openDay(model.todayKey) } }
                .buttonStyle(CoreButtonStyle(.secondary))
                .disabled(model.isToday || model.service == nil)
                .help("Go to today's note")
            LoreProjectChip(model: model)
        } actions: {
            Text(model.syncWords).foregroundStyle(GlassInk.secondary).accessibilityIdentifier("lore-sync")
            CoreIconButton(symbol: "sidebar.left", label: "Hide the left sidebar  ⌘[") { model.showLeft.toggle() }
                .keyboardShortcut("[", modifiers: .command)
            CoreIconButton(symbol: "sidebar.right", label: "Hide the right sidebar  ⌘]") { model.showRight.toggle() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Focus") { model.toggleFocus() }.keyboardShortcut(".", modifiers: .command).hidden()
                .frame(width: 0, height: 0).accessibilityHidden(true)
            CoreIconButton(symbol: "clock.arrow.circlepath", label: "Show earlier versions of this note") {
                model.showVersions()
            }
            .disabled(model.note == nil || model.load != .ready)
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
