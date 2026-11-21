import CoreUI
import SwiftUI

extension AccountsModel {
    /// How many accounts the Core holds, for the setup's last page.
    public var accountCount: Int { accounts.count }
}

/// The AI page of setup (E3-1, approved 02 Setup): connect as many accounts as you like and see the ones connected. Adding
/// one is the Accounts app's own flow (`AddAccountDialog`, embedded), so every provider the Core offers works here the same
/// way: an API key, or a subscription sign-in (Claude, ChatGPT / Codex, Antigravity, OpenCode).
public struct SetupAIStep: View {
    let model: AccountsModel
    /// True while a provider is being added: setup steps its own Back / Continue aside, so there is one row of buttons.
    @Binding var inFlow: Bool
    public init(model: AccountsModel, inFlow: Binding<Bool>) {
        self.model = model
        self._inFlow = inFlow
    }

    @State private var adding = false
    @Environment(\.corePalette) private var palette

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if !model.accounts.isEmpty && !adding {
                list
            } else {
                AddAccountDialog(
                    model: model, provider: nil,
                    close: {
                        adding = false
                        inFlow = false
                    },
                    embedded: true, inFlow: $inFlow)
            }
        }
        .task { await model.reload() }
    }

    // MARK: connected (approved 02 Setup, "Your AI accounts")

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(model.accounts) { a in
                let name = ProviderCatalog.name(a.provider, fallback: model.providerName(a.provider))
                HStack(spacing: Space.s3) {
                    ProviderTile(name: name)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.title(a)).coreFont(size: MacTextSize.body, weight: .semibold)
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
            HStack {
                Button {
                    adding = true
                } label: {
                    Label("Add another", systemImage: "plus")
                }
                .coreGlassButton()
                .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
                Spacer()
            }
        }
    }
}
