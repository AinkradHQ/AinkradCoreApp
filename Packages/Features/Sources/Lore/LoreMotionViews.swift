// LoreMotionViews — the space's small shared motions: a sidebar's sections arriving just after the sidebar, and the
// lift a card gives under the pointer. Reduce Motion: sections fade in together, cards only light.
import CoreUI
import SwiftUI

extension View {
    /// A section of a sidebar that just opened: it fades up a few points, `step` beats after the sidebar.
    func loreArrive(_ step: Int) -> some View { modifier(LoreArrive(step: step)) }

    /// A card under the pointer rises a hair (the fill lights it already).
    func loreLift(_ on: Bool) -> some View { modifier(LoreLift(on: on)) }
}

private struct LoreArrive: ViewModifier {
    let step: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : coreMove(reduce, Space.s1))
            .onAppear {
                // At most three beats, so the whole sidebar settles inside 300 ms; Reduce Motion: one fade.
                let delay = reduce ? 0 : Double(min(step, 2)) * Motion.stagger
                withAnimation(Motion.calm(Motion.out(Motion.ui), reduce).delay(delay)) { shown = true }
            }
    }
}

private struct LoreLift: ViewModifier {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .scaleEffect(on && !reduce ? 1.012 : 1)
            .animation(Motion.out(Motion.hover), value: on)
    }
}
