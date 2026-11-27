import Foundation

/// What a project is, as the Core holds it (`ProjectInfo.kind`, API 111). It decides which pages and buttons the project shows:
/// a web app has a live preview and a public link, an app has a build, infrastructure has services and health, and a project
/// that is not software has no run at all.
enum ProjectKind: String, CaseIterable, Identifiable, Sendable {
    case web, app, infra, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: "Web app or site"
        case .app: "Desktop or mobile app"
        case .infra: "Infrastructure or OS"
        case .other: "Not software"
        }
    }

    /// A short name for the card, the badge and the select.
    var short: String {
        switch self {
        case .web: "Web"
        case .app: "App"
        case .infra: "Infrastructure"
        case .other: "Not software"
        }
    }

    var line: String {
        switch self {
        case .web: "Runs in a browser, with a live preview and an optional public link."
        case .app: "Built for a Mac, a phone or another device. It is built and run, not browsed."
        case .infra: "Servers, a platform or an operating system. It shows its services and health."
        case .other: "Docs, research, a business or a book. No run, just Brain, Docs and AI Sessions."
        }
    }

    /// What the wizard's tile says in a few words.
    var tagline: String {
        switch self {
        case .web: "A site or web app"
        case .app: "Mac, iPhone or Android"
        case .infra: "Servers and platforms"
        case .other: "Docs, research, a book"
        }
    }

    /// The tile's title in the wizard.
    var tileTitle: String { self == .other ? "Anything else" : short }

    /// "Looks like …": how the wizard names this kind in its one-line correction.
    var lookWord: String {
        switch self {
        case .web: "a Web project"
        case .app: "an App"
        case .infra: "Infrastructure"
        case .other: "a project that is not software"
        }
    }

    var symbol: String {
        switch self {
        case .web: "globe"
        case .app: "macbook.and.iphone"
        case .infra: "server.rack"
        case .other: "doc.text"
        }
    }

    /// A project that can be started, stopped and shown at a public link.
    var runs: Bool { self != .other }
    var hasPublicLink: Bool { self == .web }
}

/// The kind the wizard suggests from the repos picked, and the plain words for why.
struct KindSuggestion: Equatable, Sendable {
    let kind: ProjectKind
    let why: String
    /// What the repos say, short ("Swift, iOS"): the wizard's one-line correction.
    var evidence = ""
    /// The repos clearly say it. False for "no repos" and for the web fallback guess: those never change the kind.
    var clear = false
}

extension ProjectKind {
    private static let languages: [ProjectKind: [String: Double]] = [
        .app: ["swift": 1, "kotlin": 1, "dart": 1, "objective-c": 1, "objective-c++": 1, "java": 0.3, "c#": 0.3],
        .infra: [
            "hcl": 1, "nix": 1, "dockerfile": 1, "puppet": 1, "jsonnet": 1, "shell": 0.5, "makefile": 0.5, "c": 0.3,
            "go": 0.2,
        ],
        .web: [
            "typescript": 1, "javascript": 1, "php": 1, "ruby": 1, "html": 1, "css": 1, "scss": 1, "vue": 1,
            "svelte": 1,
            "blade": 1, "astro": 1, "python": 0.7,
        ],
    ]
    private static let noCode: Set<String> = ["markdown", "mdx", "tex", "latex", "jupyter notebook", "text"]

