import AppKit
import CoreUI
import Observation
import SwiftUI

/// Connect an account as a wizard (N22, variant B): Provider (rows with a live state) → Key or sign-in → Name and limit →
/// optionally "Where does it go?". The quick path adds the account with the defaults; the advanced path asks where.
@MainActor @Observable
final class ConnectWizardState {
    enum Step: Int {
        case provider = 0
        case key, name, place
    }

    var step = Step.provider
    var provider: String
    var flow = KeyEntryFlow()
    var limitText = "20"
    let advanced: Bool
    var poolPick: PoolPick = .standard
    var newPoolName = ""
    var chainPick: ChainPick = .standard
    var newChainName = ""
    /// The new account's seat (0-based) in the chosen order; nil is the end.
    var position: Int?
    var runners: [AccountRunner] = []
    var labelTouched = false

    init(provider: String, advanced: Bool) {
        self.provider = provider
        self.advanced = advanced
    }

    func isPlan(_ m: AccountsModel) -> Bool { m.provider(provider)?.loginMethods.contains("browser_code") ?? false }

    func readiness(_ p: ProviderItem) -> ProviderReadiness { .of(p, runners: runners) }

    /// The default name: "claude-work" for the provider, until the person types one.
    func suggestName(_ m: AccountsModel) {
        guard !labelTouched, let p = m.provider(provider) else { return }
        var base = KeyEntryFlow.slug("\(ProviderLook.short(p.id, p.name)) work")
        var n = 2
        let taken = Set(m.accounts.map(\.label))
        let start = base
        while taken.contains(base) {
            base = "\(start)-\(n)"
            n += 1
        }
        flow.label = base
    }

    var limit: Int64? { Placement.limitMicros(limitText) }

    /// The placement the wizard sends: nil on the quick path with the standard limit still means "the Core's defaults".
    func placement() -> AccountPlacement? {
        guard let limit else { return nil }
        var p = AccountPlacement(monthlyLimitMicros: limit)
        p.pool = poolPick
        p.chain = chainPick
        p.position = position
        return p
    }

    // MARK: the order, as the person sees it

    func chain(_ m: AccountsModel) -> ChainItem? {
        switch chainPick {
        case .standard: m.defaultChain
        case .existing(let id): m.chain(id)
        case .new: nil
        }
    }

    func resolvedPoolID(_ m: AccountsModel) -> Int64? {
        switch poolPick {
        case .standard: m.defaultPool(provider)?.id
        case .existing(let id): id
        case .new: nil
        }
    }

    func baseSeats(_ m: AccountsModel) -> [OrderSeat] {
        Placement.seats(chain: chain(m), pools: m.pools, accounts: m.accounts)
    }

    func newSeat(_ m: AccountsModel) -> OrderSeat {
        OrderSeat(
            id: "new", labels: [flow.slugged.isEmpty ? "new account" : flow.slugged], provider: provider,
            poolID: resolvedPoolID(m), isNew: true)
    }

    func seats(_ m: AccountsModel) -> [OrderSeat] {
        Placement.inserting(newSeat(m), into: baseSeats(m), at: position)
    }

    func issue(_ m: AccountsModel) -> String? { Placement.issue(adding: newSeat(m), to: baseSeats(m)) }

    var nameIssue: String? {
        if case .new(let n) = poolPick, KeyEntryFlow.slug(n).isEmpty { return "Name the new pool." }
        if case .new(let n) = chainPick, KeyEntryFlow.slug(n).isEmpty { return "Name the new order." }
        return nil
    }
}

struct ConnectWizard: View {
    let model: AccountsModel
    let close: () -> Void
    @State private var w: ConnectWizardState
    @State private var dragged = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    init(model: AccountsModel, provider: String?, advanced: Bool, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        let first =
            provider ?? ProviderLook.ordered(model.providers).first { ProviderSites.page($0.id) != nil }?.id
            ?? model.providers.first?.id ?? ""
        _w = State(initialValue: ConnectWizardState(provider: first, advanced: advanced))
    }

    private var plan: Bool { w.isPlan(model) }
    private var stages: [String] { plan ? ["Provider", "Sign in"] : ["Provider", "Key", "Name", "Where it goes"] }

