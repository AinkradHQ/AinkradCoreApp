import Foundation
import Shell

/// What the setup's "About you" pages collect (D-9), and the plain sentences it becomes in the Brain's Me space. Pure data:
/// every page edits it, `items` turns it into the `PUT /brain/me/profile` body.
struct SetupProfile: Equatable {
    struct Item: Equatable, Sendable {
        let key: String
        let body: String
    }
    /// Hours of a day, `from` up to `to`, both 0...24.
    struct Band: Equatable, Comparable {
        var from: Int
        var to: Int
        static func < (a: Band, b: Band) -> Bool { a.from < b.from }
        var text: String { "\(from)-\(to)" }
    }
    enum HoursMode: String, Equatable, CaseIterable { case set, vary, onCall }

    // The choices, in the order the pages show them.
    static let roles = ["Build software", "Design", "Write and plan", "Research", "Run a team", "Something else"]
    static let workKinds = ["New products", "Client projects", "Maintenance", "Open source", "Learning", "Operations"]
    static let languages = ["Swift", "TypeScript", "Python", "Go", "Rust", "PHP", "Java", "C#", "Ruby", "Kotlin"]
    static let tools = [
        "Git", "Docker", "Xcode", "VS Code", "Figma", "Linear", "Notion", "Slack", "GitHub", "Postgres",
    ]
    static let hosting = ["This Mac", "A home server", "Cloud", "Containers"]
    static let tones = [
        (
            "Short and direct", "The answer first, no extras.",
            "Likes short, direct answers: the answer first, no extras."
        ),
        ("Friendly and clear", "Plain words, a bit of warmth.", "Likes friendly, clear answers in plain words."),
        ("Detailed", "Full reasoning, step by step.", "Likes detailed answers with the full reasoning, step by step."),
    ]
    static let goals = [
        "Planning my day", "Meeting notes", "Status updates", "Code review", "Research", "Drafting text", "Reminders",
        "Email triage", "Tidying notes",
    ]
    static let spoken = ["English", "Arabic", "German", "French", "Spanish", "Turkish", "Hindi", "Chinese"]
    static let focus = [
        "Shipping features", "Quality", "Learning", "Writing", "Health", "Side projects", "Saving time",
    ]
    static let routines = ["Morning review", "Daily stand-up", "Weekly planning", "Friday wrap-up", "Evening shutdown"]
    static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let quickHours: [(String, Band)] = [
        ("Early", Band(from: 6, to: 14)), ("Standard", Band(from: 9, to: 17)), ("Late", Band(from: 12, to: 20)),
        ("Night owl", Band(from: 16, to: 24)),
    ]
    /// The ranges the `+` button tries, in order, for a day's next range.
    static let extraBands = [Band(from: 9, to: 13), Band(from: 14, to: 18), Band(from: 19, to: 22)]

    /// What to call the person: the first About you question. Also kept on this Mac for the Home greeting.
    var name = ""
    var roleSet: Set<String> = []
    var workSet: Set<String> = []
    var languageSet: Set<String> = []
    var toolSet: Set<String> = []
    var hostingSet: Set<String> = []
    var hoursMode = HoursMode.set
    var hours: [String: [Band]] = Dictionary(
        uniqueKeysWithValues: SetupProfile.days.enumerated().map { i, d in (d, i < 5 ? [Band(from: 9, to: 17)] : []) })
    var quiet: [Band] = [Band(from: 22, to: 24), Band(from: 0, to: 6)]
    var timeZone = TimeZone.current.identifier
    /// Index into `tones`; nil until one is picked.
    var tone: Int?
    var goalSet: Set<String> = []
    var spokenSet: Set<String> = []
    var focusSet: Set<String> = []
    var routineSet: Set<String> = []
    /// Whether the hours page was ever touched: the standard week is a default, not an answer.
    var hoursTouched = false

    // MARK: hours

