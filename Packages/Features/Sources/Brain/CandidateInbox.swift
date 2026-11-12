import CoreUI
import SwiftUI

/// The Inbox: what the distillations proposed, across the open rooms. The list is on the left, the chosen candidate on the
/// right with its sources and Accept, Edit and Reject; Edit swaps the right side for a form. The keyboard drives it:
/// ↑ ↓ move, Return accepts, E edits, ⌫ rejects, ⌘↩ saves an edit, Esc cancels it.
struct CandidateInboxTab: View {
    let model: BrainModel
    private var c: BrainCandidates { model.candidates }
    @FocusState private var focus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let n = c.notice {
                CoreNotice(symbol: "exclamationmark.triangle", title: n, tone: .fail) {
                    Button("Dismiss") { c.dismissNotice() }.buttonStyle(CoreButtonStyle(.plain, size: .small))
                }
            }
            switch c.phase {
            case .idle, .loading: BrainSkeleton(shape: .list)
            case .failed(let why):
                BrainStateCard(
                    symbol: "exclamationmark.triangle", title: "Could not read the Inbox", text: why,
                    primary: CoreAction("Try again") { Task { await c.load() } })
            case .ready: ready
            }
        }
        .task(id: c.phase == .idle) { if c.phase == .idle { await c.load() } }
        .task {
            for r in model.rooms where c.policy(r.id) == nil { await c.loadPolicy(r.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-inbox")
    }

    @ViewBuilder private var ready: some View {
        if c.items.isEmpty {
            BrainStateCard(
                symbol: "tray", title: "Nothing needs review",
                text: "When a sync distils something new, it waits here until you accept or reject it.",
                secondary: CoreAction("Set rules") { goToRules() }
            )
            .accessibilityIdentifier("inbox-empty")
        } else {
            HStack(alignment: .top, spacing: Space.s4) {
                CandidateList(model: model, goToRules: goToRules).frame(width: Space.s8 * 13.75)
                Group {
                    if let d = c.draft, let cand = c.items.first(where: { $0.id == d.id }) {
                        CandidateEditForm(model: model, c: cand)
                    } else if let cand = c.selected {
                        CandidateDetail(model: model, c: cand)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .coreWell()
            }
            .focusable().focused($focus).focusEffectDisabled()
            .onAppear { focus = true }
            .onKeyPress(phases: .down) { key($0) }
        }
    }

    private func goToRules() {
        withAnimation(Motion.out(Motion.ui)) {
            c.paneMode = .settings
            model.tab = .rooms
        }
    }

    private func key(_ p: KeyPress) -> KeyPress.Result {
        // Typing in the edit form must not move the list.
        guard c.draft == nil, !c.busy, let cur = c.selected else { return .ignored }
        let v = c.visible
        if p.modifiers.isEmpty, p.key == .downArrow || p.key == .upArrow, let i = v.firstIndex(of: cur) {
            let j = i + (p.key == .downArrow ? 1 : -1)
            if v.indices.contains(j) { c.select(v[j].id) }
            return .handled
        }
        if p.modifiers.isEmpty, p.key == .return {
            Task { await c.accept(cur.id) }
            return .handled
        }
        if p.modifiers.isEmpty, p.characters == "e" {
            c.startEdit(cur.id)
            return .handled
        }
        if p.key == .delete || p.key == .deleteForward {
            Task { await c.reject(cur.id) }
            return .handled
        }
        return .ignored
    }
}

// MARK: list

private struct CandidateList: View {
    let model: BrainModel
    let goToRules: () -> Void
    private var c: BrainCandidates { model.candidates }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !c.inbox.queued.isEmpty { queued }
            HStack(spacing: Space.s2) {
                Text("Needs review").coreFont(size: MacTextSize.headline, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                CountBadge(c.visible.count, tone: .quiet, showsZero: true, label: "to review")
                Spacer(minLength: Space.s2)
                QuietFilter(
                    title: c.kindFilter?.plural ?? "All kinds",
                    items: [CoreDropdownItem("All kinds", checked: c.kindFilter == nil) { c.kindFilter = nil }]
                        + CandidateKind.allCases.map { k in
                            CoreDropdownItem(k.plural, checked: c.kindFilter == k) { c.kindFilter = k }
                        })
                QuietFilter(
                    title: c.rooms.first { $0.id == c.roomFilter }?.name ?? "All rooms",
                    items: [CoreDropdownItem("All rooms", checked: c.roomFilter == nil) { c.roomFilter = nil }]
                        + c.rooms.map { r in
                            CoreDropdownItem(r.name, checked: c.roomFilter == r.id) { c.roomFilter = r.id }
                        })
            }
            .padding(.horizontal, Space.s3)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(c.visible) { CandidateRow(model: model, c: $0) }
                }
            }
            .scrollIndicators(.automatic)
            autoLine
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var queued: some View {
        let names = c.inbox.queued.map(\.name)
        let list =
            names.count > 1
            ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") : names.first ?? ""
        return CoreNotice(
            symbol: "icloud.slash",
            title: BrainWords.plural(names.count, "room needs", "rooms need") + " a local model",
            text:
                "\(list) \(names.count == 1 ? "is" : "are") local only. "
                + "\(c.inbox.queuedItems) items wait to be distilled.",
            tone: .warn
        ) {
            Button("Choose a model") { goToQueued() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
        .accessibilityIdentifier("inbox-queued")
    }

    private func goToQueued() {
        if let r = c.inbox.queued.first { model.view(r.room) }
        withAnimation(Motion.out(Motion.ui)) {
            c.paneMode = .settings
            model.tab = .rooms
        }
    }

    private var autoLine: some View {
        let on = c.policies.filter { $0.value.autoAccept }.count
        return CoreNotice(
            symbol: "info.circle",
            title: on == 0
                ? "Auto-accept is off in every room. Nothing is filed until you accept it."
                : "Auto-accept is on in \(BrainWords.plural(on, "room", "rooms")). Everything else waits here."
        ) {
            Button("Set rules") { goToRules() }.buttonStyle(CoreButtonStyle(.plain, size: .small))
        }
    }
}

/// A quiet "All kinds" style filter: words and a chevron on a well, opening the glass dropdown.
private struct QuietFilter: View {
    let title: String
    let items: [CoreDropdownItem]
    @State private var hovering = false

    var body: some View {
        CoreDropdown(items: items) {
            HStack(spacing: Space.s1) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .accessibilityHidden(true)
            }
            .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            .padding(.leading, Space.s2 + 2).padding(.trailing, Space.s2).frame(minHeight: MacSize.controlSm)
            .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel(title)
    }
}

private struct CandidateRow: View {
    let model: BrainModel
    let c: InboxCandidate
    @State private var hovering = false
    private var state: BrainCandidates { model.candidates }

    var body: some View {
        let selected = state.selected?.id == c.id
        CoreRow(c.text, subtitle: subtitle, symbol: c.kind.symbol, selected: selected, action: { state.select(c.id) }) {
            ZStack(alignment: .trailing) {
                Text(c.date).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .opacity(hovering || selected ? 0 : 1)
                HStack(spacing: Space.s1) {
                    CoreIconButton(symbol: "xmark", label: "Reject") { Task { await state.reject(c.id) } }
                    CoreIconButton(symbol: "checkmark", label: "Accept") { Task { await state.accept(c.id) } }
                }
                .opacity(hovering || selected ? 1 : 0)
                .allowsHitTesting(hovering || selected)
            }
        }
        .lineLimit(1)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityIdentifier("candidate-\(c.id)")
    }

    private var subtitle: String {
        ([c.kind.label, c.roomName, c.app].filter { !$0.isEmpty } + (state.isEdited(c) ? ["Edited"] : []))
            .joined(separator: " · ")
    }
}

// MARK: detail

private struct SourceRows: View {
    let c: InboxCandidate
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text("Sources").coreFont(size: MacTextSize.headline, weight: .semibold)
                CountBadge(c.sources.count, tone: .quiet, label: "sources")
                Spacer(minLength: Space.s2)
                Text("Open one to read the original").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(c.sources) { s in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Image(systemName: "link").foregroundStyle(GlassInk.blueInk).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).coreFont(size: MacTextSize.body, weight: .medium).foregroundStyle(
                                GlassInk.blueInk)
                            if !s.quote.isEmpty {
                                Text(s.quote).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Space.s3)
                        Text(s.place).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .modifier(BrainRowHover())
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct DetailHead: View {
    let symbol: String
    let title: String
    let sub: String
    var body: some View {
        HStack(spacing: Space.s3) {
            IconTile(symbol, hue: GlassInk.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(sub).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
        }
    }
}

private struct ActionLabel: View {
    let title: String
    let key: String
    var body: some View {
        HStack(spacing: Space.s2) {
            Text(title)
            CoreKeycap(key)
        }
    }
}

private struct CandidateDetail: View {
    let model: BrainModel
    let c: InboxCandidate

    var body: some View {
        let state: BrainCandidates = model.candidates
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                DetailHead(
                    symbol: c.kind.symbol, title: c.kind.label,
                    sub: (["For \(c.roomName)"]
                        + [c.distilled.isEmpty ? "" : "distilled \(c.distilled)", c.account]
                        .filter { !$0.isEmpty }).joined(separator: " · "))
                Text(c.text).coreFont(size: MacTextSize.title, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                SourceRows(c: c)
                HStack(spacing: Space.s2) {
                    Button {
                        Task { await state.accept(c.id) }
                    } label: {
                        ActionLabel(title: "Accept", key: "↩")
                    }
                    .buttonStyle(CoreButtonStyle(.prominent))
                    Button {
                        state.startEdit(c.id)
                    } label: {
                        HStack(spacing: Space.s2) {
                            Image(systemName: "pencil")
                            ActionLabel(title: "Edit", key: "E")
                        }
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    Button {
                        Task { await state.reject(c.id) }
                    } label: {
                        ActionLabel(title: "Reject", key: "⌫")
                    }
                    .buttonStyle(CoreButtonStyle(.quietDanger))
                    Spacer(minLength: Space.s3)
                    Text("Accepting files it in \(c.roomName).").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
                .disabled(state.busy)
            }
            .padding(.horizontal, Space.s5).padding(.vertical, Space.s4)
        }
        .id(c.id)
        .accessibilityIdentifier("candidate-detail")
    }
}

private struct CandidateEditForm: View {
    let model: BrainModel
    let c: InboxCandidate
    @State private var text: String
    @State private var kind: CandidateKind
    @FocusState private var textFocus: Bool

    init(model: BrainModel, c: InboxCandidate) {
        self.model = model
        self.c = c
        let d = model.candidates.draft
        _text = State(initialValue: d?.text ?? c.text)
        _kind = State(initialValue: d?.kind ?? c.kind)
    }

    var body: some View {
        let state: BrainCandidates = model.candidates
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                DetailHead(
                    symbol: "pencil", title: "Edit candidate", sub: "Changes are yours; the sources stay attached.")
                Grid(alignment: .topLeading, horizontalSpacing: Space.s5, verticalSpacing: Space.s3) {
                    GridRow {
                        label("Kind")
                        CoreSelect(
                            nil, selection: $kind,
                            options: CandidateKind.allCases.map { CoreSelectOption($0, $0.label) }
                        )
                        .frame(maxWidth: Space.s8 * 7, alignment: .leading)
                    }
                    GridRow {
                        label("Room")
                        // A candidate cannot change room here: the Core files it where it was distilled.
                        CoreSelect(nil, selection: .constant(c.room), options: [CoreSelectOption(c.room, c.roomName)])
                            .disabled(true).frame(maxWidth: Space.s8 * 7, alignment: .leading)
                    }
                    GridRow(alignment: .top) {
                        label("Text")
                        VStack(alignment: .leading, spacing: Space.s1) {
                            CoreTextArea(
                                nil, placeholder: "One statement", text: $text, minHeight: Space.s8 * 3,
                                focus: $textFocus)
                            Text(
                                "One statement, in your words. It is shown in search and given to AI sessions that read this room."
                            )
                            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        }
                    }
                }
                SourceRows(c: c)
                HStack(spacing: Space.s2) {
                    Button {
                        Task { await state.saveEdit() }
                    } label: {
                        ActionLabel(title: "Save and accept", key: "⌘↩")
                    }
                    .buttonStyle(CoreButtonStyle(.prominent))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.busy)
                    .keyboardShortcut(.return, modifiers: .command)
                    Button("Cancel") { state.cancelEdit() }.buttonStyle(CoreButtonStyle(.plain))
                        .keyboardShortcut(.cancelAction)
                    Spacer(minLength: Space.s3)
                    Text("Esc cancels. Nothing is lost.").coreFont(size: MacTextSize.meta).foregroundStyle(
                        GlassInk.secondary)
                }
            }
            .padding(.horizontal, Space.s5).padding(.vertical, Space.s4)
        }
        .onChange(of: text) { _, t in model.candidates.setDraft(kind: kind, text: t) }
        .onChange(of: kind) { _, k in model.candidates.setDraft(kind: k, text: text) }
        .onAppear { textFocus = true }
        .accessibilityIdentifier("candidate-edit")
    }

    private func label(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.body, weight: .medium).frame(width: Space.s8 * 4.5, alignment: .leading)
            .padding(.top, Space.s2)
    }
}
