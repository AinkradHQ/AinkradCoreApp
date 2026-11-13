import CoreUI
import SwiftUI

/// A room's Settings half: which models may read it, and what it files without a review. Every change asks for Touch ID
/// (the model asks); until the Core answers, the controls show what the Core has.
struct RoomSettings: View {
    let model: BrainModel
    let room: RoomSummary
    private var c: BrainCandidates { model.candidates }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if let p = c.policy(room.id) {
                if p.needsLocalModel { queue(p) }
                policy(p)
                auto(p)
                RoomAISessions(c: c, room: room)
            } else {
                BrainSkeleton(shape: .list)
            }
        }
        .task(id: room.id) {
            await c.loadPolicy(room.id)
            await c.loadAccess(room.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-settings")
    }

    private func head(_ title: String, _ note: String) -> some View {
        HStack {
            Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s3)
            Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, 2)
    }

    private func hint(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.body, weight: .medium).frame(width: Space.s8 * 4.5, alignment: .leading)
            .padding(.top, Space.s2)
    }

    // MARK: queue

    private func queue(_ p: RoomPolicy) -> some View {
        CoreNotice(
            symbol: "icloud.slash", title: "Needs a local model",
            text:
                "\(BrainWords.plural(p.queued, "item is", "items are")) queued. This room is local only and no runner "
                + "has a local model yet. They are distilled as soon as one is ready.",
            tone: .warn
        ) {
            Button("Use Cloud") { Task { await c.setModel(room.id, .cloud) } }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
        }
        .accessibilityIdentifier("room-queued")
    }

    // MARK: model policy

    private func policy(_ p: RoomPolicy) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            head("Model policy", "Changing it asks for Touch ID")
            HStack(spacing: Space.s3) {
                CoreSegmented(
                    "Model policy",
                    segments: [
                        CoreSegment(ModelPolicy.cloud, "Cloud", symbol: "cloud"),
                        CoreSegment(.localOnly, "Local only", symbol: "cpu"),
                    ],
                    selection: Binding(get: { p.model }, set: { m in Task { await c.setModel(room.id, m) } }))
                hint(
                    p.model == .localOnly
                        ? "Text from this room never leaves your devices."
                        : "Distilling may send text to the provider below.")
            }
            .padding(.horizontal, 2)
            Grid(alignment: .topLeading, horizontalSpacing: Space.s5, verticalSpacing: Space.s2) {
                if p.model == .localOnly { local(p) } else { cloud(p) }
            }
            .padding(.horizontal, 2)
        }
    }

    /// What the Core says, on the field surface without the chevrons: it is shown, not chosen here.
    private func shown(_ text: String, dim: Bool = false) -> some View {
        Text(text).coreFont(size: MacTextSize.body).foregroundStyle(dim ? GlassInk.secondary : GlassInk.primary)
            .lineLimit(1).padding(.horizontal, Space.s3)
            .frame(maxWidth: .infinity, minHeight: MacSize.controlLg, alignment: .leading)
            .coreFieldSurface(focused: false)
    }

    @ViewBuilder private func cloud(_ p: RoomPolicy) -> some View {
        GridRow(alignment: .top) {
            label("Provider")
            field(shown(p.provider), "Only approved providers are listed.")
        }
        GridRow(alignment: .top) {
            label("Account")
            field(
                shown(
                    p.accounts.isEmpty ? "None set up yet" : p.accounts.joined(separator: ", "), dim: p.accounts.isEmpty
                ),
                "The whole chain, runner to account, is checked before every run.")
        }
    }

    @ViewBuilder private func local(_ p: RoomPolicy) -> some View {
        let none = p.localModels.isEmpty
        GridRow(alignment: .top) {
            label("Local model")
            field(
                shown(none ? "None available yet" : p.localModels.joined(separator: ", "), dim: none),
                none
                    ? "A runner with a local model appears here. No cloud account is ever used for this room."
                    : "Run by a runner on your devices. No cloud account is ever used for this room.")
        }
    }

    private func field(_ select: some View, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            select
            hint(note)
        }
        .frame(maxWidth: Space.s8 * 11, alignment: .leading)
    }

    // MARK: auto-accept

    private func auto(_ p: RoomPolicy) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            head("Auto-accept", "Off by default")
            row(
                "Accept candidates automatically",
                p.autoAccept
                    ? "These kinds go straight into the room."
                    : "Everything waits in the Inbox until you accept it.",
                dim: false
            ) {
                CoreSwitch(
                    "",
                    isOn: Binding(get: { p.autoAccept }, set: { on in Task { await c.setAutoAccept(room.id, on) } }))
            }
            ForEach(CandidateKind.autoRows, id: \.self) { k in
                row(k.plural, Self.autoAbout(k), dim: !p.autoAccept, inline: true) {
                    CoreCheckbox(
                        "",
                        isOn: Binding(
                            get: { p.kinds.contains(k) }, set: { _ in Task { await c.toggleKind(room.id, k) } }),
                        spoken: k.plural)
                }
                .disabled(!p.autoAccept)
            }
            row("Only with at least", nil, dim: !p.autoAccept, inline: true) {
                CoreSelect(
                    nil,
                    selection: Binding(get: { p.minSources }, set: { n in Task { await c.setMinSources(room.id, n) } }),
                    options: Self.minChoices(p.minSources).map {
                        CoreSelectOption($0, BrainWords.plural($0, "source", "sources"))
                    }
                )
                .frame(width: Space.s8 * 4)
                .disabled(!p.autoAccept)
            }
        }
    }

    /// Auto-accept filters by type, so the two tagged kinds say how wide they are.
    private static func autoAbout(_ k: CandidateKind) -> String {
        switch k {
        case .landmine: "A trap to avoid. Takes every rule"
        case .openThread: "A question still open. Takes every task"
        default: k.about
        }
    }

    private static func minChoices(_ current: Int) -> [Int] { Set([1, 2, 3, 5, 10, current]).sorted() }

    private func row<T: View>(
        _ title: String, _ sub: String?, dim: Bool, inline: Bool = false, @ViewBuilder trailing: () -> T
    )
        -> some View
    {
        HStack(spacing: Space.s3) {
            if inline {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                    if let sub { Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary) }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                    if let sub { Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary) }
                }
            }
            Spacer(minLength: Space.s3)
            trailing()
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s1)
        .frame(minHeight: Space.s8 + Space.s1)
        .opacity(dim ? 0.45 : 1)
        .modifier(BrainRowHover(enabled: !dim))
        .accessibilityElement(children: .contain)
    }
}
