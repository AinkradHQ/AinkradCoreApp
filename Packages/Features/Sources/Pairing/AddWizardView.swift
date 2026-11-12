import AppKit
import CoreUI
import Shell
import SwiftUI

/// Add a device or a runner (n17): What → Install → Connect → Access (a device) or Settings (a runner) → Done, one screen
/// each. The step bar always shows the six names, so a person sees the whole way; the steps a kind skips stay unlit.
struct AddWizardView: View {
    let app: AppModel
    @Bindable var model: AddWizardModel
    let close: () -> Void
    @Environment(\.corePalette) var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    static let stepNames = ["What", "Install", "Connect", "Access", "Settings", "Done"]

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 21) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if model.kind != .phone || model.step == .what {
                    CoreStepper(Self.stepNames, at: model.step.rawValue)
                }
                Group {
                    switch model.step {
                    case .what: what
                    case .install: install
                    case .connect: connect
                    case .access: access
                    case .settings: settings
                    case .done: done
                    }
                }
                .transition(reduce ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                StepUpBanner(app: app)
                footer
            }
            .animation(reduce ? .easeOut(duration: Motion.hover) : Motion.out(Motion.ui), value: model.step)
        }
        .background(WindowSharingGuard())
        .accessibilityIdentifier("add-wizard")
    }

    // The mockup's header: the step's title, one quiet line, and Close. No icon tile (ModalHeader always draws one).
    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AddWizardWords.title(model)).coreFont(size: MacTextSize.large, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(AddWizardWords.sub(model)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            CoreIconButton(symbol: "xmark", label: "Close", action: attemptClose)
        }
    }

    // MARK: pieces

    /// A plain well inside the framed dialog (inner cards carry no rim).
    func well<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) { c() }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.uDim, in: coreShape(Radius.cardMac))
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: 1 what

    private var what: some View {
        Grid(horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
            ForEach([0, 2], id: \.self) { row in
                GridRow {
                    ForEach(Array(AddKind.allCases[row..<row + 2]), id: \.self) { k in
                        Button {
                            model.choose(k)
                        } label: {
                            VStack(alignment: .leading, spacing: Space.s2) {
                                IconTile(k.symbol, hue: k.isRunner ? GlassInk.slate : GlassInk.blue, size: 48)
                                Text(k.title).coreFont(size: MacTextSize.body, weight: .semibold).padding(
                                    .top, Space.s1)
                                Text(k.blurb).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(Space.s4)
                            .frame(maxWidth: .infinity, minHeight: Space.s8 * 4 + Space.s6, alignment: .topLeading)
                        }
                        .buttonStyle(ChoiceCardStyle(selected: model.kind == k))
                        .accessibilityAddTraits(model.kind == k ? .isSelected : [])
                        .accessibilityIdentifier("add-kind-\(k)")
                    }
                }
            }
        }
    }

    // MARK: 4 access

    private var access: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(spacing: Space.s2) {
                ForEach(AccessPreset.choices, id: \.self) { p in
                    RadioRow(p.title, subtitle: p.blurb, symbol: p.symbol, selected: model.preset == p) {
                        model.pick(p)
                    }
                }
            }
            if model.preset == .full, model.onlyOneAdmin {
                CoreNotice(
                    symbol: "bell",
                    title:
                        "Recommended: you have only one admin device. A second one with Full control is a good backup.",
                    tone: .warn)
            }
            if !model.dropped.isEmpty {
                CoreNotice(
                    symbol: "exclamationmark.triangle",
                    title: "This Mac does not hold \(model.dropped.joined(separator: ", ")), so it cannot hand it on.",
                    tone: .warn)
            }
            if let e = model.accessError {
                CoreNotice(symbol: "exclamationmark.triangle", title: e, tone: .fail)
            }
            DisclosureGroup("Advanced · \(ScopeText.all.count) separate switches") {
                Grid(horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
                    ForEach(Array(stride(from: 0, to: ScopeText.all.count, by: 2)), id: \.self) { i in
                        GridRow {
                            ForEach(i..<min(i + 2, ScopeText.all.count), id: \.self) { j in scopeToggle(j) }
                        }
                    }
                }
                .padding(.top, Space.s2)
            }
            .foregroundStyle(palette.text2)
        }
    }

    private func scopeToggle(_ i: Int) -> some View {
        let s = ScopeText.all[i]
        return ScopeToggle(
            scope: s,
            on: Binding(get: { model.scopes.contains(s) }, set: { model.setScope(s, $0) }),
            locked: model.held.isEmpty || model.held.contains(s)
                ? nil : "This Mac does not hold it, so it cannot hand it on.", index: i)
    }

    // MARK: 6 done

    private var done: some View {
        let d = model.connected
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile(model.kind?.symbol ?? "checkmark", hue: GlassInk.blue, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(d?.name ?? model.name).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(AddWizardWords.summary(model, d)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
                if d != nil {
                    StateBadge("Online", tone: .done, symbol: "checkmark")
                } else {
                    StateBadge("Not listed yet", tone: .queue, symbol: "clock")
                        .help("The Core does not list it under this name yet. Check Devices in a moment.")
                }
            }
            .padding(Space.s3).background(palette.uDim, in: coreShape(Radius.cardMac))
            if model.kind?.isRunner == true, d != nil {
                HStack(spacing: Space.s3) {
                    Button {
                        Task { await model.test() }
                    } label: {
                        Label("Test it", systemImage: "bolt")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, busy: model.testing))
                    Text(model.testLine ?? "Sends a small test job and shows how fast it answers.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
            }
        }
        .task { await model.findConnected() }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: Space.s2) {
            if model.step == .done {
                Button("Add another") { Task { await model.startOver() } }.buttonStyle(.corePlain)
                Spacer(minLength: 0)
                Button("Done", action: attemptClose).buttonStyle(.coreProminent).coreShortcut(.primary)
            } else {
                if model.step == .what {
                    Button("Cancel", action: attemptClose).buttonStyle(.corePlain).coreShortcut(.cancel)
                } else {
                    Button("Back") { model.back() }.buttonStyle(.coreSecondary)
                }
                if model.step == .connect, let withdraw = withdrawAction {
                    Button("Withdraw the invite", action: withdraw).buttonStyle(.corePlain)
                }
                Spacer(minLength: 0)
                if model.step == .install && model.kind == .phone {
                    Button("Pick something else") { model.step = .what }.buttonStyle(.coreProminent)
                } else {
                    Button(AddWizardWords.next(model)) { Task { await model.next() } }
                        .buttonStyle(CoreButtonStyle(.prominent, busy: model.applying))
                        .coreShortcut(.primary).disabled(!model.canGoNext)
                }
            }
        }
    }

    /// The connect step's quiet second action, while an invite is live.
    private var withdrawAction: (() -> Void)? {
        if model.usesRunnerInvite, let m = model.runnerInvite, m.live { return { Task { await m.withdraw() } } }
        if model.usesInvite, let m = model.invite, m.invite != nil, !m.used, !m.ended {
            return { Task { await m.withdraw() } }
        }
        return nil
    }

    func attemptClose() {
        Task { if await model.requestClose() { close() } }
    }
}

/// A choice card in a grid (What do you want to add?): a plain well that lifts on hover, gets the blue edge when chosen and
/// presses in. Local: CoreUI's RadioRow is a row, not a card. Proposal: a card variant of RadioRow.
struct ChoiceCardStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.corePalette) private var palette
        @Environment(\.accessibilityReduceMotion) private var reduce
        @State private var hovering = false
        var body: some View {
            let shape = coreShape(Radius.cardMac)
            configuration.label
                .foregroundStyle(palette.text)
                .background(selected || hovering ? palette.uDimHover : palette.uDim, in: shape)
                .overlay { if selected { shape.strokeBorder(palette.primary, lineWidth: 1.5) } }
                .contentShape(shape)
                .scaleEffect(configuration.isPressed && !reduce ? 0.985 : 1)
                .animation(Motion.out(Motion.press), value: configuration.isPressed)
                .animation(Motion.out(Motion.hover), value: hovering)
                .animation(Motion.out(Motion.hover), value: selected)
                .onHover { hovering = $0 }
        }
    }
}
