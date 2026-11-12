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
        case .online, .reconnecting: .run
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

/// The chip in the status bar: a symbol and a word in a small rounded glass chip. A click opens `ConnectionPanel`.
struct ConnectionChip: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hovering = false

    var body: some View {
        if let state = shell.chipState {
            let c = palette.tone(state.tone)
            let title = state.title(core: shell.home.coreName)
            Button {
                shell.toggleConnectionPanel()
            } label: {
                HStack(spacing: Space.s1) {
                    Image(systemName: state.symbol)
                        .contentTransition(reduce ? .opacity : .symbolEffect(.replace))
                        .accessibilityHidden(true)
                    Text(title).lineLimit(1).contentTransition(.opacity)
                }
                .coreFont(size: MacTextSize.body)
                .foregroundStyle(c.ink)
                .padding(.horizontal, Space.s2)
                .frame(minHeight: MacSize.controlMd)
                .background(c.fill.opacity(hovering ? 1.4 : 1), in: coreShape(Radius.control))
                .contentShape(coreShape(Radius.control))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: state)
            .help("\(state.popTitle). Click for details.")
            .accessibilityLabel("\(shell.home.coreName), \(state.popTitle)")
        }
    }
}

/// What the chip opens: the state in words, last contact, the next try and a Reconnect now button (⌘R).
struct ConnectionPanel: View {
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
        let ink = palette.tone(state.tone).ink
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: state.symbol).coreFont(size: MacTextSize.title).foregroundStyle(ink)
                    .contentTransition(.symbolEffect(.replace)).accessibilityHidden(true)
                Text(state.popTitle).coreFont(size: MacTextSize.title, weight: .semibold)
            }
            Text(state.say(core: shell.home.coreName, since: shell.lastLiveAt, now: now))
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            if case .reconnecting = state, let next = shell.nextRetryAt, let span = shell.retrySpan {
                CoreMeter(1 - max(0, next.timeIntervalSince(now)) / span, label: "Time to the next try")
            }
            Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s1 + 2) {
                row("Last contact", lastContact(state, now: now))
                row("Next try", nextTry(state, now: now))
                if state != .online { row("Meanwhile", "Showing the last data") }
                if let h = shell.home.health {
                    row("Core version", h.version)
                    row("Up for", h.uptime)
                    row(
                        "Certificate",
                        h.certificate.map { $0 + (h.certDaysLeft ?? 0 > 0 ? " left" : "") } ?? "Not reported yet")
                    row("Last backup", h.backup(now: now) ?? "Not reported yet")
                }
            }
            if state != .online {
                Button {
                    shell.connectionPanelOpen = false
                    shell.retryConnection?()
                } label: {
                    HStack(spacing: Space.s2) {
                        Text("Reconnect now")
                        Text("⌘R").coreFont(size: 10, weight: .medium, design: .rounded)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CoreButtonStyle(.prominent))
                .disabled(shell.retryConnection == nil)
            }
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 10)
        .corePanel(radius: Radius.panel, padding: 0, part: .popups)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connection to \(shell.home.coreName)")
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            Text(v).coreFont(size: MacTextSize.body, weight: .medium).monospacedDigit()
        }
    }

    private func lastContact(_ state: ConnectionChipState, now: Date) -> String {
        if state == .online { return "Just now" }
        return shell.lastLiveAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "Not yet"
    }

    private func nextTry(_ state: ConnectionChipState, now: Date) -> String {
        switch state {
        case .online: return "Not needed"
        case .noNetwork: return "When the network is back"
        default:
            guard let next = shell.nextRetryAt else { return "Now" }
            let s = Int(next.timeIntervalSince(now).rounded(.up))
            if s <= 0 { return "Now" }
            let base = s == 1 ? "In 1 second" : "In \(s) seconds"
            if case .reconnecting(let n) = state, n > 0 { return base + " (try \(n))" }
            return base
        }
    }
}
