import CoreUI
import SwiftUI

/// The Runners pane: one tile per machine, or one machine's page. Only what runners report: work slots, load per core, drivers.
struct RunnersView: View {
    let model: TerminalsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let id = model.runnerDetail, let r = model.runner(id) {
                    RunnerDetail(model: model, runner: r)
                } else {
                    fleet
                }
            }
            .padding(Space.s3)
        }
        .task {
            // Load and heartbeat move without events: look again while this pane is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await model.reload()
            }
        }
        .onChange(of: model.runners) { _, now in
            if let id = model.runnerDetail, !now.contains(where: { $0.id == id }) { model.runnerDetail = nil }
        }
    }

    @ViewBuilder private var fleet: some View {
        switch model.load {
        case .failed(let m):
            ConnectionBanner(
                .error("Check that your Core is reachable, then try again."), retry: { Task { await model.reload() } }
            )
            .help(m)
        default:
            if model.runners.isEmpty {
                if model.load == .ready {
                    VStack(spacing: Space.s2) {
                        Text("No runners").font(.system(size: MacTextSize.title, weight: .semibold))
                        Text("Pair a runner to open terminals.").foregroundStyle(palette.text2)
                    }
                    .frame(maxWidth: .infinity).padding(.top, Space.s8)
                } else {
                    BusyBar()
                }
            }
            ForEach(model.runners) { r in RunnerTile(model: model, runner: r) }
            Text("Runners report work slots and load per core.")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .help("Memory and disk are not reported.")
        }
    }
}

private struct RunnerTile: View {
    let model: TerminalsModel
    let runner: RunnerItem
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        let st = RunnerStatus(runner)
        Button {
            model.runnerDetail = runner.id
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Text(runner.name).font(.system(size: MacTextSize.headline, weight: .semibold, design: .monospaced))
                    Spacer(minLength: Space.s2)
                    if let v = runner.version {
                        Text("v\(v)").font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(
                            palette.text2)
                    }
                    StateBadge(st.label, tone: st.tone, symbol: st.symbol)
                }
                if let a = runner.arch {
                    Text(RunnerWords.arch(a)).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                        .help(a)
                }
                labelled(
                    "Work running\(st == .off ? " · last known" : "")", "\(runner.load) of \(runner.capacity) slots"
                ) {
                    CoreSlots(used: runner.load, capacity: runner.capacity)
                }
                if let p = runner.perCore {
                    labelled("Host load per core", String(format: "%.2f", p)) {
                        CoreMeter(p / 6, low: p > RunnerStatus.busyPerCore, label: "Host load per core")
                    }
                    if let s = model.loadSamples[runner.id], s.count >= 2 {
                        CoreSpark(s, tone: st == .busy ? .warn : .run, ceiling: max(0.5, s.max() ?? 0.5))
                        Text("Load seen on this Mac").font(.system(size: MacTextSize.meta))
                            .foregroundStyle(palette.text2).help("Sampled on this Mac while it watched.")
                    }
                }
                HStack(spacing: Space.s2) {
                    ForEach(runner.drivers, id: \.name) { d in
                        Text(RunnerWords.driver(d.name)).font(.system(size: MacTextSize.meta, weight: .medium))
                            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                            .background(palette.uDim, in: coreShape(Radius.chip)).help(d.name)
                    }
                    if runner.drivers.isEmpty {
                        Text("No drivers reported yet").font(.system(size: MacTextSize.meta)).foregroundStyle(
                            palette.text2)
                    }
                    Spacer(minLength: 0)
                    Text(model.onRunner(runner.id) == 1 ? "1 terminal" : "\(model.onRunner(runner.id)) terminals")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? palette.rowHover : palette.glassCard, in: coreShape(Radius.row))
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel("\(runner.name), \(st.label), \(runner.load) of \(runner.capacity) slots in use")
    }

    private func labelled<V: View>(_ title: String, _ value: String, @ViewBuilder bar: () -> V) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Text(title).foregroundStyle(palette.text2)
                Spacer(minLength: Space.s2)
                Text(value).font(.system(size: MacTextSize.body, weight: .semibold)).monospacedDigit()
            }
            .font(.system(size: MacTextSize.meta))
            bar()
        }
    }
}

/// One runner: load, drivers, isolation, what runs here, and the no-op test.
private struct RunnerDetail: View {
    let model: TerminalsModel
    let runner: RunnerItem
    @Environment(\.corePalette) private var palette

