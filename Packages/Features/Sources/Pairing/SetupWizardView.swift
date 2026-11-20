import AppKit
import CoreUI
import Shell
import SwiftUI

/// The first screen of a fresh Mac: set up a new Core, or use one that already runs. Both end on the same paste screen.
struct SetupWizardView: View {
    @Bindable var model: SetupWizardModel
    /// "Pair with a code" instead: the older flow for a Core whose first device already exists.
    let useCode: () -> Void
    /// The welcome cards: About you and Your look open those setup pages before a Core is connected.
    let startTour: (SetupTourModel.Detour) -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.clear.overlay {
                WallpaperView()
            }
            .clipped().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                Group {
                    switch model.stage {
                    case .choose:
                        if model.welcomed { choose } else { welcome }
                    case .install: install
                    case .waiting: waiting
                    case .found: found
                    case .nearby: nearby
                    case .connect, .connecting: connect
                    case .failed(let f): failed(f)
                    }
                }
                .id(screen)
                .transition(.opacity.combined(with: .offset(x: coreMove(reduce, 12))))
            }
            .foregroundStyle(palette.text)
            .coreFont(size: MacTextSize.body)
            .padding(Space.s6)
            .coreFrame(radius: Radius.pane, part: .dialogs)
            .frame(width: Space.s8 * 17)
            .accessibilityElement(children: .contain)
        }
        .coreTheme()
        .animation(reduce ? .easeOut(duration: 0.2) : Motion.out(Motion.ui), value: screen)
        .ignoresSafeArea()
    }

    /// The screen a stage belongs to (connecting stays on the paste screen).
    private enum Stage: Hashable {
        case welcome, choose, install, waiting, found, nearby, connect, failed
        init(_ s: SetupWizardModel.Stage) {
            switch s {
            case .choose: self = .choose
            case .install: self = .install
            case .waiting: self = .waiting
            case .found: self = .found
            case .nearby: self = .nearby
            case .connect, .connecting: self = .connect
            case .failed: self = .failed
            }
        }
    }

    private var screen: Stage { model.stage == .choose && !model.welcomed ? .welcome : Stage(model.stage) }

    /// The bar this screen lights (of seven, see `SetupBars`) and its name.
    private var step: (Int, String) {
        switch model.stage {
        case .choose: model.welcomed ? (1, "Your Core") : (0, "Welcome")
        case .install: (1, "Install Core")
        case .connect, .connecting: (1, "Connect")
        case .waiting: (1, "Waiting for your Core")
        case .found: (1, "Your Core is here")
        case .nearby: (1, "Find your Core")
        case .failed: (0, "Connect to a Core")
        }
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                .accessibilityHidden(true)
            SetupBars(at: step.0)
            Text(step.1).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
        }
    }

    private func title(_ t: String) -> some View {
        Text(t).coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
    }

    private func note(_ t: LocalizedStringKey) -> some View {
        Text(t).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 0, welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Welcome to Ainkrad").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            note(
                "Your Core keeps your work, notes and AI in one calm place. Setup takes about three minutes, and you can skip anything."
            )
            HStack(alignment: .top, spacing: Space.s3) {
                welcomeTile("server.rack", "Your Core", "One place for everything") { model.getStarted() }
                welcomeTile("person", "About you", "So the AI knows you") { startTour(.you) }
                welcomeTile("sparkles", "Your look", "Make it yours") { startTour(.look) }
            }
            HStack {
                Spacer()
                Button("Get started") { model.getStarted() }.buttonStyle(CoreButtonStyle(.prominent, size: .large))
                    .coreShortcut(.primary)
            }
        }
    }

    private func welcomeTile(_ symbol: String, _ title: String, _ sub: String, open: @escaping () -> Void) -> some View
    {
        Button(action: open) {
            VStack(spacing: Space.s1) {
                IconTile(symbol, hue: GlassInk.blue, size: 36)
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            .frame(maxWidth: .infinity).padding(Space.s4).coreWell()
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 1, new or existing

    private var choose: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title("Set up Ainkrad")
            note("Ainkrad runs your AI sessions and terminals on a Core. This Mac shows you everything it does.")
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
                note("3. It asks two questions. This page moves on by itself when your Core says hello.")
            }
            HStack(alignment: .top, spacing: Space.s2) {
                Text(command).coreFont(size: MacTextSize.body, design: .monospaced)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("install-command")
                Spacer(minLength: 0)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }
                .coreGlassButton().accessibilityHint("Copies the install command")
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.control))
            Text("It checks the release signature before it runs anything, and needs root to set Core up as a service.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Back") { model.back() }.coreGlassButton().coreShortcut(.cancel)
                Spacer()
                Button("I have the link") { model.haveLink() }.coreGlassButton()
                Button("I pasted it") { model.startWaiting() }.coreGlassButton(prominent: true).coreShortcut(.primary)
            }
        }
    }

    /// The install line, with this setup's one-time code in it so the Core can hand the link back by itself.
    private var command: String {
        model.rendezvous.map { SetupWizardModel.installCommand(rendezvous: $0.spec) } ?? SetupWizardModel.installCommand
    }

    // MARK: 2b, waiting for the Core

    private var waiting: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title(model.waitEnded == nil ? "Waiting for your Core" : "Nothing yet")
            if let ended = model.waitEnded {
                note(LocalizedStringKey(ended))
            } else {
                note("This page moves on by itself when your Core says hello.")
                CoreBusyBar()
                Text("The link comes back sealed, so only this Mac can read it.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(palette.text2)
            }
            HStack {
                Button("Back") { model.back() }.coreGlassButton().coreShortcut(.cancel)
                Spacer()
                Button("Paste the link instead") { model.haveLink() }.coreGlassButton(prominent: model.waitEnded != nil)
            }
        }
    }

    // MARK: 2c, the Core that said hello

    private var found: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title("Your Core is here")
            note(
                "It is running and ready to connect. Compare the fingerprint below with the Fingerprint line your installer printed, and press Connect only if they are the same."
            )
            if let link = model.link {
                FactCard {
                    FactRow(key: "Core", value: String(link.address.prefix(80)), mono: true, oneLine: true)
                    // The whole fingerprint, wrapped, so it can be compared and not only recognised.
                    VStack(alignment: .leading, spacing: Space.s1 / 2) {
                        Text("Fingerprint").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        Text(link.coreFingerprint).coreFont(size: MacTextSize.body, design: .monospaced)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            note("From now on your Core updates itself at night.")
            HStack {
                Button("Back") { model.back() }.coreGlassButton().coreShortcut(.cancel)
                Spacer()
                Button("Paste a link instead") { model.haveLink() }.coreGlassButton()
                // No Return shortcut: this link came from the network, so it is connected only by a deliberate press.
                Button("Connect") { model.connect() }.buttonStyle(CoreButtonStyle(.prominent, size: .large))
                    .disabled(!model.canConnect)
            }
        }
    }

    // MARK: 1b, a Core near you

    private var nearby: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title(model.nearby.isEmpty ? "Looking for your Core" : "Found a Core near you")
            note(
                model.nearby.isEmpty
                    ? "Cores on your network show up here. You can also paste a link from yours."
                    : "Pick yours, then paste its link. The link proves it is the one you meant.")
            ForEach(model.nearby) { core in
                Button {
                    model.pick(core)
                } label: {
                    HStack(spacing: Space.s3) {
                        IconTile("server.rack", hue: GlassInk.blue, size: 36)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(core.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                            Text("Fingerprint \(core.fingerprintHint)").coreFont(
                                size: MacTextSize.meta, design: .monospaced
                            )
                            .foregroundStyle(palette.text2)
                        }
                        Spacer()
                    }
                    .padding(Space.s3).coreWell().contentShape(coreShape(Radius.cardMac))
                }
                .buttonStyle(CoreQuietPressStyle())
            }
            HStack {
                Button("Back") { model.back() }.coreGlassButton().coreShortcut(.cancel)
                Spacer()
                Button("Paste a link instead") { model.haveLink() }.coreGlassButton(prominent: model.nearby.isEmpty)
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
                error: model.linkError, mono: true, autofocus: !model.receivedFromApp,
                onSubmit: { if !model.receivedFromApp { model.connect() } }
            )
            .disabled(busy)
            .accessibilityIdentifier("connect-link-field")
            .background { if !model.linkText.isEmpty { WindowSharingGuard() } }
            if let p = model.picked {
                CoreNotice(
                    symbol: model.pickedMismatch ? "exclamationmark.triangle" : "server.rack",
                    title: model.pickedMismatch ? "That link is for a different Core" : "Paste the link from \(p.name)",
                    text: model.pickedMismatch
                        ? "It does not match the Core you picked (fingerprint \(p.fingerprintHint)), so nothing is sent."
                        : "Its fingerprint should start \(p.fingerprintHint).",
                    tone: model.pickedMismatch ? .warn : .queue
                ) {}
            }
            if model.receivedFromApp {
                CoreNotice(
                    symbol: "exclamationmark.triangle", title: "Opened from another app",
                    text: "Only continue if this is your Core. Compare the address and fingerprint with your Core's.",
                    tone: .warn
                ) {}
            }
            if let link = model.link {
                FactCard {
                    FactRow(key: "Core", value: String(link.address.prefix(80)), mono: true, oneLine: true)
                    if model.receivedFromApp {
                        // The whole fingerprint, wrapped, so it can be compared and not only recognised.
                        VStack(alignment: .leading, spacing: Space.s1 / 2) {
                            Text("Fingerprint").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                            Text(link.fingerprintFull).coreFont(size: MacTextSize.body, design: .monospaced)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        FactRow(key: "Fingerprint", value: link.fingerprintHint, mono: true)
                    }
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
                // A link from another app is never connected by Return: the person has to press the button.
                Button("Connect") { model.connect() }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .large, busy: busy))
                    .modifier(PrimaryKey(on: !model.receivedFromApp)).disabled(!model.canConnect)
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
            }
            .frame(maxWidth: .infinity, minHeight: Space.s8 * 4, alignment: .topLeading)
            .padding(Space.s4)
            .coreWell(active: hover)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(reduce ? nil : Motion.out(Motion.ui), value: hover)
        .accessibilityElement(children: .combine)
    }
}

private struct PrimaryKey: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.coreShortcut(.primary) } else { content }
    }
}
