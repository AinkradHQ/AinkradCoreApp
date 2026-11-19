import CoreUI
import SwiftUI

/// Settings, Apps, Accounts, Options (E2-4). "Ask Touch ID to reveal keys" decides whether a key's last characters show on its
/// page straight away or only after Touch ID (`AccountDetailView.keyTile`). "Default AI account" is the provider the Connect
/// wizard starts on (`ConnectWizard`).
@MainActor enum AccountsOptions {
    static var options: AppOptions { .shared("accounts") }
    static let touchID = "touchID"
    static let provider = "provider"

    /// The mockup's three choices and the Core provider ids each one stands for.
    static let providers: [(id: String, title: String, ids: [String])] = [
        ("claude", "Claude", ["anthropic", "claude-sub"]), ("openai", "OpenAI", ["openai"]),
        ("gemini", "Gemini", ["google", "gemini"]),
    ]

    static var asksTouchID: Bool { options.bool(touchID, true) }

    /// The provider the wizard starts on: the chosen family's first provider the Core offers, else nil.
    static func startProvider(_ choice: String, among offered: [String]) -> String? {
        providers.first { $0.id == choice }?.ids.first { offered.contains($0) }
    }
}

struct AccountsOptionsTab: View {
    @Environment(\.coreAccent) private var paneAccent
    let options = AccountsOptions.options

    var body: some View {
        GlassSection("Accounts", sub: "Keys and where you start", symbol: "creditcard", hue: GlassInk.accent(paneAccent)) {
            VStack(spacing: Space.s2) {
                OptionSwitchRow(
                    "Ask Touch ID to reveal keys", sub: "A key's last characters show only after Touch ID",
                    symbol: "touchid", isOn: options.flag(AccountsOptions.touchID, true))
                OptionSelectRow(
                    "Default AI account", sub: "The provider Connect starts on", symbol: "person.crop.circle",
                    selection: options.text(AccountsOptions.provider, "claude"),
                    options: AccountsOptions.providers.map { CoreSelectOption($0.id, $0.title) })
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
