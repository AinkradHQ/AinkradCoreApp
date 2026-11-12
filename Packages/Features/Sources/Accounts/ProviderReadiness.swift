import Foundation

/// What a provider needs from a runner, from what the runners advertise (`GET /runners`, their drivers' commands). The Core
/// has no list of the tools installed on a runner, so "installed" means: an online runner offers the capability the provider
/// needs (the auth gateway for an API key, the sign-in driver for a Claude plan), which a runner has only when agents are on.
enum ProviderReadiness: Equatable, Sendable {
    /// Some online runner can serve it; its name.
    case ready(runner: String, runnerID: String)
    /// A runner is online but cannot serve it yet: the tool or the agents are missing there.
    case notInstalled
    /// No runner is online.
    case needsRunner

    static func needs(_ p: ProviderItem) -> [String] {
        p.loginMethods.contains("browser_code") ? ["login"] : ["gateway"]
    }

    static func of(_ p: ProviderItem, runners: [AccountRunner]) -> ProviderReadiness {
        let online = runners.filter(\.online)
        if online.isEmpty { return .needsRunner }
        let need = Set(needs(p))
        if let r = online.first(where: { need.isSubset(of: $0.commands) }) {
            return .ready(runner: r.name, runnerID: r.id)
        }
        return .notInstalled
    }

    var isReady: Bool { if case .ready = self { true } else { false } }
}

/// The words of the provider rows.
enum ProviderWords {
    static func title(_ p: ProviderItem) -> String {
        switch p.id {
        case "anthropic": "Claude (Anthropic)"
        case "claude-sub": "Claude"
        case "openai": "OpenAI"
        case "google", "gemini": "Gemini"
        default: p.name
        }
    }

    static func how(_ p: ProviderItem) -> String {
        p.loginMethods.contains("browser_code") ? "Your Claude plan" : "API key"
    }

    /// The shape of a key, while it is typed: "Looks like an Anthropic key", or nil when nothing is known or typed.
    static func keyShape(_ provider: String, _ key: String) -> (text: String, ok: Bool)? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let known: [String: (prefix: String, name: String)] = [
            "anthropic": ("sk-ant-", "an Anthropic"), "openai": ("sk-", "an OpenAI"), "google": ("AIza", "a Google"),
        ]
        guard !k.isEmpty, let m = known[provider] else { return nil }
        return k.hasPrefix(m.prefix)
            ? ("Looks like \(m.name) key", true)
            : ("This does not look like \(m.name) key. Check you copied all of it.", false)
    }
}
