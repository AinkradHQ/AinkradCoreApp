import CoreUI
import LoreEditor
import Shell
import SwiftUI

/// The Lore space: the top bar, the note list, the page and the outline as cards on the pane's surface, which follows
/// the Look (transparency and blur) like Accounts, Connections and Leyline. Opens on today's note with the cursor ready
/// (L1). Every action has a key (`LoreKeys`); the key line along the bottom names them.
struct LoreView: View {
    let model: LoreModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var listFocus: Bool
    @FocusState private var outlineFocus: Bool

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
                    LoreLeftSidebar(model: model, focus: $listFocus).frame(width: Self.leftWidth)
                        .coreWell(radius: Radius.pane)
                        .transition(.opacity)
                }
                // The page is capped and centred: on a wide window the room left goes to the margins beside it.
                content.frame(maxWidth: Self.paneWidth, maxHeight: .infinity).frame(maxWidth: .infinity)
                if model.showRight {
                    LoreRightSidebar(model: model, focus: $outlineFocus).frame(width: Self.rightWidth)
                        .coreWell(radius: Radius.pane)
                        .transition(.opacity)
                }
            }
            // Reduce Motion: the sidebars simply appear.
            .animation(reduceMotion ? nil : Motion.out(Motion.ui), value: model.showLeft)
            .animation(reduceMotion ? nil : Motion.out(Motion.ui), value: model.showRight)
            LoreKeyLine()
        }
        .padding([.horizontal, .top], Space.s2)
        .background { keys }
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .animation(Motion.out(Motion.ui), value: model.notice)
        // The pane's surface follows the Look (Settings, Appearance, or Lore's own): transparency and blur.
        .paneLook(AppLookPrefs.shared("lore").look)
        .appLookTheme(AppLookPrefs.shared("lore"))
        .onAppear {
            model.editor?.setTextScale(LoreOptions.scale(LoreOptions.options.string(LoreOptions.textSize, "medium")))
        }
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

    /// The widest bar over the page (the AI banner, the table tools). The text column itself is the editor's measure,
    /// centred inside a scroll view that spans the whole page, so its scroller sits at the page's right edge.
    static let pageWidth = Space.s8 * 28
    /// The page pane's widest (Ahmed, 2026-11-26: "reduce the editor pane's width"); the editor's text column and its
    /// side insets fit inside it.
    static let paneWidth = Space.s8 * 30
    /// The sidebars took a little more of the room too.
    static let leftWidth = Space.s8 * 8.5
    static let rightWidth = Space.s8 * 9

    /// The keys without a control of their own on screen. Hidden buttons, so the menu bar's keys still come first.
    private var keys: some View {
        Group {
            Button(LoreKeys.find.title) {
                model.showLeft = true
                listFocus = true
            }
            .loreKey(LoreKeys.find)
            Button(LoreKeys.outline.title) {
                model.showRight = true
                outlineFocus = true
            }
            .loreKey(LoreKeys.outline)
            Button(LoreKeys.focus.title) { model.toggleFocus() }.loreKey(LoreKeys.focus)
            Button(LoreKeys.save.title) { Task { await model.save() } }.loreKey(LoreKeys.save)
                .disabled(model.load != .ready)
        }
        .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }

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
        VStack(spacing: 0) {
            if model.openDoc != nil || model.hasTable {
                VStack(spacing: Space.s2) {
                    if let doc = model.openDoc { LoreAIBanner(model: model, doc: doc) }
                    if model.hasTable { LoreTableBar(model: model) }
                }
                .padding(.horizontal, Space.s6).padding(.top, Space.s5)
            }
            // Full width: the editor centres its text column with insets, so the scroller sits at the page's edge.
            if let editor = model.editor {
                LoreEditor(editor)
                    .opacity(model.load == .ready ? 1 : 0)
                    .onAppear { model.ready() }
                    .onChange(of: model.load) { if model.load == .ready { model.ready() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The page sits on the pane's Look surface (transparency and blur) with only a faint lift, lighter than the
        // sidebar cards, so the wallpaper shows through as much as the Look allows. No outline.
        .background(GlassInk.lift(0.04), in: coreShape(Radius.pane))
        .clipShape(coreShape(Radius.pane))
        .accessibilityLabel(model.title)
        .accessibilityIdentifier("lore-page")
    }
}

/// Long date (or the note's title), ‹ › days, Today, the project chip; the save state, Open… ⌘O and New ⌘N.
private struct LoreTopBar: View {
    let model: LoreModel
    @State private var projectOpen = false

    var body: some View {
        AppHeader {
            CoreIconButton(symbol: "chevron.left", label: LoreKeys.dayBefore.help) { model.step(-1) }
                .loreKey(LoreKeys.dayBefore)
            CoreIconButton(symbol: "chevron.right", label: LoreKeys.nextDay.help) { model.step(1) }
                .loreKey(LoreKeys.nextDay)
            Text(model.title).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                .help(model.title)
                .accessibilityAddTraits(.isHeader)
            Button("Today") { Task { await model.openDay(model.todayKey) } }
                .buttonStyle(CoreButtonStyle(.secondary))
                .loreKey(LoreKeys.today)
                .disabled(model.isToday || model.service == nil)
                .help(LoreKeys.today.help)
            LoreProjectChip(model: model, open: $projectOpen)
            Button(LoreKeys.project.title) { projectOpen.toggle() }.loreKey(LoreKeys.project)
                .disabled(model.note?.kind != "note")
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        } actions: {
            Text(model.syncWords).foregroundStyle(GlassInk.secondary).accessibilityIdentifier("lore-sync")
            CoreIconButton(symbol: "sidebar.left", label: LoreKeys.left.help) { model.showLeft.toggle() }
                .loreKey(LoreKeys.left)
            CoreIconButton(symbol: "sidebar.right", label: LoreKeys.right.help) { model.showRight.toggle() }
                .loreKey(LoreKeys.right)
            CoreIconButton(symbol: "clock.arrow.circlepath", label: LoreKeys.versions.help) {
                model.showVersions()
            }
            .loreKey(LoreKeys.versions)
            .disabled(model.note == nil || model.load != .ready)
            Button {
                LoreOpenSheet.open(model)
            } label: {
                Label("Open…", systemImage: "magnifyingglass")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .loreKey(LoreKeys.open)
            .disabled(model.service == nil)
            .help(LoreKeys.open.help)
            // ⌘N is the shell's New (File menu), which runs this pane's `onNew`; the keycap shows it here.
            Button {
                Task { await model.newNote() }
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent))
            .environment(\.coreKeycap, LoreKeys.new.label)
            .disabled(model.load != .ready)
            .help("A blank note in this project, or personal  ⌘N")
            .accessibilityIdentifier("lore-new")
        }
        .frame(maxWidth: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }
}
