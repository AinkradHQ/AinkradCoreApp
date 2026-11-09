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
                    ProgressView().controlSize(.small).frame(width: 32, height: 32).accessibilityHidden(true)
                } else {
                    ToneGlyph(symbol: state.symbol, ink: colours.ink, size: 32)
                }
            }
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(state.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(state.detail).font(.system(size: MacTextSize.body)).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            if let retry, state != .loading {
                Button("Retry", action: retry).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2 + Space.s1 / 2)
        .coreGlass(radius: Radius.cardMac, interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.title). \(state.detail)")
        .accessibilityAddTraits(state == .loading || state == .reconnecting ? .updatesFrequently : [])
    }
}
