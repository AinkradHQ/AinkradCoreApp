import CoreUI
import Foundation
import SwiftUI

/// One repo of a project, as the gallery and the project space show it. `fetchedAt` is nil until the Core has tried to copy it.
struct RepoItem: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let remoteURL: String
    let branch: String
    let primary: Bool
    let fetchedAt: Date?
    let fetchError: String?
    /// The commit the Core's copy is at (`mirror.head`).
    var head: String? = nil
    /// The mirror's own words (`mirror.state`, `.reason`, `.started_at`); nil from a Core that does not say them yet.
    var state: String? = nil
    var reason: String? = nil
    var startedAt: Date? = nil

    /// Where the Core's copy stands: copying (since when), ready, or failed with a reason the person can act on.
    var copy: RepoCopy {
        if state == "fetching" { return .fetching(since: startedAt) }
        if state == "failed" || fetchError != nil {
            return .failed(RepoFailure(code: reason), fetchError ?? "The Core could not copy this repo.")
        }
        return fetchedAt == nil ? .fetching(since: startedAt) : .ready
    }
}

/// Why a copy failed, as the Core classifies it (`mirror.reason`).
enum RepoFailure: Equatable, Sendable {
    case needsGithub, notFoundOrPrivate, authFailed, timeout, sshNotSupported, other

    init(code: String?) {
        switch code {
        case "needs_github": self = .needsGithub
        case "not_found_or_private": self = .notFoundOrPrivate
        case "auth_failed": self = .authFailed
        case "timeout": self = .timeout
        case "ssh_not_supported": self = .sshNotSupported
        default: self = .other
        }
    }

    /// The fix is in Connections, not another try.
    var needsConnection: Bool { self == .needsGithub || self == .authFailed }
}

enum RepoCopy: Equatable, Sendable {
    case fetching(since: Date?)
    case ready
    case failed(RepoFailure, String)

    /// "copying · 40 s" (the Core's start time, else just "copying…").
    static func elapsed(since: Date?, now: Date) -> String {
        guard let since else { return "copying…" }
        let s = max(0, Int(now.timeIntervalSince(since)))
        return s < 60 ? "copying · \(s) s" : "copying · \(s / 60) min \(s % 60) s"
    }
}

/// What the Core's run engine says of a project. The engine (P5) does not exist yet, so a live project has none and the
/// stand-in data (Debug) is the only thing that fills it.
struct RunSummary: Equatable, Sendable {
    enum State: Equatable, Sendable { case running, starting, stopped, failed }
    var state: State
    var services = 0
    var sessions = 0
    /// "yesterday", "Mon", "20 min ago": already in words.
    var lastRun: String?
}

/// A project's newest run as the Core's run routes (`/projects/{id}/run`, AinkradCore #318) answer it.
struct ProjectRunState: Equatable, Sendable {
    var summary: RunSummary
    var startedAt: Date
    /// When the idle stop is due, for a running run.
    var idleStopAt: Date?
    /// What went wrong, for a failed run (the Core redacts it).
    var error: String?
    /// `user`, `idle`, `crash`, `runner_lost`, `replaced` or `start_failed`.
    var stopReason: String?
    /// The runner's id it is placed on, and when anything last visited it.
    var runner: String?
    var lastActivityAt: Date?
}

/// A drafted run (P4): shown in the "ready to start" state.
struct RunDraft: Equatable, Sendable {
    let source: String
    let services: [String]
    /// The secrets the setup asks for that the Core does not hold yet.
    let secrets: [String]
    /// Written or saved by a person, not drafted from a repo file.
    var manual = false
}

struct ProjectItem: Identifiable, Equatable, Sendable {
    let id: Int64
    let slug: String
    var name: String
    var description: String
    var expose: Bool
    var repos: [RepoItem]
    var updatedAt: Date
    var run: RunSummary?
    var draft: RunDraft?
    /// What the Overview shows of a running project: services, logs, AI sessions, the Brain room. Nil on a real Core today.
    var live: ProjectLive?
    /// What a run may use and when it stops by itself (the Core's defaults until it says otherwise).
    var cpuLimit = 2.0
    var memLimitMb: Int64 = 2048
    var idleMinutes = ProjectRules.idleMinutes
    /// Set aside with Archive: it keeps its repos, secrets and notes but does not run.
    var archived = false
    /// The project never stops for being idle (`idle_never`).
    var idleNever = false
    /// The Core has been asked whether the project has a run setup (its spec); `draft` is that setup when it has one.
    var setupChecked = false
    /// The Core could not be reached just now: the run state shown is how it last looked.
    var stale = false

    /// Where a project with no run yet stands, from what the Core says.
    enum Setup: Equatable {
        case noRepos, copying
        case copyFailed(String)
        /// The Core has not been asked yet whether there is a spec.
        case checking
        /// Copies are ready, there is no spec: it has to be drafted or written.
        case needsSetup
        case ready(RunDraft)
        /// It has run before, so it has a setup.
        case ran
    }

