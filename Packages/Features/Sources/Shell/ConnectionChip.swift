import CoreUI
import Network
import SwiftUI

/// What the status chip says about the Core connection (N14): four states, told apart by what the Mac knows
/// (`NWPathMonitor`) and what the socket says (`CoreLink`).
public enum ConnectionChipState: Equatable, Sendable {
    case online
    case reconnecting(attempt: Int)
    case noNetwork
    case coreNotAnswering

    /// nil when there is no Core to name (not paired yet): the chip stays away.
    public static func of(link: CoreLink, networkUp: Bool, attempt: Int) -> ConnectionChipState? {
        switch link {
        case .none: nil
        case .live: .online
        case .connecting, .reconnecting: networkUp ? .reconnecting(attempt: attempt) : .noNetwork
        case .offline: networkUp ? .coreNotAnswering : .noNetwork
        }
    }

    var symbol: String {
        switch self {
        case .online: "checkmark.icloud"
        case .reconnecting: "arrow.triangle.2.circlepath.icloud"
        case .noNetwork: "wifi.slash"
        case .coreNotAnswering: "exclamationmark.icloud"
        }
    }

    var tone: Tone {
        switch self {
        // n14: online and reconnecting are blue; green is kept for work that runs.
        case .online, .reconnecting: .done
        case .noNetwork: .queue
        case .coreNotAnswering: .warn
        }
    }

    /// The chip's words; `core` is the Core's name.
    func title(core: String) -> String {
        switch self {
        case .online: core
        case .reconnecting(let n): n > 0 ? "Reconnecting… (try \(n))" : "Reconnecting…"
        case .noNetwork: "No network"
        case .coreNotAnswering: "Core not answering · Retry"
        }
    }

    var popTitle: String {
        switch self {
        case .online: "Connected"
        case .reconnecting: "Reconnecting"
        case .noNetwork: "No network"
        case .coreNotAnswering: "Core not answering"
        }
    }

    func say(core: String, since: Date?, now: Date) -> String {
        switch self {
        case .online: "\(core) answers. Everything is live."
        case .reconnecting:
            "The connection dropped\(since.map { " \(Self.ago($0, now)) ago" } ?? ""). Ainkrad is trying again by itself."
        case .noNetwork: "This Mac is not connected to the internet. Ainkrad tries again when the network is back."
        case .coreNotAnswering:
            "This Mac is online, but \(core) did not answer\(since.map { " for \(Self.ago($0, now))" } ?? ""). Your AI sessions keep working."
        }
    }

    /// "12 seconds", "1 minute", "3 minutes".
    static func ago(_ d: Date, _ now: Date) -> String {
        let s = max(1, Int(now.timeIntervalSince(d)))
        if s < 60 { return s == 1 ? "1 second" : "\(s) seconds" }
        let m = s / 60
        return m == 1 ? "1 minute" : "\(m) minutes"
    }
}

/// Watches the Mac's network path. One per shell; the app starts it once.
@MainActor
final class NetworkWatch {
    private let monitor = NWPathMonitor()
    private var started = false

    func start(_ change: @escaping @MainActor (Bool) -> Void) {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            Task { @MainActor in change(up) }
        }
        monitor.start(queue: DispatchQueue(label: "ainkrad.network-watch"))
    }
}

