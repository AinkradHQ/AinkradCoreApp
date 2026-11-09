import AppKit
import CoreUI
import SwiftUI

/// Connect an account, or use a new key. An API key is pasted here and goes straight to the Core (see `KeyEntryFlow`);
/// a subscription signs in on the provider's own page.
struct ConnectDialog: View {
    let model: AccountsModel
    let replacing: AccountItem?
    let close: () -> Void
    @State private var provider: String
    /// The accounts that were there when the dialog opened: one that is not in it has arrived.
    @State private var flow: KeyEntryFlow
    @Environment(\.corePalette) private var palette

    init(
        model: AccountsModel, provider: String?, replacing: AccountItem?, flow: KeyEntryFlow? = nil,
        close: @escaping () -> Void
    ) {
        self.model = model
        self.replacing = replacing
        self.close = close
        _flow = State(initialValue: flow ?? KeyEntryFlow(target: replacing))
        _provider = State(
            initialValue: provider ?? model.providers.first { ProviderSites.page($0.id) != nil }?.id ?? model.providers
                .first?.id ?? "")
    }

    var body: some View {
        let site = ProviderSites.page(provider)
        let hue = GlassInk.blue
        CoreDialogPanel(replacing.map { "New key for \($0.label)" } ?? "Connect an account") {
            VStack(alignment: .leading, spacing: Space.s4) {
                if replacing == nil && model.signIn == nil && flow.stage == .form && flow.target == nil {
                    HStack(spacing: Space.s2) {
                        ForEach(ProviderLook.ordered(model.providers)) { p in
                            ProviderChoice(provider: p, on: p.id == provider, lens: lens) {
                                provider = p.id
                            }
                        }
                    }
                    .focusable()
                    .focused($keys)
                    .focusEffectDisabled()
                    .coreSideKeys { move($0) }
                    .onAppear { keys = true }
                }
                if let p = model.provider(provider), p.loginMethods.contains("browser_code") {
                    SubscriptionSignIn(model: model, provider: p, close: close).id(provider)
                } else {
                    if flow.stage == .form {
                        VStack(alignment: .leading, spacing: 0) {
                            step(
                                1, "Get a key", hue: hue, on: true,
                                detail: site.map {
                                    "Create an API key in \($0.name). Ainkrad never sees your password."
                                }
                                    ?? "Open this provider's own site and create a key there."
                            ) {
                                if let site {
                                    AppActionTile(
                                        title: "Open \(site.name)", symbol: "arrow.up.right.square", key: "⌘O",
                                        hue: hue, prominent: true
                                    ) {
                                        model.opener(site.url)
                                    }
                                    .keyboardShortcut("o", modifiers: .command)
                                    .help(site.url.absoluteString)
                                }
                            }
                            step(
                                2, "Add it to your Core", hue: hue, on: true, last: true,
                                detail: "The key goes straight to your Core and is never shown again."
                            ) { keyStep }
                        }
                        .id(provider)
                        .transition(.opacity)
                    } else {
                        outcome
                    }
                }
            }
        }
        .accessibilityIdentifier("account-connect")
        .task { await flow.load(model) }
        .onDisappear { flow.wipe() }
    }

    private var rotating: Bool { flow.target != nil }

