import CoreUI
import Shell
import SwiftUI

/// The Brain's dialogs, shown over the shell like Devices and Accounts.
@MainActor
enum BrainSheets {
    static func openNewRoom(_ m: BrainModel) {
        m.host.clearElevationNotice()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "brain-new-room", onClose: { [weak m] in m?.host.clearElevationNotice() }) {
                NewRoomSheet(model: m) { shell.closeDialog() }
            })
    }
}

/// New room (advanced): a name, what kind of room, where it lives, and a live "what you get". The plain New room action
/// makes a room at once with the defaults (this Mac only, local models); this sheet is for choosing.
struct NewRoomSheet: View {
    let model: BrainModel
    let close: () -> Void
    @State private var name = ""
    @State private var kind: RoomKind = .product
    @State private var mode: StorageMode = .localOnly
    @State private var busy = false

    private static let kinds: [(RoomKind, String, String)] = [
        (.product, "Product", "Your own project"), (.personal, "Personal", "Life and identity"),
        (.employer, "Employer", "Local models until approved"), (.client, "Client", "Local models until approved"),
    ]

    private var typed: String { name.trimmingCharacters(in: .whitespaces) }
    private var taken: Bool { model.rooms.contains { $0.name.lowercased() == typed.lowercased() } }

    var body: some View {
        CoreDialogPanel("New room (advanced)", width: Space.s8 * 17) {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField(
                    "Name", placeholder: "For example, Side project", text: $name,
                    error: taken ? "A room with this name exists." : nil, autofocus: true
                ) { go() }
                CoreFieldLabel("Kind")
                HStack(spacing: Space.s2) {
                    ForEach(Self.kinds, id: \.0) { k in
                        ChoiceTile(title: k.1, sub: k.2, on: kind == k.0) { kind = k.0 }
                    }
                }
                CoreFieldLabel("Where it lives")
                HStack(spacing: Space.s2) {
                    ForEach(StorageMode.allCases, id: \.self) { m in
                        ChoiceTile(title: m.label, sub: m.plain, on: mode == m) { mode = m }
                    }
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("What you get").font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(preview).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
                if mode.widens {
                    Text("Touch ID is asked first, because this room will leave this Mac.")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
                if let n = model.host.elevationNotice {
                    CoreNotice(symbol: n.symbol, title: n.title, text: n.detail, tone: n.warn ? .warn : .queue)
                }
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction("Create room", key: .primary) { go() }, busy: busy,
                    enabled: !(typed.isEmpty || taken))
            }
        }
        .accessibilityIdentifier("brain-new-room")
    }

    /// The live summary of the choice, in plain words.
    private var preview: String {
        let who = kind.chipLabel.map { "\($0) room. " } ?? ""
        return
            "\(who)Your room will be sealed apart from every other room. \(mode.story) Only models on this Mac read it until you approve a cloud model."
    }

    private func go() {
        guard !typed.isEmpty, !taken else { return }
        busy = true
        Task {
            let ok = await model.createRoom(NewRoomDraft(name: typed, kind: kind, mode: mode))
            busy = false
            if ok { close() }
        }
    }
}

/// A choice as a rounded tile with a title and one plain line. Solid blue selection, no ring.
private struct ChoiceTile: View {
    let title: String
    let sub: String
    let on: Bool
    let pick: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 2, alignment: .topLeading)
            .background(
                on ? GlassInk.blue.opacity(0.32) : hovering ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.cardMac)
            )
            .overlay { if on { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.7), lineWidth: 1) } }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.hover), value: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
