import CoreUI
import SwiftUI

extension View {
    /// A gallery card's surface: a plain well inside the pane (which follows Settings › Appearance), with a hover tint.
    func projectCardSurface(radius: CGFloat = Radius.pane, lit: Bool = false) -> some View {
        // An inner surface of the pane (the pane carries the Look): a plain well, as Design's cards are.
        coreWell(radius: radius)
            .overlay { coreShape(radius).fill(GlassInk.wellHover).opacity(lit ? 1 : 0).allowsHitTesting(false) }
            .clipShape(coreShape(radius))
    }
}

/// A status dot: an 8 pt rounded square (the design has no circles), in the tone's colour.
struct StatusDot: View {
    let colour: Color
    var body: some View {
        coreShape(2).fill(colour).frame(width: Space.s2, height: Space.s2).accessibilityHidden(true)
    }
}

/// The project's colour: one small rounded square per accent, the picked one carries a tick.
struct ColourSwatches: View {
    @Binding var selection: ProjectColour
    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(ProjectColour.allCases, id: \.self) { c in
                Button {
                    selection = c
                } label: {
                    coreShape(Radius.chip).fill(c.fill).frame(width: Space.s6, height: Space.s6)
                        .overlay {
                            if selection == c {
                                Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold)
                                    .foregroundStyle(.white)
                            }
                        }
                        .contentShape(coreShape(Radius.chip))
                }
                .buttonStyle(.plain)
                .help(c.title)
                .accessibilityLabel(c.title)
                .accessibilityAddTraits(selection == c ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colour")
    }
}
