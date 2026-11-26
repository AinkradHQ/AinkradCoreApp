import CoreKit
import CoreUI
import LoreEditor
import Shell
import SwiftUI

/// The Lore space: one calm writing surface on the pane's Look (transparency and blur, like Accounts, Connections and
/// Leyline). The header, the navigator and the inspector sit straight on that surface with no cards around them; the
/// note is the hero in the middle. While typing, the header and the key line step back. Opens on today's note with
/// the cursor ready (L1). Every action has a key (`LoreKeys`); the key line along the bottom names them.
struct LoreView: View {
    let model: LoreModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var listFocus: Bool
    @FocusState private var outlineFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            LoreTopBar(model: model)
                .opacity(model.typing ? 0.3 : 1)
                .onHover { if $0 { model.typing = false } }
            if let line = model.notice {
                CoreNotice(symbol: "clock.arrow.circlepath", title: line, tone: .warn) { noticeButtons }
                    .frame(maxWidth: Self.measure)
                    .padding(.bottom, Space.s2)
                    .transition(.opacity)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                if model.showLeft {
                    LoreLeftSidebar(model: model, focus: $listFocus).frame(width: Self.leftWidth)
                        .transition(side(-1))
                }
                // The page is capped and centred: on a wide window the room left goes to the margins beside it.
                content.frame(maxWidth: Self.paneWidth, maxHeight: .infinity).frame(maxWidth: .infinity)
                if model.showRight {
                    LoreRightSidebar(model: model, focus: $outlineFocus).frame(width: Self.rightWidth)
                        .transition(side(1))
                }
            }
            .padding(.horizontal, Space.s4)
            // A critically damped spring: the sidebar arrives without overshoot; Reduce Motion, a fade.
            .animation(Motion.calm(.spring(duration: 0.36, bounce: 0), reduceMotion), value: model.showLeft)
            .animation(Motion.calm(.spring(duration: 0.36, bounce: 0), reduceMotion), value: model.showRight)
            // Typing and focus mode put the key line away; it comes back on the next pause.
            LoreKeyLine().opacity(model.typing || !(model.showLeft || model.showRight) ? 0 : 1)
        }
        .background { keys }
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .animation(Motion.out(Motion.ui), value: model.notice)
        .animation(Motion.out(model.typing ? Motion.reveal : Motion.ui), value: model.typing)
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

    /// A sidebar comes in from its own edge, a short way; Reduce Motion: it fades.
    private func side(_ edge: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: edge * Space.s3))
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
    static let leftWidth = Space.s8 * 8
    static let rightWidth = Space.s8 * 8
    /// The editor's text size and measure (`LoreTextView`: 45 body widths), for what lines up with the text column.
    static var textSize: CGFloat {
        let size = LoreOptions.options.string(LoreOptions.textSize, "medium")
        return MacTextSize.scaled(MacTextSize.title) * LoreOptions.scale(size)
    }
    static var measure: CGFloat { (textSize * 45).rounded() }

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
            Button(LoreKeys.today.title) { Task { await model.openDay(model.todayKey) } }.loreKey(LoreKeys.today)
                .disabled(model.isToday || model.service == nil)
            Button(LoreKeys.save.title) { Task { await model.save() } }.loreKey(LoreKeys.save)
                .disabled(model.load != .ready)
            // Versions live in the inspector; the key opens all of them.
            Button(LoreKeys.versions.title) { model.showVersions() }.loreKey(LoreKeys.versions)
                .disabled(model.note == nil || model.load != .ready)
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

/// The note, straight on the pane: no card, the text column centred by the editor. A blank page shows the prompt
/// on its first line. The editor stays the same view across days and notes; only its text changes.
private struct LorePageIsland: View {
    let model: LoreModel

