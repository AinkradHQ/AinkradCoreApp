import AppKit
import CoreUI
import SwiftUI

/// Checks: the safety checks the Brain runs itself, their last result and trend, Run now, and the pilot targets. This page
/// only shows what the service returns; it never computes health. Paused names its rooms and clears only with Touch ID.
struct ChecksTab: View {
    let model: BrainModel

    var body: some View {
        let c = model.checks!
        VStack(alignment: .leading, spacing: Space.s4) {
            header(c)
            PausedBanner(model: model, full: true)
            switch c.phase {
            case .loading:
                BrainSkeleton(shape: .list)
            case .failed(let why):
                BrainStateCard(
                    symbol: "exclamationmark.triangle", title: "Checks could not load", text: why,
                    primary: CoreAction("Try again") { c.retry() })
            case .ready:
                HStack(alignment: .top, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        VStack(spacing: Space.s2) { ForEach(c.items) { CheckRow(model: model, item: $0) } }
                        if !c.housekeeping.isEmpty {
                            Text("Housekeeping").coreFont(size: MacTextSize.meta, weight: .medium)
                                .foregroundStyle(GlassInk.secondary).padding(.top, Space.s1)
                            VStack(spacing: Space.s2) { ForEach(c.housekeeping) { CheckRow(model: model, item: $0) } }
                        }
                        PilotTargets(targets: c.report.pilot)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    if let sel = c.selected { CheckDetail(model: model, item: sel).frame(width: Space.s8 * 9.5) }
                }
            }
        }
        .task { c.enter() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-checks")
    }

    private func header(_ c: ChecksModel) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                BrainTitle("Checks")
                Text(
                    (c.phase == .ready ? c.summary + " " : "")
                        + "The Brain runs these itself; this page only shows the results."
                )
                .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            if let q = model.overview?.flags.offlineQueued {
                BrainChip(
                    "Offline, \(q) queued", GlassInk.slate,
                    help: "The local Core answers; the remote server is unreachable.")
            }
            if c.phase == .ready {
                Button("Run all with options…") { ChecksSheets.open(model, only: nil) }
                    .buttonStyle(CoreButtonStyle(.secondary))
                Button {
                    Task { await c.runAll() }
                } label: {
                    Label("Run all", systemImage: "play")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).disabled(c.anyRunning)
            }
        }
    }
}

private func hue(_ s: CheckState) -> Color {
    switch s {
    case .pass: GlassInk.green
    case .fail: GlassInk.red
    case .due, .running: GlassInk.blue
    case .never, .skipped: GlassInk.slate
    }
}

/// The last results as bars, oldest first: green passed, red failed. Bars, not rings.
struct TrendBars: View {
    let history: [Bool]
    var height: CGFloat = 22
    var body: some View {
        if history.isEmpty {
            Text("No runs yet").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        } else {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(history.enumerated()), id: \.offset) { _, ok in
                    coreShape(2).fill(ok ? GlassInk.green.opacity(0.85) : GlassInk.red)
                        .frame(width: height > 30 ? 14 : 8, height: ok ? height : height * 0.55)
                }
            }
            .frame(height: height, alignment: .bottom)
            .accessibilityElement()
            .accessibilityLabel(
                "Last \(history.count) runs: \(history.filter { $0 }.count) passed, \(history.filter { !$0 }.count) failed"
            )
        }
    }
}

private struct CheckRow: View {
    let model: BrainModel
    let item: CheckItem
    @State private var hovering = false

    var body: some View {
        let c = model.checks!
        let st = c.state(item)
        let on = c.selectedID == item.id
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).fontWeight(.semibold)
                Text(c.sentence(item)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("Last run").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Text(item.last).coreFont(size: MacTextSize.body, weight: .medium)
            }
            .frame(width: Space.s8 * 2.5, alignment: .leading)
            if let p = c.running[item.id] {
                VStack(alignment: .leading, spacing: 3) {
                    CoreMeter(p, label: "\(item.name) progress")
                    Text("Running, \(Int(p * 100))%").coreFont(size: MacTextSize.meta).foregroundStyle(
                        GlassInk.secondary
                    )
                    .monospacedDigit()
                }
                .frame(width: Space.s8 * 6)
            } else {
                TrendBars(history: item.history).frame(width: Space.s8 * 3, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    BrainChip(st.label, hue(st))
                    if st == .pass, item.due != "now" {
                        Text("Due \(item.due)").coreFont(size: MacTextSize.meta).foregroundStyle(
                            GlassInk.secondary)
                    }
                }
                .frame(width: Space.s8 * 3.5, alignment: .leading)
            }
            Button {
                run(advanced: NSEvent.modifierFlags.contains(.option))
            } label: {
                Label("Run now", systemImage: "play")
            }
            .buttonStyle(CoreButtonStyle(st == .pass ? .secondary : .prominent, size: .small))
            .disabled(c.running[item.id] != nil)
            .help("Run now. Option-click for more choices.")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .coreWell(active: on || hovering)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture { c.selectedID = item.id }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.hover), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(st.label)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .coreActivates { c.selectedID = item.id }
    }

    private func run(advanced: Bool) {
        if advanced { ChecksSheets.open(model, only: item.id) } else { Task { await model.checks.run(item.id) } }
    }
}

