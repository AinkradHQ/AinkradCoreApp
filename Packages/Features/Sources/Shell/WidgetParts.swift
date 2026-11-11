import CoreUI
import SwiftUI

/// Widget ink on clear glass (Apple's widgets): pure white text, a softer white for the second line, a white well for
/// tiles, and vivid gauge colours. The glass is clear, so the sky decides the background; white with a soft shadow
/// (DeskWidget) reads on both skies.
enum WidgetInk {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.78)
    static let track = Color.white.opacity(0.24)
    static let well = Color.white.opacity(0.16)
    static let wellEdge = Color.white.opacity(0.3)
    static let blue = Color(red: 0.25, green: 0.6, blue: 1)
    static let green = Color(red: 0.2, green: 0.85, blue: 0.45)
    static let orange = Color(red: 1, green: 0.62, blue: 0.1)
}

/// Pieces the widgets share (`widgets.css`: header, section label, status square, meters, slot squares, load line).
/// Everything arrives with motion (counts roll up, bars grow, lines draw in); Reduce Motion keeps fades and colour only.
struct WidgetHead: View {
    let title: String
    var sub: String?
    /// The widget's icon, in a small glass tile that bounces when the widget arrives.
    var symbol: String?
    @Environment(\.corePalette) private var palette
    @State private var shown = false
    var body: some View {
        HStack(spacing: Space.s2) {
            if let symbol {
                Image(systemName: symbol).coreFont(size: MacTextSize.body, weight: .semibold)
                    .foregroundStyle(palette.primary)
                    .coreBounce(shown)
                    .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .coreGlass(radius: Radius.control, interactive: false)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.title - 1, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                if let sub {
                    Text(sub).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2).lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
        }
        .onAppear { shown = true }
    }
}

struct WidgetLabel: View {
    let text: String
    @Environment(\.corePalette) private var palette
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
            .padding(.top, Space.s2)
    }
}

/// Nothing to show: an icon that breathes and one calm line, never a bare sentence.
struct WidgetCalm: View {
    let text: String
    let symbol: String
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    init(_ text: String, symbol: String = "checkmark.circle") {
        self.text = text
        self.symbol = symbol
    }
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: symbol).coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(palette.primary.opacity(0.9))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduce)
                .accessibilityHidden(true)
            Text(text).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
        }
        .padding(.vertical, Space.s1)
    }
}

/// A number that rolls up from zero when it first shows and rolls to every new value after.
struct RollingNumber: View {
    let value: Double
    var format: (Double) -> String = { String(Int($0)) }
    var size: CGFloat
    var design: Font.Design = .default
    var ink: Color?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Double = 0
    var body: some View {
        Text(format(shown)).coreFont(size: size, weight: .semibold, design: design).monospacedDigit()
            .foregroundStyle(ink ?? palette.text)
            .contentTransition(.numericText(value: shown))
            .lineLimit(1).minimumScaleFactor(0.6)
            .onAppear { roll() }
            .onChange(of: value) { _, _ in roll() }
            .accessibilityLabel(format(value))
    }
    private func roll() {
        withAnimation(Motion.calm(Motion.out(Motion.reveal), reduce)) { shown = value }
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
            if let n = Double(value) {
                RollingNumber(value: n, size: small ? 28 : 38)
            } else {
                Text(value).coreFont(size: small ? 28 : 38, weight: .semibold).monospacedDigit().lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(caption).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The prototype's status mark: a small rounded square (never a circle). The word beside it says the same thing.
/// A live one breathes (opacity, so it stays under Reduce Motion too).
public struct StatusDot: View {
    let color: Color
    var live = false
    @State private var dim = false
    public init(color: Color, live: Bool = false) {
        self.color = color
        self.live = live
    }
    public var body: some View {
        coreShape(2).fill(color).frame(width: Space.s2, height: Space.s2)
            .opacity(live && dim ? 0.45 : 1)
            .coreLoop(live ? .easeInOut(duration: 1.1).repeatForever() : nil, value: dim)
            .onAppear { if live { dim = true } }
            .accessibilityHidden(true)
    }
}

/// A bar that fills from empty when it appears, with a soft glow along its leading edge.
struct Meter: View {
    let value: Double
    var tint: Color?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = 0.0
    var body: some View {
        coreShape(3).fill(palette.track).frame(height: 7)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    coreShape(3)
                        .fill(
                            LinearGradient(
                                colors: [(tint ?? palette.primary).opacity(0.6), tint ?? palette.primary],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(0, g.size.width * min(max(shown, 0), 1)))
                }
            }
            .onAppear {
                withAnimation(Motion.calm(Motion.out(Motion.reveal), reduce)) { shown = value }
            }
            .onChange(of: value) { _, v in withAnimation(Motion.out(Motion.tick)) { shown = v } }
            .accessibilityHidden(true)
    }
}

/// Slot squares that light up one after another; busy ones breathe.
struct SlotBar: View {
    let used: Int
    let slots: Int
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var lit = 0
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(slots, 0), id: \.self) { i in
                coreShape(2).fill(i < min(used, lit) ? palette.primary : palette.track).frame(
                    width: 14, height: Space.s2
                )
                .shadow(color: i < min(used, lit) ? palette.primary.opacity(0.5) : .clear, radius: 3)
            }
        }
        .onAppear {
            guard !reduce else {
                lit = used
                return
            }
            for i in 0...max(used, 0) {
                withAnimation(.easeOut(duration: 0.2).delay(Double(i) * 0.12)) { lit = i }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Host load as a line over a soft gradient area, newest on the right. It draws itself in when it appears.
struct Sparkline: View {
    let values: [Double]
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var drawn: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            let pts = points(g.size)
            ZStack {
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: last.x, y: g.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [palette.primary.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                )
                .mask(alignment: .leading) { Rectangle().frame(width: g.size.width * drawn) }
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .trim(from: 0, to: drawn)
                .stroke(palette.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .shadow(color: palette.primary.opacity(0.5), radius: 3)
            }
        }
        .onAppear { withAnimation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 1.2)) { drawn = 1 } }
        .accessibilityHidden(true)
    }
    private func points(_ size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        return values.enumerated().map { i, v in
            CGPoint(
                x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                y: size.height * (1 - CGFloat(min(max(v, 0), 1))))
        }
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
                    Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                        .lineLimit(compact ? 1 : 3).multilineTextAlignment(.leading)
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? WidgetInk.wellEdge : WidgetInk.well, in: coreShape(Radius.row))
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
    }
}
