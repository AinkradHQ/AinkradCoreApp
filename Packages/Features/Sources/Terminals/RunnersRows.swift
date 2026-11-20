import CoreUI
import SwiftUI

// The Runners tab's parts (mockup 12): summary tiles, one-line runner cards, tool pills and the live motion. E2's Devices & Runners
// app shows `RunnersTab(model:)` as its Runners tab; the rest of this file is private to the tab and the detail page.

/// The colour of a live state, for tiles and the glow behind them.
func liveHue(_ live: RunnerFacts.Live, _ palette: Palette) -> Color {
    switch live {
    case .working: palette.tone(.run).ink
    case .idle: GlassInk.slate
    case .gettingReady: GlassInk.blue
    case .offline: palette.tone(.fail).ink
    }
}

func liveTone(_ live: RunnerFacts.Live) -> Tone {
    switch live {
    case .working: .run
    case .idle: .queue
    case .gettingReady: .done
    case .offline: .fail
    }
}

/// Seven small bars that breathe while the runner works or gets ready. Reduce Motion, idle and offline: still, and low.
struct RunnerActivity: View {
    let live: RunnerFacts.Live
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette
    @State private var low = false
    private static let heights: [CGFloat] = [5, 12, 8, 14, 6, 11, 9]
    private var moving: Bool { !reduce && (live == .working || live == .gettingReady) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Self.heights.indices, id: \.self) { i in
                coreShape(2)
                    .fill(live == .offline ? GlassInk.track : liveHue(live, palette))
                    .frame(width: 3, height: height(i))
                    .animation(
                        moving
                            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(i) * 0.17)
                            : .default, value: low)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .opacity(live == .idle ? 0.5 : 0.85)
        .onAppear { low = moving }
        .onChange(of: moving) { _, now in low = now }
        .accessibilityHidden(true)
    }

    private func height(_ i: Int) -> CGFloat {
        let h = Self.heights[i]
        if live == .offline || live == .idle { return 3 }
        return moving && low ? h * 0.6 : h
    }
}

/// The runner's tile: a glow while it works, a slow turn while it gets ready. Both stand still under Reduce Motion.
struct RunnerTile: View {
    let symbol: String
    let live: RunnerFacts.Live
    var size: CGFloat = Space.s8 + Space.s1
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette
    @State private var on = false

    var body: some View {
        let animate = !reduce
        IconTile(symbol, hue: liveHue(live, palette), size: size)
            .rotationEffect(.degrees(live == .gettingReady && animate && on ? 360 : 0))
            .animation(
                live == .gettingReady && animate ? .linear(duration: 2.4).repeatForever(autoreverses: false) : .default,
                value: on
            )
            .overlay {
                coreShape(size > 40 ? Radius.cardMac : Radius.control).fill(palette.tone(.run).ink)
                    .opacity(live == .working && animate && on ? 0.16 : 0)
                    .animation(
                        live == .working && animate
                            ? .easeInOut(duration: 3).repeatForever(autoreverses: true) : .default,
                        value: on
                    )
                    .allowsHitTesting(false)
            }
            .onAppear { on = true }
    }
}

/// One tool on a card: Ready is plain, missing is quiet, installing is blue with its words and a thin progress line.
struct RunnerToolPill: View {
    enum Kind: Equatable {
        case ready, missing
        case installing(Double)
    }
    let symbol: String
    let name: String
    let kind: Kind
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s1 + 1) {
            Image(systemName: kind.isInstalling ? "arrow.down.circle" : symbol).imageScale(.small)
            Text(kind.isInstalling ? "Installing \(name)" : name).lineLimit(1)
        }
        .coreFont(size: MacTextSize.meta, weight: .medium)
        .foregroundStyle(color)
        .padding(.horizontal, Space.s2).frame(height: 24)
        .background(kind == .missing ? Color.clear : fill, in: coreShape(Radius.chip))
        .overlay(alignment: .bottomLeading) {
            if case .installing(let p) = kind {
                GeometryReader { g in
                    Rectangle().fill(palette.primary.opacity(0.5)).frame(
                        width: g.size.width * min(1, max(0, p)), height: 2)
                }
                .frame(height: 2).clipShape(coreShape(Radius.chip))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            { () -> String in
                switch kind {
                case .ready: "\(name) ready"
                case .missing: "\(name) not installed"
                case .installing: "Installing \(name)"
                }
            }())
    }

    private var fill: Color { kind.isInstalling ? palette.primary.opacity(0.14) : GlassInk.well }
    private var color: Color {
        switch kind {
        case .ready: GlassInk.primary
        case .missing: palette.text2.opacity(0.7)
        case .installing: palette.primary
        }
    }
}

extension RunnerToolPill.Kind {
    var isInstalling: Bool { if case .installing = self { true } else { false } }
}