    /// Quick hours: every working day gets the range (Monday to Friday when none is on).
    mutating func applyQuick(_ b: Band) {
        hoursTouched = true
        var on = Self.days.filter { !(hours[$0] ?? []).isEmpty }
        if on.isEmpty { on = Array(Self.days.prefix(5)) }
        for d in on { hours[d] = [b] }
    }

    mutating func toggleDay(_ d: String) {
        hoursTouched = true
        hours[d] = (hours[d] ?? []).isEmpty ? [Band(from: 9, to: 17)] : []
    }

    /// Adds the first range that fits beside the day's others. False when the day is full.
    @discardableResult
    mutating func addRange(_ d: String) -> Bool {
        let now = hours[d] ?? []
        guard let b = Self.extraBands.first(where: { c in now.allSatisfy { c.to <= $0.from || c.from >= $0.to } })
        else { return false }
        hoursTouched = true
        hours[d] = (now + [b]).sorted()
        return true
    }

    /// Replaces a day's range, or removes it when `to` is nil.
    mutating func setRange(_ d: String, at i: Int, to b: Band?) {
        guard var list = hours[d], list.indices.contains(i) else { return }
        hoursTouched = true
        if let b { list[i] = b } else { list.remove(at: i) }
        hours[d] = list.sorted()
    }

    // MARK: sentences

    private static func join(_ options: [String], _ chosen: Set<String>) -> String {
        options.filter(chosen.contains).joined(separator: ", ")
    }

    /// "Mon-Tue 9-17, Wed 9-13 and 14-18, Sat-Sun off": neighbouring days with the same hours share one phrase.
    static func hoursText(_ hours: [String: [Band]]) -> String {
        var groups: [(first: String, last: String, text: String)] = []
        for d in days {
            let b = hours[d] ?? []
            let text = b.isEmpty ? "off" : b.sorted().map(\.text).joined(separator: " and ")
            if let g = groups.last, g.text == text {
                groups[groups.count - 1].last = d
            } else {
                groups.append((d, d, text))
            }
        }
        return groups.map { ($0.first == $0.last ? $0.first : "\($0.first)-\($0.last)") + " " + $0.text }
            .joined(separator: ", ")
    }

    /// The answers as one sentence each; a page that was skipped adds nothing. The Core keeps 200 characters of each.
    var items: [Item] {
        var out: [Item] = []
        func add(_ key: String, _ lead: String, _ list: String) {
            if !list.isEmpty { out.append(Item(key: key, body: String((lead + list + ".").prefix(200)))) }
        }
        add("name", "Prefers to be called ", UserProfile.clean(name))
        add("role", "Does this kind of work: ", Self.join(Self.roles, roleSet))
        add("work", "Mostly works on: ", Self.join(Self.workKinds, workSet))
        add("languages", "Programs in: ", Self.join(Self.languages, languageSet))
        add("tools", "Uses these tools: ", Self.join(Self.tools, toolSet))
        add("hosting", "Runs things on: ", Self.join(Self.hosting, hostingSet))
        switch hoursMode {
        case .set:
            if hoursTouched {
                out.append(
                    Item(key: "hours", body: String("Works \(Self.hoursText(hours)) (\(timeZone)).".prefix(200))))
            }
        case .vary:
            out.append(Item(key: "hours", body: "Work hours change from day to day. Ask rather than assume."))
        case .onCall:
            let q = quiet.sorted().map(\.text).joined(separator: " and ")
            let line =
                q.isEmpty
                ? "On call: any hour can be work time."
                : "On call: any hour is work time except quiet hours \(q) (\(timeZone))."
            out.append(Item(key: "hours", body: String(line.prefix(200))))
        }
        if let tone, Self.tones.indices.contains(tone) { out.append(Item(key: "tone", body: Self.tones[tone].2)) }
        add("goals", "Wants help with: ", Self.join(Self.goals, goalSet))
        add("spoken", "Speaks: ", Self.join(Self.spoken, spokenSet))
        add("focus", "Focuses on: ", Self.join(Self.focus, focusSet))
        add("routines", "Routines: ", Self.join(Self.routines, routineSet))
        return out
    }
}
