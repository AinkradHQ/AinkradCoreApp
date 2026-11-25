import CoreUI
import Foundation

// The host page's decisions, as plain values the tests pin: a metric's tone, the commands and their keys, the history's days
// and filters, and what a page-level failure says and fixes.

/// How loud a health number is: blue under 70 %, amber over 70, red over 85 (the same lines as the map's load bars).
enum HealthTone {
    static func percent(_ p: Double?) -> Tone {
        guard let p else { return .queue }
        return p > 85 ? .fail : p > 70 ? .warn : .run
    }
    /// The load average per core: busy over 1, overloaded over 1.5.
    static func load(_ load1: Double?, cpus: Int?) -> Tone {
        guard let load1, let cpus, cpus > 0 else { return .queue }
        let perCore = load1 / Double(cpus)
        return perCore > 1.5 ? .fail : perCore > 1 ? .warn : .run
    }
    /// The word beside an amber or red tile.
    static func word(_ t: Tone) -> String? { t == .fail ? "High" : t == .warn ? "Busy" : nil }
}

/// What New Command holds: a name, one line to run, and whether it asks before it runs.
struct CommandDraft: Equatable, Sendable {
    var name = ""
    var command = ""
    var confirm = false

    /// The Core's own rules, in words: a 1 to 64 character name with no space around it, one line of at most 1000.
    var problem: String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Give the command a name." }
        if n.count > 64 { return "Keep the name to 64 characters." }
        if n.lowercased().hasPrefix("lc_") { return "A name cannot start with lc_." }
        let c = command.trimmingCharacters(in: .whitespaces)
        if c.isEmpty { return "Type the command to run." }
        if c.contains("\n") || c.count > 1000 { return "One line of at most 1000 characters." }
        return nil
    }
}

/// The cards of the pre-set commands: the saved ones meant for this host, then the built-ins that are not saved yet (a
/// built-in is saved in the Core the first time it runs, so it follows the same gate as every command).
enum HostCommandList {
    struct Item: Identifiable, Equatable {
        let command: PresetCommand
        /// Not saved in the Core yet: Run saves it first.
        let builtIn: Bool
        var id: String { command.id }
    }

    static let builtIns: [PresetCommand] = [
        b("disk", "Disk usage", "df -h -x tmpfs -x devtmpfs", "How full each disk is", readOnly: true),
        b(
            "memory", "Memory and top processes", "ps aux --sort=-%mem | head -n 15", "What uses the memory",
            readOnly: true),
        b("syslog", "Tail the system log", "tail -n 200 /var/log/syslog", "The last 200 lines", readOnly: true),
        b(
            "docker", "Docker containers", "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Image}}'",
            "What is running", readOnly: true),
        b("restart", "Restart nginx", "sudo systemctl restart nginx", "Asks before it runs", confirm: true),
        b(
            "update", "Update packages", "sudo apt-get update && sudo apt-get -y upgrade", "Asks before it runs",
            confirm: true),
    ]

    private static func b(
        _ id: String, _ name: String, _ step: String, _ line: String, readOnly: Bool = false, confirm: Bool = false
    ) -> PresetCommand {
        PresetCommand(
            id: "builtin-\(id)", name: name, description: line, steps: [step], scopeKind: nil, scopeValue: nil,
            readOnly: readOnly, confirm: confirm)
    }

    /// Saved first (the Core's order, by name), then the built-ins whose name and line are not saved yet. A Mac host gets no
    /// built-ins: they are Linux commands.
    static func items(saved: [PresetCommand], host: HostItem) -> [Item] {
        let fits = saved.filter { $0.fits(host) }
        let names = Set(fits.map { $0.name.lowercased() })
        let lines = Set(fits.flatMap(\.steps))
        let extra =
            host.os == "darwin"
            ? [] : builtIns.filter { !names.contains($0.name.lowercased()) && !lines.contains($0.steps[0]) }
        return fits.map { Item(command: $0, builtIn: false) } + extra.map { Item(command: $0, builtIn: true) }
    }

    /// ⌥1 … ⌥9 run the first nine cards (⌘2 is Files and ⌘, is Access on this page).
    static func key(_ index: Int) -> Character? {
        (0..<9).contains(index) ? Character(String(index + 1)) : nil
    }
    static func keyWord(_ index: Int) -> String? { key(index).map { "⌥\($0)" } }

    /// The card's glyph, from what the command runs.
    static func symbol(_ c: PresetCommand) -> String {
        let s = (c.steps.first ?? "").lowercased()
        func has(_ words: String...) -> Bool { words.contains { s.contains($0) } }
        if c.steps.count > 1 { return "list.number" }
        if has("df ", "du ", "ncdu") { return "internaldrive" }
        if has("free", "top", "ps aux", "vmstat") { return "memorychip" }
        if has("docker", "podman", "kubectl") { return "shippingbox" }
        if has("tail", "journalctl", "log") { return "doc.text.magnifyingglass" }
        if has("systemctl", "service ", "restart", "reload") { return "arrow.clockwise" }
        if has("apt", "dnf", "yum", "brew", "upgrade") { return "arrow.down.circle" }
        return "chevron.right"
    }
}

/// The host's history as a timeline: newest first, filtered by who, cut into days.
enum HostTimeline {
    struct Day: Identifiable, Equatable {
        let title: String
        let events: [HostEvent]
        var id: String { title }
    }

    static func shown(_ all: [HostEvent], who: HostEvent.Who?) -> [HostEvent] {
        all.filter { who == nil || $0.who == who }
            .sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
    }

    static func days(_ events: [HostEvent], now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        var out: [Day] = []
        for e in events {
            let t = title(e.at, now: now, calendar: calendar)
            if out.last?.title == t {
                out[out.count - 1] = Day(title: t, events: out[out.count - 1].events + [e])
            } else {
                out.append(Day(title: t, events: [e]))
            }
        }
        return out
    }

    static func title(_ d: Date?, now: Date, calendar: Calendar) -> String {
        guard let d else { return "Earlier" }
        if calendar.isDate(d, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) {
            return "Yesterday"
        }
        return d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    /// The filter chips, in order: everything, then each kind of actor.
    static let filters: [(who: HostEvent.Who?, title: String)] = [
        (nil, "All"), (.you, "You"), (.ai, "AI"), (.fleet, "Fleet"), (.system, "Alerts"),
    ]
}

/// A failure that stops the whole page, with the words and the fix the state card shows.
struct HostProblem: Equatable {
    enum Fix: Equatable { case updates, access, none }
    let symbol: String
    let title: String
    let line: String
    let fix: Fix

    /// nil for a failure that belongs to one action (a toast or the card that asked), not to the page.
    init?(_ e: LeylineFailure) {
        switch e.code {
        case "runner_cannot_ssh", "runner_cannot_sftp":
            self.init(
                symbol: "arrow.down.circle", title: "This runner can’t reach hosts yet",
                line: "Update your Core and its runner in Settings → Updates. Then try again.", fix: .updates)
        case "no_runner":
            self.init(
                symbol: "server.rack", title: "No runner can reach this host",
                line: "Pick the runner that reaches it in Access.", fix: .access)
        default: return nil
        }
    }

    init(symbol: String, title: String, line: String, fix: Fix) {
        self.symbol = symbol
        self.title = title
        self.line = line
        self.fix = fix
    }
}