private struct CheckDetail: View {
    let model: BrainModel
    let item: CheckItem

    var body: some View {
        let c = model.checks!
        let st = c.state(item)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(item.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s2)
                BrainChip(st.label, hue(st))
            }
            Text(item.about).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .topLeading, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
                row("Last run", item.last)
                row("Next due", item.due)
                row("Measured", item.value, bad: st == .fail)
                row("Target", item.target)
            }
            .coreFont(size: MacTextSize.body).padding(.top, Space.s1)
            if item.trend.isEmpty {
                small("History, oldest to newest")
                TrendBars(history: item.history, height: 56)
                small(item.history.isEmpty ? "This check has no history yet." : "Green passed, red failed.")
            } else {
                small("Local search, last \(item.trend.count) runs")
                SpeedBars(values: item.trend, limit: item.trendLimit ?? 0)
                small("Target is under \(Int(item.trendLimit ?? 0)) ms.")
            }
            if item.skippedOffline {
                CoreNotice(
                    symbol: "wifi.slash", title: "Skipped because this Mac is offline", text: "Nothing was measured.")
            }
            if item.clearedAfter {
                CoreNotice(
                    symbol: "info.circle", title: "You cleared Paused after this result",
                    text: "Run the check again to confirm.")
            }
            Label("This page keeps results only, never memory text. Hover for the codes.", systemImage: "info.circle")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .help("chk.\(item.id), run-\(item.id)-\(item.history.count)")
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Run with options…") { ChecksSheets.open(model, only: item.id) }
                    .buttonStyle(CoreButtonStyle(.secondary))
                Button {
                    Task { await c.run(item.id) }
                } label: {
                    Label("Run now", systemImage: "play")
                }
                .buttonStyle(CoreButtonStyle(st == .pass ? .secondary : .prominent)).disabled(c.running[item.id] != nil)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-check-detail")
    }

    private func row(_ k: String, _ v: String, bad: Bool = false) -> some View {
        GridRow {
            Text(k).foregroundStyle(GlassInk.secondary)
            Text(v).foregroundStyle(bad ? GlassInk.redInk : GlassInk.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func small(_ t: String) -> some View {
        Text(t).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).padding(.top, Space.s1)
    }
}

/// Speed's last runs as bars, tall for slow. Red above the limit, green under. Hover for the number.
private struct SpeedBars: View {
    let values: [Double]
    let limit: Double
    var body: some View {
        let top = max(values.max() ?? 1, limit, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                coreShape(2).fill(v > limit ? GlassInk.red : GlassInk.green.opacity(0.85))
                    .frame(maxWidth: 14, minHeight: 2).frame(height: 56 * v / top).help("\(Int(v)) ms")
            }
        }
        .frame(height: 56, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Last \(values.count) runs, \(values.filter { $0 > limit }.count) over the target")
    }
}

private struct PilotTargets: View {
    let targets: [PilotTarget]
    var body: some View {
        BrainCard(
            "Pilot targets", sub: "The numbers the pilot must meet. They come from the checks above."
        ) {
            VStack(spacing: 0) {
                ForEach(targets) { t in
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title)
                            Text("Target: \(t.target)").coreFont(size: MacTextSize.meta)
                                .foregroundStyle(GlassInk.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(t.value).monospacedDigit().frame(width: Space.s8 * 3, alignment: .trailing)
                        BrainChip(
                            t.result.label,
                            t.result == .pass ? GlassInk.green : t.result == .fail ? GlassInk.red : GlassInk.slate
                        )
                        .frame(width: Space.s8 * 3, alignment: .leading)
                    }
                    .padding(.vertical, Space.s2)
                    .help("Pilot target \(t.code)")
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("brain-pilot")
    }
}
