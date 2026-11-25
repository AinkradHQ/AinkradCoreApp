import CoreUI
import SwiftUI

/// The host panel at the bottom right: the selected host, live. Name, group and system, its light; the route as chips;
/// CPU, memory and disk with their trend; how it signs in; an AI request waiting; the last three things that happened; and
/// the actions: Open Terminal (Return), Files ⌘2, History ⌘3, Access ⌘, and More. An offline host says so, with Try Now.
struct HostPeek: View {
    static let width: CGFloat = 360
    let model: LeylineModel
    let host: HostItem
    @State private var trying = false
    @Environment(\.corePalette) private var palette

    private var extras: HostExtras { model.extras[host.id] ?? HostExtras() }
    private var off: Bool { host.light == .off }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3 + 2) {
            header
            RouteChain(hops: chain)
            if off { offline } else if let h = model.healthByHost[host.id] { metrics(h) }
            facts
            if let ask = extras.approval { approval(ask) }
            feed
            actions
        }
        .frame(width: Self.width - Space.s4 * 2)
        .corePanel(radius: Radius.pane, padding: Space.s4)
        .task(id: host.id) { if model.activity[host.id] == nil { await model.loadActivity(host.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(host.name), host panel")
        .accessibilityIdentifier("host-peek")
    }

    // MARK: parts

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            HostTile(symbol: host.symbol(isJump: model.jumpIDs.contains(host.id)))
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(host.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                HStack(spacing: Space.s1 + 2) {
                    CoreChip(model.groupTitle(host), minWidth: 0)
                    if let os = extras.osName ?? host.os.map(Self.osWord) { CoreChip(os, minWidth: 0) }
                }
            }
            Spacer(minLength: Space.s2)
            if let word = host.latencyWord {
                StateBadge(
                    off ? "Offline" : host.light == .slow ? "Slow · \(word)" : word,
                    tone: off ? .queue : host.light == .slow ? .warn : .run, symbol: "circle")
            }
        }
    }

    static func osWord(_ os: String) -> String {
        switch os {
        case "linux": "Linux"
        case "darwin": "macOS"
        default: os.capitalized
        }
    }

    /// The Core, each jump host, then this host.
    private var chain: [RouteChain.Hop] {
        [RouteChain.Hop(name: host.viaRunner == nil ? "Core" : "Runner", symbol: nil, me: false)]
            + host.jumpChain.map {
                RouteChain.Hop(
                    name: model.hostItem($0)?.name ?? "a removed host", symbol: "checkmark.shield", me: false)
            } + [RouteChain.Hop(name: host.name, symbol: "cpu", me: true)]
    }

    private var offline: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(
                (host.reach?.seenAt.map { "No answer since \($0.formatted(date: .omitted, time: .shortened)). " }
                    ?? "It is not answering. ") + "Leyline tries again every minute."
            )
            .coreFont(size: MacTextSize.meta).fixedSize(horizontal: false, vertical: true)
            Button("Try Now") { Task { await tryNow() } }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small, busy: trying)).disabled(trying)
                .accessibilityIdentifier("peek-try-now")
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
    }

    /// Asks the Core to reach the host now, says how it went, and reads the hosts again.
    private func tryNow() async {
        trying = true
        defer { trying = false }
        do {
            let c = try await model.checkHost(host.address, host.port)
            model.host.shell.showToast(
                c.ok
                    ? "\(host.name) answered in \(c.ms ?? 0) ms"
                    : "\(host.name) did not answer: \(c.reason ?? "no reply")",
                kind: c.ok ? .info : .warn)
        } catch { model.host.shell.showToast(model.words(error), kind: .warn) }
        await model.reload()
    }

    private func metrics(_ h: HostHealth) -> some View {
        HStack(spacing: Space.s2) {
            tile("CPU", h.cpuPct, h.load1.map { "load \(coreDecimal($0, 1))" }, h.cpuSeries)
            tile("Memory", h.memPct, extras.memoryTotal, h.memSeries)
            tile("Disk", h.diskPct, extras.diskFree, h.diskSeries)
        }
    }

    @ViewBuilder private func tile(_ name: String, _ v: Double?, _ extra: String?, _ series: [Double]) -> some View {
        if let v {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack {
                    Text(name)
                    Spacer(minLength: Space.s1)
                    if let extra { Text(extra).lineLimit(1) }
                }
                .coreFont(size: 10).foregroundStyle(GlassInk.secondary)
                Text("\(Int(v.rounded()))%").coreFont(size: MacTextSize.title, weight: .semibold)
                    .foregroundStyle(v > 85 ? palette.error : v > 70 ? palette.warning : GlassInk.primary)
                CoreSpark(series, tone: v > 85 ? .fail : v > 70 ? .warn : .run, ceiling: 100).frame(
                    height: Space.s4 + 2)
            }
            .padding(.horizontal, Space.s2 + 2).padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.control + 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name) \(Int(v.rounded())) percent" + (extra.map { ", \($0)" } ?? ""))
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s2 - 2) {
            fact("Signs in", Text(host.login).coreFont(size: MacTextSize.meta, design: .monospaced))
            fact("Key", Text(keyWord))
            fact("AI here", Text(host.aiRule.title))
            if let up = extras.uptime { fact("Up", Text(up)) }
        }
        .coreFont(size: MacTextSize.meta + 1)
    }

    private func fact<V: View>(_ name: String, _ value: V) -> some View {
        GridRow {
            Text(name).foregroundStyle(GlassInk.secondary).frame(width: Space.s8 * 2 + Space.s1, alignment: .leading)
            value.lineLimit(1)
        }
    }

    private var keyWord: String {
        guard let id = host.keyID else { return "Password, typed in the terminal" }
        guard let k = model.key(id) else { return "A key that is gone" }
        return "\(k.name) · \(k.typeWord)"
    }

    private func approval(_ command: String) -> some View {
        HStack(spacing: Space.s2 + 2) {
            CountBadge(1, label: "AI waits for you")
            (Text("AI wants to run ") + Text(command).font(.system(size: MacTextSize.meta + 1, design: .monospaced)))
                .coreFont(size: MacTextSize.meta + 1).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s1)
            Button("Review") { model.host.shell.bellOpen = true }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .help("Open the approval in the bell")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var feed: some View {
        let rows = model.activity[host.id] ?? []
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2 - 2) {
                ForEach(rows) { e in
                    HStack(spacing: Space.s2) {
                        Image(systemName: HostWords.symbol(e.who)).coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary).frame(width: Space.s4).accessibilityHidden(true)
                        Text(Self.say(e)).lineLimit(1)
                        Spacer(minLength: Space.s2)
                        Text(HostWords.ago(e.at)).foregroundStyle(GlassInk.secondary)
                    }
                    .coreFont(size: MacTextSize.meta + 1)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// "You · terminal · 12 min", or the words as the Core wrote them.
    static func say(_ e: HostEvent) -> String {
        e.detail.isEmpty || e.who == .system && e.what != "terminal"
            ? e.what : "\(HostWords.who(e.who)) · \(e.what)" + (e.minutes.map { " · \($0) min" } ?? "")
    }

    private var actions: some View {
        HStack(spacing: Space.s1 + 2) {
            Button {
                model.openHost(host.id, .terminal)
            } label: {
                Label("Open Terminal", systemImage: "terminal").frame(maxWidth: .infinity)
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .environment(\.coreKeycap, "⏎")
            .disabled(off)
            .accessibilityIdentifier("peek-open-terminal")
            ForEach([HostSection.files, .history, .access]) { s in
                CoreIconButton(symbol: s.symbol, label: "\(s.title)  \(s.keyWord)") { model.openHost(host.id, s) }
                    .disabled(off && s != .access)
                    .help("\(s.title)  \(s.keyWord)")
            }
            CoreDropdown(items: HostMore.items(model, host)) {
                Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .medium)
                    .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .background(GlassInk.well, in: coreShape(Radius.control))
            }
            .help("More")
            .accessibilityLabel("More")
        }
    }
}

/// The route as chips joined by short lines: Core — bastion — lan-web-1, the host itself in the accent.
struct RouteChain: View {
    struct Hop: Hashable {
        let name: String
        let symbol: String?
        let me: Bool
    }
    let hops: [Hop]
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s1 + 2) {
            ForEach(Array(hops.enumerated()), id: \.offset) { i, h in
                if i > 0 {
                    coreShape(1).fill(GlassInk.secondary.opacity(0.5)).frame(width: Space.s3 + 2, height: 1.5)
                }
                HStack(spacing: Space.s1 + 2) {
                    if let s = h.symbol {
                        Image(systemName: s).coreFont(size: MacTextSize.meta - 1)
                    } else {
                        Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: Space.s3)
                    }
                    Text(h.name).coreFont(size: MacTextSize.meta, weight: h.me ? .semibold : .regular).lineLimit(1)
                }
                .foregroundStyle(h.me ? palette.primary : GlassInk.primary)
                .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
                .background(h.me ? palette.btnPrimary.opacity(0.22) : GlassInk.well, in: coreShape(Radius.control))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reached through " + hops.map(\.name).joined(separator: ", then "))
    }
}