    var setup: Setup {
        if repos.isEmpty { return .noRepos }
        if run != nil { return .ran }
        if let e = repos.compactMap({ $0.fetchError }).first { return .copyFailed(e) }
        if repos.contains(where: { $0.fetchedAt == nil }) { return .copying }
        if let draft { return .ready(draft) }
        return setupChecked ? .needsSetup : .checking
    }

    /// Why Start cannot be pressed for the project's own reasons (not the connection's); nil when it can.
    var startBlock: String? {
        switch setup {
        case .noRepos: "Add a repo first. The Core runs what is in it."
        case .copying, .checking: "Start is ready once the repos are copied and the setup is read."
        case .copyFailed: "A repo could not be copied. Fix that first."
        case .needsSetup: "This project has no setup yet. Draft one from the repo in Runs, Setup and secrets."
        case .ready(let d) where !d.secrets.isEmpty:
            "Set the secrets the setup needs first: \(d.secrets.joined(separator: ", "))."
        case .ready, .ran: nil
        }
    }

    var link: String { ProjectRules.host(slug) }

    /// The word on the card's tag. Always a word with its colour, never colour alone.
    enum Tag: Equatable, Sendable { case running, starting, stopped, failed, settingUp, new }

    var tag: Tag {
        if let run {
            switch run.state {
            case .running: return .running
            case .starting: return .starting
            case .failed: return .failed
            case .stopped: break
            }
        }
        if repos.isEmpty { return .new }
        if run == nil, repos.contains(where: { $0.fetchedAt == nil }) { return .settingUp }
        return .stopped
    }

    /// The state as the design system's badge says it.
    var badge: (label: String, tone: Tone, symbol: String) {
        if archived { return ("Archived", .queue, "archivebox") }
        if stale, tag == .running || tag == .starting { return ("Status unknown", .queue, "questionmark.circle") }
        return switch tag {
        case .running: ("Running", Tone.run, "play.circle")
        case .starting: ("Starting", Tone.warn, "gearshape")
        case .stopped: ("Stopped", Tone.queue, "stop.circle")
        case .failed: ("Failed", Tone.fail, "exclamationmark.triangle")
        case .settingUp: ("Setting up", Tone.warn, "gearshape")
        case .new: ("New", Tone.queue, "sparkle")
        }
    }

    /// The line under the name: "Running · 5 services · 2 AI sessions".
    var subtitle: String {
        if archived { return "Archived · \(Self.count(repos.count, "repo"))" }
        if stale, tag == .running || tag == .starting { return "Last seen running · the Core is not answering" }
        if let run {
            switch run.state {
            case .running:
                var parts = ["Running"]
                if run.services > 0 { parts.append(Self.count(run.services, "service")) }
                if run.sessions > 0 { parts.append(Self.count(run.sessions, "AI session")) }
                return parts.joined(separator: " · ")
            case .starting: return run.services > 0 ? "Starting · \(Self.count(run.services, "service"))" : "Starting"
            case .failed: return run.lastRun.map { "Last run failed \($0)" } ?? "Last run failed"
            case .stopped: return run.lastRun.map { "Stopped · last run \($0)" } ?? "Stopped"
            }
        }
        switch tag {
        case .new: return "New · no repos yet"
        case .settingUp: return "Setting up · \(Self.count(repos.count, "repo"))"
        default:
            if draft != nil { return "Ready to start · \(Self.count(repos.count, "repo"))" }
            if setupChecked { return "No setup yet · \(Self.count(repos.count, "repo"))" }
            return "Stopped · \(Self.count(repos.count, "repo"))"
        }
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

/// A project's colour is one of the design system's accents (`CoreAccent`): no hues of our own.
/// TODO(design-system): proposal CoreSwatch, a row of tinted rounded squares to pick one of these.
typealias ProjectColour = CoreAccent

extension CoreAccent {
    /// A stable colour for a project that never had one picked.
    static func standard(for slug: String) -> CoreAccent {
        let sum = slug.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 }
        return allCases[sum % allCases.count]
    }
}

/// The rules of the Core for names, links and repo remotes, checked here first so a typo is caught before Touch ID.
enum ProjectRules {
    static let domain = "ainkrad.io"
    static let idleMinutes = 30
    /// What the Core gives a new project (its table defaults), shown as "Runs on".
    static let defaultLimits = "2 CPUs, 2 GB"
    /// "2 CPUs, 2 GB": what a project's run really gets.
    static func limits(cpu: Double, memMb: Int64) -> String {
        let c = cpu == cpu.rounded() ? String(Int(cpu)) : String(format: "%.1f", cpu)
        let g = Double(memMb) / 1024
        let mem = g >= 1 ? (g == g.rounded() ? "\(Int(g)) GB" : String(format: "%.1f GB", g)) : "\(memMb) MB"
        return "\(c) CPU\(cpu == 1 ? "" : "s"), \(mem)"
    }
    /// "after 30 min with no visits", or that it never stops.
    static func idleWords(minutes: Int, never: Bool) -> String {
        never ? "never" : "after \(minutes) min with no visits"
    }
    static func host(_ slug: String) -> String { "\(slug).\(domain)" }

