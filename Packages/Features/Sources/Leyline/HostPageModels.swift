import Foundation

// What the host page shows, as values. The wire types decode the Core's JSON (snake case, see `LiveLeylineService.call`).

/// One agentless health check of a host (Y5-01). `nil` for a number the host did not report (only Linux reports them all).
struct HostHealth: Equatable, Sendable {
    enum State: String, Sendable { case up, down, unknown }
    var state: State
    var checkedAt: Date?
    var load1: Double?
    var cpus: Int?
    var memPct: Double?
    var diskPct: Double?
    var failedUnits: Int?
    /// Last samples, oldest first, 0...100, for the sparklines.
    var cpuSeries: [Double] = []
    var memSeries: [Double] = []
    var diskSeries: [Double] = []

    /// The load as a share of the cores.
    var cpuPct: Double? {
        guard let load1, let cpus, cpus > 0 else { return nil }
        return min(100, load1 / Double(cpus) * 100)
    }
}

struct HealthWire: Decodable {
    struct Sample: Decodable {
        let load1: Double?
        let cpus: Int?
        let memPct: Double?
        let diskPct: Double?
    }
    let state: String
    let checkedAt: String?
    let load1: Double?
    let cpus: Int?
    let memPct: Double?
    let diskPct: Double?
    let failedUnits: Int?
    let history: [Sample]?

    var item: HostHealth {
        let h = history ?? []
        return HostHealth(
            state: HostHealth.State(rawValue: state) ?? .unknown, checkedAt: checkedAt.flatMap(HostWire.date),
            load1: load1, cpus: cpus, memPct: memPct, diskPct: diskPct, failedUnits: failedUnits,
            cpuSeries: h.compactMap { s in s.load1.map { l in min(100, l / Double(max(s.cpus ?? cpus ?? 1, 1)) * 100) }
            },
            memSeries: h.compactMap(\.memPct), diskSeries: h.compactMap(\.diskPct))
    }
}

/// A pre-set command (`CommandView` of the Core): one to twenty steps, a scope, and two flags.
struct PresetCommand: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var description: String
    var steps: [String]
    /// `host`, `group`, `tag` or `project_role`; nil = every host.
    var scopeKind: String?
    var scopeValue: String?
    /// Safe for AI under "Read-only".
    var readOnly: Bool
    /// The Core refuses a run that does not say it was confirmed.
    var confirm: Bool

    /// The first step is what the card shows; more steps say how many.
    var line: String { steps.count > 1 ? "\(steps.first ?? "") · \(steps.count) steps" : (steps.first ?? "") }

    /// Whether the command is meant for this host. A scope the app cannot resolve (a project role) counts as "yes": the Core
    /// refuses a command that is not for the host (409) and the card says so.
    func fits(_ h: HostItem) -> Bool {
        guard let kind = scopeKind, let value = scopeValue else { return true }
        switch kind {
        case "host": return value == h.id || value == h.name
        case "group": return value == h.group
        case "tag": return h.tags.contains(value)
        default: return true
        }
    }
}

struct CommandWire: Decodable {
    struct Scope: Decodable {
        let kind: String
        let value: String
    }
    let id: String
    let name: String
    let description: String
    let steps: [String]
    let scope: Scope?
    let readOnly: Bool
    let confirm: Bool

    var item: PresetCommand {
        PresetCommand(
            id: id, name: name, description: description, steps: steps, scopeKind: scope?.kind,
            scopeValue: scope?.value, readOnly: readOnly, confirm: confirm)
    }
}

/// How a run on this host stands: the words are the Core's states.
struct CommandRun: Equatable, Sendable {
    enum State: String, Sendable {
        case queued
        case needsApproval = "needs_approval"
        case ok, failed, refused, skipped, running
    }
    let id: String
    var commandName: String
    var state: State
    var step: Int?
    var exitCode: Int?
    var durationMS: Int?
    /// Each step's command line and output, redacted by the Core, at most 64 KB.
    var output: String?
    /// When this Mac started it (the Core's run has its own times; this is for "2 min ago" on the card).
    var startedAt: Date?
    var finished: Bool { state != .running && state != .queued && state != .needsApproval }
}

struct RunStarted: Decodable {
    let run: String
    let state: String
}

struct RunWire: Decodable {
    struct Host: Decodable {
        let hostId: String
        let state: String
        let step: Int?
        let exitCode: Int?
        let durationMs: Int?
        let output: String?
    }
    let id: String
    let state: String
    let hosts: [Host]