/// The More menu of a host (the panel and the host view): what has no key of its own.
@MainActor
enum HostMore {
    static func items(_ m: LeylineModel, _ h: HostItem, state: HostPageState? = nil) -> [CoreDropdownItem] {
        var out = [
            CoreDropdownItem("Commands", symbol: "chevron.right.2") { m.openHost(h.id, .commands) },
            CoreDropdownItem("Change Host…", symbol: "slider.horizontal.3", enabled: !m.readOnly) {
                HostDialogs.openEdit(m, h)
            },
            CoreDropdownItem("Keys", symbol: "key") {
                m.closeHost()
                m.page = .keys
            },
        ]
        if let state {
            out.insert(
                state.direct == nil
                    ? CoreDropdownItem("Lend the Key to This Mac…", symbol: "touchid", enabled: !m.readOnly) {
                        Task { await state.startDirect() }
                    }
                    : CoreDropdownItem("Take the Key Back", symbol: "key", destructive: true) {
                        Task { await state.stopDirect() }
                    }, at: 1)
            if m.hostTerminals[h.id] != nil {
                out.insert(
                    CoreDropdownItem("Open Terminal in Its Own Pane", symbol: "macwindow") {
                        if let t = m.hostTerminals[h.id] { Task { await m.openTerminal?(t) } }
                    }, at: 1)
            }
        }
        return out
    }
}
