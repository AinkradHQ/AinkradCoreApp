import CoreUI
import SwiftUI

/// Inbox: what waits for you in the viewing room (memories, conflicts, blocked notes) and, as its own list, the captures
/// that have no room yet. One room at a time: switching rooms clears the old lists before the new ones load.
struct InboxTab: View {
    let model: BrainModel
    private var st: InboxState { model.inboxState }

    private struct LoadKey: Hashable {
        let room: String?
        let fresh: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            strip
            if let p = model.movePause { InboxNote("shield", GlassInk.red, "Paused", p) }
            HStack(alignment: .center, spacing: Space.s3) {
                BrainTitle("Inbox")
                Spacer(minLength: Space.s3)
                HStack(spacing: Space.s2) {
                    ForEach(Array(InboxList.allCases.enumerated()), id: \.offset) { i, l in
                        let n = st.count(l)
                        AppFilterTile(title: l.title, count: n > 0 ? n : -1, on: st.list == l, key: "⌥\(i + 1)") {
                            withAnimation(.smooth(duration: 0.25)) { st.list = l }
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .option)
                        .accessibilityIdentifier("inbox-list-\(l.rawValue)")
                    }
                }
            }
            if st.queued > 0 {
                InboxNote(
                    "wifi.slash", GlassInk.slate,
                    "\(BrainWords.plural(st.queued, "change", "changes")) made here wait to sync.")
            }
            content
            if !st.done.isEmpty { DoneList(items: st.done) }
        }
        .task(id: LoadKey(room: model.viewingID, fresh: st.phase == .idle)) {
            if st.phase == .idle { await model.loadInbox() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-inbox")
    }

    /// Which room this is, always. The no-room list says it is not a room.
    @ViewBuilder private var strip: some View {
        HStack(spacing: Space.s2) {
            if st.list == .noRoom {
                Text("No room yet").coreFont(size: MacTextSize.headline, weight: .semibold)
                BrainChip("Not a room", GlassInk.slate, help: "The unclassified inbox is a sealed pseudo-room.")
                BrainChip("Never searched", GlassInk.slate)
                BrainChip("AI sessions never see it", GlassInk.slate)
                Spacer(minLength: Space.s2)
                Text("This Mac and iPhone only").coreFont(size: MacTextSize.meta).foregroundStyle(
                    GlassInk.secondary)
            } else if let r = model.viewing {
                Text(r.name).coreFont(size: MacTextSize.headline, weight: .semibold).help(r.help)
                RoomChips(room: r)
                Spacer(minLength: Space.s2)
                Text(r.mounted ? "Shows only this room" : "Name and mode only")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch st.phase {
        case .idle, .loading:
            BrainSkeleton(shape: .list)
        case .failed(let why):
            BrainStateCard(
                symbol: "exclamationmark.triangle", title: "Could not read the Inbox", text: why,
                primary: CoreAction("Try again") { model.retryInbox() }
            )
            .accessibilityIdentifier("inbox-error")
        case .refused(let why):
            BrainStateCard(symbol: "shield", title: "Refused by a room rule", text: why)
                .accessibilityIdentifier("inbox-refused")
        case .ready:
            if st.list == .noRoom {
                NoRoomList(model: model)
            } else if model.viewing == nil {
                BrainStateCard(
                    symbol: "lock", title: "Pick a room first",
                    text:
                        "Waiting memories, conflicts and blocked notes belong to one room. Choose a room in the picker above."
                )
            } else if let lock = model.viewingLock, let r = model.viewing {
                BrainStateCard(
                    symbol: "lock", title: "This room is sealed",
                    text: lock.sentence
                        + " Its memories, conflicts and blocked notes stay hidden. No AI session, cloud runner or search can read it.",
                    primary: CoreAction("Open this room with Touch ID") { Task { await model.open(r.id) } }
                )
                .accessibilityIdentifier("inbox-sealed")
            } else {
                roomList
            }
        }
    }

    @ViewBuilder private var roomList: some View {
        switch st.list {
        case .waiting:
            if let d = st.data, !d.waiting.isEmpty {
                WaitingList(model: model, items: d.waiting)
            } else {
                empty(
                    "Nothing waits for you",
                    "AI sessions propose memories here. When one does, you approve, edit or reject it, and nothing is used until you do."
                )
            }
        case .conflicts:
            if let d = st.data, !d.conflicts.isEmpty {
                VStack(spacing: Space.s3) {
                    ForEach(d.conflicts) { c in
                        ConflictCard(model: model, c: c) { choice in Task { await model.keep(c.id, choice) } }
                    }
                }
            } else {
                empty(
                    "No conflicts in this room",
                    "When two memories in this room disagree, you see them side by side here.")
            }
            InboxNote(
                "info.circle", GlassInk.slate, "Two rooms that disagree are not a conflict",
                "Only disagreements inside this room show here.")
        case .blocked:
            if let d = st.data, !d.blocked.isEmpty {
                VStack(spacing: Space.s3) {
                    ForEach(d.blocked) { b in
                        BlockedCard(model: model, b: b, redact: { Task { await model.redact(b.id) } }) {
                            BrainSheets.confirmDiscard(model, b.id)
                        }
                    }
                }
            } else {
                empty(
                    "No blocked notes",
                    "A note that holds a secret or breaks a room rule is stopped here, with the rule that stopped it.")
            }
        case .noRoom: EmptyView()
        }
    }

    /// An empty list says what it is for and gives one next step.
    func empty(_ title: String, _ text: String) -> some View {
        BrainStateCard(
            symbol: "tray", title: title, text: text,
            secondary: CoreAction("Back to Overview") { withAnimation { model.tab = .overview } }
        )
        .accessibilityIdentifier("inbox-empty")
    }
}

/// Waiting memories as cards with arrow-key navigation.
private struct WaitingList: View {
    let model: BrainModel
    let items: [Candidate]
    @FocusState private var focus: String?

    var body: some View {
        VStack(spacing: Space.s3) {
            ForEach(items) { c in
                CandidateCard(
                    model: model, c: c, approve: { act(c) { await BrainSheets.approve(model, c.id) } },
                    reject: { act(c) { _ = await model.reject(c.id) } }, edit: { BrainSheets.edit(model, c.id) },
                    advanced: { BrainSheets.approveAdvanced(model, c.id) }
                )
                .focusable().focused($focus, equals: c.id).focusEffectDisabled()
                .onTapGesture { focus = c.id }
                .onKeyPress(phases: .down) { key(c, $0) }
            }
        }
        .onAppear { if focus == nil { focus = items.first?.id } }
    }

    private func key(_ c: Candidate, _ p: KeyPress) -> KeyPress.Result {
        guard let i = items.firstIndex(of: c), model.busy == nil else { return .ignored }
        if p.modifiers == .command, p.key == .return {
            act(c) { await BrainSheets.approve(model, c.id) }
            return .handled
        }
        if p.modifiers == .command, p.key == .delete {
            act(c) { _ = await model.reject(c.id) }
            return .handled
        }
        if p.modifiers.isEmpty, p.characters == "e" {
            BrainSheets.edit(model, c.id)
            return .handled
        }
        if p.modifiers.isEmpty, p.key == .downArrow || p.key == .upArrow {
            let j = i + (p.key == .downArrow ? 1 : -1)
            if items.indices.contains(j) { focus = items[j].id }
            return .handled
        }
        return .ignored
    }

    /// Runs the action, then puts focus on the card that took its place.
    private func act(_ c: Candidate, _ run: @escaping () async -> Void) {
        let i = items.firstIndex(of: c) ?? 0
        Task {
            await run()
            let left = model.inboxState.data?.waiting ?? []
            focus = left.isEmpty ? nil : left[min(i, left.count - 1)].id
        }
    }
}

/// What you settled this session, kept quiet under the lists.
private struct DoneList: View {
    let items: [InboxState.Done]
    @State private var open = false
    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(items) { d in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        BrainChip(d.kind, d.tone == .fail ? GlassInk.red : GlassInk.green)
                        Text(d.text).foregroundStyle(GlassInk.secondary)
                    }
                }
            }
            .padding(.top, Space.s2)
        } label: {
            Text("Done this session \(items.count)").coreFont(size: MacTextSize.headline, weight: .semibold)
        }
        .padding(Space.s3).coreWell()
        .accessibilityIdentifier("inbox-done")
    }
}
