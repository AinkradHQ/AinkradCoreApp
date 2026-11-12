import CoreUI
import Shell
import SwiftUI

/// The Inbox's dialogs, shown over the shell like the rest of the Brain's. Each one names its task, Cancel sits left, the
/// action right, and Esc cancels. A cancelled Touch ID (asked by the model) leaves everything as it was.
@MainActor
extension BrainSheets {
    private static func show(_ m: BrainModel, _ id: String, @ViewBuilder _ content: @escaping () -> some View) {
        m.host.clearElevationNotice()
        m.host.shell.present(
            ShellDialog(id: id, onClose: { [weak m] in m?.host.clearElevationNotice() }, content: content))
    }

    /// Approves with the room defaults. A note that reads like an instruction asks first.
    static func approve(_ m: BrainModel, _ id: String) async {
        if await m.approve(id) == .needsConfirm, let c = m.candidate(id) {
            show(m, "inbox-instruction") {
                InboxConfirm(
                    title: "Approve a note that reads like an instruction?",
                    text:
                        "\(c.flag ?? "") If you approve, it is kept as a quoted memory. It is still never run or followed as an instruction.",
                    action: "Approve as quoted text", model: m
                ) { _ = await m.approve(id, confirmed: true) }
            }
        }
    }

    static func edit(_ m: BrainModel, _ id: String) {
        guard let c = m.candidate(id) else { return }
        show(m, "inbox-edit") { EditSheet(model: m, c: c) }
    }

    static func approveAdvanced(_ m: BrainModel, _ id: String) {
        guard let c = m.candidate(id) else { return }
        show(m, "inbox-approve-advanced") { AdvancedApproveSheet(model: m, c: c) }
    }

    static func confirmDiscard(_ m: BrainModel, _ id: String) {
        show(m, "inbox-discard") {
            InboxConfirm(
                title: "Discard this blocked note?",
                text:
                    "The note and the blocked secret are wiped from this Mac. This cannot be undone. Touch ID asks next.",
                action: "Discard…", danger: true, model: m
            ) { _ = await m.discard(id) }
        }
    }

    static func confirmDelete(_ m: BrainModel, _ ids: [String]) {
        show(m, "inbox-delete") {
            InboxConfirm(
                title: ids.count == 1
                    ? "Delete this capture after review?" : "Delete \(ids.count) captures after review?",
                text:
                    "The raw \(ids.count == 1 ? "capture is" : "captures are") wiped from this Mac. Nothing is deleted without this step. Touch ID asks next.",
                action: "Delete…", danger: true, model: m
            ) { _ = await m.deleteCaptures(ids) }
        }
    }

    static func assign(_ m: BrainModel, _ ids: [String]) { show(m, "inbox-assign") { AssignSheet(model: m, ids: ids) } }
    static func split(_ m: BrainModel, _ id: String) { show(m, "inbox-split") { SplitSheet(model: m, id: id) } }
}

/// Cancel left, one named action right (⌘↩, so Return alone never approves).
private struct SheetButtons: View {
    let model: BrainModel
    let action: String
    var danger = false
    var enabled = true
    var busy = false
    let go: () -> Void
    var body: some View {
        CoreDialogFooter(
            cancel: CoreAction("Cancel", key: .cancel) { model.host.shell.closeDialog() },
            primary: CoreAction(action, key: .command, run: go), danger: danger, busy: busy, enabled: enabled)
    }
}

/// A plain confirm: a sentence and the action. The action's own Touch ID comes from the model.
private struct InboxConfirm: View {
    let title: String
    let text: String
    let action: String
    var danger = false
    let model: BrainModel
    let run: () async -> Void
    @State private var busy = false
    var body: some View {
        CoreDialogPanel(title, width: Space.s8 * 14) {
            Text(text).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            SheetButtons(model: model, action: action, danger: danger, busy: busy) {
                busy = true
                Task {
                    model.host.shell.closeDialog()
                    await run()
                }
            }
        }
        .accessibilityIdentifier("inbox-confirm")
    }
}

