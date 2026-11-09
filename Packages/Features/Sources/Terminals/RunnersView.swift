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
        case .failed(let m): ConnectionBanner(.error(m), retry: { Task { await model.reload() } })
        default:
            if model.runners.isEmpty {
                if model.load == .ready {
                    VStack(spacing: Space.s2) {
                        Text("No runners").font(.system(size: MacTextSize.title, weight: .semibold))
                        Text("Pair a runner to open terminals.").foregroundStyle(palette.text2)
                    }
                    .frame(maxWidth: .infinity).padding(.top, Space.s8)
                } else {
                    CoreBusyBar()
                }
            }
            ForEach(model.runners) { r in RunnerTile(model: model, runner: r) }
            Text("Runners report work slots and load per core; memory and disk are not reported.")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
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
                if let a = runner.arch { Text(a).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2) }
                labelled(
                    "Work running\(st == .off ? " · last known" : "")", "\(runner.load) of \(runner.capacity) slots"
                ) {
                    CoreSlots(used: runner.load, capacity: runner.capacity)
                }
                if let p = runner.perCore {
                    labelled("Host load per core", coreDecimal(p, 2)) {
                        Meter(value: p, max: 6, limit: RunnerStatus.busyPerCore, warn: p > RunnerStatus.busyPerCore)
                    }
                    if let s = model.loadSamples[runner.id], s.count >= 2 {
                        CoreSpark(s, tone: st == .busy ? .warn : .run, ceiling: max(0.5, s.max() ?? 0.5))
                        Text("Load sampled on this Mac while it watched.").font(.system(size: MacTextSize.meta))
                            .foregroundStyle(palette.text2)
                    }
                }
                HStack(spacing: Space.s2) {
                    ForEach(runner.drivers, id: \.name) { d in
                        Text(d.name).font(.system(size: MacTextSize.meta, weight: .medium, design: .monospaced))
                            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                            .background(palette.uDim, in: coreShape(Radius.chip))
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
            Label("All runners", systemImage: "chevron.backward")
        }
        .buttonStyle(CoreButtonStyle(.plain, size: .small))
        .keyboardShortcut(.escape, modifiers: [])
        HStack(spacing: Space.s2) {
            Text(runner.name).font(.system(size: MacTextSize.large, weight: .semibold, design: .monospaced))
            StateBadge(st.label, tone: st.tone, symbol: st.symbol)
        }
        Text([runner.arch, runner.version.map { "runner v\($0)" }].compactMap { $0 }.joined(separator: " · "))
            .foregroundStyle(palette.text2)
        switch st {
        case .degraded:
            TermBanner(
                tone: .warn, title: "Not answering heartbeats",
                detail:
                    "The Core has not heard from \(runner.name) for two heartbeats (runner.degraded). It is still listed as connected, but treat the figures below as possibly stale. If it stays silent it shows as disconnected."
            )
        case .off:
            TermBanner(
                tone: .fail, title: "Disconnected",
                detail:
                    "The Core can’t reach \(runner.name), so nothing can start there and its terminals answer runner_offline. Figures below are the last the Core saw. Everything resumes when the runner reconnects."
            )
        case .busy:
            TermBanner(
                tone: .warn, title: "Too busy for new work",
                detail:
                    "Host load is \(coreDecimal(runner.perCore ?? 0, 1)) per core and the default limit is \(Int(RunnerStatus.busyPerCore)), so new terminals and sessions are refused with runner_busy (503). Work already running is not touched. It clears by itself when the load drops."
            )
        case .ok: EmptyView()
        }
        card("Load\(off ? " · last known" : "")") {
            fact("Work running", "\(runner.load) of \(runner.capacity)")
            CoreSlots(used: runner.load, capacity: runner.capacity)
            if let a = runner.avg1, let c = runner.cores {
                fact("Host load, 1 min average", "\(coreDecimal(a, 1)) on \(c) cores")
                fact("Per core", coreDecimal(runner.perCore ?? 0, 2))
                Meter(value: runner.perCore ?? 0, max: 6, limit: RunnerStatus.busyPerCore, warn: st == .busy)
                Text(
                    "The marker is the limit: above \(Int(RunnerStatus.busyPerCore)) per core the runner refuses new work (default)."
                )
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
                        Text(d.name).font(.system(size: MacTextSize.body, weight: .semibold, design: .monospaced))
                        Spacer()
                        if let c = d.capacity { Text("\(c) at once").foregroundStyle(palette.text2) }
                    }
                    if !d.commands.isEmpty {
                        Text(d.commands.joined(separator: ", ")).font(.system(size: MacTextSize.meta)).foregroundStyle(
                            palette.text2)
                    }
                }
            }
            if !runner.hasPty && !runner.drivers.isEmpty {
                Text("Terminals are off here. Start the runner with --enable-pty to use them.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
        }
        card("Isolation") {
            if let tiers = runner.isolationTiers, !tiers.isEmpty {
                fact("Isolation tiers", tiers.joined(separator: ", "))
            } else {
                note(
                    "Isolation tier: not reported",
                    "This Core does not tell clients this runner’s isolation tier yet, so this app can’t say what \(runner.name) can or can’t meet."
                )
            }
            note(
                "Shells and the runner share one user",
                "That is why the terminal scope counts as admin-level today. Don’t read “sandboxed” as “isolated”.")
        }
        let here = model.items.filter { $0.runner == runner.id && !$0.isEnded }
        card("\(off ? "Was running" : "Running here") · \(here.count) \(here.count == 1 ? "item" : "items")") {
            if here.isEmpty { Text("Nothing running.").foregroundStyle(palette.text2) }
            ForEach(here) { t in
                Button {
                    model.openTerminal(t.id, attach: false)
                } label: {
                    HStack {
                        Text("Terminal").font(.system(size: MacTextSize.meta, weight: .medium))
                            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                            .background(palette.uDim, in: coreShape(Radius.chip))
                        Text(t.id).font(.system(size: MacTextSize.body, design: .monospaced)).lineLimit(1)
                        Spacer()
                        Text(t.attached == 0 ? "not attached" : "\(t.attached) attached").foregroundStyle(palette.text2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        card("Check it") {
            let n = model.noop[runner.id]
            HStack(spacing: Space.s3) {
                Button("Run no-op test") { Task { await model.runNoop(runner.id) } }
                    .buttonStyle(CoreButtonStyle(.secondary)).disabled(off || n == .running)
                Group {
                    switch n {
                    case .running: Text("Waiting for the runner…")
                    case .answered(let ms)?: Text("The runner answered in \(ms) ms. No work was started.")
                    case .failed(let m)?: Text(m)
                    case nil:
                        Text(
                            off
                                ? "Disconnected, so the test would fail with runner_offline."
                                : "Sends an empty round trip to the runner. No work is started.")
                    }
                }
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
            if n == .running { CoreBusyBar() }
            Text("Needs the read and agent scopes.").font(.system(size: MacTextSize.meta)).foregroundStyle(
                palette.text2)
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
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
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
