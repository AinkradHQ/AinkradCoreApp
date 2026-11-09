import CoreUI
import AppKit
import SwiftUI

/// Connect an account, or use a new key. Sign-in happens on the provider's own page: this dialog opens it and never holds a
/// key, a token or a field to type one in.
struct ConnectDialog: View {
    let model: AccountsModel
    let replacing: AccountItem?
    let close: () -> Void
    @State private var provider: String
    /// The accounts that were there when the dialog opened: one that is not in it has arrived.
    @State private var known: Set<Int64>
    @State private var copied = false
    @Environment(\.corePalette) private var palette

    init(model: AccountsModel, provider: String?, replacing: AccountItem?, close: @escaping () -> Void) {
        self.model = model
        self.replacing = replacing
        self.close = close
        _known = State(initialValue: Set(model.accounts.map(\.id)))
        _provider = State(
            initialValue: provider ?? model.providers.first { ProviderSites.page($0.id) != nil }?.id ?? model.providers
                .first?.id ?? "")
    }

    var body: some View {
        let site = ProviderSites.page(provider)
        let hue = GlassInk.blue
        CoreDialogPanel(replacing.map { "New key for \($0.label)" } ?? "Connect an account") {
            VStack(alignment: .leading, spacing: Space.s4) {
                if replacing == nil && model.signIn == nil {
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
                    .onKeyPress(.leftArrow) { move(-1) }
                    .onKeyPress(.rightArrow) { move(1) }
                    .onAppear { keys = true }
                }
                if let p = model.provider(provider), p.loginMethods.contains("browser_code") {
                    SubscriptionSignIn(model: model, provider: p, close: close).id(provider)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        step(
                            1, "Get a key", hue: hue, on: true,
                            detail: site.map { "Create an API key in \($0.name). Ainkrad never sees your password." }
                                ?? "Open this provider's own site and create a key there."
                        ) {
                            if let site {
                                AppActionTile(
                                    title: "Open \(site.name)", symbol: "arrow.up.right.square", key: "⌘O", hue: hue,
                                    prominent: true
                                ) {
                                    model.opener(site.url)
                                }
                                .keyboardShortcut("o", modifiers: .command)
                                .help(site.url.absoluteString)
                            }
                        }
                        step(
                            2, "Add it to your Core", hue: hue, on: arrived == nil, last: true,
                            detail:
                                "Keys are added from an admin computer, not from this app: there is no place here to type one, so a key can't leak from this Mac. Run this there, with your own admin token and the key."
                        ) {
                            command
                            waiting
                        }
                    }
                    .id(provider)
                    .transition(.opacity)
                    if let arrived {
                        AccDialogButtons(
                            confirm: "Open \(arrived.label)", cancelTitle: "Close", cancel: close
                        ) {
                            close()
                            model.show(.accounts, account: arrived.id)
                        }
                    } else {
                        AccDialogButtons(cancelTitle: "Close", cancel: close)
                    }
                }
            }
        }
        .accessibilityIdentifier("account-connect")
    }

    /// The new account of this provider that showed up since the dialog opened.
    private var arrived: AccountItem? {
        model.accounts.first { !known.contains($0.id) && $0.provider == provider }
    }

    /// The real path today: the Core's own API (`ainkradctl` has no command to add an account). The key is yours to paste
    /// there; this app never sees it.
    private var addCommand: String {
        let label = replacing?.label ?? "Work"
        return """
            curl -X POST "$CORE/api/v1/accounts" -H "Authorization: Bearer $ADMIN_TOKEN" \\
              -H "Content-Type: application/json" \\
              -d '{"provider":"\(provider)","label":"\(label)","value":"<paste the key here>"}'
            """
    }

    private var command: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(addCommand).font(.system(size: MacTextSize.meta, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                .background(GlassInk.well, in: coreShape(Radius.control))
                .overlay { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            AccLink(title: copied ? "Copied" : "Copy command", symbol: copied ? "checkmark" : "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(addCommand, forType: .string)
                copied = true
                CoreAnnounce.post("Command copied")
            }
            .help("Copies the command. It has no key in it.")
        }
    }

    /// Live: turns into the new account when the list changes (events drive it; a slow re-read covers a missed one).
    @ViewBuilder private var waiting: some View {
        if let arrived {
            Label("\(arrived.label) arrived and is in your Core.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(palette.tone(.run).ink)
                .accessibilityIdentifier("connect-arrived")
        } else {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Waiting for the key to arrive").font(.system(size: MacTextSize.meta, weight: .semibold))
                CoreBusyBar().frame(maxWidth: Space.s8 * 5)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("connect-waiting")
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    model.resync()
                }
            }
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
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
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
                Text(ProviderLook.short(provider.id, provider.name)).font(
                    .system(size: MacTextSize.body, weight: .semibold)
                ).lineLimit(1)
                Text(provider.loginMethods.contains("browser_code") ? "Subscription" : "API key")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
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
