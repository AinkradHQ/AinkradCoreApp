import CoreUI
import SwiftUI

/// The small moving parts of Settings, Updates (mockup `Designs/core/0-10/review/updates`). Motion values are the
/// mockup's: 320 ms fade and 4 pt rise when a value changes, 1.6 s link pulse, 500 ms check draw, 70 ms stagger for the
/// done pop. Reduce Motion keeps every progress cue: bars still fill, pulses become a 2 s opacity breath, the dropped link
/// stays a still dashed line with its counter, and value changes are 200 ms fades.
enum UpdMotion {
    static func swap(_ reduce: Bool) -> Animation { reduce ? .easeOut(duration: 0.2) : Motion.out(0.32) }
    static let pulse: Double = 1.6
    static let stagger: Double = 0.07
}

extension EnvironmentValues {
    /// Reduce Motion for this page: the system's, or the demo walk's stand-in (`UpdatesModel.debugReduceMotion`).
    @Entry var updReduce = false
}

extension View {
    /// The content swaps with a fade and a 4 pt rise whenever `key` changes (Reduce Motion: a 200 ms fade).
    func updSwap<K: Hashable>(_ key: K) -> some View { modifier(UpdSwap(key: key)) }
}

private struct UpdSwap<K: Hashable>: ViewModifier {
    let key: K
    @Environment(\.updReduce) private var reduce
    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content.id(key)
                .transition(
                    .asymmetric(
                        insertion: reduce ? .opacity : .opacity.combined(with: .offset(y: 4)),
                        removal: .opacity))
        }
        .animation(UpdMotion.swap(reduce), value: key)
    }
}

/// "0.10.2 → 0.10.3": the old version, an arrow, the new one in the accent ink.
struct UpdVersions: View {
    let from: String
    let to: String?
    var size: CGFloat = MacTextSize.meta
    var weight: Font.Weight = .regular
    @Environment(\.coreAccent) private var accent

    var body: some View {
        HStack(spacing: size > 14 ? Space.s2 : Space.s1) {
            Text(from)
            if let to, to != from {
                Image(systemName: "arrow.right").coreFont(size: size * 0.6, weight: .semibold)
                    .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                Text(to).foregroundStyle(GlassInk.accentInk(accent)).fontWeight(.semibold)
            }
        }
        .coreFont(size: size, weight: weight)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(to.map { $0 == from ? from : "\(from) to \($0)" } ?? from)
    }
}

/// One rounded bar: the track and a fill that glides to `value`. `waiting` slides a short segment instead (the Core is
/// restarting, nothing to count); under Reduce Motion that is the whole bar breathing.
struct UpdBar: View {
    enum Look { case accent, done, fail }
    let value: Double
    var look = Look.accent
    var height: CGFloat = 6
    var waiting = false
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @Environment(\.updReduce) private var reduce

