import Foundation

/// The pure rules of Add an AI account (approved mockup `Designs/core/0-10/review/ai-accounts`): which providers get a card,
/// what each card says, where a key is made and how it starts, and where a sign-in stands. The Core's own data wins; the
/// small maps here only fill in for a Core that does not say.
enum AddCards {
    /// The mockup's card order. Providers not listed follow in the Core's order, so a new preset still shows.
    static let order = [
        "claude-sub", "codex-sub", "agy-sub",
        "openrouter", "anthropic", "openai", "google", "gemini", "deepseek", "mistral", "xai", "groq", "vercel",
    ]
    private static let faces: [String: (name: String, line: String)] = [
        "claude-sub": ("Claude", "Pro or Max plan"), "codex-sub": ("ChatGPT", "Plus or Pro plan"),
        "agy-sub": ("Google", "Google AI plan"),
        "openrouter": ("OpenRouter", "Hundreds of models, one key"),
        "anthropic": ("Anthropic", "Claude models by API key"),
        "openai": ("OpenAI", "GPT models by API key"), "google": ("Google Gemini", "Gemini models by API key"),
        "gemini": ("Google Gemini", "Gemini models by API key"),
        "deepseek": ("DeepSeek", "Fast, low-cost coding models"),
        "mistral": ("Mistral", "Codestral and Mistral models"), "xai": ("xAI", "Grok models"),
        "groq": ("Groq", "Very fast open models"), "vercel": ("Vercel AI Gateway", "Many providers behind one key"),
    ]
    /// Who a plan signs in with, as the checklist says it ("Sign in to OpenAI").
    private static let who = ["claude-sub": "Claude", "codex-sub": "OpenAI", "agy-sub": "Google"]
    private static let logos = [
        "claude-sub": "claude", "codex-sub": "openai", "agy-sub": "gemini", "anthropic": "anthropic",
        "openai": "openai",
        "google": "gemini", "gemini": "gemini", "openrouter": "openrouter", "deepseek": "deepseek",
        "mistral": "mistral",
        "xai": "x", "groq": "groq", "vercel": "vercel",
    ]
    /// Where each built-in's keys are made, for a Core that does not give `key_url`.
    private static let keyPages = [
        "openrouter": "https://openrouter.ai/keys", "anthropic": "https://console.anthropic.com/settings/keys",
        "openai": "https://platform.openai.com/api-keys", "google": "https://aistudio.google.com/apikey",
        "gemini": "https://aistudio.google.com/apikey", "deepseek": "https://platform.deepseek.com/api_keys",
        "mistral": "https://console.mistral.ai/api-keys", "xai": "https://console.x.ai",
        "groq": "https://console.groq.com/keys", "vercel": "https://vercel.com/ai-gateway",
    ]
    /// How each built-in's keys start, for a Core that gives no `key_hint`. A hint only: it never blocks Add.
    private static let keyStarts = [
        "openrouter": "sk-or-", "anthropic": "sk-ant-", "openai": "sk-", "google": "AIza", "gemini": "AIza",
        "deepseek": "sk-", "xai": "xai-", "groq": "gsk_",
    ]

    /// OpenCode's own login is not a card: the Core flags it `hidden`, and an older Core is matched by the harness.
    static func hidden(_ p: ProviderItem) -> Bool {
        p.hidden || (ProviderCatalog.kind(p) == .subscription && (p.harness == "opencode" || p.id == "opencode-sub"))
    }

    /// The cards of one kind, in the mockup's order.
    static func cards(_ providers: [ProviderItem], _ kind: ProviderKind) -> [ProviderItem] {
        let mine = providers.filter { ProviderCatalog.kind($0) == kind && !hidden($0) }
        let rank = { (p: ProviderItem) in order.firstIndex(of: p.id) ?? order.count }
        return mine.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    static func name(_ p: ProviderItem) -> String { faces[p.id]?.name ?? ProviderCatalog.name(p.id, fallback: p.name) }
    static func line(_ p: ProviderItem) -> String { faces[p.id]?.line ?? ProviderCatalog.blurb(p) }
    static func who(_ p: ProviderItem) -> String { who[p.id] ?? name(p) }
    /// The plan's sign-in carries the small risk line (the mockup has it for Google's plan only).
    static func risky(_ id: String) -> Bool { id == "agy-sub" }
    /// The `ConnLogo` kind: a monochrome mark when there is one, else the id (its first letter).
    static func logo(_ id: String) -> String { logos[id].map { "ai-\($0)" } ?? id }

    static func keyPage(_ p: ProviderItem) -> URL? {
        (p.keyURL ?? keyPages[p.id]).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }

    /// How a key should start, and whether a different start stops Add. Only a user definition's `keyPrefix` is a rule;
    /// a preset's `key_hint` and the built-in map are hints.
    static func keyStart(_ p: ProviderItem) -> (prefix: String?, strict: Bool) {
        if let k = p.keyPrefix, !k.isEmpty { return (k, true) }
        if let h = p.keyHint, !h.isEmpty { return (h, false) }
        return (keyStarts[p.id], false)
    }
}

/// The line under the paste field, as the key is typed.
enum KeyHint: Equatable {
    case waiting(String)
    case looksRight
    case wrongStart(String)

