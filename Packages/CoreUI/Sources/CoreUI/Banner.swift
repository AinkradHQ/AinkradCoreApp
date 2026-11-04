import SwiftUI

public enum ConnectionState: Sendable, Hashable {
    case offline, reconnecting, loading
    case error(String)

    var tone: Tone {
        switch self {
        case .offline, .reconnecting: .warn
        case .loading: .done
        case .error: .fail
        }
    }
    var title: String {
        switch self {
        case .offline: "You are offline"
        case .reconnecting: "Reconnecting"
        case .loading: "Loading"
        case .error: "Something went wrong"
        }
    }
    var detail: String {
        switch self {
        case .offline: "Changes wait here until the connection is back."
        case .reconnecting: "Trying to reach your Core again."
        case .loading: "Getting the latest from your Core."
        case .error(let message): message
        }
    }
    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .loading: "hourglass"
        case .error: "exclamationmark.triangle"
        }
    }
}

/// Connection banner: offline, reconnecting, loading, error. A word and a symbol carry the state; the tint backs them up.
public struct ConnectionBanner: View {
    let state: ConnectionState
    let retry: (() -> Void)?
    @Environment(\.corePalette) private var palette

    public init(_ state: ConnectionState, retry: (() -> Void)? = nil) {
        self.state = state
        self.retry = retry
    }

    public var body: some View {
        let colours = palette.tone(state.tone)
        HStack(alignment: .top, spacing: Space.s3) {
            Group {
                if state == .loading || state == .reconnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state.symbol)
                }
            }
            .foregroundStyle(colours.ink)
            .frame(width: Space.s4, height: Space.s4)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(state.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(state.detail).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s2)
            if let retry, state != .loading {
                Button("Retry", action: retry).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2 + Space.s1 / 2)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .background(colours.fill, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.title). \(state.detail)")
        .accessibilityAddTraits(state == .loading || state == .reconnecting ? .updatesFrequently : [])
    }
}