    /// (word in the name or blurb, how it is shown to the person).
    private static let words: [ProjectKind: [(String, String)]] = [
        .app: [
            ("ios", "iOS"), ("android", "Android"), ("iphone", "iPhone"), ("macos", "macOS"), ("swiftui", "SwiftUI"),
            ("flutter", "Flutter"), ("electron", "Electron"), ("tauri", "Tauri"), ("xcode", "Xcode"),
        ],
        .infra: [
            ("terraform", "Terraform"), ("kubernetes", "Kubernetes"), ("k8s", "Kubernetes"), ("helm", "Helm"),
            ("ansible", "Ansible"), ("devops", "DevOps"), ("infrastructure", "Infrastructure"), ("kernel", "Kernel"),
            ("firmware", "Firmware"), ("nixos", "NixOS"),
        ],
        .web: [
            ("nextjs", "Next.js"), ("next", "Next.js"), ("react", "React"), ("laravel", "Laravel"),
            ("rails", "Rails"), ("django", "Django"), ("website", "Website"), ("frontend", "Frontend"),
        ],
    ]
    /// Order breaks a tie: an app repo next to some shell scripts is still an app.
    private static let order: [ProjectKind] = [.app, .infra, .web]

    /// The kind that fits the picked repos best, from their language and what their name and blurb say. Pure; no repos at all,
    /// or only docs, reads as "not software". Nothing clear falls back to web, and says so.
    static func suggest(from repos: [PickRepo]) -> KindSuggestion {
        guard !repos.isEmpty else {
            return KindSuggestion(
                kind: .other, why: "No repos picked, so this looks like a project that is not software.")
        }
        var score: [ProjectKind: Double] = [:]
        var evidence: [ProjectKind: [String]] = [:]
        func add(_ k: ProjectKind, _ w: Double, _ shown: String) {
            score[k, default: 0] += w
            if !(evidence[k] ?? []).contains(shown) { evidence[k, default: []].append(shown) }
        }
        var docsOnly = true
        for r in repos {
            let lang = r.language?.lowercased()
            if let lang, !noCode.contains(lang) { docsOnly = false }
            if let lang, let k = order.first(where: { languages[$0]?[lang] != nil }) {
                add(k, languages[k]?[lang] ?? 0, r.language ?? lang)
            }
            let text = "\(r.name) \(r.blurb)".lowercased()
            let tokens = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            for k in order {
                for (word, shown) in words[k] ?? [] where tokens.contains(word) { add(k, 1, shown) }
            }
        }
        if docsOnly && score.isEmpty {
            return KindSuggestion(
                kind: .other, why: "Your repos hold no code, only documents.", evidence: "only documents", clear: true)
        }
        guard let best = order.max(by: { (score[$0] ?? 0) < (score[$1] ?? 0) }), (score[best] ?? 0) >= 0.5 else {
            return KindSuggestion(kind: .web, why: "Nothing in your repos says what it is, so web is a guess.")
        }
        let shown = (evidence[best] ?? []).prefix(3).joined(separator: ", ")
        return KindSuggestion(kind: best, why: "Suggested from your repos: \(shown)", evidence: shown, clear: true)
    }

    /// The devices a project's repos are named for ("iOS, Android"); empty when the names say nothing.
    static func platforms(_ repos: [RepoItem]) -> [String] {
        let tokens = Set(
            repos.flatMap { $0.name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) })
        let known = [
            ("ios", "iOS"), ("iphone", "iOS"), ("ipad", "iPadOS"), ("macos", "macOS"), ("mac", "macOS"),
            ("android", "Android"), ("windows", "Windows"), ("linux", "Linux"), ("desktop", "Desktop"),
            ("watch", "watchOS"),
        ]
        var out: [String] = []
        for (word, shown) in known where tokens.contains(word) && !out.contains(shown) { out.append(shown) }
        return out
    }
}

/// Kinds chosen on this Mac, by link name: used until the Core holds them (API 111), like the colours.
@MainActor
final class ProjectKinds {
    private let defaults: UserDefaults
    static let key = "ainkrad.core.projects.kinds"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func kind(_ slug: String) -> ProjectKind? {
        (defaults.dictionary(forKey: Self.key) as? [String: String])?[slug].flatMap(ProjectKind.init(rawValue:))
    }
    func set(_ kind: ProjectKind, for slug: String) {
        var all = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        all[slug] = kind.rawValue
        defaults.set(all, forKey: Self.key)
    }
}
