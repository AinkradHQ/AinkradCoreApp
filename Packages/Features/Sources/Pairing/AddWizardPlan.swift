import Foundation

/// The pure rules of the Add flow (N17): what can be added, the steps each kind goes through, what an access preset means
/// in scopes, and the exact commands that put a runner on a machine. No Core calls here, so the tests pin them.
enum AddKind: CaseIterable, Equatable, Sendable {
    case phone, mac, linuxRunner, macRunner

    var title: String {
        switch self {
        case .phone: "iPhone or iPad"
        case .mac: "Another Mac"
        case .linuxRunner: "A Linux server as a runner"
        case .macRunner: "Another Mac as a runner"
        }
    }

    var blurb: String {
        switch self {
        case .phone: "Approve AI sessions and watch work from your phone."
        case .mac: "Use Ainkrad Core on a second Mac."
        case .linuxRunner: "More power for AI sessions and terminals."
        case .macRunner: "Run AI sessions and terminals on that Mac."
        }
    }

    var symbol: String {
        switch self {
        case .phone: "iphone"
        case .mac: "laptopcomputer"
        case .linuxRunner: "server.rack"
        case .macRunner: "macmini"
        }
    }

    var isRunner: Bool { self == .linuxRunner || self == .macRunner }
    /// What the Core calls it when it is paired.
    var coreKind: String { isRunner ? "runner" : "device" }
    var defaultName: String {
        switch self {
        case .phone: "iPhone"
        case .mac: "Mac"
        case .linuxRunner: "linux-runner"
        case .macRunner: "mac-runner"
        }
    }
}

enum AddStep: Int, Equatable, Sendable {
    case what, install, access, connect, settings, done

    var title: String {
        switch self {
        case .what: "What"
        case .install: "Install"
        case .access: "Access"
        case .connect: "Connect"
        case .settings: "Settings"
        case .done: "Done"
        }
    }
}

/// What the new device may do, in words a person can choose (the six switches stay under Advanced).
enum AccessPreset: CaseIterable, Equatable, Sendable {
    case watch, work, full, custom

    static let choices: [AccessPreset] = [.watch, .work, .full]

    var title: String {
        switch self {
        case .watch: "Watch and approve"
        case .work: "Work"
        case .full: "Full control"
        case .custom: "Your own mix"
        }
    }

    var blurb: String {
        switch self {
        case .watch: "Read and approve. Good for a phone."
        case .work: "Read, approve, terminals and AI sessions. Good for a second Mac."
        case .full: "Everything, including settings and other devices."
        case .custom: "The switches you chose under Advanced."
        }
    }

    var symbol: String {
        switch self {
        case .watch: "eye"
        case .work: "laptopcomputer"
        case .full: "shield"
        case .custom: "slider.horizontal.3"
        }
    }

    /// The Core's scopes behind it, in the order the app lists them.
    var scopes: [String] {
        switch self {
        case .watch: ["read", "approve"]
        case .work: ["read", "approve", "terminal", "agent"]
        case .full: ["read", "approve", "terminal", "agent", "admin"]
        case .custom: []
        }
    }

    /// The preset a set of scopes is, or `.custom`.
    static func matching(_ scopes: Set<String>) -> AccessPreset {
        choices.first { Set($0.scopes) == scopes } ?? .custom
    }

    /// What a phone and a Mac start with.
    static func standard(for kind: AddKind) -> AccessPreset { kind == .phone ? .watch : .work }
}

enum AddWizardPlan {
    static let macReleases = URL(string: "https://github.com/AinkradHQ/AinkradCoreApp/releases/latest")!
    static let runnerReleases = URL(string: "https://github.com/AinkradHQ/AinkradCore/releases/latest")!

    /// The screens a kind goes through. A device is told what it may do before its QR exists, because the Core fixes the
    /// scopes when it makes the invite; a runner has no choice of scopes (it holds only `runner`) and has its settings.
    static func steps(_ kind: AddKind) -> [AddStep] {
        switch kind {
        case .phone: [.what, .install]
        case .mac: [.what, .install, .access, .connect, .done]
        case .linuxRunner, .macRunner: [.what, .install, .connect, .settings, .done]
        }
    }

    static func next(after step: AddStep, _ kind: AddKind) -> AddStep? {
        let all = steps(kind)
        return all.firstIndex(of: step).flatMap { all.indices.contains($0 + 1) ? all[$0 + 1] : nil }
    }

    static func previous(before step: AddStep, _ kind: AddKind) -> AddStep? {
        let all = steps(kind)
        return all.firstIndex(of: step).flatMap { $0 > 0 ? all[$0 - 1] : nil }
    }

    /// What a Mac that holds `mine` can hand on of `wanted`, and what it cannot (the Core refuses a wider pairing).
    static func narrowed(_ wanted: [String], mine: [String]) -> (granted: [String], dropped: [String]) {
        mine.isEmpty
            ? (wanted, []) : (wanted.filter(mine.contains), wanted.filter { !mine.contains($0) })
    }

    /// One command for a Linux server: install the runner service, turn on what was chosen, pair with the code (waits for
    /// your approval) and start. Run from the unpacked runner release.
    static func linuxCommand(core: String, code: String, terminals: Bool, agents: Bool) -> String {
        var c = "sudo ./deploy/install-linux.sh --binary ./ainkrad-runner"
        if terminals { c += " --pty" }
        if agents { c += " --agents" }
        return c + " --pair \(core) --code \(code)"
    }

    /// The one command for a Linux server with a runner invite: installs the runner and connects it. Contains the secret token.
    static func runnerInviteCommand(token: String) -> String {
        "sudo sh -c \"$(curl -fsSL https://github.com/AinkradHQ/AinkradCore/releases/latest/download/get.sh)\" sh --runner --invite \(token)"
    }

    /// For a Mac runner: pair, then serve the Core with what was chosen.
    static func macCommands(core: String, code: String, terminals: Bool, agents: Bool) -> [String] {
        var connect = "ainkrad-runner connect"
        if terminals { connect += " --enable-pty" }
        if agents { connect += " --enable-agents" }
        return ["ainkrad-runner pair \(core) --code \(code)", connect]
    }
}