    func item(host: String, name: String) -> CommandRun {
        let h = hosts.first { $0.hostId == host }
        // The run's own state decides until a host row exists (waiting for approval, denied).
        let state: CommandRun.State =
            h.flatMap { CommandRun.State(rawValue: $0.state) }
            ?? (self.state == "denied" ? .refused : self.state == "waiting_approval" ? .needsApproval : .running)
        return CommandRun(
            id: id, commandName: name, state: state, step: h?.step, exitCode: h?.exitCode, durationMS: h?.durationMs,
            output: h?.output)
    }
}

/// An entry of a remote folder, over SFTP.
struct RemoteFile: Identifiable, Equatable, Sendable, Hashable {
    enum Kind: String, Sendable { case file, dir, link }
    var id: String { path }
    let path: String
    let name: String
    let kind: Kind
    let size: Int64?
    let modified: Date?
    /// Where a link points (never followed here).
    let target: String?
    var isFolder: Bool { kind == .dir }
    /// A file that usually holds secrets is not drawn until a person asks with Touch ID.
    var mayHoldSecrets: Bool {
        let n = name.lowercased()
        return n == ".env" || n.hasPrefix(".env.") || n.hasSuffix(".pem") || n.hasSuffix(".key") || n.hasPrefix("id_")
            || n == "credentials" || n == ".netrc"
    }
}

struct RemoteFileWire: Decodable {
    let path: String
    let name: String
    let kind: String
    let size: Int64?
    let modified: String?
    let target: String?
    var item: RemoteFile {
        RemoteFile(
            path: path, name: name, kind: RemoteFile.Kind(rawValue: kind) ?? .file, size: size,
            modified: modified.flatMap(HostWire.date), target: target)
    }
}

/// Paths of the host: absolute, `/` separated. Nothing here touches a shell; the path is data for the Core.
enum RemotePath {
    static func parent(_ p: String) -> String {
        let parts = p.split(separator: "/")
        return parts.count <= 1 ? "/" : "/" + parts.dropLast().joined(separator: "/")
    }
    static func join(_ dir: String, _ name: String) -> String { dir == "/" ? "/" + name : dir + "/" + name }
    /// "/srv/app" -> [("/", "/"), ("/srv", "srv"), ("/srv/app", "app")].
    static func crumbs(_ p: String) -> [(path: String, name: String)] {
        var out = [(path: "/", name: "/")]
        var acc = ""
        for part in p.split(separator: "/") {
            acc += "/" + part
            out.append((path: acc, name: String(part)))
        }
        return out
    }
    /// A file name that is safe to create in a local folder: no slash, no leading dot dot.
    static func safeName(_ n: String) -> String { n.replacingOccurrences(of: "/", with: "_") }
}

/// One thing that happened on a host: a terminal, a command, an AI request, a Mac-direct lease, an alert.
struct HostEvent: Identifiable, Equatable, Sendable {
    enum Who: String, Sendable, CaseIterable { case you, ai, fleet, system }
    let id: String
    let who: Who
    /// "terminal", "df -h", "Mac-direct", "disk 88%".
    let what: String
    /// "relayed · recorded", "read-only · auto".
    let detail: String
    let at: Date?
    /// Set when a recording exists to replay (output only, redacted by the Core).
    let recording: String?
    var minutes: Int?
}

struct HostEventWire: Decodable {
    let id: String
    let who: String
    let what: String
    let detail: String
    let at: String
    let recording: String?
    let minutes: Int?
    var item: HostEvent {
        HostEvent(
            id: id, who: HostEvent.Who(rawValue: who) ?? .system, what: what, detail: detail,
            at: HostWire.date(at), recording: recording, minutes: minutes)
    }
}

/// A recording: the frames of one terminal, output only, as asciicast `[seconds, "o", text]`.
struct Recording: Equatable, Sendable {
    struct Frame: Equatable, Sendable {
        let at: Double
        let text: String
    }
    var frames: [Frame]
    var length: Double { frames.last?.at ?? 0 }

    /// Reads the Core's cast: a header line, then one JSON array per line. Anything that is not an output frame is dropped.
    static func parse(_ data: Data) -> Recording {
        var frames: [Frame] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst() {
            guard let a = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [Any], a.count >= 3,
                let t = a[0] as? Double, a[1] as? String == "o", let s = a[2] as? String
            else { continue }
            frames.append(Frame(at: t, text: s))
        }
        return Recording(frames: frames)
    }

