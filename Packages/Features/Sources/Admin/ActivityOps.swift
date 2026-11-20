import CoreKit
import CoreUI
import SwiftUI

// Activity, Ops (E2-6, mockup 11b): how the Core machine is doing. Processor, Memory and Disk of the whole host with a line over
// the last day, the backups (a square a day, the next one, "Back up now") and the runner fleet. A Core that does not say the host
// figures (a Core on a Mac, or before 0.10) shows what it has: the Core process's own. Every bar and line draws in once and sits
// still under Reduce Motion; nothing follows the pointer.

/// The words of the Ops cards, as pure functions.
enum ActivityWords {
    /// "Quiet", "Busy", "Heavy" for a CPU share.
    static func load(_ pct: Double) -> String { pct < 40 ? "Quiet" : pct < 75 ? "Busy" : "Heavy" }
    /// "Plenty free", "Getting full", "Almost full" for a share in use.
    static func room(_ pct: Double) -> String { pct < 70 ? "Plenty free" : pct < 90 ? "Getting full" : "Almost full" }

    static func size(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    /// "Today 10:42", "Yesterday 22:00", "Mon 22:00", "12 Nov 22:00".
    static func last(_ at: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = at.formatted(.dateTime.hour().minute())
        if calendar.isDate(at, inSameDayAs: now) { return "Today \(time)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(at, inSameDayAs: y) {
            return "Yesterday \(time)"
        }
        if now.timeIntervalSince(at) < 6 * 86_400 { return "\(at.formatted(.dateTime.weekday(.abbreviated))) \(time)" }
        return "\(at.formatted(.dateTime.day().month(.abbreviated))) \(time)"
    }

    /// "Next one tonight at 22:00", "Next one tomorrow at 03:00", "Next one Mon at 03:00".
    static func next(_ at: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = at.formatted(.dateTime.hour().minute())
        if calendar.isDate(at, inSameDayAs: now) {
            return "Next one \(calendar.component(.hour, from: at) >= 18 ? "tonight" : "today") at \(time)"
        }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(at, inSameDayAs: t) {
            return "Next one tomorrow at \(time)"
        }
        return "Next one \(at.formatted(.dateTime.weekday(.abbreviated))) at \(time)"
    }

    /// "Core restarted on request", "Runner restarted on request, it did not work".
    static func restart(_ r: CoreRestart) -> (who: String, what: String) {
        let who = r.target == "core" ? "Core" : "Runner"
        return (who, r.worked ? "restarted on request" : "could not be restarted")
    }

    /// The fleet in one line: "1 working, 2 idle, 1 offline", leaving out the zeros.
    static func fleet(_ f: CoreFleet) -> String {
        let parts = [(f.working, "working"), (f.idle, "idle"), (f.offline, "offline")].filter { $0.0 > 0 }
        return parts.isEmpty ? "No runners yet" : parts.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }
}

struct OpsHostCards: View {
    let admin: AdminModel
    @Environment(\.corePalette) private var palette

    private var ops: OpsModel { admin.ops }

    var body: some View {
        let points = ops.coreHistory
        let cpu = ActivityStats.readings(points) { $0.hostCpuPct ?? $0.cpuPct }
        let ram = ActivityStats.readings(points) { p in
            guard let u = p.ramUsedBytes, let t = p.ramTotalBytes, t > 0 else { return p.memoryBytes }
            return u / t * 100
        }
        let disk = ActivityStats.readings(points) { $0.diskUsedPct }
        let host = ops.host
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("How your Core is doing").coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer(minLength: 0)
                Text("One reading a minute").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                processor(cpu, host: host)
                memory(ram, host: host)
                disk(disk, host: host, last: points.last)
                OpsBackupCard(ops: ops, index: 3)
            }
            if let fleet = host?.fleet {
                OpsFleetCard(fleet: fleet) { admin.host.shell.launcher.entry("runners")?.run() }
            }
            if !ops.restarts.isEmpty { OpsRestartsCard(restarts: ops.restarts) }
        }
        .accessibilityElement(children: .contain)
    }

    private func processor(_ series: [Double], host: CoreHostFacts?) -> some View {
        let now = host?.cpuPct ?? series.last
        return card(
            0, "Processor", big: now.map { "\(Int($0.rounded()))%" } ?? "–", small: nil,
            share: now.map { min($0, 100) / 100 },
            series: series, ceiling: max(100, series.max() ?? 0), note: now.map(ActivityWords.load))
    }

    private func memory(_ series: [Double], host: CoreHostFacts?) -> some View {
        if let u = host?.ramUsedBytes, let t = host?.ramTotalBytes, t > 0 {
            let pct = Double(u) / Double(t) * 100
            return card(
                1, "Memory", big: ActivityWords.size(Double(u)), small: " of \(ActivityWords.size(Double(t)))",
                share: pct / 100,
                series: series, ceiling: 100, note: ActivityWords.room(pct))
        }
        let own = ops.coreHistory.last?.memoryBytes
        return card(
            1, "Memory", big: own.map(ActivityWords.size) ?? "–", small: own == nil ? nil : " used by the Core",
            share: nil,
            series: series, ceiling: nil, note: nil)
    }

    private func disk(_ series: [Double], host: CoreHostFacts?, last: OpsPoint?) -> some View {
        let used = host?.diskUsedBytes.map(Double.init) ?? last?.diskUsedBytes
        let total = last?.diskTotalBytes
        let pct = last?.diskUsedPct ?? (used.flatMap { u in total.map { u / $0 * 100 } })
        let big = used.map(ActivityWords.size) ?? pct.map { "\(Int($0.rounded()))%" } ?? "–"
        return card(
            2, "Disk", big: big, small: total.map { " of \(ActivityWords.size($0))" }, share: pct.map { $0 / 100 },
            series: series, ceiling: 100, note: pct.map(ActivityWords.room))
    }

    private func card(
        _ i: Int, _ title: String, big: String, small: String?, share: Double?, series: [Double], ceiling: Double?,
        note: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(big).coreFont(size: MacTextSize.large, weight: .bold, design: .rounded).contentTransition(
                    .numericText())
                if let small { Text(small).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2) }
            }
            if let share { CoreMeter(share, low: share >= 0.9, label: title) }
            if series.count >= 2 { CoreSpark(series, ceiling: ceiling).chartReveal() }
            if let note { Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2) }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .modifier(RiseIn(index: i))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(big)\(small ?? "")")
    }
}