    var body: some View {
        CoreDialogPanel("Connect an account", width: Space.s8 * 16) {
            VStack(alignment: .leading, spacing: Space.s4) {
                StepTrack(stages, at: min(w.step.rawValue, stages.count - 1), hue: GlassInk.blue)
                Group {
                    if w.flow.stage != .form {
                        outcome
                    } else {
                        switch w.step {
                        case .provider: providerStep
                        case .key: plan ? AnyView(signInStep) : AnyView(keyStep)
                        case .name: nameStep
                        case .place: placeStep
                        }
                    }
                }
                .transition(reduce ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            }
            .animation(.smooth(duration: 0.3), value: w.step)
        }
        .accessibilityIdentifier("account-connect")
        .task {
            await w.flow.load(model)
            w.runners = w.flow.runners
            w.suggestName(model)
        }
        .onDisappear { w.flow.wipe() }
    }

    // MARK: 1 provider

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Choose a provider. Ainkrad checks if it can work on this Core.").foregroundStyle(GlassInk.secondary)
            VStack(spacing: Space.s2) {
                ForEach(ProviderLook.ordered(model.providers)) { p in providerRow(p) }
            }
            Text("Agents run their tools on a runner. A provider is ready when a runner that is online can serve it.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            footer(
                back: nil, next: "Next", enabled: model.provider(w.provider).map { w.readiness($0).isReady } ?? false
            ) {
                go(.key)
            }
        }
    }

    private func providerRow(_ p: ProviderItem) -> some View {
        let on = p.id == w.provider
        let r = w.readiness(p)
        return Button {
            w.provider = p.id
            w.labelTouched = false
            w.suggestName(model)
        } label: {
            HStack(spacing: Space.s3) {
                AccTile(provider: p.id)
                VStack(alignment: .leading, spacing: 0) {
                    Text(ProviderWords.title(p)).coreFont(size: MacTextSize.headline, weight: .semibold)
                    Text(ProviderWords.how(p)).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                status(p, r)
            }
            .padding(Space.s3)
            .background(on ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    on ? GlassInk.blue.opacity(0.8) : GlassInk.wellEdge, lineWidth: on ? 1.5 : 1)
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("provider-\(p.id)")
    }

    @ViewBuilder private func status(_ p: ProviderItem, _ r: ProviderReadiness) -> some View {
        switch r {
        case .ready(let runner, _):
            VStack(alignment: .trailing, spacing: 2) {
                StateBadge("Ready", tone: .run, symbol: "checkmark.circle")
                Text("Works on \(runner)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        case .notInstalled:
            VStack(alignment: .trailing, spacing: Space.s1) {
                StateBadge("Not installed", tone: .queue, symbol: "arrow.down.circle")
                AccLink(title: "How to install", symbol: "terminal") { InstallHelpSheet.open(model, p) }
            }
        case .needsRunner:
            VStack(alignment: .trailing, spacing: Space.s1) {
                StateBadge("Needs a runner", tone: .warn, symbol: "server.rack")
                AccLink(title: "Add runner", symbol: "plus") {
                    close()
                    model.openRunners()
                }
            }
        }
    }

    // MARK: 2 key or sign in

    private var keyStep: some View {
        let p = model.provider(w.provider)
        let site = ProviderSites.page(w.provider)
        let shape = ProviderWords.keyShape(w.provider, w.flow.key)
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("Add your \(p.map(ProviderWords.title) ?? "provider") key").coreFont(
                size: MacTextSize.headline, weight: .semibold)
            if let site {
                HStack(spacing: Space.s3) {
                    AccTile(symbol: "link", provider: nil)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Open \(site.name)").fontWeight(.semibold)
                        Text("Go to API keys, choose Create key, and copy it. Ainkrad never sees your password.")
                            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.s2)
                    AppActionTile(title: "Open", symbol: "arrow.up.right.square", key: "⌘O", hue: GlassInk.blue) {
                        model.opener(site.url)
                    }
                    .keyboardShortcut("o", modifiers: .command)
                }
                .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.cardMac))
            }
            if w.flow.needsGate { gateCard }
            HStack(alignment: .bottom, spacing: Space.s2) {
                CoreSecureField("Your key", placeholder: "Paste your key", text: $w.flow.key, autofocus: true)
                    .accessibilityIdentifier("account-key")
                AccLink(title: "Paste", symbol: "doc.on.clipboard") { w.flow.paste() }
            }
            if let shape {
                Label(shape.text, systemImage: shape.ok ? "checkmark.circle" : "exclamationmark.triangle")
                    .coreFont(size: MacTextSize.meta)
                    .foregroundStyle(shape.ok ? GlassInk.green : GlassInk.orangeInk)
            }
            if let n = w.flow.gateNote { AccIssue(text: n) }
            footer(
                back: .provider, next: "Next",
                enabled: !w.flow.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !w.flow.needsGate
            ) { go(.name) }
        }
    }

    private var gateCard: some View {
        HStack(spacing: Space.s3) {
            IconTile("key.fill", hue: GlassInk.blue, size: 36, bounce: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("Turn on keys for accounts").coreFont(size: MacTextSize.headline, weight: .semibold)
                Text("Your Core is set to keep no provider keys. This turns that on.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            Button(w.flow.enabling ? "Turning on…" : "Turn on") { Task { await w.flow.enableKeys(model) } }
                .buttonStyle(CoreButtonStyle(.prominent)).disabled(w.flow.enabling)
        }
        .padding(Space.s3)
        .background(GlassInk.blue.opacity(0.12), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.4), lineWidth: 1) }
        .accessibilityIdentifier("key-gate")
    }

    @ViewBuilder private var signInStep: some View {
        if let p = model.provider(w.provider) {
            VStack(alignment: .leading, spacing: Space.s3) {
                SubscriptionSignIn(model: model, provider: p, close: close).id(w.provider)
                if model.signIn == nil {
                    Text(
                        "A Claude plan gets its own pool and goes to the end of the order. Drag it in Accounts to move it."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    HStack {
                        Button("Back") { go(.provider) }.buttonStyle(.coreSecondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: 3 name and limit

    private var nameStep: some View {
        let slug = w.flow.slugged
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("Name it and set a limit").coreFont(size: MacTextSize.headline, weight: .semibold)
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreTextField(
                    "Name", placeholder: "claude-work",
                    text: Binding(
                        get: { w.flow.label },
                        set: {
                            w.flow.label = $0
                            w.labelTouched = true
                        }),
                    error: w.flow.labelOK || w.flow.label.isEmpty ? nil : "Start the name with a letter.")
                if w.flow.labelOK, slug != w.flow.label {
                    Text("Shown as “\(slug)” everywhere. Ainkrad makes the short name for you.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreTextField(
                    "Monthly limit", placeholder: "20", text: $w.limitText,
                    error: w.limit == nil ? "Type a dollar amount, or 0 for no limit." : nil, suffix: "USD")
                Text("Agents stop using it when it reaches this. You can change it later. 0 means no limit.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if case .ready(let runner, _) = model.provider(w.provider).map({ w.readiness($0) }) ?? .needsRunner {
                Label("The key is checked on \(runner) when you add it.", systemImage: "checkmark.shield")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            HStack(spacing: Space.s2) {
                Button("Back") { go(.key) }.buttonStyle(.coreSecondary)
                Spacer(minLength: 0)
                if w.advanced {
                    Button("Add with the defaults") { add() }.buttonStyle(.coreSecondary).disabled(!canAdd)
                } else {
                    Button("Choose where it goes…") { go(.place) }.buttonStyle(.coreSecondary).disabled(!canAdd)
                }
                if w.advanced {
                    Button("Choose where it goes…") { go(.place) }.buttonStyle(.coreProminent)
                        .coreShortcut(.primary).disabled(!canAdd)
                } else {
                    Button("Add account") { add() }.buttonStyle(.coreProminent).coreShortcut(.primary)
                        .disabled(!canAdd)
                }
            }
        }
    }

    private var canAdd: Bool {
        w.flow.labelOK && w.limit != nil && w.flow.runner != nil && w.nameIssue == nil
    }

    // MARK: 4 where does it go

    private var placeStep: some View {
        let seats = w.seats(model)
        let issue = w.issue(model)
        return VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where does it go?").coreFont(size: MacTextSize.headline, weight: .semibold)
                Text("Agents try accounts in an order. Most people keep the defaults.")
                    .foregroundStyle(GlassInk.secondary)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    heading("Pool", "accounts of one provider that share the work")
                    radio("Default pool for \(model.providerName(w.provider))", w.poolPick == .standard) {
                        w.poolPick = .standard
                    }
                    ForEach(model.pools(for: w.provider).filter { !$0.isDefault }) { p in
                        radio("Pool “\(p.name)”", w.poolPick == .existing(p.id)) { w.poolPick = .existing(p.id) }
                    }
                    radio("New pool…", isNewPool) { w.poolPick = .new(w.newPoolName) }
                    if isNewPool {
                        CoreTextField(
                            "Pool name", placeholder: "team-keys", text: $w.newPoolName
                        )
                        .onChange(of: w.newPoolName) { _, v in w.poolPick = .new(v) }
                    }
                    heading("Order", "the list agents try, one place after another").padding(.top, Space.s2)
                    radio("Default order", w.chainPick == .standard) { w.chainPick = .standard }
                    ForEach(model.chains.filter { !$0.isDefault }) { c in
                        radio("Order “\(c.name)”", w.chainPick == .existing(c.id)) { w.chainPick = .existing(c.id) }
                    }
                    radio("New order…", isNewChain) { w.chainPick = .new(w.newChainName) }
                    if isNewChain {
                        CoreTextField("Order name", placeholder: "night-work", text: $w.newChainName)
                            .onChange(of: w.newChainName) { _, v in w.chainPick = .new(v) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.s2) {
                    heading("Position", "drag to move, or use the arrows")
                    ForEach(Array(seats.enumerated()), id: \.element.id) { i, seat in
                        seatRow(i, seat, count: seats.count)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(Placement.preview(seats)).fixedSize(horizontal: false, vertical: true)
                .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                .background(GlassInk.wellHover, in: coreShape(Radius.control))
                .accessibilityIdentifier("order-preview")
            if let issue { AccIssue(text: issue) }
            if let n = w.nameIssue { AccIssue(text: n) }
            HStack(spacing: Space.s2) {
                Button("Back") { go(.name) }.buttonStyle(.coreSecondary)
                Spacer(minLength: 0)
                Button("Add account") { add() }.buttonStyle(.coreProminent).coreShortcut(.primary)
                    .disabled(!canAdd || issue != nil)
            }
        }
    }

    private var isNewPool: Bool { if case .new = w.poolPick { true } else { false } }
    private var isNewChain: Bool { if case .new = w.chainPick { true } else { false } }

    private func heading(_ title: String, _ sub: String) -> some View {
        (Text(title).fontWeight(.semibold) + Text("  ") + Text(sub).foregroundStyle(GlassInk.secondary))
            .coreFont(size: MacTextSize.meta)
    }

    private func radio(_ title: String, _ on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack(spacing: Space.s2) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? GlassInk.blueInk : GlassInk.secondary)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(Space.s2)
            .background(on ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control))
            .overlay {
                coreShape(Radius.control).strokeBorder(on ? GlassInk.blue.opacity(0.8) : .clear, lineWidth: 1.5)
            }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func seatRow(_ i: Int, _ seat: OrderSeat, count: Int) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "line.3.horizontal").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            Text("\(i + 1)").coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(seat.isNew ? GlassInk.blue : GlassInk.track, in: coreShape(6))
            Text(seat.title).fontWeight(seat.isNew ? .semibold : .regular).lineLimit(1)
            if seat.isNew {
                Text(Placement.positionWords(i, in: w.seats(model))).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
            if seat.isNew {
                Button {
                    w.position = max(i - 1, 0)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain).disabled(i == 0).help("Move earlier").accessibilityLabel("Move earlier")
                Button {
                    w.position = min(i + 1, count - 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain).disabled(i == count - 1).help("Move later").accessibilityLabel("Move later")
            }
        }
        .padding(Space.s2)
        .background(seat.isNew ? GlassInk.blue.opacity(0.14) : GlassInk.well, in: coreShape(Radius.control))
        .modifier(NewSeatDrag(isNew: seat.isNew, index: i) { w.position = $0 })
    }

    // MARK: outcome

    @ViewBuilder private var outcome: some View {
        switch w.flow.stage {
        case .form: EmptyView()
        case .working(let line):
            VStack(spacing: Space.s3) {
                Text(line).coreFont(size: MacTextSize.headline, weight: .semibold)
                CoreBusyBar().frame(maxWidth: Space.s8 * 6)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Space.s4)
            .accessibilityIdentifier("key-working")
        case .done(let id, let ms, _):
            let a = model.account(id)
            let place = a.flatMap { Placement.usedWords(seat: model.seatIndex(of: $0)) }?.lowercased()
            VStack(spacing: Space.s3) {
                IconTile("checkmark.seal.fill", hue: GlassInk.green, size: 64, bounce: true)
                Text("\(a?.label ?? w.flow.slugged) works for agents").coreFont(size: MacTextSize.large, weight: .bold)
                Text(
                    "\(place.map { "It is \($0.replacingOccurrences(of: "used ", with: "")) in the order" } ?? "It is added"), with a \(w.limit.map(Placement.limitWords) ?? "default") monthly limit. It answered in \(ms) ms."
                )
                .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                HStack(spacing: Space.s2) {
                    Button("Open account") {
                        close()
                        model.show(.accounts, account: id)
                    }
                    .buttonStyle(.coreSecondary)
                    Spacer(minLength: 0)
                    Button("Done", action: close).buttonStyle(.coreProminent).coreShortcut(.primary)
                }
            }
            .frame(maxWidth: .infinity).accessibilityIdentifier("key-done")
        case .failed(let why, let id):
            VStack(spacing: Space.s3) {
                IconTile("exclamationmark.triangle.fill", hue: GlassInk.red, size: 64, bounce: false)
                Text("Couldn't connect").coreFont(size: MacTextSize.large, weight: .bold)
                Text(why).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) {
                    if id != nil {
                        Button("Remove account") { Task { await w.flow.remove(model) } }.buttonStyle(.coreSecondary)
                        Spacer(minLength: Space.s3)
                        Button("Try another key") {
                            w.flow.tryAnother()
                            w.step = .key
                        }
                        .buttonStyle(.coreProminent)
                    } else {
                        Button("Close", action: close).buttonStyle(.coreSecondary)
                        Spacer(minLength: Space.s3)
                        Button("Try again") { w.flow.stage = .form }.buttonStyle(.coreProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity).accessibilityIdentifier("key-failed")
        }
    }

    // MARK: pieces

    private func go(_ s: ConnectWizardState.Step) {
        withAnimation(.smooth(duration: 0.3)) { w.step = s }
        if s == .name { w.suggestName(model) }
        if case .ready(_, let id) = model.provider(w.provider).map({ w.readiness($0) }) ?? .needsRunner {
            w.flow.runner = id
        }
    }

    private func add() {
        w.flow.placement = w.placement()
        Task { await w.flow.connect(model, provider: w.provider) }
    }

    private func footer(back: ConnectWizardState.Step?, next: String, enabled: Bool, _ run: @escaping () -> Void)
        -> some View
    {
        HStack(spacing: Space.s2) {
            if let back {
                Button("Back") { go(back) }.buttonStyle(.coreSecondary)
            } else {
                Button("Cancel", action: close).buttonStyle(.coreSecondary).coreShortcut(.cancel)
            }
            Spacer(minLength: 0)
            Button(next, action: run).buttonStyle(.coreProminent).coreShortcut(.primary).disabled(!enabled)
        }
    }
}

/// The new account's row can be dragged onto another row; the position it lands on is its seat.
private struct NewSeatDrag: ViewModifier {
    let isNew: Bool
    let index: Int
    let drop: (Int) -> Void

    func body(content: Content) -> some View {
        if isNew {
            content.draggable("new") { Text("New account").padding(Space.s2) }
        } else {
            content.dropDestination(for: String.self) { items, _ in
                guard items.first == "new" else { return false }
                drop(index)
                return true
            }
        }
    }
}

/// How to install: the exact commands for the provider's tool on a runner, until Core can install it in one click.
struct InstallHelpSheet: View {
    let provider: ProviderItem
    let close: () -> Void

    @MainActor static func open(_ m: AccountsModel, _ p: ProviderItem) {
        AccountDialogs.present(m, "provider-install-help") { close in InstallHelpSheet(provider: p, close: close) }
    }

    var body: some View {
        CoreDialogPanel("Install \(ProviderWords.title(provider)) on a runner", width: Space.s8 * 16) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("One-click install is not in Core yet. Run these on the runner's machine, in order.")
                    .foregroundStyle(GlassInk.secondary)
                ForEach(Array(InstallHelp.steps(provider).enumerated()), id: \.element.id) { i, s in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("\(i + 1). \(s.title)").fontWeight(.semibold)
                        Text(s.detail).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                        if let c = s.command {
                            HStack(alignment: .top, spacing: Space.s2) {
                                Text(c).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                AccLink(title: "Copy", symbol: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(c, forType: .string)
                                }
                            }
                            .padding(Space.s2).background(GlassInk.wellHover, in: coreShape(Radius.control))
                        }
                    }
                }
                Text("This window updates by itself: when a runner can serve the provider, it says Ready.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                HStack {
                    Spacer(minLength: 0)
                    Button("Done", action: close).buttonStyle(.coreProminent).coreShortcut(.primary)
                }
            }
        }
        .accessibilityIdentifier("provider-install-help")
    }
}
