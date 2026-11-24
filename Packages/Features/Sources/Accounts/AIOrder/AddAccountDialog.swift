import CoreUI
import SwiftUI

/// Add account (E7-2): three steps. Pick a provider card, paste a key or sign in, done. The cards come from the Core's
/// provider list, so a provider the Core adds (a preset, a new subscription) appears here with no change to this view.
struct AddAccountDialog: View {
    @Environment(\.coreAccent) private var paneAccent
    let model: AccountsModel
    let provider: String?
    let close: () -> Void
    /// Inside setup's AI page (no dialog frame, no step track): the pick is the approved 02 Setup one, a switch between API
    /// key and subscription over one grid of provider cards; `inFlow` tells setup to step its own buttons aside meanwhile.
    var embedded = false
    var inFlow: Binding<Bool>? = nil
    @State private var flow = AddAccountFlow()
    @State private var kind = AddAccountDialog.startKind
    #if DEBUG
    private static var startKind: ProviderKind { SetupAIDebug.subscriptionFirst ? .subscription : .apiKey }
    #else
    private static let startKind = ProviderKind.apiKey
    #endif
    @State private var code = ""
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                CoreDialogPanel("", width: Space.s8 * 18) { content }
            }
        }
        .onChange(of: flow.stepper.step, initial: true) { _, s in inFlow?.wrappedValue = s != .pick }
        .animation(reduce ? nil : Motion.out(Motion.ui), value: flow.stepper.step)
        .task {
            // Unstructured: a sign-in outlives this task, and the dialog's close stops it.
            if let id = provider, let p = model.provider(id) { Task { await flow.choose(p, model) } }
        }
        .onChange(of: model.signIn?.stage) { _, s in
            if case .done(let account)? = s, flow.stepper.step == .signIn {
                Task { await flow.signedIn(account, model) }
            }
        }
        .onDisappear {
            flow.key = ""
            if model.signInEnded { model.signIn = nil }
        }
        .accessibilityIdentifier("account-add")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if !embedded {
                StepTrack(["Pick", "Add", "Done"], at: flow.stepper.number - 1, hue: GlassInk.accent(paneAccent))
            }
            Group {
                switch flow.stepper.step {
                case .pick: if embedded { setupPick } else { pick }
                case .key: keyStep
                case .checking: checking
                case .signIn: signIn
                case .done: done
                }
            }
            .transition(reduce ? .identity : .opacity)
        }
    }

    // MARK: pick

    /// Setup's pick (approved 02 Setup): API key or subscription, then that kind's providers, ⌘1… on each card.
    private var setupPick: some View {
        let cards = ProviderCatalog.cards(model.providers, kind)
        return VStack(alignment: .leading, spacing: Space.s3) {
            CoreSegmented(
                "How to connect",
                segments: [
                    CoreSegment(ProviderKind.apiKey, "API key"),
                    CoreSegment(.subscription, "Sign in with subscription"),
                ],
                selection: $kind)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 4), spacing: Space.s3)
            {
                ForEach(Array(cards.prefix(8).enumerated()), id: \.element.id) { i, p in
                    SetupProviderCard(provider: p, key: i + 1) { Task { await flow.choose(p, model) } }
                }
            }
            if kind == .subscription {
                Label(
                    "Uses your subscription at your own risk. The provider may limit or block this.",
                    systemImage: "exclamationmark.triangle"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.amberInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pick: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            heading("Add an account", "Pick where your AI comes from. You can add more later.")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    section("Use your subscription", .subscription)
                    section("Use an API key", .apiKey)
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: Space.s8 * 12)
            AccDialogButtons(cancel: close)
        }
    }

    @ViewBuilder private func section(_ title: String, _ kind: ProviderKind) -> some View {
        let cards = ProviderCatalog.cards(model.providers, kind)
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())], spacing: Space.s2
                ) {
                    ForEach(cards) { p in ProviderCard(provider: p) { Task { await flow.choose(p, model) } } }
                }
            }
        }
    }

    // MARK: key

    private var keyBinding: Binding<String> { Binding(get: { flow.key }, set: { flow.key = $0 }) }

    /// The new account's name (Core API minor 96): prefilled with the provider's, editable, capitals and spaces allowed.
    @ViewBuilder private func nameField(submit: @escaping () -> Void) -> some View {
        if model.namesOn {
            CoreTextField(
                "Name", placeholder: flow.name(model),
                text: Binding(get: { flow.accountName }, set: { flow.accountName = $0 }), error: flow.nameIssue
            ) { submit() }
            .accessibilityIdentifier("account-name")
        }
    }

    private var keyStep: some View {
        let live = flow.live(model)
        return VStack(alignment: .leading, spacing: Space.s3) {
            hero("Add your \(flow.name(model)) key", "Paste it below. Core checks it right away.")
            nameField { go() }
            HStack(alignment: .bottom, spacing: Space.s2) {
                CoreSecureField("", placeholder: "Paste your key", text: keyBinding, autofocus: true) { go() }
                    .accessibilityIdentifier("account-key")
                AccLink(title: "Paste", symbol: "doc.on.clipboard") { flow.keyFlow.paste() }
            }
            Label(KeyShape.words(live), systemImage: live == .looksValid ? "checkmark" : "key")
                .coreFont(size: MacTextSize.meta)
                .foregroundStyle(live == .looksValid ? GlassInk.ink(GlassInk.green) : GlassInk.secondary)
            if let e = flow.error { AccIssue(text: e) }
            AccNotice(notice: model.host.elevationNotice)
            Text("Your key goes straight to your Core and is never shown again.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            AccDialogButtons(
                confirm: "Check and add", cancelTitle: "Back", enabled: live == .looksValid && flow.nameIssue == nil,
                cancel: { flow.back(model) }, run: go)
        }
    }

    private func go() {
        guard flow.live(model) == .looksValid, flow.nameIssue == nil else { return }
        Task { await flow.submitKey(model, settle: !reduce) }
    }

    private var checking: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            hero("Checking your key", "One moment.")
            let lines = [
                "Reaching \(flow.name(model))", "Your key works",
                flow.modelsSettled
                    ? (flow.modelsFound.map { "Found \($0) models" } ?? "Found its models") : "Finding its models",
            ]
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, text in
                    let state = i < flow.progress ? 2 : i == flow.progress ? 1 : 0
                    HStack(spacing: Space.s3) {
                        Image(
                            systemName: state == 2 ? "checkmark" : state == 1 ? "arrow.triangle.2.circlepath" : "minus"
                        )
                        .coreFont(size: MacTextSize.body, weight: .semibold)
                        .foregroundStyle(state == 2 ? GlassInk.ink(GlassInk.green) : GlassInk.secondary)
                        .frame(width: Space.s6, height: Space.s6)
                        .background(GlassInk.well, in: coreShape(Radius.chip))
                        Text(text).foregroundStyle(state == 0 ? GlassInk.secondary : GlassInk.primary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(state == 2 ? "Done" : state == 1 ? "Working" : "Waiting")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            AccDialogButtons(confirm: "Checking", busy: true, enabled: false, cancel: { flow.back(model) })
        }
    }

    // MARK: sign-in

    @ViewBuilder private var signIn: some View {
        if let c = flow.runners, model.signIn == nil {
            let name = flow.name(model)
            if c.none {
                NoRunnerView(
                    provider: name, choice: c, install: installOffer(c),
                    openRunners: {
                        // Setup hides the desktop: the Runners app would open behind it. Back to the pick there.
                        if embedded { return flow.back(model) }
                        close()
                        model.openRunners()
                    },
                    back: { flow.back(model) })
            } else {
                ConsentView(
                    provider: name, consent: Binding(get: { flow.consent }, set: { flow.consent = $0 }),
                    start: { Task { await flow.startOnCore(model) } }, back: { flow.back(model) })
            }
        } else {
            signInRunning
        }
    }

    /// The install that lets a runner sign in, when the Core can do it.
    private func installOffer(_ c: RunnerChoice) -> NoRunnerView.Install? {
        guard let p = flow.provider(model), let target = flow.installing ?? c.installTarget(harness: p.harness) else {
            return nil
        }
        let progress = model.installs["\(target.id)|\(p.harness)"]
        return NoRunnerView.Install(
            runner: target.name, progress: progress, waiting: flow.waitingRestart,
            running: flow.installing != nil || progress?.state == .running, note: flow.installNote,
            start: { Task { await flow.installThenSignIn(model, on: target) } })
    }

    private var signInRunning: some View {
        let s = model.signIn
        let name = flow.name(model)
        let style = flow.style(model)
        let pastes = style == .paste
        return VStack(alignment: .leading, spacing: Space.s3) {
            hero(
                "Sign in with \(name)",
                style == .guided
                    ? "Follow the sign-in below. Type what it asks for."
                    : s?.deviceCode != nil
                        ? "Open the page and type this code."
                        : pastes
                            ? "Sign in on the page that opens in your browser, then paste the code it shows."
                            : "Sign in on the page that opens in your browser.")
            nameField {}
            if let c = s?.deviceCode { codeBlock(c) }
            if case .guided? = s?.stage {
                GuidedTerminal(
                    lines: s?.screen ?? [], error: s?.inputError, provider: s?.provider ?? "",
                    sending: s?.sending ?? false,
                    send: { l in Task { await model.sendGuidedInput(l) } })
            }
            if pastes, case .open? = s?.stage { pasteField(s?.codeError) }
            status(s?.stage, name: name)
            RunnerBoundNote(binding: RunnerBinding.forSignIn(flow.providerID ?? ""))
            if SignInStyle.showsRisk(flow.providerID ?? "") {
                Label(
                    "Uses your subscription at your own risk. The provider's rules may not allow it.",
                    systemImage: "exclamationmark.triangle"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.amberInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            footerSignIn(s?.stage, pastes: pastes)
        }
    }

    private func codeBlock(_ c: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your code").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Text(c).coreFont(size: MacTextSize.large, weight: .bold, design: .monospaced).textSelection(.enabled)
            }
            Spacer(minLength: Space.s2)
            AccLink(title: "Copy", symbol: "doc.on.doc", help: "Copy the code") {
                flow.copy(c)
                model.host.shell.showToast("Code copied")
            }
        }
        .padding(Space.s3)
        .coreWell(radius: Radius.control)
        .accessibilityIdentifier("sign-in-device-code")
    }

    private func pasteField(_ err: String?) -> some View {
        CoreTextField(
            "", placeholder: "Paste the code here", text: $code, error: err, mono: true, autofocus: true
        ) { Task { await model.sendSignInCode(code) } }
        .accessibilityIdentifier("sign-in-code")
    }

    @ViewBuilder private func status(_ stage: SignInFlow.Stage?, name: String) -> some View {
        switch stage {
        case nil, .starting?: wait("Getting \(name) ready…")
        case .open?, .guided?: WaitingDots(text: "Waiting for you to finish…")
        case .working?: wait("Almost there. Connecting \(name) to your Core…")
        case .failed(let why)?: AccIssue(text: why)
        case .done?: EmptyView()
        }
    }

    private func wait(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreBusyBar().frame(maxWidth: Space.s8 * 8)
            Text(text).foregroundStyle(GlassInk.secondary)
        }
    }

    @ViewBuilder private func footerSignIn(_ stage: SignInFlow.Stage?, pastes: Bool) -> some View {
        if case .failed? = stage {
            AccDialogButtons(
                confirm: "Try again", cancelTitle: "Back", cancel: { flow.back(model) },
                run: { Task { await flow.retrySignIn(model) } })
        } else if pastes, case .open? = stage {
            VStack(alignment: .leading, spacing: Space.s2) {
                if case .open(let url)? = stage {
                    AccLink(title: "Open sign-in page", symbol: "globe") { model.opener(url) }
                }
                AccDialogButtons(
                    confirm: "Connect", cancelTitle: "Back",
                    enabled: !code.trimmingCharacters(in: .whitespaces).isEmpty,
                    cancel: { flow.back(model) }, run: { Task { await model.sendSignInCode(code) } })
            }
        } else if case .guided(let url)? = stage {
            VStack(alignment: .leading, spacing: Space.s2) {
                if let url { AccLink(title: "Open sign-in page", symbol: "globe") { model.opener(url) } }
                AccDialogButtons(cancelTitle: "Cancel", cancel: { flow.back(model) })
            }
        } else if case .open(let url)? = stage {
            AccDialogButtons(
                confirm: "Open sign-in page", cancelTitle: "Back", cancel: { flow.back(model) },
                run: { model.opener(url) })
        } else {
            AccDialogButtons(cancelTitle: "Back", cancel: { flow.back(model) })
        }
    }

    // MARK: done

    private var done: some View {
        VStack(alignment: .center, spacing: Space.s3) {
            ProviderTile(name: flow.name(model), size: Space.s8 * 2)
            Text("\(flow.name(model)) is added").coreFont(size: MacTextSize.large, weight: .bold)
            Text("It is number \(flow.number(model)) in your AI order. Drag it up to use it sooner.")
                .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            StateBadge("Ready", tone: .run, symbol: "checkmark.circle")
            HStack(spacing: Space.s2) {
                Button("Add another") {
                    code = ""
                    flow.again(model)
                }.buttonStyle(CoreButtonStyle(.secondary))
                Spacer(minLength: Space.s2)
                Button("Done", action: close).buttonStyle(CoreButtonStyle(.prominent))
                    .keyboardShortcut(.defaultAction).environment(\.coreKeycap, "⏎")
            }
            .padding(.top, Space.s3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("account-add-done")
    }

    // MARK: parts

    private func heading(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.large, weight: .bold).accessibilityAddTraits(.isHeader)
            Text(sub).foregroundStyle(GlassInk.secondary)
        }
    }

    private func hero(_ title: String, _ sub: String) -> some View {
        VStack(spacing: Space.s2) {
            ProviderTile(name: flow.name(model), size: Space.s8 * 2)
            Text(title).coreFont(size: MacTextSize.large, weight: .bold).accessibilityAddTraits(.isHeader)
            Text(sub).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProviderCard: View {
    let provider: ProviderItem
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let name = ProviderCatalog.name(provider.id, fallback: provider.name)
        Button(action: action) {
            HStack(spacing: Space.s3) {
                ProviderTile(name: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    Text(ProviderCatalog.blurb(provider)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(hover ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(name)
        .accessibilityIdentifier("add-\(provider.id)")
    }
}

/// A provider on setup's pick (approved 02 Setup): its letter, name and one line, centred; ⌘<n> picks it.
private struct SetupProviderCard: View {
    let provider: ProviderItem
    let key: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let name = ProviderCatalog.name(provider.id, fallback: provider.name)
        Button(action: action) {
            VStack(spacing: Space.s2) {
                ProviderTile(name: name)
                VStack(spacing: 2) {
                    Text(name).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(ProviderCatalog.blurb(provider)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, Space.s4).padding(.horizontal, Space.s2)
            .coreWell(active: hover)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .coreTileKey("⌘\(key)", key: Character("\(key)"))
        .accessibilityLabel(name)
        .accessibilityIdentifier("setup-add-\(provider.id)")
    }
}

#if DEBUG
/// Snapshot walks: which side setup's AI pick opens on.
public enum SetupAIDebug {
    nonisolated(unsafe) public static var subscriptionFirst = false
}
#endif
