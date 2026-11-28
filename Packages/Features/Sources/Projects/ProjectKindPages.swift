import CoreUI
import SwiftUI

/// A doc as a large tile: a plain well that lights on hover, lifts 3 pt (not with Reduce Motion) and sinks a little on press.
struct DocTile: View {
    let title: String
    let symbol: String
    let group: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Image(systemName: symbol).coreFont(size: MacTextSize.large).foregroundStyle(GlassInk.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Text(group).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: 0)
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 3, alignment: .topLeading)
            .coreCard(hovering ? GlassInk.wellHover : GlassInk.well, radius: Radius.cardMac)
            .offset(y: hovering && !reduce ? -3 : 0)
            .animation(Motion.out(Motion.hover), value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .help("Open “\(title)”")
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(Motion.out(Motion.press), value: configuration.isPressed)
    }
}
