import CoreUI
import SwiftUI

/// Add an AI account (approved mockup `Designs/core/0-10/review/ai-accounts`, the Connections dialog's look): Pick · Add ·
/// Done. The cards come from the Core's provider list (`AddCards`), so a provider the Core adds appears here with no change.
/// The steps live in `AddAccountSteps.swift`; this is the frame, the pick and the wiring. The dialog is as tall as its step.
struct AddAccountDialog: View {
    let model: AccountsModel
    let provider: String?
    let close: () -> Void
    /// Inside setup's AI page (no dialog frame, no step track): the pick is the approved 02 Setup one, a switch between API
    /// key and subscription over one grid of provider cards; `inFlow` tells setup to step its own buttons aside meanwhile.
    var embedded = false
    var inFlow: Binding<Bool>? = nil
    @State var flow = AddAccountFlow()
    @State var kind = AddAccountDialog.startKind
    #if DEBUG
    private static var startKind: ProviderKind { SetupAIDebug.subscriptionFirst ? .subscription : .apiKey }
    #else
    private static let startKind = ProviderKind.apiKey
    #endif
    @State var code = ""
    @State var copied = false
    @State var details = false
    @Environment(\.accessibilityReduceMotion) var reduce

    static let width: CGFloat = 600

    var body: some View {
        Group {
            if embedded {
                stage
            } else {
                CoreDialogPanel("", width: Self.width) {
                    VStack(spacing: Space.s5) {
                        AddPath(at: flow.stepper.number - 1)
                        ConnStage(index: flow.stepper.number) { stage }
                    }
                }
            }
        }
        // The height eases between steps and as a sign-in moves on; Reduce Motion fades instead.
        .animation(Motion.calm(Motion.out(Motion.move), reduce), value: flow.stepper.number)
        .animation(Motion.calm(Motion.out(Motion.move), reduce), value: flow.stepper.step)
        .animation(Motion.calm(Motion.out(Motion.move), reduce), value: signInAt)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: kind)
        .onChange(of: flow.stepper.step, initial: true) { _, s in inFlow?.wrappedValue = s != .pick }
        .task {
            // Unstructured: a sign-in outlives this task, and the dialog's close stops it.
            if let id = provider, let p = model.provider(id) {
                kind = ProviderCatalog.kind(p)
                Task { await flow.choose(p, model) }
            }
            #if DEBUG
            if AddAccountDebug.subscription { kind = .subscription }
            await AddAccountDebug.apply(flow)
            #endif
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

    @ViewBuilder private var stage: some View {
        switch flow.stepper.step {
        case .pick: if embedded { setupPick } else { pick }
        case .key, .checking: keyStep
        case .signIn: signInStep
        case .done: doneStep
        }
    }

    // MARK: parts the steps share

    var chosen: ProviderItem? { flow.provider(model) }
    var name: String { chosen.map(AddCards.name) ?? flow.name(model) }
    var logo: String { AddCards.logo(flow.providerID ?? "") }
    var signInAt: SignInStep { SignInStep.of(model.signIn, style: flow.style(model)) }

    func head(_ title: String, _ sub: String) -> some View {
        VStack(spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.large, weight: .semibold).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(sub).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Cancel (esc) and Back on the left, the step's action on the right.
    func footer(
        back: Bool = true, primary: (String, () -> Void)? = nil, enabled: Bool = true, busy: Bool = false
    ) -> some View {
        ConnFooter(
            cancel: close, back: back ? { flow.back(model) } : nil, primary: primary, enabled: enabled, busy: busy)
    }

    func choose(_ p: ProviderItem) {
        code = ""
        copied = false
        details = false
        Task { await flow.choose(p, model) }
    }

    // MARK: 1. pick

    private var pick: some View {
        let cards = AddCards.cards(model.providers, kind)
        return VStack(spacing: Space.s4) {
            head(
                "Add an AI account",
                kind == .apiKey
                    ? "Paste a key from the provider. Core keeps it sealed."
                    : "Use a plan you already pay for. You sign in on their website.")
            kindSwitch
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3), spacing: Space.s2)
            {
                ForEach(cards) { p in AddPickCard(provider: p) { choose(p) } }
            }
            .id(kind)
            .transition(.opacity)
            if cards.isEmpty {
                Text("Your Core offers none of these yet.").foregroundStyle(GlassInk.secondary)
            }
            footer(back: false)
        }
    }

    private var kindSwitch: some View {
        CoreSegmented(
            "How to connect",
            segments: [CoreSegment(ProviderKind.apiKey, "API key"), CoreSegment(.subscription, "Subscription")],
            selection: $kind, fill: true)
    }

    /// Setup's pick (approved 02 Setup): API key or subscription, then that kind's providers, ⌘1… on each card.
    private var setupPick: some View {
        let cards = AddCards.cards(model.providers, kind)
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
                    SetupProviderCard(provider: p, key: i + 1) { choose(p) }
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
}

/// Pick · Add · Done as a path: a bar and a word each, done and current bars in the accent (the Connections path).
private struct AddPath: View {
    @Environment(\.coreAccent) private var paneAccent
    let at: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    private static let steps = ["Pick", "Add", "Done"]
    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                VStack(spacing: Space.s2) {
                    coreShape(2).fill(i <= at ? GlassInk.accent(paneAccent) : GlassInk.track).frame(height: 3)
                    Text(s).coreFont(size: MacTextSize.meta, weight: i == at ? .semibold : .regular)
                        .foregroundStyle(i == at ? GlassInk.primary : GlassInk.secondary)
                }
                .frame(width: Space.s8 * 2 + Space.s4)
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: at)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(at + 1) of 3: \(Self.steps[min(max(at, 0), 2)])")
    }
}

/// A provider as a card in the pick's grid: its monochrome logo, name and one line (the Connections pick card).
private struct AddPickCard: View {
    let provider: ProviderItem
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        let name = AddCards.name(provider)
        let line = AddCards.line(provider)
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.s3) {
                ConnLogo(kind: AddCards.logo(provider.id), size: Space.s8 + Space.s1, lit: hover)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).coreFont(size: MacTextSize.body, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac, hoverFill: true))
        .onHover { hover = $0 }
        .accessibilityLabel("\(name). \(line)")
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

/// Snapshot walks: a state of the key step to open on, set by the demo scene before the dialog opens.
enum AddAccountDebug {
    nonisolated(unsafe) static var key: String?
    nonisolated(unsafe) static var opened = false
    nonisolated(unsafe) static var checking = false
    nonisolated(unsafe) static var doneModels: Int?
    nonisolated(unsafe) static var subscription = false

    static func reset() { (key, opened, checking, doneModels, subscription) = (nil, false, false, nil, false) }

    @MainActor static func apply(_ flow: AddAccountFlow) async {
        guard key != nil || opened || checking || doneModels != nil else { return }
        try? await Task.sleep(for: .milliseconds(400))  // after the pick's choose
        if let k = key { flow.key = k }
        flow.keyOpened = opened
        if checking || doneModels != nil { flow.stepper.submitKey() }
        if let n = doneModels {
            flow.modelsFound = n
            flow.stepper.checked(ok: true)
        }
    }
}
#endif
