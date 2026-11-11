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

/// The exact commands that put a provider's tool on a runner. The one-click install needs a Core API that does not exist
/// yet (N22 gap), so the sheet shows these instead.
enum InstallHelp {
    struct Step: Equatable, Identifiable {
        var id: String { title }
        let title: String
        let detail: String
        let command: String?
    }

    static func steps(_ p: ProviderItem) -> [Step] {
        var out: [Step] = []
        switch p.harness {
        case "claude":
            out.append(
                Step(
                    title: "Install Claude Code on the runner",
                    detail: "Run this on the runner's machine. The version is pinned.",
                    command: "sudo npm install -g @anthropic-ai/claude-code@2.1.318"))
            out.append(
                Step(
                    title: "Stop it from updating itself",
                    detail: "Core uses the version above. Updates would change it under your agents.",
                    command:
                        "sudo mkdir -p /etc/claude-code && echo '{\"env\":{\"DISABLE_AUTOUPDATER\":\"1\"}}' | sudo tee /etc/claude-code/managed-settings.json"
                ))
        case "codex":
            out.append(
                Step(
                    title: "Install Codex on the runner", detail: "Run this on the runner's machine.",
                    command: "sudo npm install -g @openai/codex"))
        default:
            out.append(
                Step(
                    title: "Install \(p.harness) on the runner",
                    detail: "Install it so that `\(p.harness)` is on the runner's PATH.", command: nil))
        }
        out.append(
            Step(
                title: "Turn agents on for the runner",
                detail:
                    "A runner offers accounts only with agents on. Add --enable-agents to how the runner starts, then restart it.",
                command: "ainkrad-runner connect --enable-agents"))
        return out
    }
}
