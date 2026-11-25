import CoreUI
import SwiftUI

/// The host's overview: what stops the page (if anything), the health monitor, then the pre-set commands beside the history.
/// The three parts rise in once, one after another; nothing inside them staggers.
struct HostOverview: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState
    @State private var settled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                if let p = state.problem {
                    HostProblemCard(problem: p, model: model, hostID: host.id) {
                        await state.loadCommands()
                        await state.loadHistory()
                    }
                } else if host.light == .off {
                    OfflineCard(model: model, host: host)
                }
                HostHealthSection(model: model, host: host, state: state).coreRise(settled, 0)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.s6) {
                        HostCommandsSection(model: model, host: host, state: state).coreRise(settled, 1)
                            .frame(minWidth: Space.s8 * 16)
                        // Under the Access panel: hidden, so no sliver of it shows beside the panel.
                        HostTimelineSection(state: state).coreRise(settled, 2).frame(width: Space.s8 * 12)
                            .opacity(model.accessOpen ? 0 : 1).accessibilityHidden(model.accessOpen)
                    }
                    VStack(alignment: .leading, spacing: Space.s6) {
                        HostCommandsSection(model: model, host: host, state: state).coreRise(settled, 1)
                        HostTimelineSection(state: state).coreRise(settled, 2)
                    }
                }
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s1).padding(.bottom, Space.s5)
        }
        .scrollIndicators(.automatic)
        .onAppear { settled = true }
        .accessibilityIdentifier("host-overview")
    }
}

/// An offline host: when it last answered, what still works, and Try Now.
private struct OfflineCard: View {
    let model: LeylineModel
    let host: HostItem
    @State private var trying = false
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        LeylineStateCard(
            symbol: "moon.zzz", title: "\(host.name) is not answering",
            text: (host.reach?.seenAt.map { "No answer since \($0.formatted(date: .omitted, time: .shortened)). " }
                ?? "")
                + "Leyline tries again every minute. History and Access still work; the terminal and files wait for it."
        ) {
            AppActionTile(title: "Try Now", symbol: "arrow.clockwise", key: "", hue: GlassInk.accent(paneAccent)) {
                guard !trying else { return }
                trying = true
                Task {
                    await model.tryNow(host)
                    trying = false
                }
            }
            .disabled(trying)
        }
        .accessibilityIdentifier("host-offline")
    }
}

/// A section's title line: the title, a quiet line beside it, and what sits at its right.
struct HostSectionTitle<Accessory: View>: View {
    let title: String
    let line: String?
    @ViewBuilder let accessory: Accessory
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            if let line {
                Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            accessory
        }
    }
}

extension HostSectionTitle where Accessory == EmptyView {
    init(_ title: String, line: String? = nil) { self.init(title: title, line: line) { EmptyView() } }
}

// MARK: health

