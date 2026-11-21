import CoreUI
import Foundation

/// The one status of a machine (Machines review, 2026-11-21): computed here once and shown the same everywhere. Offline wins
/// over everything, so an offline machine never reads Ready or Working.
enum MachineStatus: String, Equatable, Sendable {
    case working = "Working"
    case idle = "Idle"
    case notAnswering = "Not answering"
    case offline = "Offline"
    /// A phone, iPad or Mac that only opens your Core.
    case signedIn = "Signed in"

    init(_ r: RunnerItem) {
        switch RunnerStatus(r) {
        case .off: self = .offline
        case .degraded: self = .notAnswering
        case .busy: self = .working
        case .ok:
            let used = (r.slots?.agentsUsed ?? 0) + (r.slots?.terminalsUsed ?? 0)
            self = used > 0 || (r.slots == nil && r.load > 0) ? .working : .idle
        }
    }

    var tone: Tone {
        switch self {
        case .working: .run
        case .idle: .queue
        case .notAnswering: .warn
        case .offline: .fail
        case .signedIn: .done
        }
    }
}

/// A phone, iPad or Mac that only signs in to the Core, as the Machines list needs it. The app's devices model fills it.
public struct SignInMachine: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    /// `ios`, `ipados`, `macos`; nil when the device did not say.
    public var platform: String?
    public var lastSeen: Date?
    public var added: Date
    public var scopes: [String]
    /// The device this app signs in with.
    public var isThisMac: Bool
    public init(
        id: String, name: String, platform: String?, lastSeen: Date?, added: Date, scopes: [String], isThisMac: Bool
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.lastSeen = lastSeen
        self.added = added
        self.scopes = scopes
        self.isThisMac = isThisMac
    }

    /// How it can start doing work from its page; nil for a phone, an iPad or a browser.
    public func promote(macRunnerAvailable: Bool) -> PromotePath? {
        Machines.promote(self, macRunnerAvailable: macRunnerAvailable)
    }

    public var isMac: Bool { platform?.lowercased().contains("mac") == true || isThisMac }
    var isPad: Bool { platform?.lowercased().contains("ipad") == true }
    public var symbol: String { platform == "web" ? "globe" : isMac ? "laptopcomputer" : isPad ? "ipad" : "iphone" }
}

/// What the top of the list says when something is wrong: the first problem, and how many more there are.
struct MachineProblem: Equatable {
    let machine: String
    let title: String
    let text: String
}

/// How a Mac that only signs in can start doing work, from its own page.
public enum PromotePath: Equatable, Sendable {
    /// The Mac you are on: the Do work on this Mac switch.
    case thisMacSwitch
    /// Another Mac: Add machine, prefilled with its name.
    case runWorkHere
}

