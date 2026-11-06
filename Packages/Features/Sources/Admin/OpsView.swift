import CoreUI
import Shell
import SwiftUI

/// Settings, Core, Ops: how your Core is doing, in plain words. One verdict at the top, the three warnings (backup,
/// certificate, disk) with how close each is to its limit, then the figures the Core reports about itself. It reads the
/// metrics again every 15 seconds while shown; ⌘R reads now, M shows the raw metrics.
struct OpsSection: View {
    let admin: AdminModel

    var body: some View {
        let model = admin.ops!
        AdminScreen(
            admin: admin, what: "Ops",
            intro: "How your Core is doing, from its own figures. Updates by itself while you look.",
            state: model.state, empty: ("No figures yet", "Your Core reported no figures.", "tray"),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Verdict(admin: admin, model: model)
                let warnings = model.details(admin.registry.items)
                if !warnings.isEmpty {
                    GlassSection(
                        "Warnings", sub: "Your Core warns you before these become a problem.",
                        symbol: "exclamationmark.triangle.fill", hue: GlassInk.orange, index: 1
                    ) {
                        HStack(alignment: .top, spacing: Space.s3) {
                            ForEach(warnings) { d in WarningCard(admin: admin, detail: d) }
                        }
                    }
                }
                let tiles = model.tiles.filter { OpsWords.figure[$0.name] != nil }
                if !tiles.isEmpty {
                    GlassSection(
                        "Right now", sub: "What your Core reports about itself.", symbol: "waveform.path.ecg",
                        hue: GlassInk.blue, index: 2
                    ) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 3),
                            spacing: Space.s3
                        ) {
                            ForEach(tiles) { t in FigureTile(model: model, tile: t) }
                        }
                    }
                }
                RawMetrics(model: model)
            }
            .foregroundStyle(GlassInk.primary)
        }
        .task {
            await model.reload()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                await model.reload()
            }
        }
        .accessibilityIdentifier("ops")
    }
}

/// Plain words for what the metrics name.
enum OpsWords {
    static let figure: [String: (symbol: String, hue: Color)] = [
        "ainkrad_uptime_seconds": ("clock.fill", GlassInk.blue),
        "ainkrad_devices_active": ("laptopcomputer.and.iphone", GlassInk.blue),
        "ainkrad_runners": ("server.rack", GlassInk.blue),
        "ainkrad_terminals": ("terminal.fill", GlassInk.blue),
        "ainkrad_agent_sessions": ("play.fill", GlassInk.blue),
        "ainkrad_db_size_bytes": ("cylinder.fill", GlassInk.slate),
    ]

    static let warning: [String: (title: String, symbol: String, ok: String, raised: String, fix: String)] = [
        "backup_age": (
            "Backup", "externaldrive.fill.badge.timemachine", "Your newest backup is recent enough.",
            "Your newest backup is too old.", "Backups run on the Core's host. Run one there."
        ),
        "cert_expiry": (
            "Certificate", "lock.shield.fill", "The certificate has plenty of time left.",
            "The certificate runs out soon.", "Renew it on the Core's host."
        ),
        "disk_free": (
            "Disk space", "internaldrive.fill", "There is enough free space for the database.",
            "Disk space is running low.", "Free space on the Core's host."
        ),
    ]

    /// `2 days 4 h`, `41 days`, `38%`.
    static func reading(_ name: String, _ v: Double) -> String {
        switch name {
        case "backup_age": duration(v)
        case "cert_expiry": Int(v.rounded()) == 1 ? "1 day left" : "\(Int(v.rounded())) days left"
        case "disk_free": "\(Int(v.rounded()))% free"
        default: v.formatted()
        }
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        func n(_ k: Int, _ w: String) -> String { "\(k) \(w)\(k == 1 ? "" : "s")" }
        if s >= 86_400 {
            return s % 86_400 / 3_600 == 0 ? n(s / 86_400, "day") : "\(n(s / 86_400, "day")) \(s % 86_400 / 3_600) h"
        }
        if s >= 3_600 { return "\(s / 3_600) h \(s % 3_600 / 60) min" }
        if s >= 60 { return "\(s / 60) min" }
        return "\(s) s"
    }
}

