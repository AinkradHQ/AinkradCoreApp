import CoreUI
import SwiftUI

extension AccountsModel {
    /// How many accounts the Core holds, for the setup's last page.
    public var accountCount: Int { accounts.count }
}

/// The AI page of setup (E3-1): connect as many accounts as you like, each by API key or by subscription sign-in, and see
/// the ones that are connected. It uses the same key entry, test and sign-in as Accounts, so the key goes to the Core once
/// and is never shown again. Setup runs before the Mac runner is on, so a key is saved first and checked when a runner can.
public struct SetupAIStep: View {
    let model: AccountsModel
    /// Turns this Mac on as a runner (setup's runner page, early), so a subscription can sign in on it. nil: there is none.
    let turnOnThisMac: (@MainActor () async -> Void)?
    public init(model: AccountsModel, turnOnThisMac: (@MainActor () async -> Void)? = nil) {
        self.model = model
        self.turnOnThisMac = turnOnThisMac
    }

    @State private var adding = false
    @State private var provider = ""
    @State private var plan = false
    @State private var flow = KeyEntryFlow(allowNoRunner: true)
    @State private var busy = false
    @State private var note: String?
    @Environment(\.corePalette) private var palette

    private var keyProviders: [ProviderItem] {
        model.providers.filter { !$0.loginMethods.contains("browser_code") }.sorted { $0.builtin && !$1.builtin }
    }
    private var planProvider: ProviderItem? { model.providers.first { $0.loginMethods.contains("browser_code") } }
    private var showList: Bool { !model.accounts.isEmpty && !adding }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if showList { list } else { add }
        }
        .task {
            await flow.load(model)
            if provider.isEmpty { provider = keyProviders.first?.id ?? "" }
        }
        .onDisappear { flow.wipe() }
    }

    // MARK: connected

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(model.accounts) { a in
                HStack(spacing: Space.s3) {
                    letter(model.providerName(a.provider))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.providerName(a.provider)).coreFont(size: MacTextSize.body, weight: .semibold)
                        Text(a.isPlan ? "Subscription" : "API key ending \(a.maskedTail)")
                            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    }
                    Spacer(minLength: Space.s3)
                    CoreChip("Connected", symbol: "checkmark")
                    AccLink(title: "Remove", danger: true) { Task { _ = await model.delete(a) } }
                }
                .padding(Space.s3).coreWell()
                .accessibilityElement(children: .combine)
            }
            if let note {
                Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Add another") {
                    note = nil
                    adding = true
                }
                .coreGlassButton()
                Spacer()
            }
        }
    }

    // MARK: add one

    private var add: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 4), spacing: Space.s3)
            {
                ForEach(keyProviders.prefix(8)) { p in
                    Button {
                        provider = p.id
                        note = nil
                    } label: {
                        VStack(spacing: Space.s2) {
                            letter(p.name)
                            Text(p.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                        .coreWell(active: provider == p.id)
                        .contentShape(coreShape(Radius.cardMac))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(provider == p.id ? .isSelected : [])
                }
            }
            HStack {
                if planProvider != nil {
                    CoreSegmented(
                        "How to connect",
                        segments: [CoreSegment(false, "API key"), CoreSegment(true, "Sign in with subscription")],
                        selection: $plan)
                }
                Spacer()
                if !model.accounts.isEmpty {
                    Button("Cancel") {
                        adding = false
                        flow.wipe()
                    }
                    .coreGlassButton()
                }
            }
            if plan, let p = planProvider { subscription(p) } else { keyEntry }
        }
    }

    @ViewBuilder private var keyEntry: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .bottom, spacing: Space.s2) {
                CoreSecureField("Key", placeholder: "Paste your key", text: $flow.key)
                    .accessibilityIdentifier("setup-ai-key")
                Button("Paste") { flow.paste() }.coreGlassButton()
                Button("Connect") { Task { await connect() } }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .large, busy: busy))
                    .disabled(
                        busy || flow.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider.isEmpty)
            }
            if let note {
                Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(palette.tone(.fail).ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Kept encrypted on your Core. It is never shown again.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
    }

    @ViewBuilder private func subscription(_ p: ProviderItem) -> some View {
        if flow.runners.contains(where: \.online) {
            SubscriptionSignIn(model: model, provider: p) { adding = false }
        } else {
            CoreNotice(
                symbol: "exclamationmark.triangle", title: "Signing in needs a runner",
                text: turnOnThisMac == nil
                    ? "Add a runner, then sign in from Accounts. Or use an API key now."
                    : "Your subscription signs in on a runner. This Mac can be one.",
                tone: .warn
            ) {
                if let turnOnThisMac {
                    Button("Turn on This Mac") {
                        Task {
                            busy = true
                            await turnOnThisMac()
                            await flow.load(model)
                            busy = false
                        }
                    }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: busy)).disabled(busy)
                }
            }
        }
    }

    private func letter(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased()).coreFont(size: MacTextSize.title, weight: .semibold)
            .frame(width: 36, height: 36).background(GlassInk.well, in: coreShape(Radius.control))
            .accessibilityHidden(true)
    }

    /// A free name for one more account of this provider: `claude`, then `claude-2`, and so on.
    private func freeLabel(_ id: String) -> String {
        let base = KeyEntryFlow.slug(id)
        let taken = Set(model.accounts.map(\.label))
        if !taken.contains(base) { return base }
        return (2...).lazy.map { "\(base)-\($0)" }.first { !taken.contains($0) } ?? base
    }

    private func connect() async {
        busy = true
        note = nil
        defer { busy = false }
        // One Touch ID turns the key switches on when they are off.
        if flow.needsGate { await flow.enableKeys(model) }
        if flow.needsGate {
            note = flow.gateNote ?? "Keys are turned off on your Core."
            return
        }
        flow.label = freeLabel(provider)
        await flow.connect(model, provider: provider)
        switch flow.stage {
        case .done:
            adding = false
            reset()
        case .failed(let why, let account):
            if account != nil {
                // Saved, but the check could not run yet: it stays in the list, checked once a runner is on.
                adding = false
                reset()
                note = why
            } else {
                note = why
                flow.tryAnother()
            }
        default:
            flow.tryAnother()
        }
    }

    private func reset() {
        flow.wipe()
        flow = KeyEntryFlow(allowNoRunner: true)
        Task { await flow.load(model) }
    }
}
