import CoreUI
import SwiftUI

/// A CoreUI notice with the optional action button and a busy bar under it. The title says the state; the tone backs it up.
struct TermBanner: View {
    let tone: Tone
    let title: String
    let detail: String
    var busy = false
    var symbol: String?
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            CoreNotice(symbol: symbol ?? Self.symbol(tone), title: title, text: detail, tone: tone) {
                if let actionTitle {
                    Button(actionTitle, action: action).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
            if busy { BusyBar().padding(.horizontal, Space.s3).padding(.vertical, Space.s2) }
        }
        .accessibilityAddTraits(busy ? .updatesFrequently : [])
    }

    static func symbol(_ tone: Tone) -> String {
        switch tone {
        case .run: "checkmark.circle"
        case .done: "info.circle"
        case .warn: "exclamationmark.triangle"
        case .fail: "xmark.octagon"
        case .queue: "circle.dashed"
        }
    }
}

/// A moving bar for "working, length unknown". Reduce Motion: the bar rests in the middle.
struct BusyBar: View {
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

/// The card over a terminal that is not showing a screen: a title, what it means, the actions.
struct TermCard: View {
    let title: String
    let text: String
    var note: String?
    var actions: [(title: String, primary: Bool, run: () -> Void)]
    @Environment(\.corePalette) private var palette
    @FocusState private var focus: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(text).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            if let note { Text(note).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2) }
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                    Button(a.title, action: a.run)
                        .buttonStyle(CoreButtonStyle(a.primary ? .prominent : .secondary))
                        .focused($focus, equals: i)
                }
            }
            .padding(.top, Space.s2)
        }
        .font(.system(size: MacTextSize.body))
        .padding(Space.s4)
        .frame(maxWidth: Space.s8 * 11)
        .corePanel(radius: Radius.panel, padding: 0)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .onAppear { focus = actions.firstIndex { $0.primary } ?? 0 }
    }
}

/// A bar for a value against a maximum, with an optional limit mark.
struct Meter: View {
    let value: Double
    let max: Double
    var limit: Double?
    var warn = false
    @Environment(\.corePalette) private var palette
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                coreShape(Space.s1 / 2).fill(palette.track)
                coreShape(Space.s1 / 2).fill(warn ? palette.warning : palette.primary)
                    .frame(width: geo.size.width * Swift.min(1, Swift.max(0, value / Swift.max(max, 0.001))))
                if let limit {
                    Rectangle().fill(palette.text.opacity(0.8)).frame(width: 2)
                        .offset(x: geo.size.width * Swift.min(1, limit / Swift.max(max, 0.001)))  // grid: ok limit mark
                }
            }
        }
        .frame(height: Space.s2)
        .accessibilityHidden(true)
    }
}

/// The inline outcome of a Touch ID that did not elevate.
struct ElevationBanner: View {
    let notice: ElevationNotice
    var body: some View {
        TermBanner(tone: notice.tone, title: notice.title, detail: notice.detail, symbol: notice.symbol)
            .accessibilityIdentifier("stepup-notice")
    }
}

func ago(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "just now" }
    let m = Int(now.timeIntervalSince(date) / 60)
    if m < 1 { return "just now" }
    if m < 60 { return "\(m) min" }
    if m < 1440 { return "\(m / 60) h" }
    return "\(m / 1440) d"
}
