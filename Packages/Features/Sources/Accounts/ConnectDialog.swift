import CoreUI
import SwiftUI

/// Connect an account, or use a new key. Sign-in happens on the provider's own page: this dialog opens it and never holds a
/// key, a token or a field to type one in.
struct ConnectDialog: View {
    let model: AccountsModel
    let replacing: AccountItem?
    let close: () -> Void
    @State private var provider: String

    init(model: AccountsModel, provider: String?, replacing: AccountItem?, close: @escaping () -> Void) {
        self.model = model
        self.replacing = replacing
        self.close = close
        _provider = State(
            initialValue: provider ?? model.providers.first { ProviderSites.page($0.id) != nil }?.id ?? model.providers
                .first?.id ?? "")
    }

    var body: some View {
        let site = ProviderSites.page(provider)
        let hue = ProviderLook.hue(provider)
        CoreDialogPanel(replacing.map { "New key for \($0.label)" } ?? "Connect an account") {
            VStack(alignment: .leading, spacing: Space.s4) {
                if replacing == nil {
                    HStack(spacing: Space.s2) {
                        ForEach(model.providers) { p in
                            ProviderChoice(provider: p, on: p.id == provider, lens: lens) {
                                withAnimation(.spring(duration: 0.35, bounce: 0.25)) { provider = p.id }
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
                        2, "Add it to your Core", hue: hue, on: false, last: true,
                        detail:
                            "Keys are added from an admin computer, not from this app: there is no place here to type one, so a key can't leak from this Mac."
                    ) { EmptyView() }
                }
                .id(provider)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                AccDialogButtons(confirm: "Done", cancel: close, run: close)
            }
        }
        .accessibilityIdentifier("account-connect")
    }

    @Namespace private var lens
    @FocusState private var keys: Bool

    private func move(_ step: Int) -> KeyPress.Result {
        let ids = model.providers.map(\.id)
        guard let i = ids.firstIndex(of: provider) else { return .ignored }
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { provider = ids[min(max(i + step, 0), ids.count - 1)] }
        return .handled
    }

    /// A step on a short timeline: its number tile (lit when it is yours to do), a line down to the next step.
    private func step<C: View>(
        _ n: Int, _ title: String, hue: Color, on: Bool, last: Bool = false, detail: String,
        @ViewBuilder _ action: () -> C
    ) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                Image(systemName: on ? "\(n).square.fill" : "lock.square.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(on ? hue : GlassInk.slate)
                    .shadow(color: hue.opacity(on ? 0.5 : 0), radius: 8)
                    .symbolEffect(.bounce, value: provider)
                if !last {
                    coreShape(1).fill(
                        LinearGradient(colors: [hue, GlassInk.track], startPoint: .top, endPoint: .bottom)
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
        let hue = ProviderLook.hue(provider.id)
        Button(action: pick) {
            VStack(spacing: Space.s2) {
                AccTile(large: true, provider: provider.id).symbolEffect(.bounce, value: on)
                Text(provider.name).font(.system(size: MacTextSize.body, weight: .semibold)).lineLimit(1)
                Text("API key").font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            }
            .foregroundStyle(GlassInk.primary)
            .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
            .background {
                if on {
                    coreShape(Radius.cardMac).fill(hue.opacity(0.22))
                        .shadow(color: hue.opacity(0.45), radius: 14)
                        .matchedGeometryEffect(id: "lens", in: lens)
                } else {
                    coreShape(Radius.cardMac).fill(hovering ? GlassInk.wellHover : GlassInk.well)
                }
            }
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    on ? hue.opacity(0.75) : GlassInk.wellEdge, lineWidth: on ? 1.5 : 1)
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(on ? 1.03 : hovering ? 1.02 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
        .accessibilityLabel(provider.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
