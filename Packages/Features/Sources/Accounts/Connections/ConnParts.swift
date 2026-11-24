import CoreUI
import SwiftUI

/// A service's logo as a template image in one ink: the primary ink, or the accent when `lit` (hover, connected).
/// A kind without a logo shows its letter.
struct ConnMark: View {
    let kind: String
    let size: CGFloat
    var lit = false
    @Environment(\.coreAccent) private var paneAccent
    var body: some View {
        let ink = lit ? GlassInk.accentInk(paneAccent) : GlassInk.primary
        Group {
            if ConnLook.logos.contains(kind) {
                Image("conn-\(kind)", bundle: .module).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Text(ConnLook.letter(kind)).coreFont(size: size * 0.8, weight: .bold)
            }
        }
        .foregroundStyle(ink)
        .animation(Motion.out(Motion.hover), value: lit)
        .accessibilityHidden(true)
    }
}

/// The logo tile: the mark on a quiet well. No brand colours.
struct ConnLogo: View {
    let kind: String
    var size: CGFloat = 44
    var lit = false
    var body: some View {
        coreShape(size >= 40 ? Radius.cardMac : Radius.control)
            .fill(GlassInk.well)
            .frame(width: size, height: size)
            .overlay { ConnMark(kind: kind, size: (size * 0.5).rounded(), lit: lit) }
            .accessibilityHidden(true)
    }
}

/// The Ainkrad emblem on a tile: the Core end of every wire.
struct ConnCoreTile: View {
    var size: CGFloat = 64
    var body: some View {
        coreShape(Radius.cardMac)
            .fill(GlassInk.well)
            .frame(width: size, height: size)
            .overlay {
                Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: size * 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// The five steps as a path: a bar and a word each. Done and current bars take the accent; the current word is the bold one.
struct ConnSteps: View {
    @Environment(\.coreAccent) private var paneAccent
    let at: ConnStep
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(ConnStep.allCases, id: \.rawValue) { s in
                VStack(spacing: Space.s2) {
                    coreShape(2)
                        .fill(s.rawValue <= at.rawValue ? GlassInk.accent(paneAccent) : GlassInk.track)
                        .frame(height: 3)
                    Text(s.label).coreFont(size: MacTextSize.meta, weight: s == at ? .semibold : .regular)
                        .foregroundStyle(s == at ? GlassInk.primary : GlassInk.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: at)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(at.rawValue) of 5: \(at.label)")
    }
}

/// Five small squares hopping from the service to Core. No pointer input; under Reduce Motion the first three rest lit.
struct ConnLink: View {
    @Environment(\.coreAccent) private var paneAccent
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { i in
                    let p = reduce ? 0 : max(0, sin((t * 3.9) - Double(i) * 0.6))
                    let lit = reduce ? i < 3 : p > 0.5
                    coreShape(2).fill(GlassInk.accent(paneAccent))
                        .frame(width: 6, height: 6)
                        .opacity(lit ? 1 : 0.28)
                }
            }
        }
        .accessibilityHidden(true)
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
    func connRise(index: Int) -> some View { modifier(ConnRise(index: index)) }
}
