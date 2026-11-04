import CoreUI
import Shell
import SwiftUI

/// Settings, Core, Ops: what the Core's metrics say, in words, and the metrics themselves.
struct OpsSection: View {
    let admin: AdminModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.ops!
        AdminScreen(
            admin: admin, what: "Ops",
            intro: "From the Core's own metrics. Backups, restore and export run on the host.",
            state: model.state, empty: ("All clear", "The Core reported no metrics.", "checkmark.circle"),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s5) {
                Hero(model: model)
                if !model.alarms.isEmpty {
                    AdminSection(
                        title: "Alarms",
                        detail:
                            "ainkrad_alarm_active. Each bar shows how close the reading is to its threshold, which is a setting."
                    ) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Space.s8 * 6), spacing: Space.s3, alignment: .top)],
                            spacing: Space.s3
                        ) {
                            ForEach(model.details(admin.registry.items)) { d in AlarmCard(detail: d) }
                        }
                    }
                }
                if !model.tiles.isEmpty {
                    AdminSection(title: "Health", detail: "Figures the Core reports about itself.") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Space.s8 * 6), spacing: Space.s3, alignment: .top)],
                            spacing: Space.s3
                        ) {
                            ForEach(model.tiles) { t in tile(t) }
                        }
                    }
                }
                AdminSection(
                    title: "Lockouts",
                    detail: "Too many failed requests lock an address for a while. They are managed under Security."
                ) {
                    AdminPanel {
                        HStack {
                            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                                Text("Lockouts live in Security").font(
                                    .system(size: MacTextSize.headline, weight: .semibold))
                                Text("See which addresses and devices are locked out, and clear them there.")
                                    .foregroundStyle(palette.text2)
                            }
                            Spacer()
                            Button("Open lockouts") {
                                admin.host.shell.settings.selected = "lockouts"
                            }
                            .buttonStyle(.coreSecondary)
                        }
                    }
                }
                AdminSection(
                    title: "Metrics",
                    detail:
                        "\(model.samples.count) samples, read \(model.readAt.map { AdminWords.time($0) } ?? "just now"). Admin only."
                ) {
                    HStack(spacing: Space.s3) {
                        Button(model.showRaw ? "Hide Prometheus text" : "View Prometheus text") {
                            model.showRaw.toggle()
                        }
                        .buttonStyle(.coreSecondary)
                        Button("Refresh") { Task { await model.reload() } }.buttonStyle(.coreSecondary)
                            .help("Read the metrics again")
                    }
                    if model.showRaw {
                        ScrollView(.horizontal) {
                            Text(model.raw).font(.system(size: MacTextSize.meta, design: .monospaced))
                                .textSelection(.enabled).padding(Space.s3)
                        }
                        .frame(maxHeight: Space.s8 * 10)
                        .background(palette.glassCard, in: coreShape(Radius.cardMac))
                    }
                }
                Text(
                    "Backups run on the host. Restore, export and import are host commands with no button here. The Core only raises the backup age alarm above."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
        }
        .task { await model.reload() }
        .accessibilityIdentifier("ops")
    }

    private func tile(_ t: MetricTile) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(t.title).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
            Text(t.value).font(.system(size: MacTextSize.title, weight: .semibold).monospacedDigit()).lineLimit(2)
            Text(t.help).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).lineLimit(2)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
        .help(t.name)
    }
}

/// Core health in one line: whether any alarm is raised, and which.
private struct Hero: View {
    let model: OpsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let raised = model.alarms.filter(\.raised)
        let quiet = model.alarms.isEmpty
        let tone: Tone = raised.isEmpty ? .run : .warn
        let c = palette.tone(tone)
        HStack(alignment: .top, spacing: Space.s4) {
            Image(systemName: raised.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: MacTextSize.large * 1.4)).foregroundStyle(c.ink)
                .frame(width: MacSize.controlLg * 2, height: MacSize.controlLg * 2)
                .background(c.fill, in: coreShape(Radius.cardMac)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Core health").foregroundStyle(palette.text2)
                Text(raised.isEmpty ? (quiet ? "No alarms reported" : "All clear") : "Needs attention")
                    .font(.system(size: MacTextSize.large, weight: .semibold))
                Text(
                    raised.isEmpty
                        ? (quiet ? "The metrics name no alarm." : "No alarm is raised.")
                        : "Raised: \(raised.map(\.name).joined(separator: ", "))."
                )
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .background(c.fill, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ops-health")
    }
}

private struct AlarmCard: View {
    let detail: AlarmDetail
    @Environment(\.corePalette) private var palette

    var body: some View {
        let a = detail.alarm
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(a.name).font(.system(size: MacTextSize.headline, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                if a.raised {
                    StateBadge("Raised", tone: .warn, symbol: "exclamationmark.triangle")
                } else {
                    StateBadge("Clear", tone: .run, symbol: "checkmark")
                }
            }
            if let text = detail.readingText {
                Text(text).font(.system(size: MacTextSize.large, weight: .semibold).monospacedDigit())
                if let r = detail.reading, let l = detail.limit {
                    Gauge(reading: r, limit: l, raised: a.raised)
                    Text("limit \(detail.limitText ?? "") (\(detail.setting ?? ""))")
                        .font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2)
                        .lineLimit(2).truncationMode(.middle)
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .overlay {
            if a.raised { coreShape(Radius.cardMac).strokeBorder(palette.tone(.warn).ink.opacity(0.6), lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A reading against its threshold: a filled track and a tick at the limit.
private struct Gauge: View {
    let reading: Double
    let limit: Double
    let raised: Bool
    @Environment(\.corePalette) private var palette
    var body: some View {
        let top = max(reading, limit, 1) * 1.25
        GeometryReader { g in
            ZStack(alignment: .leading) {
                coreShape(Space.s1 / 2).fill(palette.track)
                coreShape(Space.s1 / 2).fill(raised ? palette.tone(.warn).ink : palette.primary)
                    .frame(width: g.size.width * reading / top)
                coreShape(1).fill(palette.text).frame(width: 2, height: Space.s3).offset(
                    x: g.size.width * limit / top - 1)  // grid: ok tick
            }
        }
        .frame(height: Space.s3)
        .accessibilityHidden(true)
    }
}