/// Edit before approving: the title and text, then approve with your edit.
private struct EditSheet: View {
    let model: BrainModel
    let c: Candidate
    @State private var title: String
    @State private var text: String
    @State private var busy = false
    init(model: BrainModel, c: Candidate) {
        self.model = model
        self.c = c
        _title = State(initialValue: c.title)
        _text = State(initialValue: c.text)
    }
    private var empty: Bool { title.trimmingCharacters(in: .whitespaces).isEmpty }
    var body: some View {
        CoreDialogPanel("Edit before approving", width: Space.s8 * 17) {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField(
                    "Title", placeholder: "A short title", text: $title, error: empty ? "Give it a title." : nil,
                    autofocus: true)
                CoreTextArea("Text", placeholder: "What the memory says", text: $text)
                if c.flag != nil {
                    InboxNote(
                        "exclamationmark.triangle", GlassInk.red,
                        "This reads like an instruction. It stays quoted text and agents never run it.")
                }
                SheetButtons(model: model, action: "Save and approve", enabled: !empty, busy: busy) {
                    busy = true
                    Task {
                        let o = await model.approve(
                            c.id, edit: CandidateEdit(title: title, text: text), confirmed: true)
                        busy = false
                        if o == .done { model.host.shell.closeDialog() }
                    }
                }
            }
        }
        .accessibilityIdentifier("inbox-edit")
    }
}

/// Approve with options: who it applies to, who said so, when it ends, when to review.
private struct AdvancedApproveSheet: View {
    let model: BrainModel
    let c: Candidate
    @State private var o = ApproveOptions()
    @State private var busy = false
    private static let said: [Authority] = [.projectOwner, .userExplicit, .teamMember, .imported]
    private func pick(_ v: [String]) -> [CoreSelectOption<String>] { v.map { CoreSelectOption($0, $0) } }
    var body: some View {
        CoreDialogPanel("Approve with options", width: Space.s8 * 17) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Approve this memory with settings you choose. The plain Approve uses the room defaults.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreSelect("Applies to", selection: $o.appliesTo, options: pick(ApproveOptions.appliesChoices))
                    CoreSelect(
                        "Who said so", selection: $o.whoSaidSo,
                        options: Self.said.map { CoreSelectOption($0, $0.label) })
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreSelect("Valid until", selection: $o.validUntil, options: pick(ApproveOptions.untilChoices))
                    CoreSelect("Review again", selection: $o.reviewAgain, options: pick(ApproveOptions.reviewChoices))
                }
                SheetButtons(model: model, action: "Approve", busy: busy) {
                    busy = true
                    Task {
                        var out = await model.approve(c.id, options: o)
                        if out == .needsConfirm { out = await model.approve(c.id, options: o, confirmed: true) }
                        busy = false
                        if out == .done { model.host.shell.closeDialog() }
                    }
                }
            }
        }
        .accessibilityIdentifier("inbox-approve-advanced")
    }
}

/// Assign: source room, target room, Move or Copy, and what happens, before anything moves.
private struct AssignSheet: View {
    let model: BrainModel
    let ids: [String]
    @State private var target = ""
    @State private var mode: MoveMode = .move
    @State private var busy = false

    private var rooms: [RoomSummary] { model.mountedRooms.filter { $0.lock == nil } }
    private var room: RoomSummary? { model.room(target) }
    private var items: [Capture] { ids.compactMap { model.capture($0) } }

    var body: some View {
        CoreDialogPanel(ids.count == 1 ? "Assign to a room" : "Assign \(ids.count) captures", width: Space.s8 * 17) {
            VStack(alignment: .leading, spacing: Space.s3) {
                fromTo
                Text(ids.count == 1 ? (items.first?.source ?? "") : "\(ids.count) captures").foregroundStyle(
                    GlassInk.secondary)
                CoreSelect(
                    "Room", selection: $target,
                    options: rooms.map { CoreSelectOption($0.id, "\($0.name), \($0.mode.label.lowercased())") })
                VStack(spacing: Space.s2) {
                    option(.move, "Move", "The capture leaves the inbox and becomes a waiting memory in the room.")
                    option(.copy, "Copy", "A copy goes to the room and the original stays here for you to review.")
                    HStack(alignment: .top, spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Link").coreFont(size: MacTextSize.headline, weight: .semibold)
                            Text("Not available. A link would keep a door open into the inbox.")
                                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.s3).opacity(0.5).help(
                        "The inbox is only entered by capture, so a link into it is not allowed.")
                }
                if let p = model.movePause { InboxNote("shield", GlassInk.red, Text("Paused. ").bold() + Text(p)) }
                if let r = room { effect(r) }
                SheetButtons(
                    model: model, action: "Assign", enabled: room != nil && model.movePause == nil, busy: busy
                ) {
                    busy = true
                    Task {
                        let o = await model.assign(ids, to: target, mode: mode)
                        busy = false
                        if o == .done { model.host.shell.closeDialog() }
                    }
                }
            }
        }
        .onAppear {
            // A local model's guess, only when it exists, is the starting point. Advice, not action.
            let guess = items.first?.guess.flatMap { g in rooms.first { $0.name == g }?.id }
            target = guess ?? rooms.first?.id ?? ""
        }
        .accessibilityIdentifier("inbox-assign")
    }

