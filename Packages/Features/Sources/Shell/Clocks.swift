import CoreUI
import SwiftUI

// The two Home clocks (ui-fixes 2026-11-12, home-clocks.html). The analog face is the one round thing on Home besides
// the traffic lights; everything else stays a rounded rectangle. Blue hands, no orange.

/// The analog dial: a faint face, 60 ticks (every fifth longer and brighter), 12/3/6/9 on the Large size, blue hour and
/// minute hands, a lighter blue second hand and a small rounded-square centre.
/// Second hand: Smooth sweeps (one linear turn a minute, run by the animation system, not a redraw per frame); Ticking
/// jumps once a second; Off draws none. Reduce Motion, or Home hidden behind the workspace, turns Smooth into Ticking.
struct AnalogDial: View {
    var numbers = false
    @Environment(\.homeLive) private var live
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Bindable private var prefs = ClockPrefs.shared

    var body: some View {
        let hand = prefs.secondHand.shown(reduceMotion: reduce, live: live)
        // The minute tick re-syncs the smooth second hand (it drifts after sleep or a clock change) and keeps what
        // VoiceOver reads current.
        TimelineView(homeTicks(60, live: live)) { minute in
            GeometryReader { g in
                let r = min(g.size.width, g.size.height) / 2
                ZStack {
                    Canvas { c, size in face(c, size) }
                    TimelineView(homeTicks(1, live: live)) { ctx in
                        let a = ClockFace.angles(ctx.date, hand: hand)
                        ZStack {
                            HandLine(tail: 0.08, length: 0.42, width: 0.06 * r, ink: GlassInk.blue).rotationEffect(
                                .degrees(a.hour))
                            HandLine(tail: 0.08, length: 0.70, width: 0.04 * r, ink: GlassInk.blue).rotationEffect(
                                .degrees(a.minute))
                            if hand == .ticking {
                                secondHand(r).rotationEffect(.degrees(a.second))
                            }
                        }
                    }
                    if hand == .smooth {
                        SweepHand { secondHand(r) }.id(minute.date)
                    }
                    coreShape(0.03 * r).fill(GlassInk.blue).frame(width: 0.1 * r, height: 0.1 * r)
                }
                .frame(width: 2 * r, height: 2 * r)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel("Analog clock")
            .accessibilityValue(Text(minute.date, format: .dateTime.hour().minute()))
        }
    }

    private func secondHand(_ r: CGFloat) -> some View {
        HandLine(tail: 0.20, length: 0.80, width: 0.018 * r, ink: GlassInk.blueInk)
    }

    /// Face, ticks and (Large) the four numbers. Drawn once; only the hands move.
    private func face(_ c: GraphicsContext, _ size: CGSize) {
        let r = min(size.width, size.height) / 2
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let disc = Path(ellipseIn: CGRect(x: mid.x - r + 1, y: mid.y - r + 1, width: 2 * r - 2, height: 2 * r - 2))
        c.fill(disc, with: .color(GlassInk.well))
        c.stroke(disc, with: .color(GlassInk.wellHover), lineWidth: max(1, 0.015 * r))
        for i in 0..<60 {
            let a = Double(i) / 60 * 2 * .pi
            let major = i % 5 == 0
            var p = Path()
            p.move(to: point(mid, r * (major ? 0.90 : 0.88), a))
            p.addLine(to: point(mid, r * (major ? 0.78 : 0.83), a))
            c.stroke(
                p, with: .color(major ? GlassInk.secondary : GlassInk.secondary.opacity(0.5)),
                style: StrokeStyle(lineWidth: (major ? 0.03 : 0.016) * r, lineCap: .round))
        }
        guard numbers else { return }
        for h in [12, 3, 6, 9] {
            c.draw(
                Text("\(h)").font(.system(size: 0.18 * r, weight: .medium)).foregroundStyle(GlassInk.secondary),
                at: point(mid, r * 0.6, Double(h) / 12 * 2 * .pi))
        }
    }

    /// A point `distance` from the centre at `angle` (0 = 12 o'clock, clockwise).
    private func point(_ mid: CGPoint, _ distance: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: mid.x + distance * CGFloat(sin(angle)), y: mid.y - distance * CGFloat(cos(angle)))
    }
}