/// The Core dropdown (E2-2, mockup `kit/topbar.js` core): how the Core is, three facts, the devices, the last backup, and
/// Reconnect (only when the link is down) beside Core settings.
struct ConnectionPanel: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        if let state = shell.chipState {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                content(state, now: ctx.date)
            }
        }
    }

    private func content(_ state: ConnectionChipState, now: Date) -> some View {
        let health = shell.home.health
        return VStack(alignment: .leading, spacing: Space.s3) {
            DropHead(
                symbol: "cube", title: shell.home.coreName, meta: meta(state, now: now),
                badge: DropBadge(state == .online ? "Healthy" : state.popTitle, tone: state.tone))
            if state != .online, case .reconnecting = state, let next = shell.nextRetryAt, let span = shell.retrySpan {
                CoreMeter(1 - max(0, next.timeIntervalSince(now)) / span, label: "Time to the next try")
            }
            if let h = health {
                HStack(spacing: Space.s2) {
                    // Memory, disk and response when the Core says them; a Core that does not still shows its version and uptime.
                    ForEach(stats(h), id: \.label) { DropStat($0.value, $0.label, share: $0.share, low: $0.low) }
                }
            }
            if let u = shell.coreUpdate {
                HStack(spacing: Space.s3) {
                    IconTile("arrow.down.circle", hue: GlassInk.accent(paneAccent), size: MacSize.controlMd)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available").coreFont(size: MacTextSize.headline, weight: .semibold)
                        Text(u.line).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    }
                    Spacer(minLength: Space.s2)
                    Button("Update now") {
                        shell.topMenu = nil
                        u.installNow()
                    }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                }
                .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.cardMac))
            }
            let devices = shell.devicesGlance?() ?? []
            if !devices.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Devices").coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
                        .padding(.horizontal, Space.s1)
                    ForEach(devices.prefix(4)) { d in
                        CoreRow(d.name, subtitle: d.sub, symbol: d.symbol, action: { open("devices") }) {
                            DropBadge(d.online ? "Online" : "Away", tone: d.online ? .run : .queue)
                        }
                    }
                }
            }
            HStack(spacing: Space.s2) {
                if state != .online {
                    Button("Reconnect") {
                        shell.topMenu = nil
                        shell.retryConnection?()
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .environment(\.coreKeycap, "⌘R")
                    .disabled(shell.retryConnection == nil)
                    .help("Try to reach \(shell.home.coreName) now (⌘R)")
                }
                Spacer(minLength: 0)
                Button("Core settings") { open("settings") }.buttonStyle(CoreButtonStyle(.plain))
            }
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 11)
        .corePanel(radius: Radius.pane, padding: 0, part: .popups)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connection to \(shell.home.coreName)")
    }

    private struct Stat {
        let value: String
        let label: String
        var share: Double?
        var low = false
    }

    /// Memory, Disk and Response with a bar each when the Core says the share (the whole machine's memory, the disk, the
    /// answer time against 150 ms); a Core that does not still shows what it has, then its version and uptime.
    private func stats(_ h: CoreHealthFacts) -> [(value: String, label: String, share: Double?, low: Bool)] {
        let ms = shell.responseMs
        let all: [Stat?] = [
            h.memoryPct.map { Stat(value: "\($0)%", label: "Memory", share: Double($0) / 100, low: $0 >= 90) }
                ?? h.memory.map { Stat(value: $0, label: "Memory") },
            h.diskUsedPct.map { Stat(value: "\($0)%", label: "Disk", share: Double($0) / 100, low: $0 >= 90) },
            ms.map { Stat(value: "\($0) ms", label: "Response", share: min(1, Double($0) / 150), low: $0 >= 150) },
            Stat(value: h.version, label: "Version"), Stat(value: h.uptime, label: "Up for"),
        ]
        return Array(all.compactMap { $0 }.prefix(3)).map { ($0.value, $0.label, $0.share, $0.low) }
    }

    /// "Up for 12 days · everything is fine", or what is wrong in a few words.
    private func meta(_ state: ConnectionChipState, now: Date) -> String {
        switch state {
        case .online:
            return shell.home.health.map { "Up for \($0.uptime) · everything is fine" } ?? "Everything is fine"
        case .reconnecting(let n): return n > 0 ? "Trying again by itself (try \(n))" : "Trying again by itself"
        case .noNetwork: return "This Mac is not online"
        case .coreNotAnswering: return "Your AI sessions keep working"
        }
    }

    private func open(_ id: String) {
        shell.topMenu = nil
        shell.launcher.entry(id)?.run()
    }
}