    static func of(_ key: String, prefix: String?, name: String) -> KeyHint {
        switch KeyShape.live(key, prefix: prefix) {
        case .looksValid: .looksRight
        case .wrongPrefix(let p): .wrongStart("\(name) keys start with \(p)")
        case .empty: .waiting(prefix.map { "Starts with \($0)" } ?? "Paste the whole key")
        }
    }

    var words: String {
        switch self {
        case .waiting(let w), .wrongStart(let w): w
        case .looksRight: "Looks right"
        }
    }
}

/// Where a subscription sign-in stands, as the checklist shows it. The Core's `stage` wins; an older Core's is inferred:
/// a page to open, then a code once the provider's CLI asks for one.
enum SignInStep: Equatable, Sendable {
    case starting, chooseMethod, openURL, enterCode, finishing, done, failed

    static func of(_ flow: SignInFlow?, style: SignInStyle) -> SignInStep {
        guard let flow else { return .starting }
        switch flow.stage {
        case .done: return .done
        case .failed: return .failed
        default: break
        }
        if flow.sending { return .finishing }
        switch flow.coreStage {
        case "starting"?: return .starting
        case "open_url"?: return .openURL
        case "enter_code"?: return .enterCode
        case "finishing"?: return .finishing
        default: break
        }
        switch flow.stage {
        case .starting: return .starting
        case .working: return .finishing
        // Claude's CLI asks for the code as soon as its page is open.
        case .open: return style == .paste ? .enterCode : .openURL
        case .guided(let u):
            if asksForCode(flow.screen) { return .enterCode }
            // An older Core leaves the CLI's own menu up (Antigravity's login method): the person picks, never the app. A
            // menu already answered here is not asked again; a new one is.
            let menu = GuidedMenu.options(flow.screen)
            if u == nil, flow.deviceCode == nil, !menu.isEmpty, menu != flow.pickedMenu { return .chooseMethod }
            return .openURL
        case .done, .failed: return .starting  // handled above
        }
    }

    /// The runner's screen ends on a request for a code ("Paste the authorization code").
    static func asksForCode(_ lines: [String]) -> Bool {
        lines.reversed().lazy.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3)
            .contains { $0.lowercased().contains("code") }
    }

    /// The page the sign-in opened, to open again.
    static func page(_ flow: SignInFlow?) -> URL? {
        switch flow?.stage {
        case .open(let u)?: u
        case .guided(let u)?: u
        default: nil
        }
    }
}

/// One choice of a sign-in CLI's numbered menu, and the line that picks it (its number, as the person would type it).
struct MenuOption: Equatable, Sendable {
    let number: String
    let title: String
}

/// The numbered menu a sign-in CLI is waiting on, read from its screen: the last run numbered 1, 2, … with at least two
/// choices. Items may sit on their own lines (`> 1. Google OAuth`) or on one squashed line. The menu must be the screen's
/// tail: after its last choice only blank lines and navigation hints may follow, or the CLI has moved on.
enum GuidedMenu {
    static func options(_ lines: [String]) -> [MenuOption] {
        var found: [(option: MenuOption, line: Int)] = []
        for (n, line) in lines.enumerated() {
            let marks = line.matches(of: #/(\d{1,2})[.)]\s+/#)
            for (i, m) in marks.enumerated() {
                // The number starts the line or follows a space or a cursor mark, never another digit or a dot.
                if m.range.lowerBound != line.startIndex,
                    !" >❯›*".contains(line[line.index(before: m.range.lowerBound)])
                {
                    continue
                }
                let end = i + 1 < marks.count ? marks[i + 1].range.lowerBound : line.endIndex
                var title = Substring(line[m.range.upperBound..<end])
                for stop in ["  ", "↑", "↓"] {
                    if let r = title.range(of: stop) { title = title[..<r.lowerBound] }
                }
                let t = title.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ">❯›")))
                if !t.isEmpty { found.append((MenuOption(number: String(m.output.1), title: t), n)) }
            }
        }
        guard let start = found.lastIndex(where: { $0.option.number == "1" }) else { return [] }
        var run: [(option: MenuOption, line: Int)] = []
        for o in found[start...] where o.option.number == "\(run.count + 1)" { run.append(o) }
        guard run.count >= 2, let last = run.last?.line, lines[(last + 1)...].allSatisfy(hintOrBlank) else { return [] }
        return run.map(\.option)
    }

    /// A line a menu may leave under itself: blank, or how to move through it ("↑/↓ Navigate · enter Select").
    static func hintOrBlank(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespaces).lowercased()
        return l.isEmpty || ["↑", "↓", "navigate", "select", "esc to"].contains { l.contains($0) }
    }
}
