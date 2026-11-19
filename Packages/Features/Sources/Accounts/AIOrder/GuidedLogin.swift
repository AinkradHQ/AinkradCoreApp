import Foundation

/// The pure rules of a runner-bound sign-in (E7-4 Codex, E7-5 OpenCode, E7-5b Antigravity): which of the three screens a
/// provider uses, which runner it may start on, how a typed line is checked, and how fast the screen is polled. No views.

/// How a subscription provider signs in. Read from the Core's `login_methods` first, so a new provider needs no change here;
/// the ids are only the fallback for a Core that lists none.
enum SignInStyle: Equatable, Sendable {
    /// Claude: open a page, then paste the code it shows.
    case paste
    /// Codex: open a page and type the code Ainkrad shows (the Core carries it).
    case deviceCode
    /// OpenCode and Antigravity: the runner's own sign-in, as text on a screen and one typed line at a time.
    case guided

    static func of(_ provider: String, methods: [String] = []) -> SignInStyle {
        if methods.contains("runner_login") { return .guided }
        if methods.contains("device_code") { return .deviceCode }
        if methods.contains("browser_code") { return .paste }
        switch provider {
        case "opencode-sub", "agy-sub": return .guided
        case "codex-sub": return .deviceCode
        default: return .paste
        }
    }

    /// The login stays in one runner's own home: the account only runs there.
    var runnerBound: Bool { self != .paste }

    /// OpenCode signs in to other providers' own pages, so only the plans that have rules of their own carry the risk note.
    static func showsRisk(_ provider: String) -> Bool { provider != "opencode-sub" }
}

/// One line typed into a guided sign-in. The Core takes only a menu choice or a short code: letters, digits, `_` and `-`,
/// up to `maxLength`. The same rule is checked here first, so a refused line is explained and never sent.
enum GuidedInput {
    static let maxLength = 128
    static let hint = "Type the number of a choice, or the code shown."
    enum Verdict: Equatable { case send(String), empty, tooLong, badCharacters }

    static func check(_ raw: String) -> Verdict {
        // A paste often ends in a newline; that is the Enter the Core adds itself.
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return .empty }
        if line.count > maxLength { return .tooLong }
        if !line.unicodeScalars.allSatisfy(allowed) { return .badCharacters }
        return .send(line)
    }

    private static func allowed(_ c: Unicode.Scalar) -> Bool {
        c.isASCII && (c.properties.isAlphabetic || ("0"..."9").contains(c) || c == "_" || c == "-")
    }

    static func words(_ v: Verdict) -> String? {
        switch v {
        case .send, .empty: nil
        case .tooLong: "That is too long for a choice or a code. \(hint)"
        case .badCharacters: "Only letters, numbers, dashes and underscores. \(hint)"
        }
    }
}

/// How long to wait before the next look at the screen: quick while it changes, slower while it is still, never past the cap.
struct PollBackoff: Equatable, Sendable {
    static let floor = 1.0
    static let cap = 4.0
    private(set) var seconds = PollBackoff.floor

    mutating func note(changed: Bool) {
        seconds = changed ? Self.floor : min(Self.cap, seconds * 1.5)
    }
    /// A line was sent: look again soon.
    mutating func reset() { seconds = Self.floor }
}

/// What a guided sign-in shows now: redacted text, a page and a code once printed. Held in memory only.
struct LoginScreen: Decodable, Equatable, Sendable {
    var lines: [String] = []
    var url: String?
    var code: String?
}

/// Which runner a sign-in may start on, from the runners the Core lists. A runner can sign in to a provider only when it is
/// online and lists `login-bound:<harness>` among its commands.
struct RunnerChoice: Equatable, Sendable {
    let eligible: [AccountRunner]
    let others: [AccountRunner]
    var selected: String?

    static func make(runners: [AccountRunner], harness: String, keep: String? = nil) -> RunnerChoice {
        let can = { (r: AccountRunner) in r.online && r.commands.contains("login-bound:\(harness)") }
        let eligible = runners.filter(can)
        let pick = eligible.first { $0.id == keep }?.id ?? eligible.first?.id
        return RunnerChoice(eligible: eligible, others: runners.filter { !can($0) }, selected: pick)
    }

    /// Nobody can run it: the dialog explains instead of offering a button that does nothing.
    var none: Bool { eligible.isEmpty }
    /// Only one can: it is used without asking, and the dialog says so.
    var only: AccountRunner? { eligible.count == 1 ? eligible.first : nil }
    var needsPick: Bool { eligible.count > 1 }
    var chosen: AccountRunner? { eligible.first { $0.id == selected } }

    /// Why nothing can sign in, and what to do, in the order of what is most likely wrong.
    func why(provider: String) -> String {
        if others.isEmpty {
            return "No runner is connected to your Core yet. Connect a runner, then sign in to \(provider)."
        }
        if !others.contains(where: \.online) {
            return "None of your runners is online. Turn one on, then sign in to \(provider)."
        }
        return
            "No online runner can sign in to \(provider) yet. A runner needs the newest ainkrad-runner with \(provider)'s own app installed."
    }
}

/// The line that says an account stays on one runner.
struct RunnerBinding: Equatable, Sendable {
    /// The runner's name, when the app knows it.
    var name: String?
    var words: String { name.map { "Runs only on \($0)" } ?? "Runs on one runner only" }
    var detail: String {
        name.map {
            "This account signed in on \($0), so it only runs there. If \($0) is offline, Core moves on to the next account."
        }
            ?? "This account signed in on one runner, so it only runs there. If that runner is offline, Core moves on to the next account."
    }
}