    var body: some View {
        VStack(spacing: 0) {
            if model.openDoc != nil || model.hasTable {
                VStack(spacing: Space.s2) {
                    if let doc = model.openDoc { LoreAIBanner(model: model, doc: doc) }
                    if model.hasTable { LoreTableBar(model: model) }
                }
                .padding(.horizontal, Space.s6).padding(.top, Space.s2)
            }
            // Full width: the editor centres its text column with insets, so the scroller sits at the page's edge.
            if let editor = model.editor {
                LoreEditor(editor)
                    .opacity(model.load == .ready ? 1 : 0)
                    .overlay(alignment: .top) {
                        if model.pageBlank, model.load == .ready {
                            LoreBlankPrompt(model: model, size: LoreView.textSize)
                        }
                    }
                    .animation(Motion.out(Motion.ui), value: model.pageBlank)
                    .onAppear { model.ready() }
                    .onChange(of: model.load) { if model.load == .ready { model.ready() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(model.title)
        .accessibilityIdentifier("lore-page")
    }
}

/// On the surface, no card: ‹ › days, the long date (or the note's title), Today when away from it, the project chip;
/// the save state, Open… ⌘O and New ⌘N (versions are in the inspector, and ⇧⌘H). The sidebar toggles sit at the
/// ends, over their sidebars. Every control is the apps' header kit: `AppActionTile` (New prominent), `CoreIconButton`,
/// and the tile face (`LoreTileLabel`) on the two menus, so hover, press and the icon bounce match Leyline and Accounts.
private struct LoreTopBar: View {
    let model: LoreModel
    @State private var projectOpen = false
    @State private var moreOpen = false
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        AppHeader {
            CoreIconButton(symbol: "sidebar.left", label: LoreKeys.left.help) {
                model.showLeft.toggle()
            }
            .loreKey(LoreKeys.left)
            CoreIconButton(symbol: "chevron.left", label: LoreKeys.dayBefore.help) { model.step(-1) }
                .loreKey(LoreKeys.dayBefore)
            CoreIconButton(symbol: "chevron.right", label: LoreKeys.nextDay.help) { model.step(1) }
                .loreKey(LoreKeys.nextDay)
            // A long title shortens instead of pushing the header out of the window.
            Text(model.title).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                .truncationMode(.tail).frame(maxWidth: Space.s8 * 10, alignment: .leading)
                .help(model.title)
                .accessibilityAddTraits(.isHeader)
                .padding(.trailing, Space.s1)
            if !model.isToday, model.service != nil {
                // ⌘D is bound by the space's hidden keys; the tooltip names it.
                AppActionTile(
                    title: "Today", symbol: "sun.max", key: LoreKeys.today.label, hue: GlassInk.accent(paneAccent)
                ) {
                    Task { await model.openDay(model.todayKey) }
                }
            }
            LoreProjectChip(model: model, open: $projectOpen)
            if let n = model.note, model.load == .ready {
                CoreDropdown(items: more(n), isPresented: $moreOpen) {
                    LoreTileLabel(title: "More", symbol: "ellipsis", chevron: true)
                }
                .help("Rename, copy a link to or delete this note")
                .accessibilityLabel("More for this note")
                .accessibilityIdentifier("lore-more")
            }
            Button(LoreKeys.project.title) { projectOpen.toggle() }.loreKey(LoreKeys.project)
                .disabled(model.note?.kind != "note")
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        } actions: {
            Text(model.syncWords).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                .accessibilityIdentifier("lore-sync")
            AppActionTile(
                title: "Open…", symbol: "magnifyingglass", key: LoreKeys.open.label, hue: GlassInk.accent(paneAccent)
            ) {
                LoreOpenSheet.open(model)
            }
            .loreKey(LoreKeys.open)
            .disabled(model.service == nil)
            .accessibilityIdentifier("lore-open")
            // ⌘N is the shell's New (File menu), which runs this pane's `onNew`; the tooltip names it.
            AppActionTile(
                title: "New", symbol: "plus", key: LoreKeys.new.label, hue: GlassInk.accent(paneAccent),
                prominent: true
            ) {
                Task { await model.newNote() }
            }
            .disabled(model.load != .ready)
            .accessibilityIdentifier("lore-new")
            CoreIconButton(symbol: "sidebar.right", label: LoreKeys.right.help) {
                model.showRight.toggle()
            }
            .loreKey(LoreKeys.right)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// The open note's own menu: the list's right-click menu, minus Open and Move (the project chip moves it).
    private func more(_ n: LoreNote) -> [CoreDropdownItem] {
        let name = model.title
        let edit = LoreModel.canEdit(n)
        return [
            CoreDropdownItem("Rename…", symbol: "pencil", enabled: edit) {
                model.showLeft = true
                model.renameRequest = n.id
            },
            CoreDropdownItem("Copy Link", symbol: "link") { model.copyLink(n.id, title: name) },
            CoreDropdownItem("Delete", symbol: "trash", destructive: true, enabled: edit) {
                Task { await model.trashNote(n.id, title: name) }
            },
        ]
    }
}
