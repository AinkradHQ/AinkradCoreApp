import SwiftUI

/// The connection states the prototype shows beyond `ConnectionBanner`: the Core dropped and the app resumes where it was,
/// the Core says slow down, the session is renewing, the Core restarted. A word and a symbol carry each state.
public enum LinkState: Sendable, Hashable {
    /// The event stream dropped; `since` is when what the screen shows was last current.
    case resuming(since: Date?)
    /// 429 `rate_limited`; `until` is when the wait ends (`Retry-After`).
    case rateLimited(until: Date?)
    /// `session_expired`: the session is being reopened in the background.
    case renewing
    case restarted

    var tone: Tone {
        switch self {
        case .resuming, .rateLimited: .warn
        case .renewing, .restarted: .done
        }
    }
    var symbol: String {
        switch self {
        case .resuming: "arrow.triangle.2.circlepath"
        case .rateLimited: "gauge.with.dots.needle.67percent"
        case .renewing: "person.badge.key"
        case .restarted: "arrow.counterclockwise"
        }
    }
    var title: String {
        switch self {
        case .resuming: "Reconnecting, resuming from where you were"
        case .rateLimited: "Slow down"
        case .renewing: "Session expired. Signing in again"
        case .restarted: "Home Core restarted"
        }
    }
}

public struct LinkBanner: View {
    let state: LinkState
    let retry: (() -> Void)?
    let dismiss: (() -> Void)?
    @Environment(\.corePalette) private var palette

    public init(_ state: LinkState, retry: (() -> Void)? = nil, dismiss: (() -> Void)? = nil) {
        self.state = state
        self.retry = retry
        self.dismiss = dismiss
    }

    public var body: some View {
        let c = palette.tone(state.tone)
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: state.symbol).foregroundStyle(c.ink).frame(width: Space.s4, height: Space.s4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(state.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                detail.font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if state == .renewing { LinkBar().padding(.top, Space.s1) }
            }
            Spacer(minLength: Space.s2)
            if state != .renewing, case .resuming = state, let retry {
                Button("Retry now", action: retry).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
            if state == .restarted, let dismiss {
                Button("Dismiss", action: dismiss).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2 + Space.s1 / 2)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .background(c.fill, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state == .renewing ? .updatesFrequently : [])
        .accessibilityIdentifier("link-banner")
    }

    @ViewBuilder private var detail: some View {
        switch state {
        case .resuming(let since):
            Text(
                "The connection to Home Core dropped. What you see is from \(since.map { $0.formatted(date: .omitted, time: .standard) } ?? "before it dropped"). Changes are paused and nothing is lost: events replay by sequence once it is back."
            )
        case .rateLimited(let until):
            if let until {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
                    Text(
                        "Too many requests (rate_limited). Try again in \(left) s. Changes are paused until then."
                    )
                    .monospacedDigit()
                }
            } else {
                Text("Too many requests (rate_limited). Changes are paused until the limit lifts.")
            }
        case .renewing:
            Text(
                "This Mac is renewing its session in the background (session_expired). Nothing to do."
            )
        case .restarted:
            Text(
                "Sessions were renewed silently. Elevation did not survive the restart, so your next change asks for Touch ID again."
            )
        }
    }
}

/// Progress with no end in sight, a rounded bar with a sliding segment (a rest in the middle with Reduce Motion).
private struct LinkBar: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / (Motion.tick * 1.5)
            let phase = reduce ? 0.5 : t - t.rounded(.down)
            GeometryReader { geo in
                let seg = geo.size.width * 0.3
                ZStack(alignment: .leading) {
                    coreShape(Space.s1 / 2).fill(palette.track)
                    coreShape(Space.s1 / 2).fill(palette.primary).frame(width: seg)
                        .offset(x: (geo.size.width - seg) * phase)  // grid: ok progress motion, not layout
                }
                .clipShape(coreShape(Space.s1 / 2))
            }
        }
        .frame(height: Space.s1)
        .accessibilityHidden(true)
    }
}