/// The pure rules of the Machines app: order, groups, the one status, the problem line, load and the summary sentence.
enum Machines {
    /// Does work: This Mac first, then this Core's own runner, then the rest by name, offline ones last.
    static func ordered(_ runners: [RunnerItem], thisMac: String?) -> [RunnerItem] {
        runners.sorted { a, b in
            func rank(_ r: RunnerItem) -> Int {
                r.id == thisMac ? 0 : r.builtIn ? 1 : MachineStatus(r) == .offline ? 3 : 2
            }
            let ra = rank(a)
            let rb = rank(b)
            return ra != rb ? ra < rb : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Signs in only, newest seen first. The sign-in of this Mac goes when This Mac already does work: it is that row.
    static func signInOnly(_ devices: [SignInMachine], thisMacWorks: Bool) -> [SignInMachine] {
        devices.filter { !(thisMacWorks && $0.isThisMac) }.sorted {
            ($0.isThisMac ? 0 : 1, -($0.lastSeen ?? $0.added).timeIntervalSince1970)
                < ($1.isThisMac ? 0 : 1, -($1.lastSeen ?? $1.added).timeIntervalSince1970)
        }
    }

    /// The name a runner shows: "This Mac" for the one inside this app.
    static func name(_ r: RunnerItem, thisMac: String?) -> String { r.id == thisMac ? "This Mac" : r.name }

    /// 0...1 of how busy it is: the machine's CPU when the Core reports hardware, else the AI session slots, else the old
    /// work slots. nil when offline or nothing says.
    static func busy(_ r: RunnerItem, cpuPct: Int?) -> Double? {
        guard MachineStatus(r) != .offline else { return nil }
        if let cpuPct { return min(1, max(0, Double(cpuPct) / 100)) }
        if let s = r.slots, let cap = s.agentsCapacity, cap > 0 { return min(1, Double(s.agentsUsed) / Double(cap)) }
        return r.capacity > 0 ? min(1, Double(r.load) / Double(r.capacity)) : nil
    }

    /// "Room for 3 more AI sessions", from the runner's capacity; nil when it does not report one.
    static func room(_ r: RunnerItem) -> String? {
        guard MachineStatus(r) != .offline, let s = r.slots, let cap = s.agentsCapacity else { return nil }
        let n = max(0, cap - s.agentsUsed)
        return n == 0 ? "Full: new AI sessions wait" : "Room for \(n) more AI \(n == 1 ? "session" : "sessions")"
    }

    /// "2 working, 1 idle, 1 offline. 2 phones can sign in."
    static func summary(_ runners: [RunnerItem], signIns: Int) -> String {
        let s = runners.map(MachineStatus.init)
        let parts: [(MachineStatus, String)] = [
            (.working, "working"), (.idle, "idle"), (.notAnswering, "not answering"), (.offline, "offline"),
        ]
        let counts = parts.compactMap { st, word -> String? in
            let n = s.filter { $0 == st }.count
            return n == 0 ? nil : "\(n) \(word)"
        }
        var out = counts.isEmpty ? "Nothing does work yet." : counts.joined(separator: ", ") + "."
        if signIns > 0 { out += " \(signIns) \(signIns == 1 ? "machine signs" : "machines sign") in only." }
        return out
    }

    /// "14:02" today, else "3 Nov, 14:02".
    static func when(_ d: Date, now: Date = .now) -> String {
        Calendar.current.isDate(d, inSameDayAs: now)
            ? d.formatted(date: .omitted, time: .shortened) : d.formatted(date: .abbreviated, time: .shortened)
    }

    /// "One terminal waits for it", "2 AI sessions and 1 terminal wait for it"; nil when nothing waits.
    static func waiting(agents: Int, terminals: Int) -> String? {
        guard agents + terminals > 0 else { return nil }
        let what = RunnerFacts.stops(agents: agents, terminals: terminals)
        return "\(what.prefix(1).uppercased())\(what.dropFirst()) \(agents + terminals == 1 ? "waits" : "wait") for it"
    }

    /// The first problem among the machines, offline first, then not answering, then a failed install, then what a runner
    /// says is wrong with itself. `waiting` counts the work that waits on a machine.
    static func problem(
        _ runners: [RunnerItem], installs: [String: [String: ToolInstall]], thisMac: String?,
        waiting: (String) -> (agents: Int, terminals: Int), now: Date = .now
    ) -> MachineProblem? {
        var found: [MachineProblem] = []
        for r in ordered(runners, thisMac: thisMac) where MachineStatus(r) == .offline {
            let n = name(r, thisMac: thisMac)
            let w = waiting(r.id)
            let since = r.lastSeen.map { "Since \(when($0, now: now))." }
            let text = [
                since, Self.waiting(agents: w.agents, terminals: w.terminals).map { $0 + "." }, "Nothing was lost.",
            ]
            found.append(
                .init(machine: r.id, title: "\(n) is offline", text: text.compactMap { $0 }.joined(separator: " ")))
        }
        for r in runners where MachineStatus(r) == .notAnswering {
            found.append(
                .init(
                    machine: r.id, title: "\(name(r, thisMac: thisMac)) is not answering",
                    text: "It missed its last check-ins, so what it shows can be old."))
        }
        for r in runners where MachineStatus(r) != .offline {
            if let bad = installs[r.id]?.values.sorted(by: { $0.tool < $1.tool }).first(where: { $0.state == .failed })
            {
                found.append(
                    .init(
                        machine: r.id,
                        title: "Could not install \(RunnerTools.name(bad.tool)) on \(name(r, thisMac: thisMac))",
                        text: bad.reason ?? "The install did not finish. It is tried again when the machine restarts."))
            } else if let e = r.lastError, !e.isEmpty {
                found.append(.init(machine: r.id, title: "\(name(r, thisMac: thisMac)) reports a problem", text: e))
            }
        }
        guard let first = found.first else { return nil }
        let more = found.count - 1
        return more == 0
            ? first
            : .init(
                machine: first.machine, title: first.title,
                text: first.text + " \(more) more \(more == 1 ? "problem" : "problems") below.")
    }

    /// How a sign-in-only device can start doing work; nil for a phone or iPad, or this Mac without a runner inside.
    static func promote(_ d: SignInMachine, macRunnerAvailable: Bool) -> PromotePath? {
        if d.isThisMac { return macRunnerAvailable ? .thisMacSwitch : nil }
        return d.isMac ? .runWorkHere : nil
    }
}

/// The AI tools Ainkrad keeps on every machine that does work. The runner installs the pinned ones itself shortly after it
/// connects (D-22); when one is still missing after that, the app asks the Core once (`POST /runners/{id}/tools`).
/// Antigravity has no download Ainkrad may fetch, so it is never requested: the page says how to get it.
enum AutoInstall {
    static let pinned = ["claude", "codex", "opencode"]
    /// How long a runner gets to install its own tools before the app asks.
    static let grace: TimeInterval = 120

    /// The installs to request now, as `runner/tool`, each at most once (`requested` holds the ones asked already).
    static func due(
        _ runners: [RunnerItem], installs: [String: [String: ToolInstall]], requested: Set<String>, now: Date = .now
    ) -> [(runner: String, tool: String)] {
        var out: [(String, String)] = []
        for r in runners where MachineStatus(r) != .offline && MachineStatus(r) != .notAnswering {
            guard r.drivers.contains(where: { $0.name == "agent" }), r.policy?.agents != false else { continue }
            guard let since = r.connectedSince, now.timeIntervalSince(since) >= grace else { continue }
            if r.reported?.state == .running { continue }
            for tool in pinned where r.tools[tool] == nil && !requested.contains("\(r.id)/\(tool)") {
                if installs[r.id]?[tool] != nil { continue }
                out.append((r.id, tool))
            }
        }
        return out
    }

    /// The pinned tools a machine is still missing, in words: "Codex and OpenCode"; nil when none is.
    static func missing(_ r: RunnerItem) -> String? {
        let names = pinned.filter { r.tools[$0] == nil }.map(RunnerTools.name)
        guard let last = names.last else { return nil }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }
}