/// The one answer at the top: all good, or what needs a look. Refresh and the raw metrics at the top right.
private struct Verdict: View {
    let admin: AdminModel
    @Bindable var model: OpsModel
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let raised = model.alarms.filter(\.raised)
        let ok = raised.isEmpty
        let hue = ok ? GlassInk.green : GlassInk.orange
        let names = raised.map { OpsWords.warning[$0.name]?.title ?? $0.name }
        HStack(spacing: Space.s4) {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: MacTextSize.large * 1.5, weight: .semibold)).foregroundStyle(.white)
                .frame(width: Space.s8 * 2, height: Space.s8 * 2)
                .background(
                    LinearGradient(colors: [hue, hue.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                    in: coreShape(Radius.cardMac)
                )
                .overlay { coreShape(Radius.cardMac).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .nonRepeating, value: reduce ? true : ok)
            VStack(alignment: .leading, spacing: 3) {
                Text(ok ? "Your Core is doing well" : "\(names.joined(separator: " and ")) needs a look")
                    .font(.system(size: MacTextSize.large, weight: .semibold)).foregroundStyle(hue)
                Text(
                    ok
                        ? "Nothing needs you. Last read \(model.readAt.map { AdminWords.time($0) } ?? "just now")."
                        : raised.compactMap { OpsWords.warning[$0.name]?.fix }.joined(separator: " ")
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            AppActionTile(title: "Read now", symbol: "arrow.clockwise", key: "⌘R", hue: GlassInk.blue) {
                Task { await model.reload() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(Space.s4)
        .coreWell()
        .animation(Motion.out(Motion.move), value: ok)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ops-health")
    }
}

/// One warning: what it watches, the reading as people say it, a bar to the point where it warns, and a tile that opens
/// the limit in Core settings.
private struct WarningCard: View {
    let admin: AdminModel
    let detail: AlarmDetail

    var body: some View {
        let a = detail.alarm
        let w = OpsWords.warning[a.name]
        let hue = a.raised ? GlassInk.orange : GlassInk.green
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile(w?.symbol ?? "bell.fill", hue: hue, size: 36, bounce: a.raised)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text(w?.title ?? a.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Label(
                        a.raised ? "Needs a look" : "Fine",
                        systemImage: a.raised ? "exclamationmark.square.fill" : "checkmark.square.fill"
                    )
                    .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(hue)
                }
                Spacer(minLength: 0)
            }
            if let r = detail.reading {
                Text(OpsWords.reading(a.name, r)).font(
                    .system(size: MacTextSize.large, weight: .semibold, design: .rounded)
                )
                .contentTransition(.numericText())
                if let l = detail.limit { Meter(reading: r, limit: l, hue: hue) }
            }
            Text(a.raised ? (w?.raised ?? "Raised.") : (w?.ok ?? "Clear."))
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            if let key = detail.setting, let item = admin.registry.item(key) {
                let limit = SettingWords.value(item, item.value)
                AppActionTile(title: "Warns at \(limit)", symbol: "slider.horizontal.3", key: "", hue: GlassInk.slate) {
                    admin.registry.cursor = key
                    admin.host.shell.settings.selected = "core"
                }
                .help("Change this limit in Core settings. Setting: \(key)")
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(a.raised ? GlassInk.orange.opacity(0.1) : .clear)
        .coreWell()
        .accessibilityElement(children: .combine)
    }
}

/// A reading against the point where it warns: a fill and a tick at the limit.
private struct Meter: View {
    let reading: Double
    let limit: Double
    let hue: Color
    var body: some View {
        let top = max(reading, limit, 1) * 1.25
        GeometryReader { g in
            ZStack(alignment: .leading) {
                coreShape(3).fill(GlassInk.track.opacity(0.6)).frame(height: 6)
                coreShape(3).fill(
                    LinearGradient(colors: [hue.opacity(0.5), hue], startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: max(g.size.width * reading / top, 6), height: 6)
                coreShape(1).fill(.white).frame(width: 2, height: 14)
                    .offset(x: g.size.width * limit / top - 1)  // grid: ok tick
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .animation(Motion.out(Motion.move), value: reading)
        .accessibilityHidden(true)
    }
}

/// One figure: a glyph in its colour, the value, its name, and a line of its last readings when there are some.
private struct FigureTile: View {
    let model: OpsModel
    let tile: MetricTile

    var body: some View {
        let look = OpsWords.figure[tile.name] ?? ("number", GlassInk.slate)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                IconTile(look.symbol, hue: look.hue, size: 28)
                Text(tile.title).font(.system(size: MacTextSize.body, weight: .semibold)).foregroundStyle(
                    GlassInk.secondary)
                Spacer(minLength: 0)
            }
            Text(value).font(.system(size: MacTextSize.large, weight: .semibold, design: .rounded)).lineLimit(1)
                .minimumScaleFactor(0.7).contentTransition(.numericText())
            if let h = model.history[tile.name], h.count >= 2 { CoreSpark(h).frame(height: 24) }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .help(tile.help.isEmpty ? tile.name : tile.help)
        .accessibilityElement(children: .combine)
    }

    /// One figure, or the non-zero parts of a split one, number first: `3 apps · 2 runners`, `2 connected`.
    private var value: String {
        let rows = model.samples.filter { $0.name == tile.name }
        guard rows.count > 1 || !(rows.first?.labels.isEmpty ?? true) else {
            return tile.name == "ainkrad_uptime_seconds"
                ? OpsWords.duration(rows.first?.value ?? 0) : tile.value
        }
        let parts = rows.filter { $0.value != 0 }.map { r -> String in
            let n = Int(r.value.rounded())
            let (key, word) = r.labels.sorted { $0.key < $1.key }.first ?? ("", "")
            return "\(n) \(key == "kind" && n != 1 ? word + "s" : word)"
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }
}

/// The metrics as the Core sends them, folded away; M opens them.
private struct RawMetrics: View {
    @Bindable var model: OpsModel

    var body: some View {
        GlassSection(
            "Raw metrics", sub: "\(model.samples.count) figures exactly as your Core sends them, for tools.",
            symbol: "chevron.left.forwardslash.chevron.right", hue: GlassInk.slate, index: 3
        ) {
            AppActionTile(
                title: model.showRaw ? "Hide" : "Show", symbol: model.showRaw ? "eye.slash" : "eye", key: "M",
                hue: GlassInk.slate
            ) {
                model.showRaw.toggle()
            }
            .keyboardShortcut("m", modifiers: [])
        } content: {
            if model.showRaw {
                ScrollView(.horizontal) {
                    Text(model.raw).font(.system(size: MacTextSize.meta, design: .monospaced))
                        .textSelection(.enabled).padding(Space.s3)
                }
                .frame(maxHeight: Space.s8 * 10)
                .background(GlassInk.well, in: coreShape(Radius.control))
                .transition(.opacity)
            }
        }
        .animation(Motion.out(Motion.ui), value: model.showRaw)
    }
}
