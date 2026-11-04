import CoreUI
import SwiftUI

/// Pieces the widgets share (`widgets.css`: header, section label, status square, meters, slot squares, load line).
struct WidgetHead: View {
    let title: String
    var sub: String?
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: MacTextSize.title - 1, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let sub {
                Text(sub).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2).lineLimit(1)
            }
        }
    }
}

struct WidgetLabel: View {
    let text: String
    @Environment(\.corePalette) private var palette
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
            .padding(.top, Space.s2)
    }
}

struct WidgetCalm: View {
    let text: String
    @Environment(\.corePalette) private var palette
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2).padding(.vertical, Space.s1)
    }
}

/// A big figure and the word under it.
struct WidgetBig: View {
    let value: String
    let caption: String
    var small = false
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: small ? 28 : 38, weight: .semibold)).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The prototype's status mark: a small rounded square (never a circle). The word beside it says the same thing.
struct StatusDot: View {
    let color: Color
    var body: some View {
        coreShape(2).fill(color).frame(width: Space.s2, height: Space.s2).accessibilityHidden(true)
    }
}

struct Meter: View {
    let value: Double
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        coreShape(2).fill(palette.track).frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    coreShape(2).fill(palette.primary).frame(width: g.size.width * min(max(value, 0), 1))
                }
            }
            .animation(reduce ? .easeOut(duration: 0.2) : Motion.out(Motion.tick), value: value)
            .accessibilityHidden(true)
    }
}

struct SlotBar: View {
    let used: Int
    let slots: Int
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(slots, 0), id: \.self) { i in
                coreShape(2).fill(i < used ? palette.primary : palette.track).frame(width: 14, height: Space.s2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Host load as a thin line, newest on the right.
struct Sparkline: View {
    let values: [Double]
    @Environment(\.corePalette) private var palette
    var body: some View {
        GeometryReader { g in
            Path { p in
                guard values.count > 1 else { return }
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(
                        x: g.size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: g.size.height * (1 - CGFloat(min(max(v, 0), 1))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(palette.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// `.wd-card`: a tappable neutral card (the Needs you row).
struct WidgetCard: View {
    let title: String
    let sub: String
    var compact = false
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                StatusDot(color: palette.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                        .lineLimit(compact ? 1 : 3).multilineTextAlignment(.leading)
                    Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? palette.uDim : palette.glassCard, in: coreShape(Radius.row))
            .overlay { coreShape(Radius.row).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
    }
}
