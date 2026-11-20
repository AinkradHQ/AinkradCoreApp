import CoreUI
import SwiftUI

/// A service's logo: its letter on a rounded square in its own tint (the mockup's `c10-logo`).
struct ConnLogo: View {
    let kind: String
    var size: CGFloat = 44
    var body: some View {
        let hue = ConnLook.hue(kind)
        coreShape(size > 56 ? Radius.pane : Radius.cardMac)
            .fill(hue.opacity(0.26))
            .frame(width: size, height: size)
            .overlay {
                Text(ConnLook.letter(kind))
                    .coreFont(size: size > 56 ? 30 : MacTextSize.large, weight: .bold)
                    .foregroundStyle(hue)
            }
            .accessibilityHidden(true)
    }
}

/// The five steps as small rounded bars: done and current in the accent, the rest quiet.
struct ConnSteps: View {
    let at: ConnStep
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(ConnStep.allCases, id: \.rawValue) { s in
                coreShape(2)
                    .fill(s.rawValue <= at.rawValue ? GlassInk.blue : GlassInk.track)
                    .frame(width: s == at ? Space.s5 : Space.s2, height: Space.s1 + 2)
            }
        }
        .animation(reduce ? nil : .smooth(duration: 0.3), value: at)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(at.rawValue) of 5")
    }
}

/// Five small squares hopping from the service to Core. No pointer input; under Reduce Motion the first three rest lit.
struct ConnLink: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: Space.s2 - 2) {
                ForEach(0..<5, id: \.self) { i in
                    let p = reduce ? 0 : max(0, sin((t * 3.9) - Double(i) * 0.6))
                    let lit = reduce ? i < 3 : p > 0.5
                    coreShape(3).fill(GlassInk.blue)
                        .frame(width: 9, height: 9)
                        .opacity(lit ? 1 : 0.28)
                        .offset(y: reduce ? 0 : -3 * p)  // grid: ok motion only, a hop
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A service as a button: logo, name, one line. The tiles of the empty page and of step 1.
struct ConnTileButton: View {
    let kind: ConnKind
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s2) {
                ConnLogo(kind: kind.id)
                Text(kind.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text(kind.say).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.s2).padding(.top, Space.s4).padding(.bottom, Space.s3)
            .frame(maxWidth: .infinity)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac, hoverFill: true))
        .accessibilityLabel("\(kind.name). \(kind.say)")
    }
}

/// The five tiles in one row.
struct ConnTiles: View {
    let kinds: [ConnKind]
    let pick: (String) -> Void
    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            ForEach(Array(kinds.enumerated()), id: \.element.id) { i, k in
                ConnTileButton(kind: k) { pick(k.id) }.connRise(index: i)
            }
        }
    }
}

/// The motion maths of the Connections tiles, apart from the views so Reduce Motion can be tested.
enum ConnMotion {
    static let floatPeriod = 5.5  // the mockup's k-float: 5.5s, ease-in-out, forever
    static let floatLift = 4.0  // px up at the peak
    static let heroPhase = -2.7  // the second hero tile starts half a loop later
    static let riseStep = 0.045  // Kit.stagger: 45ms per tile
    static let riseDistance = 8.0

    /// Vertical offset at time `t` (negative is up): 0 -> lift -> 0 as a smooth sine. Reduce Motion rests at 0.
    static func floatOffset(at t: Double, phase: Double = 0, reduce: Bool) -> Double {
        if reduce { return 0 }
        let x = (t - phase).truncatingRemainder(dividingBy: floatPeriod) / floatPeriod
        return -floatLift * (1 - cos(2 * .pi * x)) / 2
    }
}

/// A tile floating up and down. Time-driven, no pointer input; a still tile under Reduce Motion.
private struct ConnFloat: ViewModifier {
    let phase: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        if reduce {
            content
        } else {
            TimelineView(.animation) { ctx in
                content.offset(
                    y: ConnMotion.floatOffset(at: ctx.date.timeIntervalSinceReferenceDate, phase: phase, reduce: false))
            }
        }
    }
}

/// A tile rising in once, 45ms after the one before (Kit.stagger). Already in place under Reduce Motion.
private struct ConnRise: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(reduce || shown ? 1 : 0)
            .offset(y: reduce || shown ? 0 : ConnMotion.riseDistance)
            .onAppear {
                guard !reduce else { return }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.5).delay(Double(index) * ConnMotion.riseStep))
                {
                    shown = true
                }
            }
    }
}

extension View {
    func connFloat(phase: Double = 0) -> some View { modifier(ConnFloat(phase: phase)) }
    func connRise(index: Int) -> some View { modifier(ConnRise(index: index)) }
}
