import CoreUI
import SwiftUI

// The top bar's dropdowns (E2-2, mockup `kit/topbar.js`): a header with a tile and a state, a few facts, then rows. The Core
// dropdown is `ConnectionPanel`; the bell is `BellGlance`.

/// A state in words with its coloured square.
struct DropBadge: View {
    let label: String
    let tone: Tone
    init(_ label: String, tone: Tone) {
        self.label = label
        self.tone = tone
    }
    var body: some View { StateBadge(label, tone: tone, symbol: "circle") }
}

/// Tile, title, one quiet line and a state on the right.
struct DropHead<Trailing: View>: View {
    @Environment(\.coreAccent) private var paneAccent
    let symbol: String
    let title: String
    let meta: String
    @ViewBuilder let trailing: Trailing
    @Environment(\.corePalette) private var palette

    init(symbol: String, title: String, meta: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.meta = meta
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            IconTile(symbol, hue: GlassInk.accent(paneAccent), size: MacSize.controlLg + Space.s1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                Text(meta).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(2)
            }
            Spacer(minLength: Space.s2)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension DropHead where Trailing == DropBadge {
    init(symbol: String, title: String, meta: String, badge: DropBadge) {
        self.init(symbol: symbol, title: title, meta: meta) { badge }
    }
}

/// A fact on a quiet well: the value big, its name small.
struct DropStat: View {
    let value: String
    let label: String
    /// A share, 0...1, drawn as a thin bar under the figure (the Core menu's Memory, Disk and Response); nil draws none.
    let share: Double?
    let low: Bool
    @Environment(\.corePalette) private var palette
    init(_ value: String, _ label: String, share: Double? = nil, low: Bool = false) {
        self.value = value
        self.label = label
        self.share = share
        self.low = low
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(value).coreFont(size: MacTextSize.title, weight: .semibold).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
            if let share { CoreMeter(share, low: low, label: label) }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
    }
}

/// Seven little bars: they breathe while the runner works, sit flat when it idles or is off. Reduce Motion: still bars.
private struct ActivityBars: View {
    let working: Bool
    let off: Bool
    @State private var on = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    private static let heights: [CGFloat] = [5, 12, 8, 14, 6, 11, 9]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { i, h in
                coreShape(1).fill(working ? palette.tone(.run).ink : palette.text2.opacity(off ? 0.4 : 0.7))
                    .frame(width: 4, height: working ? h : off ? 2 : 3)
                    .scaleEffect(y: working && on && !reduce ? 0.55 : 1, anchor: .bottom)
                    .animation(
                        working && !reduce
                            ? .easeInOut(duration: 1.3).repeatForever(autoreverses: true).delay(Double(i) * 0.37 / 2)
                            : nil, value: on)
            }
        }
        .frame(width: 44, height: 16, alignment: .bottom)
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}

/// The Runners dropdown: how many work right now, every runner with its load, and the ways on.
struct RunnersPanel: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let machines = shell.home.machines
        let working = machines.filter { $0.online && $0.used > 0 }
        let tasks = machines.reduce(0) { $0 + $1.used }
        return VStack(alignment: .leading, spacing: Space.s3) {
            DropHead(
                symbol: "server.rack", title: "Runners",
                meta: machines.isEmpty
                    ? "No runner yet"
                    : working.isEmpty
                        ? "Nothing is running right now"
                        : "\(working.count) running right now · \(tasks) \(tasks == 1 ? "task" : "tasks")"
            ) {
                Button("Add runner") { go("add-device") }.buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
            if machines.isEmpty {
                CoreStateCard(
                    symbol: "server.rack", title: "No runners yet",
                    line: "A runner is a computer your AI sessions and terminals run on.")
            } else {
                VStack(spacing: Space.s1) {
                    ForEach(machines) { m in
                        CoreRow(
                            m.id, subtitle: sub(m),
                            symbol: m.os.lowercased().contains("mac") ? "laptopcomputer" : "server.rack",
                            action: { go("runners") }
                        ) {
                            HStack(spacing: Space.s3) {
                                ActivityBars(working: m.online && m.used > 0, off: !m.online)
                                DropBadge(state(m).0, tone: state(m).1)
                            }
                        }
                        .opacity(m.online ? 1 : 0.6)
                    }
                }
            }
            ForEach(machines) { m in if let u = update(m) { updatingRow(m, u) } }
            HStack(spacing: Space.s3) {
                if shell.showsRunnerUpdates, !machines.isEmpty {
                    Text(footnote(machines)).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("Open Runners") { go("runners") }.buttonStyle(CoreButtonStyle(.plain))
            }
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 12)
        .corePanel(radius: Radius.pane, padding: 0, part: .popups)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Runners")
    }

    private func sub(_ m: HomeSnapshot.Machine) -> String {
        m.used > 0 && m.online ? "\(m.os) · \(m.used) \(m.used == 1 ? "task" : "tasks")" : m.os
    }
    /// The runner being updated, only on a Core that reports it (API minor 95) and only while it is online.
    private func update(_ m: HomeSnapshot.Machine) -> RunnerUpdate? {
        shell.showsRunnerUpdates && m.online ? shell.runnerUpdates[m.runnerID] : nil
    }
    private func state(_ m: HomeSnapshot.Machine) -> (String, Tone) {
        !m.online
            ? ("Offline", .fail)
            : update(m) != nil ? ("Updating", .done) : m.used > 0 ? ("Running", .run) : ("Idle", .queue)
    }
    private func footnote(_ ms: [HomeSnapshot.Machine]) -> String {
        let names = ms.filter { update($0) != nil }.map(\.id)
        return names.isEmpty
            ? "All runners are on the latest tools."
            : "All runners are on the latest tools except \(names.joined(separator: ", "))."
    }
    /// "Updating Dune": the tools update by themselves, so the row only shows how far it is.
    private func updatingRow(_ m: HomeSnapshot.Machine, _ u: RunnerUpdate) -> some View {
        Button {
            go("runners")
        } label: {
            HStack(spacing: Space.s3) {
                IconTile("arrow.triangle.2.circlepath", hue: GlassInk.accent(paneAccent), size: MacSize.controlLg)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Updating \(m.id)").coreFont(size: MacTextSize.body, weight: .semibold)
                    Text("Tools update by themselves, nothing to do").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(palette.text2)
                    CoreMeter(u.fraction, label: "Updating \(m.id)")
                }
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Updating \(m.id), \(u.percent) percent. \(u.toolName)")
    }
    private func go(_ id: String) {
        shell.topMenu = nil
        shell.launcher.entry(id)?.run()
    }
}
