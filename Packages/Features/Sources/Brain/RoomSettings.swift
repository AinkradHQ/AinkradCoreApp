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
            } else {
                BrainSkeleton(shape: .list)
            }
        }
        .task(id: room.id) { await c.loadPolicy(room.id) }
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
            HStack(spacing: Space.s2) {
                Button("Choose a model") {
                    c.runnerHint()
                }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                Button("Use Cloud") { Task { await c.setModel(room.id, .cloud) } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
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

    @ViewBuilder private func cloud(_ p: RoomPolicy) -> some View {
        GridRow(alignment: .top) {
            label("Provider")
            field(
                CoreSelect(
                    nil, selection: .constant(p.provider), options: p.providers.map { CoreSelectOption($0, $0) }),
                "Only approved providers are listed.")
        }
        if !p.accounts.isEmpty {
            GridRow(alignment: .top) {
                label("Account")
                field(
                    CoreSelect(
                        nil, selection: .constant(p.account), options: p.accounts.map { CoreSelectOption($0, $0) }),
                    "The whole chain, runner to account, is checked before every run.")
            }
        }
    }

    @ViewBuilder private func local(_ p: RoomPolicy) -> some View {
        let none = p.localModels.isEmpty
        GridRow(alignment: .top) {
            label("Local model")
            field(
                CoreSelect(
                    nil,
                    selection: Binding(
                        get: { p.localModel ?? "" }, set: { n in Task { await c.setLocalModel(room.id, n) } }),
                    options: none
                        ? [CoreSelectOption("", "None available yet")] : p.localModels.map { CoreSelectOption($0, $0) }
                )
                .disabled(none),
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
                    ? "These kinds go straight into the room. You can undo them from the Inbox for 14 days."
                    : "Everything waits in the Inbox until you accept it.",
                dim: false
            ) {
                CoreSwitch(
                    "",
                    isOn: Binding(get: { p.autoAccept }, set: { on in Task { await c.setAutoAccept(room.id, on) } }))
            }
            ForEach(CandidateKind.allCases, id: \.self) { k in
                row(k.plural, k.about, dim: !p.autoAccept || !p.autoKindsAllowed.contains(k), inline: true) {
                    CoreCheckbox(
                        "",
                        isOn: Binding(
                            get: { p.kinds.contains(k) }, set: { _ in Task { await c.toggleKind(room.id, k) } }),
                        spoken: k.plural)
                }
                .disabled(!p.autoAccept || !p.autoKindsAllowed.contains(k))
            }
            row("Only with at least", nil, dim: !p.autoAccept || !p.minSourcesServed, inline: true) {
                CoreSelect(
                    nil,
                    selection: Binding(get: { p.minSources }, set: { n in Task { await c.setMinSources(room.id, n) } }),
                    options: (1...3).map { CoreSelectOption($0, BrainWords.plural($0, "source", "sources")) }
                )
                .frame(width: Space.s8 * 4)
                .disabled(!p.autoAccept || !p.minSourcesServed)
            }
        }
    }

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
