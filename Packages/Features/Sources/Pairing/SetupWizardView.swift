import AppKit
import CoreUI
import Shell
import SwiftUI

/// The first screen of a fresh Mac: set up a new Core, or use one that already runs. Both end on the same paste screen.
struct SetupWizardView: View {
    @Bindable var model: SetupWizardModel
    /// "Pair with a code" instead: the older flow for a Core whose first device already exists.
    let useCode: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.clear.overlay {
                Image(scheme == .dark ? "HomeSky" : "HomeSkyDay", bundle: .main).resizable().scaledToFill()
            }
            .clipped().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                Group {
                    switch model.stage {
                    case .choose: choose
                    case .install: install
                    case .connect, .connecting: connect
                    case .failed(let f): failed(f)
                    }
                }
                .id(model.stage == .connecting ? Stage.connect : Stage(model.stage))
                .transition(.opacity.combined(with: .offset(x: coreMove(reduce, 12))))
            }
            .foregroundStyle(palette.text)
            .coreFont(size: MacTextSize.body)
            .padding(Space.s6)
            .coreFrame(radius: Radius.panel, part: .dialogs)
            .frame(width: Space.s8 * 17)
            .accessibilityElement(children: .contain)
        }
        .coreTheme()
        .animation(reduce ? .easeOut(duration: 0.2) : Motion.out(Motion.ui), value: Stage(model.stage))
        .ignoresSafeArea()
    }

    /// The screen a stage belongs to (connecting stays on the paste screen).
    private enum Stage: Hashable {
        case choose, install, connect, failed
        init(_ s: SetupWizardModel.Stage) {
            switch s {
            case .choose: self = .choose
            case .install: self = .install
            case .connect, .connecting: self = .connect
            case .failed: self = .failed
            }
        }
    }

    private var step: (Int, String) {
        switch model.stage {
        case .choose: (1, "Welcome")
        case .install: (2, "Install Core")
        case .connect, .connecting: (3, "Connect")
        case .failed: (0, "Connect to a Core")
        }
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                .accessibilityHidden(true)
            if step.0 > 0 {
                HStack(spacing: Space.s1) {
                    ForEach(1...3, id: \.self) { i in
                        coreShape(Radius.chip / 3).fill(i <= step.0 ? palette.primary : palette.track)
                            .frame(width: Space.s5, height: Space.s1)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(step.1).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
                .accessibilityLabel(step.0 > 0 ? "Step \(step.0) of 3, \(step.1)" : step.1)
        }
    }

    private func title(_ t: String) -> some View {
        Text(t).coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
    }

    private func note(_ t: LocalizedStringKey) -> some View {
        Text(t).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 1, new or existing

    private var choose: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title("Set up Ainkrad")
            note("Ainkrad runs your agents and terminals on a Core. This Mac shows you everything it does.")
            HStack(alignment: .top, spacing: Space.s3) {
                ChoiceCard(
                    symbol: "plus", title: "Set up a new Core",
                    detail: "Install Core on a Linux machine. One command, about two minutes."
                ) { model.chooseNew() }
                ChoiceCard(
                    symbol: "link", title: "Use an existing Core",
                    detail: "Paste a link from a Core that is already running."
                ) { model.chooseExisting() }
            }
            HStack {
                LinkButton(title: "Pair with a typed code instead", action: useCode)
                Spacer()
            }
        }
    }

    // MARK: 2, the one command

    private var install: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title("Install Core")
            VStack(alignment: .leading, spacing: Space.s1) {
                note("1. Open a terminal on any Linux machine you control.")
                note("2. Paste this command and press Return.")
                note("3. When it finishes it prints a link and a code. Come back here and paste the link.")
            }
            HStack(alignment: .top, spacing: Space.s2) {
                Text(SetupWizardModel.installCommand).coreFont(size: MacTextSize.body, design: .monospaced)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("install-command")
                Spacer(minLength: 0)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SetupWizardModel.installCommand, forType: .string)
                    copied = true
                }
                .coreGlassButton().accessibilityHint("Copies the install command")
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.glassCard, in: coreShape(Radius.row))
            Text("It checks the release signature before it runs anything, and needs root to set Core up as a service.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Back") { model.back() }.coreGlassButton().coreShortcut(.cancel)
                Spacer()
                Button("I have the link") { model.haveLink() }.coreGlassButton(prominent: true).coreShortcut(.primary)
            }
        }
    }

    // MARK: 3, paste the link

    private var connect: some View {
        let busy = model.stage == .connecting
        return VStack(alignment: .leading, spacing: Space.s4) {
            title("Connect to your Core")
            note("Paste the link the installer printed. It starts with ainkrad://connect.")
            CoreTextField(
                "Link", placeholder: "ainkrad://connect?host=…", text: $model.linkText,
                error: model.linkError, mono: true, autofocus: true, onSubmit: { model.connect() }
            )
            .disabled(busy)
            .accessibilityIdentifier("connect-link-field")
            if let link = model.link {
                FactCard {
                    FactRow(key: "Core", value: link.address, mono: true)
                    FactRow(key: "Fingerprint", value: link.fingerprintHint, mono: true)
                }
                .transition(.opacity)
            }
            if busy {
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreBusyBar()
                    Text("Checking this Core, then claiming your invite").coreFont(
                        size: MacTextSize.body, weight: .semibold)
                }
                .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                Button("Back") { model.back() }.coreGlassButton().coreShortcut(.cancel).disabled(busy)
                Spacer()
                Button("Connect") { model.connect() }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .large, busy: busy))
                    .coreShortcut(.primary).disabled(!model.canConnect)
            }
        }
    }

    // MARK: failed

    private func failed(_ f: Failure) -> some View {
        FailureView(
            failure: f, retryAt: nil,
            actions: f.fatal
                ? [FailureAction(label: "Start over", style: .primary) { model.startOver() }]
                : [
                    FailureAction(label: "Back") { model.startOver() },
                    FailureAction(label: "Try again", style: .primary) { model.tryAgain() },
                ])
    }
}

/// One of the two first choices: a glass card that lifts a little under the pointer (a still change with Reduce Motion).
private struct ChoiceCard: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Image(systemName: symbol).coreFont(size: MacTextSize.large).foregroundStyle(palette.primary)
                    .accessibilityHidden(true)
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: Space.s8 * 4, alignment: .topLeading)
            .padding(Space.s4)
            .background(hover ? palette.glassCardEdge : palette.glassCard, in: coreShape(Radius.row))
            .overlay { coreShape(Radius.row).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(reduce ? nil : Motion.out(Motion.ui), value: hover)
        .accessibilityElement(children: .combine)
    }
}
