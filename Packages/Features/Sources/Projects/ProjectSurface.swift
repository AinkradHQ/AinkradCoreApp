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
    /// Eight swatches and a "More…" that opens the rest in a second row. A picked colour past the eighth takes the eighth's
    /// place, so the row stays one row of eight in every screen.
    var compact = true
    @State private var more = false
    private static let first = 8

    private var all: [ProjectColour] { ProjectColour.allCases }
    private var row: [ProjectColour] {
        var r = Array(all.prefix(Self.first))
        if !r.contains(selection) { r[Self.first - 1] = selection }
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                ForEach(row, id: \.self) { swatch($0) }
                if !more {
                    Button("More…") { withAnimation(Motion.out(Motion.ui)) { more = true } }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .help("Show the other colours")
                }
            }
            if more {
                HStack(spacing: Space.s2) {
                    ForEach(all.filter { !row.contains($0) }, id: \.self) { swatch($0) }
                }
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colour")
    }

    private func swatch(_ c: ProjectColour) -> some View {
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