    @ViewBuilder private var keyStep: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if flow.needsGate { gateCard }
            if !rotating {
                CoreTextField("Name", placeholder: "Work", text: $flow.label, error: nil)
            }
            HStack(alignment: .bottom, spacing: Space.s2) {
                CoreSecureField("Key", placeholder: "Paste your key", text: $flow.key, autofocus: true)
                    .accessibilityIdentifier("account-key")
                AccLink(title: "Paste", symbol: "doc.on.clipboard") { flow.paste() }
            }
            if !rotating { runnerStep }
            if let n = flow.gateNote { AccIssue(text: n) }
            AccDialogButtons(
                confirm: rotating ? "Save key" : "Connect", enabled: flow.ready(rotating: rotating), cancel: close
            ) {
                Task { await flow.connect(model, provider: provider) }
            }
        }
    }

    /// The runner that checks the key. Required: with none online there is nothing to check it with.
    @ViewBuilder private var runnerStep: some View {
        if flow.runners.contains(where: \.online) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Check the key on").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s2)], spacing: Space.s2) {
                    ForEach(flow.runners) { r in
                        AccPick(
                            title: r.name, sub: r.online ? "Online" : "Offline", symbol: "server.rack",
                            hue: GlassInk.blue, on: flow.runner == r.id, enabled: r.online
                        ) { flow.runner = r.id }
                    }
                }
            }
        } else {
            HStack(spacing: Space.s2) {
                Label("No runner is online to check the key.", systemImage: "server.rack")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: 0)
                AccLink(title: "Open runners", symbol: "arrow.up.right") {
                    close()
                    model.openRunners()
                }
            }
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
            Button(flow.enabling ? "Turning on…" : "Turn on") { Task { await flow.enableKeys(model) } }
                .buttonStyle(CoreButtonStyle(.prominent)).disabled(flow.enabling)
        }
        .padding(Space.s3)
        .background(GlassInk.blue.opacity(0.12), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.4), lineWidth: 1) }
        .accessibilityIdentifier("key-gate")
    }

    @ViewBuilder private var outcome: some View {
        switch flow.stage {
        case .form: EmptyView()
        case .working(let line):
            VStack(spacing: Space.s3) {
                Text(line).coreFont(size: MacTextSize.headline, weight: .semibold)
                CoreBusyBar().frame(maxWidth: Space.s8 * 6)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Space.s4)
            .accessibilityIdentifier("key-working")
        case .done(let id, let ms, let note):
            VStack(spacing: Space.s3) {
                IconTile("checkmark.seal.fill", hue: GlassInk.green, size: 64, bounce: true)
                Text("Connected").coreFont(size: MacTextSize.large, weight: .bold)
                Text("\(note) It answered in \(ms) ms.").foregroundStyle(GlassInk.secondary)
                    .multilineTextAlignment(.center)
                AccDialogButtons(confirm: "Open account", cancelTitle: "Close", cancel: close) {
                    close()
                    model.show(.accounts, account: id)
                }
            }
            .frame(maxWidth: .infinity).accessibilityIdentifier("key-done")
        case .failed(let why, let id):
            VStack(spacing: Space.s3) {
                IconTile("exclamationmark.triangle.fill", hue: GlassInk.red, size: 64, bounce: false)
                Text("Couldn't connect").coreFont(size: MacTextSize.large, weight: .bold)
                Text(why).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if id != nil {
                    HStack(spacing: Space.s2) {
                        Button("Remove account") { Task { await flow.remove(model) } }
                            .buttonStyle(CoreButtonStyle(.secondary))
                        Spacer(minLength: Space.s3)
                        Button("Try another key") { flow.tryAnother() }.buttonStyle(CoreButtonStyle(.prominent))
                    }
                } else {
                    HStack(spacing: Space.s2) {
                        Button("Close", action: close).buttonStyle(CoreButtonStyle(.secondary))
                        Spacer(minLength: Space.s3)
                        Button("Try again") { flow.stage = .form }.buttonStyle(CoreButtonStyle(.prominent))
                    }
                }
            }
            .frame(maxWidth: .infinity).accessibilityIdentifier("key-failed")
        }
    }

    @Namespace private var lens
    @FocusState private var keys: Bool

    private func move(_ step: Int) -> KeyPress.Result {
        let ids = ProviderLook.ordered(model.providers).map(\.id)
        guard let i = ids.firstIndex(of: provider) else { return .ignored }
        provider = ids[min(max(i + step, 0), ids.count - 1)]
        return .handled
    }

    /// A step on a short timeline: its number tile (lit when it is yours to do), a line down to the next step.
    private func step<C: View>(
        _ n: Int, _ title: String, hue: Color, on: Bool, last: Bool = false, detail: String,
        @ViewBuilder _ action: () -> C
    ) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                Image(systemName: on ? "\(n).square.fill" : "checkmark.square.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(on ? GlassInk.blueInk : GlassInk.slate)
                if !last {
                    coreShape(1).fill(
                        LinearGradient(colors: [GlassInk.blue, GlassInk.track], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 2).frame(minHeight: 24).padding(.vertical, 4)
                }
            }
            .frame(width: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
                Text(detail).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                action()
            }
            .padding(.bottom, last ? 0 : Space.s3)
        }
        .fixedSize(horizontal: false, vertical: true)  // the line runs to the next step, no further
        .accessibilityElement(children: .contain)
    }
}

/// A provider as a choice card: its tile in its colour, the name and how it signs in. The picked one glows in the
/// provider's colour and the light glides between cards; ← → move it.
private struct ProviderChoice: View {
    let provider: ProviderItem
    let on: Bool
    let lens: Namespace.ID
    let pick: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: pick) {
            VStack(spacing: Space.s2) {
                AccTile(large: true, provider: provider.id)
                Text(ProviderLook.short(provider.id, provider.name)).coreFont(size: MacTextSize.body, weight: .semibold)
                    .lineLimit(1)
                Text(provider.loginMethods.contains("browser_code") ? "Subscription" : "API key")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            .foregroundStyle(GlassInk.primary)
            .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
            .background {
                if on {
                    coreShape(Radius.cardMac).fill(GlassInk.blue.opacity(0.22))
                        .matchedGeometryEffect(id: "lens", in: lens)
                } else {
                    coreShape(Radius.cardMac).fill(hovering ? GlassInk.wellHover : GlassInk.well)
                }
            }
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    on ? GlassInk.blue.opacity(0.75) : GlassInk.wellEdge, lineWidth: on ? 1.5 : 1)
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityLabel(provider.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