/// A hand pointing at 12 from the centre, `tail` past it; lengths are fractions of the radius. Round ends, as a watch's.
private struct HandLine: View {
    let tail: CGFloat
    let length: CGFloat
    let width: CGFloat
    let ink: Color
    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            let mid = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            Path { p in
                p.move(to: CGPoint(x: mid.x, y: mid.y + tail * r))
                p.addLine(to: CGPoint(x: mid.x, y: mid.y - length * r))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }
}

/// The smooth second hand: starts at the current second and turns once a minute, linear. The dial gives it a new identity
/// every minute, so it starts again from the real second.
private struct SweepHand<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var start = 0.0
    @State private var turn = 0.0
    var body: some View {
        content.rotationEffect(.degrees(start + turn))
            .onAppear {
                start = ClockFace.angles(.now, hand: .smooth).second
                turn = 0
                withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) { turn = 360 }
            }
    }
}

/// The analog clock widget. Small: the dial alone. Wide: the dial with the day, date and city beside it. Large: the
/// dial with the numbers, the day and "date · city" under it.
struct AnalogClockBody: View {
    let size: WidgetSize
    @Environment(\.homeLive) private var live

    var body: some View {
        switch size {
        case .s:
            AnalogDial().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .m:
            HStack(spacing: Space.s4) {
                AnalogDial()
                day { d in
                    VStack(alignment: .leading, spacing: 2) {
                        ClockLine(d, .dateTime.weekday(.wide), strong: true)
                        ClockLine(d, .dateTime.day().month(.wide))
                        Text(ClockFace.city(.current)).coreFont(size: MacTextSize.body).foregroundStyle(
                            GlassInk.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            VStack(spacing: Space.s3) {
                AnalogDial(numbers: true)
                day { d in
                    VStack(spacing: 2) {
                        ClockLine(d, .dateTime.weekday(.wide), strong: true)
                        Text("\(d.formatted(.dateTime.day().month(.wide))) · \(ClockFace.city(.current))")
                            .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func day<V: View>(@ViewBuilder _ content: @escaping (Date) -> V) -> some View {
        TimelineView(homeTicks(60, live: live)) { ctx in content(ctx.date) }
            .accessibilityElement(children: .combine)
    }
}

/// The day or date under a clock: the day in the headline weight, the date in secondary ink.
private struct ClockLine: View {
    let date: Date
    let format: Date.FormatStyle
    let strong: Bool
    init(_ date: Date, _ format: Date.FormatStyle, strong: Bool = false) {
        self.date = date
        self.format = format
        self.strong = strong
    }
    var body: some View {
        Text(date, format: format)
            .coreFont(size: strong ? MacTextSize.title : MacTextSize.body, weight: strong ? .semibold : .regular)
            .foregroundStyle(strong ? GlassInk.primary : GlassInk.secondary)
            .lineLimit(1)
    }
}

/// The digital clock widget. Small: the time and the day. Wide: the time, the day and the date. Tall: hours over
/// minutes, the day and date under them. Large: the time, the day and date, and home and UTC. Seconds (Settings →
/// Clocks) follow the minutes in a smaller, secondary size. Digits change in place; Reduce Motion swaps them without
/// the roll.
struct DigitalClockBody: View {
    let size: WidgetSize
    @Environment(\.homeLive) private var live
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Bindable private var prefs = ClockPrefs.shared

    var body: some View {
        TimelineView(homeTicks(1, live: live)) { ctx in
            let d = ctx.date
            switch size {
            case .s:
                VStack(alignment: .leading, spacing: Space.s1) {
                    time(d, 38)
                    ClockLine(d, .dateTime.weekday(.wide))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .t:
                VStack(alignment: .leading, spacing: 0) {
                    digits(ClockFace.time(d).hours, 62)
                    digits(ClockFace.time(d).minutes, 62)
                    if prefs.showsSeconds { digits(ClockFace.time(d).seconds, 28, ink: GlassInk.secondary) }
                    VStack(alignment: .leading, spacing: 2) {
                        ClockLine(d, .dateTime.weekday(.wide))
                        ClockLine(d, .dateTime.day().month(.wide))
                    }
                    .padding(.top, Space.s3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .l, .x:
                VStack(alignment: .leading, spacing: 0) {
                    time(d, 56)
                    date(d).padding(.top, Space.s2)
                    places(d).padding(.top, Space.s4)
                    Spacer(minLength: 0)
                }
                .padding(.top, Space.s1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .m:
                VStack(alignment: .leading, spacing: Space.s2) {
                    time(d, 44)
                    date(d)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Digital clock")
    }

    private func date(_ d: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ClockLine(d, .dateTime.weekday(.wide), strong: true)
            ClockLine(d, .dateTime.day().month(.wide))
        }
    }

    /// "10:09", with ":37" after it when seconds are on.
    private func time(_ d: Date, _ size: CGFloat) -> some View {
        let t = ClockFace.time(d)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            digits("\(t.hours):\(t.minutes)", size)
            if prefs.showsSeconds { digits(":\(t.seconds)", size * 0.45, ink: GlassInk.secondary) }
        }
    }

    private func digits(_ s: String, _ size: CGFloat, ink: Color = GlassInk.primary) -> some View {
        // Sized to the widget, as the dial's numbers are: the Text size setting would push 62 pt digits out of the
        // fixed Tall frame (two lines at 200 % alone are taller than it). The day and date lines still follow it.
        Text(s).font(.system(size: size, weight: .semibold)).monospacedDigit()
            .kerning(-0.03 * size)
            .foregroundStyle(ink)
            .lineLimit(1).minimumScaleFactor(0.6)
            .contentTransition(reduce ? .identity : .numericText())
            .animation(reduce ? nil : Motion.out(Motion.hover), value: s)
    }

    /// Home and UTC, one row each: name (and "home"), the time at the right.
    private func places(_ d: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ClockFace.places(home: .current), id: \.name) { p in
                let t = ClockFace.time(d, calendar: ClockFace.calendar(in: p.zone))
                HStack(spacing: Space.s2) {
                    Text(p.name).coreFont(size: MacTextSize.body, weight: .medium).foregroundStyle(GlassInk.primary)
                    if let n = p.note {
                        Text(n).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                    Spacer(minLength: Space.s2)
                    Text("\(t.hours):\(t.minutes)").coreFont(size: MacTextSize.body, weight: .semibold)
                        .monospacedDigit().foregroundStyle(GlassInk.primary)
                }
                .frame(minHeight: Space.s8)
            }
        }
    }
}

/// Settings → Clocks (home-clocks, "Reduce Motion"): one well per clock. The analog clock's second hand is Smooth,
/// Ticking or Off; the digital clock can show seconds.
struct ClockSettings: View {
    @Bindable private var prefs = ClockPrefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            well("Analog clock") {
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Second hand").coreFont(size: MacTextSize.body)
                        Text("Ticking replaces Smooth while Reduce Motion is on.").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary)
                    }
                    Spacer(minLength: Space.s3)
                    CoreSegmented(
                        "Second hand", segments: SecondHand.allCases.map { CoreSegment($0, $0.title) },
                        selection: $prefs.secondHand)
                }
            }
            well("Digital clock") {
                GlassToggleTile(
                    "Show seconds", sub: "Digits change in place. With Reduce Motion on they swap without a fade.",
                    symbol: "clock", onSymbol: "clock.fill", isOn: $prefs.showsSeconds, fill: true)
            }
        }
    }

    private func well<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
            content()
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell(radius: Radius.pane)
    }
}
