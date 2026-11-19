import CoreUI
import SwiftUI

/// Where a runner stands, in the four words of the Runners screen (mockup 12). Only what the Core reports: a runner
/// that does not answer is "Not answering", never made out to be installing something.
enum RunnerBucket: String, CaseIterable, Identifiable, Sendable {
    case working = "Working"
    case idle = "Idle"
    case attention = "Not answering"
    case offline = "Offline"
    var id: String { rawValue }

    init(of r: RunnerItem) {
        switch RunnerStatus(r) {
        case .off: self = .offline
        case .degraded: self = .attention
        case .busy: self = .working
        case .ok:
            let used = (r.slots?.agentsUsed ?? 0) + (r.slots?.terminalsUsed ?? 0)
            self = used > 0 || (r.slots == nil && r.load > 0) ? .working : .idle
        }
    }

    var symbol: String {
        switch self {
        case .working: "play.fill"
        case .idle: "pause.fill"
        case .attention: "exclamationmark.triangle"
        case .offline: "power"
        }
    }

    var tone: Tone {
        switch self {
        case .working: .run
        case .idle: .queue
        case .attention: .warn
        case .offline: .fail
        }
    }

    /// "2 are busy, 1 is not answering."; empty when there is nothing to say.
    static func sentence(_ runners: [RunnerItem]) -> String {
        let counts = Dictionary(grouping: runners, by: { RunnerBucket(of: $0) }).mapValues(\.count)
        var parts: [String] = []
        if let n = counts[.working] { parts.append("\(n) \(n == 1 ? "is" : "are") busy") }
        if let n = counts[.attention] { parts.append("\(n) \(n == 1 ? "is" : "are") not answering") }
        if let n = counts[.offline] { parts.append("\(n) \(n == 1 ? "is" : "are") offline") }
        guard let first = parts.first else { return "" }
        let rest = parts.dropFirst().map { ", " + $0 }.joined()
        let head = first.prefix(1).uppercased() + String(first.dropFirst())
        return " \(head)\(rest)."
    }
}

/// Four counts you can click to show only those runners.
struct RunnerSummary: View {
    @Bindable var model: TerminalsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s3) {
            ForEach(RunnerBucket.allCases) { b in
                let n = model.runners.filter { RunnerBucket(of: $0) == b }.count
                let on = model.runnerBucket == b
                Button {
                    model.runnerBucket = on ? nil : b
                } label: {
                    HStack(spacing: Space.s3) {
                        IconTile(b.symbol, hue: palette.tone(b.tone).ink, size: 36)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(n)").coreFont(size: MacTextSize.large, weight: .semibold).monospacedDigit()
                            Text(b.rawValue).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                    .coreWell(active: on)
                    .contentShape(coreShape(Radius.cardMac))
                }
                .buttonStyle(.coreQuietPress)
                .help(on ? "Show every runner" : "Show only runners that are \(b.rawValue.lowercased())")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// One runner on one line: name and what it is doing, the tools it has, its state, and the way into its page.
struct RunnerRow: View {
    let model: TerminalsModel
    let runner: RunnerItem
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    private static let harnesses = ["Claude", "Codex", "OpenCode", "Antigravity"]

    var body: some View {
        let facts = RunnerFacts(runner: runner)
        let bucket = RunnerBucket(of: runner)
        let mine = model.host.thisMacRunnerID == runner.id
        Button {
            model.runnerDetail = runner.id
        } label: {
            HStack(spacing: Space.s3) {
                IconTile(
                    mine ? "laptopcomputer" : "server.rack", hue: bucket == .offline ? GlassInk.slate : GlassInk.blue,
                    size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.s2) {
                        Text(runner.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                        if runner.builtIn { BuiltInBadge() }
                        if mine { ThisMacBadge() }
                    }
                    Text(Self.line(runner, bucket, terminals: model.onRunner(runner.id)))
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
                }
                .frame(width: 240, alignment: .leading)
                HStack(spacing: Space.s1) {
                    ToolChip(name: "Terminals", on: facts.terminalsOn)
                    ForEach(Self.harnesses, id: \.self) { h in
                        ToolChip(name: h, on: runner.tools.keys.contains { $0.lowercased() == h.lowercased() })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StateBadge(bucket.rawValue, tone: bucket.tone, symbol: bucket.symbol)
                Image(systemName: "chevron.right").foregroundStyle(palette.text2).accessibilityHidden(true)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .coreWell(active: hovering)
            .opacity(bucket == .offline && !hovering ? 0.62 : 1)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.coreQuietPress)
        .onHover { hovering = $0 }
        .help("Open \(runner.name)")
        .accessibilityLabel("\(runner.name), \(bucket.rawValue)")
    }

    /// "Working on 2 AI sessions and 1 terminal", "Idle · ready for work", "Offline · last seen 2 hours ago".
    static func line(_ r: RunnerItem, _ b: RunnerBucket, terminals: Int) -> String {
        switch b {
        case .working:
            let a = r.slots?.agentsUsed ?? 0
            let t = r.slots?.terminalsUsed ?? terminals
            return a + t > 0 ? "Working on \(RunnerFacts.stops(agents: a, terminals: t))" : "Working"
        case .idle: return "Idle · ready for work"
        case .attention: return "Online, but not answering"
        case .offline:
            guard let d = r.lastSeen else { return "Offline" }
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            return "Offline · last seen \(f.localizedString(for: d, relativeTo: Date()))"
        }
    }
}

/// A tool a runner has, as a small rounded tag; a missing one is quiet.
struct ToolChip: View {
    let name: String
    let on: Bool
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(name).coreFont(size: MacTextSize.meta, weight: .medium).lineLimit(1).fixedSize()
            .foregroundStyle(on ? GlassInk.primary : palette.text2.opacity(0.6))
            .padding(.horizontal, Space.s2).frame(height: MacSize.chip)
            .background(on ? GlassInk.well : .clear, in: coreShape(Radius.control))
            .accessibilityLabel(on ? "\(name) ready" : "\(name) not installed")
    }
}