/// Backups: a square a day for the last week, when the last one was written, the next one, and "Back up now".
struct OpsBackupCard: View {
    let ops: OpsModel
    let index: Int
    @Environment(\.corePalette) private var palette

    var body: some View {
        let now = Date()
        let b = ops.backups
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Backups").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            Text(b?.history.first.map { ActivityWords.last($0.at, now: now) } ?? "None yet")
                .coreFont(size: MacTextSize.headline, weight: .bold)
            if let b {
                HStack(spacing: Space.s1) {
                    let days = b.days(7, now: now)
                    ForEach(days.indices, id: \.self) { i in
                        coreShape(Radius.chip / 2).fill(days[i] ? palette.primary : palette.track)
                            .frame(width: Space.s4, height: Space.s4)
                            .help(
                                Calendar.current.date(byAdding: .day, value: i - 6, to: now)?
                                    .formatted(.dateTime.weekday(.wide).day().month()) ?? "")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(days.filter { $0 }.count) of the last 7 days have a backup")
                if let next = b.nextAt, b.available {
                    Text(ActivityWords.next(next, now: now)).coreFont(size: MacTextSize.meta).foregroundStyle(
                        palette.text2)
                } else if let words = b.scheduleWords {
                    Text(words).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                if b.running {
                    Text("A backup is running").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                } else if b.lastResult.map({ $0 != "success" }) == true {
                    Text("The last backup did not finish").coreFont(size: MacTextSize.meta).foregroundStyle(
                        palette.warning)
                }
                if b.available {
                    AppActionTile(
                        title: ops.startingBackup || b.running ? "Backing up…" : "Back up now",
                        symbol: "externaldrive.badge.timemachine",
                        key: "", hue: GlassInk.slate
                    ) { Task { await ops.backUpNow() } }
                    .disabled(ops.startingBackup || b.running)
                } else {
                    Text(b.helper == "absent" ? "Backups run on the Core machine." : "The Core machine did not answer.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                if let note = ops.backupNote {
                    Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
            } else {
                Text("Not reported by this Core yet.").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .modifier(RiseIn(index: index))
        .accessibilityElement(children: .contain)
    }
}

/// Recent restarts (mockup 11b): a small tile, who restarted and why, and when. The rows rise in once and sit still under Reduce
/// Motion (`RiseIn`).
struct OpsRestartsCard: View {
    let restarts: [CoreRestart]
    @Environment(\.corePalette) private var palette

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Recent restarts").coreFont(size: MacTextSize.headline, weight: .semibold)
            ForEach(Array(restarts.prefix(3).enumerated()), id: \.element.id) { i, r in
                let w = ActivityWords.restart(r)
                HStack(spacing: Space.s2) {
                    Image(systemName: r.target == "core" ? "arrow.triangle.2.circlepath" : "server.rack")
                        .coreFont(size: MacTextSize.meta)
                        .frame(width: Space.s6, height: Space.s6)
                        .background(coreShape(Radius.chip).fill(palette.track))
                        .accessibilityHidden(true)
                    (Text(w.who).fontWeight(.bold) + Text(" \(w.what)")).coreFont(size: MacTextSize.body)
                    Spacer(minLength: 0)
                    Text(ActivityWords.last(r.at, now: now)).coreFont(size: MacTextSize.meta).foregroundStyle(
                        palette.text2)
                }
                .modifier(RiseIn(index: i))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }
}

/// The runner fleet: how many are working, idle and offline, and each one with how busy it is.
struct OpsFleetCard: View {
    let fleet: CoreFleet
    let open: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Runners").coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(ActivityWords.fleet(fleet)).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                Spacer(minLength: 0)
                Button("Open Runners", action: open).buttonStyle(CoreButtonStyle(.plain))
            }
            ForEach(Array(fleet.runners.enumerated()), id: \.offset) { i, r in
                HStack(spacing: Space.s3) {
                    Text(r.name).coreFont(size: MacTextSize.body, weight: .medium).frame(
                        width: Space.s8 * 4, alignment: .leading)
                    CoreMeter(Double(r.busyPct ?? 0) / 100, low: (r.busyPct ?? 0) > 60, label: "\(r.name) busy")
                    CoreChip(Self.word(r.state), minWidth: Space.s8 * 2)
                    Text(r.state == "offline" ? "–" : "\(r.busyPct ?? 0)% busy").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(palette.text2).frame(width: Space.s8 * 2, alignment: .trailing)
                }
                .modifier(RiseIn(index: i))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }

    static func word(_ state: String) -> String {
        switch state {
        case "working": "Working"
        case "idle": "Idle"
        default: "Offline"
        }
    }
}
