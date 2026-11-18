import CoreUI
import Projects
import SwiftUI

/// Small words shared by the host pages.
enum HostWords {
    static func ago(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
    static func percent(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "–" }
    static func size(_ n: Int64?) -> String { n.map { $0.formatted(.byteCount(style: .file)) } ?? "–" }

    /// How a command's run on this host stands, in a line.
    static func run(_ r: CommandRun) -> String {
        switch r.state {
        case .queued, .running: "Running…"
        case .needsApproval: "Waiting for approval"
        case .ok:
            "ok"
                + (r.durationMS.map { " · \((Double($0) / 1000).formatted(.number.precision(.fractionLength(1)))) s" }
                    ?? "")
        case .failed: "failed" + (r.exitCode.map { " · exit \($0)" } ?? "") + (r.step.map { " · step \($0)" } ?? "")
        case .refused: "Refused by the gate"
        case .skipped: "Skipped"
        }
    }
    static func symbol(_ w: HostEvent.Who) -> String {
        switch w {
        case .you: "person"
        case .ai: "sparkles"
        case .fleet: "square.stack.3d.up"
        case .system: "bell"
        }
    }
    static func who(_ w: HostEvent.Who) -> String {
        switch w {
        case .you: "You"
        case .ai: "AI"
        case .fleet: "Fleet"
        case .system: "Alert"
        }
    }
    /// What a read that has no data says, in place of the data.
    static func gone(_ missing: String) -> String { "\(missing) arrives with the next Core update." }
}

/// Overview: health, the one-click commands and what happened lately. (Live tunnels join it when tunnels do.)
struct HostOverviewPage: View {
    let state: HostPageState
    @State private var settled = false

    var body: some View {
        VStack(spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                HealthIsland(state: state).coreRise(settled, 0)
                CommandsIsland(state: state).coreRise(settled, 1)
            }
            .frame(height: Space.s8 * 11)
            RecentIsland(state: state).coreRise(settled, 2).frame(maxHeight: .infinity)
        }
        .onAppear { settled = true }
        // Once a minute, as the Core's prober does.
        .task {
            while !Task.isCancelled {
                await state.loadHealth()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .accessibilityIdentifier("host-page-Overview")
    }
}

// MARK: Health

private struct HealthIsland: View {
    let state: HostPageState

    var body: some View {
        Island(
            title: "Health", sub: sub,
            accessory: {
                Button("Check now") { Task { await state.loadHealth() } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(state.health.isLoading)
                    .help("Ask the Core to look at the host again")
            }
        ) {
            switch state.health {
            case .idle, .loading:
                HStack(spacing: Space.s4) {
                    ForEach(0..<3, id: \.self) { _ in CoreSkeleton().frame(height: Space.s8 * 2) }
                }
            case .missing:
                Text(HostWords.gone("Health")).foregroundStyle(GlassInk.secondary)
            case .failed(let why):
                CoreNotice(symbol: "exclamationmark.triangle", title: "Health did not load", text: why, tone: .warn)
            case .ready(let h):
                ready(h)
            }
        }
        .accessibilityIdentifier("overview-health")
    }

    private var sub: String {
        guard let h = state.health.value, let at = h.checkedAt else {
            return "agentless, nothing installed on the host"
        }
        return "checked \(HostWords.ago(at))"
    }

    @ViewBuilder private func ready(_ h: HostHealth) -> some View {
        switch h.state {
        case .down:
            CoreNotice(
                symbol: "xmark.octagon", title: "Not answering", text: "The last check could not connect to the host.",
                tone: .fail)
        case .unknown:
            CoreNotice(
                symbol: "questionmark.circle", title: "Not checked",
                text: "Leyline checks a host once its key is trusted. Open Access to compare it.", tone: .queue)
        case .up:
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s4) {
                    gauge("CPU", h.cpuPct, h.cpus.map { "\($0) cores" } ?? "", h.cpuSeries)
                    gauge("Memory", h.memPct, "in use", h.memSeries)
                    gauge("Disk", h.diskPct, "used", h.diskSeries)
                }
                HStack(spacing: Space.s2) {
                    let failed = h.failedUnits ?? 0
                    Image(systemName: failed == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(
                        [
                            h.failedUnits.map { Words.count($0, "failed service") },
                            h.load1.map { "load \($0.formatted(.number.precision(.fractionLength(2))))" },
                        ].compactMap { $0 }.joined(separator: " · ")
                    )
                }
            }
        }
    }

    private func gauge(_ name: String, _ v: Double?, _ note: String, _ series: [Double]) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(name).foregroundStyle(GlassInk.secondary)
            Text(HostWords.percent(v)).coreFont(size: MacTextSize.large, weight: .semibold).monospacedDigit()
            Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            if series.count > 1 {
                CoreSpark(series, tone: (v ?? 0) > 85 ? .warn : .run, ceiling: 100).frame(height: Space.s6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Commands

private struct CommandsIsland: View {
    let state: HostPageState
    private let columns = [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible(), spacing: Space.s2)]

    var body: some View {
        Island(
            title: "Commands", sub: "one click, the same rules as AI",
            accessory: {
                Button("All…") { state.model.section = .commands }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Open the pre-set commands and runbooks")
            }
        ) {
            switch state.commands {
            case .idle, .loading: CoreSkeleton().frame(height: Space.s8 * 2)
            case .missing: Text(HostWords.gone("Commands")).foregroundStyle(GlassInk.secondary)
            case .failed(let why): Text(why).foregroundStyle(GlassInk.secondary)
            case .ready:
                if state.presets.isEmpty {
                    Text(HostSection.commands.empty.line).foregroundStyle(GlassInk.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: Space.s2) {
                        ForEach(state.presets.prefix(4)) { PresetCard(state: state, command: $0) }
                    }
                }
            }
        }
        .accessibilityIdentifier("overview-commands")
    }
}

/// One command as a card: a click runs it (after the confirm card when the command asks for one).
struct PresetCard: View {
    let state: HostPageState
    let command: PresetCommand

    var body: some View {
        let run = state.runs[command.id]
        Button {
            state.tap(command)
        } label: {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(command.name).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                Text(command.line).coreFont(size: MacTextSize.meta, design: .monospaced)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
                Text(run.map(HostWords.run) ?? (command.confirm ? "confirms first" : "runs at once"))
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s3)
            .coreWell()
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac, hoverFill: true))
        .disabled(run?.finished == false)
        .help(command.description.isEmpty ? "Run \(command.name) on this host" : command.description)
        .accessibilityLabel("Run \(command.name)")
        .accessibilityIdentifier("preset-\(command.name)")
    }
}

// MARK: Recent

private struct RecentIsland: View {
    let state: HostPageState

    var body: some View {
        Island(
            title: "Recent", sub: "what you and AI did here",
            accessory: {
                Button("History") { state.model.section = .history }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        ) {
            switch state.history {
            case .idle, .loading: CoreSkeleton().frame(height: Space.s8 * 2)
            case .missing: Text(HostWords.gone("History")).foregroundStyle(GlassInk.secondary)
            case .failed(let why): Text(why).foregroundStyle(GlassInk.secondary)
            case .ready(let all):
                if all.isEmpty {
                    Text(HostSection.history.empty.line).foregroundStyle(GlassInk.secondary)
                } else {
                    VStack(spacing: Space.s1) {
                        ForEach(all.prefix(5)) { e in
                            CoreRow(
                                "\(HostWords.who(e.who)) · \(e.what)", subtitle: "\(HostWords.ago(e.at)) · \(e.detail)",
                                symbol: HostWords.symbol(e.who))
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("overview-recent")
    }
}