    var body: some View {
        let st = RunnerStatus(runner)
        let off = st == .off
        Button {
            model.runnerDetail = nil
        } label: {
            Label("All runners", systemImage: "chevron.left")
        }
        .buttonStyle(CoreButtonStyle(.plain, size: .small))
        .keyboardShortcut(.escape, modifiers: [])
        HStack(spacing: Space.s2) {
            Text(runner.name).font(.system(size: MacTextSize.large, weight: .semibold, design: .monospaced))
            StateBadge(st.label, tone: st.tone, symbol: st.symbol)
        }
        Text(
            [runner.arch.map(RunnerWords.arch), runner.version.map { "runner v\($0)" }].compactMap { $0 }.joined(
                separator: " · ")
        )
        .foregroundStyle(palette.text2).help(runner.arch ?? "")
        switch st {
        case .degraded:
            TermBanner(
                tone: .warn, title: "Not answering heartbeats",
                detail: "It is still listed as connected, but its figures may be stale.",
                help: "The Core has not heard from \(runner.name) for two heartbeats (runner.degraded)."
            )
        case .off:
            TermBanner(
                tone: .fail, title: "Disconnected",
                detail: "Nothing can start there until it is back. Figures are the last the Core saw.",
                help: "runner_offline: its terminals answer that until the runner reconnects."
            )
        case .busy:
            TermBanner(
                tone: .warn, title: "Too busy for new work",
                detail: "New terminals and sessions are refused until the load drops.",
                help:
                    "runner_busy (503): host load is \(String(format: "%.1f", runner.perCore ?? 0)) per core, over the limit of \(Int(RunnerStatus.busyPerCore)). Work already running is not touched."
            )
        case .ok: EmptyView()
        }
        card("Load\(off ? " · last known" : "")") {
            fact("Work running", "\(runner.load) of \(runner.capacity)")
            CoreSlots(used: runner.load, capacity: runner.capacity)
            if let a = runner.avg1, let c = runner.cores {
                fact("Host load, 1 min average", "\(String(format: "%.1f", a)) on \(c) cores")
                fact("Per core", String(format: "%.2f", runner.perCore ?? 0))
                CoreMeter((runner.perCore ?? 0) / 6, low: st == .busy, label: "Host load per core")
                Text("Above \(Int(RunnerStatus.busyPerCore)) per core the runner refuses new work.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            } else {
                Text("This runner has not reported host load.").foregroundStyle(palette.text2)
            }
        }
        card("Drivers") {
            if runner.drivers.isEmpty { Text("None reported yet.").foregroundStyle(palette.text2) }
            ForEach(runner.drivers, id: \.name) { d in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(RunnerWords.driver(d.name)).font(.system(size: MacTextSize.body, weight: .semibold))
                            .help(d.name)
                        Spacer()
                        if let c = d.capacity { Text("\(c) at once").foregroundStyle(palette.text2) }
                    }
                    if !d.commands.isEmpty {
                        Text(RunnerWords.commands(d.commands)).font(.system(size: MacTextSize.meta))
                            .foregroundStyle(palette.text2).help(d.commands.joined(separator: ", "))
                    }
                }
            }
            if !runner.hasPty && !runner.drivers.isEmpty {
                Text("Terminals are off on this runner.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    .help("Start the runner with --enable-pty to use them.")
            }
        }
        card("Isolation") {
            if let tiers = runner.isolationTiers, !tiers.isEmpty {
                fact("Isolation tiers", tiers.joined(separator: ", "))
            } else {
                note("Isolation tier: not reported", "This Core does not report it yet.")
            }
            note(
                "Shells and the runner share one user", "Don’t read “sandboxed” as “isolated”.")
        }
        let here = model.items.filter { $0.runner == runner.id && !$0.isEnded }
        card("\(off ? "Was running" : "Running here") · \(here.count) \(here.count == 1 ? "item" : "items")") {
            if here.isEmpty { Text("Nothing running.").foregroundStyle(palette.text2) }
            ForEach(here) { t in
                Button {
                    model.openTerminal(t.id, attach: false)
                } label: {
                    HStack {
                        Text(model.shell.tabNames["terminal-\(t.id)"] ?? "Terminal opened \(ago(t.createdAt))")
                            .font(.system(size: MacTextSize.body)).lineLimit(1)
                        Spacer()
                        Text(t.attached == 0 ? "not attached" : "\(t.attached) attached").foregroundStyle(palette.text2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Terminal \(t.id)")
            }
        }
        card("Check it") {
            let n = model.noop[runner.id]
            HStack(spacing: Space.s3) {
                Button("Test the runner") { Task { await model.runNoop(runner.id) } }
                    .buttonStyle(CoreButtonStyle(.secondary)).disabled(off || n == .running)
                    .help("Needs the read and agent scopes")
                Group {
                    switch n {
                    case .running: Text("Waiting for the runner…")
                    case .answered(let ms)?: Text("The runner answered in \(ms) ms. No work was started.")
                    case .failed(let m)?: Text("The runner did not answer").help(m)
                    case nil:
                        Text(
                            off
                                ? "Disconnected, so the test would fail."
                                : "Sends an empty round trip to the runner. No work is started.")
                    }
                }
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
            if n == .running { BusyBar() }
            HStack(spacing: Space.s3) {
                Button("Open a terminal here") { model.openNew(runner: runner.id) }
                    .buttonStyle(CoreButtonStyle(.secondary)).disabled(off || st == .busy || !runner.hasPty)
                Text(
                    off
                        ? "Not available while disconnected."
                        : st == .busy
                            ? "Refused while the host is over its load limit."
                            : !runner.hasPty ? "Terminals are off on this runner." : ""
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(.system(size: MacTextSize.headline, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content()
        }
        .font(.system(size: MacTextSize.body))
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .accessibilityElement(children: .contain)
    }

    private func fact(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(palette.text2)
            Spacer(minLength: Space.s3)
            Text(v).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: MacTextSize.body, weight: .semibold))
            Text(text).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
