import CoreUI
import SwiftUI

/// The failure as a picture: this Mac on the left, the Core on the right, and the link between them stopping at the
/// point that failed. Packets travel from the Mac and fade at the break; Reduce Motion keeps them still and pulses the
/// break instead (a change of opacity, not travel).
struct FailureDiagram: View {
    let failure: Failure
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tone = palette.tone(failure.tone)
        // Top-aligned with the link as tall as a tile, so the line runs through the middle of the icons.
        HStack(alignment: .top, spacing: Space.s3) {
            node("laptopcomputer", "This Mac", ink: palette.text, fill: palette.glassCard)
            TimelineView(.animation(paused: reduceMotion)) { context in
                link(t: context.date.timeIntervalSinceReferenceDate, ink: tone.ink)
            }
            .frame(height: MacSize.controlLg * 1.6)
            node(failure.diagramEnd, failure.diagramLabel, ink: tone.ink, fill: tone.fill)
                .symbolEffect(.pulse, options: .repeating)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This Mac to \(failure.diagramLabel): stopped")
    }

    private func node(_ symbol: String, _ label: String, ink: Color, fill: Color) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).font(.system(size: MacTextSize.large * 1.5, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: MacSize.controlLg * 2, height: MacSize.controlLg * 1.6)
                .background(fill, in: coreShape(Radius.control))
            Text(label).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
        }
    }

    /// Dots run from the Mac to the break at 70 % of the line, fading as they reach it; the break is a short bar.
    private func link(t: TimeInterval, ink: Color) -> some View {
        Canvas { ctx, size in
            let y = size.height / 2
            let stop = size.width * 0.7
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: stop, y: y))
            ctx.stroke(line, with: .color(palette.text2.opacity(0.35)), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
            let pulse = reduceMotion ? 1 : 0.55 + 0.45 * abs(sin(t * 2))
            ctx.fill(
                Path(roundedRect: CGRect(x: stop, y: y - 9, width: 4, height: 18), cornerRadius: 2),
                with: .color(ink.opacity(pulse)))
            for i in 0..<3 {
                let phase = reduceMotion ? Double(i) / 3 : (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let x = stop * phase
                ctx.fill(
                    Path(roundedRect: CGRect(x: x - 3, y: y - 3, width: 6, height: 6), cornerRadius: 2),
                    with: .color(palette.text.opacity(1 - phase * 0.8)))
            }
        }
    }
}

extension Failure {
    /// What the Mac was trying to reach, drawn at the end of the link.
    var diagramEnd: String {
        switch kind {
        case .identityMismatch, .unproven, .sasMismatch: "exclamationmark.shield"
        case .offline: "wifi.slash"
        case .clockSkew: "clock.badge.exclamationmark"
        case .rejected, .revokedHere: "xmark.shield"
        default: "server.rack"
        }
    }

    var diagramLabel: String {
        switch kind {
        case .identityMismatch: "A different Core"
        case .offline: "Core not answering"
        default: "Your Core"
        }
    }
}