    private var fromTo: some View {
        HStack(spacing: Space.s3) {
            endpoint("From", "No room yet", "Unclassified inbox")
            Image(systemName: "arrow.right").flipsForRightToLeftLayoutDirection(true).foregroundStyle(
                GlassInk.secondary
            ).accessibilityHidden(true)
            endpoint(
                "To", room?.name ?? "Choose a room",
                room.map { "\($0.mode.label), \($0.provider.label.lowercased())" } ?? "")
        }
    }

    private func endpoint(_ cap: String, _ name: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cap).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            Text(name).coreFont(size: MacTextSize.headline, weight: .semibold)
            Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityElement(children: .combine)
    }

    private func option(_ m: MoveMode, _ title: String, _ sub: String) -> some View {
        Button {
            mode = m
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(mode == m ? GlassInk.blue.opacity(0.32) : GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay {
                if mode == m { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.7), lineWidth: 1) }
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    /// The consequence, in plain words, for the chosen room.
    private func effect(_ r: RoomSummary) -> some View {
        let wide = model.widens(r)
        let line =
            (mode == .copy
                ? "The original stays in the inbox, still unsearchable." : "The raw capture leaves the inbox.")
            + " In \(r.name) it waits for your approval and follows that room's rules."
            + (r.provider == .local ? " Only local models read it, no cloud agent." : "")
            + (r.kind.chipLabel.map { " This is an \($0.lowercased()) room: the stricter room rule applies." } ?? "")
            + " Undo later removes it from the room and flags it for review."
        return InboxNote(
            wide ? "touchid" : "info.circle", wide ? GlassInk.orange : GlassInk.slate,
            Text("What happens. ").bold() + Text(line)
                + Text(wide ? " This room can reach cloud agents, so " : "") + Text(wide ? "Touch ID asks" : "").bold()
                + Text(wide ? " before it goes in." : ""))
    }
}

/// Split: a mixed capture becomes two parts, each in its own room.
private struct SplitSheet: View {
    let model: BrainModel
    let id: String
    @State private var one = ""
    @State private var two = ""
    @State private var busy = false
    private var rooms: [RoomSummary] { model.mountedRooms.filter { $0.lock == nil } }
    var body: some View {
        CoreDialogPanel("Split and assign", width: Space.s8 * 17) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    "\(model.capture(id)?.source ?? "This capture") holds two topics. Give each part its own room. Each part follows that room's rules."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Space.s3) {
                    part("Part 1", $one)
                    part("Part 2", $two)
                }
                InboxNote(
                    "info.circle", GlassInk.slate,
                    "Both parts wait for your approval in their rooms. Touch ID asks if a room can reach cloud agents.")
                SheetButtons(
                    model: model, action: "Split", enabled: !one.isEmpty && !two.isEmpty && model.movePause == nil,
                    busy: busy
                ) {
                    busy = true
                    Task {
                        let o = await model.split(id, into: [one, two])
                        busy = false
                        if o == .done { model.host.shell.closeDialog() }
                    }
                }
            }
        }
        .onAppear {
            one = rooms.first?.id ?? ""
            two = rooms.dropFirst().first?.id ?? one
        }
        .accessibilityIdentifier("inbox-split")
    }
    private func part(_ title: String, _ sel: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
            CoreSelect(nil, selection: sel, options: rooms.map { CoreSelectOption($0.id, $0.name) })
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
