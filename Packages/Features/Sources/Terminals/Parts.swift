import CoreUI
import SwiftUI

/// The prototype's `t-banner`: a small square mark, a bold line, a quiet line, an optional action and a busy bar. The mark
/// never carries the state alone: the title says it.
struct TermBanner: View {
    let tone: Tone
    let title: String
    let detail: String
    var busy = false
    var symbol: String?
    var actionTitle: String?
    var action: () -> Void = {}
    @Environment(\.corePalette) private var palette

    var body: some View {
        let colours = palette.tone(tone)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: symbol ?? Self.symbol(tone)).font(.system(size: MacTextSize.body, weight: .semibold))
                    .foregroundStyle(colours.ink).frame(width: Space.s4, height: Space.s4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.s2)
                if let actionTitle {
                    Button(actionTitle, action: action).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
            if busy { BusyBar().padding(.horizontal, Space.s3).padding(.bottom, Space.s2) }
        }
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .background(colours.fill, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(detail.isEmpty ? title : "\(title). \(detail)")
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

/// Filled squares for "n of capacity" (work slots, attachments). The number always sits beside it.
struct Slots: View {
    let used: Int
    let capacity: Int
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: Space.s1 / 2) {
            ForEach(0..<max(1, min(capacity, 16)), id: \.self) { i in
                coreShape(Space.s1 / 2).fill(i < used ? palette.primary : palette.track)
                    .frame(width: Space.s2, height: Space.s2)
            }
        }
        .accessibilityHidden(true)
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

/// A destructive action that is not the default: an outline, the fail ink, a word.
struct TermDangerStyle: ButtonStyle {
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: MacTextSize.body, weight: .medium))
            .foregroundStyle(palette.tone(.fail).ink)
            .padding(.horizontal, Space.s3)
            .frame(minHeight: MacSize.controlMd)
            .background(configuration.isPressed ? palette.tone(.fail).fill : .clear, in: coreShape(Radius.control))
            .overlay { coreShape(Radius.control).strokeBorder(palette.tone(.fail).ink.opacity(0.6), lineWidth: 1) }
            .opacity(enabled ? 1 : 0.45)
    }
}

/// A dialog over the shell: title, content, a rounded panel.
struct TermDialog<Content: View>: View {
    let title: String
    var width: CGFloat = Space.s8 * 17
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title).font(.system(size: MacTextSize.large, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content
        }
        .foregroundStyle(palette.text)
        .corePanel(radius: Radius.panel, padding: Space.s6)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
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