extension TerminalsModel {
    /// A runner's tools as pills: Terminals, then the four AI tools, each ready, installing (with progress) or missing.
    func toolPills(_ r: RunnerItem) -> [(name: String, symbol: String, kind: RunnerToolPill.Kind)] {
        let facts = RunnerFacts(runner: r)
        var out: [(String, String, RunnerToolPill.Kind)] = [
            ("Terminals", "terminal", facts.terminalsOn ? .ready : .missing)
        ]
        for t in RunnerFacts.aiTools {
            let inst = installs[r.id]?[t.key]
            if let inst, inst.state == .running {
                out.append((t.name, "sparkles", .installing(Double(inst.percent) / 100)))
            } else {
                out.append((t.name, "sparkles", r.tools[t.key] != nil ? .ready : .missing))
            }
        }
        return out
    }

    func isInstalling(_ r: RunnerItem) -> Bool { installs[r.id]?.values.contains { $0.state == .running } == true }

    func live(_ r: RunnerItem) -> RunnerFacts.Live { RunnerFacts(runner: r).live(installing: isInstalling(r)) }
}

/// One runner on one line: tile, name and what it is doing, the tools, a little activity, the state, and a chevron.
struct RunnerRow: View {
    let model: TerminalsModel
    let runner: RunnerItem
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        let facts = RunnerFacts(runner: runner)
        let live = model.live(runner)
        Button {
            model.runnerDetail = runner.id
        } label: {
            HStack(spacing: Space.s3 + 2) {
                RunnerTile(symbol: icon, live: live)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s2) {
                        Text(runner.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                        if runner.builtIn { BuiltInBadge() }
                        if model.host.thisMacRunnerID == runner.id { ThisMacBadge() }
                    }
                    Text(line(live, facts)).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
                }
                .frame(width: Space.s8 * 8 + Space.s2, alignment: .leading)
                HStack(spacing: Space.s1 + 2) {
                    ForEach(model.toolPills(runner), id: \.name) { p in
                        RunnerToolPill(symbol: p.symbol, name: p.name, kind: p.kind)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading).clipped()
                RunnerActivity(live: live)
                StateBadge(live.chip, tone: liveTone(live), symbol: "circle").frame(width: 100, alignment: .trailing)
                Image(systemName: "chevron.right").foregroundStyle(palette.text2).imageScale(.small)
            }
            .padding(.horizontal, Space.s5).padding(.vertical, Space.s4 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(live == .offline ? (hovering ? 0.85 : 0.62) : 1)
            .coreWell(active: hovering)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.coreQuietPress)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .help("Open \(runner.name)")
        .accessibilityLabel("\(runner.name), \(live.chip)")
    }

    private var icon: String {
        let mac = model.host.thisMacRunnerID == runner.id || (runner.os ?? "").lowercased().contains("mac")
        return mac ? "laptopcomputer" : "server.rack"
    }

    /// What it is doing, in one line.
    private func line(_ live: RunnerFacts.Live, _ facts: RunnerFacts) -> String {
        switch live {
        case .working:
            if let w = model.host.runnerHost?.agentWork(on: runner.id).first { return "Working on “\(w.title)”" }
            return "Working"
        case .idle: return "Idle · ready for work"
        case .gettingReady: return "Getting ready · installing tools"
        case .offline:
            return ["Offline", facts.lastSeenWords].compactMap { $0 }.joined(separator: " · ").capitalizedFirst
        }
    }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// The four count tiles above the list; a tap shows only that state, a second tap shows all.
struct RunnerSummary: View {
    @Bindable var model: TerminalsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s3) {
            ForEach(RunnerFacts.Live.allCases) { l in
                let n = model.runners.filter { model.live($0) == l }.count
                Button {
                    model.runnerFilter = model.runnerFilter == l ? nil : l
                } label: {
                    HStack(spacing: Space.s3) {
                        IconTile(symbol(l), hue: liveHue(l, palette), size: Space.s8)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(n)").coreFont(size: MacTextSize.large, weight: .semibold).monospacedDigit()
                                .contentTransition(.numericText())
                            Text(l.rawValue).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3 + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .coreWell(active: model.runnerFilter == l)
                    .contentShape(coreShape(Radius.cardMac))
                }
                .buttonStyle(.coreQuietPress)
                .help(model.runnerFilter == l ? "Show all runners" : "Show runners that are \(l.rawValue.lowercased())")
                .accessibilityLabel("\(n) \(l.rawValue)")
                .accessibilityAddTraits(model.runnerFilter == l ? .isSelected : [])
            }
        }
    }

    private func symbol(_ l: RunnerFacts.Live) -> String {
        switch l {
        case .working: "play"
        case .idle: "pause"
        case .gettingReady: "arrow.triangle.2.circlepath"
        case .offline: "power"
        }
    }
}