    var body: some View {
        let fill: Color =
            switch look {
            case .accent: GlassInk.accent(accent)
            case .done: GlassInk.accentInk(accent)
            case .fail: palette.error
            }
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                coreShape(height / 2).fill(palette.track)
                if waiting {
                    if reduce {
                        coreShape(height / 2).fill(fill).modifier(UpdBreath(reduce: true))
                    } else {
                        TimelineView(.animation) { tl in
                            let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                            coreShape(height / 2).fill(fill).frame(width: geo.size.width * 0.3)
                                .offset(x: (geo.size.width * 1.3) * p - geo.size.width * 0.3)  // grid: ok motion
                        }
                        .clipShape(coreShape(height / 2))
                    }
                } else {
                    coreShape(height / 2).fill(fill).frame(width: geo.size.width * min(1, max(0, value)))
                        .animation(.linear(duration: 0.3), value: value)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(waiting ? "Waiting" : value.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// The running step's icon breathes (1.6 s, opacity 1 → 0.4); Reduce Motion: a slower 2 s breath, no other motion.
struct UpdBreath: ViewModifier {
    let reduce: Bool
    @State private var low = false
    func body(content: Content) -> some View {
        content.opacity(low ? 0.4 : 1)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: (reduce ? 2 : UpdMotion.pulse) / 2).repeatForever(autoreverses: true)
                ) {
                    low = true
                }
            }
    }
}

/// The success check, drawn in 500 ms (after 120 ms) when it first shows; Reduce Motion: it fades in.
struct UpdDrawnCheck: View {
    var size: CGFloat = 24
    @State private var drawn: CGFloat = 0
    @Environment(\.updReduce) private var reduce

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 5, y: 12.5))
            p.addLine(to: CGPoint(x: 9.5, y: 17))
            p.addLine(to: CGPoint(x: 19, y: 7))
        }
        .trim(from: 0, to: reduce ? 1 : drawn)
        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 24, height: 24)
        .scaleEffect(size / 24)
        .frame(width: size, height: size)
        .opacity(reduce ? drawn : 1)
        .onAppear {
            withAnimation(reduce ? .easeOut(duration: 0.2) : Motion.out(0.5).delay(0.12)) { drawn = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// A large tile for the map and the card: the glyph on a quiet well, on a soft accent (or state) tint when it is the
/// subject of what is happening.
struct UpdTile<Glyph: View>: View {
    let size: CGFloat
    let tint: Color?
    @ViewBuilder let glyph: Glyph

    var body: some View {
        glyph.frame(width: size, height: size)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .background(tint?.opacity(0.22) ?? .clear, in: coreShape(Radius.cardMac))
            .animation(Motion.out(Motion.ui), value: tint == nil)
            .accessibilityHidden(true)
    }
}

/// A one-shot 1.06 pop of a map tile when `trigger` changes, `delay` after it (the done wave: 70 ms apart). None under
/// Reduce Motion.
struct UpdPop<T: Equatable>: ViewModifier {
    let trigger: T
    let delay: Double
    @State private var up = false
    @Environment(\.updReduce) private var reduce
    func body(content: Content) -> some View {
        content.scaleEffect(up ? 1.06 : 1)
            .onChange(of: trigger) { _, _ in
                guard !reduce else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    withAnimation(Motion.out(0.17)) { up = true }
                    try? await Task.sleep(for: .seconds(0.17))
                    withAnimation(Motion.out(0.25)) { up = false }
                }
            }
    }
}

/// The line between two map tiles. `flow`: data moves (a 28 pt blip travels the line every 1.6 s, `reverse` toward the
/// Mac for a download). `gap`: the connection dropped, two dashed halves pull 8 pt apart under "Reconnecting · n s".
/// Reduce Motion: a flowing line is plain accent, a dropped one stays dashed and still, the counter stays.
struct UpdLink: View {
    var flow = false
    var reverse = false
    var gap = false
    var label: String?
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @Environment(\.updReduce) private var reduce

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let half = max(0, w / 2 - Space.s2)
            let line = flow ? (reduce ? GlassInk.accent(accent) : GlassInk.accent(accent).opacity(0.55)) : palette.track
            ZStack(alignment: .leading) {
                segment(half, line).offset(x: Space.s2 - (gap && !reduce ? Space.s2 : 0))  // grid: ok motion
                segment(half, line).offset(x: w / 2 + (gap && !reduce ? Space.s2 : 0))  // grid: ok motion
                if flow && !reduce && !gap {
                    TimelineView(.animation) { tl in
                        let raw =
                            tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: UpdMotion.pulse)
                            / UpdMotion.pulse
                        let p = reverse ? 1 - raw : raw
                        coreShape(1).fill(GlassInk.accentInk(accent)).frame(width: 28, height: 2)
                            .opacity(min(1, min(raw, 1 - raw) / 0.15))
                            .offset(x: Space.s2 + (w - 44) * p)  // grid: ok motion
                    }
                }
            }
            .frame(height: 2)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let label {
                    Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                        .frame(maxWidth: .infinity).transition(.opacity)
                }
            }
            .animation(Motion.out(Motion.move), value: gap)
            .animation(Motion.out(Motion.ui), value: label == nil)
        }
        .accessibilityElement()
        .accessibilityLabel(label ?? (flow ? "Updating" : "Connected"))
    }

    @ViewBuilder private func segment(_ width: CGFloat, _ colour: Color) -> some View {
        if gap {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1))
                p.addLine(to: CGPoint(x: width, y: 1))
            }
            .stroke(GlassInk.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .frame(width: width, height: 2)
        } else {
            coreShape(1).fill(colour).frame(width: width, height: 2)
                .animation(Motion.out(Motion.ui), value: flow)
        }
    }
}

/// A small fact under the ready card: an icon and a line on a quiet well.
struct UpdFact: View {
    let symbol: String
    let text: String
    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).coreFont(size: MacTextSize.meta, weight: .medium)
        }
        .labelStyle(.titleAndIcon)
        .coreFont(size: MacTextSize.meta + 1)
        .foregroundStyle(GlassInk.secondary)
        .padding(.horizontal, Space.s2)
        .frame(minHeight: Space.s6)
        .background(GlassInk.well, in: coreShape(Radius.chip))
    }
}