    /// What the screen holds at `t`: every frame up to it, with the control bytes left out (the replay is a text view, not a
    /// terminal emulator).
    func text(at t: Double) -> String {
        let raw = frames.prefix { $0.at <= t }.map(\.text).joined()
        return Self.plain(raw)
    }

    static func plain(_ s: String) -> String {
        var out = ""
        var it = s.unicodeScalars.makeIterator()
        while let c = it.next() {
            if c == "\u{1B}" {
                // CSI: ESC [ params final-byte (0x40...0x7E). Other escapes lose their one next byte.
                guard let n = it.next() else { break }
                if n == "[" { while let f = it.next(), !(0x40...0x7E).contains(f.value) {} }
            } else if c == "\r" {
                continue
            } else if c == "\n" || c == "\t" || c.value >= 0x20 {
                out.unicodeScalars.append(c)
            }
        }
        return out
    }
}

/// The Mac-direct lease: the Mac's own `ssh` borrows the key for a few minutes, only for this host (Y6-01).
struct DirectLease: Equatable, Sendable {
    /// The command that connects through the lease's socket.
    let command: String
    let expiresAt: Date?
}

struct DirectWire: Decodable {
    /// What to run in a terminal on the Mac: it reaches the host, and only the host.
    let ready: String
    let expiresAt: String?
    var item: DirectLease { DirectLease(command: ready, expiresAt: expiresAt.flatMap(HostWire.date)) }
}

/// One terminal session on a host, as the Core's history lists it (`SessionRow`).
struct HostSession: Identifiable, Equatable, Sendable {
    let id: String
    let terminal: String
    /// `person:d_…` or `session:…`.
    let principal: String
    let startedAt: Date?
    let endedAt: Date?
    /// A recording exists to replay.
    let recorded: Bool
    /// Recording right now (not ended, not paused).
    let recording: Bool

    var live: Bool { endedAt == nil }
    var paused: Bool { live && recorded && !recording }
}

struct SessionWire: Decodable {
    let id: String
    let terminal: String
    let principal: String
    let startedAt: String
    let endedAt: String?
    let endReason: String?
    let recorded: Bool
    let recording: Bool

    var item: HostSession {
        HostSession(
            id: id, terminal: terminal, principal: principal, startedAt: HostWire.date(startedAt),
            endedAt: endedAt.flatMap(HostWire.date), recorded: recorded, recording: recording)
    }

    /// The history row of a terminal session.
    var event: HostEvent {
        let start = HostWire.date(startedAt)
        let end = endedAt.flatMap(HostWire.date)
        let who: HostEvent.Who = principal.hasPrefix("session:") ? .ai : principal.hasPrefix("person:") ? .you : .system
        var detail = "relayed"
        if recorded { detail += " · recorded" }
        if let endReason, endReason != "exited" { detail += " · \(endReason.replacingOccurrences(of: "_", with: " "))" }
        return HostEvent(
            id: id, who: who, what: "terminal", detail: detail, at: start, recording: recorded ? id : nil,
            minutes: start.flatMap { s in end.map { max(0, Int($0.timeIntervalSince(s) / 60)) } })
    }
}

/// The runner install the Core started (it runs by itself; an older Core also opened a terminal with the installer typed in),
/// and an invite that ends in 15 minutes.
struct RunnerInstall: Equatable, Sendable {
    /// A terminal the Core opened with the installer in it: nil now, the install runs by itself (older Cores still send one).
    let terminal: String?
    let expiresAt: Date?
}

struct RunnerInstallWire: Decodable {
    struct Session: Decodable { let terminal: String }
    let session: Session?
    let expiresAt: String
    var item: RunnerInstall { RunnerInstall(terminal: session?.terminal, expiresAt: HostWire.date(expiresAt)) }
}

/// The machine that claimed the invite: the one check the person has that it is the machine they meant, because the invite is
/// its own approval. Read from the Core's device list (name, platform, key fingerprint).
public struct RunnerClaimer: Equatable, Sendable {
    public let id: String
    public let name: String
    public let platform: String?
    public let fingerprint: String?
    public init(id: String, name: String, platform: String?, fingerprint: String?) {
        self.id = id
        self.name = name
        self.platform = platform
        self.fingerprint = fingerprint
    }
}

/// A host terminal the Core opened: the id is the Core terminal the existing pane attaches to.
struct HostTerminalOpened: Decodable {
    let id: String
    let hostId: String
    let terminal: String
}