    /// "Tidepool Labs" -> "tidepool-labs": lowercase letters and digits, one dash between words, at most 40.
    static func slug(from name: String) -> String {
        var out = ""
        for ch in name.lowercased().unicodeScalars {
            if (ch.value >= 97 && ch.value <= 122) || (ch.value >= 48 && ch.value <= 57) {
                out.unicodeScalars.append(ch)
            } else if !out.hasSuffix("-") {
                out += "-"
            }
        }
        out = String(out.drop { $0 == "-" }.prefix(40))
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    /// Why a link name would be refused, in words; nil when it is fine. (The Core also refuses reserved names.)
    static func slugProblem(_ slug: String) -> String? {
        if slug.count < 2 { return "Use at least 2 letters or digits for the link." }
        if slug.count > 40 { return "The link can be at most 40 characters." }
        if !(slug.first?.isASCII == true && slug.first?.isLetter == true) {
            return "The link has to start with a letter."
        }
        if slug.contains(where: { !($0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-")) }) {
            return "Use lowercase letters, digits and dashes in the link."
        }
        return nil
    }

    static func nameProblem(_ name: String) -> String? {
        let t = name.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "Give the project a name." }
        if t.count > 100 { return "The name can be at most 100 characters." }
        return nil
    }

    /// A repo link typed or pasted by hand: `https://`, `ssh://` or `git@host:org/repo`. The Core checks again.
    static func repo(fromLink link: String) -> (name: String, url: String)? {
        let url = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !url.contains(where: \.isWhitespace) else { return nil }
        let scp = !url.contains("://") && url.contains("@") && url.contains(":")
        if url.hasPrefix("https://") || url.hasPrefix("ssh://") {
            // A password in the link would be stored in the Core; refuse it before it leaves this Mac.
            let authority = url.drop { $0 != "/" }.dropFirst(2).prefix { $0 != "/" }
            if url.hasPrefix("https://"), authority.contains("@") { return nil }
        } else if !scp {
            return nil
        }
        var last = url.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        if last.hasSuffix(".git") { last.removeLast(4) }
        let name = String(last.map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) ? $0 : "-" })
            .drop { $0 == "." || $0 == "-" }
        guard !name.isEmpty, name.count <= 100 else { return nil }
        return (String(name), url)
    }
}

/// A repo the person can pick from GitHub (or paste): grouped by org in the picker.
struct PickRepo: Identifiable, Hashable, Sendable {
    let org: String
    let name: String
    let url: String
    var language: String?
    var updatedAt: Date?
    var id: String { url }
    /// "Go · updated 2 h ago".
    func detail(now: Date) -> String {
        var parts: [String] = []
        if let language { parts.append(language) }
        if let updatedAt { parts.append("updated \(Self.ago(updatedAt, now))") }
        return parts.joined(separator: " · ")
    }
    static func ago(_ d: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(d)))
        if s < 3600 { return "just now" }
        if s < 86_400 { return "\(s / 3600) h ago" }
        let days = s / 86_400
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        return days < 14 ? "last week" : "\(days / 7) weeks ago"
    }
}

/// Where the picker's repos come from: the Core's GitHub list (`LiveRepoCatalog`).
protocol RepoCatalog: Sendable {
    /// Nil when there is no GitHub connection (or this Core cannot list repos): the picker then says "Connect GitHub".
    func repos() async throws -> [PickRepo]?
}

struct NoRepoCatalog: RepoCatalog {
    func repos() async throws -> [PickRepo]? { nil }
}

enum ProjectsLoad: Equatable {
    case loading
    case ready
    case failed(String)
    case notConnected
}

/// Colours chosen on this Mac, by link name (the Core has no colour field yet).
@MainActor
final class ProjectColours {
    private let defaults: UserDefaults
    static let key = "ainkrad.core.projects.accents"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func colour(_ slug: String) -> ProjectColour {
        let all = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        return all[slug].flatMap(ProjectColour.init(rawValue:)) ?? .standard(for: slug)
    }
    func set(_ colour: ProjectColour, for slug: String) {
        var all = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        all[slug] = colour.rawValue
        defaults.set(all, forKey: Self.key)
    }
}

/// A project as other apps see it: the Core's id as text (the Design module's links use text ids) and its name.
public struct ProjectRef: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
