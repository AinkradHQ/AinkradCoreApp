import CoreUI
import SwiftUI

/// What a machine's row says beside its tools: whether it takes work, and its cores, CPU and memory in one quiet line.
struct HardwareGlance: View {
    let facts: HardwareFacts
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Label(facts.gateWords, systemImage: facts.gateSymbol)
                .foregroundStyle(facts.gateOpen ? palette.text : palette.text2).lineLimit(1)
            Text("\(facts.hw.cores) cores · CPU \(facts.hw.cpuPct)% · RAM \(Int((facts.memUsed * 100).rounded()))%")
                .foregroundStyle(palette.text2).lineLimit(1).monospacedDigit().contentTransition(.numericText())
        }
        .coreFont(size: MacTextSize.meta)
        .frame(width: Space.s8 * 4, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

extension HardwarePage {
    /// Cores, CPU with its sparkline, RAM, whether it takes work, and the pause control (E15 §10). Nothing before the Core
    /// reports hardware, and nothing for a machine that is not in the list.
    @ViewBuilder var capacity: some View {
        if let f = model.facts(runner.id), !off {
            card("Capacity") {
                HStack(spacing: Space.s3) {
                    Label(f.gateWords, systemImage: f.gateSymbol).coreFont(size: MacTextSize.body, weight: .medium)
                    Spacer(minLength: Space.s2)
                    if !f.isCore { pauseMenu(f) }
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    RunnerBar(text: f.cpuWords, value: Double(f.hw.cpuPct) / 100, warn: f.hw.cpuPct >= 85)
                    RunnerBar(text: f.memWords, value: f.memUsed, warn: f.memUsed >= 0.85)
                }
                cpuChart
                if let b = f.battery { Text(b).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2) }
                Text(f.doing).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).monospacedDigit()
            }
        }
    }

    /// CPU use as sampled on each `hardware.changed`; under two samples it says so instead of drawing a line.
    @ViewBuilder private var cpuChart: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("CPU, recent").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            if let s = model.cpuSamples[runner.id], s.count >= 2 {
                CoreSpark(s, ceiling: 100).frame(height: Space.s8 + Space.s2)
            } else {
                Text("Not enough readings yet").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
        }
    }

    /// Pause for an hour, until tomorrow or indefinitely; Resume when it is paused. The Core is never paused by itself.
    private func pauseMenu(_ f: HardwareFacts) -> some View {
        let id = runner.id
        let m = model
        var items = [
            CoreDropdownItem("Pause for 1 hour", symbol: "pause") { Task { await m.pause(id, .hour) } },
            CoreDropdownItem("Pause until tomorrow", symbol: "moon") { Task { await m.pause(id, .tomorrow) } },
            CoreDropdownItem("Pause indefinitely", symbol: "pause.rectangle") {
                Task { await m.pause(id, .indefinite) }
            },
        ]
        if f.pausedNow {
            items.append(CoreDropdownItem("Resume", symbol: "play") { Task { await m.pause(id, .resume) } })
        }
        return CoreDropdown(items: items) {
            Label(f.pausedNow ? "Paused" : "Pause", systemImage: "pause")
                .coreFont(size: MacTextSize.meta, weight: .medium)
                .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlMd)
                .background(palette.uDim, in: coreShape(Radius.control))
        }
        .help("Stop new jobs and AI sessions going to \(runner.name). Work that is running finishes")
    }

    /// The toolchains the machine has ready for jobs, as quiet chips.
    @ViewBuilder var toolchains: some View {
        if let f = model.facts(runner.id), !off {
            card("Toolchains") {
                if f.toolchains.isEmpty {
                    Text("None ready for jobs yet.").foregroundStyle(palette.text2)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Space.s8 * 2), alignment: .leading)], alignment: .leading
                    ) {
                        ForEach(f.toolchains, id: \.self) { CoreChip($0, minWidth: 0).lineLimit(1) }
                    }
                }
            }
        }
    }

    /// A job running here now: what it runs and since when.
    func jobRow(_ j: HardwareItem.Job) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "hammer").foregroundStyle(palette.text2).frame(width: Space.s5).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(j.label).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text("Job · started " + j.startedAt.formatted(.relative(presentation: .named)))
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(palette.uDim, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
    }
}
