import CoreUI
import SwiftUI

/// The picture at the top of first run: this Mac, the link, and the Core, telling the step as it goes. You (name),
/// the Mac looking for its Core (address), a key travelling to the Core (code), the two joined (paired). Travel
/// stops under Reduce Motion; the symbols still change.
struct FirstRunHero: View {
    enum Scene: Equatable { case you, find, key, checking, paired }
    let scene: Scene
    /// The name as it is typed: it fills the "You" tile's label live.
    var name = ""
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Top-aligned with the link as tall as a tile, so the line runs through the middle of the icons.
        HStack(alignment: .top, spacing: Space.s3) {
            tile(left.symbol, left.label, ink: palette.text)
            TimelineView(.animation(paused: reduceMotion || scene == .you)) { context in
                link(t: context.date.timeIntervalSinceReferenceDate)
            }
            .frame(height: MacSize.controlLg * 1.6)
            .opacity(scene == .you ? 0.35 : 1)
            tile(right.symbol, right.label, ink: scene == .paired ? palette.tone(.run).ink : palette.primary)
                .corePulse(scene == .find || scene == .checking)
        }
        .coreBounce(scene)
        .animation(Motion.out(Motion.ui), value: scene)
        .accessibilityHidden(true)
    }

    private var left: (symbol: String, label: String) {
        scene == .you ? ("person.crop.circle", name.isEmpty ? "You" : name) : ("laptopcomputer", "This Mac")
    }

    private var right: (symbol: String, label: String) {
        switch scene {
        case .you: ("laptopcomputer", "This Mac")
        case .find: ("server.rack", "Your Core")
        case .key, .checking: ("lock.shield", "Your Core")
        case .paired: ("checkmark.shield", "Paired")
        }
    }

    private func tile(_ symbol: String, _ label: String, ink: Color) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).font(.system(size: MacTextSize.large * 1.5, weight: .medium))
                .foregroundStyle(ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: MacSize.controlLg * 2, height: MacSize.controlLg * 1.6)
                .coreGlass(radius: Radius.control, interactive: false)
            Text(label).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .contentTransition(.opacity)
        }
    }

    /// Paired: one solid line. Otherwise a dashed line with packets running from the Mac to the Core; on the key
    /// step the lead packet is a key.
    private func link(t: TimeInterval) -> some View {
        Canvas { ctx, size in
            let y = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            if scene == .paired {
                ctx.stroke(line, with: .color(palette.tone(.run).ink), lineWidth: 3)
                return
            }
            ctx.stroke(line, with: .color(palette.text2.opacity(0.35)), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
            guard scene != .you else { return }
            let speed = scene == .checking ? 1.1 : 0.5
            for i in 0..<3 {
                let phase =
                    reduceMotion ? Double(i + 1) / 4 : (t * speed + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let x = size.width * phase
                let a = sin(phase * .pi)
                if scene == .key && i == 0, let key = ctx.resolveSymbol(id: 0) {
                    ctx.opacity = a
                    ctx.draw(key, at: CGPoint(x: x, y: y))
                    ctx.opacity = 1
                } else {
                    ctx.fill(
                        Path(roundedRect: CGRect(x: x - 3, y: y - 3, width: 6, height: 6), cornerRadius: 2),
                        with: .color(palette.primary.opacity(a)))
                }
            }
        } symbols: {
            Image(systemName: "key.fill").font(.system(size: MacTextSize.body)).foregroundStyle(palette.primary).tag(0)
        }
    }
}