/// The health monitor: a tile per number with its trend over the last half hour, in blue, amber or red, and the reach chip.
/// What the Core does not report yet shows as a quiet tile, never as a made-up number.
struct HostHealthSection: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState
    @Environment(\.coreAccent) private var paneAccent

    private var health: HostHealth? { state.health.value ?? model.healthByHost[host.id] }
    private var extras: HostExtras { model.extras[host.id] ?? HostExtras() }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HostSectionTitle(title: "Health", line: checked) {
                HStack(spacing: Space.s2) {
                    reachChip
                    if let n = health?.failedUnits, n > 0 {
                        AppStatChip(
                            "exclamationmark.triangle.fill", n == 1 ? "1 service failed" : "\(n) services failed",
                            GlassInk.amber)
                    }
                }
            }
            // Six across when they fit, else three by two: the row always spans the page.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s2) { cells }
                Grid(horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
                    let all = Array(cellList.enumerated())
                    GridRow { ForEach(all.prefix(3), id: \.offset) { $0.element } }
                    GridRow { ForEach(all.dropFirst(3), id: \.offset) { $0.element } }
                }
            }
            .animation(Motion.out(Motion.ui), value: health)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("host-health")
    }

    private let tileHeight = Space.s8 * 4 - Space.s2

    /// The Core has no health for this host (an older Core, or a host it cannot probe): every tile says so.
    private var gone: Bool {
        switch state.health {
        case .missing, .failed: true
        default: false
        }
    }

    private var checked: String? {
        if host.light == .off, health == nil { return "no reading while it is not answering" }
        return health?.checkedAt.map { "checked \(HostWords.ago($0))" }
            ?? (gone ? "not reported by this Core yet" : nil)
    }

    @ViewBuilder private var reachChip: some View {
        if let w = host.latencyWord {
            let hue = host.light == .ok ? GlassInk.green : host.light == .slow ? GlassInk.amber : GlassInk.slate
            AppStatChip("dot.radiowaves.left.and.right", host.light == .off ? "Not answering" : "Reachable · \(w)", hue)
                .help(host.seenLine ?? "The Core checks the host once a minute")
        }
    }

    @ViewBuilder private var cells: some View {
        ForEach(Array(cellList.enumerated()), id: \.offset) { $0.element }
    }

    /// The six tiles, or six quiet placeholders while the first read is on its way.
    private var cellList: [AnyView] {
        if health == nil, state.health.isLoading || state.health.value == nil && !gone {
            return (0..<6).map { _ in
                AnyView(
                    CoreSkeleton(coreShape(Radius.cardMac)).frame(minWidth: Space.s8 * 5, maxWidth: .infinity)
                        .frame(height: tileHeight))
            }
        }
        let h = health
        let os = extras.osName ?? host.os.map { $0 == "darwin" ? "macOS" : $0.capitalized }
        let tiles: [HealthTile] = [
            HealthTile(
                title: "CPU", symbol: "cpu", value: h?.cpuPct.map { "\(Int($0.rounded()))" }, unit: "%",
                sub: h?.cpus.map { "load per core · \($0) cores" }, series: h?.cpuSeries ?? [], ceiling: 100,
                tone: HealthTone.percent(h?.cpuPct)),
            HealthTile(
                title: "Memory", symbol: "memorychip", value: h?.memPct.map { "\(Int($0.rounded()))" }, unit: "%",
                sub: extras.memoryTotal.map { "of \($0)" } ?? "in use", series: h?.memSeries ?? [], ceiling: 100,
                tone: HealthTone.percent(h?.memPct)),
            HealthTile(
                title: "Disk", symbol: "internaldrive", value: h?.diskPct.map { "\(Int($0.rounded()))" }, unit: "%",
                sub: extras.diskFree ?? "of the root disk", series: h?.diskSeries ?? [], ceiling: 100,
                tone: HealthTone.percent(h?.diskPct)),
            HealthTile(
                title: "Load", symbol: "gauge.with.dots.needle.50percent", value: h?.load1.map { coreDecimal($0, 2) },
                unit: "", sub: "1-minute average" + (h?.cpus.map { " · \($0) cores" } ?? ""),
                series: (h?.cpuSeries ?? []).map { $0 * Double(h?.cpus ?? 1) / 100 }, ceiling: nil,
                tone: HealthTone.load(h?.load1, cpus: h?.cpus)),
            HealthTile(
                title: "Network", symbol: "arrow.up.arrow.down", value: extras.network, unit: "",
                sub: extras.network == nil ? nil : "in · out", series: extras.networkSeries, ceiling: nil, tone: .run,
                compact: true),
            HealthTile(
                title: "Uptime", symbol: "clock.arrow.circlepath", value: extras.uptime, unit: "", sub: os,
                series: [], ceiling: nil, tone: .run),
        ]
        return tiles.map { AnyView($0) }
    }
}

/// One number of the monitor: its name, the value, a line under it and its trend. With no value it says "Not reported yet"
/// and keeps the same shape, so the grid never jumps when a number arrives.
struct HealthTile: View {
    let title: String
    let symbol: String
    let value: String?
    let unit: String
    let sub: String?
    let series: [Double]
    let ceiling: Double?
    let tone: Tone
    /// A long value (the network's two rates) at body size.
    var compact = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s1 + 2) {
                Image(systemName: symbol).coreFont(size: MacTextSize.meta, weight: .semibold).accessibilityHidden(true)
                Text(title).coreFont(size: MacTextSize.meta, weight: .medium)
                Spacer(minLength: Space.s1)
                if value != nil, let w = HealthTone.word(tone) { StateBadge(w, tone: tone, symbol: "exclamationmark") }
            }
            .frame(height: MacSize.chip)
            .foregroundStyle(GlassInk.secondary)
            Group {
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value).coreFont(size: compact ? MacTextSize.title : MacTextSize.large, weight: .semibold)
                            .monospacedDigit().contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.8)
                        if !unit.isEmpty {
                            Text(unit).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                        }
                    }
                } else {
                    Text("Not reported yet").coreFont(size: MacTextSize.body, weight: .medium)
                        .foregroundStyle(GlassInk.secondary)
                }
            }
            .frame(height: Space.s6, alignment: .leading)
            Text(value == nil && sub == nil ? "The Core does not send it yet" : sub ?? " ")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            if value != nil, series.count >= 2 {
                CoreSpark(series, tone: tone, ceiling: ceiling)
            } else {
                // No line the data does not support: a flat track where the trend will be.
                coreShape(1).fill(palette.track).frame(height: 2)
                    .frame(height: Space.s6 + Space.s2, alignment: .bottom)
            }
        }
        .padding(Space.s3)
        .frame(minWidth: Space.s8 * 5, maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\($0)\(unit)" + (sub.map { ", \($0)" } ?? "") } ?? "Not reported yet")
    }
}
