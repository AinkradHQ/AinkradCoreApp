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
            ForEach(kinds) { k in ConnTileButton(kind: k) { pick(k.id) } }
        }
    }
}
